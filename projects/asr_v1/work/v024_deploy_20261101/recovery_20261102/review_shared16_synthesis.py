"""Review one completed shared16 retry; emit implementation gate only on proof.

Usage: python -I review_shared16_synthesis.py path/to/synth_reuse_ip_*_process.json
No Vivado, synthesis, implementation, or hardware is started by this script.
"""
from pathlib import Path
import argparse
import datetime as dt
import hashlib
import json
import re
import sys

ROOT = Path(__file__).resolve().parent
OUT = ROOT / 'shared16_candidate'
REPORTS = OUT / 'reports'
EXPECTED_IP_DCP = '3398344c3a787c46194e63ef81cd5968daa2bbcbd13176d1c2205819d8d6f10d'
EXPECTED_PART = 'xczu15eg-ffvb1156-2-i'

def need(condition, message):
    if not condition:
        raise RuntimeError(message)

def sha(path):
    need(path.is_file(), f'Missing file: {path}')
    return hashlib.sha256(path.read_bytes()).hexdigest()

def load(path):
    return json.loads(path.read_text(encoding='utf-8-sig'))

def text(path):
    return path.read_text(encoding='utf-8-sig', errors='replace')

def under(path, root):
    return path.resolve().is_relative_to(root.resolve())

def fresh(path, start, end):
    need(path.is_file(), f'Missing run output: {path}')
    timestamp = path.stat().st_mtime
    need(start <= timestamp <= end + 5, f'Stale or out-of-run output: {path}')

p = argparse.ArgumentParser()
p.add_argument('receipt', type=Path, help='specific finished retry process receipt')
a = p.parse_args()
receipt_path = a.receipt.resolve()
need(under(receipt_path, REPORTS), 'Receipt must be in candidate reports')
receipt = load(receipt_path)
need(receipt_path.name.startswith('synth_reuse_ip_') and receipt_path.name.endswith('_process.json'), 'Wrong receipt type')
need(receipt.get('stage') == 'synth' and receipt.get('status') == 'PROCESS_EXITED' and receipt.get('exit_code') == 0, 'Retry process did not exit successfully')
start = dt.datetime.fromisoformat(receipt['started']).timestamp()
end = dt.datetime.fromisoformat(receipt['finished']).timestamp()
need(start < end, 'Invalid receipt timestamps')

manifest_path = REPORTS / 'SOURCE_MANIFEST.json'
manifest = load(manifest_path)
manifest_sha = sha(manifest_path)
gate = load(REPORTS / 'ROOT_FUNCTIONAL_ACCEPTANCE.json')
need(gate.get('status') == 'PASS' and gate.get('source_manifest_sha256') == manifest_sha, 'Functional acceptance does not bind this manifest')
need(sha(REPORTS / 'SHARED16_RESULTS.json') == gate.get('acceptance_sha256'), 'Functional results changed')
need(receipt.get('source_manifest_sha256') == manifest_sha, 'Run receipt references a different manifest')
need(len(manifest.get('entries', [])) == 50 and len(manifest.get('frozen_files', {})) > 50, 'Incomplete source manifest')
for relative, digest in manifest['frozen_files'].items():
    item = OUT / relative
    need(under(item, OUT) and sha(item) == digest, f'Frozen input differs: {relative}')

retry = load(REPORTS / 'SYNTH_RETRY2_PLAN.json')
script = OUT / 'synth_reuse_ip.tcl'
need(sha(script) == retry['script_sha256'] == receipt.get('script_sha256'), 'Retry script differs from plan/receipt')
for relative, digest in retry['verified_ip_inputs'].items():
    item = OUT / relative
    need(under(item, OUT) and sha(item) == digest, f'IP input changed: {relative}')
ip_dcp = (OUT / 'ip/asr_fma_ip/generated/asr_fma_ip.dcp').resolve()
need(sha(ip_dcp) == EXPECTED_IP_DCP, 'FMA DCP hash mismatch')

log_path = Path(receipt['vivado_log']).resolve()
need(under(log_path, OUT / 'logs'), 'Unexpected log path')
fresh(log_path, start, end)
log = text(log_path)
need('CANDIDATE_SYNTH_PASS' in log and 'synth_design completed successfully' in log, 'Synthesis completion marker absent')
need(not re.search(r'^ERROR:', log, re.M), 'Vivado log contains ERROR')
imports = re.findall(r"\[Project 1-454\] Reading design checkpoint ['\"]([^'\"]+)['\"] for cell ['\"]([^'\"]+)['\"]", log)
need(any(Path(path).resolve() == ip_dcp and cell == 'graph/vec/arithmetic/fused' for path, cell in imports), 'Expected FMA checkpoint import missing')
need('Using original IP XDC constraints' in log, 'IP XDC selection missing from log')

