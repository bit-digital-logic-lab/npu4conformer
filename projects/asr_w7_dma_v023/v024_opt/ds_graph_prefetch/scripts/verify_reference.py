#!/usr/bin/env python3
"""Verify frozen reference metadata and independently recompute the final gold.

The final gold is derived from the matrix integer golden (exp_c.txt) with an
independently written numpy float32 path.  RTL output is never used as a
reference.  Any mismatch exits non-zero.
"""
import hashlib
import json
import struct
import sys
from pathlib import Path

import numpy as np

HERE = Path(__file__).resolve().parents[1]
FREEZE = HERE / 'reference' / 'REFERENCE_FREEZE.json'


def sha(p):
    h = hashlib.sha256()
    with open(p, 'rb') as f:
        for chunk in iter(lambda: f.read(1 << 20), b''):
            h.update(chunk)
    return h.hexdigest()


def load_words(p):
    return [int(x, 16) for x in Path(p).read_text().split()]


def main():
    if not FREEZE.exists():
        print('FAIL missing', FREEZE)
        return 2
    frozen = json.loads(FREEZE.read_text())
    bad = []
    for rel, want in frozen['files'].items():
        got = sha(HERE / rel)
        if got != want:
            bad.append(f'{rel}: {got} != {want}')
    for rel, want in frozen['baseline_rtl'].items():
        got = sha(HERE / rel)
        if got != want:
            bad.append(f'{rel}: {got} != {want}')
    if bad:
        print('FAIL reference hash drift')
        for b in bad:
            print(' ', b)
        return 2

    exp = load_words(HERE / 'integrated_copy/fixtures/mat32/exp_c.txt')
    if len(exp) != 1024:
        print('FAIL exp_c length', len(exp))
        return 2
    # signed 48-bit
    xs = np.array([v - (1 << 48) if (v & (1 << 47)) else v for v in exp], dtype=np.int64)
    x = xs.astype(np.float32)
    y = np.float32(x * np.float32(2.0 ** -10))
    z = np.float32(y + np.float32(0.5))
    r = np.clip(np.rint(z.astype(np.float64)), -32768, 32767).astype(np.int16)
    words = []
    for i in range(0, 1024, 2):
        words.append((int(r[i]) & 0xffff) | ((int(r[i + 1]) & 0xffff) << 16))
    gold = load_words(HERE / 'integrated_copy/fixtures/gold_i16.hex')
    if len(gold) != 512:
        print('FAIL gold length', len(gold))
        return 2
    mism = sum(1 for a, b in zip(words, gold) if a != b)
    if mism:
        print('FAIL independent gold recompute mismatch', mism)
        return 2

    # Verify the plan blob SHA from the frozen memory image.
    mem = load_words(HERE / 'fixtures/mem_normal.hex')
    plan_base = 0x10008000
    plan_bytes = 1792
    off = (0xc0000 + (plan_base - 0x10000000)) // 4
    blob = b''.join(mem[off + i].to_bytes(4, 'little') for i in range(plan_bytes // 4))
    plan_sha = hashlib.sha256(blob).hexdigest()
    meta = json.loads((HERE / 'integrated_copy/fixtures/integrated_meta.json').read_text())
    if plan_sha != meta['plan_sha256']:
        print('FAIL plan sha', plan_sha, '!=', meta['plan_sha256'])
        return 2

    print(json.dumps({
        'reference_frozen': True,
        'gold_words': len(gold),
        'independent_gold_mismatches': 0,
        'plan_sha256': plan_sha,
    }, indent=2))
    return 0


if __name__ == '__main__':
    sys.exit(main())
