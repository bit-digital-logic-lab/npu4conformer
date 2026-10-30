#!/usr/bin/env python3
"""Independent golden model for the matrix -> epilogue -> A16 fusion test.

This model is written from the documented numeric contract, not from the RTL:
  * integer C48: A16 * W7(S/J/M) with positions nibbles, clip saturation,
    32-bit product wrap and INT48 two's-complement accumulation in ascending K;
  * I48 -> binary32: exact integer, round-to-nearest-even, subnormals FTZ;
  * FMA: y = x*scale + bias with ONE binary32 rounding (exact product+add then
    a single RNE/FTZ pack);
  * mul+add baseline: round(x*scale) then round(+bias), i.e. two roundings;
  * F32 -> I16: RNE and [-32768,32767] saturation, |x|<0.5 -> 0.

The two numeric contracts are deliberately separate: the fused DUT is expected
to match fma_a16 exactly, while fma_a16 may differ from muladd_a16.  A mismatch
between fma_a16 and muladd_a16 is NOT a DUT failure.
"""
import argparse
import json
import struct
from fractions import Fraction
from pathlib import Path

MASK16 = 0xFFFF
MASK20 = 0xFFFFF
MASK32 = 0xFFFFFFFF
MASK48 = 0xFFFFFFFFFFFF
F32_INF = 0x7F800000


# ---------------------------------------------------------------------------
# integer C48 contract
# ---------------------------------------------------------------------------
def to_s16(x: int) -> int:
    x &= MASK16
    return x - 0x10000 if x & 0x8000 else x


def to_s32(x: int) -> int:
    x &= MASK32
    return x - 0x100000000 if x & 0x80000000 else x


def to_s48(x: int) -> int:
    x &= MASK48
    return x - 0x1000000000000 if x & 0x800000000000 else x


def abs16(a: int) -> int:
    a = to_s16(a)
    return (-a) & MASK16 if a < 0 else a


def product32(a: int, w: int, positions: int, clip: int) -> int:
    w &= 0x7F
    sign = (w >> 6) & 1
    j = (w >> 4) & 3
    m = w & 0xF
    p = (positions >> (4 * j)) & 0xF
    sat = bool(clip and p == 12 and m >= 8)
    mag = abs16(a)
    m_eff = 8 if sat else m
    raw = (mag * m_eff) & MASK20
    aligned = (raw << p) & MASK32
    magnitude = (aligned - (mag if sat else 0)) & MASK32
    signed_magnitude = to_s32(magnitude)
    prod = -signed_magnitude if ((sign ^ (1 if to_s16(a) < 0 else 0)) & 1) else signed_magnitude
    return to_s32(prod)


def accumulate(sum48: int, prod32: int) -> int:
    return to_s48(to_s48(sum48) + to_s32(prod32))


# ---------------------------------------------------------------------------
# exact binary32 helpers (no numpy / no host-float rounding assumptions)
# ---------------------------------------------------------------------------
def f32_decode(bits: int) -> Fraction:
    """Decode a finite binary32 bit pattern to an exact Fraction (FTZ on input)."""
    sign = -1 if (bits >> 31) & 1 else 1
    exp = (bits >> 23) & 0xFF
    man = bits & 0x7FFFFF
    if exp == 0:
        return Fraction(0)                      # FTZ: subnormal input is zero
    if exp == 0xFF:
        raise ValueError("non-finite input 0x%08x" % bits)
    value = Fraction((1 << 23) | man, 1 << 23) * (Fraction(2) ** (exp - 127))
    return sign * value


def round_even(q: Fraction) -> int:
    """Round a non-negative (or any) Fraction to the nearest integer, ties even."""
    n = q.numerator
    d = q.denominator
    floor = n // d
    rem = n - floor * d
    twice = rem * 2
    if twice > d or (twice == d and (floor & 1)):
        return floor + 1
    return floor


