#!/usr/bin/env python3

from decimal import Decimal, localcontext
from fractions import Fraction
from functools import lru_cache

from fpu_exact_reference import (
    extended_bits_value,
    mode_name,
    precision_name,
    round_binary_precision,
)
from generate_fpu_logn_vectors import source_values as logarithm_sources


def pi_decimal() -> Decimal:
    one = Decimal(1)
    a = one
    b = one / Decimal(2).sqrt()
    t = one / 4
    scale = one
    for _ in range(10):
        next_a = (a + b) / 2
        b = (a * b).sqrt()
        t -= scale * (a - next_a) * (a - next_a)
        a = next_a
        scale *= 2
    return (a + b) * (a + b) / (4 * t)


def atan_decimal(value: Decimal) -> Decimal:
    reciprocal = value > 1
    if reciprocal:
        value = Decimal(1) / value
    scale = 1
    for _ in range(8):
        value = value / (Decimal(1) +
                         (Decimal(1) + value * value).sqrt())
        scale *= 2
    square = value * value
    term = value
    result = value
    denominator = 3
    while True:
        term *= -square
        previous = result
        result += term / denominator
        if result == previous:
            break
        denominator += 2
    result *= scale
    if reciprocal:
        result = pi_decimal() / 2 - result
    return result


def source_values() -> list[int]:
    magnitudes = logarithm_sources()[:48]
    values = []
    for magnitude in magnitudes:
        values.append(magnitude)
        values.append(magnitude | (1 << 79))
    return values


@lru_cache(maxsize=None)
def high_precision_atan(source: int) -> Fraction:
    source_value = extended_bits_value(source)
    sign = -1 if source_value < 0 else 1
    source_value = abs(source_value)
    if source_value < Fraction(1, 1 << 34):
        result = source_value - source_value / (1 << 200)
        return result * sign
    with localcontext() as context:
        context.prec = 450
        source_decimal = Decimal(source_value.numerator) / Decimal(
            source_value.denominator)
        result_decimal = atan_decimal(source_decimal)
    return Fraction(result_decimal) * sign


def reference_atan(source: int, precision_bits: int,
                   mode: int) -> tuple[int, int, int]:
    result, condition_codes, status = round_binary_precision(
        high_precision_atan(source), precision_bits, mode)
    status |= 0x02
    return result, condition_codes, status


def make_vectors():
    vectors = []
    for source in source_values():
        for precision_index in range(3):
            precision, precision_bits = precision_name(precision_index)
            for mode in range(4):
                result, condition_codes, status = reference_atan(
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

entity tb_tg68k_fpu_atan_differential is
end entity;

architecture test of tb_tg68k_fpu_atan_differential is
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

    dut : entity work.TG68K_FPU_Arc_Tangent
        port map(
            clk => clk,
            nReset => nReset,
            start => start,
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
                assert cycles < 250
                    report "differential FATAN timeout" severity failure;
            end loop;
            assert result = vectors(index).expected_result and
                condition_codes = vectors(index).expected_cc and
                exception_status = vectors(index).expected_status
                report "differential FATAN vector " & integer'image(index) &
                    " mismatch: result=" & to_hstring(result) &
                    " cc=" & to_hstring(condition_codes) &
                    " status=" & to_hstring(exception_status)
                severity failure;
            wait until rising_edge(clk);
            wait for 1 ns;
        end loop;
        report "PASS: 1152 high-precision FATAN vectors" severity note;
        stop;
    end process;
end architecture;
""")


if __name__ == "__main__":
    emit_testbench()
