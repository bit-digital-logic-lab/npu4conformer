#!/usr/bin/env python3
"""Generate deterministic C48 stream vectors for the cycle benchmark.

Each line is: lane0 lane1 lane2 lane3 tag last
- 4 lanes/beat, 48-bit two's-complement signed values in hex
- independent data per beat length (seed = length), so 256/1024/4096 are
  separate vector files rather than one file truncated three ways.
"""
import hashlib
import os
import random
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
VEC = ROOT / "vectors"
VEC.mkdir(parents=True, exist_ok=True)
LENGTHS = (256, 1024, 4096)


def hx(v, n):
    return f"{v & ((1 << n) - 1):0{n // 4}x}"


def make_vec(n):
    rng = random.Random(0xA16_0000 + n)
    edge = [
        0, 1, -1, 2, -2, 3, -3, 7, -7, 31, -31, 255, -255, 4095, -4095,
        (1 << 23) - 1, 1 << 23, (1 << 23) + 1,
        (1 << 24) - 1, 1 << 24, (1 << 24) + 1,
        (1 << 32) - 1, 1 << 32,
        (1 << 47) - 1, -(1 << 47), (1 << 47) - 2, -((1 << 47) - 1),
        123456789, -987654321, 0x5A5A5A5A5A5A, -0x5A5A5A5A5A5A,
    ]
    rows = []
    for i in range(n):
        if i % 11 == 0:
            lanes = [edge[(i + k) % len(edge)] for k in range(4)]
        elif i % 7 == 0:
            lanes = [rng.randrange(-(1 << 47), 1 << 47) for _ in range(4)]
        elif i % 5 == 0:
            lanes = [rng.choice(edge) for _ in range(4)]
        else:
            # Mostly moderate magnitudes, with occasional full-range values.
            lanes = []
            for k in range(4):
                if rng.random() < 0.20:
                    lanes.append(rng.randrange(-(1 << 47), 1 << 47))
                else:
                    lanes.append(rng.randrange(-(1 << 23), 1 << 23))
        tag = (0x1200 + 7 * i) & 0xFFFF
        last = 1 if i == n - 1 else 0
        rows.append(" ".join(hx(v, 48) for v in lanes) + f" {hx(tag, 16)} {last}")
    path = VEC / f"stream_{n}.vec"
    path.write_text("\n".join(rows) + "\n")
    return path


def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


if __name__ == "__main__":
    out = {}
    for n in LENGTHS:
        p = make_vec(n)
        out[p.name] = {"beats": n, "sha256": sha256(p), "bytes": p.stat().st_size}
        print(p.name, out[p.name]["sha256"])
    import json
    (ROOT / "vectors" / "VECTOR_SHA256.json").write_text(json.dumps(out, indent=2) + "\n")
