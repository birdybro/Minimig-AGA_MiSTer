#!/usr/bin/env python3

from functools import cache
from fractions import Fraction
import random

from fpu_exact_reference import round_binary


POWER_PRECISION = 192
SEGMENT_SIZE = 128
LOG10_TWO_SCALED = 1292913986


@cache
def power_of_ten(exponent: int) -> Fraction:
    if exponent >= 0:
        return Fraction(10 ** exponent, 1)
    return Fraction(1, 10 ** -exponent)


@cache
def normalized_power(exponent: int, inverse: bool) -> tuple[int, int]:
    power = 5 ** exponent
    power_bits = power.bit_length()
    if inverse:
        numerator = 1 << (power_bits - 2 + POWER_PRECISION)
        return (numerator + power - 1) // power, power_bits
    shift = POWER_PRECISION - power_bits
    if shift >= 0:
        return power << shift, power_bits
    return power >> -shift, power_bits


def finite_fields(source: int) -> tuple[int, int, int]:
    sign = (source >> 79) & 1
    exponent_field = (source >> 64) & 0x7FFF
    significand = source & ((1 << 64) - 1)
    binary_power = (-16446 if exponent_field == 0 else
                    exponent_field - 16383 - 63)
    return sign, significand, binary_power


def finite_value(source: int) -> Fraction:
    sign, significand, binary_power = finite_fields(source)
    if binary_power >= 0:
        magnitude = Fraction(significand << binary_power, 1)
    else:
        magnitude = Fraction(significand, 1 << -binary_power)
    return -magnitude if sign else magnitude


def decimal_exponent(magnitude: Fraction, estimate: int) -> int:
    while magnitude < power_of_ten(estimate):
        estimate -= 1
    while magnitude >= power_of_ten(estimate + 1):
        estimate += 1
    return estimate


def rounding_increment(mode: int, sign: int, quotient: int,
                       remainder: int, denominator: int) -> bool:
    if remainder == 0:
        return False
    if mode == 0:
        twice_remainder = 2 * remainder
        return twice_remainder > denominator or (
            twice_remainder == denominator and (quotient & 1) != 0)
    if mode == 2:
        return sign == 1
    if mode == 3:
        return sign == 0
    return False


