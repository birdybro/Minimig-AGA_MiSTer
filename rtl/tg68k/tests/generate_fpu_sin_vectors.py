#!/usr/bin/env python3

from decimal import Decimal, localcontext, ROUND_HALF_EVEN
from fractions import Fraction
from functools import lru_cache
import random

from fpu_exact_reference import (
    encode_extended,
    extended_bits_value,
    mode_name,
    power_of_two,
    precision_name,
    round_binary_precision,
)
from generate_fpu_atan_vectors import pi_decimal


SEED = 0x6888100E


def rounded_extended(value: Decimal) -> int:
    return round_binary_precision(Fraction(value), 64, 0)[0]


def source_values() -> list[int]:
    magnitudes = [
        encode_extended(0, exponent, significand)
        for exponent, significand in (
            (-16383, 1 << 63),
            (-100, 1 << 63),
            (-41, 1 << 63),
            (-40, 1 << 63),
            (-39, 1 << 63),
            (-20, 5 << 61),
            (-2, 1 << 63),
            (-1, 1 << 63),
            (-1, 3 << 62),
            (0, 1 << 62),
            (0, 1 << 63),
            (1, 1 << 63),
            (2, 15 << 59),
            (4, 15 << 59),
            (10, (1 << 64) - 1),
            (30, (1 << 63) | 0x123456789ABCDEF),
            (60, (1 << 63) | 0x23456789ABCDEF0),
            (66, (1 << 63) | 0x3456789ABCDEF01),
        )
    ]
    with localcontext() as context:
        context.prec = 450
        pi = pi_decimal()
        for multiplier in (
                Decimal(1) / 4, Decimal(1) / 2, Decimal(1),
                Decimal(3) / 2, Decimal(2), Decimal(15)):
            center = rounded_extended(pi * multiplier)
            magnitudes.extend((center - 1, center, center + 1))
    rng = random.Random(SEED)
    while len(magnitudes) < 48:
        exponent = rng.randrange(-39, 67)
        significand = (1 << 63) | rng.getrandbits(63)
        magnitudes.append(encode_extended(0, exponent, significand))
    values = []
    for magnitude in magnitudes[:48]:
        values.append(magnitude)
        values.append(magnitude | (1 << 79))
    return values


def sine_cosine_decimal(angle: Decimal, cosine: bool) -> Decimal:
    pi = pi_decimal()
    half_pi = pi / 2
    quadrant = int((angle / half_pi).to_integral_value(
        rounding=ROUND_HALF_EVEN))
    reduced = angle - Decimal(quadrant) * half_pi
    square = reduced * reduced
    if (quadrant & 1) != 0:
        term = Decimal(1)
        result = term
        index = 1
        while True:
            term *= -square / Decimal((2 * index - 1) * (2 * index))
            previous = result
            result += term
            if result == previous:
                break
            index += 1
        if (quadrant & 3) == 3:
            result = -result
    else:
        term = reduced
        result = term
        index = 1
        while True:
            term *= -square / Decimal((2 * index) * (2 * index + 1))
            previous = result
            result += term
            if result == previous:
                break
            index += 1
        if (quadrant & 3) == 2:
            result = -result
    if cosine:
        return sine_cosine_decimal(angle + half_pi, False)
    return result


@lru_cache(maxsize=None)
def high_precision_trig(source: int, cosine: bool,
                        tangent: bool = False) -> Fraction:
    source_value = extended_bits_value(source)
    sign = -1 if source_value < 0 else 1
    magnitude = abs(source_value)
    if magnitude < power_of_two(-100):
        square = magnitude * magnitude
        if tangent:
            result = magnitude + magnitude * square / 3 + (
                2 * magnitude * square * square / 15)
            return result * sign
        if cosine:
            return 1 - square / 2 + square * square / 24
        result = magnitude - magnitude * square / 6 + (
            magnitude * square * square / 120)
        return result * sign
    with localcontext() as context:
        context.prec = 450
        source_decimal = Decimal(source_value.numerator) / Decimal(
            source_value.denominator)
        if tangent:
            sine = sine_cosine_decimal(source_decimal, False)
            cosine_result = sine_cosine_decimal(source_decimal, True)
            return Fraction(sine / cosine_result)
        return Fraction(sine_cosine_decimal(source_decimal, cosine))


def reference_trig(source: int, precision_bits: int, mode: int,
                   cosine: bool, tangent: bool = False) -> tuple[int, int, int]:
    result, condition_codes, status = round_binary_precision(
        high_precision_trig(source, cosine, tangent), precision_bits, mode)
    return result, condition_codes, status | 0x02


