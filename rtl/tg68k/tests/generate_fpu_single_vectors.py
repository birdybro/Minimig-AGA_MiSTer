#!/usr/bin/env python3

import random

from fpu_exact_reference import (
    encode_extended,
    extended_value,
    mode_name,
    precision_name,
    round_binary,
)

SEED = 0x68882561
VECTOR_COUNT = 512
SINGLE_MANTISSA_MASK = ((1 << 64) - 1) ^ ((1 << 40) - 1)


def make_vectors() -> list[tuple[int, int, str, str, tuple[int, int, int],
                                  tuple[int, int, int]]]:
    generator = random.Random(SEED)
    vectors = []
    for index in range(VECTOR_COUNT):
        source_sign = generator.randrange(2)
        destination_sign = generator.randrange(2)
        source_exponent = generator.randint(-400, 400)
        destination_exponent = generator.randint(-400, 400)
        source_significand = (1 << 63) | generator.getrandbits(63)
        destination_significand = (1 << 63) | generator.getrandbits(63)
        ignored_precision, _ = precision_name(generator.randrange(3))
        mode = generator.randrange(4)

        if index % 31 == 0:
            source_significand = (1 << 63) | 1
            destination_significand = (1 << 63) | 1
        elif index % 31 == 1:
            source_significand = (1 << 64) - 1
            destination_significand = (1 << 64) - 1
        elif index % 31 == 2:
            source_significand = (1 << 63) | (1 << 40)
            destination_significand = (1 << 63) | (1 << 40)
        elif index % 31 == 3:
            destination_significand = source_significand

        source_bits = encode_extended(source_sign, source_exponent,
                                      source_significand)
        destination_bits = encode_extended(destination_sign,
                                           destination_exponent,
                                           destination_significand)
        source_value = extended_value(
            source_sign, source_exponent,
            source_significand & SINGLE_MANTISSA_MASK)
        destination_value = extended_value(
            destination_sign, destination_exponent,
            destination_significand & SINGLE_MANTISSA_MASK)
        multiply_result = round_binary(
            source_value * destination_value, 24, mode)
        divide_result = round_binary(
            destination_value / source_value, 24, mode)
        vectors.append((source_bits, destination_bits, ignored_precision,
                        mode_name(mode), multiply_result, divide_result))
    return vectors