def pack_finite(sign: int, exponent: int, mantissa: int) -> int:
    if mantissa == 0:
        return sign << 95
    magnitude = abs(exponent)
    digits = [int(character) for character in f"{mantissa:017d}"]
    result = sign << 95
    result |= int(exponent < 0) << 94
    result |= ((magnitude // 100) % 10) << 88
    result |= ((magnitude // 10) % 10) << 84
    result |= (magnitude % 10) << 80
    result |= ((magnitude // 1000) % 10) << 76
    result |= digits[0] << 64
    for index, digit in enumerate(digits[1:]):
        result |= digit << ((15 - index) * 4)
    return result


def reference(source: int, k_factor: int, mode: int) -> tuple[int, int]:
    sign = (source >> 79) & 1
    exponent_field = (source >> 64) & 0x7FFF
    significand = source & ((1 << 64) - 1)
    k_status = 0x20 if k_factor > 17 else 0
    if exponent_field == 0x7FFF:
        result = (sign << 95) | (0x7FFF << 80)
        if significand & ((1 << 63) - 1):
            result |= significand | (1 << 62)
            status = 0x40 if (significand & (1 << 62)) == 0 else 0
        else:
            status = 0
        return result, status | k_status
    if significand == 0:
        return sign << 95, k_status

    value = finite_value(source)
    magnitude = abs(value)
    _, _, binary_power = finite_fields(source)
    binary_logarithm = significand.bit_length() - 1 + binary_power
    estimate = (binary_logarithm * LOG10_TWO_SCALED) // (1 << 32)
    exponent = decimal_exponent(magnitude, estimate)

    status = 0
    selected_k = k_factor
    if selected_k > 17:
        selected_k = 17
        status |= 0x20
    if selected_k > 0:
        displayed_digits = selected_k
    else:
        displayed_digits = exponent + 1 - selected_k
    displayed_digits = max(1, min(17, displayed_digits))
    result_exponent = max(exponent, selected_k) if selected_k <= 0 else exponent
    least_significant_exponent = result_exponent + 1 - displayed_digits
    scaled = magnitude / power_of_ten(least_significant_exponent)
    quotient, remainder = divmod(scaled.numerator, scaled.denominator)
    if rounding_increment(mode, sign, quotient, remainder,
                          scaled.denominator):
        quotient += 1
    if quotient == 10 ** displayed_digits:
        quotient //= 10
        result_exponent += 1
    mantissa = quotient * 10 ** (17 - displayed_digits)
    if remainder != 0:
        status |= 0x02
    if mantissa == 0:
        result_exponent = 0
    if abs(result_exponent) > 999:
        status |= 0x20
    return pack_finite(sign, result_exponent, mantissa), status


def approximate_scale(source: int, scale_exponent: int) -> tuple[int, int]:
    _, significand, binary_power = finite_fields(source)
    decimal_power = 17 - scale_exponent
    exponent = abs(decimal_power)
    chunk = exponent // SEGMENT_SIZE * SEGMENT_SIZE
    residual = exponent - chunk
    chunk_multiplier, chunk_bits = normalized_power(
        chunk, decimal_power < 0)
    residual_multiplier, residual_bits = normalized_power(
        residual, decimal_power < 0)
    product = significand * chunk_multiplier * residual_multiplier
    if decimal_power >= 0:
        shift = (binary_power + decimal_power + chunk_bits + residual_bits -
                 2 * POWER_PRECISION)
    else:
        shift = (binary_power + decimal_power - chunk_bits - residual_bits +
                 4 - 2 * POWER_PRECISION)
    if shift >= 0:
        return product << shift, shift
    return product >> -shift, shift


def expected_latency(source: int, k_factor: int) -> int:
    exponent_field = (source >> 64) & 0x7FFF
    significand = source & ((1 << 64) - 1)
    if exponent_field == 0x7FFF or significand == 0:
        return 0
    _, _, binary_power = finite_fields(source)
    binary_logarithm = significand.bit_length() - 1 + binary_power
    estimate = (binary_logarithm * LOG10_TWO_SCALED) // (1 << 32)
    attempts = [estimate]
    scaled, _ = approximate_scale(source, estimate)
    if scaled < 10 ** 17:
        estimate -= 1
        attempts.append(estimate)
    elif scaled >= 10 ** 18:
        estimate += 1
        attempts.append(estimate)

    selected_k = min(k_factor, 17)
    if selected_k <= 0 and estimate < selected_k:
        attempts.append(selected_k)
    alignment_cycles = []
    for exponent in attempts:
        shift = approximate_scale(source, exponent)[1]
        if shift < 0:
            alignment_cycles.append(max(64, min(-shift, 448)))
        else:
            alignment_cycles.append(64)
    return 79 + sum(261 + cycles for cycles in alignment_cycles)


def extended_from_fraction(value: Fraction) -> int:
    return round_binary(value, 64, 0)[0]


def source_values() -> list[tuple[int, int, int]]:
    vectors = []
    specials = [
        0,
        1 << 79,
        (0x7FFF << 64) | (1 << 63),
        (1 << 79) | (0x7FFF << 64) | (1 << 63),
        (0x7FFF << 64) | 0xC123456789ABCDEF,
        (1 << 79) | (0x7FFF << 64) | 0x8123456789ABCDEF,
    ]
    for source in specials:
        for k_factor in (17, 18, 63):
            for mode in range(4):
                vectors.append((source, k_factor, mode))

    manual_value = extended_from_fraction(Fraction(12345678765, 1000000))
    for k_factor in range(-64, 64):
        for mode in range(4):
            vectors.append((manual_value, k_factor, mode))
            vectors.append((manual_value | (1 << 79), k_factor, mode))

    directed = [
        extended_from_fraction(Fraction(1, 10)),
        extended_from_fraction(Fraction(1, 2)),
        extended_from_fraction(Fraction(5, 2)),
        extended_from_fraction(Fraction(99999999999999995, 10)),
        extended_from_fraction(Fraction(99999999999999996, 10)),
        (1 << 63),
        (1 << 64) | (1 << 63),
        (0x7FFE << 64) | ((1 << 64) - 1),
        (0x4000 << 64) | 1,
    ]
    selected_k = [-64, -17, -5, -1, 0, 1, 3, 5, 16, 17, 18, 63]
    for source in directed:
        for k_factor in selected_k:
            for mode in range(4):
                vectors.append((source, k_factor, mode))
                vectors.append((source | (1 << 79), k_factor, mode))

    # Cover every residual-table address in both directions.
    for exponent in range(128):
        for direction in (-1, 1):
            decimal_power = direction * exponent
            scale_exponent = 17 - decimal_power
            source = extended_from_fraction(
                Fraction(3, 2) * power_of_ten(scale_exponent))
            vectors.append((source, 17, (exponent + direction) & 3))

    # Cover every segmented exponent chunk in both directions.
    for chunk in range(39):
        for direction in (-1, 1):
            decimal_power = direction * chunk * SEGMENT_SIZE
            scale_exponent = 17 - decimal_power
            source = extended_from_fraction(
                Fraction(3, 2) * power_of_ten(scale_exponent))
            vectors.append((source, 17, chunk & 3))

    rng = random.Random(0x68882BCD)
    for _ in range(4096):
        exponent_field = rng.randrange(0x7FFF)
        significand = rng.randrange(1, 1 << 64)
        source = ((rng.randrange(2) << 79) | (exponent_field << 64) |
                  significand)
        vectors.append((source, rng.randrange(-64, 64), rng.randrange(4)))
    return vectors


def emit_testbench() -> None:
    vectors = []
    for source, k_factor, mode in source_values():
        expected_result, expected_status = reference(source, k_factor, mode)
        vectors.append((source, k_factor, mode, expected_result,
                        expected_status, expected_latency(source, k_factor)))

    mode_names = [
        "FPU_ROUND_NEAREST",
        "FPU_ROUND_ZERO",
        "FPU_ROUND_MINUS_INFINITY",
        "FPU_ROUND_PLUS_INFINITY",
    ]
    print("""library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;
use work.TG68K_FPU_Pack.all;

entity tb_tg68k_fpu_extended_to_packed_differential is
end entity;

architecture test of tb_tg68k_fpu_extended_to_packed_differential is
    constant CLK_PERIOD : time := 10 ns;
    type vector_t is record
        source_value : fpu_extended_t;
        k_factor_value : std_logic_vector(6 downto 0);
        mode_value : fpu_rounding_mode_t;
        expected_result : std_logic_vector(95 downto 0);
        expected_status : std_logic_vector(7 downto 0);
        expected_cycles : natural;
    end record;
    type vector_array_t is array (natural range <>) of vector_t;
    constant vectors : vector_array_t := (""")
    for index, (source, k_factor, mode, result, status, cycles) in enumerate(vectors):
        suffix = "," if index + 1 < len(vectors) else ""
        encoded_k = k_factor & 0x7F
        print(f'        (x"{source:020X}", "{encoded_k:07b}", '
              f'{mode_names[mode]}, x"{result:024X}", x"{status:02X}", '
              f'{cycles}){suffix}')
    print(f"""    );
    signal clk : std_logic := '0';
    signal nReset : std_logic := '0';
    signal start : std_logic := '0';
    signal source : fpu_extended_t := (others => '0');
    signal k_factor : std_logic_vector(6 downto 0) := (others => '0');
    signal rounding_mode : fpu_rounding_mode_t := FPU_ROUND_NEAREST;
    signal result : std_logic_vector(95 downto 0);
    signal exception_status : std_logic_vector(7 downto 0);
    signal done : std_logic;
begin
    clk <= not clk after CLK_PERIOD / 2;

    dut : entity work.TG68K_FPU_Extended_To_Packed
        port map(
            clk => clk,
            nReset => nReset,
            start => start,
            source => source,
            k_factor => k_factor,
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
            k_factor <= vectors(index).k_factor_value;
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
                assert cycles < 2500
                    report "packed output vector " & integer'image(index) &
                        " conversion timeout" severity failure;
            end loop;
            assert cycles = vectors(index).expected_cycles
                report "packed output vector " & integer'image(index) &
                    " latency mismatch: got " & integer'image(cycles) &
                    " expected " & integer'image(vectors(index).expected_cycles)
                severity failure;
            assert result = vectors(index).expected_result and
                exception_status = vectors(index).expected_status
                report "packed output vector " & integer'image(index) &
                    " mismatch: source=" & to_hstring(source) &
                    " k=" & integer'image(to_integer(signed(k_factor))) &
                    " result=" & to_hstring(result) &
                    " expected=" & to_hstring(vectors(index).expected_result) &
                    " status=" & to_hstring(exception_status) &
                    " expected_status=" &
                    to_hstring(vectors(index).expected_status)
                severity failure;
            wait until rising_edge(clk);
            wait for 1 ns;
        end loop;
        report "PASS: {len(vectors)} exact packed-decimal output vectors"
            severity note;
        stop;
    end process;
end architecture;
""")


if __name__ == "__main__":
    emit_testbench()
