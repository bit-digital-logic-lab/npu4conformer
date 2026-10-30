#!/usr/bin/env python3
"""V0.24 unified small-graph fixture, explicit fused-MAT plan and independent gold.

Independent gold is computed in numpy from the ds_matrix integer model output;
no RTL output, no old result.json and no same-source golden is used.
FSYN: deterministic seed fixed in the frozen manifest.
"""
import hashlib
import json
import struct
import subprocess
import sys
from pathlib import Path

import numpy as np

HERE = Path(__file__).resolve().parents[1]
FIX = HERE / 'fixtures'
sys.path.insert(0, str(HERE / 'scripts'))
import graph_common as G

MEM_WORDS = 262144
PARAM_END = 0x10040000
PLAN = 0x10008000
PAY = 0x10009000
# parameter window
PARAM_A = 0x10001000
PARAM_W = 0x10002000
PARAM_PC = 0x10003000
# arena
D_IN = 0x04000000
DIV_B = 0x04001000
D_SQ = 0x04002000
ARENA_A = 0x04003000
ARENA_B = 0x04003800
ARENA_C = 0x04004000
ARENA_D0 = 0x04005800
ARENA_D1 = 0x04006800
ARENA_OUT = 0x04007800
FB_C = 0x04008000
FB_D0 = 0x0400A000
FB_D1 = 0x0400B000
QUEUE = 0x0400C000
# output dump window (TB writes bfm words starting here)
DUMP_BASE = 0x04004000
DUMP_BYTES = 0x8000

BASE = {'arena': 0x04000000, 'external': 0x08000000, 'param': 0x10000000}
WIN = {'arena': 0x40000, 'external': 0x80000, 'param': 0xC0000}


def wi(addr):
    for n, b in BASE.items():
        if b <= addr < b + 0x40000:
            return (WIN[n] + addr - b) // 4
    raise ValueError(hex(addr))


def put(mem, addr, w):
    mem[wi(addr)] = w & 0xffffffff


def put_bytes(mem, addr, blob):
    for i in range(0, len(blob), 4):
        c = blob[i:i + 4] + b'\x00' * (4 - len(blob[i:i + 4]))
        put(mem, addr + i, int.from_bytes(c, 'little'))


def get_bytes(mem, addr, n):
    return b''.join(put_word(mem, addr + i) for i in range(0, n, 4))[:n]


def put_word(mem, addr):
    return mem[wi(addr)].to_bytes(4, 'little')


def f32(x):
    return struct.unpack('<I', struct.pack('<f', np.float32(x)))[0]


def f32s(x):
    return struct.unpack('<f', struct.pack('<I', x & 0xffffffff))[0]


def q16(c):
    """C48 -> float32 -> single-rounding fma32 -> optional relu -> RNE i16."""
    return c


def rne_i16(v, relu=False):
    if np.isnan(v):
        return 0
    if relu and v < 0:
        return 0
    if v >= 32768.0:
        return 32767
    if v <= -32768.0:
        return -32768
    return int(np.rint(float(v)))


def lay(mode, src, dst, total, nb):
    return [0x224C4159, mode, src, dst, total, nb] + [0] * 26


def vec(flags, a, b, c, d, count, period=0):
    return [0x22564543, flags, a, b, c, d, count, period] + [0] * 8


def mem_image():
    return [0] * MEM_WORDS


def write_plan(mem, nodes, flags):
    blob, hw = G.emit(PLAN, nodes, PARAM_END, generation=0, flags=flags,
                      input_base=0x08000000, input_limit=0x10000000)
    for off in range(0, len(blob), 4):
        put(mem, PLAN + off, int.from_bytes(blob[off:off + 4], 'little'))
    return blob, hw


def emit_desc(mem, addr, cookie, cbase=ARENA_C):
    q = [0] * 16
    q[0] = 0x51415352
    q[1] = 1 | (21 << 16)
    q[2] = cookie
    q[3] = 0xffffffff
    q[4] = ARENA_A
    q[5] = ARENA_B
    q[6] = cbase
    q[7] = 32
    q[8] = 32
    q[9] = 32
    q[10] = 1
    q[11] = 0 | (1 << 16)
    q[12] = 2 | (3 << 16)
    q[13] = 0x3210 | (1 << 16)
    q[14] = 0 | (1 << 16)
    q[15] = 0
    for i, v in enumerate(q):
        put(mem, addr + i * 4, v)


