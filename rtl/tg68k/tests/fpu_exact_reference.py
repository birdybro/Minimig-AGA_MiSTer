from fractions import Fraction
from math import isqrt


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


def extended_condition_codes(value: int) -> int:
    sign = (value >> 79) & 1
    exponent = (value >> 64) & 0x7FFF
    significand = value & ((1 << 64) - 1)
    if exponent == 0x7FFF:
        if significand & ((1 << 63) - 1):
            return (sign << 3) | 1
        return (sign << 3) | 2
    if exponent == 0 and significand == 0:
        return (sign << 3) | 4
    return sign << 3


def extract_extended(source: int, get_exponent: bool) -> tuple[int, int, int]:
    sign = (source >> 79) & 1
    exponent_field = (source >> 64) & 0x7FFF
    significand = source & ((1 << 64) - 1)

    if exponent_field == 0x7FFF:
        if significand & ((1 << 63) - 1):
            result = source | (1 << 62)
            status = 0x40 if (significand & (1 << 62)) == 0 else 0
        else:
            result = (0x7FFF << 64) | ((1 << 64) - 1)
            status = 0x20
    elif significand == 0:
        result = sign << 79
        status = 0
    else:
        leading_position = significand.bit_length() - 1
        normalized = significand << (63 - leading_position)
        unbiased_exponent = (
            1 - EXPONENT_BIAS if exponent_field == 0
            else exponent_field - EXPONENT_BIAS
        ) - (63 - leading_position)
        if get_exponent:
            if unbiased_exponent == 0:
                result = 0
            else:
                result_sign = int(unbiased_exponent < 0)
                magnitude = abs(unbiased_exponent)
                integer_exponent = magnitude.bit_length() - 1
                result = encode_extended(
                    result_sign, integer_exponent,
                    magnitude << (63 - integer_exponent))
        else:
            result = encode_extended(sign, 0, normalized)
        status = 0
    return result, extended_condition_codes(result), status


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


def round_square_root(value: Fraction, precision: int,
                      mode: int) -> tuple[int, int, int]:
    if value <= 0:
        raise ValueError("square-root reference requires a positive operand")

    source_exponent = value.numerator.bit_length() - value.denominator.bit_length()
    if value < power_of_two(source_exponent):
        source_exponent -= 1
    result_exponent = source_exponent // 2
    scaled_squared = value * power_of_two(
        2 * ((precision - 1) - result_exponent))
    quotient = isqrt(scaled_squared.numerator // scaled_squared.denominator)
    inexact = quotient * quotient * scaled_squared.denominator != \
        scaled_squared.numerator

    increment = False
    if inexact:
        if mode == 0:
            midpoint = 2 * quotient + 1
            comparison = 4 * scaled_squared.numerator - \
                midpoint * midpoint * scaled_squared.denominator
            increment = comparison > 0 or (comparison == 0 and
                                            (quotient & 1) != 0)
        elif mode == 3:
            increment = True
    if increment:
        quotient += 1
    if quotient == 1 << precision:
        quotient >>= 1
        result_exponent += 1

    significand = quotient << (64 - precision)
    encoded = encode_extended(0, result_exponent, significand)
    return encoded, 0, 0x02 if inexact else 0


def round_integral(value: Fraction, precision: int, mode: int,
                   force_round_zero: bool) -> tuple[int, int, int]:
    effective_mode = 1 if force_round_zero else mode
    sign = int(value < 0)
    magnitude = abs(value)
    quotient, remainder = divmod(magnitude.numerator, magnitude.denominator)
    inexact = remainder != 0
    if rounding_increment(effective_mode, sign, quotient, remainder,
                          magnitude.denominator):
        quotient += 1
    integral = -quotient if sign else quotient
    if integral == 0:
        return sign << 79, (sign << 3) | 4, 0x02 if inexact else 0
    result, condition_codes, status = round_binary(
        Fraction(integral), precision, effective_mode)
    if inexact:
        status |= 0x02
    return result, condition_codes, status


def round_scale(source: Fraction, destination: Fraction, precision: int,
                mode: int) -> tuple[int, int, int]:
    magnitude = abs(source)
    scale_factor = magnitude.numerator // magnitude.denominator
    if source < 0:
        scale_factor = -scale_factor
    return round_binary(destination * power_of_two(scale_factor),
                        precision, mode)


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
