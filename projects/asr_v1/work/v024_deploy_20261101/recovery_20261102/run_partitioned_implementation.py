"""Own and record one fixed shared16 Vivado stage; never accesses hardware."""
import argparse
import datetime
import hashlib
import importlib.util
import json
from pathlib import Path
import subprocess
import time

def now():
    return datetime.datetime.now().astimezone().isoformat()

def digest(p):
    return hashlib.sha256(p.read_bytes()).hexdigest()

parser = argparse.ArgumentParser()
parser.add_argument('stage', choices=['implement'])
parser.add_argument('--post-core-receipt', type=Path, required=True, help='completed independent post-core PROCESS_RECEIPT.json')
options = parser.parse_args()
root = Path(__file__).resolve().parent
out = root / 'partitioned_shared16'
shared = root / 'shared16_candidate'
script = out / (options.stage + '.tcl')
gate = out / 'reports' / ('ROOT_FUNCTIONAL_ACCEPTANCE.json' if options.stage == 'synth' else 'READY_FOR_IMPLEMENTATION.json')
g = json.loads(gate.read_text(encoding='utf-8-sig'))
if g['status'] != 'PASS':
    raise RuntimeError('Review gate is not PASS')
manifest = shared / 'reports/SOURCE_MANIFEST.json'
m = json.loads(manifest.read_text(encoding='utf-8-sig'))
for relative, sha in m['frozen_files'].items():
    if digest(shared / relative) != sha:
        raise RuntimeError('Frozen input changed: ' + relative)
if digest(manifest) != g['source_manifest_sha256']:
    raise RuntimeError('Source manifest differs from independent review')
if options.stage == 'implement':
    plan = json.loads((out / 'reports/IMPLEMENTATION_PLAN.json').read_text(encoding='utf-8-sig'))
    if digest(out / 'reports/LEAF_ACCEPTANCE.json') != g['leaf_acceptance_sha256'] or digest(out / 'build/array16_ooc_clockless.dcp') != g['leaf_checkpoint_sha256']:
        raise RuntimeError('Reviewed leaf checkpoint changed')
    if digest(out / 'reports/PARTITION_PLAN.json') != g['partition_plan_sha256']:
        raise RuntimeError('Partition plan changed')
    if digest(script) != plan['script_sha256'] or digest(script) != g['implementation_script_sha256']:
        raise RuntimeError('Implementation script differs from reviewed plan/gate')
    if digest(out / 'build/candidate_synth.dcp') != g['core_checkpoint_sha256']:
        raise RuntimeError('Synthesis checkpoint changed since review')
    if digest(out / 'build/platform_synth_copy.dcp') != g['platform_checkpoint_sha256']:
        raise RuntimeError('Platform checkpoint changed since review')
# Independent post-core review is a required gate, not a routed-closure claim.
gate_module_path = root / 'post_core_gate.py'
spec = importlib.util.spec_from_file_location('partitioned_post_core_gate', gate_module_path)
if spec is None or spec.loader is None:
    raise RuntimeError('Unable to load independent post-core gate')
gate_module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(gate_module)
post_core = gate_module.verify_postcore(options.post_core_receipt, out, g)
stamp = datetime.datetime.now().strftime('%Y%m%d_%H%M%S')
runid = options.stage + '_' + stamp
logdir = out / 'logs'
logdir.mkdir(exist_ok=True)
receipt_path = out / 'reports' / (runid + '_process.json')
receipt = {'status': 'RUNNING', 'stage': options.stage, 'started': now(),
           'scope': 'shared16 isolated build; no hardware access',
           'source_manifest_sha256': digest(manifest), 'script_sha256': digest(script),
           'post_core_receipt_sha256': post_core['receipt_sha256'],
           'post_core_acceptance_sha256': post_core['acceptance_sha256'],
           'post_core_gate_script_sha256': digest(gate_module_path),
           'post_core_scope': post_core['scope'],
           'vivado_log': str(logdir / (runid + '.log'))}
vivado = Path('C:/Academic_Application/Vivado/2025.2/Vivado/bin/vivado.bat')
args = ['cmd.exe', '/d', '/c', str(vivado), '-mode', 'batch', '-nojournal',
        '-log', receipt['vivado_log'], '-source', str(script)]
start = time.monotonic()
with (logdir / (runid + '_console.log')).open('w', encoding='utf-8') as stream:
    child = subprocess.Popen(args, cwd=out, stdout=stream, stderr=subprocess.STDOUT,
                             creationflags=subprocess.CREATE_NO_WINDOW)
    receipt['launcher_pid'] = child.pid
    receipt_path.write_text(json.dumps(receipt, indent=2) + '\n', encoding='utf-8')
    print(json.dumps(receipt), flush=True)
    code = child.wait()
receipt.update(status='PROCESS_EXITED', exit_code=code, elapsed_seconds=round(time.monotonic()-start, 3), finished=now())
receipt_path.write_text(json.dumps(receipt, indent=2) + '\n', encoding='utf-8')
print(json.dumps(receipt), flush=True)
raise SystemExit(code)