def matf_word(pc_en, relu, mode):
    return 0x4D410000 | ((pc_en & 1) << 13) | ((relu & 1) << 12) | ((mode & 3) << 10)


def main():
    FIX.mkdir(parents=True, exist_ok=True)
    MAT = FIX / 'mat32'
    MAT.mkdir(parents=True, exist_ok=True)
    subprocess.run([
        sys.executable,
        '/home/yang/Desktop/项目/v023_repair/ds_matrix/tests/gen_engine_vectors.py',
        '--out', str(MAT), '--m', '32', '--n', '32', '--k', '32',
        '--c-valid', '0', '--positions', '0x3210', '--clip', '1',
        '--a-base', '0x03000000', '--b-base', '0x03001000',
        '--c-base', '0x03002000', '--mem-words', '2048'
    ], check=True, stdout=subprocess.DEVNULL)

    init_words = [int(x, 16) for x in (MAT / 'init.hex').read_text().split()]
    init_bytes = b''.join(w.to_bytes(16, 'little') for w in init_words)
    a_bytes = init_bytes[0x0000:0x0000 + 2048]
    w_bytes = init_bytes[0x1000:0x1000 + 1024]
    exp = [int(x, 16) for x in (MAT / 'exp_c.txt').read_text().split()]
    assert len(exp) == 1024

    # Per-channel parameters: distinct scale/bias per column, moderate range.
    rng = np.random.default_rng(20261030)
    scales = np.array([np.float32(2.0 ** (-10 - (c % 5)) * (1.0 + 0.01 * c))
                       for c in range(32)], dtype=np.float32)
    biases = np.array([np.float32((c - 16) * 0.125) for c in range(32)], dtype=np.float32)

    # Numeric operands (positive, finite; DIV denominator away from zero).
    din = np.array([np.float32(0.5 + (i % 97) * 0.37) for i in range(1024)], dtype=np.float32)
    divb = np.array([np.float32(0.75 + (i % 31) * 0.21) for i in range(1024)], dtype=np.float32)
    dsq = np.array([np.float32(0.01 + (i % 89) * 0.53) for i in range(1024)], dtype=np.float32)

    # Independent golds.
    exp_s = [v - (1 << 48) if (v & (1 << 47)) else v for v in exp]
    a16 = []
    muladd = []
    fma_mismatch = 0
    for i, c in enumerate(exp_s):
        col = i % 32
        x = np.float32(c)
        s = scales[col]
        b = biases[col]
        # single-rounding: exact product in float64, one RNE to float32
        f = np.float32(np.float64(x) * np.float64(s) + np.float64(b))
        a16.append(rne_i16(f))
        # legacy two-step: rounded product then add, rounded again
        m = np.float32(np.float32(x * s) + b)
        muladd.append(rne_i16(m))
        if rne_i16(f) != rne_i16(m):
            fma_mismatch += 1
    gold_fma_words = [((a16[i] & 0xffff) | ((a16[i + 1] & 0xffff) << 16))
                      for i in range(0, 1024, 2)]
    div_gold = np.float32(din / divb)
    sqrt_gold = np.float32(np.sqrt(dsq))
    fb_i16 = [rne_i16(np.float32(np.float32(c))) for c in exp_s]

    def words_of_f32(arr):
        return [int(np.float32(v).view(np.uint32)) for v in arr]

    def i16_words(arr):
        return [((int(arr[i]) & 0xffff) | ((int(arr[i + 1]) & 0xffff) << 16))
                for i in range(0, len(arr), 2)]

    # ---- fused plan ----
    mem = mem_image()
    put_bytes(mem, PARAM_A, a_bytes)
    put_bytes(mem, PARAM_W, w_bytes)
    # host preload image: 0..31 scale, 32..63 bias
    for c in range(32):
        put(mem, PARAM_PC + c * 4, f32(scales[c]))
        put(mem, PARAM_PC + (32 + c) * 4, f32(biases[c]))
    for i, v in enumerate(words_of_f32(din)):
        put(mem, D_IN + i * 4, v)
    for i, v in enumerate(words_of_f32(divb)):
        put(mem, DIV_B + i * 4, v)
    for i, v in enumerate(words_of_f32(dsq)):
        put(mem, D_SQ + i * 4, v)
    emit_desc(mem, QUEUE, 1)
    for off, w in {
        0x000: lay(0, PARAM_A, ARENA_A, 1024, 2),
        0x100: lay(0, PARAM_W, ARENA_B, 512, 2),
        0x200: vec(3, D_IN, DIV_B, 0, ARENA_D0, 1024),
        0x300: vec(4, D_SQ, 0, 0, ARENA_D1, 1024),
        0x400: lay(0, ARENA_C, ARENA_OUT, 1024, 2),
    }.items():
        for i, v in enumerate(w):
            put(mem, PAY + off + i * 4, v)

    fused_nodes = [
        G.node(G.T_IN, 0, 0, base=PARAM_A, count=512,
               flags=G.FLAG_ROOT | G.FLAG_EXTERNAL, input_tid=0, output_tid=0,
               input_base=PARAM_A, input_bytes=2048,
               output_base=PARAM_A, output_bytes=2048, version=1, epoch=1),
        G.node(G.T_LAY, 1, 1 << 0, base=PAY + 0x000, count=0,
               input_tid=0, output_tid=1, input_base=PARAM_A, input_bytes=2048,
               output_base=ARENA_A, output_bytes=2048, version=1, epoch=2),
        G.node(G.T_LAY, 2, 1 << 0, base=PAY + 0x100, count=0,
               input_tid=0, output_tid=2, input_base=PARAM_W, input_bytes=1024,
               output_base=ARENA_B, output_bytes=1024, version=1, epoch=3),
        G.node(G.T_MAT, 3, (1 << 1) | (1 << 2), base=QUEUE, count=1,
               flags=G.FLAG_OUTPUT | G.FLAG_RETAINED,
               input_tid=1, output_tid=3, input_base=ARENA_A, input_bytes=2048,
               output_base=ARENA_C, output_bytes=2048, version=1, epoch=4),
        G.node(G.T_VEC, 4, 1 << 0, base=PAY + 0x200, count=0,
               input_tid=0, output_tid=4, input_base=D_IN, input_bytes=4096,
               output_base=ARENA_D0, output_bytes=4096, version=1, epoch=5),
        G.node(G.T_VEC, 5, 1 << 0, base=PAY + 0x300, count=0,
               input_tid=0, output_tid=5, input_base=D_SQ, input_bytes=4096,
               output_base=ARENA_D1, output_bytes=4096, version=1, epoch=6),
        G.node(G.T_LAY, 6, 1 << 3, base=PAY + 0x400, count=0,
               input_tid=3, output_tid=6, input_base=ARENA_C, input_bytes=2048,
               output_base=ARENA_OUT, output_bytes=2048, version=1, epoch=7),
    ]
    # explicit fusion descriptor words 14/15
    fused_nodes[3][14] = matf_word(pc_en=1, relu=0, mode=1)
    fused_nodes[3][15] = 0
    # explicit A16 consumer tag on the copy node that reads the fused output
    fused_nodes[6][14] = 0x41313643
    fused_nodes[6][15] = 0
    blob_f, _ = write_plan(mem, fused_nodes, flags=G.FLAG_SYNTH_ORDER | 0x10000)
    (FIX / 'mem_v024_fused.hex').write_text('\n'.join(f'{w:08x}' for w in mem) + '\n')

    # ---- fallback plan: explicit request but queue_count=2, and consumer is
    # not A16C, so the controller must refuse fusion and run legacy C48. ----
    memf = mem_image()
    put_bytes(memf, PARAM_A, a_bytes)
    put_bytes(memf, PARAM_W, w_bytes)
    emit_desc(memf, QUEUE, 1, FB_C)
    emit_desc(memf, QUEUE + 64, 2, FB_C)
    for off, w in {
        0x000: lay(0, PARAM_A, ARENA_A, 1024, 2),
        0x100: lay(0, PARAM_W, ARENA_B, 512, 2),
        0x200: vec(14 | (1 << 13), FB_C, D_IN, 0, FB_D0, 1024),
        0x300: vec(15 | (1 << 9), FB_D0, 0, 0, FB_D1, 1024),
    }.items():
        for i, v in enumerate(w):
            put(memf, PAY + off + i * 4, v)
    fb_nodes = [
        G.node(G.T_IN, 0, 0, base=PARAM_A, count=512,
               flags=G.FLAG_ROOT | G.FLAG_EXTERNAL, input_tid=0, output_tid=0,
               input_base=PARAM_A, input_bytes=2048,
               output_base=PARAM_A, output_bytes=2048, version=1, epoch=1),
        G.node(G.T_LAY, 1, 1 << 0, base=PAY + 0x000, count=0,
               input_tid=0, output_tid=1, input_base=PARAM_A, input_bytes=2048,
               output_base=ARENA_A, output_bytes=2048, version=1, epoch=2),
        G.node(G.T_LAY, 2, 1 << 0, base=PAY + 0x100, count=0,
               input_tid=0, output_tid=2, input_base=PARAM_W, input_bytes=1024,
               output_base=ARENA_B, output_bytes=1024, version=1, epoch=3),
        G.node(G.T_MAT, 3, (1 << 1) | (1 << 2), base=QUEUE, count=2,
               input_tid=1, output_tid=3, input_base=ARENA_A, input_bytes=2048,
               output_base=FB_C, output_bytes=6144, version=1, epoch=4),
        G.node(G.T_VEC, 4, 1 << 3, base=PAY + 0x200, count=0,
               input_tid=3, output_tid=4, input_base=FB_C, input_bytes=6144,
               output_base=FB_D0, output_bytes=4096, version=1, epoch=5),
        G.node(G.T_VEC, 5, 1 << 4, base=PAY + 0x300, count=0,
               flags=G.FLAG_OUTPUT | G.FLAG_RETAINED,
               input_tid=4, output_tid=5, input_base=FB_D0, input_bytes=4096,
               output_base=FB_D1, output_bytes=2048, version=1, epoch=6),
    ]
    # Request fusion explicitly on the MAT node (must be refused: count=2).
    fb_nodes[3][14] = matf_word(pc_en=0, relu=0, mode=0)
    blob_b, _ = write_plan(memf, fb_nodes, flags=0x10000)
    (FIX / 'mem_v024_fallback.hex').write_text('\n'.join(f'{w:08x}' for w in memf) + '\n')

    # ---- bad plan: MATF word present but header FUSION_ALLOW clear ----
    memb = mem_image()
    put_bytes(memb, PARAM_A, a_bytes)
    put_bytes(memb, PARAM_W, w_bytes)
    emit_desc(memb, QUEUE, 1)
    for off, w in {0x000: lay(0, PARAM_A, ARENA_A, 1024, 2),
                   0x100: lay(0, PARAM_W, ARENA_B, 512, 2)}.items():
        for i, v in enumerate(w):
            put(memb, PAY + off + i * 4, v)
    bad_nodes = [
        G.node(G.T_IN, 0, 0, base=PARAM_A, count=512,
               flags=G.FLAG_ROOT | G.FLAG_EXTERNAL, input_tid=0, output_tid=0,
               input_base=PARAM_A, input_bytes=2048,
               output_base=PARAM_A, output_bytes=2048, version=1, epoch=1),
        G.node(G.T_LAY, 1, 1 << 0, base=PAY + 0x000, count=0,
               input_tid=0, output_tid=1, input_base=PARAM_A, input_bytes=2048,
               output_base=ARENA_A, output_bytes=2048, version=1, epoch=2),
        G.node(G.T_LAY, 2, 1 << 0, base=PAY + 0x100, count=0,
               input_tid=0, output_tid=2, input_base=PARAM_W, input_bytes=1024,
               output_base=ARENA_B, output_bytes=1024, version=1, epoch=3),
        G.node(G.T_MAT, 3, (1 << 1) | (1 << 2), base=QUEUE, count=1,
               input_tid=1, output_tid=3, input_base=ARENA_A, input_bytes=2048,
               output_base=ARENA_C, output_bytes=2048, version=1, epoch=4),
    ]
    bad_nodes[3][14] = matf_word(pc_en=0, relu=0, mode=0)
    write_plan(memb, bad_nodes, flags=G.FLAG_SYNTH_ORDER)  # no 0x10000
    (FIX / 'mem_v024_badflag.hex').write_text('\n'.join(f'{w:08x}' for w in memb) + '\n')

    # ---- directed FMA vs mul+add vectors (int48 x, per-beat scale/bias) ----
    rng2 = np.random.default_rng(7)
    found = []
    tries = 0
    while len(found) < 64 and tries < 4000000:
        n = 200000
        tries += n
        xi = rng2.integers(-(1 << 22), 1 << 22, size=n, dtype=np.int64)
        se = rng2.uniform(-30, 10, size=n)
        sf = np.exp2(se).astype(np.float32)
        bf = (rng2.standard_normal(n) * np.exp2(rng2.uniform(-25, 5, size=n))).astype(np.float32)
        xf = xi.astype(np.float32)
        one = np.float32(np.float64(xf) * np.float64(sf) + np.float64(bf))
        two = np.float32(np.float32(xf * sf) + bf)
        diff = one.view(np.uint32) != two.view(np.uint32)
        idx = np.nonzero(diff)[0]
        for j in idx:
            if len(found) >= 64:
                break
            if not np.isfinite(one[j]) or not np.isfinite(two[j]):
                continue
            found.append((int(xi[j]), int(sf[j].view(np.uint32)),
                          int(bf[j].view(np.uint32)), int(one[j].view(np.uint32)),
                          int(two[j].view(np.uint32))))
    assert len(found) == 64
    lane_words = []
    lane_gold = []
    lane_two = []
    for x, sbits, bbits, onebits, twobits in found:
        lane_words += [x & 0xffffffff, sbits, bbits]
        lane_gold.append(onebits)
        lane_two.append(twobits)
    (FIX / 'lane_vectors.hex').write_text('\n'.join(f'{w:08x}' for w in lane_words) + '\n')
    (FIX / 'lane_gold.hex').write_text('\n'.join(f'{w:08x}' for w in lane_gold) + '\n')
    (FIX / 'lane_muladd.hex').write_text('\n'.join(f'{w:08x}' for w in lane_two) + '\n')

    # ---- frozen reference / gold metadata ----
    ref = {
        'generator': 'scripts/gen_v024_graph.py',
        'matrix': 'ds_matrix eng_c0 integer exp_c (independent Python model)',
        'plan_fused_sha256': hashlib.sha256(blob_f).hexdigest(),
        'plan_fallback_sha256': hashlib.sha256(blob_b).hexdigest(),
        'fused_a16_words': gold_fma_words,
        'fused_fma_vs_muladd_mismatch': fma_mismatch,
        'div_gold': words_of_f32(div_gold),
        'sqrt_gold': words_of_f32(sqrt_gold),
        'fallback_i16_words': i16_words(fb_i16),
        'scales': [f32(v) for v in scales],
        'biases': [f32(v) for v in biases],
        'dump_base': DUMP_BASE,
        'dump_bytes': DUMP_BYTES,
        'arena': {'A': ARENA_A, 'B': ARENA_B, 'C': ARENA_C, 'D0': ARENA_D0,
                  'D1': ARENA_D1, 'OUT': ARENA_OUT,
                  'FB_C': FB_C, 'FB_D0': FB_D0, 'FB_D1': FB_D1},
        'lane_fma_vectors': 64,
        'lane_fma_vs_muladd_diff': sum(1 for a,b in zip(lane_gold,lane_two) if a!=b),
        'tolerances': {'div_rel': 0.0012, 'sqrt_rel': 6.0e-6},
        'scope': 'logic simulation only; no synthesis/STA/board; per-channel table host-preloaded once',
    }
    (FIX / 'v024_ref.json').write_text(json.dumps(ref))

    # flat gold files for the checker
    (FIX / 'gold_a16.hex').write_text('\n'.join(f'{w:08x}' for w in gold_fma_words) + '\n')
    (FIX / 'gold_fallback_i16.hex').write_text('\n'.join(f'{w:08x}' for w in i16_words(fb_i16)) + '\n')
    print(json.dumps({k: ref[k] for k in ('plan_fused_sha256', 'plan_fallback_sha256',
                                          'fused_fma_vs_muladd_mismatch')}, indent=2))


if __name__ == '__main__':
    main()
