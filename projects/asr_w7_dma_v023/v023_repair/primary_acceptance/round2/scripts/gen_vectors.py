"""Generate adversarial vector files for the numeric audit.

All vectors are saved in ../vectors.  No DUT source is imported.
"""

import json
import os
import random
import struct
from fractions import Fraction

import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, os.path.join(ROOT, "ref"))
import refmodel as R  # noqa: E402

VEC = os.path.join(ROOT, "vectors")
os.makedirs(VEC, exist_ok=True)
rng = random.Random(0xC0FFEE)

# Actual LayerNorm output scales read from the project's parameters002 image
# (see audit_model.py / real_model_scales.json).  These are NOT KWT values.
try:
    _rm = json.load(open(os.path.join(ROOT, "ref/real_model_scales.json")))
    REAL_LN_SCALES = _rm["ln_output_scales"]
except Exception:
    REAL_LN_SCALES = [
        0.0014219279401004314, 0.00014384460519067943,
        0.00012182338832644746, 0.002551283687353134,
        0.0010732965311035514, 0.002912039402872324,
        4.205753793939948e-05, 2.438972114759963e-05,
        0.0001160990068456158, 0.0002658649464137852,
        0.00011022004036931321, 0.0034750308841466904,
    ]


def f2b(x):
    return struct.unpack("<I", struct.pack("<f", x))[0]


def b2f(b):
    return struct.unpack("<f", struct.pack("<I", b))[0]


def hx(v, n):
    return f"{v & ((1 << n) - 1):0{n // 4}x}"


# ---------------------------------------------------------------- i48 -> f32
def gen_i48():
    vals = set()
    # small exhaustive band
    for v in range(-8192, 8193):
        vals.add(v)
    # powers of two and neighbours
    for k in range(0, 48):
        p = 1 << k
        for v in (p - 1, p, p + 1, -p - 1, -p, -p + 1):
            if -(1 << 47) <= v < (1 << 47):
                vals.add(v)
    # rounding ties / just-below / just-above at every top bit
    for t in range(24, 48):
        base = 1 << t
        half = 1 << (t - 24)
        for delta in (0, 1, -1, 2, -2, half - 1, half, half + 1,
                      2 * half - 1, 2 * half, 2 * half + 1):
            for sign in (1, -1):
                v = sign * (base + delta)
                if -(1 << 47) <= v < (1 << 47):
                    vals.add(v)
        # mantissa LSB even/odd ties
        for mant in (0, 1, 2, 3, (1 << 23) - 1, (1 << 23) - 2):
            v = base + (mant << (t - 23)) + half
            if v < (1 << 47):
                vals.add(v)
                vals.add(-v)
    # random full-range 48-bit
    for _ in range(20000):
        vals.add(rng.randrange(-(1 << 47), 1 << 47))
    vals = sorted(vals)
    with open(os.path.join(VEC, "i48.vec"), "w") as f:
        for i, v in enumerate(vals):
            f.write(f"{hx(v, 48)} {hx(i & 0xFFFF, 16)} {1 if i == len(vals) - 1 else 0}\n")
    return len(vals)


# ---------------------------------------------------------------- FMA
def gen_fma():
    rows = []  # (mode, scale_bits, bias_bits, x_bits)

    def add(mode, s, b, x):
        rows.append((mode, f2b(s), f2b(b), f2b(x)))

    # primary-acceptance counterexample and variants
    for s in (1.5, 1.0000001192092896, 0.75, 3.0, 1.0 + 2**-23):
        for x in (1.0 + 2**-23, 1.0 + 2**-22, 1.0 + 3 * 2**-23):
            add(1, s, 0.0, x)
    # exact tie cases for x*scale, no bias
    for k in range(1, 24):
        x = 1.0 + k * 2**-23
        for s in (1.0 + 2**-23, 1.5, 1.0 + 3 * 2**-23):
            add(1, s, 0.0, x)
    # real-model non-trivial scales, non-zero bias, both signs
    for i in range(4000):
        s = REAL_LN_SCALES[i % len(REAL_LN_SCALES)]
        if rng.random() < 0.5:
            s = -s
        x = rng.uniform(-20.0, 20.0)
        b = rng.choice([0.0, 0.5, -0.5, 1.25, -3.75, 12.0, -0.001,
                        rng.uniform(-10.0, 10.0)])
        add(1, s, b, x)
    # cancellation / near-cancellation with non-trivial scale and bias
    for i in range(2000):
        s = REAL_LN_SCALES[i % len(REAL_LN_SCALES)]
        x = rng.uniform(-10.0, 10.0)
        prod = R.f32_to_frac(f2b(x)) * R.f32_to_frac(f2b(s))
        # bias near -prod, quantised to float
        b = float(-prod) * (1.0 + rng.choice([0.0, 1e-7, -1e-7, 1e-6, -1e-6]))
        add(1, s, b, x)
    # rounding carry: mantissa all ones, scale slightly >1
    for x in (1.9999998807907104, 1.999999761581421, 0.9999999403953552,
              3.4028234663852886e38, 1.1754943508222875e-38):
        for s in (1.0 + 2**-23, 1.0000001192092896, 1.5, 0.5):
            for b in (0.0, 1.0, -1.0, 1.1754943508222875e-38):
                add(1, s, b, x)
    # exponent boundaries / overflow / underflow
    for x in (3.4028234663852886e38, -3.4028234663852886e38,
              1.1754943508222875e-38, 1e-38, 1e-30, 1e30,
              2.0**-126, 2.0**-127, 1e-45):
        for s in (1.0, 1.5, 2.0, 1e-20, 1e20, 0.5):
            for b in (0.0, 1.0, -1.0, 1e-40, 1e38):
                add(1, s, b, x)
    # special inputs
    specials = [0x00000000, 0x80000000, 0x7F800000, 0xFF800000,
                0x7FC00000, 0x7F800001, 0x00000001, 0x80000001,
                0x007FFFFF, 0x00800000]
    for xb in specials:
        for sb in (0x3F800000, 0x00000000, 0x7F800000, 0x7FC00000, 0x80000000):
            for bb in (0x00000000, 0x7F800000, 0xFF800000, 0x7FC00000,
                       0x3F800000, 0x80000000):
                rows.append((1, sb, bb, xb))
    # mode 0 bypass and mode 2 scale-only, including non-trivial scale
    for i in range(1000):
        s = REAL_LN_SCALES[i % len(REAL_LN_SCALES)]
        x = rng.uniform(-100.0, 100.0)
        b = rng.uniform(-10.0, 10.0)
        add(0, s, b, x)
        add(2, s, b, x)
    with open(os.path.join(VEC, "fma.vec"), "w") as f:
        for i, (mode, sb, bb, xb) in enumerate(rows):
            f.write(f"{mode:x} {hx(sb,32)} {hx(bb,32)} {hx(xb,32)} "
                    f"{hx(i & 0xFFFF,16)} {1 if i == len(rows)-1 else 0}\n")
    return len(rows)


