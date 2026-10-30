#!/usr/bin/env python3
"""Verify frozen sources and the two intended payload files.

Read-only sources: v023_repair/ds_closeout_numeric and ds_fma_deep.  The only
edited/new files in this tree are ddr_vector_engine_pipe.sv, vector_fma_lane.sv
and the copied 7-stage candidate.  Their SHAs are pinned here so a silent
change cannot be mistaken for a repeat run.
"""
import hashlib, json
from pathlib import Path

HERE = Path(__file__).resolve().parents[1]
SRC = Path('/home/yang/Desktop/项目/v023_repair/ds_closeout_numeric/rtl')
FMA7 = Path('/home/yang/Desktop/项目/v024_opt/ds_fma_deep/candidate/fp32_fma_pipe.sv')


def sha(p):
    return hashlib.sha256(Path(p).read_bytes()).hexdigest()


frozen = [
    'fp32_fma_pipe.sv', 'asr_fma_ip.sv', 'approx_div_sqrt.sv',
    'approx_recip_lut.sv', 'approx_rsqrt_lut.sv',
    'pe_w7_c48_cfg.sv', 'array16_w7_c48_cfg.sv',
    'c_cache_banked4.sv', 'c_cache_banked4_pipe.sv',
    'operand_banks_dual_v2.sv', 'block_storage_stream_v2.sv',
    'block_engine_prefetch_v2.sv', 'matrix_p2_cluster_v2.sv',
    'ddr_layout_engine_v023_burst.sv',
]
out = {'frozen': {}, 'changed': [], 'missing': [], 'payload': {}}
for f in frozen:
    a = HERE / 'rtl' / f
    b = SRC / f
    if not a.exists() or not b.exists():
        out['missing'].append(f)
        continue
    ha = sha(a)
    hb = sha(b)
    out['frozen'][f] = {'sha256': ha, 'matches_v023': ha == hb}
    if ha != hb:
        out['changed'].append(f)

payload_expected = {
    'rtl/ddr_vector_engine_pipe.sv': 'dad7cac00ecbe5a722ed68f64c5650bd7dc77a07356280e9d550acb5a852f84c',
    'rtl/vector_fma_lane.sv': '09175e5963140349ed39f9ff83b5fd3bb35edc07d6e6b4529fe3128a6315584b',
    'fma7/fp32_fma_pipe.sv': 'b062284af692349ac0afe1de14ac0d10f0cbbab97a5b33f849b50a93caccac82',
    'baseline/ddr_vector_engine_pipe_base.sv': '234e9c34b9ca6ad5eae94cead08d3030d7c0e838a6720500f21347b66e9bec2e',
}
for rel, expected in payload_expected.items():
    p = HERE / rel
    actual = sha(p) if p.exists() else None
    out['payload'][rel] = {'sha256': actual, 'expected': expected,
                           'match': actual == expected}
if FMA7.exists():
    out['ds_fma_deep_candidate_sha256'] = sha(FMA7)
else:
    out['ds_fma_deep_candidate_sha256'] = None

out['pass'] = (not out['changed'] and not out['missing'] and
               all(v['match'] for v in out['payload'].values()) and
               out['ds_fma_deep_candidate_sha256'] ==
               'b062284af692349ac0afe1de14ac0d10f0cbbab97a5b33f849b50a93caccac82')
out['note'] = ('ddr_vector_engine_pipe.sv is the intended edit; vector_fma_lane.sv '
               'is new; fma7/fp32_fma_pipe.sv is the frozen ds_fma_deep 7-stage '
               'candidate. W7A16C48/matrix sources are byte-identical to v023.')
(HERE / 'reports' / 'frozen.json').write_text(json.dumps(out, indent=2) + '\n')
print(json.dumps({'pass': out['pass'], 'changed': out['changed'],
                  'missing': out['missing'],
                  'payload': out['payload']}, indent=2))
raise SystemExit(0 if out['pass'] else 1)
