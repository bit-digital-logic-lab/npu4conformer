#!/usr/bin/env python3
"""Record read-only source and candidate artifact hashes."""
import hashlib
import json
from pathlib import Path

TASK = Path(__file__).resolve().parents[1]
PROJ = TASK.parents[1]
WORK = PROJ / 'work'


def h(p):
    return hashlib.sha256(Path(p).read_bytes()).hexdigest()


files = [
    str(PROJ / 'model_a_v0_22(1).zip'),
    str(PROJ / 'tasks/ds_pl_autonomy/assets/manifest_v022.json'),
    str(PROJ / 'tasks/ds_pl_autonomy/rtl/wc_superplan_ctrl.sv'),
    str(WORK / 'assets/parameters002/parameters.bin'),
    str(WORK / 'rtl/axi_dma_v019.sv'),
    str(WORK / 'rtl/ddr_vector_axi.sv'),
    str(WORK / 'rtl/ddr_vector_engine.sv'),
    str(WORK / 'rtl/ddr_layout_axi.sv'),
    str(WORK / 'rtl/ddr_layout_engine.sv'),
    str(WORK / 'rtl/asr_fp32_alu.sv'),
    str(WORK / 'rtl/u16_divmod.sv'),
    str(WORK / 'tests/fma_forbidden_stub.sv'),
]
local = [
    'rtl/wc_graph_ctrl.sv', 'rtl/wc_graph_top.sv',
    'tb/wc_graph_bfm.sv', 'tb/tb_wc_graph_ctrl.sv', 'tb/tb_wc_graph_real.sv',
    'scripts/explore_sources.py', 'scripts/allocator.py',
    'scripts/compile_graph.py', 'scripts/verify_graph.py',
    'scripts/check_alloc.py', 'scripts/make_fixtures.py', 'scripts/run_all.py',
    'scripts/graph_common.py',
    'analysis/whole68_global.bin', 'analysis/ledger591.bin',
    'analysis/small_real.bin', 'analysis/global_alloc.json',
    'analysis/tensor_map.json', 'analysis/descriptor_map.json',
    'tests/fixtures/mem_graph.hex', 'tests/fixtures/gold_small.hex',
    'reports/run_all/run_all.json',
]
out = dict(
    read_only={p: h(p) for p in files},
    candidate={p: h(TASK / p) for p in local},
    note='Hashes are SHA-256.  Read-only sources were not modified.  The 68 '
         'manifest is the ds_pl_autonomy extracted copy; its sealed ZIP member '
         'identity is recorded in analysis/source_ledger.json.',
)
(TASK / 'SOURCE_SHA.json').write_text(json.dumps(out, indent=2) + '\n')
print(json.dumps({k: len(v) for k, v in out.items() if isinstance(v, dict)}, indent=2))