# ---------------------------------------------------------------- f32 -> i16
def gen_f32_i16():
    vals = set()
    # exact integers and half-way ties across the full i16 range
    for n in range(-33000, 33001):
        for frac in (0.0, 0.5, -0.5, 0.25, -0.25, 0.75, -0.75):
            v = n + frac
            if -1e9 < v < 1e9:
                vals.add(f2b(float(v)))
    # dense near the clamp boundaries
    for n in range(-40, 41):
        for base in (32767.0, 32768.0, -32768.0, -32769.0):
            vals.add(f2b(base + n * 0.0625))
    # special / extreme
    for b in (0x00000000, 0x80000000, 0x7F800000, 0xFF800000,
              0x7FC00000, 0x7F800001, 0x00000001, 0x80000001,
              0x007FFFFF, 0x00800000, 0x4F000000, 0xCF000000,
              0x4EFFFFFF, 0xCEFFFFFF):
        vals.add(b)
    # random bit patterns (finite and special)
    for _ in range(200000):
        vals.add(rng.getrandbits(32))
    vals = sorted(vals)
    with open(os.path.join(VEC, "f32_i16.vec"), "w") as f:
        for i, b in enumerate(vals):
            f.write(f"{hx(b,32)} {hx(i & 0xFFFF,16)} {1 if i == len(vals)-1 else 0}\n")
    return len(vals)


# ---------------------------------------------------------------- approx
def gen_approx():
    rows = []  # op, a, b

    def add(op, a, b=0.0):
        rows.append((op, f2b(a), f2b(b)))

    # DIV over model-relevant and wide exponent ranges
    for _ in range(6000):
        ea = rng.uniform(-30, 30)
        eb = rng.uniform(-30, 30)
        a = rng.uniform(1.0, 2.0) * (2.0 ** ea)
        b = rng.uniform(1.0, 2.0) * (2.0 ** eb)
        if rng.random() < 0.5:
            a = -a
        if rng.random() < 0.5:
            b = -b
        add(0, a, b)
    # softmax reciprocal domain 1/S, S in [1,128]
    for _ in range(1000):
        s = rng.uniform(1.0, 128.0)
        add(0, 1.0, s)
    # layernorm var+eps domain
    for _ in range(1000):
        v = rng.uniform(1e-6, 1e2)
        add(2, v)
        add(1, v)
    # SQRT / RSQRT wide positive range
    for _ in range(3000):
        e = rng.uniform(-30, 30)
        a = rng.uniform(1.0, 2.0) * (2.0 ** e)
        add(1, a)
        add(2, a)
    # specials for all ops
    sp = [0.0, -0.0, float("inf"), float("-inf"), float("nan"),
          1e-45, -1e-45, 1e-38, -1e-38, 1.1754943508222875e-38,
          3.4028234663852886e38, -3.4028234663852886e38]
    for a in sp:
        for b in sp:
            add(0, a, b)
        add(1, a)
        add(2, a)
    with open(os.path.join(VEC, "approx.vec"), "w") as f:
        for i, (op, ab, bb) in enumerate(rows):
            f.write(f"{op:x} {hx(ab,32)} {hx(bb,32)} {hx(i & 0xFFFF,16)}\n")
    return len(rows)


# ---------------------------------------------------------------- stream
def gen_stream():
    beats = []
    # mix of small, large, negative, zero and rounding-edge C48 values
    pool = [0, 1, -1, 2, -2, 3, -3, 7, -7, 255, -255, 4095, -4095,
            (1 << 23) - 1, 1 << 23, (1 << 23) + 1, (1 << 24) - 1,
            (1 << 24), (1 << 24) + 1, (1 << 47) - 1, -(1 << 47),
            123456789, -987654321]
    for i in range(256):
        lane = [pool[(i * 4 + k) % len(pool)] for k in range(4)]
        if i % 3 == 0:
            lane = [rng.randrange(-(1 << 47), 1 << 47) for _ in range(4)]
        beats.append(lane)
    with open(os.path.join(VEC, "stream.vec"), "w") as f:
        for i, lane in enumerate(beats):
            f.write(" ".join(hx(v, 48) for v in lane))
            f.write(f" {hx(i & 0xFFFF,16)} {1 if i == len(beats)-1 else 0}\n")
    return len(beats)


if __name__ == "__main__":
    counts = {
        "i48": gen_i48(),
        "fma": gen_fma(),
        "f32_i16": gen_f32_i16(),
        "approx": gen_approx(),
        "stream": gen_stream(),
    }
    print(counts)
