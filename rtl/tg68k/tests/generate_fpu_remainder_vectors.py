#!/usr/bin/env python3

import random

from fpu_exact_reference import (
    encode_extended,
    extended_bits_value,
    extended_value,
    mode_name,
    precision_name,
    round_remainder,
)

SEED = 0x68882125
VECTOR_COUNT = 512


def make_vectors() -> list[tuple[int, int, int, str, str, int, int, int, int]]:
    generator = random.Random(SEED)
    vectors = []
    for index in range(VECTOR_COUNT):
        source_sign = generator.randrange(2)
        destination_sign = generator.randrange(2)
        source_exponent = generator.randint(-10, 10)
        destination_exponent = generator.randint(-15, 100)
        source_significand = (1 << 63) | generator.getrandbits(63)
        destination_significand = (1 << 63) | generator.getrandbits(63)
        precision_index = generator.randrange(3)
        mode = generator.randrange(4)
        ieee_remainder = index & 1

        pattern = index % 32
        if pattern == 0:
            source_exponent = 1
            source_significand = 0x8000000000000000
            destination_exponent = 2
            destination_significand = 0xE000000000000000
        elif pattern == 1:
            source_exponent = 2
            source_significand = 0x8000000000000000
            destination_exponent = 2
            destination_significand = 0xC000000000000000
        elif pattern == 2:
            source_exponent = 2
            source_significand = 0x8000000000000000
            destination_exponent = 1
            destination_significand = 0xC000000000000000
        elif pattern == 3:
            source_exponent = 0
            source_significand = 0xC000000000000000
            destination_exponent = 100
            destination_significand = 0x8000000000000000
        elif pattern == 4:
            destination_exponent = source_exponent
            destination_significand = source_significand

        source_bits = encode_extended(source_sign, source_exponent,
                                      source_significand)
        destination_bits = encode_extended(destination_sign,
                                           destination_exponent,
                                           destination_significand)
        source_value = extended_value(source_sign, source_exponent,
                                      source_significand)
        destination_value = extended_value(destination_sign,
                                           destination_exponent,
                                           destination_significand)
        if index % 128 in (5, 70):
            source_bits = 0x00008000000000000000
            destination_bits = 0x00018000000000000000
            source_value = extended_bits_value(source_bits)
            destination_value = extended_bits_value(destination_bits)
            precision_index = 0
            mode = 0
        precision_enum, precision_bits = precision_name(precision_index)
        result, condition_codes, status, quotient = round_remainder(
            source_value, destination_value, precision_bits, mode,
            bool(ieee_remainder))
        vectors.append((ieee_remainder, source_bits, destination_bits,
                        precision_enum, mode_name(mode), result,
                        condition_codes, status, quotient))
    return vectors


