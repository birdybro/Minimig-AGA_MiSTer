from fractions import Fraction


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
