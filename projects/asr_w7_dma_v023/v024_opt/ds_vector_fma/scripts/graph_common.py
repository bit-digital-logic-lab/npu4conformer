#!/usr/bin/env python3
"""Common WCPG v2 (whole-graph) binary helpers.

New format (this task, no change to any sealed V022 payload):

  header 64 B, 16 little-endian words
  node   192 B, 48 little-endian words
     words 0..15  metadata
     words 16..47 1024-bit predecessor mask (bit 16*32+...)

The format is deliberately wider than the ds_pl_autonomy WCPL v1 (128 nodes,
128-bit mask) because the existing outer ledger alone has 591 matrix tasks.
"""
import struct

MAGIC_H = 0x57435047       # 'WCPG'
MAGIC_N = 0x5743474e       # 'WCGN'
VERSION = 0x00020001
HASH_SEED = 0x811c9dc5
HEADER_WORDS = 16
NODE_WORDS = 48
NODE_BYTES = NODE_WORDS * 4
DEP_WORDS = 32

T_MAT, T_VEC, T_LAY, T_SEQ, T_IN = 1, 2, 3, 4, 5
FLAG_ROOT = 1
FLAG_OUTPUT = 2
FLAG_EXTERNAL = 4
FLAG_RETAINED = 8
FLAG_SYNTH_ORDER = 16

PARAM_BASE = 0x10000000
PARAM_LIMIT = 0x40000000
ARENA_BASE = 0x03000000
ARENA_LIMIT = 0x08000000
EXTERNAL_BASE = 0x08000000
EXTERNAL_LIMIT = 0x10000000


def fnv(h, w):
    return ((h ^ (w & 0xffffffff)) * 0x01000193) & 0xffffffff


def align(x, n=64):
    return (x + n - 1) // n * n


def hash_header(words):
    h = HASH_SEED
    for j, v in enumerate(words):
        if j != 7:
            h = fnv(h, v)
    return h


def hash_node(h, words):
    for v in words:
        h = fnv(h, v)
    return h


def node(type_, node_id, dep_mask, base=0, count=0, *, flags=0,
         input_tid=0, output_tid=0, input_base=0, input_bytes=0,
         output_base=0, output_bytes=0, version=0, epoch=1):
    w = [MAGIC_N, type_, node_id, flags, base, count,
         input_tid, output_tid, input_base, input_bytes,
         output_base, output_bytes, version, epoch, 0, 0]
    # keep only lower 1024 bits; reject wider fan-in instead of silently
    # truncating a predecessor mask
    if dep_mask >> 1024:
        raise ValueError('dependency fan-in exceeds 1024-bit mask')
    for i in range(DEP_WORDS):
        w.append((dep_mask >> (32 * i)) & 0xffffffff)
    assert len(w) == NODE_WORDS
    return w


def parse_node(w):
    if len(w) != NODE_WORDS or w[0] != MAGIC_N:
        raise ValueError('bad node')
    mask = 0
    for i in range(DEP_WORDS):
        mask |= w[16 + i] << (32 * i)
    return dict(magic=w[0], type=w[1], id=w[2], flags=w[3], base=w[4],
                count=w[5], input_tid=w[6], output_tid=w[7],
                input_base=w[8], input_bytes=w[9], output_base=w[10],
                output_bytes=w[11], version=w[12], epoch=w[13],
                reserved=w[14:16], dep_mask=mask, words=list(w))


def emit(plan_base, nodes, param_end, *, generation=0, flags=0,
         input_base=EXTERNAL_BASE, input_limit=EXTERNAL_LIMIT,
         bad_hash=False, header_words=None):
    n = len(nodes)
    if not 1 <= n <= 1024:
        raise ValueError('node count 1..1024')
    plan_bytes = HEADER_WORDS * 4 + NODE_BYTES * n
    hw = [MAGIC_H, VERSION, n, flags, param_end, plan_bytes, generation, 0,
          input_base, input_limit, 0, 0, 0, 0, 0, 0]
    if header_words is not None:
        hw = list(header_words)
    h = hash_header(hw)
    for nd in nodes:
        if nd[0] != MAGIC_N:
            raise ValueError('node magic')
        h = hash_node(h, nd)
    hw[7] = h ^ (1 if bad_hash else 0)
    blob = bytearray(struct.pack('<16I', *hw))
    for nd in nodes:
        blob += struct.pack('<48I', *nd)
    if len(blob) != plan_bytes:
        raise ValueError('plan length')
    return bytes(blob), hw


def parse(blob):
    if len(blob) < HEADER_WORDS * 4 or (len(blob) - HEADER_WORDS * 4) % NODE_BYTES:
        raise ValueError('bad WCPG length')
    hw = list(struct.unpack_from('<16I', blob, 0))
    if hw[0] != MAGIC_H or hw[1] != VERSION:
        raise ValueError('bad WCPG magic/version')
    if hw[2] != (len(blob) - HEADER_WORDS * 4) // NODE_BYTES:
        raise ValueError('node count mismatch')
    if hw[5] != len(blob):
        raise ValueError('plan_bytes mismatch')
    h = hash_header(hw)
    nodes = []
    for i in range(hw[2]):
        w = list(struct.unpack_from('<48I', blob, HEADER_WORDS * 4 + NODE_BYTES * i))
        h = hash_node(h, w)
        nodes.append(parse_node(w))
    return dict(words=hw, nodes=nodes, hash=h)


def check_hash(blob):
    d = parse(blob)
    return d['words'][7] == d['hash']


if __name__ == '__main__':
    print('WCPG v2 helper; no side effects')
