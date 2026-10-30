"""Independent exact reference model for the V0.23 numeric audit.

Deliberately does NOT import or reuse gemini_epilogue/golden_epilogue.py or
gemini_approx/golden/approx_model.py.  All FP32 rounding is done with Python
integers / Fractions so that the reference is independent of the DUT and of
the vendor "golden" scripts.

Semantics implemented here (stated explicitly, so mismatches are diagnosable):
  * binary32, round-to-nearest-even (RNE)
  * subnormal inputs/outputs flushed to signed zero (FTZ) by default
  * NaN canonicalised to 0x7fc00000
  * i48 -> f32 is an exact integer conversion, RNE
  * FMA is a true single-rounding fused multiply-add: round(x*s + b) once
  * f32 -> i16 is RNE with saturation to [-32768, 32767]; NaN -> 0
"""

from fractions import Fraction
from decimal import Decimal, getcontext
import math

getcontext().prec = 90

FP32_QNAN = 0x7FC00000
FP32_POS_INF = 0x7F800000
FP32_NEG_INF = 0xFF800000
FP32_POS_ZERO = 0x00000000
FP32_NEG_ZERO = 0x80000000

MAX_FINITE = (1 << 24) - 1  # significand of max finite
# midpoint between max finite (=(2^24-1)*2^104) and 2^128
OVERFLOW_MID = Fraction((1 << 25) - 1) * (1 << 103)


def is_nan(bits):
    return ((bits >> 23) & 0xFF) == 0xFF and (bits & 0x7FFFFF) != 0


def is_inf(bits):
    return ((bits >> 23) & 0xFF) == 0xFF and (bits & 0x7FFFFF) == 0


def is_zero(bits):
    return (bits & 0x7FFFFFFF) == 0


def is_sub(bits):
    return ((bits >> 23) & 0xFF) == 0 and (bits & 0x7FFFFF) != 0


def f32_to_frac(bits, ftz=True):
    """Finite FP32 bits -> exact Fraction.  Raises on NaN/Inf."""
    if is_nan(bits) or is_inf(bits):
        raise ValueError("non-finite")
    sign = -1 if (bits >> 31) else 1
    exp = (bits >> 23) & 0xFF
    frac = bits & 0x7FFFFF
    if exp == 0:
        if ftz:
            return Fraction(0)
        return sign * Fraction(frac, 1 << 149)
    return sign * Fraction((1 << 23) + frac) * Fraction(2) ** (exp - 150)


def _floor_log2(x):
    """floor(log2(x)) for a positive Fraction, exact."""
    n, d = x.numerator, x.denominator
    e = n.bit_length() - d.bit_length()
    if e >= 0:
        if n < (d << e):
            e -= 1
    else:
        if (n << (-e)) < d:
            e -= 1
    return e


def _rne_int(x):
    """Round a non-negative Fraction to nearest integer, ties to even."""
    n, d = x.numerator, x.denominator
    q, r = divmod(n, d)
    twice = 2 * r
    if twice > d or (twice == d and (q & 1)):
        q += 1
    return q


def round_f32(value, ftz=True, zero_sign=0):
    """Round an exact Fraction to binary32 bits (RNE, FTZ by default)."""
    if value == 0:
        return (zero_sign << 31) & 0x80000000
    sign = 1 if value < 0 else 0
    v = abs(value)
    if v >= OVERFLOW_MID:
        return (sign << 31) | FP32_POS_INF
    e = _floor_log2(v)
    if e < -126:
        if ftz:
            return (sign << 31) | 0
        scaled = v * (1 << 149)
        n = _rne_int(scaled)
        if n == 0:
            return (sign << 31) | 0
        if n >= (1 << 23):
            return (sign << 31) | (1 << 23)
        return (sign << 31) | n
    shift = 23 - e
    scaled = v * (1 << shift) if shift >= 0 else v / (1 << (-shift))
    n = _rne_int(scaled)
    if n == (1 << 24):
        n >>= 1
        e += 1
    if e > 127:
        return (sign << 31) | FP32_POS_INF
    exp = e + 127
    frac = n - (1 << 23)
    return (sign << 31) | (exp << 23) | frac


def i48_to_f32_bits(v):
    return round_f32(Fraction(int(v)))


