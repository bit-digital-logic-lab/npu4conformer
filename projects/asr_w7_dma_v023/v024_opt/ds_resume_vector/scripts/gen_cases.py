#!/usr/bin/env python3
"""Generate independent vector-FMA regression cases for ds_vector_fma.

Read-only inputs:
  * v023_repair/ds_numeric_adversarial/vectors/fma.vec
  * v023_repair/ds_numeric_adversarial/ref/refmodel.py
  * work/tests/fma_fixture/{memory.hex,gold.hex,descriptor.hex}

Every case gets its own 1 MiB-word image (the BFM's sparse AXI model), a
512-bit vector descriptor, a WCPG v2 one-node plan, the exact input list and
an independent gold.  The checker recomputes the gold from the input list with
refmodel; it does not trust this generator's gold file.
"""
import json, hashlib, struct, sys
from fractions import Fraction
from pathlib import Path

HERE = Path(__file__).resolve().parents[1]
ROOT = HERE
DS = Path('/home/yang/Desktop/项目/v023_repair/ds_numeric_adversarial')
WORK = Path('/home/yang/Desktop/项目/work/tests/fma_fixture')
sys.path.insert(0, str(HERE / 'scripts'))
import graph_common as G
sys.path.insert(0, str(DS / 'ref'))
import refmodel as R

FIX = HERE / 'fixtures'
CASES = FIX / 'cases'
CASES.mkdir(parents=True, exist_ok=True)

WORDS = 262144
ARENA = 0x04000000
EXT = 0x08000000
PARAM = 0x10000000
PARAM_END = 0x10040000
WIN = {'arena': 0x40000, 'external': 0x80000, 'param': 0xC0000}
MEM_BASE = {'arena': ARENA, 'external': EXT, 'param': PARAM}

MAGIC = 0x22564543
OP_ADD, OP_SUB, OP_MUL, OP_F32_I16, OP_FMA = 0, 1, 2, 15, 17

PLAN1 = 0x10008000
PAY1 = 0x10009000
PLAN2 = 0x10010000
PAY2 = 0x10011000

# arena layout used by <=1024-element cases (4 KiB spacing is enough)
A_BASE = ARENA + 0x00000
B_BASE = ARENA + 0x01000
C_BASE = ARENA + 0x02000
D_BASE = ARENA + 0x10000
# wide layout for 8734-element planes (34936 bytes each, non-overlapping)
WA = ARENA + 0x00000
WB = ARENA + 0x09000
WC = ARENA + 0x12000
WD = ARENA + 0x1B000
D2_BASE = ARENA + 0x30000
D3_BASE = ARENA + 0x34000


def win_index(addr):
    for name, base in MEM_BASE.items():
        if base <= addr < base + 0x40000:
            return (WIN[name] + (addr - base)) // 4
    raise ValueError(hex(addr))


def mem_set(mem, addr, word):
    mem[win_index(addr)] = word & 0xffffffff


def mem_set_bytes(mem, addr, blob):
    for i in range(0, len(blob), 4):
        chunk = blob[i:i + 4] + b'\x00' * (4 - len(chunk))
        mem_set(mem, addr + i, int.from_bytes(chunk, 'little'))


def u32(bits):
    return struct.pack('<I', bits & 0xffffffff)


def vec_desc(op, a, b, c, d, total, *, period=0, bscalar=0, ascalar=0,
             cscalar=0, a16=0, out16=0, a48=0, btiled=0):
    w1 = (op & 0xff) | (a16 << 8) | (out16 << 9) | (bscalar << 10) | \
         (ascalar << 11) | (cscalar << 12) | (a48 << 13) | (btiled << 14)
    return [MAGIC, w1, a, b, c, d, total, period] + [0] * 8