def frac_to_f32(x: Fraction, negative_zero: bool = False) -> int:
    """Round an exact Fraction to binary32 with RNE and FTZ on underflow."""
    if x == 0:
        return 0x80000000 if negative_zero else 0
    sign = 1 if x < 0 else 0
    ax = -x if x < 0 else x
    # exponent e with 2^e <= ax < 2^(e+1)
    e = ax.numerator.bit_length() - ax.denominator.bit_length()
    if Fraction(2) ** e > ax:
        e -= 1
    elif Fraction(2) ** (e + 1) <= ax:
        e += 1
    if e < -126:
        return sign << 31                      # FTZ underflow
    if e > 127:
        return (sign << 31) | F32_INF          # overflow to infinity
    scaled = ax / (Fraction(2) ** e)           # [1,2)
    m = round_even(scaled * (1 << 23))         # 24-bit significand
    if m >= (1 << 24):
        m >>= 1
        e += 1
        if e > 127:
            return (sign << 31) | F32_INF
    exp_field = e + 127
    mant = m - (1 << 23)
    return (sign << 31) | (exp_field << 23) | mant


def f32_mul(a: int, b: int) -> int:
    """Correctly-rounded binary32 multiply through exact rationals."""
    if ((a >> 23) & 0xFF) == 0xFF or ((b >> 23) & 0xFF) == 0xFF:
        return 0x7FC00000
    return frac_to_f32(f32_decode(a) * f32_decode(b))


def f32_fma(a: int, b: int, c: int) -> int:
    """Single-rounding y = a*b + c (finite normals; FTZ inputs)."""
    if ((a >> 23) & 0xFF) == 0xFF or ((b >> 23) & 0xFF) == 0xFF:
        return 0x7FC00000
    exact = f32_decode(a) * f32_decode(b) + f32_decode(c)
    return frac_to_f32(exact)


def f32_muladd(a: int, b: int, c: int) -> int:
    """Two-rounding baseline: round(a*b), then round(+c)."""
    return frac_to_f32(f32_decode(f32_mul(a, b)) + f32_decode(c))


def i48_to_f32(v: int) -> int:
    if v == 0:
        return 0
    return frac_to_f32(Fraction(v))


def f32_to_i16(bits: int) -> int:
    sign = (bits >> 31) & 1
    exp = (bits >> 23) & 0xFF
    man = bits & 0x7FFFFF
    if exp == 0xFF and man:
        return 0
    if exp == 0:
        return 0
    if exp == 0xFF:
        return 0x8000 if sign else 0x7FFF
    e = exp - 127
    if e < -1:
        return 0
    if e >= 31:
        return 0x8000 if sign else 0x7FFF
    exact = f32_decode(bits)
    mag = round_even(abs(exact))
    val = -mag if sign else mag
    if val > 32767:
        return 0x7FFF
    if val < -32768:
        return 0x8000
    return val & 0xFFFF


# ---------------------------------------------------------------------------
# memory fixture decoding
# ---------------------------------------------------------------------------
def read_hex_words(path: Path):
    return [int(line.strip(), 16) for line in path.read_text().splitlines() if line.strip()]


