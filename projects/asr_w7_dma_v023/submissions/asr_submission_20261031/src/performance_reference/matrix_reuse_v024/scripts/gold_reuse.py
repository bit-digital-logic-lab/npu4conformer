#!/usr/bin/env python3
"""Independent integer golden for the 2x1 W-reuse matrix schedule.

This model is hand-written for this task; it does not import or execute any
RTL, and it does not read the v023 golden generator.  It implements the
documented V020/V023 integer contract:

  A: signed 16-bit, row-major 32x32 block, 2048 B
  W: 8-bit stored byte = parity_bit[7] | {S[6],J[5:4],M[3:0]}
     stored parity is even over all 8 bits; only bits [6:0] are numeric
  positions nibble selects a 4-bit shift for J
  clip: if positions[J]==12 and M>=8, saturate magnitude to 8<<12 - 1*A
  C: signed INT48, natural two's-complement wrap on accumulation

Outputs are the same formats used by the RTL testbench:
  init.hex   : MEM_WORDS 128-bit little-endian words
  exp_c.txt  : one 12-hex-digit C48 per line, block order br*nbc+bc, i*...
"""
import argparse
import hashlib
import json
import random
from pathlib import Path


def s48(x):
    x &= (1 << 48) - 1
    return x - (1 << 48) if x & (1 << 47) else x


def prod(a, w, positions, clip):
    sign = (w >> 6) & 1
    p = (positions >> (((w >> 4) & 3) * 4)) & 0xF
    magc = w & 0xF
    sat = 1 if (clip and p == 12 and magc >= 8) else 0
    m = 8 if sat else magc
    av = abs(a)
    magnitude = (av * m) << p
    if sat:
        magnitude -= av
    neg = (1 if a < 0 else 0) ^ sign
    return -magnitude if neg else magnitude


