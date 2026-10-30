#!/usr/bin/env python3
"""Generate targeted and random FMA test vectors for round 2 verification.
Reuses ds_numeric_adversarial/ref/refmodel.py (read-only) for golden reference.
Covers:
1. Exact ties (LSB even / odd, round bit = 1, sticky = 0)
2. Extreme exponent alignment (C >> P, P >> C)
3. Specials (NaN, Inf * 0, Inf + (-Inf), signed zero combinations)
4. Massive cancellation (P ~ -C)
5. Pure random bit patterns across modes 0, 1, 2
"""
import random
import os
import sys

sys.path.insert(0, '/home/yang/Desktop/项目/v023_repair/ds_numeric_adversarial/ref')
import refmodel as R

def make_float(sign, exp, mant):
    return ((sign & 1) << 31) | ((exp & 0xff) << 23) | (mant & 0x7fffff)

def gen_vectors(out_path, count=20000, seed=12345):
    random.seed(seed)
    lines = []

    # 1. Exact tie test cases with zero bias and non-zero bias
    for exp_x in [127, 126, 128, 100, 150, 1, 253]:
        for exp_s in [127, 126, 128, 100, 150, 1, 253]:
            # Mantissa chosen such that product has exact half-ULP
            for mant_tail in [1, 3, 5, 7, 9, 11, 13, 15, 0x7ffffb, 0x7ffffd]:
                x = make_float(0, exp_x, mant_tail)
                s = make_float(0, exp_s, 0x400000) # 1.5 -> product has .5 at 24th bit
                b = 0x00000000
                lines.append((1, s, b, x))
                lines.append((2, s, b, x))

    # 2. Extreme exponent differences: C far larger than P
    for exp_diff in [30, 40, 50, 60, 70, 80, 100, 120, 150, 200]:
        for sign_x in [0, 1]:
            for sign_b in [0, 1]:
                x = make_float(sign_x, 1, 0x000001)
                s = make_float(0, 127, 0x000001)
                b = make_float(sign_b, min(254, 1 + exp_diff), 0x123456)
                lines.append((1, s, b, x))

    # 3. Extreme exponent differences: P far larger than C
    for exp_diff in [30, 40, 50, 60, 70, 80, 100, 120, 150, 200]:
        for sign_x in [0, 1]:
            for sign_b in [0, 1]:
                x = make_float(sign_x, min(254, 127 + exp_diff//2), 0x555555)
                s = make_float(0, min(254, 127 + exp_diff//2), 0x333333)
                b = make_float(sign_b, 1, 0x7fffff)
                lines.append((1, s, b, x))

    # 4. Near-cancellation (P ~ -C)
    for exp in range(50, 200, 5):
        for delta in [0, 1, 2, 3, 4, 8, 16, 32, 64]:
            x = make_float(0, exp, 0x200000)
            s = make_float(0, 127, 0x000000) # s = 1.0
            # b = - (x + delta)
            b = make_float(1, exp, 0x200000 + delta)
            lines.append((1, s, b, x))
            # b = - (x - delta)
            if delta <= 0x200000:
                b2 = make_float(1, exp, 0x200000 - delta)
                lines.append((1, s, b2, x))

    # 5. Specials
    invalids = [0x7fc00000, 0x7f800001, 0xffc00001]
    infs = [0x7f800000, 0xff800000]
    zeros = [0x00000000, 0x80000000]
    subnormals = [0x00000001, 0x00000010, 0x007fffff, 0x80000001, 0x807fffff]
    normals = [0x3f800000, 0xbf800000, 0x40000000, 0xc0000000, 0x00800000, 0x7f7fffff]

    special_pool = invalids + infs + zeros + subnormals + normals
    for _ in range(2000):
        x = random.choice(special_pool)
        s = random.choice(special_pool)
        b = random.choice(special_pool)
        mode = random.choice([0, 1, 2])
        lines.append((mode, s, b, x))

    # 6. Uniform random 32-bit values
    while len(lines) < count:
        mode = random.choice([0, 1, 2])
        x = random.randint(0, 0xffffffff)
        s = random.randint(0, 0xffffffff)
        b = random.randint(0, 0xffffffff)
        lines.append((mode, s, b, x))

    lines = lines[:count]

    with open(out_path, 'w') as f:
        for tag, (mode, s, b, x) in enumerate(lines):
            last = 1 if tag == len(lines) - 1 else 0
            tag16 = tag & 0xffff
            f.write(f"{mode:x} {s:08x} {b:08x} {x:08x} {tag16:04x} {last}\n")

    print(f"Generated {len(lines)} test vectors into {out_path}")

if __name__ == '__main__':
    out_dir = os.path.dirname(os.path.abspath(__file__)) + '/../vectors'
    gen_vectors(os.path.join(out_dir, 'fma_random.vec'), 20000)
