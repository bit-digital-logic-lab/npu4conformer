#!/usr/bin/env python3
"""Record cited read-only evidence and snapshot integrity (no writes outside)."""
import hashlib, json, subprocess
from pathlib import Path

HERE = Path(__file__).resolve().parents[1]
ROOT = HERE.parent
REP = HERE / 'reports'
REP.mkdir(exist_ok=True)


def sha(p):
    return hashlib.sha256(Path(p).read_bytes()).hexdigest()


def main():
    fma_p = ROOT / 'primary_acceptance/round2/result_primary_fma.json'
    ap_p = ROOT / 'primary_acceptance/round2/result_primary_approx.json'
    fma = json.loads(fma_p.read_text())
    ap = json.loads(ap_p.read_text())
    out = {
        'note': 'cited read-only primary acceptance; not rerun as full core suites here',
        'fma': {
            'path': 'primary_acceptance/round2/result_primary_fma.json',
            'sha256': sha(fma_p),
            'vectors': fma['tests']['fma']['vectors'],
            'mismatches': fma['tests']['fma']['mismatches'],
            'stability_errors': fma['tests']['fma']['stability_errors'],
            'pass': fma['tests']['fma']['pass'],
            'source_sha256': fma['source_sha256'],
        },
        'approx': {
            'path': 'primary_acceptance/round2/result_primary_approx.json',
            'sha256': sha(ap_p),
            'vectors': ap['tests']['approx_t1']['vectors'],
            'special_mismatch': ap['tests']['approx_t1']['special_mismatch'],
            'max_rel_err': ap['tests']['approx_t1']['max_rel_err'],
            'latency': ap['tests']['approx_t1']['latency'],
            'ii': ap['tests']['approx_t1']['ii'],
            'pass': ap['tests']['approx_t1']['pass'],
            'source_sha256': ap['source_sha256'],
        },
        'integrated_old_report_sha256': sha(ROOT / 'integrated/REPORT.md'),
        'primary_report_sha256': sha(ROOT / 'primary_acceptance/round2/REPORT.md'),
    }
    (REP / 'PRIMARY_ACCEPTANCE_CITED.json').write_text(json.dumps(out, indent=2))

    lines = []
    r = subprocess.run(['diff', '-qr', str(ROOT / 'integrated/rtl'), str(HERE / 'snapshot/integrated/rtl')],
                       capture_output=True, text=True)
    lines.append('integrated/rtl vs snapshot/integrated/rtl: ' +
                 ('identical (diff -qr)' if r.returncode == 0 else 'DIFFERS'))
    r = subprocess.run(['diff', '-q', str(ROOT / 'integrated/tb/tb_v023_integrated.sv'),
                        str(HERE / 'snapshot/integrated/tb/tb_v023_integrated.sv')],
                       capture_output=True, text=True)
    lines.append('integrated tb vs snapshot: ' + ('identical' if r.returncode == 0 else 'DIFFERS'))
    lines.append('primary_stream_fix: read-only, not modified')
    lines.append('work/ and ZIP: read-only, not modified')
    (REP / 'SNAPSHOT_INTEGRITY.txt').write_text('\n'.join(lines) + '\n')
    print(json.dumps({'fma': out['fma']['pass'], 'approx': out['approx']['pass'],
                      'snapshot': lines}, indent=2))


if __name__ == '__main__':
    main()
