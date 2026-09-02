#!/usr/bin/env python3

from decimal import Decimal, localcontext
from fractions import Fraction
from functools import lru_cache

from fpu_exact_reference import (
    mode_name,
    precision_name,
    round_binary_precision,
)
from generate_fpu_asin_vectors import high_precision_asin, source_values
from generate_fpu_atan_vectors import pi_decimal


POSITIVE_ONE = 0x3FFF8000000000000000
NEGATIVE_ONE = 0xBFFF8000000000000000


@lru_cache(maxsize=None)
def high_precision_acos(source: int) -> Fraction:
    if source == POSITIVE_ONE:
        return Fraction(0)
    if source == NEGATIVE_ONE:
        with localcontext() as context:
            context.prec = 450
            return Fraction(pi_decimal())
    arc_sine = high_precision_asin(source)
    with localcontext() as context:
        context.prec = 450
        result = (pi_decimal() / 2 -
                  Decimal(arc_sine.numerator) / Decimal(arc_sine.denominator))
    return Fraction(result)


def reference_acos(source: int, precision_bits: int,
                   mode: int) -> tuple[int, int, int]:
    result, condition_codes, status = round_binary_precision(
        high_precision_acos(source), precision_bits, mode)
    if source != POSITIVE_ONE:
        status |= 0x02
    return result, condition_codes, status


def make_vectors():
    vectors = []
    boundary_sources = [0, 1 << 79, POSITIVE_ONE, NEGATIVE_ONE]
    for source in source_values() + boundary_sources:
        for precision_index in range(3):
            precision, precision_bits = precision_name(precision_index)
            for mode in range(4):
                result, condition_codes, status = reference_acos(
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

entity tb_tg68k_fpu_acos_differential is
end entity;

architecture test of tb_tg68k_fpu_acos_differential is
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
            arc_cosine => '1',
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
                assert cycles < 610
                    report "differential FACOS timeout" severity failure;
            end loop;
            assert result = vectors(index).expected_result and
                condition_codes = vectors(index).expected_cc and
                exception_status = vectors(index).expected_status
                report "differential FACOS vector " & integer'image(index) &
                    " mismatch: source=" & to_hstring(source) &
                    " result=" & to_hstring(result) &
                    " expected=" & to_hstring(vectors(index).expected_result) &
                    " cc=" & to_hstring(condition_codes) &
                    " status=" & to_hstring(exception_status)
                severity failure;
            wait until rising_edge(clk);
            wait for 1 ns;
        end loop;
		report "PASS: 1200 high-precision FACOS vectors" severity note;
        stop;
    end process;
end architecture;
""")


if __name__ == "__main__":
    emit_testbench()
