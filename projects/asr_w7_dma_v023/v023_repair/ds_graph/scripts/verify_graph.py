#!/usr/bin/env python3
"""Independent verifier for WCPG v2 plans and the global tensor allocation.

Exit codes:
  0  plan accepted
  1  plan rejected (expected for negative tags with --expect-reject)
  2  malformed input / internal error
"""
import argparse
import json
import sys
from pathlib import Path

import graph_common as G

TASK = Path(__file__).resolve().parents[1]
A = TASK / 'analysis'


def readable(p, n, param_end, allow_external=True):
    if n <= 0 or p == 0:
        return False
    e = p + n
    if G.PARAM_BASE <= p and e <= param_end and param_end <= G.PARAM_LIMIT:
        return True
    if G.ARENA_BASE <= p and e <= G.ARENA_LIMIT:
        return True
    if allow_external and G.EXTERNAL_BASE <= p and e <= G.EXTERNAL_LIMIT:
        return True
    return False


def verify(path, alloc=None, strict=False):
    blob = Path(path).read_bytes()
    d = G.parse(blob)
    hw, nodes = d['words'], d['nodes']
    errs = []
    if hw[7] != d['hash']:
        errs.append('bad hash %08x != %08x' % (hw[7], d['hash']))
    n = hw[2]
    if not 1 <= n <= 1024:
        errs.append('node_count')
    if len(nodes) != n:
        errs.append('node count')
    if hw[15] != 0 or any(hw[10:15]):
        errs.append('reserved header words')
    roots = outputs = 0
    edges = 0
    type_count = {}
    for i, nd in enumerate(nodes):
        type_count[nd['type']] = type_count.get(nd['type'], 0) + 1
        if nd['id'] != i:
            errs.append('node %d id %d' % (i, nd['id']))
        if nd['type'] not in (G.T_MAT, G.T_VEC, G.T_LAY, G.T_SEQ, G.T_IN):
            errs.append('node %d type' % i)
        if nd['dep_mask'] >> 1024:
            errs.append('node %d dep width' % i)
        if nd['dep_mask'] & ~((1 << i) - 1):
            errs.append('node %d forward dependency' % i)
        edges += bin(nd['dep_mask']).count('1')
        if nd['flags'] & G.FLAG_ROOT:
            roots += 1
            if nd['dep_mask']:
                errs.append('node %d root with predecessors' % i)
            if not readable(nd['input_base'], nd['input_bytes'], hw[4]):
                errs.append('node %d root input provenance %x/%d' %
                            (i, nd['input_base'], nd['input_bytes']))
        else:
            if not nd['dep_mask'] and nd['type'] != G.T_IN:
                errs.append('node %d non-root without predecessor' % i)
        if nd['flags'] & G.FLAG_OUTPUT:
            outputs += 1
            if not readable(nd['output_base'], nd['output_bytes'], hw[4]):
                errs.append('node %d output address %x/%d' %
                            (i, nd['output_base'], nd['output_bytes']))
            if nd['output_tid'] == 0:
                errs.append('node %d output tid zero' % i)
        if nd['type'] == G.T_IN:
            if not (nd['flags'] & G.FLAG_ROOT):
                errs.append('node %d IN not root' % i)
            if not readable(nd['output_base'], nd['output_bytes'], hw[4]):
                errs.append('node %d IN provenance' % i)
        if nd['type'] == G.T_MAT:
            if nd['base'] < G.ARENA_BASE or nd['base'] >= G.ARENA_LIMIT:
                errs.append('node %d MAT base %x' % (i, nd['base']))
            if nd['count'] == 0:
                errs.append('node %d zero count' % i)
        if nd['type'] == G.T_SEQ:
            if not (G.PARAM_BASE <= nd['base'] < hw[4]):
                errs.append('node %d SEQ base %x outside param_end %x' %
                            (i, nd['base'], hw[4]))
            if nd['base'] + nd['count'] * 64 > hw[4]:
                errs.append('node %d SEQ extent outside param_end' % i)
            if nd['count'] == 0:
                errs.append('node %d zero count' % i)
        if nd['type'] in (G.T_VEC, G.T_LAY):
            if not (G.PARAM_BASE <= nd['base'] < hw[4]):
                errs.append('node %d payload base' % i)
    if (hw[3] & 4) and roots == 0:
        errs.append('header requires provenance but no root')
    if (hw[3] & 8) and outputs == 0:
        errs.append('header requires output but none flagged')

    # Allocation cross-check: every output tid must be unique live storage,
    # and every root input must equal its declared tensor base.
    if alloc is not None:
        by_id = {t['id']: t for t in alloc['tensors']}
        for i, nd in enumerate(nodes):
            if nd['output_tid']:
                t = by_id.get(nd['output_tid'])
                if t is None:
                    errs.append('node %d output tid %d not allocated' %
                                (i, nd['output_tid']))
                elif nd['flags'] & G.FLAG_OUTPUT and t['base'] != nd['output_base']:
                    errs.append('node %d output base != tensor map' % i)
            if nd['flags'] & G.FLAG_ROOT and nd['input_tid']:
                t = by_id.get(nd['input_tid'])
                if t is None:
                    errs.append('node %d input tid %d not allocated' %
                                (i, nd['input_tid']))
                elif t['base'] != nd['input_base']:
                    # The ledger uses fresh A bases even when the old queue
                    # base is shared; the tensor map is authoritative.
                    errs.append('node %d root input base != tensor map' % i)

    return dict(ok=not errs, errors=errs, node_count=n, roots=roots,
                outputs=outputs, edges=edges, type_count=type_count,
                hash=hw[7], plan_bytes=len(blob))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--plan', required=True)
    ap.add_argument('--tag', default='')
    ap.add_argument('--expect-reject', action='store_true')
    ap.add_argument('--alloc', default=None)
    args = ap.parse_args()
    alloc = json.loads(Path(args.alloc).read_text()) if args.alloc else None
    r = verify(args.plan, alloc)
    r['tag'] = args.tag
    print(json.dumps(r, indent=2))
    if args.expect_reject:
        return 0 if not r['ok'] else 1
    return 0 if r['ok'] else 1


if __name__ == '__main__':
    sys.exit(main())
