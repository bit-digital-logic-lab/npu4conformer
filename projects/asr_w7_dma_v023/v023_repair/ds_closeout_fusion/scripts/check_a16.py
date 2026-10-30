#!/usr/bin/env python3
"""Compare a DUT A16 hex dump with the independent golden hex."""
import argparse
import sys
from pathlib import Path


def load(p):
    return [int(x, 16) for x in Path(p).read_text().split()]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("dut")
    ap.add_argument("gold")
    ap.add_argument("--label", default="")
    a = ap.parse_args()
    d, g = load(a.dut), load(a.gold)
    n = min(len(d), len(g))
    bad = [(i, d[i], g[i]) for i in range(n) if d[i] != g[i]]
    print("CHECK %s dut=%d gold=%d mismatch=%d" % (a.label, len(d), len(g), len(bad)))
    for i, x, y in bad[:12]:
        print("  idx=%d dut=%04x gold=%04x" % (i, x, y))
    if len(d) != len(g):
        print("  FAIL length mismatch")
        return 1
    if bad:
        return 1
    print("CHECK_PASS")
    return 0


if __name__ == "__main__":
    sys.exit(main())
