#!/usr/bin/env python3

import random

from fpu_exact_reference import (
    encode_extended,
    extended_bits_value,
    extended_value,
    mode_name,
    precision_name,
    round_integral,
)

SEED = 0x68880103
VECTOR_COUNT = 512


def make_vectors() -> list[tuple[int, int, str, str, int, int, int]]:
    generator = random.Random(SEED)
    vectors = []
    for index in range(VECTOR_COUNT):
        sign = generator.randrange(2)
        exponent = generator.randint(-80, 80)
        significand = (1 << 63) | generator.getrandbits(63)
        precision_index = generator.randrange(3)
        mode = generator.randrange(4)
        force_round_zero = index & 1

        pattern = index % 32
        if pattern == 0:
            exponent = 0
            significand = 0xC000000000000000
        elif pattern == 1:
            exponent = 1
            significand = 0xA000000000000000
        elif pattern == 2:
            exponent = -1
            significand = 0x8000000000000000
        elif pattern == 3:
            exponent = -1
            significand = 0x8000000000000001
        elif pattern == 4:
            exponent = 24
            significand = 0x8000008000000000
            precision_index = 1

        source = encode_extended(sign, exponent, significand)
        value = extended_value(sign, exponent, significand)
        if index % 128 in (5, 70):
            source = 0x00008000000000000000
            value = extended_bits_value(source)
        precision_enum, precision_bits = precision_name(precision_index)
        result, condition_codes, status = round_integral(
            value, precision_bits, mode, bool(force_round_zero))
        vectors.append((source, force_round_zero, precision_enum,
                        mode_name(mode), result, condition_codes, status))
    return vectors


def emit_testbench() -> None:
    vectors = make_vectors()
    print("""library ieee;
use ieee.std_logic_1164.all;
use std.env.all;
use work.TG68K_FPU_Pack.all;

entity tb_tg68k_fpu_integer_differential is
end entity;

architecture test of tb_tg68k_fpu_integer_differential is
    type vector_t is record
        source_value : fpu_extended_t;
        force_round_zero_value : std_logic;
        precision_value : fpu_rounding_precision_t;
        mode_value : fpu_rounding_mode_t;
        expected_result : fpu_extended_t;
        expected_cc : std_logic_vector(3 downto 0);
        expected_status : std_logic_vector(7 downto 0);
    end record;
    type vector_array_t is array (natural range <>) of vector_t;
    constant vectors : vector_array_t := (""")
    for index, vector in enumerate(vectors):
        source, force_zero, precision, mode, result, cc, status = vector
        suffix = "," if index + 1 < len(vectors) else ""
        print(f'        (x"{source:020X}", \'{force_zero}\', {precision}, '
              f'{mode}, x"{result:020X}", x"{cc:X}", '
              f'x"{status:02X}"){suffix}')
    print("""    );
    signal source_value : fpu_extended_t := (others => '0');
    signal force_round_zero_value : std_logic := '0';
    signal precision_value : fpu_rounding_precision_t := FPU_PRECISION_EXTENDED;
    signal mode_value : fpu_rounding_mode_t := FPU_ROUND_NEAREST;
    signal round_input_value : fpu_round_input_t;
    signal base_exception_status : std_logic_vector(7 downto 0);
    signal selected_mode : fpu_rounding_mode_t;
    signal result_value : fpu_extended_t;
    signal condition_codes : std_logic_vector(3 downto 0);
    signal exception_status : std_logic_vector(7 downto 0);
    signal rounded_inexact : std_logic;
    signal rounded_overflow : std_logic;
    signal rounded_underflow : std_logic;
begin
    dut : entity work.TG68K_FPU_Integer
        generic map(
            INCLUDE_ROUNDING_STAGE => false
        )
        port map(
            source => source_value,
            force_round_zero => force_round_zero_value,
            rounding_precision => precision_value,
            rounding_mode => mode_value,
            result => open,
            condition_codes => open,
            exception_status => open,
            round_input => round_input_value,
            base_exception_status => base_exception_status
        );

    selected_mode <= FPU_ROUND_ZERO when force_round_zero_value = '1' else
        mode_value;

    shared_round : entity work.TG68K_FPU_Round
        port map(
            input_class => round_input_value.data_class,
            input_sign => round_input_value.sign,
            input_exponent => round_input_value.exponent,
            input_significand => round_input_value.significand,
            special_value => round_input_value.special,
            rounding_precision => precision_value,
            rounding_mode => selected_mode,
            result => result_value,
            inexact => rounded_inexact,
            overflow => rounded_overflow,
            underflow => rounded_underflow,
            signaling_nan => open
        );

    condition_codes <= fpu_condition_codes(result_value);
    exception_status <= base_exception_status(7 downto 5) &
        rounded_overflow & rounded_underflow & base_exception_status(2) &
        (base_exception_status(1) or rounded_inexact) &
        base_exception_status(0);

    stimulus : process
    begin
        for index in vectors'range loop
            source_value <= vectors(index).source_value;
            force_round_zero_value <= vectors(index).force_round_zero_value;
            precision_value <= vectors(index).precision_value;
            mode_value <= vectors(index).mode_value;
            wait for 1 ns;
            assert result_value = vectors(index).expected_result and
                condition_codes = vectors(index).expected_cc and
                exception_status = vectors(index).expected_status
                report "differential FINT/FINTRZ vector " &
                    integer'image(index) & " mismatch: result=" &
                    to_hstring(result_value) & " cc=" &
                    to_hstring(condition_codes) & " status=" &
                    to_hstring(exception_status)
                severity failure;
        end loop;
        report "PASS: 512 exact-rational FINT/FINTRZ differential vectors"
            severity note;
        stop;
    end process;
end architecture;
""")


if __name__ == "__main__":
    emit_testbench()
