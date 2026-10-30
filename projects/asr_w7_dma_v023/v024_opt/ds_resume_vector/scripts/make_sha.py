#!/usr/bin/env python3
"""Write SHA256SUMS.txt for the delivered ds_vector_fma tree."""
import hashlib
from pathlib import Path

HERE = Path(__file__).resolve().parents[1]
files = []
fl = HERE / 'filelist_vector_fma.f'
for ln in fl.read_text().splitlines():
    ln = ln.split('//')[0].strip()
    if ln:
        files.append(ln)
files += [
    'filelist_vector_fma.f', 'filelist_baseline.f', 'run_all.sh',
    'baseline_compare.sh', 'backpressure_seeds.sh',
    'tb/tb_vector_fma_plan.sv', 'tb/tb_vector_fma_abort_reset.sv',
    'tb/wc_graph_bfm.sv',
    'scripts/gen_cases.py', 'scripts/check_case.py',
    'scripts/check_unique_modules.py', 'scripts/make_result.py',
    'scripts/check_frozen.py', 'scripts/summarize.py',
    'scripts/fill_report.py', 'scripts/make_sha.py',
    'fixtures/manifest.json',
    'REPORT.md', 'INTERFACE.md', 'README.md', 'progress.json',
    'USER_UPDATES.md', 'result.json',
]
seen = set()
lines = []
for f in files:
    if f in seen:
        continue
    seen.add(f)
    p = HERE / f
    if p.exists():
        lines.append(f'{hashlib.sha256(p.read_bytes()).hexdigest()}  {f}')
    else:
        lines.append(f'MISSING  {f}')
(HERE / 'SHA256SUMS.txt').write_text('\n'.join(lines) + '\n')
print(f'SHA256SUMS.txt: {len(lines)} entries')
if any(x.startswith('MISSING') for x in lines):
    raise SystemExit(1)