def emit_plan(mem, plan_base, payload_base, desc, input_base, input_bytes,
              output_base, output_bytes, epoch=1):
    for i, w in enumerate(desc):
        mem_set(mem, payload_base + i * 4, w)
    node = G.node(G.T_VEC, 0, 0, base=payload_base, count=0,
                  flags=G.FLAG_ROOT | G.FLAG_OUTPUT,
                  input_tid=0, output_tid=1,
                  input_base=input_base, input_bytes=input_bytes,
                  output_base=output_base, output_bytes=output_bytes,
                  version=1, epoch=epoch)
    blob, hw = G.emit(plan_base, [node], PARAM_END, generation=0, flags=0,
                      input_base=EXT, input_limit=0x10000000)
    assert G.check_hash(blob)
    for off in range(0, len(blob), 4):
        mem_set(mem, plan_base + off, int.from_bytes(blob[off:off + 4], 'little'))
    return hw


# ---- independent fixed-op references (not the RTL, not ds_vector gold) ----

def f32_mul_bits(a, b):
    if R.is_nan(a) or R.is_nan(b):
        return R.FP32_QNAN
    if (R.is_inf(a) and R.is_zero(b)) or (R.is_inf(b) and R.is_zero(a)):
        return R.FP32_QNAN
    if R.is_inf(a) or R.is_inf(b):
        return ((a >> 31) ^ (b >> 31) << 31) | R.FP32_POS_INF
    if R.is_zero(a) or R.is_zero(b):
        return (((a >> 31) ^ (b >> 31)) << 31) & 0x80000000
    return R.round_f32(R.f32_to_frac(a) * R.f32_to_frac(b))


def f32_add_bits(a, b):
    if R.is_nan(a) or R.is_nan(b):
        return R.FP32_QNAN
    if R.is_inf(a) and R.is_inf(b) and ((a >> 31) != (b >> 31)):
        return R.FP32_QNAN
    if R.is_inf(a):
        return a
    if R.is_inf(b):
        return b
    if R.is_zero(a) and R.is_zero(b):
        return ((a >> 31) & (b >> 31)) << 31
    if R.is_zero(a):
        return b
    if R.is_zero(b):
        return a
    return R.round_f32(R.f32_to_frac(a) + R.f32_to_frac(b))


def pack_i16(vals):
    out = []
    for i in range(0, len(vals), 2):
        lo = vals[i] & 0xffff
        hi = (vals[i + 1] & 0xffff) if i + 1 < len(vals) else 0
        out.append(lo | (hi << 16))
    return out


# ---- deterministic input patterns ----

def rand32(state):
    state = (state * 1664525 + 1013904223) & 0xffffffff
    return state


def gen_triples(n, seed=0x12345678):
    """FMA triples with specials concentrated at the start."""
    specials = [
        (0x00000000, 0x3f800000, 0x00000000),
        (0x80000000, 0x3f800000, 0x80000000),
        (0x7f800000, 0x3f800000, 0x00000000),
        (0xff800000, 0x3f800000, 0x00000000),
        (0x7fc00000, 0x3f800000, 0x00000000),
        (0x7f7fffff, 0x3f800001, 0x00000000),
        (0x00800000, 0x3f800001, 0x3f800000),
        (0x00800000, 0x3f800001, 0xbf800000),
        (0x3f800003, 0x3fc00000, 0x00000000),
        (0x3f800007, 0x3fc00000, 0x00000000),
        (0x3f800001, 0x3f7ffffe, 0xbf800000),
        (0x00000001, 0x3f800000, 0x00000000),
        (0x80000001, 0x3f800000, 0x80000000),
        (0x7f7fffff, 0x7f7fffff, 0xff7fffff),
        (0x3f800001, 0x3fc00000, 0xbf800000),
        (0x3fc00000, 0x40000000, 0xc0400000),
        (0x40200000, 0x3fe00000, 0xbec00000),
    ]
    out = []
    st = seed
    for i in range(n):
        if i < len(specials):
            out.append(specials[i])
        else:
            x = rand32(st); st = rand32(st)
            s = rand32(st); st = rand32(st)
            b = rand32(st); st = rand32(st)
            # keep most values finite/usable but include occasional specials
            if (i % 37) == 0:
                x = 0x00800000 | (x & 0x7fffff)
            if (i % 53) == 0:
                s = 0x7f800000 if (s & 1) else 0xff800000
            if (i % 71) == 0:
                b = 0x7fc00000
            out.append((x, s, b))
    return out


