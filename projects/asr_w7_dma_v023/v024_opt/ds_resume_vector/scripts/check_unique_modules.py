#!/usr/bin/env python3
"""Reject duplicate/missing module definitions in both delivered filelists."""
import json, re, sys
from pathlib import Path

HERE = Path(__file__).resolve().parents[1]
FILELISTS = ['filelist_vector_fma.f', 'filelist_vector_fma7.f']
required_once = ['vector_fma_lane', 'asr_fma_ip', 'fp32_fma_pipe',
                 'approx_div_sqrt', 'ddr_layout_engine',
                 'ddr_vector_engine_pipe', 'task_queue']
out = {'filelists': {}, 'pass': True}


def check(fl_name):
    fl = HERE / fl_name
    mods = {}
    files = []
    for ln in fl.read_text().splitlines():
        ln = ln.split('//')[0].strip()
        if not ln:
            continue
        p = HERE / ln
        files.append(ln)
        if not p.exists():
            return {'pass': False, 'error': f'missing {ln}'}
        for m in re.finditer(r'^\s*module\s+([A-Za-z_]\w*)', p.read_text(), re.M):
            mods.setdefault(m.group(1), []).append(ln)
    dups = {k: v for k, v in mods.items() if len(v) > 1}
    forbidden_stub = any('fma_forbidden_stub' in f for f in files)
    missing = [m for m in required_once if m not in mods]
    d = {
        'filelist': fl_name, 'files': len(files), 'modules': len(mods),
        'duplicates': dups, 'forbidden_stub_present': forbidden_stub,
        'required_present_once': {m: (m in mods and len(mods[m]) == 1)
                                  for m in required_once},
        'missing': missing,
    }
    d['pass'] = (not dups and not forbidden_stub and not missing and
                 all(d['required_present_once'].values()))
    d['fp32_fma_pipe_source'] = mods.get('fp32_fma_pipe')
    return d


for fl in FILELISTS:
    r = check(fl)
    out['filelists'][fl] = r
    out['pass'] = out['pass'] and r.get('pass', False)
(HERE / 'reports' / 'unique_modules.json').write_text(json.dumps(out, indent=2))
print(json.dumps(out, indent=2))
sys.exit(0 if out['pass'] else 1)
