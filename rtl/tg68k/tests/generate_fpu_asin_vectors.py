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
    round_binary_precision,
)
from generate_fpu_atan_vectors import atan_decimal


SEED = 0x6888100C


def source_values() -> list[int]:
    magnitudes = [
        encode_extended(0, exponent, significand) for exponent, significand in (
            (-1, 1 << 63),
            (-2, 1 << 63),
            (-1, 3 << 62),
            (-1, 15 << 59),
            (-1, (1 << 64) - (1 << 56)),
            (-1, (1 << 64) - (1 << 32)),
            (-1, (1 << 64) - 2),
            (-1, (1 << 64) - 1),
            (-26, 1 << 63),
            (-33, 1 << 63),
            (-34, 1 << 63),
            (-67, 1 << 63),
            (-68, 1 << 63),
            (-100, 1 << 63),
            (-16383, 1 << 63),
        )
    ]
    rng = random.Random(SEED)
    while len(magnitudes) < 48:
        exponent = rng.randrange(-180, 0)
        significand = (1 << 63) | rng.getrandbits(63)
        magnitudes.append(encode_extended(0, exponent, significand))
    values = []
    for magnitude in magnitudes:
        values.append(magnitude)
        values.append(magnitude | (1 << 79))
    return values


@lru_cache(maxsize=None)
def high_precision_asin(source: int) -> Fraction:
    source_value = extended_bits_value(source)
    sign = -1 if source_value < 0 else 1
    magnitude = abs(source_value)
    if magnitude < Fraction(1, 1 << 100):
        square = magnitude * magnitude
        result = magnitude + magnitude * square / 6 + (
            3 * magnitude * square * square / 40)
        return result * sign
    with localcontext() as context:
        context.prec = 450
        source_decimal = Decimal(magnitude.numerator) / Decimal(
            magnitude.denominator)
        complement = (Decimal(1) - source_decimal * source_decimal).sqrt()
        result_decimal = atan_decimal(source_decimal / complement)
    return Fraction(result_decimal) * sign


def reference_asin(source: int, precision_bits: int,
                   mode: int) -> tuple[int, int, int]:
    result, condition_codes, status = round_binary_precision(
        high_precision_asin(source), precision_bits, mode)
    return result, condition_codes, status | 0x02


def make_vectors():
    vectors = []
    for source in source_values():
        for precision_index in range(3):
            precision, precision_bits = precision_name(precision_index)
            for mode in range(4):
                result, condition_codes, status = reference_asin(
                    source, precision_bits, mode)
                vectors.append((source, precision, mode_name(mode), result,
                                condition_codes, status))
    return vectors


def emit_testbench() -> None:
    vectors = make_vectors()
    print("""library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;
use work.TG68K_FPU_Pack.all;

entity tb_tg68k_fpu_asin_differential is
end entity;

architecture test of tb_tg68k_fpu_asin_differential is
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
    signal cordic_start : std_logic;
    signal cordic_x_input : signed(147 downto 0);
    signal cordic_y_input : signed(147 downto 0);
    signal cordic_z_input : signed(147 downto 0);
    signal cordic_z_result : signed(147 downto 0);
    signal cordic_done : std_logic;
begin
    clk <= not clk after CLK_PERIOD / 2;

    cordic : entity work.TG68K_FPU_Circular_CORDIC
        port map(
            clk => clk, nReset => nReset, start => cordic_start,
            vectoring => '1', narrow_precision => '1',
            rotate_on_start => '0', x_input => cordic_x_input,
            y_input => cordic_y_input, z_input => cordic_z_input,
            x_result => open, y_result => open,
            z_result => cordic_z_result, busy => open,
            done => cordic_done
        );

    dut : entity work.TG68K_FPU_Arc_Tangent
        port map(
            clk => clk,
            nReset => nReset,
            start => start,
            source => source,
            arc_sine => '1',
            rounding_precision => rounding_precision,
            rounding_mode => rounding_mode,
            cordic_start => cordic_start,
            cordic_x_input => cordic_x_input,
            cordic_y_input => cordic_y_input,
            cordic_z_input => cordic_z_input,
            cordic_z_result => cordic_z_result,
            cordic_done => cordic_done,
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
                assert cycles < 570
                    report "differential FASIN timeout" severity failure;
            end loop;
            assert result = vectors(index).expected_result and
                condition_codes = vectors(index).expected_cc and
                exception_status = vectors(index).expected_status
                report "differential FASIN vector " & integer'image(index) &
                    " mismatch: source=" & to_hstring(source) &
                    " result=" & to_hstring(result) &
                    " expected=" & to_hstring(vectors(index).expected_result) &
                    " cc=" & to_hstring(condition_codes) &
                    " status=" & to_hstring(exception_status)
                severity failure;
            wait until rising_edge(clk);
            wait for 1 ns;
        end loop;
        report "PASS: 1152 high-precision FASIN vectors" severity note;
        stop;
    end process;
end architecture;
""")


if __name__ == "__main__":
    emit_testbench()
