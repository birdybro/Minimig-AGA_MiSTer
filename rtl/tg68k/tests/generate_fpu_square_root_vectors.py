#!/usr/bin/env python3

import random

from fpu_exact_reference import (
    encode_extended,
    extended_bits_value,
    extended_value,
    mode_name,
    precision_name,
    round_square_root,
)

SEED = 0x68882504
VECTOR_COUNT = 512


def make_vectors() -> list[tuple[int, str, str, int, int, int]]:
    generator = random.Random(SEED)
    vectors = []
    for index in range(VECTOR_COUNT):
        exponent = generator.randint(-100, 100)
        significand = (1 << 63) | generator.getrandbits(63)
        precision_index = generator.randrange(3)
        mode = generator.randrange(4)

        if index % 31 == 0:
            exponent &= ~1
            significand = 1 << 63
        elif index % 31 == 1:
            exponent |= 1
            significand = 1 << 63
        elif index % 31 == 2:
            significand = (1 << 64) - 1

        source_bits = encode_extended(0, exponent, significand)
        source_value = extended_value(0, exponent, significand)
        if index % 64 == 5:
            source_bits = 0x00004000000000000000
            source_value = extended_bits_value(source_bits)
            precision_index = 0
            mode = 0
        precision_enum, precision_bits = precision_name(precision_index)
        result, condition_codes, status = round_square_root(
            source_value, precision_bits, mode)
        vectors.append((source_bits, precision_enum, mode_name(mode),
                        result, condition_codes, status))
    return vectors


def emit_testbench() -> None:
    vectors = make_vectors()
    print("""library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;
use work.TG68K_FPU_Pack.all;

entity tb_tg68k_fpu_square_root_differential is
end entity;

architecture test of tb_tg68k_fpu_square_root_differential is
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
    signal source_value : fpu_extended_t := (others => '0');
    signal precision_value : fpu_rounding_precision_t := FPU_PRECISION_EXTENDED;
    signal mode_value : fpu_rounding_mode_t := FPU_ROUND_NEAREST;
    signal result_value : fpu_extended_t;
    signal condition_codes : std_logic_vector(3 downto 0);
    signal exception_status : std_logic_vector(7 downto 0);
    signal busy : std_logic;
    signal done : std_logic;
    signal round_input_value : fpu_round_input_t;
    signal base_exception_status : std_logic_vector(7 downto 0);
    signal rounded_inexact : std_logic;
    signal rounded_overflow : std_logic;
    signal rounded_underflow : std_logic;
    signal root_start : std_logic;
    signal root_radicand : unsigned(65 downto 0);
    signal root_result : unsigned(112 downto 0);
    signal root_remainder_nonzero : std_logic;
    signal root_done : std_logic;
begin
    clk <= not clk after CLK_PERIOD / 2;

    dut : entity work.TG68K_FPU_Square_Root
        generic map(
            INCLUDE_ROUNDING_STAGE => false
        )
        port map(
            clk => clk,
            nReset => nReset,
            start => start,
            source => source_value,
            rounding_precision => precision_value,
            rounding_mode => mode_value,
            root_start => root_start,
            root_radicand => root_radicand,
            root_result => root_result(65 downto 0),
            root_remainder_nonzero => root_remainder_nonzero,
            root_done => root_done,
            result => open,
            condition_codes => open,
            exception_status => open,
            busy => busy,
            done => done,
            round_input => round_input_value,
            base_exception_status => base_exception_status
        );

    root_engine : entity work.TG68K_FPU_Square_Root_Engine
        port map(
            clk => clk,
            nReset => nReset,
            narrow_start => root_start,
            narrow_radicand => root_radicand,
            wide_start => '0',
            wide_radicand => (others => '0'),
            root_result => root_result,
            remainder_nonzero => root_remainder_nonzero,
            busy => open,
            done => root_done
        );

    shared_round : entity work.TG68K_FPU_Round
        port map(
            input_class => round_input_value.data_class,
            input_sign => round_input_value.sign,
            input_exponent => round_input_value.exponent,
            input_significand => round_input_value.significand,
            special_value => round_input_value.special,
            rounding_precision => precision_value,
            rounding_mode => mode_value,
            result => result_value,
            inexact => rounded_inexact,
            overflow => rounded_overflow,
            underflow => rounded_underflow,
            signaling_nan => open
        );

    condition_codes <= fpu_condition_codes(result_value);
    exception_status <= base_exception_status(7 downto 5) &
        rounded_overflow & rounded_underflow & base_exception_status(2) &
        rounded_inexact & base_exception_status(0);

    stimulus : process
    begin
        wait for 3 * CLK_PERIOD;
        wait until rising_edge(clk);
        nReset <= '1';
        for index in vectors'range loop
            wait until falling_edge(clk);
            source_value <= vectors(index).source_value;
            precision_value <= vectors(index).precision_value;
            mode_value <= vectors(index).mode_value;
            start <= '1';
            wait until rising_edge(clk);
            wait for 1 ns;
            start <= '0';
            while done = '0' loop
                wait until rising_edge(clk);
                wait for 1 ns;
            end loop;
            assert result_value = vectors(index).expected_result and
                condition_codes = vectors(index).expected_cc and
                exception_status = vectors(index).expected_status
                report "differential FSQRT vector " & integer'image(index) &
                    " mismatch: result=" & to_hstring(result_value) &
                    " cc=" & to_hstring(condition_codes) &
                    " status=" & to_hstring(exception_status)
                severity failure;
            wait until rising_edge(clk);
            wait for 1 ns;
        end loop;
        report "PASS: 512 exact-integer FSQRT differential vectors"
            severity note;
        stop;
    end process;
end architecture;
""")


if __name__ == "__main__":
    emit_testbench()
