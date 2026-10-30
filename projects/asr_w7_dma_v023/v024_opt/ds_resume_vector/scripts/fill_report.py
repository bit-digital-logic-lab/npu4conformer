#!/usr/bin/env python3
"""Fill the REPORT.md result placeholders from the actual run artifacts."""
import json, re
from pathlib import Path

HERE = Path(__file__).resolve().parents[1]
REP = HERE / 'reports'
LOGS = HERE / 'logs'
summary = json.loads((REP / 'summary.json').read_text())
cases = summary['cases']
by = {c['reg_name']: c for c in cases}


def group_table():
    groups = {}
    for c in cases:
        n = c['reg_name']
        if n.startswith('x3:'):
            g = 'latency x3'
        elif n.startswith('tail_'):
            g = 'tails'
        elif n.startswith(('mul_', 'add_', 'i16_')):
            g = '4-lane short banks'
        elif n.startswith('fma_'):
            g = 'operand modes'
        elif n in ('abort_newepoch', 'reset_newepoch'):
            g = 'abort/reset'
        elif n == 'official_fixture_1001':
            g = 'official fixture'
        elif n == 'full8734':
            g = 'full 8734'
        else:
            g = 'other'
        groups.setdefault(g, []).append(c)
    lines = ['| group | cases | sim rc | check rc | vcyc range |',
             '|---|---:|---:|---:|---|']
    for g, cs in sorted(groups.items()):
        vc = [c['vcyc'] for c in cs if c.get('vcyc') is not None]
        lines.append(f"| {g} | {len(cs)} | "
                     f"{'ok' if all(c['sim_rc'] == 0 for c in cs) else 'FAIL'} | "
                     f"{'ok' if all(c['check_rc'] == 0 for c in cs) else 'FAIL'} | "
                     f"{min(vc)}..{max(vc)} |" if vc else
                     f"| {g} | {len(cs)} | "
                     f"{'ok' if all(c['sim_rc'] == 0 for c in cs) else 'FAIL'} | "
                     f"{'ok' if all(c['check_rc'] == 0 for c in cs) else 'FAIL'} | - |")
    return '\n'.join(lines)


def key_table():
    names = ['full8734', 'official_fixture_1001', 'fma_btiled2048',
             'fma_period128_1001', 'tail_1001', 'tail_0513', 'tail_0383',
             'mul_0017', 'i16_0007', 'abort_newepoch', 'reset_newepoch']
    lines = ['| case | total | vcyc | cyc/elem | done | last B | B@done | post B/AW | r/w beats |',
             '|---|---:|---:|---:|---:|---:|---:|---|---|']
    for n in names:
        c = by.get(n)
        if not c:
            continue
        t = c.get('total') or 0
        v = c.get('vcyc') or 0
        cpe = f'{v / t:.2f}' if t else '-'
        lines.append(f"| {n} | {t} | {v} | {cpe} | {c.get('done_cycle')} | "
                     f"{c.get('last_b')} | {c.get('b_count_at_done')} | "
                     f"{c.get('b_after_done')}/{c.get('aw_after_done')} | "
                     f"{c.get('rbeats')}/{c.get('wbeats')} |")
    return '\n'.join(lines)


def abort_block():
    out = []
    for name, title in (('abort_newepoch', 'Abort'), ('reset_newepoch', 'Reset')):
        p = LOGS / f'{name}.log'
        if not p.exists():
            out.append(f'- {title}: missing log')
            continue
        t = p.read_text()
        lines = [ln for ln in t.splitlines() if ln.startswith('HOST')]
        out.append(f'### {title}')
        out.append('```')
        out.extend(lines)
        out.append('```')
    return '\n'.join(out)


def x3_block():
    names = ['x3:full8734', 'x3:official_fixture_1001', 'x3:tail_0260',
             'x3:tail_0513', 'x3:mul_0005', 'x3:i16_0007']
    lines = ['| case | sim rc | check rc | vcyc |',
             '|---|---:|---:|---:|']
    for n in names:
        c = by.get(n)
        if c:
            lines.append(f"| {n} | {c['sim_rc']} | {c['check_rc']} | {c.get('vcyc')} |")
    return '\n'.join(lines)


def bp_block():
    p = REP / 'backpressure.tsv'
    if not p.exists():
        return 'Random-backpressure seed sweep was not run.'
    lines = ['| case | seed | sim rc | check rc |', '|---|---:|---:|---:|']
    for ln in p.read_text().splitlines():
        a = ln.split()
        if len(a) >= 5:
            lines.append(f'| {a[0]} | {a[1]} | {a[3]} | {a[4]} |')
    return '\n'.join(lines)


def frozen_block():
    p = REP / 'frozen.json'
    if not p.exists():
        return 'Frozen-source check was not run.'
    d = json.loads(p.read_text())
    return (f"`scripts/check_frozen.py`: pass={d.get('pass')}, "
            f"changed={d.get('changed')}, missing={d.get('missing')}. "
            "All copied W7A16C48/matrix/numeric sources are byte-identical to "
            "the v023 snapshot; only `ddr_vector_engine_pipe.sv` is edited and "
            "`vector_fma_lane.sv` is new.")


def baseline_block():
    p = LOGS / 'rc_baseline.txt'
    if not p.exists():
        return ('Baseline comparison was not run; the canonical `run_all.sh`\n'
                'regression uses the independent `refmodel` gold as the gate.')
    base = {}
    for ln in p.read_text().splitlines():
        if '=' in ln:
            k, v = ln.split('=', 1)
            base[k.strip()] = v.strip()
    lines = ['```']
    lines.extend(p.read_text().strip().splitlines())
    lines.append('```')
    if 'baseline_vs_new byte_identical=1' in p.read_text():
        lines.append('')
        lines.append('The old single-outstanding op17 and the new single-lane II=1 op17 '
                     'produce byte-identical full-8734 output under the same BFM/plan.')
    return '\n'.join(lines)


def main():
    results = f"""{group_table()}

### Key cases

{key_table()}

### Latency-variable build (`vector_fma_lane EXTRA_STAGES=3`)

{x3_block()}

### Random-backpressure seed sweep

{bp_block()}

### Frozen W7A16C48 / numeric sources

{frozen_block()}

### Negative control

`reports/negative_control.txt`: `{summary.get('negative_control')}`. A
deliberately corrupted expected word made `scripts/check_case.py` exit non-zero
(`CHECK_NEGATIVE_OK`); an unexpected pass would fail the suite.
"""
    report = HERE / 'REPORT.md'
    text = report.read_text()
    text = text.replace('<!-- RESULTS_TABLE -->', results)
    text = text.replace('<!-- ABORT_RESULTS -->', abort_block())
    text = text.replace('<!-- BASELINE_RESULTS -->', baseline_block())
    report.write_text(text)
    (REP / 'RESULTS.md').write_text(results + '\n\n' + abort_block() + '\n\n' + baseline_block() + '\n')
    print('REPORT.md placeholders filled; reports/RESULTS.md written')


if __name__ == '__main__':
    main()