def finite_normal(st):
    """A finite normal binary32 with a moderate exponent; no NaN/Inf/overflow."""
    r = rand32(st)
    sign = (r >> 31) << 31
    e = 100 + (r % 40)          # 100..139, safe for MUL and ADD
    frac = r & 0x7fffff
    return sign | (e << 23) | frac


def gen_pairs(n, seed=0x55aa55aa):
    # The 4-lane fixed-op test targets tail masking/packing.  Keep inputs
    # finite/normal so a legitimate NaN/Inf cannot be mistaken for a fault by
    # the engine's numeric_flags gate (special-value FMA coverage is separate).
    out = [(0x3f800000, 0x3f800000), (0x00000000, 0x3f800000),
           (0x80000000, 0xbf800000)]
    st = seed
    while len(out) < n:
        a = finite_normal(st); st = rand32(st)
        b = finite_normal(st); st = rand32(st)
        out.append((a, b))
    return out[:n]


def gen_singles(n, seed=0x0badf00d):
    out = [0x00000000, 0x80000000, 0x7f7fffff, 0x00800000,
           0xbf800000, 0x3fc00000, 0xc0200000]
    st = seed
    while len(out) < n:
        out.append(finite_normal(st)); st = rand32(st)
    return out[:n]


# ---- case writers ----

META = []


def write_case(name, mem, *, op, total, out16, outwords, inputs, gold,
               plan_base=PLAN1, d_addr=D_BASE, extra=None, desc=None):
    d = CASES / name
    d.mkdir(parents=True, exist_ok=True)
    (d / 'mem.hex').write_text('\n'.join(f'{w:08x}' for w in mem) + '\n')
    (d / 'inputs.txt').write_text('\n'.join(' '.join(f'{v:08x}' for v in row)
                                           for row in inputs) + '\n')
    (d / 'gold.hex').write_text('\n'.join(f'{w:08x}' for w in gold) + '\n')
    meta = {
        'name': name, 'op': op, 'total': total, 'out16': out16,
        'outwords': outwords, 'plan_base': plan_base, 'd_addr': d_addr,
        'gold_count': len(gold), 'gold_sha256':
            hashlib.sha256((d / 'gold.hex').read_bytes()).hexdigest(),
        'inputs_sha256':
            hashlib.sha256((d / 'inputs.txt').read_bytes()).hexdigest(),
        'mem_sha256': hashlib.sha256((d / 'mem.hex').read_bytes()).hexdigest(),
    }
    if extra:
        meta.update(extra)
    (d / 'meta.json').write_text(json.dumps(meta, indent=2) + '\n')
    META.append(meta)
    return meta


def fma_case(name, triples, total, a_base=A_BASE, b_base=B_BASE,
             c_base=C_BASE, d_base=D_BASE, **kw):
    extra = kw.pop('extra', None)
    use = triples[:total]
    x = [t[0] for t in use]
    s = [t[1] for t in use]
    b = [t[2] for t in use]
    mem = [0] * WORDS
    for i in range(total):
        mem_set(mem, a_base + i * 4, x[i])
        mem_set(mem, b_base + i * 4, s[i])
        mem_set(mem, c_base + i * 4, b[i])
    desc = vec_desc(OP_FMA, a_base, b_base, c_base, d_base, total, **kw)
    emit_plan(mem, PLAN1, PAY1, desc, a_base, total * 12, d_base, total * 4)
    gold = [R.fma_bits(x[i], s[i], b[i]) for i in range(total)]
    ex = {'desc': desc[:8]}
    if extra:
        ex.update(extra)
    return write_case(name, mem, op=OP_FMA, total=total, out16=0,
                      outwords=total, inputs=list(zip(x, s, b)), gold=gold,
                      d_addr=d_base, extra=ex)


