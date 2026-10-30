#!/usr/bin/env python3
"""Verify that the frozen numeric/matrix sources were copied unchanged from
v023_repair/ds_closeout_numeric.  Only ddr_vector_engine_pipe.sv is expected to
differ; vector_fma_lane.sv is new.  Read-only source tree."""
import hashlib, json
from pathlib import Path

HERE = Path(__file__).resolve().parents[1]
SRC = Path('/home/yang/Desktop/项目/v023_repair/ds_closeout_numeric/rtl')
frozen = [
    'fp32_fma_pipe.sv', 'asr_fma_ip.sv', 'approx_div_sqrt.sv',
    'approx_recip_lut.sv', 'approx_rsqrt_lut.sv',
    'pe_w7_c48_cfg.sv', 'array16_w7_c48_cfg.sv',
    'c_cache_banked4.sv', 'c_cache_banked4_pipe.sv',
    'operand_banks_dual_v2.sv', 'block_storage_stream_v2.sv',
    'block_engine_prefetch_v2.sv', 'matrix_p2_cluster_v2.sv',
    'ddr_layout_engine_v023_burst.sv',
]
out = {'frozen': {}, 'changed': [], 'missing': []}
for f in frozen:
    a = HERE / 'rtl' / f
    b = SRC / f
    if not a.exists() or not b.exists():
        out['missing'].append(f)
        continue
    ha = hashlib.sha256(a.read_bytes()).hexdigest()
    hb = hashlib.sha256(b.read_bytes()).hexdigest()
    out['frozen'][f] = {'sha256': ha, 'matches_v023': ha == hb}
    if ha != hb:
        out['changed'].append(f)
out['pass'] = not out['changed'] and not out['missing']
out['note'] = ('ddr_vector_engine_pipe.sv is the intended edit; vector_fma_lane.sv is '
               'new. W7A16C48 matrix sources are byte-identical to v023.')
(HERE / 'reports' / 'frozen.json').write_text(json.dumps(out, indent=2) + '\n')
print(json.dumps({'pass': out['pass'], 'changed': out['changed'],
                  'missing': out['missing']}, indent=2))
raise SystemExit(0 if out['pass'] else 1)
