#!/usr/bin/env python3
"""Independent gold for the per-channel C48 -> FP32 -> A16 epilogue.

Contract (from ds_epilogue_channels/INTERFACE.md, implemented from the spec):
  x   = int48_to_f32_rne_ftz(c48)
  y   = fma_rne_ftz(x, scale[col], bias[col])     # one rounding
  z   = relu(y)                                   # NaN kept canonical, -0 -> +0
  fp32_out = z
  a16_out  = f32_to_i16_rne_sat(z)                # NaN -> 0
No RTL or worker golden code is imported.
"""
from fractions import Fraction
import sys
sys.path.insert(0, __file__.rsplit('/', 1)[0])
from fma_gold import round_f32, fma_bits, QNAN, INF


def i48_to_f32(v):
    if v == 0:
        return 0
    s = 1 if v < 0 else 0
    return round_f32(s, abs(int(v)), 0)


def _f32_frac(bits):
    s = -1 if (bits >> 31) else 1
    e = (bits >> 23) & 0xFF
    f = bits & 0x7FFFFF
    if e == 0xFF:
        return None
    if e == 0:
        return Fraction(0)
    return s * Fraction((1 << 23) + f) * (Fraction(2) ** (e - 150))


def _rne_int(x):
    n, d = x.numerator, x.denominator
    q, r = divmod(n, d)
    if 2 * r > d or (2 * r == d and (q & 1)):
        q += 1
    return q


def f32_to_i16(bits):
    if (bits & 0x7FFFFFFF) == INF or ((bits >> 23) & 0xFF) == 0xFF:
        if ((bits >> 23) & 0xFF) == 0xFF and (bits & 0x7FFFFF):
            return 0
        return -32768 if (bits >> 31) else 32767
    v = _f32_frac(bits)
    if v is None:
        return 0
    if v >= 32768:
        return 32767
    if v <= -32769:
        return -32768
    q = _rne_int(v) if v >= 0 else -_rne_int(-v)
    return max(-32768, min(32767, q))


def relu(bits):
    if ((bits >> 23) & 0xFF) == 0xFF and (bits & 0x7FFFFF):
        return QNAN
    if (bits & 0x7FFFFFFF) == 0:
        return 0
    if bits >> 31:
        return 0
    return bits


def epi_lane(c48, scale_bits, bias_bits, relu_en, fma_mode):
    x = i48_to_f32(c48)
    if fma_mode == 0:
        y = x
    elif fma_mode == 2:
        y = fma_bits(x, scale_bits, 0x00000000, project=False)
    else:
        y = fma_bits(x, scale_bits, bias_bits, project=False)
    z = relu(y) if relu_en else y
    return z, f32_to_i16(z)