def fixed_case(name, op, pairs, total, out16=0, **kw):
    a = [p[0] for p in pairs[:total]]
    b = [p[1] for p in pairs[:total]]
    mem = [0] * WORDS
    for i in range(total):
        mem_set(mem, A_BASE + i * 4, a[i])
        if op in (OP_ADD, OP_SUB, OP_MUL):
            mem_set(mem, B_BASE + i * 4, b[i])
    desc = vec_desc(op, A_BASE, B_BASE, C_BASE, D_BASE, total, out16=out16, **kw)
    input_bytes = total * (8 if op in (OP_ADD, OP_SUB, OP_MUL) else 4)
    emit_plan(mem, PLAN1, PAY1, desc, A_BASE, input_bytes, D_BASE,
              total * (2 if out16 else 4))
    if op == OP_MUL:
        gold = [f32_mul_bits(a[i], b[i]) for i in range(total)]
        inputs = list(zip(a, b))
    elif op == OP_ADD:
        gold = [f32_add_bits(a[i], b[i]) for i in range(total)]
        inputs = list(zip(a, b))
    elif op == OP_F32_I16:
        vals = [R.f32_to_i16(a[i]) for i in range(total)]
        gold = pack_i16(vals)
        inputs = [(a[i],) for i in range(total)]
    else:
        raise ValueError(op)
    outwords = total if not out16 else (total + 1) // 2
    return write_case(name, mem, op=op, total=total, out16=out16,
                      outwords=outwords, inputs=inputs, gold=gold,
                      extra={'desc': desc[:8]})


def full_8734():
    rows = [ln.split() for ln in (DS / 'vectors/fma.vec').read_text().splitlines() if ln.strip()]
    triples = []
    for r in rows:
        mode = int(r[0], 16)
        s = int(r[1], 16)
        b = int(r[2], 16)
        x = int(r[3], 16)
        if mode == 0:
            s, b = 0x3f800000, 0x00000000   # bypass == x*1+0 for these vectors
        elif mode == 2:
            b = 0x00000000                 # scale-only mode
        triples.append((x, s, b))
    assert len(triples) == 8734, len(triples)
    return fma_case('full8734', triples, 8734, a_base=WA, b_base=WB,
                    c_base=WC, d_base=WD,
                    extra={'source': 'v023 ds_numeric_adversarial fma.vec modes 0/1/2 mapped to op17',
                           'mode0': 'scale=1,bias=0', 'mode2': 'bias=0'})


def tails():
    tri = gen_triples(1001, seed=0x12345678)
    totals = [256] + list(range(257, 274)) + [383, 511, 513, 1001]
    for t in totals:
        fma_case(f'tail_{t:04d}', tri, t,
                 extra={'tail': t % 256})


