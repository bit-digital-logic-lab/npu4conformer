#!/usr/bin/env python3
"""Independent verifier for W023 superplans.

Checks binary framing/hash, node order/dependency topology, and (for the real
68-program candidate) that every pair of nodes not ordered by the dependency
closure still has disjoint DDR read/write spans.  The roots candidate is
expected to FAIL this last test; that failure is the aliasing counter-example.
"""
import argparse, hashlib, json, struct
from pathlib import Path

HERE = Path(__file__).resolve().parents[1]
OUT = HERE / 'analysis'
MAGIC_H = 0x5743504c
MAGIC_N = 0x57434e44
VERSION = 0x00010001
HASH_SEED = 0x811c9dc5


def fnv(h, w):
    return ((h ^ (w & 0xffffffff)) * 0x01000193) & 0xffffffff


def read_plan(blob):
    if len(blob) < 64 or len(blob) % 64:
        raise ValueError('framing')
    hw = list(struct.unpack_from('<16I', blob, 0))
    if hw[0] != MAGIC_H or hw[1] != VERSION:
        raise ValueError('header magic/version')
    if hw[2] < 1 or hw[2] > 128 or hw[5] != 64 + 64 * hw[2]:
        raise ValueError('header count/size')
    if len(blob) != hw[5]:
        raise ValueError('file size')
    h = HASH_SEED
    for j, v in enumerate(hw):
        if j != 7:
            h = fnv(h, v)
    nodes = []
    for i in range(hw[2]):
        nd = list(struct.unpack_from('<16I', blob, 64 + 64 * i))
        for v in nd:
            h = fnv(h, v)
        nodes.append(nd)
    return hw, nodes, h


def overlap(a, b):
    return a[0] < b[1] and b[0] < a[1]


def closure(nodes):
    n = len(nodes)
    pred = []
    for nd in nodes:
        m = nd[3] | (nd[4] << 32) | (nd[5] << 64) | (nd[6] << 96)
        pred.append(m)
    anc = [0] * n
    for i in range(n):
        # Nodes may only depend on lower ids, so one pass is sufficient.
        a = pred[i]
        m = a
        while m:
            b = m & -m
            j = b.bit_length() - 1
            m &= ~b
            m |= pred[j] & ~a
            a |= pred[j]
        anc[i] = a
    return pred, anc


def ordered(anc, i, j):
    return (i < j and (anc[j] >> i) & 1) or (j < i and (anc[i] >> j) & 1)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--plan', required=True)
    ap.add_argument('--tag', required=True)
    ap.add_argument('--allow-conflicts', action='store_true')
    args = ap.parse_args()
    blob = Path(args.plan).read_bytes()
    hw, nodes, h = read_plan(blob)
    checks = []
    if h != hw[7]:
        checks.append('hash mismatch')
    for i, nd in enumerate(nodes):
        if nd[0] != MAGIC_N or nd[2] != i or nd[1] not in (1, 2, 3, 4):
            checks.append(f'node {i} framing/type/id')
        m = nd[3] | (nd[4] << 32) | (nd[5] << 64) | (nd[6] << 96)
        if m & ~((1 << i) - 1):
            checks.append(f'node {i} non-topological dependency')
        if nd[15] != 0 or nd[14] != 0 or nd[12] != 0 or nd[13] == 0:
            checks.append(f'node {i} reserved/epoch')
    pred, anc = closure(nodes)
    progs = json.loads((OUT / 'programs.json').read_text())
    if args.tag == 'real68':
        by_addr = {p['plan_address']: p for p in progs.values()}
        for i, nd in enumerate(nodes):
            p = by_addr.get(nd[7])
            if p is None or p['plan_count'] != nd[8]:
                checks.append(f'node {i} plan pointer/count not in manifest')
    # Unordered memory conflicts using the independently merged spans.
    keys = list(progs)
    conflicts = []
    for i in range(len(nodes)):
        for j in range(i + 1, len(nodes)):
            if ordered(anc, i, j):
                continue
            # Match nodes to programs by plan address.
            pa = next((p for p in progs.values() if p['plan_address'] == nodes[i][7]), None)
            pb = next((p for p in progs.values() if p['plan_address'] == nodes[j][7]), None)
            if pa is None or pb is None:
                continue
            kinds = set()
            for wa in pa['writes']:
                for wb in pb['writes']:
                    if overlap(wa, wb):
                        kinds.add('WAW')
                for rb in pb['reads']:
                    if overlap(wa, rb):
                        kinds.add('RAW')
            for ra in pa['reads']:
                for wb in pb['writes']:
                    if overlap(ra, wb):
                        kinds.add('WAR')
            if kinds:
                conflicts.append(dict(a=i, b=j, kinds=sorted(kinds)))
    status = 'PASS' if not checks and (not conflicts or args.allow_conflicts) else 'FAIL'
    result = dict(tag=args.tag, plan=args.plan, sha256=hashlib.sha256(blob).hexdigest(),
                  status=status, node_count=len(nodes), plan_bytes=len(blob),
                  hash_ok=h == hw[7], checks=checks,
                  unordered_conflicts=len(conflicts),
                  conflict_examples=conflicts[:8],
                  dependency_edges=sum(bin(x).count('1') for x in pred),
                  max_predecessors=max((bin(x).count('1') for x in pred), default=0),
                  notes='Conflicts are expected for whole68_roots.bin and reject parallel execution; whole68_serial.bin must have zero.')
    (OUT / f'verify_{args.tag}.json').write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps({k: v for k, v in result.items() if k != 'conflict_examples'}, indent=2))
    if status != 'PASS':
        raise SystemExit(1)


if __name__ == '__main__':
    main()
