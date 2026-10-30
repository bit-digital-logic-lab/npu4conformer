#!/usr/bin/env python3
"""Independent integer golden model for the W7p8 / A16 / C48 contract.

This model is written from the arithmetic contract, not from the candidate RTL:
  W7 = {S, J[1:0], M[3:0]}
  P  = positions[4*J +: 4]
  SAT= clip && P == 12 && M >= 8
  MAG= |A|                         (A = -32768 -> 32768)
  RAW= MAG * (SAT ? 8 : M)         (20-bit unsigned product)
  AL = RAW << P                    (32-bit wrap)
  MG = AL - (SAT ? MAG : 0)        (32-bit wrap)
  PR = (S ^ sign(A)) ? -MG : MG    (32-bit wrap)
  SUM= (SUM + sign_extend(PR)) mod 2^48
No Verilog source is imported or evaluated.
"""

MASK16 = 0xFFFF
MASK20 = 0xFFFFF
MASK32 = 0xFFFFFFFF
MASK48 = 0xFFFFFFFFFFFF


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
    """|A| as an unsigned 16-bit magnitude; -32768 maps to 32768."""
    a = to_s16(a)
    return (-a) & MASK16 if a < 0 else a


def w7_fields(w: int, positions: int, clip: int):
    w &= 0x7F
    sign = (w >> 6) & 1
    j = (w >> 4) & 0x3
    m = w & 0xF
    p = (positions >> (4 * j)) & 0xF
    sat = bool(clip and p == 12 and m >= 8)
    return sign, j, m, p, sat


def product32(a: int, w: int, positions: int, clip: int) -> int:
    """Exact signed 32-bit product contribution, including 32-bit wrap."""
    sign, _j, m, p, sat = w7_fields(w, positions, clip)
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


def sum_products(items) -> int:
    """items: iterable of (a, w, positions, clip) accepted in order."""
    s = 0
    for a, w, positions, clip in items:
        s = accumulate(s, product32(a, w, positions, clip))
    return s


def matrix_tile(a_rows, w_rows, positions: int, clip: int):
    """Return [16][16] C48 sums for C[r][c] = sum_k A[r][k] * W7[k][c]."""
    assert len(a_rows) == 16 and all(len(row) == 32 for row in a_rows)
    assert len(w_rows) == 32 and all(len(row) == 16 for row in w_rows)
    out = [[0] * 16 for _ in range(16)]
    for r in range(16):
        for c in range(16):
            s = 0
            for k in range(32):
                s = accumulate(s, product32(a_rows[r][k], w_rows[k][c], positions, clip))
            out[r][c] = s
    return out


if __name__ == "__main__":
    # A few contract corners, useful as a smoke test.
    corners = [
        (-32768, 0x00, 0x0000, 0),      # -32768 * 0
        (-32768, 0x0F, 0x0000, 0),      # |A| * 15
        (-32768, 0x3F, 0xC000, 1),      # P=12, M=15, clip -> 32767 * |A| * sign
        (32767, 0x7F, 0xC000, 1),
        (1, 0x00, 0x0000, 0),
    ]
    for c in corners:
        print(c, product32(*c))
    print("INT48 wrap:", to_s48(0x7FFFFFFFFFFF + 1))