required = [OUT / 'build/candidate_synth.dcp', REPORTS / 'synth_pass.txt',
            REPORTS / 'synthesized_array_shape.txt', REPORTS / 'utilization.rpt',
            REPORTS / 'timing.rpt', REPORTS / 'retry2_ip_status.rpt']
for item in required:
    fresh(item, start, end)
need(required[0].stat().st_size > 0, 'Empty core checkpoint')
need(re.search(r'^SYNTH_PASS BLACKBOX=0 MAX_NODES=128 FMA_LATENCY=12\s*$', text(required[1]), re.M), 'Synthesis gate marker invalid')
shape = text(required[2])
need(re.search(r'^ARRAY_COUNT=1 PE_COUNT=256\s*$', shape, re.M), 'Array/PE shape mismatch')
need(len(re.findall(r'^ARRAY=', shape, re.M)) == 1, 'Array shape evidence incomplete')

timing = text(required[4])
need(re.search(r'^core_clk\s+\{[^}]+\}\s+20\.0+\s+50\.0+\s*$', timing, re.M), '20 ns clock absent from timing report')
ipstatus = text(required[5])
need(re.search(r'^\|\s*asr_fma_ip\s*\|\s*Up-to-date\s*\|\s*No changes required\s*\|', ipstatus, re.M | re.I), 'FMA IP status is not explicitly up-to-date')
util = text(required[3])
need(re.search(r'Design\s*:\s*v024_unified_top\b', util) and EXPECTED_PART in util.lower() and re.search(r'Design State\s*:\s*Synthesized', util), 'Utilization report design/part/state mismatch')
resources = {}
for label in ['CLB LUTs*', 'LUT as Memory', 'CLB Registers', 'CARRY8', 'F7 Muxes', 'F8 Muxes', 'F9 Muxes', 'Block RAM Tile', 'DSPs']:
    pattern = r'^\|\s*' + re.escape(label) + r'\s*\|\s*([\d,.]+)\s*\|\s*[\d,.]+\s*\|\s*[\d,.]+\s*\|\s*([\d,.]+)\s*\|\s*([\d,.]+)\s*\|'
    match = re.search(pattern, util, re.M)
    need(match, f'Cannot parse resource row: {label}')
    used, available, reported = (float(v.replace(',', '')) for v in match.groups())
    need(available > 0 and 0 <= used <= available and 0 <= reported <= 100, f'Resource exceeds device or invalid: {label}')
    need(abs(100 * used / available - reported) <= 0.06, f'Resource ratio inconsistent: {label}')
    resources[label] = {'used': used, 'available': available, 'percent': reported}
section = re.search(r'\n9\. Black Boxes\s*\n-+\s*(.*?)\n10\. Instantiated Netlists', util, re.S)
need(section is not None and not re.search(r'^\|\s*(?!Ref Name\b)[\w$./-]+\s*\|\s*\d+\s*\|', section[1], re.M), 'Black-box section missing or nonempty')
netlists = re.search(r'\n10\. Instantiated Netlists\s*\n-+\s*(.*?)(?:\n\d+\. |\Z)', util, re.S)
need(netlists and re.search(r'^\|\s*asr_fma_ip\s*\|\s*1\s*\|', netlists[1], re.M), 'FMA instantiated-netlist evidence missing')

plan = load(REPORTS / 'IMPLEMENTATION_PLAN.json')
need(plan.get('part') == EXPECTED_PART and plan.get('clock_period_ns') == 20 and plan.get('required_array_instances') == 1 and plan.get('required_pe_instances') == 256, 'Implementation plan constraints differ')
platform = OUT / 'build/platform_synth_copy.dcp'
implementation_script = OUT / 'implement.tcl'
need(sha(platform) == plan['platform_sha256'], 'Platform checkpoint differs from implementation plan')
need(sha(implementation_script) == plan['script_sha256'], 'Implementation script differs from plan')
result = {'status': 'PASS', 'source_manifest_sha256': manifest_sha,
          'core_checkpoint_sha256': sha(required[0]), 'platform_checkpoint_sha256': sha(platform),
          'implementation_script_sha256': sha(implementation_script), 'functional_acceptance_sha256': sha(REPORTS / 'ROOT_FUNCTIONAL_ACCEPTANCE.json'),
          'synthesis_receipt_sha256': sha(receipt_path), 'synthesis_log_sha256': sha(log_path),
          'fma_checkpoint_sha256': sha(ip_dcp), 'part': EXPECTED_PART, 'clock_period_ns': 20,
          'array_count': 1, 'pe_count': 256, 'blackboxes': 0, 'resources': resources,
          'scope': 'Out-of-context synthesis review only; no route, timing closure, or hardware claim'}
target = REPORTS / 'READY_FOR_IMPLEMENTATION.json'
need(not target.exists(), f'Existing gate must be reviewed separately: {target}')
target.write_text(json.dumps(result, indent=2) + '\n', encoding='utf-8')
print('READY_FOR_IMPLEMENTATION: PASS')

