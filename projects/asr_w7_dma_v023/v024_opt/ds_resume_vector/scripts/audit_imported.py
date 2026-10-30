#!/usr/bin/env python3
"""Audit the imported ds_vector_fma logs before trusting any of them.

The old worker exited 0 but produced no result.json and its run was interrupted
(see imported/logs/rc.txt).  This script:

  * reads the old fixture manifest (saved before regeneration);
  * re-runs the independent checker on every imported RTL dump that exists;
  * records missing dumps/logs and old rc entries;
  * never promotes an old PASS line to a result: the new run must regenerate
    every dump from the copied RTL.

Exit code is 0 for a completed audit (failures are reported, not hidden).  The
new run_all.sh gate is independent of this audit.
"""
import json, re, subprocess, sys
from pathlib import Path

HERE = Path(__file__).resolve().parents[1]
IMP = HERE / 'imported'
LOGS = IMP / 'logs'
REP = HERE / 'reports'
REP.mkdir(exist_ok=True)


def main():
    manifest_path = IMP / 'fixtures_manifest.json'
    if not manifest_path.exists():
        out = {'pass': False, 'error': 'missing imported/fixtures_manifest.json'}
        (REP / 'imported_audit.json').write_text(json.dumps(out, indent=2) + '\n')
        print(json.dumps(out, indent=2))
        return 1
    manifest = json.loads(manifest_path.read_text())
    cases = sorted(c['name'] for c in manifest['cases'])

    old_rc = {}
    rc_path = LOGS / 'rc.txt'
    if rc_path.exists():
        for ln in rc_path.read_text().splitlines():
            m = re.match(r'(\S+)\s+rc=(-?\d+)', ln)
            if m:
                old_rc[m.group(1)] = int(m.group(2))

    audited, bad, missing = [], [], []
    for c in cases:
        dump = LOGS / f'{c}.out.hex'
        log = LOGS / f'{c}.log'
        if not dump.exists() or not log.exists():
            missing.append(c)
            continue
        r = subprocess.run(
            [sys.executable, str(HERE / 'scripts/check_case.py'),
             '--case', str(HERE / 'fixtures/cases' / c),
             '--dump', str(dump), '--log', str(log)],
            capture_output=True, text=True)
        rec = {'case': c, 'check_rc': r.returncode,
               'line': (r.stdout.strip().splitlines() or [''])[-1]}
        if r.returncode == 0:
            audited.append(rec)
        else:
            bad.append(rec)

    x3 = sorted(p.name[:-4] for p in LOGS.glob('*_x3.log'))
    bp = sorted(p.name for p in LOGS.glob('*_bp_*.log'))
    out = {
        'source': str(LOGS),
        'case_count_in_imported_manifest': len(cases),
        'imported_dump_and_log_checked_ok': len(audited),
        'independent_check_failures': bad,
        'missing_dump_or_log': missing,
        'old_rc_entries': len(old_rc),
        'old_rc_has_tail_0270': 'sim_tail_0270' in old_rc,
        'old_rc_has_abort_newepoch': 'sim_abort_newepoch' in old_rc,
        'old_x3_logs': x3,
        'old_backpressure_logs': bp,
        'conclusion': (
            'The imported logs were audited, but they are NOT the acceptance '
            'evidence: ' + str(len(missing)) + ' case dump(s) are missing and '
            'the old run has no result.json.  Every case is re-run in this tree.'
        ),
    }
    out['pass'] = len(audited) + len(missing) + len(bad) == len(cases) and not bad
    (REP / 'imported_audit.json').write_text(json.dumps(out, indent=2) + '\n')
    print(json.dumps({k: out[k] for k in (
        'case_count_in_imported_manifest',
        'imported_dump_and_log_checked_ok',
        'missing_dump_or_log', 'independent_check_failures',
        'old_rc_entries', 'pass')}, indent=2))
    return 0


if __name__ == '__main__':
    sys.exit(main())
