#!/usr/bin/env python3

from fractions import Fraction
import random


SEED = 0x68882ADD
VECTOR_COUNT = 512
EXPONENT_BIAS = 16383


def power_of_two(exponent: int) -> Fraction:
    if exponent >= 0:
        return Fraction(1 << exponent, 1)
    return Fraction(1, 1 << -exponent)


def extended_value(sign: int, exponent: int, significand: int) -> Fraction:
    value = Fraction(significand, 1) * power_of_two(exponent - 63)
    return -value if sign else value


def encode_extended(sign: int, exponent: int, significand: int) -> int:
    return (sign << 79) | ((exponent + EXPONENT_BIAS) << 64) | significand


def rounding_increment(mode: int, sign: int, quotient: int,
                       remainder: int, denominator: int) -> bool:
    if remainder == 0:
        return False
    if mode == 0:
        twice_remainder = remainder * 2
        return twice_remainder > denominator or (
            twice_remainder == denominator and (quotient & 1) != 0)
    if mode == 1:
        return False
    if mode == 2:
        return sign == 1
    return sign == 0


def round_binary(value: Fraction, precision: int, mode: int) -> tuple[int, int, int]:
    if value == 0:
        sign = 1 if mode == 2 else 0
        return sign << 79, 0x4 | (sign << 3), 0

    sign = 1 if value < 0 else 0
    magnitude = abs(value)
    exponent = magnitude.numerator.bit_length() - magnitude.denominator.bit_length()
    if magnitude < power_of_two(exponent):
        exponent -= 1
    elif magnitude >= power_of_two(exponent + 1):
        exponent += 1

    scaled = magnitude / power_of_two(exponent - (precision - 1))
    quotient, remainder = divmod(scaled.numerator, scaled.denominator)
    inexact = remainder != 0
    if rounding_increment(mode, sign, quotient, remainder, scaled.denominator):
        quotient += 1
    if quotient == 1 << precision:
        quotient >>= 1
        exponent += 1
    significand = quotient << (64 - precision)
    encoded = encode_extended(sign, exponent, significand)
    condition_codes = sign << 3
    status = 0x02 if inexact else 0
    return encoded, condition_codes, status


def precision_name(index: int) -> tuple[str, int]:
    return (
        ("FPU_PRECISION_EXTENDED", 64),
        ("FPU_PRECISION_SINGLE", 24),
        ("FPU_PRECISION_DOUBLE", 53),
    )[index]


def mode_name(index: int) -> str:
    return (
        "FPU_ROUND_NEAREST",
        "FPU_ROUND_ZERO",
        "FPU_ROUND_MINUS_INFINITY",
        "FPU_ROUND_PLUS_INFINITY",
    )[index]


def make_vectors() -> list[tuple[int, int, int, str, str, int, int, int]]:
    generator = random.Random(SEED)
    vectors = []
    for index in range(VECTOR_COUNT):
        source_sign = generator.randrange(2)
        destination_sign = generator.randrange(2)
        source_exponent = generator.randint(-80, 80)
        destination_exponent = generator.randint(-80, 80)
        source_significand = (1 << 63) | generator.getrandbits(63)
        destination_significand = (1 << 63) | generator.getrandbits(63)
        subtract = generator.randrange(2)
        precision_index = generator.randrange(3)
        mode = generator.randrange(4)

        if index % 31 == 0:
            destination_sign = source_sign
            destination_exponent = source_exponent
            destination_significand = source_significand
            subtract = 1
        elif index % 31 == 1:
            source_sign = 0
            destination_sign = 0
            source_exponent = generator.randint(-40, 40)
            destination_exponent = source_exponent + 1
            source_significand = (1 << 64) - 1
            destination_significand = 1 << 63
            subtract = 1
        elif index % 31 == 2:
            source_sign = destination_sign
            source_exponent = generator.randint(-80, 40)
            destination_exponent = source_exponent + 70
            subtract = generator.randrange(2)
        elif index % 31 == 3:
            source_sign = destination_sign
            destination_exponent = source_exponent + 4
            subtract = 1

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
        exact_result = destination_value - source_value if subtract else (
            destination_value + source_value)
        precision_enum, precision_bits = precision_name(precision_index)
        result, condition_codes, status = round_binary(
            exact_result, precision_bits, mode)
        vectors.append((source_bits, destination_bits, subtract,
                        precision_enum, mode_name(mode), result,
                        condition_codes, status))
    return vectors


def emit_testbench() -> None:
    vectors = make_vectors()
    print("""library ieee;
use ieee.std_logic_1164.all;
use std.env.all;
use work.TG68K_FPU_Pack.all;

entity tb_tg68k_fpu_add_differential is
end entity;

architecture test of tb_tg68k_fpu_add_differential is
    type vector_t is record
        source_value : fpu_extended_t;
        destination_value : fpu_extended_t;
        subtract_value : std_logic;
        precision_value : fpu_rounding_precision_t;
        mode_value : fpu_rounding_mode_t;
        expected_result : fpu_extended_t;
        expected_cc : std_logic_vector(3 downto 0);
        expected_status : std_logic_vector(7 downto 0);
    end record;
    type vector_array_t is array (natural range <>) of vector_t;
    constant vectors : vector_array_t := (""")
    for index, vector in enumerate(vectors):
        source, destination, subtract, precision, mode, result, cc, status = vector
        suffix = "," if index + 1 < len(vectors) else ""
        print(f'        (x"{source:020X}", x"{destination:020X}", '
              f"'{subtract}', {precision}, {mode}, "
              f'x"{result:020X}", x"{cc:X}", x"{status:02X}"){suffix}')
    print("""    );
    signal source_value : fpu_extended_t := (others => '0');
    signal destination_value : fpu_extended_t := (others => '0');
    signal subtract_value : std_logic := '0';
    signal precision_value : fpu_rounding_precision_t := FPU_PRECISION_EXTENDED;
    signal mode_value : fpu_rounding_mode_t := FPU_ROUND_NEAREST;
    signal result_value : fpu_extended_t;
    signal condition_codes : std_logic_vector(3 downto 0);
    signal exception_status : std_logic_vector(7 downto 0);
begin
    dut : entity work.TG68K_FPU_Add_Subtract
        port map(
            source => source_value,
            destination => destination_value,
            subtract => subtract_value,
            compare_only => '0',
            rounding_precision => precision_value,
            rounding_mode => mode_value,
            result => result_value,
            condition_codes => condition_codes,
            exception_status => exception_status
        );

    stimulus : process
    begin
        for index in vectors'range loop
            source_value <= vectors(index).source_value;
            destination_value <= vectors(index).destination_value;
            subtract_value <= vectors(index).subtract_value;
            precision_value <= vectors(index).precision_value;
            mode_value <= vectors(index).mode_value;
            wait for 1 ns;
            assert result_value = vectors(index).expected_result and
                condition_codes = vectors(index).expected_cc and
                exception_status = vectors(index).expected_status
                report "differential FADD/FSUB vector " & integer'image(index) &
                    " mismatch: result=" & to_hstring(result_value) &
                    " cc=" & to_hstring(condition_codes) &
                    " status=" & to_hstring(exception_status)
                severity failure;
        end loop;
        report "PASS: 512 exact-rational FADD/FSUB differential vectors"
            severity note;
        stop;
    end process;
end architecture;
""")


if __name__ == "__main__":
    emit_testbench()
