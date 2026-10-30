#!/usr/bin/env python3
"""Reject duplicate module definitions in the delivered unique filelist."""
import json, re, sys
from pathlib import Path

HERE = Path(__file__).resolve().parents[1]
FL = HERE / 'filelist_vector_fma.f'
mods = {}
files = []
for ln in FL.read_text().splitlines():
    ln = ln.split('//')[0].strip()
    if not ln:
        continue
    p = HERE / ln
    files.append(ln)
    if not p.exists():
        print(json.dumps({'pass': False, 'error': f'missing {ln}'}))
        sys.exit(1)
    for m in re.finditer(r'^\s*module\s+([A-Za-z_]\w*)', p.read_text(), re.M):
        mods.setdefault(m.group(1), []).append(ln)

dups = {k: v for k, v in mods.items() if len(v) > 1}
forbidden_stub = any('fma_forbidden_stub' in f for f in files)
required_once = ['vector_fma_lane', 'asr_fma_ip', 'fp32_fma_pipe',
                 'approx_div_sqrt', 'ddr_layout_engine',
                 'ddr_vector_engine_pipe', 'task_queue']
missing = [m for m in required_once if m not in mods]
out = {
    'filelist': str(FL), 'files': len(files), 'modules': len(mods),
    'duplicates': dups, 'forbidden_stub_present': forbidden_stub,
    'required_present_once': {m: (m in mods and len(mods[m]) == 1) for m in required_once},
    'missing': missing,
}
out['pass'] = not dups and not forbidden_stub and not missing and all(out['required_present_once'].values())
(HERE / 'reports' / 'unique_modules.json').write_text(json.dumps(out, indent=2))
print(json.dumps(out, indent=2))
sys.exit(0 if out['pass'] else 1)
