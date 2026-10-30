#!/usr/bin/env python3
"""Bounded search for the dependencies ds_graph/ds_integration reported missing.

Scope is deliberately limited to the local project, the original sealed ZIP,
and two adjacent local software trees.  No full-disk scan, no network.
"""
import hashlib, json, os, subprocess, sys, zipfile
from pathlib import Path

PROJ = Path('/home/yang/Desktop/项目')
HOME = Path('/home/yang/Desktop')
SCOPES = [PROJ, HOME/'当前工程文件', HOME/'software4npu']
ZIP = PROJ/'model_a_v0_22(1).zip'
NEEDLES = ('lowbit_executor.py', 'profiled_backend.py', 'vm_abi.py')

def sha(p):
    h = hashlib.sha256()
    with open(p, 'rb') as f:
        for b in iter(lambda: f.read(1 << 20), b''):
            h.update(b)
    return h.hexdigest()

def walk(scope):
    if not scope.exists():
        return
    for root, dirs, files in os.walk(scope):
        # bounded pruning of environments and caches
        dirs[:] = [d for d in dirs if d not in ('.git', '.venv', 'venv', '__pycache__',
                                                'node_modules', '.cache')]
        for f in files:
            yield Path(root)/f

found = {n: [] for n in NEEDLES}
onnx = []
executors = []
files_seen = 0
for scope in SCOPES:
    for p in walk(scope):
        files_seen += 1
        name = p.name
        if name in found:
            found[name].append(str(p))
        if name.lower().endswith('.onnx') and 'site-packages' not in str(p):
            onnx.append(str(p))
        if name in ('onnx_executor.py', 'onnx_executor_v5.py', 'model_a.py',
                    'model_manifest.py', 'fp32_reference.py', 'integer_reference.py'):
            executors.append(str(p))

zip_members = []
with zipfile.ZipFile(ZIP) as z:
    for n in z.namelist():
        if any(n.endswith(x) for x in NEEDLES) or n.lower().endswith('.onnx'):
            zip_members.append(n)

# Prove the host modules cannot be imported as-is.
import importlib, sys as _sys
_sys.path.insert(0, str(PROJ/'work'/'host'))
imports = {}
for m in ('base_v021', 'backend_v021', 'fusion_backend'):
    try:
        importlib.import_module(m)
        imports[m] = 'IMPORT_OK'
    except Exception as e:
        imports[m] = f'{type(e).__name__}: {e}'

onnx_info = []
for p in onnx:
    try:
        onnx_info.append({'path': p, 'bytes': Path(p).stat().st_size, 'sha256': sha(p)})
    except OSError as e:
        onnx_info.append({'path': p, 'error': str(e)})

res = {
    'scope': [str(s) for s in SCOPES],
    'files_seen': files_seen,
    'zip': str(ZIP),
    'missing_required_v022_host': {k: v for k, v in found.items()},
    'zip_hits_for_missing_or_onnx': zip_members,
    'host_import_probe': imports,
    'onnx_candidates': onnx_info,
    'executor_candidates': executors[:50],
    'conclusion': (
        'lowbit_executor.py / profiled_backend.py / vm_abi.py are absent from the bounded '
        'local scopes and the sealed ZIP; work/host imports fail. ONNX candidates found in '
        '当前工程文件/解压归档/v5_xc7a35t_frozen are an int16 QDQ model bundle for a different '
        '(xc7a35t v5) release, not proven to be the V022 W7p8/A16/C48 graph. They are an '
        'unblock lead only; they do not justify a recovered 591 tensor DAG or full CASE0000.'),
}
out = Path(__file__).resolve().parents[1] / 'analysis' / 'dependency_search.json'
out.write_text(json.dumps(res, indent=2))
print(json.dumps({'missing': found, 'onnx_count': len(onnx_info),
                  'imports': imports, 'zip_hits': zip_members}, indent=2))
print('wrote', out)
sys.exit(0)
