#!/usr/bin/env python3
"""Generate the W023 superplan fixtures and the sparse AXI-BFM image.

All descriptors use the real V022 vector/layout word formats, including the
unchanged FP32 op codes.  The control-only stub modes never claim arithmetic.
"""
import json, struct
from pathlib import Path
import numpy as np

HERE = Path(__file__).resolve().parents[1]
OUT = HERE / 'tests' / 'fixtures'
OUT.mkdir(parents=True, exist_ok=True)

PARAM_BASE = 0x10000000
PARAM_END = 0x10040000
ARENA = 0x03000000
INTER = 0x04000000
HASH_SEED = 0x811c9dc5
MAGIC_H = 0x5743504c
MAGIC_N = 0x57434e44
MAGIC_VEC = 0x22564543
MAGIC_LAY = 0x224c4159
MAGIC_Q = 0x51415352

mem = bytearray(0x100000)  # 1 MiB model


def fnv(h, w):
    return ((h ^ (w & 0xffffffff)) * 0x01000193) & 0xffffffff


def hash_header(w):
    h = HASH_SEED
    for j, v in enumerate(w):
        if j != 7:
            h = fnv(h, v)
    return h


def hash_node(h, w):
    for v in w:
        h = fnv(h, v)
    return h


def zwords(n):
    return [0] * n


def vec_descriptor(op=0, a=0x03000000, b=0x03001000, c=0, d=0x04001000,
                   total=64, period=0, a16=False, out16=False, bs=True,
                   as_=False, cs=False, a48=False, tiled=False):
    flags = op | (int(a16) << 8) | (int(out16) << 9) | (int(bs) << 10) | \
            (int(as_) << 11) | (int(cs) << 12) | (int(a48) << 13) | (int(tiled) << 14)
    w = [MAGIC_VEC, flags, a, b, c, d, total, period] + zwords(8)
    return struct.pack('<16I', *w)


def lay_descriptor(mode=0, src=0x03000000, dst=0x04000000, total=64, nbytes=4,
                   m=0, n=0, full_n=0, col_start=0, conv=None, koff=0):
    w = [MAGIC_LAY, mode, src, dst, total, nbytes, m, n, full_n, col_start] + zwords(22)
    if conv:
        w[10:24] = list(conv) + [koff]
    else:
        w[23] = koff
    return struct.pack('<32I', *w)


def queue_descriptor(a=0x03000000, b=0x03001000, c=0x04000000, m=32, n=32,
                     depth=32, accum=False, epoch=1):
    w = [MAGIC_Q, (21 << 16) | 1, epoch, 0xffffffff, a, b, c, m, n, depth,
         epoch, (1 << 16) | 7, (3 << 16) | 2, (1 << 16) | (1 if accum else 0),
         1 << 16, 0]
    return struct.pack('<16I', *w)


def put(addr, data):
    if not (PARAM_BASE <= addr < PARAM_END):
        raise ValueError('fixture write outside parameter window')
    off = 0xc0000 + addr - PARAM_BASE
    if off + len(data) > len(mem):
        raise ValueError('fixture image overflow')
    mem[off:off + len(data)] = data


def put_scratch(addr, data):
    off = addr - ARENA
    if off < 0 or off + len(data) > 0x40000:
        raise ValueError('fixture scratch outside window')
    mem[off:off + len(data)] = data


def plan(base, nodes, generation=7, bad_hash=False):
    n = len(nodes)
    words = [MAGIC_H, 0x00010001, n, 3, PARAM_END, 64 + 64 * n, generation, 0] + zwords(8)
    h = hash_header(words)
    for i, nd in enumerate(nodes):
        nd = list(nd)
        assert nd[2] == i
        h = hash_node(h, nd)
    words[7] = h ^ (1 if bad_hash else 0)
    put(base, struct.pack('<16I', *words))
    for i, nd in enumerate(nodes):
        put(base + 64 + 64 * i, struct.pack('<16I', *nd))
    return base


def node(t, i, deps, base, count=0, epoch=1):
    mask = 0
    for d in deps:
        assert d < i
        mask |= 1 << d
    return [MAGIC_N, t, i, mask & 0xffffffff, (mask >> 32) & 0xffffffff,
            (mask >> 64) & 0xffffffff, (mask >> 96) & 0xffffffff, base, count,
            0, 0, 0, 0, epoch, 0, 0]


