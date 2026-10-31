#!/usr/bin/env python3
"""Independent V0.24 checker.  Returns non-zero on any mismatch.

Reads only the RTL simulation dump and the frozen golden files produced by
scripts/gen_v024_graph.py.  No old result.json, no RTL-derived golden.
"""
import hashlib
import json
import struct
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parents[2]
FIX = HERE / 'sim' / 'fixtures'
LOG = HERE / 'logs'
FAIL = 0


def fail(msg):
    global FAIL
    print('FAIL', msg)
    FAIL += 1


def read_words(p):
    try:
        return [int(x, 16) for x in Path(p).read_text().split()]
    except (OSError, ValueError) as e:
        print('FAIL unreadable/non-hex output', p, e)
        sys.exit(2)


def f32(v):
    return struct.unpack('<f', struct.pack('<I', v & 0xffffffff))[0]


def main():
    # Frozen reference metadata: refuse to judge against a mutated fixture.
    if (HERE / 'reference_freeze.json').exists():
        frozen = json.loads((HERE / 'reference_freeze.json').read_text())
        for f, want in frozen.items():
            got = hashlib.sha256((HERE / f).read_bytes()).hexdigest()
            if got != want:
                fail(f'frozen reference changed: {f}')
    ref = json.loads((FIX / 'v024_ref.json').read_text())
    gold_a16 = read_words(FIX / 'gold_a16.hex')
    gold_fb = read_words(FIX / 'gold_fallback_i16.hex')

    # ---- fused plan ----
    out = read_words(LOG / 'v024_fused_out.hex')
    a16 = out[0:512]
    copy = out[3584:3584 + 512]
    div = out[1536:1536 + 1024]
    sq = out[2560:2560 + 1024]
    nm = sum(1 for a, b in zip(a16, gold_a16) if a != b)
    if nm:
        fail(f'fused A16 mismatch {nm}/512')
    nm = sum(1 for a, b in zip(copy, gold_a16) if a != b)
    if nm:
        fail(f'layout A16 copy mismatch {nm}/512')
    for name, got, gname, tol in (
            ('DIV', div, 'div_gold', ref['tolerances']['div_rel']),
            ('SQRT', sq, 'sqrt_gold', ref['tolerances']['sqrt_rel'])):
        gold = [f32(v) for v in ref[gname]]
        worst = 0.0
        bad = 0
        for g, w in zip(gold, got):
            v = f32(w)
            if v != v or abs(v) == float('inf'):
                bad += 1
                continue
            e = abs(v - g) / (abs(g) if g != 0 else 1.0)
            worst = max(worst, e)
            if e > tol:
                bad += 1
        print(f'INFO {name} worst_rel={worst:.3e} bad={bad}')
        if bad:
            fail(f'{name} tolerance {tol} exceeded for {bad} elements')
    log = (LOG / 'v024_fused.log').read_text()
    if 'V024_RESULT PASS' not in log:
        fail('fused run did not print V024_RESULT PASS')
    if 'V024_FUSION used=1 c48_ddr_bytes=0 a16_bytes=2048' not in log:
        fail('fused run did not prove explicit fusion with zero C48 DDR traffic')
    if 'V024_FUSED_C48_TRAFFIC' in log:
        fail('fused run reported C48 DDR traffic')
    if 'V024_ERROR_MISMATCH' in log or 'V024_TIMEOUT' in log:
        fail('fused run terminal-state error')

    # ---- fallback plan ----
    fbout = read_words(LOG / 'v024_fallback_out.hex')
    fb = fbout[7168:7168 + 512]
    nm = sum(1 for a, b in zip(fb, gold_fb) if a != b)
    if nm:
        fail(f'fallback I16 mismatch {nm}/512')
    fblog = (LOG / 'v024_fallback.log').read_text()
    if 'V024_RESULT PASS' not in fblog:
        fail('fallback run did not print V024_RESULT PASS')
    if 'V024_FUSION used=0' not in fblog:
        fail('fallback did not prove legacy (used=0) execution')
    if 'V024_FB_UNEXPECTED_FUSION' in fblog:
        fail('fallback unexpectedly fused')

    # ---- multi-consumer fallback ----
    mclog = (LOG / 'v024_multicons.log').read_text()
    if 'V024_RESULT PASS' not in mclog:
        fail('multi-consumer run did not print V024_RESULT PASS')
    if 'V024_FUSION used=0' not in mclog:
        fail('multi-consumer run did not fall back to legacy (used=0)')
    if 'V024_MC_UNEXPECTED_FUSION' in mclog:
        fail('multi-consumer run fused despite an untagged consumer')

    # ---- bad flag ----
    badlog = (LOG / 'v024_badflag.log').read_text()
    if 'V024_RESULT PASS' not in badlog:
        fail('badflag run did not reach expected 0x04 terminal')
    if 'error=04' not in badlog:
        fail('badflag run did not report error 04')

    # ---- hold B ----
    holdlog = (LOG / 'v024_hold.log').read_text()
    if 'V024_RESULT PASS' not in holdlog:
        fail('hold-B run did not reach isolation contract')
    import re
    m = re.search(r'V024_DRAIN .*b_pending=(\d+) .*quiesced=(\d)', holdlog)
    if not m or int(m.group(1)) == 0 or int(m.group(2)) != 0:
        fail('hold-B run did not prove a non-drained port (b_pending>0, quiesced=0)')

    # ---- directed FMA vs mul+add lane ----
    lane = read_words(LOG / 'v024_lane_out.hex')
    lg = read_words(FIX / 'lane_gold.hex')
    lm = read_words(FIX / 'lane_muladd.hex')
    nm = sum(1 for a, b in zip(lane, lg) if a != b)
    if nm:
        fail(f'FMA lane mismatch {nm}/64 against single-rounding gold')
    ndiff = sum(1 for a, b in zip(lg, lm) if a != b)
    print(f'INFO FMA vs mul+add differing vectors: {ndiff}/64')
    if ndiff < 16:
        fail('directed vectors do not separate single-rounding FMA from mul+add')

    print('V024_CHECK', 'FAIL' if FAIL else 'PASS')
    return 1 if FAIL else 0


if __name__ == '__main__':
    sys.exit(main())
