#!/usr/bin/env python3

from fractions import Fraction
import random

from fpu_exact_reference import round_binary


def encode_packed(sign: int, exponent_sign: int, exponent_digits: list[int],
                  mantissa_digits: list[int], y_bits: int = 0,
                  exponent_four: int = 0, unused: int = 0) -> int:
    value = sign << 95
    value |= exponent_sign << 94
    value |= (y_bits & 3) << 92
    value |= (exponent_digits[0] & 15) << 88
    value |= (exponent_digits[1] & 15) << 84
    value |= (exponent_digits[2] & 15) << 80
    value |= (exponent_four & 15) << 76
    value |= (unused & 255) << 68
    value |= (mantissa_digits[0] & 15) << 64
    for index, digit in enumerate(mantissa_digits[1:]):
        value |= (digit & 15) << ((15 - index) * 4)
    return value


def packed_special(sign: int, fraction: int) -> int:
    value = (sign << 95) | (1 << 94) | (3 << 92) | (0xFFF << 80)
    return value | (fraction & ((1 << 64) - 1))


def decode_integer(digits: list[int]) -> int:
    value = 0
    for digit in digits:
        value = value * 10 + digit
    return value


def reference(source: int, mode: int) -> tuple[int, int]:
    sign = (source >> 95) & 1
    exponent_sign = (source >> 94) & 1
    y_bits = (source >> 92) & 3
    exponent_field = (source >> 80) & 0xFFF
    fraction = source & ((1 << 64) - 1)
    if exponent_sign and y_bits == 3 and exponent_field == 0xFFF:
        if fraction == 0:
            return ((sign << 79) | (0x7FFF << 64) | (1 << 63), 0)
        result = (sign << 79) | (0x7FFF << 64) | fraction | (1 << 62)
        status = 0x40 if (fraction & (1 << 62)) == 0 else 0
        return result, status

    exponent_digits = [
        (source >> 88) & 15,
        (source >> 84) & 15,
        (source >> 80) & 15,
    ]
    mantissa_digits = [(source >> 64) & 15]
    mantissa_digits.extend((source >> shift) & 15
                           for shift in range(60, -1, -4))
    mantissa = decode_integer(mantissa_digits)
    if mantissa == 0:
        return sign << 79, 0

    exponent = decode_integer(exponent_digits)
    scale = (-exponent if exponent_sign else exponent) - 16
    if scale >= 0:
        magnitude = Fraction(mantissa * 10 ** scale, 1)
    else:
        magnitude = Fraction(mantissa, 10 ** -scale)
    value = -magnitude if sign else magnitude
    result, _, binary_status = round_binary(value, 64, mode)
    return result, 1 if binary_status & 2 else 0