def mem_byte(words, base: int, addr: int) -> int:
    off = addr - base
    word = words[off // 16]
    lane = off % 16
    return (word >> (lane * 8)) & 0xFF


def read_region(words, base: int, addr: int, n: int) -> bytes:
    return bytes(mem_byte(words, base, addr + i) for i in range(n))


def matrix_gold(manifest, words):
    M, N, K = manifest["M"], manifest["N"], manifest["K"]
    positions = int(manifest["positions"], 0)
    clip = manifest["clip"]
    abase = int(manifest["A_BASE"], 0)
    bbase = int(manifest["B_BASE"], 0)
    cbase = int(manifest["C_BASE"], 0)
    mem_base = 0x03000000
    nbr, nbc, nbk = (M + 31) // 32, (N + 31) // 32, (K + 31) // 32

    def load_a(br, bk):
        raw = read_region(words, mem_base, abase + (br * nbk + bk) * 2048, 2048)
        return [[struct.unpack_from("<h", raw, (r * 32 + k) * 2)[0]
                 for k in range(32)] for r in range(32)]

    def load_w(bk, bc):
        raw = read_region(words, mem_base, bbase + (bk * nbc + bc) * 1024, 1024)
        return [[raw[k * 32 + c] for c in range(32)] for k in range(32)]

    def load_c(br, bc):
        raw = read_region(words, mem_base, cbase + (br * nbc + bc) * 6144, 6144)
        vals = []
        for i in range(1024):
            b = raw[i * 6:(i + 1) * 6]
            u = int.from_bytes(b, "little")
            vals.append(to_s48(u))
        return vals

    tiles = []
    for br in range(nbr):
        for bc in range(nbc):
            c = load_c(br, bc) if manifest["C_VALID"] else [0] * 1024
            for bk in range(nbk):
                A = load_a(br, bk)
                W = load_w(bk, bc)
                for r in range(32):
                    row = br * 32 + r
                    for cc in range(32):
                        col = bc * 32 + cc
                        if row >= M or col >= N:
                            continue
                        s = 0
                        for k in range(32):
                            kk = bk * 32 + k
                            if kk >= K:
                                continue
                            s = accumulate(s, product32(A[r][k], W[k][cc], positions, clip))
                        c[r * 32 + cc] = to_s48(c[r * 32 + cc] + s)
            tiles.append(c)
    return tiles, nbr, nbc, nbk


def epilogue_gold(c48, scale, bias, fma_mode, relu_en):
    fma_out = []
    muladd_out = []
    for v in c48:
        x = i48_to_f32(v)
        if fma_mode == 0:
            f = f32_fma(x, 0x3F800000, 0x00000000)
            m = f32_muladd(x, 0x3F800000, 0x00000000)
        elif fma_mode == 2:
            f = f32_fma(x, scale, 0x00000000)
            m = f32_muladd(x, scale, 0x00000000)
        else:
            f = f32_fma(x, scale, bias)
            m = f32_muladd(x, scale, bias)
        if relu_en:
            if ((f >> 23) & 0xFF) == 0xFF and (f & 0x7FFFFF):
                f = 0x7FC00000
            elif (f >> 31) & 1 or (f & 0x7FFFFFFF) == 0:
                f = 0
            if ((m >> 23) & 0xFF) == 0xFF and (m & 0x7FFFFF):
                m = 0x7FC00000
            elif (m >> 31) & 1 or (m & 0x7FFFFFFF) == 0:
                m = 0
        fma_out.append(f32_to_i16(f))
        muladd_out.append(f32_to_i16(m))
    return fma_out, muladd_out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dir", required=True)
    ap.add_argument("--scale", type=lambda x: int(x, 0), default=0x3F000000)
    ap.add_argument("--bias", type=lambda x: int(x, 0), default=0x3F800000)
    ap.add_argument("--fma", type=int, default=1)
    ap.add_argument("--relu", type=int, default=0)
    ap.add_argument("--out", default=None)
    a = ap.parse_args()
    d = Path(a.dir)
    manifest = json.loads((d / "manifest.json").read_text())
    words = read_hex_words(d / "init.hex")
    tiles, nbr, nbc, nbk = matrix_gold(manifest, words)

    fma_all, muladd_all = [], []
    for c in tiles:
        f, m = epilogue_gold(c, a.scale, a.bias, a.fma, a.relu)
        fma_all.extend(f)
        muladd_all.extend(m)

    diff = sum(1 for x, y in zip(fma_all, muladd_all) if x != y)
    sat = sum(1 for x in fma_all if x in (0, 0xFFFF))
    out = Path(a.out) if a.out else (d / "gold_a16.hex")
    out.write_text("".join("%04x\n" % v for v in fma_all))
    (d / "gold_muladd_a16.hex").write_text("".join("%04x\n" % v for v in muladd_all))
    report = {
        "dir": str(d),
        "M": manifest["M"], "N": manifest["N"], "K": manifest["K"],
        "tiles": nbr * nbc, "values": len(fma_all),
        "scale": "0x%08x" % a.scale, "bias": "0x%08x" % a.bias,
        "fma_mode": a.fma, "relu": a.relu,
        "fma_vs_muladd_diff": diff,
        "fma_zero_or_ff_count": sat,
        "gold_a16": str(out),
        "gold_muladd_a16": str(d / "gold_muladd_a16.hex"),
    }
    (d / "gold_report.json").write_text(json.dumps(report, indent=1) + "\n")
    print(json.dumps(report, indent=1))


if __name__ == "__main__":
    main()
