#!/usr/bin/env python3
"""Generate direct-engine vector vectors + independent gold.

Cases: op17 FMA, op0 ADD, optional out16. A/B/C are finite normals.
"""
import os
import random
import struct
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from fma_gold import fma_bits, round_f32
from epilogue_gold import f32_to_i16

def f2b(x):
    return struct.unpack("<I", struct.pack("<f", x))[0]

def rnd_normal(rng):
    s = rng.getrandbits(1) << 31
    e = rng.randrange(100, 150)
    m = rng.getrandbits(23)
    if rng.random() < 0.15:
        m = rng.choice([0, 1, 0x400000, 0x7FFFFF])
    return s | (e << 23) | m

def write_bytes(path, vals, width):
    with open(path, "w") as f:
        for v in vals:
            for b in range(width):
                f.write("%02x\n" % ((v >> (8*b)) & 0xFF))

def main():
    op = int(sys.argv[1]) if len(sys.argv) > 1 else 17
    n = int(sys.argv[2]) if len(sys.argv) > 2 else 1001
    out16 = int(sys.argv[3]) if len(sys.argv) > 3 else 0
    out = sys.argv[4] if len(sys.argv) > 4 else "vectors/vec"
    seed = int(sys.argv[5], 0) if len(sys.argv) > 5 else 0xACE
    rng = random.Random(seed)
    a = [rnd_normal(rng) for _ in range(n)]
    b = [rnd_normal(rng) for _ in range(n)]
    c = [rnd_normal(rng) for _ in range(n)]
    if op == 17:
        d = [fma_bits(a[i], b[i], c[i], project=False) for i in range(n)]
    elif op == 0:
        d = [fma_bits(a[i], 0x3F800000, b[i], project=False) for i in range(n)]
    elif op == 15:
        d = [f32_to_i16(a[i]) & 0xFFFF for i in range(n)]
        if not out16:
            raise SystemExit("op15 requires out16=1")
    else:
        raise SystemExit("op must be 0 or 17")
    os.makedirs(out, exist_ok=True)
    write_bytes(os.path.join(out, "a.hex"), a, 4)
    write_bytes(os.path.join(out, "b.hex"), b, 4)
    write_bytes(os.path.join(out, "c.hex"), c, 4)
    if out16:
        q = [x & 0xFFFF for x in d] if op == 15 else [f32_to_i16(x) & 0xFFFF for x in d]
        write_bytes(os.path.join(out, "exp16.hex"), q, 2)
    else:
        write_bytes(os.path.join(out, "exp32.hex"), d, 4)
    with open(os.path.join(out, "meta.txt"), "w") as f:
        f.write("op=%d n=%d out16=%d seed=%#x\n" % (op, n, out16, seed))
    print("wrote op=%d n=%d out16=%d to %s" % (op, n, out16, out))

if __name__ == "__main__":
    main()