def make_vectors(cosine: bool, tangent: bool = False):
    vectors = []
    for source in source_values():
        for precision_index in range(3):
            precision, precision_bits = precision_name(precision_index)
            for mode in range(4):
                result, condition_codes, status = reference_trig(
                    source, precision_bits, mode, cosine, tangent)
                vectors.append((source, precision, mode_name(mode), result,
                                condition_codes, status))
    return vectors


def emit_testbench(cosine: bool, tangent: bool = False) -> None:
    operation = "tan" if tangent else "cos" if cosine else "sin"
    operation_upper = operation.upper()
    cosine_literal = "'1'" if cosine else "'0'"
    tangent_literal = "'1'" if tangent else "'0'"
    vectors = make_vectors(cosine, tangent)
    print(f"""library ieee;
use ieee.std_logic_1164.all;
use std.env.all;
use work.TG68K_FPU_Pack.all;

entity tb_tg68k_fpu_{operation}_differential is
end entity;

architecture test of tb_tg68k_fpu_{operation}_differential is
    constant CLK_PERIOD : time := 10 ns;
    type vector_t is record
        source_value : fpu_extended_t;
        precision_value : fpu_rounding_precision_t;
        mode_value : fpu_rounding_mode_t;
        expected_result : fpu_extended_t;
        expected_cc : std_logic_vector(3 downto 0);
        expected_status : std_logic_vector(7 downto 0);
    end record;
    type vector_array_t is array (natural range <>) of vector_t;
    constant vectors : vector_array_t := (""")
    for index, vector in enumerate(vectors):
        source, precision, mode, result, cc, status = vector
        suffix = "," if index + 1 < len(vectors) else ""
        print(f'        (x"{source:020X}", {precision}, {mode}, '
              f'x"{result:020X}", x"{cc:X}", x"{status:02X}"){suffix}')
    print(f"""    );
    signal clk : std_logic := '0';
    signal nReset : std_logic := '0';
    signal start : std_logic := '0';
    signal source : fpu_extended_t := (others => '0');
    signal rounding_precision : fpu_rounding_precision_t :=
        FPU_PRECISION_EXTENDED;
    signal rounding_mode : fpu_rounding_mode_t := FPU_ROUND_NEAREST;
    signal result : fpu_extended_t;
    signal condition_codes : std_logic_vector(3 downto 0);
    signal exception_status : std_logic_vector(7 downto 0);
    signal done : std_logic;
begin
    clk <= not clk after CLK_PERIOD / 2;

    dut : entity work.TG68K_FPU_Sine_Cosine
        port map(
            clk => clk,
            nReset => nReset,
            start => start,
            cosine => {cosine_literal},
            tangent => {tangent_literal},
            source => source,
            rounding_precision => rounding_precision,
            rounding_mode => rounding_mode,
            result => result,
            condition_codes => condition_codes,
            exception_status => exception_status,
            busy => open,
            done => done,
            round_input => open,
            base_exception_status => open
        );

    stimulus : process
        variable cycles : natural;
    begin
        wait for 3 * CLK_PERIOD;
        wait until rising_edge(clk);
        nReset <= '1';
        wait until rising_edge(clk);
        for index in vectors'range loop
            wait until falling_edge(clk);
            source <= vectors(index).source_value;
            rounding_precision <= vectors(index).precision_value;
            rounding_mode <= vectors(index).mode_value;
            start <= '1';
            wait until rising_edge(clk);
            wait for 1 ns;
            start <= '0';
            cycles := 0;
            while done = '0' loop
                wait until rising_edge(clk);
                wait for 1 ns;
                cycles := cycles + 1;
                assert cycles < 400
                    report "differential F{operation_upper} timeout" severity failure;
            end loop;
            assert result = vectors(index).expected_result and
                condition_codes = vectors(index).expected_cc and
                exception_status = vectors(index).expected_status
                report "differential F{operation_upper} vector " & integer'image(index) &
                    " mismatch: source=" & to_hstring(source) &
                    " result=" & to_hstring(result) &
                    " expected=" & to_hstring(vectors(index).expected_result) &
                    " cc=" & to_hstring(condition_codes) &
                    " status=" & to_hstring(exception_status)
                severity failure;
            wait until rising_edge(clk);
            wait for 1 ns;
        end loop;
        report "PASS: 1152 high-precision F{operation_upper} vectors" severity note;
        stop;
    end process;
end architecture;
""")


if __name__ == "__main__":
    emit_testbench(False)
