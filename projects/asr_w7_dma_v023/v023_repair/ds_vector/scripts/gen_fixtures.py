#!/usr/bin/env python3
"""Generate independent vector regression fixtures (offline, deterministic).

Values are chosen to exercise W7/A16/C48/QDQ boundaries and tails.  The
generator does not call the RTL; it writes memory/descriptor/gold files.
Baseline-vs-candidate comparison is the primary same-load check in run_regression.py.
"""
import json, struct, shutil
from pathlib import Path
import numpy as np

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "fixtures" / "regression"
if OUT.exists():
    shutil.rmtree(OUT)
OUT.mkdir(parents=True)

MAGIC = 0x22564543
A_BASE, B_BASE, C_BASE, D_BASE = 0x04000000, 0x04002000, 0x04004000, 0x04010000
SA_BASE, SB_BASE, SC_BASE = 0x04005000, 0x04005010, 0x04005020

def f32(x):
    return np.asarray(x, dtype=np.float32)

def rand_f32(n, seed, lo=-8.0, hi=8.0):
    r = np.random.default_rng(seed)
    x = r.uniform(lo, hi, n).astype(np.float32)
    # inject exact ties / zeros / signed zeros / small normals
    pat = np.array([0.0, -0.0, 1.0, -1.0, 0.5, -0.5, 1.5, -1.5,
                    2.0**-20, -(2.0**-20), 3.1415927, -2.7182817], np.float32)
    x[:len(pat)] = pat[:min(len(pat), n)]
    return x

def put(mem, at, data):
    mem[at:at+len(data)] = data

def make(name, mem, desc, nbytes, count, kind="normal", gold=None, expect_fault=0, no_dma=0):
    folder = OUT / name
    folder.mkdir()
    (folder/"memory.hex").write_text("".join(f"{v:02x}\n" for v in mem), encoding="ascii")
    (folder/"descriptor.hex").write_text("".join(f"{w:08x}\n" for w in desc), encoding="ascii")
    if gold is not None:
        (folder/"gold.hex").write_text("".join(f"{v:02x}\n" for v in gold), encoding="ascii")
    _META.append(dict(name=name, output_bytes=nbytes, count=count, kind=kind,
                      expect_fault=expect_fault, no_dma=no_dma))

_META = []

def descriptor(op, aa, ba, ca, da, count, period=0, a16=0, out16=0,
               bscalar=0, ascalar=0, cscalar=0, a48=0, btiled=0, corrupt=None):
    w = [MAGIC,
         op | (a16 << 8) | (out16 << 9) | (bscalar << 10) | (ascalar << 11) |
         (cscalar << 12) | (a48 << 13) | (btiled << 14),
         aa, ba, ca, da, count, period] + [0]*9
    if corrupt:
        for idx, val in corrupt:
            w[idx] = val
    return w

def mem_image():
    return bytearray(b"\xa5" * (1 << 18))

def add_fixed(name, op, count, flags=None, seed=1, golden=True):
    flags = flags or {}
    mem = mem_image()
    a = rand_f32(count, seed)
    b = rand_f32(count, seed+1)
    put(mem, 0, a.tobytes())
    put(mem, 0x2000, b.tobytes())
    out16 = flags.get("out16", 0); a16 = flags.get("a16", 0)
    a48 = flags.get("a48", 0); ascalar = flags.get("ascalar", 0)
    bscalar = flags.get("bscalar", 0); period = flags.get("period", 0)
    if a48:
        av = np.resize(np.array([0, 1, -1, 2**24+1, -2**24-3, 2**39+12345,
                                 -2**39-12345, 2**47-1, -2**47], np.int64), count)
        put(mem, 0, b"".join((int(v) & ((1 << 48)-1)).to_bytes(6, "little") for v in av))
    if a16:
        av = np.resize(np.array([-32768, -32767, -1, 0, 1, 32767, 12345, -12345], np.int16), count)
        put(mem, 0, av.astype("<i2").tobytes())
        a = av.astype(np.float32)
    if ascalar:
        put(mem, SA_BASE - A_BASE, struct.pack("<f", float(a[0])))
        a = np.full(count, a[0], np.float32)
    if bscalar:
        put(mem, SB_BASE - A_BASE, struct.pack("<f", float(b[0])))
        b = np.full(count, b[0], np.float32)
    if period:
        bp = np.resize(b[:period], period)
        put(mem, 0x2000, bp.tobytes())
        b = np.array([bp[i & (period-1)] for i in range(count)], np.float32)
    nbytes = count * (2 if out16 else 4)
    desc = descriptor(op, SA_BASE if ascalar else A_BASE,
                      SB_BASE if bscalar else B_BASE, C_BASE, D_BASE,
                      count, period, a16, out16, bscalar, ascalar, 0, a48, 0)
    gold = None
    if golden:
        if op == 0: y = f32(a + b)
        elif op == 1: y = f32(a - b)
        elif op == 2: y = f32(a * b)
        elif op == 7: y = f32(a) if a16 else f32(a)
        elif op == 8:
            if a48:
                y = np.array([int(v) for v in av[:count]], np.float32)
            else:
                y = np.rint(a).astype(np.int64).clip(-2**31, 2**31-1).astype("<i4")
                nbytes = count * 4
        elif op == 15:
            y = np.clip(np.rint(a), -32768, 32767).astype("<i2")
        elif op == 14:
            y = np.array([int(v) for v in av[:count]], np.float32)
        else:
            y = None
        if y is not None:
            gold = bytes(y.view(np.uint8))
    make(name, mem, desc, nbytes, count, gold=gold)

