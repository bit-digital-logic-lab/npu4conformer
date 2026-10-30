#!/usr/bin/env python3
"""Summarize the export run from logs/ into docs/verification/RESULTS.md.

Exits non-zero if a run failed or a required marker is absent.  It reads only
logs produced by scripts/sim/run_export.sh.
"""
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
LOG = ROOT / 'logs'
FAIL = 0


def rd(name):
    p = LOG / name
    return p.read_text(errors='replace') if p.exists() else ''


def need(text, pat, label):
    global FAIL
    if not re.search(pat, text, re.S):
        print('FAIL missing', label)
        FAIL += 1


def main():
    rc = {}
    for ln in rd('rc.tsv').splitlines():
        if not ln.strip():
            continue
        parts = ln.split('\t')
        if len(parts) >= 2:
            rc[parts[0]] = int(parts[1])

    fused = rd('v024_fused.log')
    fb = rd('v024_fallback.log')
    mc = rd('v024_multicons.log')
    bad = rd('v024_badflag.log')
    hold = rd('v024_hold.log')
    lane = rd('v024_lane.log')
    check = rd('check_export.log')

    need(fused, r'V024_RESULT PASS', 'fused PASS')
    need(fused, r'V024_FUSION used=1 c48_ddr_bytes=0 a16_bytes=2048', 'fused zero-C48 traffic')
    need(fused, r'V024_DRAIN .*b_pending=0 .*quiesced=1', 'fused drain')
    need(fb, r'V024_RESULT PASS', 'fallback PASS')
    need(fb, r'V024_FUSION used=0', 'fallback used=0')
    need(fb, r'V024_DRAIN .*b_pending=0 .*quiesced=1', 'fallback drain')
    need(mc, r'V024_RESULT PASS', 'multicons PASS')
    need(mc, r'V024_FUSION used=0', 'multicons used=0')
    need(bad, r'V024_RESULT PASS', 'badflag PASS')
    need(bad, r'error=04', 'badflag error 0x04')
    need(hold, r'V024_RESULT PASS', 'hold PASS')
    need(hold, r'b_pending=[1-9]\d*.*quiesced=0', 'hold non-drain')
    need(hold, r'requires_reset=1', 'hold requires_reset')
    need(lane, r'V024_LANE_RESULT PASS', 'lane PASS')
    need(lane, r'V024_LANE seen=64 gold_mismatch=0', 'lane 64/64')
    need(check, r'V024_CHECK PASS', 'independent judge')

    for name in ['base_normal', 'base_multitask']:
        t = rd(name + '.log')
        need(t, r'SAFETY_RESULT PASS', name + ' PASS')
        need(t, r'b_pending=0.*quiesced=1', name + ' drain')
    need(rd('base_bad_queue_magic.log'), r'SAFETY_RESULT PASS', 'bad queue magic')
    need(rd('base_bad_vec_op.log'), r'SAFETY_RESULT PASS', 'bad vector op')
    need(rd('base_hold_b_c.log'), r'SAFETY_RESULT PASS', 'base hold B')

    def grab(text, pat, cast=str):
        m = re.search(pat, text)
        return cast(m.group(1)) if m else None

    table = [
        ('v024_fused', fused, grab(fused, r'V024_END .*cycles=(\d+)', int)),
        ('v024_fallback', fb, grab(fb, r'V024_END .*cycles=(\d+)', int)),
        ('v024_multicons', mc, grab(mc, r'V024_END .*cycles=(\d+)', int)),
        ('v024_badflag', bad, grab(bad, r'V024_END .*cycles=(\d+)', int)),
        ('v024_hold', hold, grab(hold, r'V024_END .*cycles=(\d+)', int)),
    ]

    lines = ['# Export run results', '',
             f'Run log: `docs/verification/logs/run_export_console.log`; '
             f'per-run rc: `docs/verification/logs/rc.tsv`.',
             '', '## Per-run status', '', '| run | rc | cycles |', '|---|---:|---:|']
    for name, _, cyc in table:
        lines.append(f'| {name} | {rc.get(name, "missing")} | {cyc if cyc is not None else "—"} |')
    for name in ['v024_lane', 'base_normal', 'base_multitask',
                 'base_bad_queue_magic', 'base_bad_vec_op', 'base_hold_b_c']:
        lines.append(f'| {name} | {rc.get(name, "missing")} | — |')
    lines += ['', '## Judge output', '', '```', check.strip(), '```', '',
              '## Key terminal lines', '', '```']
    for name in ['v024_fused', 'v024_fallback', 'v024_hold']:
        for ln in rd(name + '.log').splitlines():
            if re.match(r'V024_(FUSION|DRAIN|END|RESULT)', ln):
                lines.append(ln)
    lines += ['```', '',
              'No synthesis, STA, board, VNC or push. No frequency or',
              'whole-model-seconds claim.']

    out = ROOT / 'docs' / 'verification' / 'RESULTS.md'
    out.write_text('\n'.join(lines) + '\n')

    perf = {
        'fixture': 'V0.24 unified small graph',
        'runs': {name: {'rc': rc.get(name), 'cycles': cyc}
                 for name, _, cyc in table},
        'base_smoke_rc': {n: rc.get(n) for n in
                          ['base_normal', 'base_multitask',
                           'base_bad_queue_magic', 'base_bad_vec_op',
                           'base_hold_b_c']},
        'fused_c48_ddr_bytes': 0 if 'c48_ddr_bytes=0' in fused else None,
        'fused_a16_bytes': grab(fused, r'a16_bytes=(\d+)', int),
        'div_worst_rel': grab(check, r'DIV worst_rel=([0-9.eE+-]+)', float),
        'sqrt_worst_rel': grab(check, r'SQRT worst_rel=([0-9.eE+-]+)', float),
        'fma_vs_muladd_diff': grab(check, r'differing vectors: (\d+)/64', int),
        'note': 'logic cycles only; not additive; no whole-model or board claim',
    }
    (ROOT / 'docs' / 'performance' / 'MEASURED_RUN.json').write_text(
        json.dumps(perf, indent=2) + '\n')
    print(json.dumps(perf, indent=2))
    return 1 if FAIL else 0


if __name__ == '__main__':
    sys.exit(main())
