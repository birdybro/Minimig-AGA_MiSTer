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
from generate_fpu_logn_vectors import source_values


def exact_power_of_two_logarithm(value: Fraction) -> int | None:
    if value.numerator.bit_count() == 1 and value.denominator.bit_count() == 1:
        return value.numerator.bit_length() - value.denominator.bit_length()
    return None


@lru_cache(maxsize=None)
def high_precision_log2(source: int) -> tuple[Fraction, bool]:
    source_value = extended_bits_value(source)
    exact_integer = exact_power_of_two_logarithm(source_value)
    if exact_integer is not None:
        return Fraction(exact_integer), True
    with localcontext() as context:
        context.prec = 450
        source_decimal = Decimal(source_value.numerator) / Decimal(
            source_value.denominator)
        result_decimal = source_decimal.ln() / Decimal(2).ln()
    return Fraction(result_decimal), False


def reference_log2(source: int, precision_bits: int,
                   mode: int) -> tuple[int, int, int]:
    result_value, exact = high_precision_log2(source)
    result, condition_codes, status = round_binary_precision(
        result_value, precision_bits, mode)
    if not exact:
        status |= 0x02
    return result, condition_codes, status


def make_vectors():
    vectors = []
    for source in source_values():
        for precision_index in range(3):
            precision, precision_bits = precision_name(precision_index)
            for mode in range(4):
                result, condition_codes, status = reference_log2(
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

entity tb_tg68k_fpu_log2_differential is
end entity;

architecture test of tb_tg68k_fpu_log2_differential is
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

    dut : entity work.TG68K_FPU_Logarithm
        port map(
            clk => clk,
            nReset => nReset,
            start => start,
            source => source,
            add_one => '0',
            logarithm_base => FPU_LOG_BASE_TWO,
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
                assert cycles < 580
                    report "differential FLOG2 timeout" severity failure;
            end loop;
            assert result = vectors(index).expected_result and
                condition_codes = vectors(index).expected_cc and
                exception_status = vectors(index).expected_status
                report "differential FLOG2 vector " & integer'image(index) &
                    " mismatch: result=" & to_hstring(result) &
                    " cc=" & to_hstring(condition_codes) &
                    " status=" & to_hstring(exception_status)
                severity failure;
            wait until rising_edge(clk);
            wait for 1 ns;
        end loop;
        report "PASS: 1152 high-precision FLOG2 vectors" severity note;
        stop;
    end process;
end architecture;
""")


if __name__ == "__main__":
    emit_testbench()