def even_parity_byte(low7):
    ones = bin(low7 & 0x7F).count("1")
    return (low7 & 0x7F) | ((ones & 1) << 7)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", required=True)
    ap.add_argument("--tag", default="case")
    ap.add_argument("--m", type=int, required=True)
    ap.add_argument("--n", type=int, required=True)
    ap.add_argument("--k", type=int, required=True)
    ap.add_argument("--c-valid", type=int, default=0)
    ap.add_argument("--seed", type=int, default=1)
    ap.add_argument("--positions", type=lambda x: int(x, 0), default=0x76543210)
    ap.add_argument("--clip", type=int, default=1)
    ap.add_argument("--a-base", type=lambda x: int(x, 0), default=0x03000000)
    ap.add_argument("--b-base", type=lambda x: int(x, 0), default=0x03008000)
    ap.add_argument("--c-base", type=lambda x: int(x, 0), default=0x03020000)
    ap.add_argument("--mem-words", type=int, default=0x5000)
    ap.add_argument("--c-mode", choices=["zero", "random", "max"], default="zero")
    ap.add_argument("--a-mode", choices=["random", "one"], default="random")
    ap.add_argument("--w-mode", choices=["random", "one"], default="random")
    ap.add_argument("--bad-parity", action="store_true")
    args = ap.parse_args()

    M, N, K = args.m, args.n, args.k
    nbr, nbc, nbk = (M + 31) // 32, (N + 31) // 32, (K + 31) // 32
    base = 0x03000000
    mem = bytearray(args.mem_words * 16)

    def put(addr, blob, what):
        off = addr - base
        assert off >= 0, f"{what}: address below BASE"
        assert off + len(blob) <= len(mem), f"{what}: does not fit in MEM_WORDS"
        mem[off:off + len(blob)] = blob

    rng = random.Random(args.seed)

    # A blocks: [br][bk][r][k]
    A = [[[0] * 32 for _ in range(32)] for _ in range(nbr * nbk)]
    for bi in range(nbr * nbk):
        for r in range(32):
            for k in range(32):
                A[bi][r][k] = 1 if args.a_mode == "one" else rng.randint(-120, 120)

    # W blocks: [bk][bc][k][c] as stored bytes (parity included unless bad)
    B = [[[0] * 32 for _ in range(32)] for _ in range(nbk * nbc)]
    for bi in range(nbk * nbc):
        for k in range(32):
            for c in range(32):
                if args.w_mode == "one":
                    low7 = 0x01          # S=0, J=0, M=1 -> product = +A
                else:
                    low7 = rng.randint(0, 0x7F)
                if args.bad_parity and (bi == 0 and k == 0 and c == 0):
                    # deliberately wrong bit7 on exactly one W byte
                    B[bi][k][c] = low7 & 0x7F
                else:
                    B[bi][k][c] = even_parity_byte(low7)

    # A / W DDR layout
    for br in range(nbr):
        for bk in range(nbk):
            blob = bytearray()
            for r in range(32):
                for k in range(32):
                    v = A[br * nbk + bk][r][k] & 0xFFFF
                    blob += bytes([v & 0xFF, v >> 8])
            put(args.a_base + (br * nbk + bk) * 2048, blob, "A")
    for bk in range(nbk):
        for bc in range(nbc):
            blob = bytes(B[bk * nbc + bc][k][c] for k in range(32) for c in range(32))
            put(args.b_base + (bk * nbc + bc) * 1024, blob, "W")

    # C init and golden
    Cinit = {}
    for br in range(nbr):
        for bc in range(nbc):
            vals = []
            for i in range(1024):
                if args.c_mode == "max":
                    vals.append((1 << 47) - 1)
                elif args.c_mode == "random" and args.c_valid:
                    vals.append(rng.randint(-(1 << 40), 1 << 40))
                else:
                    vals.append(0)
            Cinit[(br, bc)] = vals
            blob = bytearray()
            for v in vals:
                blob += (v & ((1 << 48) - 1)).to_bytes(6, "little")
            put(args.c_base + (br * nbc + bc) * 6144, blob, "C")

    exp = {}
    for br in range(nbr):
        for bc in range(nbc):
            c = list(Cinit[(br, bc)])
            for bk in range(nbk):
                for r in range(32):
                    row = br * 32 + r
                    for cc in range(32):
                        col = bc * 32 + cc
                        if row >= M or col >= N:
                            continue
                        s = 0
                        for k in range(32):
                            kk = bk * 32 + k
                            if kk >= K:
                                continue
                            s += prod(A[br * nbk + bk][r][k],
                                      B[bk * nbc + bc][k][cc],
                                      args.positions, args.clip)
                        idx = r * 32 + cc
                        c[idx] = s48(c[idx] + s)
            exp[(br, bc)] = c

    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    exp_lines = []
    for br in range(nbr):
        for bc in range(nbc):
            for v in exp[(br, bc)]:
                exp_lines.append(f"{v & ((1 << 48) - 1):012x}")
    (out / "exp_c.txt").write_text("\n".join(exp_lines) + "\n")

    hex_lines = []
    for w in range(args.mem_words):
        word = 0
        for j in range(16):
            word |= mem[w * 16 + j] << (8 * j)
        hex_lines.append(f"{word:032x}")
    (out / "init.hex").write_text("\n".join(hex_lines) + "\n")

    def sha(name):
        return hashlib.sha256((out / name).read_bytes()).hexdigest()

    manifest = {
        "tag": args.tag,
        "model": "gold_reuse.py independent integer model",
        "M": M, "N": N, "K": K, "C_VALID": args.c_valid,
        "seed": args.seed, "positions": f"0x{args.positions:04x}",
        "clip": args.clip, "c_mode": args.c_mode,
        "a_mode": args.a_mode, "w_mode": args.w_mode,
        "bad_parity": bool(args.bad_parity),
        "A_BASE": f"0x{args.a_base:08x}", "B_BASE": f"0x{args.b_base:08x}",
        "C_BASE": f"0x{args.c_base:08x}", "MEM_WORDS": args.mem_words,
        "nbr": nbr, "nbc": nbc, "nbk": nbk,
        "sha256_init": sha("init.hex"),
        "sha256_exp": sha("exp_c.txt"),
        "note": "integer-only golden; not derived from RTL or from a prior PASS",
    }
    (out / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    print(json.dumps(manifest, indent=2))


if __name__ == "__main__":
    main()
