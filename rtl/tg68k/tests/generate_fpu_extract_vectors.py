#!/usr/bin/env python3

import random

from fpu_exact_reference import extract_extended

SEED = 0x68881E1F
VECTOR_COUNT = 512


def make_vectors() -> list[tuple[int, int, int, int, int]]:
    generator = random.Random(SEED)
    vectors = []
    for index in range(VECTOR_COUNT):
        sign = generator.randrange(2)
        exponent = generator.randrange(0x7FFF)
        significand = generator.getrandbits(64)
        pattern = index % 16
        if pattern == 0:
            exponent = 0
            significand = 1 << generator.randrange(64)
        elif pattern == 1:
            exponent = generator.randrange(1, 0x7FFF)
            significand &= (1 << 63) - 1
            if significand == 0:
                significand = 1
        elif pattern == 2:
            significand |= 1 << 63
        elif pattern == 3:
            exponent = 0
            significand = 0
        elif pattern == 4:
            exponent = 0x7FFF
            significand = 1 << 63
        elif pattern == 5:
            exponent = 0x7FFF
            significand = (1 << 63) | (1 << 62) | generator.getrandbits(62)
        elif pattern == 6:
            exponent = 0x7FFF
            significand = (1 << 63) | generator.randrange(1, 1 << 62)
        elif pattern == 7:
            exponent = 0
            significand = 1 << 63

        source = (sign << 79) | (exponent << 64) | significand
        get_exponent = index & 1
        result, condition_codes, status = extract_extended(
            source, bool(get_exponent))
        vectors.append((source, get_exponent, result, condition_codes, status))
    return vectors


def emit_testbench() -> None:
    vectors = make_vectors()
    print("""library ieee;
use ieee.std_logic_1164.all;
use std.env.all;
use work.TG68K_FPU_Pack.all;

entity tb_tg68k_fpu_extract_differential is
end entity;

architecture test of tb_tg68k_fpu_extract_differential is
    type vector_t is record
        source_value : fpu_extended_t;
        get_exponent_value : std_logic;
        expected_result : fpu_extended_t;
        expected_cc : std_logic_vector(3 downto 0);
        expected_status : std_logic_vector(7 downto 0);
    end record;
    type vector_array_t is array (natural range <>) of vector_t;
    constant vectors : vector_array_t := (""")
    for index, vector in enumerate(vectors):
        source, get_exponent, result, cc, status = vector
        suffix = "," if index + 1 < len(vectors) else ""
        print(f'        (x"{source:020X}", \'{get_exponent}\', '
              f'x"{result:020X}", x"{cc:X}", x"{status:02X}"){suffix}')
    print("""    );
    signal source_value : fpu_extended_t := (others => '0');
    signal get_exponent_value : std_logic := '0';
    signal result_value : fpu_extended_t;
    signal condition_codes : std_logic_vector(3 downto 0);
    signal exception_status : std_logic_vector(7 downto 0);
begin
    dut : entity work.TG68K_FPU_Extract
        port map(
            source => source_value,
            get_exponent => get_exponent_value,
            result => result_value,
            condition_codes => condition_codes,
            exception_status => exception_status
        );

    stimulus : process
    begin
        for index in vectors'range loop
            source_value <= vectors(index).source_value;
            get_exponent_value <= vectors(index).get_exponent_value;
            wait for 1 ns;
            assert result_value = vectors(index).expected_result and
                condition_codes = vectors(index).expected_cc and
                exception_status = vectors(index).expected_status
                report "differential extraction vector " & integer'image(index) &
                    " mismatch: result=" & to_hstring(result_value) &
                    " cc=" & to_hstring(condition_codes) &
                    " status=" & to_hstring(exception_status)
                severity failure;
        end loop;
        report "PASS: 512 exact FGETEXP/FGETMAN differential vectors"
            severity note;
        stop;
    end process;
end architecture;
""")


if __name__ == "__main__":
    emit_testbench()
