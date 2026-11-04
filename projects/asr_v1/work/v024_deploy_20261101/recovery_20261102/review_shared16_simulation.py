from pathlib import Path
import hashlib
import json
import re

root = Path(__file__).resolve().parent
p = root / 'shared16_candidate'
base = root / 'safe16_candidate'
seqbase = root / 'safe16_sequence_reference'
def sha(path): return hashlib.sha256(path.read_bytes()).hexdigest()
def readjson(path): return json.loads(path.read_text(encoding='utf-8-sig'))
m = readjson(p / 'reports/SOURCE_MANIFEST.json')
d = readjson(p / 'reports/SHARED16_RESULTS.json')
assert len(m['entries']) == 50 and d['status'] == 'SIMULATION_PASS'
expected = {'rtl/epilogue/matrix_stream_fusion_top_v024.sv', 'rtl/graph/v024_matrix_queue_engine.sv',
            'rtl/graph/wc_graph_ctrl.sv', 'rtl/matrix/block_engine_prefetch_v2.sv',
            'rtl/matrix/matrix_p2_cluster_v2.sv', 'rtl/matrix/operand_banks_dual_v2.sv'}
changed = {x['entry'] for x in m['entries'] if x['changed']}
assert changed == expected
for name, digest in m['frozen_files'].items(): assert sha(p / name) == digest, name
for line in (base / 'core/filelist.f').read_text().splitlines():
    if line.strip(): assert sha(base / 'core' / line.strip()) == sha(seqbase / 'core' / line.strip()), line
assert sha(base / 'ip/asr_fma_ip/asr_fma_ip.xci') == sha(seqbase / 'ip/asr_fma_ip/asr_fma_ip.xci')
assert sha(p / 'fault_tb/tb_sequence.sv') == sha(seqbase / 'fault_tb/tb_sequence.sv')
for name in ('REGRESSION_COMBINED.json', 'GENERATION_INVALIDATION_CHECKS.json'):
    assert readjson(p / 'reports' / name)['status'] == 'PASS'
for case in ('vec', 'fetch', 'lay'):
    text = (p / 'logs' / f'fault_{case}.log').read_text()
    assert 'V024_RESULT PASS' in text and 'returned_b=65' in text
    assert re.search(r'REAL_ACL_DONE.*active=0 rd=0 wr=0 b=0 quiesced=1', text)
sequence = (p / 'logs/sequence.log').read_text()
reference = (seqbase / 'logs/sequence.log').read_text()
reset = (p / 'logs/reset_sequence.log').read_text()
markers = lambda text: re.findall(r'^SEQUENCE_DONE.*$', text, re.M)
assert 'SEQUENCE_PASS' in sequence and markers(sequence) == markers(reference) and len(markers(sequence)) == 6
assert 'RESET_SEQUENCE_PASS' in reset
assert len(re.findall(r'^RESET_IN_FLIGHT', reset, re.M)) == 2
assert len(re.findall(r'^RESET_SEQUENCE_DONE', reset, re.M)) == 6
for i in range(6):
    assert (p / 'logs' / f'sequence_{i}.hex').read_bytes() == (seqbase / 'logs' / f'sequence_{i}.hex').read_bytes()
    reference_output = base / 'logs' / ('v024_fused_out.hex' if i % 2 else 'v024_fallback_out.hex')
    assert (p / 'logs' / f'reset_sequence_{i}.hex').read_bytes() == reference_output.read_bytes()
for entry in ('rtl/matrix/pe_w7_c48_cfg.sv', 'rtl/matrix/array16_w7_c48_cfg.sv'):
    assert sha(p / 'core' / entry) == sha(base / 'core' / entry)
result = {'status': 'PASS', 'source_manifest_sha256': sha(p / 'reports/SOURCE_MANIFEST.json'),
          'acceptance_sha256': sha(p / 'reports/SHARED16_RESULTS.json'), 'changed_rtl': sorted(changed),
          'source_count': 50, 'regression_cases': 19, 'parallel_fault_cases': 3,
          'continuous_mode_tasks': 6, 'continuation_cycles_equal_safe16': True,
          'active_mode_global_reset_injections': 2, 'post_reset_recovery_tasks': 6,
          'original_pe_array_source_hashes_unchanged': True, 'requires_physical_array_count': 1,
          'requires_physical_pe_count': 256,
          'scope': 'Independent frozen-source simulation review; no synthesis, routing or hardware claim'}
(p / 'reports/ROOT_FUNCTIONAL_ACCEPTANCE.json').write_text(json.dumps(result, indent=2) + '\n', encoding='utf-8')
print(json.dumps(result, indent=2))