def emit_testbench() -> None:
    vectors = make_vectors()
    print("""library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;
use work.TG68K_FPU_Pack.all;

entity tb_tg68k_fpu_remainder_differential is
end entity;

architecture test of tb_tg68k_fpu_remainder_differential is
    constant CLK_PERIOD : time := 10 ns;
    type vector_t is record
        ieee_remainder_value : std_logic;
        source_value : fpu_extended_t;
        destination_value : fpu_extended_t;
        precision_value : fpu_rounding_precision_t;
        mode_value : fpu_rounding_mode_t;
        expected_result : fpu_extended_t;
        expected_cc : std_logic_vector(3 downto 0);
        expected_status : std_logic_vector(7 downto 0);
        expected_quotient : std_logic_vector(7 downto 0);
    end record;
    type vector_array_t is array (natural range <>) of vector_t;
    constant vectors : vector_array_t := (""")
    for index, vector in enumerate(vectors):
        (ieee_remainder, source, destination, precision, mode, result, cc,
         status, quotient) = vector
        suffix = "," if index + 1 < len(vectors) else ""
        print(f"        ('{ieee_remainder}', x\"{source:020X}\", "
              f'x"{destination:020X}", {precision}, {mode}, '
              f'x"{result:020X}", x"{cc:X}", x"{status:02X}", '
              f'x"{quotient:02X}"){suffix}')
    print("""    );
    signal clk : std_logic := '0';
    signal nReset : std_logic := '0';
    signal start : std_logic := '0';
    signal ieee_remainder_value : std_logic := '0';
    signal source_value : fpu_extended_t := (others => '0');
    signal destination_value : fpu_extended_t := (others => '0');
    signal precision_value : fpu_rounding_precision_t := FPU_PRECISION_EXTENDED;
    signal mode_value : fpu_rounding_mode_t := FPU_ROUND_NEAREST;
    signal result_value : fpu_extended_t;
    signal condition_codes : std_logic_vector(3 downto 0);
    signal exception_status : std_logic_vector(7 downto 0);
    signal quotient : std_logic_vector(7 downto 0);
    signal done : std_logic;
    signal digit_start : std_logic;
    signal digit_initial_mode : fpu_divide_initial_t;
    signal digit_divisor : unsigned(64 downto 0);
    signal digit_dividend : unsigned(64 downto 0);
    signal digit_forced_subtrahend : unsigned(64 downto 0);
    signal digit_iterations : natural range 0 to 65535;
    signal digit_nearest_adjust : std_logic;
    signal digit_remainder : unsigned(64 downto 0);
    signal digit_quotient : unsigned(65 downto 0);
    signal digit_sign_invert : std_logic;
    signal digit_done : std_logic;
begin
    clk <= not clk after CLK_PERIOD / 2;

    dut : entity work.TG68K_FPU_Remainder
        port map(
            clk => clk,
            nReset => nReset,
            start => start,
            ieee_remainder => ieee_remainder_value,
            source => source_value,
            destination => destination_value,
            rounding_precision => precision_value,
            rounding_mode => mode_value,
            reduction_start => digit_start,
            reduction_initial_mode => digit_initial_mode,
            reduction_divisor => digit_divisor,
            reduction_dividend => digit_dividend,
            reduction_forced_subtrahend => digit_forced_subtrahend,
            reduction_iterations => digit_iterations,
            reduction_nearest_adjust => digit_nearest_adjust,
            reduction_remainder => digit_remainder,
            reduction_quotient => digit_quotient,
            reduction_sign_invert => digit_sign_invert,
            reduction_done => digit_done,
            result => result_value,
            condition_codes => condition_codes,
            exception_status => exception_status,
            quotient => quotient,
            busy => open,
            done => done,
            round_input => open,
            base_exception_status => open
        );

    digit_engine : entity work.TG68K_FPU_Divide_Engine
        port map(
            clk => clk,
            nReset => nReset,
            start => digit_start,
            initial_mode => digit_initial_mode,
            divisor => digit_divisor,
            dividend => digit_dividend,
            forced_subtrahend => digit_forced_subtrahend,
            iterations => digit_iterations,
            nearest_adjust => digit_nearest_adjust,
            divisor_result => open,
            remainder_result => digit_remainder,
            quotient_result => digit_quotient,
            exponent_decrement => open,
            sign_invert => digit_sign_invert,
            busy => open,
            done => digit_done
        );

    stimulus : process
        variable cycle_count : natural;
    begin
        wait for 3 * CLK_PERIOD;
        wait until rising_edge(clk);
        nReset <= '1';
        for index in vectors'range loop
            wait until falling_edge(clk);
            ieee_remainder_value <= vectors(index).ieee_remainder_value;
            source_value <= vectors(index).source_value;
            destination_value <= vectors(index).destination_value;
            precision_value <= vectors(index).precision_value;
            mode_value <= vectors(index).mode_value;
            start <= '1';
            wait until rising_edge(clk);
            wait for 1 ns;
            start <= '0';
            cycle_count := 0;
            while done = '0' loop
                wait until rising_edge(clk);
                wait for 1 ns;
                cycle_count := cycle_count + 1;
                assert cycle_count < 65536
                    report "differential remainder operation did not complete"
                    severity failure;
            end loop;
            assert result_value = vectors(index).expected_result and
                condition_codes = vectors(index).expected_cc and
                exception_status = vectors(index).expected_status and
                quotient = vectors(index).expected_quotient
                report "differential FMOD/FREM vector " &
                    integer'image(index) & " mismatch: result=" &
                    to_hstring(result_value) & " cc=" &
                    to_hstring(condition_codes) & " status=" &
                    to_hstring(exception_status) & " quotient=" &
                    to_hstring(quotient)
                severity failure;
            wait until rising_edge(clk);
            wait for 1 ns;
        end loop;
        report "PASS: 512 exact-rational FMOD/FREM differential vectors"
            severity note;
        stop;
    end process;
end architecture;
""")


if __name__ == "__main__":
    emit_testbench()
