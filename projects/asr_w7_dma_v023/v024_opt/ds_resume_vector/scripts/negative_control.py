#!/usr/bin/env python3
"""Negative control: the independent checker MUST reject a corrupted gold word.

check_case.py --negative flips one reference bit and returns 1 when it detects
the mismatch.  This wrapper converts that expected rejection into a normal
test-harness rc=0 (all controls rejected as required) and rc=1 if any control
passes unexpectedly, so the top-level exit code is not inverted.
"""
import subprocess, sys
from pathlib import Path

HERE = Path(__file__).resolve().parents[1]
CASES = ['tail_0256', 'mul_0010']
REP = HERE / 'reports'
REP.mkdir(exist_ok=True)


def main():
    rows = []
    ok = True
    for c in CASES:
        cdir = HERE / 'fixtures/cases' / c
        dump = HERE / 'logs' / f'{c}.out.hex'
        log = HERE / 'logs' / f'{c}.log'
        if not dump.exists() or not log.exists():
            rows.append({'case': c, 'rc': None, 'observed': 'missing dump/log'})
            ok = False
            continue
        r = subprocess.run(
            [sys.executable, str(HERE / 'scripts/check_case.py'),
             '--case', str(cdir), '--dump', str(dump), '--log', str(log),
             '--negative'], capture_output=True, text=True)
        text = (r.stdout + r.stderr).strip()
        rejected = (r.returncode == 1 and 'CHECK_NEGATIVE_OK' in text)
        if not rejected:
            ok = False
        rows.append({'case': c, 'rc': r.returncode,
                     'observed': 'expected_failure' if rejected else 'unexpected',
                     'line': (text.splitlines() or [''])[-1]})
    lines = []
    for row in rows:
        lines.append(f"case={row['case']} rc={row['rc']} observed={row['observed']}")
        if row.get('line'):
            lines.append('  ' + row['line'])
    lines.append(f"controls={len(CASES)} expected_failure={sum(1 for r in rows if r['observed'] == 'expected_failure')}")
    lines.append(f"overall={'pass' if ok else 'fail'}")
    (REP / 'negative_control.txt').write_text('\n'.join(lines) + '\n')
    print('\n'.join(lines))
    return 0 if ok else 1


if __name__ == '__main__':
    sys.exit(main())
