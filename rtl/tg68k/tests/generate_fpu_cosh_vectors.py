#!/usr/bin/env python3

from decimal import Decimal, localcontext
from fractions import Fraction
from functools import lru_cache
import random

from fpu_exact_reference import (
    encode_extended,
    extended_bits_value,
    mode_name,
    precision_name,
    round_binary,
    round_binary_precision,
)


SEED = 0x68881019


def encode_fraction(value: Fraction) -> int:
    result, _, _ = round_binary(value, 64, 0)
    if extended_bits_value(result) != value:
        raise ValueError("test operand is not exactly representable")
    return result


def source_values() -> list[int]:
    values = [
        encode_fraction(value) for value in (
            Fraction(1, 2), Fraction(-1, 2), Fraction(1, 4),
            Fraction(-1, 4), Fraction(3, 4), Fraction(-3, 4),
            Fraction(1), Fraction(-1), Fraction(3, 2), Fraction(-3, 2),
            Fraction(13, 4), Fraction(-13, 4),
            Fraction(100), Fraction(-100),
            Fraction(1, 1 << 11), Fraction(-1, 1 << 11),
            Fraction(1, 1 << 12), Fraction(-1, 1 << 12),
            Fraction(1, 1 << 13), Fraction(-1, 1 << 13),
            Fraction(1, 1 << 26), Fraction(-1, 1 << 26),
            Fraction(1, 1 << 27), Fraction(-1, 1 << 27),
            Fraction(1, 1 << 31), Fraction(-1, 1 << 31),
            Fraction(1, 1 << 32), Fraction(-1, 1 << 32),
        )
    ]
    values.extend((
        encode_extended(0, -16383, 1 << 63),
        encode_extended(1, -16383, 1 << 63),
    ))
    rng = random.Random(SEED)
    for _ in range(66):
        sign = rng.randrange(2)
        exponent = rng.randrange(-180, 5)
        significand = (1 << 63) | rng.getrandbits(63)
        values.append(encode_extended(sign, exponent, significand))
    return values


@lru_cache(maxsize=None)
def high_precision_cosh(source: int) -> Fraction:
    source_value = extended_bits_value(source)
    if abs(source_value) < Fraction(1, 1 << 100):
        square = source_value * source_value
        return 1 + square / 2 + square * square / 24
    with localcontext() as context:
        context.prec = 400
        source_decimal = Decimal(source_value.numerator) / Decimal(
            source_value.denominator)
        positive_exponential = source_decimal.exp()
        negative_exponential = (-source_decimal).exp()
        result_decimal = (positive_exponential + negative_exponential) / 2
    return Fraction(result_decimal)


def reference_cosh(source: int, precision_bits: int,
                   mode: int) -> tuple[int, int, int]:
    result, condition_codes, status = round_binary_precision(
        high_precision_cosh(source), precision_bits, mode)
    return result, condition_codes, status | 0x02


def make_vectors():
    vectors = []
    for source in source_values():
        for precision_index in range(3):
            precision, precision_bits = precision_name(precision_index)
            for mode in range(4):
                result, condition_codes, status = reference_cosh(
                    source, precision_bits, mode)
                vectors.append((source, precision, mode_name(mode), result,
                                condition_codes, status))
    return vectors


def emit_testbench() -> None:
    vectors = make_vectors()
    print("""library ieee;
use ieee.std_logic_1164.all;
use std.env.all;
use work.TG68K_FPU_Pack.all;

entity tb_tg68k_fpu_cosh_differential is
end entity;

architecture test of tb_tg68k_fpu_cosh_differential is
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
    print("""    );
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

    dut : entity work.TG68K_FPU_Exponential_With_CORDIC
        port map(
            clk => clk,
            nReset => nReset,
            start => start,
            source => source,
            exponential_base => FPU_EXP_BASE_E,
            subtract_one => '0',
            hyperbolic_cosine => '1',
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
                assert cycles < 600
                    report "differential FCOSH timeout" severity failure;
            end loop;
            assert result = vectors(index).expected_result and
                condition_codes = vectors(index).expected_cc and
                exception_status = vectors(index).expected_status
                report "differential FCOSH vector " & integer'image(index) &
                    " mismatch: source=" & to_hstring(source) &
                    " result=" & to_hstring(result) &
                    " expected=" & to_hstring(vectors(index).expected_result) &
                    " cc=" & to_hstring(condition_codes) &
                    " status=" & to_hstring(exception_status)
                severity failure;
            wait until rising_edge(clk);
            wait for 1 ns;
        end loop;
        report "PASS: 1152 high-precision FCOSH vectors" severity note;
        stop;
    end process;
end architecture;
""")


if __name__ == "__main__":
    emit_testbench()
