#!/usr/bin/env python3
"""Random compiler/format tests, independent of RTL.

Generates topological random DAGs, emits WCPL binaries, re-parses them with the
independent verifier, and checks that a Python scheduler completes every node.
Also checks the two negative invariants: forward dependencies (cycles) and a
corrupted integrity hash are rejected.
"""
import json, random, sys
from pathlib import Path

HERE = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(HERE / 'scripts'))
import wc_compile as C
import wc_verify_plan as V


def schedule(nodes):
    pred, anc = V.closure(nodes)
    done = 0
    order = []
    while len(order) < len(nodes):
        progressed = False
        for i, nd in enumerate(nodes):
            if (done >> i) & 1:
                continue
            m = nd[3] | (nd[4] << 32) | (nd[5] << 64) | (nd[6] << 96)
            if m & ~done == 0:
                done |= 1 << i
                order.append(i)
                progressed = True
                break
        if not progressed:
            raise RuntimeError('deadlock/cycle')
    return order, anc


def main():
    rng = random.Random(20261029)
    rows = []
    for trial in range(200):
        n = rng.randint(1, 128)
        nodes = []
        masks = []
        for i in range(n):
            m = 0
            if i:
                for j in rng.sample(range(i), rng.randint(0, min(5, i))):
                    m |= 1 << j
            masks.append(m)
            nodes.append(C.node(i, 0x10000000 + i * 0x100, 1, m, i + 1))
        blob = C.emit(0x10000000, nodes, 0x40000000)
        hw, parsed, h = V.read_plan(blob)
        if h != hw[7]:
            raise RuntimeError('hash')
        pm = [x[3] | (x[4] << 32) | (x[5] << 64) | (x[6] << 96) for x in parsed]
        if pm != masks:
            raise RuntimeError('mask roundtrip')
        order, anc = schedule(parsed)
        if len(order) != n:
            raise RuntimeError('schedule length')
        rows.append(dict(trial=trial, n=n, edges=sum(bin(x).count('1') for x in masks),
                         max_dep=max((bin(x).count('1') for x in masks), default=0)))
    # Negative 1: node i depends on node j>i (a cycle/forward edge).
    bad = [C.node(0, 0x10000000, 1, 2, 1), C.node(1, 0x10000000, 1, 1, 2)]
    bw, bn, bh = V.read_plan(C.emit(0x10000000, bad, 0x40000000))
    stuck = 0
    done = 0
    for _ in range(len(bn)):
        progressed = False
        for i, nd in enumerate(bn):
            m = nd[3] | (nd[4] << 32) | (nd[5] << 64) | (nd[6] << 96)
            if not ((done >> i) & 1) and m & ~done == 0:
                done |= 1 << i
                progressed = True
        if not progressed:
            break
    if done == (1 << len(bn)) - 1:
        raise RuntimeError('forward-dep cycle was accepted')
    stuck = 1
    # Negative 2: bad hash.
    blob = C.emit(0x10000000, [C.node(0, 0x10000000, 1, 0, 1)], 0x40000000, bad_hash=True)
    hw, _, h = V.read_plan(blob)
    hash_bad = h != hw[7]
    # Negative 3: 129 nodes cannot fit the candidate controller.
    try:
        V.read_plan(C.emit(0x10000000, [C.node(i, 0x10000000, 1, 0, i + 1) for i in range(129)], 0x40000000))
        count_bad = False
    except ValueError:
        count_bad = True
    result = dict(trials=len(rows), passed=len(rows), negative_forward_dep_rejected=stuck,
                  negative_hash_rejected=hash_bad, negative_129_nodes_rejected=count_bad,
                  max_nodes=max(r['n'] for r in rows), max_edges=max(r['edges'] for r in rows),
                  rows=rows[:20])
    (HERE / 'reports/compiler_random.json').write_text(json.dumps(result, indent=2) + '\n')
    print('WC_COMPILER_RANDOM_PASS', len(rows), 'forward_rejected', stuck,
          'hash_rejected', hash_bad, '129_rejected', count_bad)


if __name__ == '__main__':
    main()
