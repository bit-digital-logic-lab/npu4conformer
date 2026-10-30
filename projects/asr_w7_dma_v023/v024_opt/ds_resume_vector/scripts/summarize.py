#!/usr/bin/env python3
"""Summarize the actual ds_vector_fma run logs into reports/summary.json and
a markdown table.  Reads only files produced by run_all.sh / baseline_compare.sh.
"""
import json, re
from pathlib import Path

HERE = Path(__file__).resolve().parents[1]
LOGS = HERE / 'logs'
REP = HERE / 'reports'


def field(text, name, cast=int, default=None):
    m = re.search(rf'{name}=(-?[0-9a-fA-Fx]+)', text)
    if not m:
        return default
    s = m.group(1)
    try:
        return cast(s, 0) if cast is int else cast(s)
    except Exception:
        return default


def parse_log(name):
    p = LOGS / f'{name}.log'
    if not p.exists():
        return {'case': name, 'exists': False}
    t = p.read_text()
    d = {
        'case': name, 'exists': True,
        'pass': 'VEC_FMA_PLAN PASS' in t or 'VEC_FMA_ABORT_RESET PASS' in t,
        'fail': 'FAIL' in t or 'CHECK_FAIL' in t,
        'vcyc': field(t, 'vcyc'),
        'done_cycle': field(t, 'done_cycle'),
        'last_b': field(t, 'last_b_cycle') if field(t, 'last_b_cycle') is not None else field(t, 'last_b'),
        'b_count_at_done': field(t, 'b_count_at_done') if field(t, 'b_count_at_done') is not None else field(t, 'b_count'),
        'b_after_done': field(t, 'b_after_done') if field(t, 'b_after_done') is not None else field(t, 'b'),
        'aw_after_done': field(t, 'aw_after_done') if field(t, 'aw_after_done') is not None else field(t, 'aw'),
        'rbeats': field(t, 'rbeats'),
        'wbeats': field(t, 'wbeats'),
        'rburst': field(t, 'rburst'),
        'wburst': field(t, 'wburst'),
        'vcompleted': field(t, 'vcompleted'),
        'vflags': field(t, 'vflags', lambda s: int(s, 16)),
        'vfault': field(t, 'vfault'),
        'vaborted': field(t, 'vaborted'),
        'total': field(t, 'total'),
    }
    return d


def main():
    reg = []
    p = REP / 'regression.tsv'
    if p.exists():
        for ln in p.read_text().splitlines():
            a = ln.split()
            if len(a) >= 3:
                reg.append((a[0], int(a[1]), int(a[2])))
    rc = {}
    p = LOGS / 'rc.txt'
    if p.exists():
        for ln in p.read_text().splitlines():
            m = re.match(r'(\S+)\s+rc=(-?\d+)', ln)
            if m:
                rc[m.group(1)] = int(m.group(2))
    cases = []
    for name, simrc, chkrc in reg:
        if name.startswith('x3:'):
            logname = f'{name[3:]}_x3'
        elif name.startswith('fma7:'):
            logname = f'{name[5:]}_fma7'
        else:
            logname = name
        d = parse_log(logname)
        d['reg_name'] = name
        d['sim_rc'] = simrc
        d['check_rc'] = chkrc
        cases.append(d)
    neg = {}
    p = REP / 'negative_control.txt'
    if p.exists():
        for ln in p.read_text().splitlines():
            if '=' in ln:
                k, v = ln.split('=', 1)
                neg[k] = v
    base = {}
    p = LOGS / 'rc_baseline.txt'
    if p.exists():
        for ln in p.read_text().splitlines():
            if '=' in ln:
                k, v = ln.split('=', 1)
                base[k] = v
    out = {
        'rc': rc,
        'cases': cases,
        'negative_control': neg,
        'baseline': base,
        'n_cases': len(cases),
        'all_pass': all(c['sim_rc'] == 0 and c['check_rc'] == 0 for c in cases) and bool(cases),
    }
    (REP / 'summary.json').write_text(json.dumps(out, indent=2) + '\n')

    print('| group | cases | sim rc | check rc | notes |')
    print('|---|---:|---:|---:|---|')
    groups = {}
    for c in cases:
        n = c['reg_name']
        if n.startswith('x3:'):
            g = 'latency x3'
        elif n.startswith('fma7:'):
            g = '7-stage core'
        elif n.startswith('tail_'):
            g = 'tails'
        elif n.startswith('mul_') or n.startswith('add_') or n.startswith('i16_'):
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
    for g, cs in sorted(groups.items()):
        sim = 'ok' if all(c['sim_rc'] == 0 for c in cs) else 'FAIL'
        chk = 'ok' if all(c['check_rc'] == 0 for c in cs) else 'FAIL'
        vc = [c['vcyc'] for c in cs if c.get('vcyc') is not None]
        note = f'vcyc {min(vc)}..{max(vc)}' if vc else ''
        print(f'| {g} | {len(cs)} | {sim} | {chk} | {note} |')
    print()
    for c in cases:
        if c['reg_name'] in ('full8734', 'official_fixture_1001',
                             'abort_newepoch', 'reset_newepoch'):
            print(f"- {c['reg_name']}: vcyc={c['vcyc']} done={c['done_cycle']} "
                  f"last_b={c['last_b']} b_at_done={c['b_count_at_done']} "
                  f"b_after={c['b_after_done']} aw_after={c['aw_after_done']} "
                  f"rbeats={c['rbeats']} wbeats={c['wbeats']} "
                  f"vcompleted={c['vcompleted']} vflags={c['vflags']}")

    return 0 if out['all_pass'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
