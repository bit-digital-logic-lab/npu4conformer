#!/usr/bin/env python3
"""Independent allocation checker, including a deliberate conflict negative.

Acceptance requires:
  * every tensor inside its declared region;
  * no two tensors with overlapping live intervals overlap in bytes;
  * the deliberate negative example (two live outputs at one base) is rejected.
"""
import json
import sys
from pathlib import Path

TASK = Path(__file__).resolve().parents[1]
A = TASK / 'analysis'


def overlap(a0, a1, b0, b1):
    return a0 < b1 and b0 < a1


def check(alloc):
    errs = []
    regions = {'arena': (alloc['arena']['base'], alloc['arena']['limit']),
               'external': (alloc['external']['base'], alloc['external']['limit'])}
    for t in alloc['tensors']:
        lo, hi = regions[t['region']]
        if not (lo <= t['base'] and t['base'] + t['bytes'] <= hi):
            errs.append('tensor %s outside region' % t['name'])
    n = len(alloc['tensors'])
    for i in range(n):
        a = alloc['tensors'][i]
        for j in range(i + 1, n):
            b = alloc['tensors'][j]
            if not overlap(a['live'][0], a['live'][1], b['live'][0], b['live'][1]):
                continue
            if overlap(a['base'], a['base'] + a['bytes'],
                       b['base'], b['base'] + b['bytes']):
                errs.append('live overlap %s / %s' % (a['name'], b['name']))
    return errs


def main():
    alloc = json.loads((A / 'global_alloc.json').read_text())
    errs = check(alloc)
    bad = alloc['negative_example']
    bad_err = []
    if overlap(bad['live_a'][0], bad['live_a'][1],
               bad['live_b'][0], bad['live_b'][1]):
        # same base and overlapping live -> conflict
        bad_err.append('negative example: live tensors share base %x' % bad['base'])
    out = dict(alloc_ok=not errs, alloc_errors=errs,
               negative_supplied=bad, negative_detected=bool(bad_err),
               negative_errors=bad_err,
               old_same_base_pairs=alloc['old_same_base_pairs'],
               old_same_base_pairs_live_simultaneously=alloc[
                   'old_same_base_pairs_live_simultaneously'],
               arena_used=alloc['arena']['used'],
               external_used=alloc['external']['used'])
    (A / 'alloc_check.json').write_text(json.dumps(out, indent=2) + '\n')
    print(json.dumps(out, indent=2))
    return 0 if (not errs and bad_err) else 1


if __name__ == '__main__':
    sys.exit(main())
