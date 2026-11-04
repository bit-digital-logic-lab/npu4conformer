"""Check a saved 18,060-byte dump of the A53 matrix self-test at 0x07c40000."""
import argparse
import hashlib
import json
import math
from pathlib import Path
import struct


def verify(path):
    m, k, n = 35, 1057, 129
    raw = path.read_bytes()
    if len(raw) != 4*m*n:
        raise ValueError("wrong DDR dump length")
    weights = [[((7*d + 13*c + ((d >> 2) ^ c)) % 5) - 2 for d in range(k)] for c in range(n)]
    words = struct.unpack(f"<{m*n}f", raw)
    largest = 0.0
    for r in range(m):
        row = [((17*r + 29*d + (r ^ d)) % 3) - 1 for d in range(k)]
        for c in range(n):
            integer = sum(v*w for v, w in zip(row, weights[c]))
            gold = integer * (0.5 if c%2 else 1.0) + c/256
            value = words[r*n+c]
            error = abs(gold-value)
            if not math.isfinite(value) or error > 0.0002:
                raise ValueError(f"output[{r},{c}] observed {value}, expected {gold}")
            largest = max(largest,error)
    return dict(result="PASS", address="0x07c40000", shape=[m,k,n], words=m*n,
                max_absolute_error=largest, raw_sha256=hashlib.sha256(raw).hexdigest())


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("dump", type=Path)
    print(json.dumps(verify(parser.parse_args().dump), indent=2))