def main():
    # Shared real-format payloads.
    pay = 0x10020000
    vec_add = pay + 0x000
    vec_mul = pay + 0x100
    lay_copy = pay + 0x200
    lay_copy2 = pay + 0x300
    vec_bad = pay + 0x400
    seq_small = pay + 0x800
    put(vec_add, vec_descriptor(0, a=0x03000000, b=0x03001000, d=0x04001000))
    put(vec_mul, vec_descriptor(2, a=0x04001000, b=0x03001004, d=0x04002000))
    put(lay_copy, lay_descriptor(0, 0x03000000, 0x04000000, 64, 4))
    put(lay_copy2, lay_descriptor(0, 0x03002000, 0x04003000, 64, 4))
    put(vec_bad, vec_descriptor(0, a=0x03000000, b=0x03001000, d=0x10001000))
    # One real V022-format linear subplan: layout copy then vector add.
    # Instruction 0: kind=3 layout payload; instruction 1: kind=2 vector payload.
    seq_lay_payload = pay + 0x500
    seq_vec_payload = pay + 0x600
    put(seq_lay_payload, lay_descriptor(0, 0x03000000, 0x04000000, 64, 4))
    put(seq_vec_payload, vec_descriptor(0, a=0x04000000, b=0x03001000, d=0x04004000))
    ins = [
        [0x22504c4e, 3, 1, 0xffffffff, seq_lay_payload, 128] + zwords(10),
        [0x22504c4e, 2, 2, 0, seq_vec_payload, 64] + zwords(10),
    ]
    put(seq_small, b''.join(struct.pack('<16I', *w) for w in ins))

    fixtures = {}
    fixtures['mode0_diamond'] = 0x10000000
    plan(0x10000000, [
        node(3, 0, [], lay_copy),                 # LAY
        node(2, 1, [0], vec_add),                 # VEC
        node(1, 2, [0], 0x03000000, 1),           # MAT stub
        node(2, 3, [1, 2], vec_mul),              # multi-dependency join
        node(3, 4, [0], lay_copy2),               # LAY
        node(2, 5, [3, 4], vec_add),              # multi-dependency join
        node(4, 6, [5], seq_small, 2),            # SEQ linear program
    ])

    fixtures['mode1_drain'] = 0x10001000
    plan(0x10001000, [
        node(2, 0, [], vec_add),
        node(1, 1, [0], 0x03000000, 1),
        node(2, 2, [1], vec_mul),
        node(3, 3, [0], lay_copy),
    ])

    fixtures['mode2_generation'] = 0x10002000
    plan(0x10002000, [
        node(2, 0, [], vec_add),
        node(2, 1, [0], vec_mul),
        node(3, 2, [0], lay_copy),
        node(1, 3, [0], 0x03000000, 1),
    ])

    fixtures['mode3_bad_hash'] = 0x10003000
    plan(0x10003000, [
        node(2, 0, [], vec_add),
        node(3, 1, [0], lay_copy),
        node(1, 2, [0], 0x03000000, 1),
    ], bad_hash=True)

    fixtures['mode4_acl'] = 0x10004000
    plan(0x10004000, [
        node(2, 0, [], vec_bad),
        node(3, 1, [0], lay_copy),
    ])

    fixtures['mode5_replay'] = 0x10005000
    long_seq = 0x10027000
    put(long_seq, b''.join(struct.pack('<16I', *w) for w in ins))
    plan(0x10005000, [
        node(4, 0, [], long_seq, 2),
        node(2, 1, [0], vec_add),
        node(1, 2, [0], 0x03000000, 1),
    ])

    fixtures['mode6_eight'] = 0x10006000
    plan(0x10006000, [
        node(2, 0, [], vec_add),
        node(3, 1, [], lay_copy),
        node(1, 2, [], 0x03000000, 1),
        node(2, 3, [0, 1], vec_mul),
        node(3, 4, [1], lay_copy2),
        node(2, 5, [3], vec_add),
        node(4, 6, [4], seq_small, 2),
        node(2, 7, [5, 6], vec_mul),
    ])

    # Real operand data: 64 FP32 normal values, scalar 1.0 and 2.0.
    base = np.array([((i % 13) - 6) * 0.25 + 0.125 for i in range(64)], dtype=np.float32)
    put_scratch(0x03000000, base.tobytes())
    put_scratch(0x03001000, np.float32(1.0).tobytes())
    put_scratch(0x03001004, np.float32(2.0).tobytes())
    g_add = (base + np.float32(1.0)).astype(np.float32)
    g_mul = (g_add * np.float32(2.0)).astype(np.float32)
    g_mix = ((g_add + np.float32(1.0)) * np.float32(2.0)).astype(np.float32)
    (OUT / 'gold_mode10.bin').write_bytes(g_mul.tobytes())
    (OUT / 'gold_mode11.bin').write_bytes(g_add.tobytes())
    (OUT / 'gold_mode12.bin').write_bytes(g_mix.tobytes())
    (OUT / 'gold_words.hex').write_text('\n'.join('%08x' % v for v in
        np.frombuffer(g_mix.tobytes(), dtype='<u4')) + '\n')
    # Real data-chain fixture (mode 10): LAY copy -> VEC add -> VEC mul.
    put(0x10028000, vec_descriptor(0, a=0x04000000, b=0x03001000, d=0x04001000))
    put(0x10028100, vec_descriptor(2, a=0x04001000, b=0x03001004, d=0x04002000))
    plan(0x10008000, [
        node(3, 0, [], lay_copy),
        node(2, 1, [0], 0x10028000),
        node(2, 2, [1], 0x10028100),
    ])
    fixtures['mode10_real_chain'] = 0x10008000

    # Real SEQ data chain (mode 11): one SEQ node whose V022 plan is LAY+VEC.
    plan(0x10009000, [node(4, 0, [], seq_small, 2)])
    fixtures['mode11_real_seq'] = 0x10009000

    # Mixed direct+SEQ chain (mode12): LAY -> VEC -> SEQ(LAY,VEC) -> VEC.
    mix_lay_payload = pay + 0x700
    mix_vec_payload = pay + 0x780
    put(mix_lay_payload, lay_descriptor(0, 0x04001000, 0x04003000, 64, 4))
    put(mix_vec_payload, vec_descriptor(0, a=0x04003000, b=0x03001000, d=0x04005000))
    mix_ins = [
        [0x22504c4e, 3, 1, 0xffffffff, mix_lay_payload, 128] + zwords(10),
        [0x22504c4e, 2, 2, 0, mix_vec_payload, 64] + zwords(10),
    ]
    mix_seq = 0x10009800
    put(mix_seq, b''.join(struct.pack('<16I', *w) for w in mix_ins))
    mix_mul = pay + 0xa00
    put(mix_mul, vec_descriptor(2, a=0x04005000, b=0x03001004, d=0x04006000))
    plan(0x1000a000, [
        node(3, 0, [], lay_copy),
        node(2, 1, [0], vec_add),
        node(4, 2, [1], mix_seq, 2),
        node(2, 3, [2], mix_mul),
    ])
    fixtures['mode12_mixed'] = 0x1000a000
    # Before-style single-program plans for the same mode12 workload.
    def one(base, kind, ptr, length):
        w = [0x22504c4e, kind, 1, 0xffffffff, ptr, length] + zwords(10)
        put(base, struct.pack('<16I', *w))
    one(0x1000b000, 3, lay_copy, 128)
    one(0x1000b100, 2, vec_add, 64)
    one(0x1000b300, 2, mix_mul, 64)
    fixtures['before_a'] = 0x1000b000
    fixtures['before_b'] = 0x1000b100
    fixtures['before_c'] = mix_seq
    fixtures['before_d'] = 0x1000b300

    # Serialize 1 MiB of 32-bit words for the BFM.
    with (OUT / 'mem_init.hex').open('w') as f:
        for i in range(0, len(mem), 4):
            f.write('%08x\n' % struct.unpack_from('<I', mem, i)[0])
    (OUT / 'fixtures.json').write_text(json.dumps(dict(
        fixtures=fixtures, param_base=PARAM_BASE, param_end=PARAM_END,
        vec_add=vec_add, vec_mul=vec_mul, lay_copy=lay_copy,
        seq_small=seq_small, memory_sha256=__import__('hashlib').sha256(mem).hexdigest(),
    ), indent=2) + '\n')
    print('WC_FIXTURES', json.dumps(fixtures))


if __name__ == '__main__':
    main()
