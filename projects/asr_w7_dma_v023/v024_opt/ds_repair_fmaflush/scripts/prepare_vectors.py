#!/usr/bin/env python3
"""Derive asr_fma_ip-format vectors from the frozen FMA vectors.

The wrapper testbench writes one result per accepted beat in order (it has no
tag), so the expected sequence is the frozen expected column. No expected
value is recomputed or changed here.
"""
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
src = os.path.join(ROOT, "vectors", "fma_8734_proj.txt")
dst = os.path.join(ROOT, "vectors", "asr_8734.txt")
n = 0
with open(src) as f, open(dst, "w") as o:
    for line in f:
        p = line.split()
        if len(p) < 4:
            continue
        a, b, c = p[0], p[1], p[2]
        # mode=1 (scale+bias), scale=b, bias=c, data=a
        o.write("1 %s %s %s %04x 0\n" % (b, c, a, n & 0xFFFF))
        n += 1
print("wrote %d asr rows to %s" % (n, dst))
