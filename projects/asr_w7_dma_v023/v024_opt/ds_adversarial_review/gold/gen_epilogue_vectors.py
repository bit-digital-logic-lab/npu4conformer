#!/usr/bin/env python3
"""Generate per-channel epilogue vectors and independent expected values."""
import os
import random
import struct
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from epilogue_gold import epi_lane

def f2b(x):
    return struct.unpack("<I", struct.pack("<f", x))[0]

def s48(v):
    v &= (1 << 48) - 1
    return v - (1 << 48) if v & (1 << 47) else v

def make_bank(n, base_scale, base_bias, cseed):
    rng = random.Random(cseed)
    scales = [f2b(base_scale + i * 0.03125) for i in range(32)]
    biases = [f2b(base_bias + i * 0.046875) for i in range(32)]
    # 4 rows x 8 beats x 4 lanes, column-major beat order within each row
    beats = []
    for row in range(n):
        for b in range(8):
            col = b * 4
            cs = [rng.randint(-100000, 100000) for _ in range(4)]
            exp = [epi_lane(cs[l], scales[col + l], biases[col + l], True, 1) for l in range(4)]
            beats.append((cs, col, exp))
    return scales, biases, beats

def write_table(path, scales, biases):
    with open(path, "w") as f:
        for i in range(32):
            f.write("%08x %08x\n" % (scales[i], biases[i]))

def write_beats(path, beats, tag_base, bc):
    with open(path, "w") as f:
        for i, (cs, col, exp) in enumerate(beats):
            tag = tag_base + i
            vals = ["%016x" % (c & ((1 << 48) - 1)) for c in cs]
            a16 = ["%04x" % (e[1] & 0xFFFF) for e in exp]
            fp = ["%08x" % e[0] for e in exp]
            f.write("%s %02x %04x %04x %s %s\n" % (" ".join(vals), col, bc, tag, " ".join(a16), " ".join(fp)))

def main():
    out = sys.argv[1] if len(sys.argv) > 1 else "vectors/epi"
    os.makedirs(out, exist_ok=True)
    s0, b0, beats0 = make_bank(4, 0.5, -0.75, 0xE010)
    s1, b1, beats1 = make_bank(4, 1.25, 0.5, 0xE011)
    write_table(os.path.join(out, "table_bank0.txt"), s0, b0)
    write_table(os.path.join(out, "table_bank1.txt"), s1, b1)
    write_beats(os.path.join(out, "beats_bank0.txt"), beats0, 0, 5)
    write_beats(os.path.join(out, "beats_bank1.txt"), beats1, 1000, 6)
    # scalar fallback: broadcast scale/bias, 1 row
    sb, bb = f2b(0.75), f2b(-0.5)
    rng = random.Random(0xE012)
    beats = []
    for b in range(8):
        col = b * 4
        cs = [rng.randint(-50000, 50000) for _ in range(4)]
        exp = [epi_lane(cs[l], sb, bb, True, 1) for l in range(4)]
        beats.append((cs, col, exp))
    write_beats(os.path.join(out, "beats_scalar.txt"), beats, 2000, 0)
    with open(os.path.join(out, "scalar.txt"), "w") as f:
        f.write("%08x %08x\n" % (sb, bb))
    print("epilogue vectors written to", out)

if __name__ == "__main__":
    main()