def add_bperiod(name, period, count, seed=2):
    mem = mem_image()
    a = rand_f32(count, seed)
    bp = rand_f32(period, seed+1)
    put(mem, 0, a.tobytes())
    put(mem, 0x2000, bp.tobytes())
    b = np.array([bp[i & (period-1)] for i in range(count)], np.float32)
    desc = descriptor(0, A_BASE, B_BASE, C_BASE, D_BASE, count, period)
    make(name, mem, desc, count*4, count, gold=(a+b).astype(np.float32).tobytes())

def add_btiled(name, count, period=32, seed=3):
    mem = mem_image()
    a = rand_f32(count, seed)
    bt = rand_f32((count//32), seed+1)
    put(mem, 0, a.tobytes())
    put(mem, 0x2000, bt.tobytes())
    # engine repeats the 32-value tile inside a 1024-element group; coefficient
    # tile advances every 1024 elements.  Compute the same addressing in Python.
    b = np.empty(count, np.float32)
    tiles = max(1, (period + 31) // 32)
    for i in range(count):
        tile = (i // 1024) % tiles
        b[i] = bt[tile*32 + (i % 32)]
    desc = descriptor(0, A_BASE, B_BASE, C_BASE, D_BASE, count, period, btiled=1)
    make(name, mem, desc, count*4, count, gold=(a+b).astype(np.float32).tobytes())

def add_corrupt(name, changes, kind="acl"):
    mem = mem_image()
    a = rand_f32(37, 9); b = rand_f32(37, 10)
    put(mem, 0, a.tobytes()); put(mem, 0x2000, b.tobytes())
    desc = descriptor(0, A_BASE, B_BASE, C_BASE, D_BASE, 37)
    for idx, val in changes: desc[idx] = val
    make(name, mem, desc, 37*4, 37, kind=kind, gold=None, expect_fault=1, no_dma=1)

# ---- fixed ops + tails ----
add_fixed("add_1001", 0, 1001, seed=11)
add_fixed("sub_1001", 1, 1001, seed=12)
add_fixed("mul_1001", 2, 1001, seed=13)
add_fixed("add_tail1", 0, 1, seed=14)
add_fixed("add_tail2", 0, 2, seed=15)
add_fixed("add_tail3", 0, 3, seed=16)
add_fixed("add_tail5", 0, 5, seed=17)
add_fixed("add_tail7", 0, 7, seed=18)
add_fixed("add_tail127", 0, 127, seed=19)
add_fixed("add_tail255", 0, 255, seed=20)
add_fixed("add_tail257", 0, 257, seed=21)
add_fixed("mul_tail3", 2, 3, seed=22)
# a16 input
add_fixed("a16_to_f32_1001", 7, 1001, {"a16": 1}, seed=23)
add_fixed("a16_tail3", 7, 3, {"a16": 1}, seed=24)
# A48
add_fixed("a48_to_f32_1001", 14, 1001, {"a48": 1}, seed=25)
add_fixed("a48_tail1", 14, 1, {"a48": 1}, seed=26)
add_fixed("a48_tail3", 14, 3, {"a48": 1}, seed=27)
# out16
add_fixed("f32_to_i16_1001", 15, 1001, {"out16": 1}, seed=28)
add_fixed("f32_to_i16_tail1", 15, 1, {"out16": 1}, seed=29)
add_fixed("f32_to_i16_tail7", 15, 7, {"out16": 1}, seed=30)
add_fixed("f32_to_i16_tail255", 15, 255, {"out16": 1}, seed=31)
# scalar A/B
add_fixed("add_ascalar_1001", 0, 1001, {"ascalar": 1}, seed=32)
add_fixed("add_bscalar_1001", 0, 1001, {"bscalar": 1}, seed=33)
add_fixed("add_bothscalar_1001", 0, 1001, {"ascalar": 1, "bscalar": 1}, seed=34)
# B period
for p in (1, 2, 4, 8, 16, 32, 64, 128, 256):
    add_bperiod(f"bperiod_{p}", p, 1001, seed=40+p)
# btiled
add_btiled("btiled_1024", 1024, 32, seed=61)
add_btiled("btiled_2048", 2048, 32, seed=62)

# ---- iterative DIV/SQRT/EXP/LOG (exact baseline path, NOT II=1) ----
def add_iter(name, op, count, seed=70):
    mem = mem_image()
    if op == 3:
        a = np.random.default_rng(seed).uniform(0.5, 4.0, count).astype(np.float32)
        b = np.random.default_rng(seed+1).uniform(0.5, 4.0, count).astype(np.float32)
        gold = (a/b).astype(np.float32)
    elif op == 4:
        a = np.random.default_rng(seed).uniform(0.25, 16.0, count).astype(np.float32)
        b = np.ones(count, np.float32)
        gold = np.sqrt(a).astype(np.float32)
    elif op == 5:
        a = np.random.default_rng(seed).uniform(-4.0, 4.0, count).astype(np.float32)
        b = np.ones(count, np.float32)
        gold = np.exp(a).astype(np.float32)
    else:
        a = np.random.default_rng(seed).uniform(0.25, 16.0, count).astype(np.float32)
        b = np.ones(count, np.float32)
        gold = np.log(a).astype(np.float32)
    put(mem, 0, a.tobytes()); put(mem, 0x2000, b.tobytes())
    desc = descriptor(op, A_BASE, B_BASE, C_BASE, D_BASE, count)
    make(name, mem, desc, count*4, count, gold=gold.tobytes())

add_iter("div_1001", 3, 1001, 70)
add_iter("div_tail7", 3, 7, 71)
add_iter("sqrt_1001", 4, 1001, 72)
add_iter("sqrt_tail7", 4, 7, 73)
add_iter("exp_1001", 5, 1001, 74)
add_iter("log_1001", 6, 1001, 75)

# ---- DIV/SQRT special cases (DMA allowed, job must fault) ----
def add_special_iter(name, op, a, b):
    mem = mem_image()
    a = np.asarray(a, np.float32); b = np.asarray(b, np.float32)
    put(mem, 0, a.tobytes()); put(mem, 0x2000, b.tobytes())
    desc = descriptor(op, A_BASE, B_BASE, C_BASE, D_BASE, len(a))
    make(name, mem, desc, len(a)*4, len(a), kind="special", gold=None,
         expect_fault=1, no_dma=0)

add_special_iter("err_div_zero", 3, [1.0, 2.0], [0.0, 1.0])
add_special_iter("err_div_0_0", 3, [0.0], [0.0])
add_special_iter("err_sqrt_neg", 4, [-1.0], [0.0])
add_special_iter("err_div_inf_inf", 3, [float("inf")], [float("inf")])

# ---- descriptor errors (no DMA side effects) ----
add_corrupt("err_magic", [(0, 0xdeadbeef)])
add_corrupt("err_reserved_low", [(1, 0x00008000)])          # descriptor[63:47] != 0
add_corrupt("err_reserved_high", [(15, 1)])                 # descriptor[511:256] != 0
add_corrupt("err_count0", [(6, 0)])
add_corrupt("err_count_huge", [(6, 0x02000000)])
add_corrupt("err_op19", [(1, 19)])
add_corrupt("err_dest_low", [(5, 0x02000000)])
add_corrupt("err_dest_unaligned", [(5, D_BASE + 4)])
add_corrupt("err_a_overlap_dest", [(5, A_BASE)])
add_corrupt("err_a_unaligned", [(2, A_BASE + 2)])
add_corrupt("err_a16_a48", [(1, 0 | (1 << 8) | (1 << 13))])
add_corrupt("err_a48_ascalar", [(1, 14 | (1 << 11) | (1 << 13))])
add_corrupt("err_out16_op", [(1, 0 | (1 << 9))])
add_corrupt("err_period_nonpow2", [(1, 0), (7, 3)])
add_corrupt("err_period_bscalar", [(1, 0 | (1 << 10)), (7, 4)])
add_corrupt("err_btiled_period0", [(1, 0 | (1 << 14)), (7, 0)])
add_corrupt("err_btiled_count", [(1, 0 | (1 << 14)), (7, 32), (6, 1001)])

(OUT/"meta.json").write_text(json.dumps(_META, indent=2) + "\n", encoding="utf-8")
print(f"V023_VECTOR_FIXTURES_CREATED {len(_META)}")