def fma_bits(xb, sb, bb, ftz=True):
    """True fused multiply-add, one RNE rounding.  FTZ on inputs/outputs."""
    # NaN propagation (canonical qNaN)
    if is_nan(xb) or is_nan(sb) or is_nan(bb):
        return FP32_QNAN
    x_inf, s_inf, b_inf = is_inf(xb), is_inf(sb), is_inf(bb)
    sx, ss, sb_sign = xb >> 31, sb >> 31, bb >> 31
    # inf * 0 -> NaN
    if (x_inf and is_zero(sb)) or (s_inf and is_zero(xb)):
        return FP32_QNAN
    if x_inf or s_inf:
        p_sign = sx ^ ss
        if b_inf and (sb_sign != p_sign):
            return FP32_QNAN  # inf + (-inf)
        return (p_sign << 31) | FP32_POS_INF
    if b_inf:
        return (sb_sign << 31) | FP32_POS_INF
    x = f32_to_frac(xb, ftz)
    s = f32_to_frac(sb, ftz)
    b = f32_to_frac(bb, ftz)
    prod = x * s
    exact = prod + b
    if exact == 0:
        # IEEE: exact zero sum of opposite-sign values is +0; -0 only if both
        # addends are -0 (or a single -0 operand with other +0).
        if prod == 0 and b == 0:
            zsign = 1 if ((xb >> 31) ^ (sb >> 31)) and (bb >> 31) else 0
            if (xb >> 31) ^ (sb >> 31):
                zsign = 1 if (bb >> 31) else 0
            else:
                zsign = 1 if (bb >> 31) else 0
            return (zsign << 31) | 0
        return FP32_POS_ZERO
    return round_f32(exact, ftz)


def f32_to_i16(bits):
    """RNE + saturation to signed 16-bit.  NaN -> 0, +-Inf -> clamp."""
    sign = bits >> 31
    exp = (bits >> 23) & 0xFF
    frac = bits & 0x7FFFFF
    if exp == 0xFF:
        if frac:
            return 0
        return -32768 if sign else 32767
    if exp == 0:
        v = Fraction(frac, 1 << 149)
    else:
        v = Fraction((1 << 23) + frac) * Fraction(2) ** (exp - 150)
    if sign:
        v = -v
    # Values this large always clamp; avoid huge Fraction arithmetic.
    if v >= 32768:
        return 32767
    if v <= -32769:
        return -32768
    if v >= 0:
        q = _rne_int(v)
    else:
        q = -_rne_int(-v)
    if q > 32767:
        return 32767
    if q < -32768:
        return -32768
    return q


def f32_bits_to_decimal(bits, ftz=True):
    """Exact Decimal value of finite FP32 bits."""
    f = f32_to_frac(bits, ftz)
    return Decimal(f.numerator) / Decimal(f.denominator)


def true_div_decimal(a_bits, b_bits, ftz=True):
    return f32_bits_to_decimal(a_bits, ftz) / f32_bits_to_decimal(b_bits, ftz)


def true_sqrt_decimal(a_bits, ftz=True):
    return f32_bits_to_decimal(a_bits, ftz).sqrt()


def true_rsqrt_decimal(a_bits, ftz=True):
    return Decimal(1) / f32_bits_to_decimal(a_bits, ftz).sqrt()


def rel_error(result_bits, true_decimal, ftz=True):
    """Relative error of a finite FP32 result vs an exact Decimal value."""
    if is_nan(result_bits) or is_inf(result_bits):
        return None
    got = f32_bits_to_decimal(result_bits, ftz)
    if true_decimal == 0:
        return Decimal(0) if got == 0 else None
    return abs((got - true_decimal) / true_decimal)


def ulp_distance(a_bits, b_bits):
    """Ordered-integer distance between two finite FP32 values (None on special)."""
    if is_nan(a_bits) or is_nan(b_bits) or is_inf(a_bits) or is_inf(b_bits):
        return None

    def key(x):
        return x if not (x >> 31) else 0x80000000 - (x & 0x7FFFFFFF)

    return abs(key(a_bits) - key(b_bits))


def f32_str(bits):
    if is_nan(bits):
        return "NaN"
    if is_inf(bits):
        return "-Inf" if bits >> 31 else "+Inf"
    return f"{f32_to_frac(bits, ftz=False)!s}"


if __name__ == "__main__":
    # quick self-checks / known counterexamples
    assert i48_to_f32_bits(0) == 0
    assert i48_to_f32_bits(1) == 0x3F800000
    assert i48_to_f32_bits(-1) == 0xBF800000
    assert fma_bits(0x3F800001, 0x3FC00000, 0) == 0x3FC00002, hex(
        fma_bits(0x3F800001, 0x3FC00000, 0)
    )
    assert f32_to_i16(0x3FC00000) == 2  # 1.5 -> 2
    assert f32_to_i16(0x40200000) == 2  # 2.5 -> 2
    assert f32_to_i16(0x40600000) == 4  # 3.5 -> 4
    print("refmodel self-check OK")
