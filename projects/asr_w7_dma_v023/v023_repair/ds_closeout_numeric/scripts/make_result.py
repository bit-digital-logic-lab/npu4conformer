#!/usr/bin/env python3
"""Assemble result.json from the independent check and run logs."""
import hashlib, json, re
from pathlib import Path

HERE = Path(__file__).resolve().parents[1]
ROOT = HERE.parent


def sha(p):
    return hashlib.sha256(Path(p).read_bytes()).hexdigest()


def rc_lines():
    out = {}
    p = HERE / 'logs/rc.txt'
    if p.exists():
        for ln in p.read_text().splitlines():
            m = re.match(r'(\S+) rc=(-?\d+)(?: seconds=(\d+))?', ln)
            if m:
                out[m.group(1)] = {'rc': int(m.group(2)),
                                   'seconds': int(m.group(3)) if m.group(3) else None}
    return out


def main():
    check = json.loads((HERE / 'reports/check_summary.json').read_text())
    uniq = json.loads((HERE / 'reports/unique_modules.json').read_text())
    meta = json.loads((HERE / 'fixtures/closeout_meta.json').read_text())
    logs = check['logs']
    rcs = rc_lines()
    numeric = {}
    for name in ('asr_fma_ip.sv', 'fp32_fma_pipe.sv', 'approx_div_sqrt.sv',
                 'approx_recip_lut.sv', 'approx_rsqrt_lut.sv'):
        numeric[name] = sha(HERE / 'rtl' / name)
    upstream = {}
    for label, p in (
        ('gemini_fma_round2/fp32_fma_pipe.sv', ROOT / 'gemini_fma_round2/candidate/fp32_fma_pipe.sv'),
        ('gemini_fma_round2/asr_fma_ip.sv', ROOT / 'gemini_fma_round2/candidate/asr_fma_ip.sv'),
        ('gemini_approx_round2/approx_div_sqrt.sv', ROOT / 'gemini_approx_round2/candidate/rtl/approx_div_sqrt.sv'),
        ('gemini_approx_round2/approx_recip_lut.sv', ROOT / 'gemini_approx_round2/candidate/rtl/approx_recip_lut.sv'),
        ('gemini_approx_round2/approx_rsqrt_lut.sv', ROOT / 'gemini_approx_round2/candidate/rtl/approx_rsqrt_lut.sv'),
    ):
        upstream[label] = sha(p)

    out = {
        'task': 'ds_closeout_numeric',
        'date': '2026-10-29',
        'scope': 'local logic simulation only; vector-numeric integration through shared AXI/WCPG',
        'not_claimed': [
            'full 591-tensor DAG / sealed payload re-lowering / host executor',
            'full-model WER/CER/CASE0000',
            'synthesis, Vivado/STA, board, VNC, git push',
            'matrix/layout abort-drain (only the vector path has abort)',
            'CDC/async FIFO or board frequency',
        ],
        'pass': check['pass'],
        'fails': check['fails'],
        'stale_gate_note': {
            'primary_acceptance_round2_fma': '8734 vectors, 0 mismatches, pass',
            'primary_acceptance_round2_approx': '15168 vectors, pass, DIV max 0.1114666%, SQRT 5.78e-6, RSQRT 5.72e-6',
            'integrated_old_report': 'quoted first-round FMA/approx failures; those are superseded by round-2 primary acceptance',
        },
        'numeric_sources_sha256': numeric,
        'upstream_candidate_sha256': upstream,
        'unique_filelist': {
            'path': 'filelist_closeout_numeric.f',
            'sha256': sha(HERE / 'filelist_closeout_numeric.f'),
            'files': uniq['files'], 'modules': uniq['modules'],
            'duplicates': uniq['duplicates'],
            'forbidden_stub_present': uniq['forbidden_stub_present'],
            'pass': uniq['pass'],
        },
        'vectors': meta['vectors'],
        'addresses': meta['addresses'],
        'exact_baseline': check['exact_baseline'],
        'candidate_approx': check['candidate_approx'],
        'epoch2_isolation': check['epoch2'],
        'cycles': {
            'exact': {'graph': logs['exact'].get('cycles'), 'vector': logs['exact'].get('vcyc'),
                      'done_cycle': logs['exact'].get('done_cycle'), 'last_b_cycle': logs['exact'].get('last_b_cycle')},
            'approx': {'graph': logs['approx'].get('cycles'), 'vector': logs['approx'].get('vcyc'),
                       'done_cycle': logs['approx'].get('done_cycle'), 'last_b_cycle': logs['approx'].get('last_b_cycle')},
        },
        'axi': {
            'exact': {k: logs['exact'].get(k) for k in ('rburst', 'wburst', 'rbeats', 'wbeats', 'tag_err')},
            'approx': {k: logs['approx'].get(k) for k in ('rburst', 'wburst', 'rbeats', 'wbeats', 'tag_err')},
        },
        'abort': logs['abort'],
        'reset': logs['reset'],
        'run_rc': rcs,
        'cited_evidence': {
            'primary_acceptance_cited_json_sha256': sha(HERE / 'reports/PRIMARY_ACCEPTANCE_CITED.json'),
            'snapshot_integrity_sha256': sha(HERE / 'reports/SNAPSHOT_INTEGRITY.txt'),
            'patch_sha256': sha(HERE / 'patch/closeout_numeric.patch'),
        },
        'deliverables': [
            'REPORT.md', 'INTERFACE.md', 'result.json', 'progress.json', 'USER_UPDATES.md',
            'filelist_closeout_numeric.f', 'run_all.sh', 'scripts/', 'tb/', 'rtl/',
            'patch/closeout_numeric.patch', 'logs/', 'reports/', 'SHA256SUMS.txt',
            'reports/NUMERIC_SOURCE_SHA256.txt', 'reports/UPSTREAM_SHA256.txt',
        ],
    }
    (HERE / 'result.json').write_text(json.dumps(out, indent=2))
    print(json.dumps({'pass': out['pass'], 'fails': out['fails']}, indent=2))


if __name__ == '__main__':
    main()
