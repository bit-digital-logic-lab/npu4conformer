#!/usr/bin/env python3
"""Generate a fresh 20,000-vector FMA stimulus set for ds_fma_deep.

The stimulus is generated locally with a fixed seed (self-contained), but the
*expected* values are never stored here: they are computed at run time by the
independent Fraction-based reference
`v023_repair/ds_numeric_adversarial/ref/refmodel.py` (imported read-only).

Coverage: exact ties, extreme alignment both directions, near cancellation,
specials (NaN/Inf/zero/subnormal), and uniform random bit patterns.
"""
import os
import random
import sys

REF_DIR = "/home/yang/Desktop/项目/v023_repair/ds_numeric_adversarial/ref"
sys.path.insert(0, REF_DIR)
import refmodel as R  # noqa: E402  (read-only independent reference)


def f(sign, exp, mant):
    return ((sign & 1) << 31) | ((exp & 0xff) << 23) | (mant & 0x7FFFFF)


def gen(count=20000, seed=0x5EED2026):
    rng = random.Random(seed)
    lines = []

    # exact half-ULP ties, both round directions, zero and non-zero bias
    for ex in (1, 100, 126, 127, 128, 150, 253):
        for es in (1, 126, 127, 128, 150, 253):
            for tail in (1, 2, 3, 5, 7, 9, 11, 13, 0x7ffffb, 0x7ffffd):
                x = f(0, ex, tail)
                s = f(0, es, 0x400000)
                for mode in (1, 2):
                    lines.append((mode, s, 0, x))
                lines.append((1, s, f(1, max(1, min(254, es - 3)), 0x400000), x))

    # C dominates P (large positive exponent difference)
    for d in (1, 2, 24, 25, 30, 40, 60, 80, 100, 120, 150, 200):
        for sx in (0, 1):
            for sb in (0, 1):
                x = f(sx, 1, 0x000001)
                s = f(0, 127, 0x000001)
                b = f(sb, min(254, 1 + d), 0x123456)
                lines.append((1, s, b, x))

    # P dominates C (large negative exponent difference)
    for d in (1, 2, 24, 25, 30, 40, 60, 80, 100, 120, 150, 200):
        for sx in (0, 1):
            for sb in (0, 1):
                x = f(sx, min(254, 127 + d // 2), 0x555555)
                s = f(0, min(254, 127 + d // 2), 0x333333)
                b = f(sb, 1, 0x7fffff)
                lines.append((1, s, b, x))

    # near / exact cancellation
    for exp in range(1, 255, 3):
        for delta in (0, 1, 2, 3, 4, 8, 16, 32, 64, 128):
            x = f(0, exp, 0x200000)
            s = f(0, 127, 0x000000)
            b = f(1, exp, (0x200000 + delta) & 0x7FFFFF)
            lines.append((1, s, b, x))
            b2 = f(1, exp, (0x200000 - delta) & 0x7FFFFF)
            lines.append((1, s, b2, x))

    # specials pool
    invalids = [0x7FC00000, 0x7F800001, 0xFFC00001, 0x7FFFFFFF]
    infs = [0x7F800000, 0xFF800000]
    zeros = [0x00000000, 0x80000000]
    subs = [0x00000001, 0x00000010, 0x007FFFFF, 0x80000001, 0x807FFFFF]
    norms = [0x3F800000, 0xBF800000, 0x40000000, 0xC0000000,
             0x00800000, 0x7F7FFFFF, 0x00400000]
    pool = invalids + infs + zeros + subs + norms
    for _ in range(2500):
        lines.append((rng.choice([0, 1, 2]),
                      rng.choice(pool), rng.choice(pool), rng.choice(pool)))

    # uniform random
    while len(lines) < count:
        lines.append((rng.choice([0, 1, 2]),
                      rng.getrandbits(32), rng.getrandbits(32),
                      rng.getrandbits(32)))

    lines = lines[:count]
    out = []
    n = len(lines)
    for tag, (mode, s, b, x) in enumerate(lines):
        out.append(f"{mode:x} {s:08x} {b:08x} {x:08x} {tag & 0xffff:04x} {1 if tag == n - 1 else 0}")
    return out


if __name__ == "__main__":
    here = os.path.dirname(os.path.abspath(__file__))
    path = os.path.join(here, "..", "vectors", "fma_random_local_20000.vec")
    rows = gen()
    with open(path, "w") as fh:
        fh.write("\n".join(rows) + "\n")
    print(f"wrote {len(rows)} vectors to {path}")
