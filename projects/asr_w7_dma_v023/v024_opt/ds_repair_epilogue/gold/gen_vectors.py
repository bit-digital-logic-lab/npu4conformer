#!/usr/bin/env python3
"""Generate the repair-tree epilogue vectors with the independent gold.

The gold (`epilogue_gold.py`, `fma_gold.py`) is the published-contract model
copied from the independent adversarial review.  It does not import RTL or any
worker golden.  This generator only scales the vector count up so the formal
gate completes a substantial number of real beats (1088 total).

Beat line: c0 c1 c2 c3 col bc tag a0 a1 a2 a3 f0 f1 f2 f3
Table line: scale_bits bias_bits
"""
import os
import random
import struct
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from epilogue_gold import epi_lane


def f2b(x):
    return struct.unpack("<I", struct.pack("<f", x))[0]


def make_bank(rows, base_scale, base_bias, cseed):
    rng = random.Random(cseed)
    scales = [f2b(base_scale + i * 0.03125) for i in range(32)]
    biases = [f2b(base_bias + i * 0.046875) for i in range(32)]
    beats = []
    for _ in range(rows):
        for b in range(8):
            col = b * 4
            cs = [rng.randint(-100000, 100000) for _ in range(4)]
            exp = [epi_lane(cs[l], scales[col + l], biases[col + l], True, 1)
                   for l in range(4)]
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
            f.write("%s %02x %04x %04x %s %s\n"
                    % (" ".join(vals), col, bc, tag, " ".join(a16), " ".join(fp)))


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else "vectors"
    os.makedirs(out, exist_ok=True)
    s0, b0, beats0 = make_bank(64, 0.5, -0.75, 0xE010)      # 512 beats
    s1, b1, beats1 = make_bank(64, 1.25, 0.5, 0xE011)       # 512 beats
    write_table(os.path.join(out, "table_bank0.txt"), s0, b0)
    write_table(os.path.join(out, "table_bank1.txt"), s1, b1)
    write_beats(os.path.join(out, "beats_bank0.txt"), beats0, 0, 5)
    write_beats(os.path.join(out, "beats_bank1.txt"), beats1, 1000, 6)

    # scalar fallback: 8 rows x 8 beats = 64 beats, broadcast scale/bias
    sb, bb = f2b(0.75), f2b(-0.5)
    rng = random.Random(0xE012)
    beats = []
    for _ in range(8):
        for b in range(8):
            col = b * 4
            cs = [rng.randint(-50000, 50000) for _ in range(4)]
            exp = [epi_lane(cs[l], sb, bb, True, 1) for l in range(4)]
            beats.append((cs, col, exp))
    write_beats(os.path.join(out, "beats_scalar.txt"), beats, 2000, 0)
    with open(os.path.join(out, "scalar.txt"), "w") as f:
        f.write("%08x %08x\n" % (sb, bb))
    print("vectors: bank0=%d bank1=%d scalar=%d total=%d -> %s"
          % (len(beats0), len(beats1), len(beats), len(beats0) + len(beats1) + len(beats), out))


if __name__ == "__main__":
    main()
