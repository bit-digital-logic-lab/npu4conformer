#!/usr/bin/env python3
"""Validate the independent gold against the frozen 8734/251 vectors and
generate a fresh deterministic vector set. No RTL is involved here."""
import os
import random
import struct
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, HERE)
from fma_gold_independent import fma_bits  # noqa: E402


def load(path):
    rows = []
    with open(path) as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            p = line.split()
            rows.append(tuple(int(x, 16) for x in p[:4]))
    return rows


def check_file(path, label):
    rows = load(path)
    bad = 0
    strict_diff = 0
    examples = []
    for a, b, c, e in rows:
        got = fma_bits(a, b, c, strict=False)
        if got != e:
            bad += 1
            if len(examples) < 5:
                examples.append((a, b, c, e, got))
        if fma_bits(a, b, c, strict=True) != got:
            strict_diff += 1
    print("%s rows=%d project_gold_mismatch=%d strict_vs_project_diff=%d"
          % (label, len(rows), bad, strict_diff))
    for a, b, c, e, got in examples:
        print("  MISMATCH %08x %08x %08x exp=%08x gold=%08x" % (a, b, c, e, got))
    return len(rows), bad, strict_diff


SPECIALS = [
    0x00000000, 0x80000000, 0x00000001, 0x80000001, 0x007FFFFF, 0x807FFFFF,
    0x00800000, 0x80800000, 0x7F7FFFFF, 0xFF7FFFFF, 0x7F800000, 0xFF800000,
    0x7FC00000, 0x7FC00001, 0xFFC00000, 0x3F800000, 0xBF800000, 0x40000000,
    0xC0000000, 0x3F800001, 0x3FC00000, 0x34000000, 0x0C000000,
]
TIES = [
    (0x3F800001, 0x3FC00000, 0xBF800000),
    (0x3F800000, 0x3F800000, 0xBF800000),
    (0x3F800001, 0x3F800001, 0xBF800002),
    (0x40000000, 0x3F000000, 0xBF800000),
    (0x00800000, 0x3F000000, 0x00000000),
    (0x00000000, 0x3F800000, 0x80000000),
    (0x80000000, 0x3F800000, 0x00000000),
    (0x80000000, 0x3F800000, 0x80000000),
    (0x00000000, 0x3F800000, 0x00000000),
    (0x7F7FFFFF, 0x40000000, 0xFF7FFFFF),
    (0x7F800000, 0x00800000, 0x00000000),   # inf * subnormal -> inf (raw-bit rule)
    (0x7F800000, 0x00000000, 0x00000000),   # inf * 0 -> NaN
]


def f2b(x):
    return struct.unpack("<I", struct.pack("<f", x))[0]


def b2f(x):
    return struct.unpack("<f", struct.pack("<I", x))[0]


def gen(n=2000, seed=0x24A5F1):
    rng = random.Random(seed)
    rows = []
    for a in SPECIALS:
        for b in (0x3F800000, 0x00000000, 0x7F800000, 0x00800000, 0x7FC00000):
            for c in (0x00000000, 0x80000000, 0x3F800000, 0x7F800000, 0x7FC00000):
                rows.append((a, b, c))
    rows.extend(TIES)
    while len(rows) < n:
        m = rng.randrange(8)
        if m == 0:
            a, b, c = (rng.getrandbits(32) for _ in range(3))
        else:
            def rnd():
                s = rng.getrandbits(1) << 31
                r = rng.random()
                if r < 0.02:
                    return s | rng.getrandbits(23)
                if r < 0.04:
                    return s | 0x7F800000 | rng.getrandbits(23)
                e = rng.randrange(1, 255)
                mm = rng.getrandbits(23)
                if rng.random() < 0.25:
                    mm = rng.choice([0, 1, 0x400000, 0x7FFFFF, 0x3FFFFF])
                return s | (e << 23) | mm
            a, b = rnd(), rnd()
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
    return rows[:n]


def main():
    vec = os.path.join(ROOT, "vectors")
    ok = True
    n1, b1, d1 = check_file(os.path.join(vec, "fma_8734_proj.txt"), "frozen_8734")
    n2, b2, d2 = check_file(os.path.join(vec, "fma_251_proj.txt"), "frozen_251")
    # AR-002 evidence: the frozen 8734 set should show a small strict difference.
    if b1 != 0 or b2 != 0:
        ok = False
    rows = gen(2000)
    out = os.path.join(vec, "fma_fresh_2000.txt")
    with open(out, "w") as f:
        for a, b, c in rows:
            f.write("%08x %08x %08x %08x\n" % (a, b, c, fma_bits(a, b, c)))
    print("wrote %d fresh vectors to %s" % (len(rows), out))
    print("GOLD_CHECK=%s" % ("PASS" if ok else "FAIL"))
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