def source_values() -> list[int]:
    sources = [
        encode_packed(0, 0, [0, 0, 0], [0] * 17),
        encode_packed(1, 1, [15, 15, 15], [0] * 17,
                      y_bits=2, exponent_four=13, unused=0xA5),
        packed_special(0, 0),
        packed_special(1, 0),
        packed_special(0, 0x4000000000000042),
        packed_special(1, 0x0000000000000042),
    ]
    decimal_cases = [
        (0, 0, [0, 0, 0], "10000000000000000"),
        (1, 0, [0, 0, 0], "10000000000000000"),
        (0, 0, [0, 0, 0], "50000000000000000"),
        (0, 0, [0, 0, 1], "10000000000000000"),
        (0, 1, [0, 0, 1], "10000000000000000"),
        (0, 0, [0, 0, 4], "12345678765000000"),
        (1, 0, [0, 0, 4], "12345678765000000"),
        (0, 0, [9, 9, 9], "99999999999999999"),
        (0, 1, [9, 9, 9], "99999999999999999"),
        (0, 0, [9, 9, 9], "00000000000000001"),
        (0, 1, [9, 9, 9], "00000000000000001"),
        (0, 0, [0, 1, 6], "18446744073709552"),
        (0, 0, [0, 0, 0], "31415926535897932"),
        (0, 1, [0, 0, 0], "27182818284590452"),
    ]
    for sign, exponent_sign, exponent_digits, text in decimal_cases:
        sources.append(encode_packed(
            sign, exponent_sign, exponent_digits,
            [int(character) for character in text],
            y_bits=(len(sources) & 3), exponent_four=11, unused=0x5A))

    invalid_cases = [
        (0, 0, [10, 0, 0], [15] + [0] * 16),
        (1, 1, [10, 0, 0], [15] * 17),
        (0, 0, [15, 15, 15], [1] + [0] * 16),
        (0, 1, [15, 15, 15], [1] + [0] * 16),
        (0, 0, [1, 10, 5], [10, 11, 12, 13, 14, 15] + [9] * 11),
        (1, 1, [1, 10, 5], [10, 11, 12, 13, 14, 15] + [9] * 11),
    ]
    for sign, exponent_sign, exponent_digits, digits in invalid_cases:
        sources.append(encode_packed(
            sign, exponent_sign, exponent_digits, digits,
            y_bits=1, exponent_four=15, unused=0xFF))

    # Exercise every normalized power and reciprocal table entry.  Values above
    # 999 deliberately use a nondecimal hundreds digit, as the MC68882 does.
    for exponent in range(1666):
        hundreds = exponent // 100
        remainder = exponent - 100 * hundreds
        exponent_digits = [hundreds, remainder // 10, remainder % 10]
        mantissa = f"{(10 ** 16 + exponent * 68881) % (10 ** 17):017d}"
        if int(mantissa) == 0:
            mantissa = "10000000000000000"
        sources.append(encode_packed(
            exponent & 1, 0, exponent_digits,
            [int(character) for character in mantissa]))
        sources.append(encode_packed(
            (exponent >> 1) & 1, 1, exponent_digits,
            [int(character) for character in mantissa]))

    for power in range(1, 25):
        mantissa = f"{5 ** power:017d}"
        if power <= 16:
            exponent_sign = 0
            exponent = 16 - power
        else:
            exponent_sign = 1
            exponent = power - 16
        sources.append(encode_packed(
            0, exponent_sign,
            [exponent // 100, (exponent // 10) % 10, exponent % 10],
            [int(character) for character in mantissa]))

    rng = random.Random(0x68882DEC)
    for _ in range(1024):
        digits = [rng.randrange(10) for _ in range(17)]
        if all(digit == 0 for digit in digits):
            digits[-1] = 1
        exponent = rng.randrange(1000)
        sources.append(encode_packed(
            rng.randrange(2), rng.randrange(2),
            [exponent // 100, (exponent // 10) % 10, exponent % 10],
            digits, y_bits=rng.randrange(4), exponent_four=rng.randrange(16),
            unused=rng.randrange(256)))
    return sources


def emit_testbench() -> None:
    vectors = []
    for source in source_values():
        for mode in range(4):
            result, status = reference(source, mode)
            vectors.append((source, mode, result, status))

    mode_names = [
        "FPU_ROUND_NEAREST",
        "FPU_ROUND_ZERO",
        "FPU_ROUND_MINUS_INFINITY",
        "FPU_ROUND_PLUS_INFINITY",
    ]
    print("""library ieee;
use ieee.std_logic_1164.all;
use std.env.all;
use work.TG68K_FPU_Pack.all;

entity tb_tg68k_fpu_packed_to_extended_differential is
end entity;

architecture test of tb_tg68k_fpu_packed_to_extended_differential is
    constant CLK_PERIOD : time := 10 ns;
    type vector_t is record
        source_value : std_logic_vector(95 downto 0);
        mode_value : fpu_rounding_mode_t;
        expected_result : fpu_extended_t;
        expected_status : std_logic_vector(7 downto 0);
    end record;
    type vector_array_t is array (natural range <>) of vector_t;
    constant vectors : vector_array_t := (""")
    for index, (source, mode, result, status) in enumerate(vectors):
        suffix = "," if index + 1 < len(vectors) else ""
        print(f'        (x"{source:024X}", {mode_names[mode]}, '
              f'x"{result:020X}", x"{status:02X}"){suffix}')
    print(f"""    );
    signal clk : std_logic := '0';
    signal nReset : std_logic := '0';
    signal start : std_logic := '0';
    signal source : std_logic_vector(95 downto 0) := (others => '0');
    signal rounding_mode : fpu_rounding_mode_t := FPU_ROUND_NEAREST;
    signal result : fpu_extended_t;
    signal exception_status : std_logic_vector(7 downto 0);
    signal done : std_logic;
begin
    clk <= not clk after CLK_PERIOD / 2;

    dut : entity work.TG68K_FPU_Packed_To_Extended
        port map(
            clk => clk,
            nReset => nReset,
            start => start,
            source => source,
            rounding_mode => rounding_mode,
            result => result,
            exception_status => exception_status,
            busy => open,
            done => done
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
                assert cycles < 950
                    report "packed input conversion timeout" severity failure;
            end loop;
            if (source(94) = '1' and source(93 downto 92) = "11" and
                    source(91 downto 80) = x"FFF") or
                    (source(67 downto 64) = "0000" and
                    source(63 downto 0) = x"0000000000000000") then
                assert cycles = 0
                    report "packed special conversion latency mismatch"
                    severity failure;
            else
                assert cycles = 76
                    report "packed finite conversion latency mismatch"
                    severity failure;
            end if;
            assert result = vectors(index).expected_result and
                exception_status = vectors(index).expected_status
                report "packed input vector " & integer'image(index) &
                    " mismatch: source=" & to_hstring(source) &
                    " result=" & to_hstring(result) &
                    " expected=" & to_hstring(vectors(index).expected_result) &
                    " status=" & to_hstring(exception_status) &
                    " expected_status=" &
                    to_hstring(vectors(index).expected_status)
                severity failure;
            wait until rising_edge(clk);
            wait for 1 ns;
        end loop;
        report "PASS: {len(vectors)} exact packed-decimal input vectors"
            severity note;
        stop;
    end process;
end architecture;
""")


if __name__ == "__main__":
    emit_testbench()
