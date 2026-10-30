#!/usr/bin/env python3
"""Independent binary32 FMA reference for ds_repair_fmaflush.

Written from the published project contract (INTERFACE.md section 3), not from
the RTL and not by importing any worker/adversarial-review golden model.

Contract implemented (project mode, the only gating mode):
  result = round_rne(a*b + c), binary32, single rounding;
  FTZ: exponent-field==0 inputs are zero, subnormal results flush to signed 0;
  NaN any -> 0x7fc00000; inf*0 raw-bit -> NaN; inf + (-inf) -> NaN;
  both addends FTZ-zero -> sign(c)  [the retained project special];
  exact non-zero cancellation -> +0;
  product FTZ-zero with finite non-zero c -> c bit-exact.

A ``strict`` switch is provided only to *measure* the documented AR-002
difference from strict IEEE; it is never used as the pass criterion.
"""
from fractions import Fraction

QNAN = 0x7FC00000
INF = 0x7F800000


def sign(x):
    return (x >> 31) & 1


def exp_field(x):
    return (x >> 23) & 0xFF


def frac(x):
    return x & 0x7FFFFF


def is_nan(x):
    return exp_field(x) == 0xFF and frac(x) != 0


def is_inf(x):
    return (x & 0x7FFFFFFF) == INF


def is_ftz_zero(x):
    return exp_field(x) == 0


def is_raw_zero(x):
    return (x & 0x7FFFFFFF) == 0


def _round_rne(sign_bit, n, e):
    """Round sign_bit * n * 2**e to binary32 (RNE, subnormal result -> 0)."""
    if n == 0:
        return sign_bit << 31
    k = n.bit_length() - 1
    e_unb = k + e
    shift = k - 23
    if shift > 0:
        q = n >> shift
        rem = n - (q << shift)
        half = 1 << (shift - 1)
        if rem > half or (rem == half and (q & 1)):
            q += 1
    elif shift == 0:
        q = n
    else:
        q = n << (-shift)
    if q == (1 << 24):
        q >>= 1
        e_unb += 1
    if e_unb > 127:
        return (sign_bit << 31) | INF
    if e_unb < -126:
        return sign_bit << 31
    ef = e_unb + 127
    return (sign_bit << 31) | (ef << 23) | (q & 0x7FFFFF)


def fma_bits(a, b, c, strict=False):
    if is_nan(a) or is_nan(b) or is_nan(c):
        return QNAN

    inf_a, inf_b, inf_c = is_inf(a), is_inf(b), is_inf(c)
    sp = sign(a) ^ sign(b)

    if strict:
        za, zb, zc = is_ftz_zero(a), is_ftz_zero(b), is_ftz_zero(c)
        raw_za, raw_zb = za, zb
    else:
        za, zb, zc = is_ftz_zero(a), is_ftz_zero(b), is_ftz_zero(c)
        raw_za, raw_zb = is_raw_zero(a), is_raw_zero(b)

    if inf_a or inf_b:
        if (inf_a and raw_zb) or (inf_b and raw_za):
            return QNAN                      # inf * 0 (project: raw zero)
        if inf_c and sign(c) != sp:
            return QNAN                      # inf + (-inf)
        return (sp << 31) | INF
    if inf_c:
        return (sign(c) << 31) | INF

    if za or zb:
        if zc:
            if strict:
                return (sp & sign(c)) << 31  # strict: -0 only if both -0
            return sign(c) << 31             # retained project special
        return c                             # x*0 + c -> c bit-exact
    if zc:
        ma = (1 << 23) | frac(a)
        mb = (1 << 23) | frac(b)
        ea = exp_field(a) - 127
        eb = exp_field(b) - 127
        return _round_rne(sp, ma * mb, ea + eb - 46)

    # exact integer accumulation, one final rounding
    ma = (1 << 23) | frac(a)
    mb = (1 << 23) | frac(b)
    mc = (1 << 23) | frac(c)
    ea = exp_field(a) - 127
    eb = exp_field(b) - 127
    ec = exp_field(c) - 127

    e_prod = ea + eb - 46
    e_c = ec - 23
    e_min = min(e_prod, e_c)
    p = ma * mb
    if sp:
        p = -p
    q = mc
    if sign(c):
        q = -q
    total = (p << (e_prod - e_min)) + (q << (e_c - e_min))
    if total == 0:
        return 0                             # exact cancellation -> +0
    s = 1 if total < 0 else 0
    return _round_rne(s, abs(total), e_min)


def fma_float(a, b, c, strict=False):
    """Fraction-exact cross-check helper (used by self-tests only)."""
    def val(x):
        e = exp_field(x)
        if e == 0:
            return Fraction(0)
        m = (1 << 23) | frac(x)
        return Fraction(-m if sign(x) else m) * Fraction(2) ** (e - 127 - 23)
    return val(a) * val(b) + val(c)


if __name__ == "__main__":
    import sys
    if len(sys.argv) != 2:
        print("usage: fma_gold_independent.py <a> <b> <c>")
        raise SystemExit(2)
    av, bv, cv = (int(t, 16) for t in sys.argv[1:4])
    print("%08x" % fma_bits(av, bv, cv))