def emit_testbench() -> None:
    vectors = make_vectors()
    print("""library ieee;
use ieee.std_logic_1164.all;
use std.env.all;
use work.TG68K_FPU_Pack.all;

entity tb_tg68k_fpu_single_differential is
end entity;

architecture test of tb_tg68k_fpu_single_differential is
    constant CLK_PERIOD : time := 10 ns;
    type vector_t is record
        source_value : fpu_extended_t;
        destination_value : fpu_extended_t;
        ignored_precision : fpu_rounding_precision_t;
        mode_value : fpu_rounding_mode_t;
        expected_multiply : fpu_extended_t;
        expected_multiply_cc : std_logic_vector(3 downto 0);
        expected_multiply_status : std_logic_vector(7 downto 0);
        expected_divide : fpu_extended_t;
        expected_divide_cc : std_logic_vector(3 downto 0);
        expected_divide_status : std_logic_vector(7 downto 0);
    end record;
    type vector_array_t is array (natural range <>) of vector_t;
    constant vectors : vector_array_t := (""")
    for index, vector in enumerate(vectors):
        source, destination, precision, mode, multiply, divide = vector
        multiply_result, multiply_cc, multiply_status = multiply
        divide_result, divide_cc, divide_status = divide
        suffix = "," if index + 1 < len(vectors) else ""
        print(f'        (x"{source:020X}", x"{destination:020X}", '
              f'{precision}, {mode}, x"{multiply_result:020X}", '
              f'x"{multiply_cc:X}", x"{multiply_status:02X}", '
              f'x"{divide_result:020X}", x"{divide_cc:X}", '
              f'x"{divide_status:02X}"){suffix}')
    print("""    );
    signal clk : std_logic := '0';
    signal nReset : std_logic := '0';
    signal divide_start : std_logic := '0';
    signal source_value : fpu_extended_t := (others => '0');
    signal destination_value : fpu_extended_t := (others => '0');
    signal ignored_precision : fpu_rounding_precision_t :=
        FPU_PRECISION_EXTENDED;
    signal mode_value : fpu_rounding_mode_t := FPU_ROUND_NEAREST;
    signal multiply_round_input : fpu_round_input_t;
    signal multiply_base_status : std_logic_vector(7 downto 0);
    signal multiply_result : fpu_extended_t;
    signal multiply_inexact : std_logic;
    signal multiply_overflow : std_logic;
    signal multiply_underflow : std_logic;
    signal multiply_cc : std_logic_vector(3 downto 0);
    signal multiply_status : std_logic_vector(7 downto 0);
    signal divide_round_input : fpu_round_input_t;
    signal divide_base_status : std_logic_vector(7 downto 0);
    signal divide_result : fpu_extended_t;
    signal divide_inexact : std_logic;
    signal divide_overflow : std_logic;
    signal divide_underflow : std_logic;
    signal divide_done : std_logic;
    signal divide_cc : std_logic_vector(3 downto 0);
    signal divide_status : std_logic_vector(7 downto 0);
begin
    clk <= not clk after CLK_PERIOD / 2;

    multiply : entity work.TG68K_FPU_Multiply
        generic map(INCLUDE_ROUNDING_STAGE => false)
        port map(
            source => source_value,
            destination => destination_value,
            rounding_precision => ignored_precision,
            rounding_mode => mode_value,
            single_precision_operation => '1',
            result => open,
            condition_codes => open,
            exception_status => open,
            round_input => multiply_round_input,
            base_exception_status => multiply_base_status
        );

    multiply_round : entity work.TG68K_FPU_Round
        port map(
            input_class => multiply_round_input.data_class,
            input_sign => multiply_round_input.sign,
            input_exponent => multiply_round_input.exponent,
            input_significand => multiply_round_input.significand,
            special_value => multiply_round_input.special,
            rounding_precision => FPU_PRECISION_SINGLE,
            rounding_mode => mode_value,
            single_extended_range => '1',
            result => multiply_result,
            inexact => multiply_inexact,
            overflow => multiply_overflow,
            underflow => multiply_underflow,
            signaling_nan => open
        );

    multiply_cc <= fpu_condition_codes(multiply_result);
    multiply_status <= multiply_base_status(7 downto 5) &
        multiply_overflow & multiply_underflow & multiply_base_status(2) &
        multiply_inexact & multiply_base_status(0);

    divide : entity work.TG68K_FPU_Divide
        generic map(INCLUDE_ROUNDING_STAGE => false)
        port map(
            clk => clk,
            nReset => nReset,
            start => divide_start,
            source => source_value,
            destination => destination_value,
            rounding_precision => ignored_precision,
            rounding_mode => mode_value,
            single_precision_operation => '1',
            result => open,
            condition_codes => open,
            exception_status => open,
            busy => open,
            done => divide_done,
            round_input => divide_round_input,
            base_exception_status => divide_base_status
        );

    divide_round : entity work.TG68K_FPU_Round
        port map(
            input_class => divide_round_input.data_class,
            input_sign => divide_round_input.sign,
            input_exponent => divide_round_input.exponent,
            input_significand => divide_round_input.significand,
            special_value => divide_round_input.special,
            rounding_precision => FPU_PRECISION_SINGLE,
            rounding_mode => mode_value,
            single_extended_range => '1',
            result => divide_result,
            inexact => divide_inexact,
            overflow => divide_overflow,
            underflow => divide_underflow,
            signaling_nan => open
        );

    divide_cc <= fpu_condition_codes(divide_result);
    divide_status <= divide_base_status(7 downto 5) &
        divide_overflow & divide_underflow & divide_base_status(2) &
        divide_inexact & divide_base_status(0);

    stimulus : process
    begin
        wait for 3 * CLK_PERIOD;
        wait until rising_edge(clk);
        nReset <= '1';
        for index in vectors'range loop
            wait until falling_edge(clk);
            source_value <= vectors(index).source_value;
            destination_value <= vectors(index).destination_value;
            ignored_precision <= vectors(index).ignored_precision;
            mode_value <= vectors(index).mode_value;
            wait for 1 ns;
            assert multiply_result = vectors(index).expected_multiply and
                multiply_cc = vectors(index).expected_multiply_cc and
                multiply_status = vectors(index).expected_multiply_status
                report "differential FSGLMUL vector " & integer'image(index) &
                    " mismatch: result=" & to_hstring(multiply_result) &
                    " cc=" & to_hstring(multiply_cc) &
                    " status=" & to_hstring(multiply_status)
                severity failure;
            divide_start <= '1';
            wait until rising_edge(clk);
            wait for 1 ns;
            divide_start <= '0';
            while divide_done = '0' loop
                wait until rising_edge(clk);
                wait for 1 ns;
            end loop;
            assert divide_result = vectors(index).expected_divide and
                divide_cc = vectors(index).expected_divide_cc and
                divide_status = vectors(index).expected_divide_status
                report "differential FSGLDIV vector " & integer'image(index) &
                    " mismatch: result=" & to_hstring(divide_result) &
                    " cc=" & to_hstring(divide_cc) &
                    " status=" & to_hstring(divide_status)
                severity failure;
            wait until rising_edge(clk);
            wait for 1 ns;
        end loop;
        report "PASS: 1024 exact-rational FSGLMUL/FSGLDIV vectors"
            severity note;
        stop;
    end process;
end architecture;
""")


if __name__ == "__main__":
    emit_testbench()