def operand_modes():
    tri = gen_triples(2048, seed=0x22334455)
    x = [t[0] for t in tri]
    s = [t[1] for t in tri]
    b = [t[2] for t in tri]
    # bscalar: one scale, full C
    for name, total in (('fma_bscalar_1001', 1001),):
        mem = [0] * WORDS
        for i in range(total):
            mem_set(mem, A_BASE + i * 4, x[i])
            mem_set(mem, C_BASE + i * 4, b[i])
        mem_set(mem, B_BASE, s[0])
        desc = vec_desc(OP_FMA, A_BASE, B_BASE, C_BASE, D_BASE, total, bscalar=1)
        emit_plan(mem, PLAN1, PAY1, desc, A_BASE, total * 12, D_BASE, total * 4)
        gold = [R.fma_bits(x[i], s[0], b[i]) for i in range(total)]
        write_case(name, mem, op=OP_FMA, total=total, out16=0, outwords=total,
                   inputs=[(x[i], s[0], b[i]) for i in range(total)], gold=gold,
                   extra={'desc': desc[:8], 'mode': 'bscalar'})
    # cscalar: full scale, one bias
    total = 1001
    mem = [0] * WORDS
    for i in range(total):
        mem_set(mem, A_BASE + i * 4, x[i])
        mem_set(mem, B_BASE + i * 4, s[i])
    mem_set(mem, C_BASE, b[0])
    desc = vec_desc(OP_FMA, A_BASE, B_BASE, C_BASE, D_BASE, total, cscalar=1)
    emit_plan(mem, PLAN1, PAY1, desc, A_BASE, total * 12, D_BASE, total * 4)
    gold = [R.fma_bits(x[i], s[i], b[0]) for i in range(total)]
    write_case('fma_cscalar_1001', mem, op=OP_FMA, total=total, out16=0,
               outwords=total, inputs=[(x[i], s[i], b[0]) for i in range(total)],
               gold=gold, extra={'desc': desc[:8], 'mode': 'cscalar'})
    # periodic B (period 32 / 128): B region is period words
    for period in (32, 128):
        total = 1001
        mem = [0] * WORDS
        for i in range(total):
            mem_set(mem, A_BASE + i * 4, x[i])
            mem_set(mem, C_BASE + i * 4, b[i])
        for i in range(period):
            mem_set(mem, B_BASE + i * 4, s[i])
        desc = vec_desc(OP_FMA, A_BASE, B_BASE, C_BASE, D_BASE, total,
                        period=period)
        emit_plan(mem, PLAN1, PAY1, desc, A_BASE, total * 12, D_BASE, total * 4)
        gold = [R.fma_bits(x[i], s[i & (period - 1)], b[i]) for i in range(total)]
        write_case(f'fma_period{period}_1001', mem, op=OP_FMA, total=total,
                   out16=0, outwords=total,
                   inputs=[(x[i], s[i & (period - 1)], b[i]) for i in range(total)],
                   gold=gold, extra={'desc': desc[:8], 'mode': f'period{period}'})
    # btiled 32-element tile, counts 1024/2048 (delivered ds_vector pattern)
    for total in (1024, 2048):
        ab, bb, cb, db = (A_BASE, B_BASE, C_BASE, D_BASE) if total <= 1024 else (WA, WB, WC, WD)
        mem = [0] * WORDS
        for i in range(total):
            mem_set(mem, ab + i * 4, x[i])
            mem_set(mem, cb + i * 4, b[i])
        for i in range(32):
            mem_set(mem, bb + i * 4, s[i])
        desc = vec_desc(OP_FMA, ab, bb, cb, db, total, period=32, btiled=1)
        emit_plan(mem, PLAN1, PAY1, desc, ab, total * 12, db, total * 4)
        gold = [R.fma_bits(x[i], s[i & 31], b[i]) for i in range(total)]
        write_case(f'fma_btiled{total}', mem, op=OP_FMA, total=total, out16=0,
                   outwords=total, d_addr=db,
                   inputs=[(x[i], s[i & 31], b[i]) for i in range(total)],
                   gold=gold, extra={'desc': desc[:8], 'mode': 'btiled32'})


def official_fixture():
    raw = (WORK / 'memory.hex').read_text().split()
    assert len(raw) == 1 << 18, len(raw)
    gold_bytes = (WORK / 'gold.hex').read_text().split()
    assert len(gold_bytes) == 4004, len(gold_bytes)
    desc_words = [int(x, 16) for x in (WORK / 'descriptor.hex').read_text().split()]
    assert len(desc_words) == 16, len(desc_words)
    assert desc_words[0] == MAGIC and desc_words[1] == OP_FMA
    total = desc_words[6]
    assert total == 1001, total
    mem = [0] * WORDS
    # official byte image starts at arena 0x04000000
    for i in range(0, len(raw), 4):
        mem_set(mem, ARENA + i, int.from_bytes(bytes(int(v, 16) for v in raw[i:i + 4]), 'little'))
    # official descriptor is the payload; its A/B/C/D are arena addresses
    emit_plan(mem, PLAN1, PAY1, desc_words,
              desc_words[2], total * 12, desc_words[5], total * 4)
    gold = [int.from_bytes(bytes(int(v, 16) for v in gold_bytes[i:i + 4]), 'little')
            for i in range(0, len(gold_bytes), 4)]
    inputs = []
    # reconstruct A/B/C from the official image for the independent checker
    for i in range(total):
        def word(off):
            j = off + i * 4
            return int.from_bytes(bytes(int(v, 16) for v in raw[j:j + 4]), 'little')
        inputs.append((word(0), word(0x1000), word(0x2000)))
    write_case('official_fixture_1001', mem, op=OP_FMA, total=total, out16=0,
               outwords=total, inputs=inputs, gold=gold,
               extra={'desc': desc_words[:8], 'mode': 'official work/tests/fma_fixture',
                      'source_gold_sha256': hashlib.sha256((WORK / 'gold.hex').read_bytes()).hexdigest(),
                      'source_mem_sha256': hashlib.sha256((WORK / 'memory.hex').read_bytes()).hexdigest()})


