#!/usr/bin/env python3
"""Freeze the reference inputs and the exact v023 baseline RTL hashes.

This is run once; the generated reference/REFERENCE_FREEZE.json is then treated
as immutable.  verify_reference.py refuses to run if any hash changed.
"""
import hashlib
import json
from pathlib import Path

HERE = Path(__file__).resolve().parents[1]
OUT = HERE / 'reference' / 'REFERENCE_FREEZE.json'


def sha(p):
    h = hashlib.sha256()
    with open(p, 'rb') as f:
        for chunk in iter(lambda: f.read(1 << 20), b''):
            h.update(chunk)
    return h.hexdigest()


def main():
    files = [
        'fixtures/mem_normal.hex',
        'fixtures/mem_multitask.hex',
        'integrated_copy/fixtures/mem_integrated.hex',
        'integrated_copy/fixtures/gold_i16.hex',
        'integrated_copy/fixtures/mat32/exp_c.txt',
        'integrated_copy/fixtures/mat32/manifest.json',
        'integrated_copy/fixtures/mat32/init.hex',
        'integrated_copy/fixtures/integrated_meta.json',
    ]
    baseline = sorted(str(p.relative_to(HERE)) for p in (HERE / 'baseline_rtl').glob('*.sv'))
    d = {
        'note': 'frozen before the candidate runs; do not regenerate to make a failing run pass',
        'files': {p: sha(HERE / p) for p in files},
        'baseline_rtl': {p: sha(HERE / p) for p in baseline},
        'independent_gold': {
            'matrix': 'integrated_copy/fixtures/mat32/exp_c.txt (ds_matrix integer golden)',
            'final': 'integrated_copy/fixtures/gold_i16.hex (numpy float32 from exp_c, not RTL)',
        },
    }
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(json.dumps(d, indent=2, sort_keys=True) + '\n')
    print('wrote', OUT)


if __name__ == '__main__':
    main()
