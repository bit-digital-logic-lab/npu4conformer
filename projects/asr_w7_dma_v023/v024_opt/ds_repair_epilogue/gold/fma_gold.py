#!/usr/bin/env python3
"""Implementation-independent binary32 FMA reference.

Written from the published contract only:
  result = round_rne(a*b + c) in binary32, with inputs and result FTZ
  (subnormal inputs are treated as zero; subnormal results flush to signed 0),
  IEEE-754 specials, quiet NaN = 0x7fc00000.

No RTL, no worker golden script, no numpy float fused ops are used.
Exact arithmetic is integer/Fraction based; a single RNE rounding is applied.
"""
from fractions import Fraction

QNAN = 0x7FC00000
INF = 0x7F800000


def is_nan(x):
    return (x >> 23) & 0xFF == 0xFF and (x & 0x7FFFFF) != 0


def is_inf(x):
    return (x & 0x7FFFFFFF) == INF


def is_zero(x):
    # FTZ: subnormal inputs are zero too
    return (x & 0x7FFFFFFF) == 0 or ((x >> 23) & 0xFF) == 0


def sign(x):
    return (x >> 31) & 1


def round_f32(sign_bit, n, e):
    """Round sign * n * 2**e (n>0 integer) to binary32, RNE, FTZ.

    Returns 32-bit int.
    """
    if n == 0:
        return sign_bit << 31
    k = n.bit_length() - 1          # value in [2**(k+e), 2**(k+e+1))
    shift = k - 23
    if shift >= 0:
        q = n >> shift
        if shift > 0:
            rem = n - (q << shift)
            half = 1 << (shift - 1)
            if rem > half or (rem == half and (q & 1)):
                q += 1
    else:
        q = n << (-shift)
    # q in [2**23, 2**24] after the possible carry
    e_unb = k + e
    if q == (1 << 24):
        q >>= 1
        e_unb += 1
    if e_unb > 127:
        return (sign_bit << 31) | INF
    if e_unb < -126:
        return sign_bit << 31          # FTZ
    expf = e_unb + 127
    mant = q - (1 << 23)
    return (sign_bit << 31) | (expf << 23) | mant


def fma_bits(a, b, c, project=False):
    # project=True reproduces the *declared V0.23 contract* (subnormal
    # flush for arithmetic, raw +/-0 only for special detection, and the
    # project's zero+zero sign rule = sign(c)).  project=False is strict IEEE.
    # ---- specials ----
    if is_nan(a) or is_nan(b) or is_nan(c):
        return QNAN
    inf_a, inf_b, inf_c = is_inf(a), is_inf(b), is_inf(c)
    if project:
        zero_a = ((a >> 23) & 0xFF) == 0
        zero_b = ((b >> 23) & 0xFF) == 0
        zero_c = ((c >> 23) & 0xFF) == 0
        raw_zero_a = (a & 0x7FFFFFFF) == 0
        raw_zero_b = (b & 0x7FFFFFFF) == 0
    else:
        zero_a, zero_b, zero_c = is_zero(a), is_zero(b), is_zero(c)
        raw_zero_a, raw_zero_b = zero_a, zero_b
    sp = sign(a) ^ sign(b)
    if (inf_a and raw_zero_b) or (inf_b and raw_zero_a):
        return QNAN
    if inf_a or inf_b:
        if inf_c and sign(c) != sp:
            return QNAN
        return (sp << 31) | INF
    if inf_c:
        return (sign(c) << 31) | INF

    # ---- zero cases (after FTZ) ----
    if (zero_a or zero_b) and zero_c:
        # strict IEEE: -0 only when both addends are -0.
        # project contract: sign(c).
        return (sign(c) if project else (sp & sign(c))) << 31
    if zero_a or zero_b:
        return c
    if zero_c:
        # exact product, still needs one rounding
        ma = (1 << 23) | (a & 0x7FFFFF)
        mb = (1 << 23) | (b & 0x7FFFFF)
        ea = ((a >> 23) & 0xFF) - 127
        eb = ((b >> 23) & 0xFF) - 127
        return round_f32(sp, ma * mb, ea + eb - 46)

    # ---- finite non-zero: exact integer accumulator ----
    ma = (1 << 23) | (a & 0x7FFFFF)
    mb = (1 << 23) | (b & 0x7FFFFF)
    mc = (1 << 23) | (c & 0x7FFFFF)
    ea = ((a >> 23) & 0xFF) - 127
    eb = ((b >> 23) & 0xFF) - 127
    ec = ((c >> 23) & 0xFF) - 127

    # product value = spa * ma*mb * 2**(ea+eb-46)
    # c value       = sc  * mc    * 2**(ec-23)
    e_prod = ea + eb - 46
    e_c = ec - 23
    e_min = min(e_prod, e_c)
    p_int = ma * mb
    if sp:
        p_int = -p_int
    c_int = mc
    if sign(c):
        c_int = -c_int
    total = (p_int << (e_prod - e_min)) + (c_int << (e_c - e_min))
    if total == 0:
        return 0  # exact cancellation -> +0 in RNE
    s = 1 if total < 0 else 0
    return round_f32(s, abs(total), e_min)


def main():
    import sys
    if len(sys.argv) != 4:
        print("usage: fma_gold.py <in.txt> <out.txt> <in|out>")
        return 2
    src, dst, fmt = sys.argv[1], sys.argv[2], sys.argv[3]
    if fmt == "in":
        with open(src) as f, open(dst, "w") as o:
            for line in f:
                line = line.strip()
                if not line or line.startswith("#"):
                    continue
                p = line.split()
                o.write("%s\n" % fma_bits(int(p[0], 16), int(p[1], 16), int(p[2], 16)))
        return 0
    with open(src) as f, open(dst, "w") as o:
        for line in f:
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            p = line.split()
            o.write("%s\n" % fma_bits(int(p[0], 16), int(p[1], 16), int(p[2], 16)))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