# Tail/alignment coverage for the 4-lane fixed-op path.
# 1..17 includes the whole old failure range 9..16 (the previous owner only
# ran 1..9 and 17, leaving 10..16 untested).  31/32/33, 63/64/65 and
# 255/256/257 cross the lane-group and CHUNK=256 boundaries; 511/513/1001
# cover multi-bank tails.
LANE_TOTALS = (list(range(1, 18)) +
               [31, 32, 33, 63, 64, 65, 127, 255, 256, 257, 511, 513, 1001])


def lane_short_cases():
    pairs = gen_pairs(1001, seed=0x55aa55aa)
    for t in LANE_TOTALS:
        fixed_case(f'mul_{t:04d}', OP_MUL, pairs, t)
    for t in LANE_TOTALS:
        fixed_case(f'add_{t:04d}', OP_ADD, pairs, t)
    singles = gen_singles(1001, seed=0x0badf00d)
    spairs = [(v, 0) for v in singles]
    for t in LANE_TOTALS:
        fixed_case(f'i16_{t:04d}', OP_F32_I16, spairs, t, out16=1)


def abort_reset_cases():
    rows = [ln.split() for ln in (DS / 'vectors/fma.vec').read_text().splitlines() if ln.strip()]
    triples = []
    for r in rows:
        mode = int(r[0], 16); s = int(r[1], 16); b = int(r[2], 16); x = int(r[3], 16)
        if mode == 0:
            s, b = 0x3f800000, 0
        elif mode == 2:
            b = 0
        triples.append((x, s, b))
    x = [t[0] for t in triples]
    s = [t[1] for t in triples]
    b = [t[2] for t in triples]
    for tag, d2 in (('abort', D2_BASE), ('reset', D3_BASE)):
        mem = [0] * WORDS
        total1 = 8734
        for i in range(total1):
            mem_set(mem, WA + i * 4, x[i])
            mem_set(mem, WB + i * 4, s[i])
            mem_set(mem, WC + i * 4, b[i])
        desc1 = vec_desc(OP_FMA, WA, WB, WC, WD, total1)
        emit_plan(mem, PLAN1, PAY1, desc1, WA, total1 * 12, WD, total1 * 4, epoch=1)
        total2 = 257
        for i in range(total2):
            mem_set(mem, A_BASE + i * 4, x[i])
            mem_set(mem, B_BASE + i * 4, s[i])
            mem_set(mem, C_BASE + i * 4, b[i])
        desc2 = vec_desc(OP_FMA, A_BASE, B_BASE, C_BASE, d2, total2)
        emit_plan(mem, PLAN2, PAY2, desc2, A_BASE, total2 * 12, d2, total2 * 4, epoch=2)
        gold2 = [R.fma_bits(x[i], s[i], b[i]) for i in range(total2)]
        inputs2 = [(x[i], s[i], b[i]) for i in range(total2)]
        write_case(f'{tag}_newepoch', mem, op=OP_FMA, total=total2, out16=0,
                   outwords=total2, inputs=inputs2, gold=gold2,
                   plan_base=PLAN2, d_addr=d2,
                   extra={'scenario': tag, 'plan1': PLAN1, 'plan1_total': total1,
                          'plan1_d': WD, 'plan2': PLAN2,
                          'desc': desc2[:8]})


def main():
    full_8734()
    tails()
    operand_modes()
    official_fixture()
    lane_short_cases()
    abort_reset_cases()
    manifest = {
        'generated_by': 'scripts/gen_cases.py',
        'upstream': {
            'fma_vec_sha256': hashlib.sha256((DS / 'vectors/fma.vec').read_bytes()).hexdigest(),
            'refmodel_sha256': hashlib.sha256((DS / 'ref/refmodel.py').read_bytes()).hexdigest(),
            'official_mem_sha256': hashlib.sha256((WORK / 'memory.hex').read_bytes()).hexdigest(),
            'official_gold_sha256': hashlib.sha256((WORK / 'gold.hex').read_bytes()).hexdigest(),
        },
        'cases': META,
    }
    (FIX / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
    print(f'CASES {len(META)} -> {FIX}')


if __name__ == '__main__':
    main()
