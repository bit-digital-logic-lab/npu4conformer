#!/usr/bin/env python3
"""Independent integer golden for the storage/engine candidate.

Exact A16 * W7(S/J/M) semantics, cfg positions/clip, INT48 two's-complement
accumulation in ascending K order.  No float arithmetic is involved in the
matrix block path; FP32 FTZ/RNE/FMA and QDQ are untouched by this task.
"""
import argparse, hashlib, json, os, random
from pathlib import Path

def s48(x):
    x &= (1 << 48) - 1
    return x - (1 << 48) if x & (1 << 47) else x

def prod(a, w, positions, clip):
    sign = (w >> 6) & 1
    p = (positions >> (((w >> 4) & 3) * 4)) & 0xf
    magc = w & 0xf
    sat = 1 if (clip and p == 12 and magc >= 8) else 0
    m = 8 if sat else magc
    av = abs(a)
    magnitude = (av * m) << p
    if sat:
        magnitude -= av
    neg = (1 if a < 0 else 0) ^ sign
    return -magnitude if neg else magnitude

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", required=True)
    ap.add_argument("--m", type=int, default=64)
    ap.add_argument("--n", type=int, default=32)
    ap.add_argument("--k", type=int, default=96)
    ap.add_argument("--c-valid", type=int, default=0)
    ap.add_argument("--seed", type=int, default=1234)
    ap.add_argument("--positions", type=lambda x: int(x, 0), default=0x76543210)
    ap.add_argument("--clip", type=int, default=1)
    ap.add_argument("--a-base", type=lambda x: int(x, 0), default=0x03000000)
    ap.add_argument("--b-base", type=lambda x: int(x, 0), default=0x03004000)
    ap.add_argument("--c-base", type=lambda x: int(x, 0), default=0x03005000)
    ap.add_argument("--mem-words", type=int, default=2048)
    a = ap.parse_args()
    rng = random.Random(a.seed)
    M, N, K = a.m, a.n, a.k
    nbr, nbc, nbk = (M + 31)//32, (N + 31)//32, (K + 31)//32
    base = 0x03000000
    mem = bytearray(a.mem_words * 16)

    def put(addr, blob):
        off = addr - base
        assert off >= 0 and off + len(blob) <= len(mem)
        mem[off:off+len(blob)] = blob

    A = [[[0]*32 for _ in range(32)] for _ in range(nbr*nbk)]
    B = [[[0]*32 for _ in range(32)] for _ in range(nbk*nbc)]
    # small values avoid any chance of exercising the engine's overflow fault
    for bi in range(nbr*nbk):
        for r in range(32):
            for k in range(32):
                A[bi][r][k] = rng.randint(-120, 120)
    for bi in range(nbk*nbc):
        for k in range(32):
            for c in range(32):
                w7 = rng.randint(0, 0x7f)
                # W7 storage byte carries an even-parity bit7, exactly as the
                # baseline engine's B_DATA parity check requires.
                par = bin(w7).count("1") & 1
                B[bi][k][c] = w7 | (par << 7)
    # A block layout: row-major A16, 2048 bytes
    for br in range(nbr):
        for bk in range(nbk):
            bi = br*nbk + bk
            blob = bytearray()
            for r in range(32):
                for k in range(32):
                    v = A[bi][r][k] & 0xffff
                    blob += bytes([v & 0xff, v >> 8])
            put(a.a_base + bi*2048, blob)
    # W block layout: row-major W8, 1024 bytes
    for bk in range(nbk):
        for bc in range(nbc):
            bi = bk*nbc + bc
            blob = bytes(B[bi][k][c] for k in range(32) for c in range(32))
            put(a.b_base + bi*1024, blob)
    # C blocks
    Cinit = {}
    for br in range(nbr):
        for bc in range(nbc):
            bi = br*nbc + bc
            vals = []
            for i in range(1024):
                if a.c_valid:
                    vals.append(s48(rng.getrandbits(48)))
                else:
                    vals.append(0)
            Cinit[(br, bc)] = vals
            blob = bytearray()
            for v in vals:
                u = v & ((1 << 48)-1)
                blob += u.to_bytes(6, "little")
            put(a.c_base + bi*6144, blob)
    # golden
    exp = {}
    for br in range(nbr):
        for bc in range(nbc):
            c = list(Cinit[(br, bc)])
            for bk in range(nbk):
                for r in range(32):
                    row = br*32 + r
                    for cc in range(32):
                        col = bc*32 + cc
                        if row >= M or col >= N:
                            continue
                        s = 0
                        for k in range(32):
                            kk = bk*32 + k
                            if kk >= K:
                                continue
                            s += prod(A[br*nbk+bk][r][k], B[bk*nbc+bc][k][cc], a.positions, a.clip)
                        idx = r*32 + cc
                        c[idx] = s48(c[idx] + s)
            exp[(br, bc)] = c
    # expected file in block order br* nbc + bc, C index order
    out = Path(a.out)
    out.mkdir(parents=True, exist_ok=True)
    exp_lines = []
    for br in range(nbr):
        for bc in range(nbc):
            for v in exp[(br, bc)]:
                exp_lines.append(f"{v & ((1<<48)-1):012x}")
    (out/"exp_c.txt").write_text("\n".join(exp_lines) + "\n")
    # init.hex: one 128b word per line, little-endian
    hex_lines = []
    for w in range(a.mem_words):
        word = 0
        for j in range(16):
            word |= mem[w*16+j] << (8*j)
        hex_lines.append(f"{word:032x}")
    (out/"init.hex").write_text("\n".join(hex_lines) + "\n")
    manifest = {
        "M": M, "N": N, "K": K, "C_VALID": a.c_valid, "seed": a.seed,
        "positions": f"0x{a.positions:04x}", "clip": a.clip,
        "A_BASE": f"0x{a.a_base:08x}", "B_BASE": f"0x{a.b_base:08x}",
        "C_BASE": f"0x{a.c_base:08x}", "MEM_WORDS": a.mem_words,
        "nbr": nbr, "nbc": nbc, "nbk": nbk,
        "sha256_init": hashlib.sha256((out/"init.hex").read_bytes()).hexdigest(),
        "sha256_exp": hashlib.sha256((out/"exp_c.txt").read_bytes()).hexdigest(),
        "note": "integer golden only; no FP32/QDQ path in this block engine test",
    }
    (out/"manifest.json").write_text(json.dumps(manifest, indent=2)+"\n")
    print(json.dumps(manifest, indent=2))

if __name__ == "__main__":
    main()
