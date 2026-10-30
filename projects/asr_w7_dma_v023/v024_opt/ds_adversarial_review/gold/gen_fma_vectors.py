#!/usr/bin/env python3
"""Generate adversarial FMA vectors. Deterministic seed, no RTL.

Columns: a b c expected (8 hex digits each).
Coverage: normals, all subnormal classes, zeros (+/-), infinities, NaNs,
cancellation, ties (bias=0), max finite, overflow/underflow, specials.
"""
import random
import struct
import sys
import os

sys.path.insert(0, os.path.dirname(__file__))
from fma_gold import fma_bits, QNAN, INF


def f2b(x):
    return struct.unpack("<I", struct.pack("<f", x))[0]


def b2f(x):
    return struct.unpack("<f", struct.pack("<I", x))[0]


SPECIALS = [
    0x00000000, 0x80000000,            # +0 -0
    0x00000001, 0x80000001,            # min subnormal
    0x007FFFFF, 0x807FFFFF,            # max subnormal
    0x00800000, 0x80800000,            # min normal
    0x7F7FFFFF, 0xFF7FFFFF,            # max finite
    0x7F800000, 0xFF800000,            # +/-inf
    0x7FC00000, 0x7FC00001, 0xFFC00000,  # NaNs
    0x3F800000, 0xBF800000,            # +/-1
    0x40000000, 0xC0000000,            # +/-2
    0x3F800001, 0x3FC00000,            # probe operands
    0x34000000, 0x0C000000,            # small normals
]

# interesting exact ties / cancellation probes
TIES = [
    (0x3F800001, 0x3FC00000, 0xBF800000),
    (0x3F800000, 0x3F800000, 0xBF800000),   # 1*1-1 = 0
    (0x3F800001, 0x3F800001, 0xBF800002),   # rounding tie
    (0x40000000, 0x3F000000, 0xBF800000),   # 2*0.5-1
    (0x7F7FFFFF, 0x3F800000, 0x7F7FFFFF),   # overflow-ish
    (0x00800000, 0x3F000000, 0x00000000),   # min normal * 0.5 -> subnormal (FTZ)
    (0x00000000, 0x3F800000, 0x80000000),   # (+0)+(-0) => +0 (strict IEEE)
    (0x80000000, 0x3F800000, 0x00000000),   # (-0)+(+0) => +0
    (0x80000000, 0x3F800000, 0x80000000),   # (-0)+(-0) => -0
    (0x00000000, 0x3F800000, 0x00000000),   # (+0)+(+0) => +0
]


def gen(n, seed=0x5EEDF0A):
    rng = random.Random(seed)
    rows = []
    # deterministic special sweep: every special x one normal x one tie-ish c
    for a in SPECIALS:
        for b in [0x3F800000, 0x00000000, 0x7F800000, 0x00800000, 0x7FC00000]:
            for c in [0x00000000, 0x80000000, 0x3F800000, 0x7F800000, 0x7FC00000]:
                rows.append((a, b, c))
    rows.extend(TIES)
    # random bit patterns, biased to normals and near-cancellation
    while len(rows) < n:
        mode = rng.randrange(8)
        if mode == 0:
            a, b, c = (rng.getrandbits(32) for _ in range(3))
        else:
            def rnd():
                s = rng.getrandbits(1) << 31
                if rng.random() < 0.02:
                    return s | rng.getrandbits(23)             # subnormal/zero
                if rng.random() < 0.02:
                    return s | 0x7F800000 | rng.getrandbits(23) # inf/nan
                e = rng.randrange(1, 255)
                m = rng.getrandbits(23)
                if rng.random() < 0.25:
                    m = rng.choice([0, 1, 0x400000, 0x7FFFFF, 0x3FFFFF])
                return s | (e << 23) | m
            a, b = rnd(), rnd()
            # half the time derive c near -(a*b) to force cancellation/tie
            if rng.random() < 0.5:
                try:
                    prod = b2f(a) * b2f(b)
                    if prod == prod and abs(prod) != float("inf"):
                        c = f2b(-prod)
                        if rng.random() < 0.5:
                            c ^= 1 << rng.randrange(23)
                    else:
                        c = rnd()
                except Exception:
                    c = rnd()
            else:
                c = rnd()
        rows.append((a, b, c))
    out = []
    for a, b, c in rows[:n]:
        out.append((a, b, c, fma_bits(a, b, c)))
    return out


def main():
    n = int(sys.argv[1]) if len(sys.argv) > 1 else 8734
    dst = sys.argv[2] if len(sys.argv) > 2 else "fma_vec.txt"
    seed = int(sys.argv[3], 0) if len(sys.argv) > 3 else 0x5EEDF0A
    contract = sys.argv[4] if len(sys.argv) > 4 else "proj"
    project = (contract == "proj")
    rows = gen(n, seed)
    with open(dst, "w") as f:
        for a, b, c, _ in rows:
            e = fma_bits(a, b, c, project=project)
            f.write("%08x %08x %08x %08x\n" % (a, b, c, e))
    print("wrote %d vectors to %s (%s)" % (len(rows), dst, contract))


if __name__ == "__main__":
    main()
