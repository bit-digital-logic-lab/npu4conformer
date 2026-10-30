#!/usr/bin/env python3
"""Extract the runtime host actions that W023 must remove or keep explicit.

This is a source audit, not a dynamic trace: the upstream FusionExecutor and
profiled_backend modules are absent from the supplied read-only tree.  Every
entry records file:line and a classification.  No source is modified.
"""
import json, re
from pathlib import Path

HERE = Path(__file__).resolve().parents[1]
WORK = HERE.parents[1] / 'work'
OUT = HERE / 'analysis'

FILES = [
    'host/base_v021.py', 'host/backend_v021.py', 'host/fusion_backend.py',
    'host/layout.py', 'host/parameters.py', 'host/plan_metrics.py',
    'scripts/run_case0000.py', 'scripts/compile_pl_plans.py',
    'ps/vm_pl.c', 'ps/async_dispatch.inc.c', 'ps/gateway_main_async.c',
    'rtl/pl_execution_plan_v022.sv', 'rtl/plan_submit_csr.sv',
    'rtl/ddr_execution_cluster_v022.sv', 'rtl/plan_board_v022.sv',
    'ps/plan_index.h', 'scripts/run_logged.py', 'scripts/derive_runtime_v022.py',
]

# (symbol, classification, why it matters / W023 disposition)
PATTERNS = [
    ('upload21', 'HOST_RUNTIME_DATA', 'host uploads each fused input to DDR before each START'),
    ('read21', 'HOST_RUNTIME_DATA', 'host reads each fused output from DDR after each START'),
    ('native21', 'HOST_RUNTIME_CONTROL', 'host packs/uploads/submits/reads one matrix queue'),
    ('pack_task', 'HOST_RUNTIME_LAYOUT', 'A/W packing on host for each matrix call'),
    ('matmul_special', 'HOST_NN_DISPATCH', 'host chooses matrix tiling/windows and calls native21'),
    ('write_words', 'HOST_RUNTIME_DATA', 'host writes nonmatrix operands through the link'),
    ('choose_row_step', 'HOST_SHAPE_DECISION', 'host chooses M row window from DDR capacity'),
    ('column_step', 'HOST_SHAPE_DECISION', 'host chooses N column window'),
    ('unpack_c', 'HOST_RUNTIME_LAYOUT', 'host converts C48 tiles to INT64 after board read'),
    ('block_bytes', 'HOST_RUNTIME_LAYOUT', 'A16/W7 tile packing'),
    ('fuse_plan', 'HOST_PER_PROGRAM_START', 'one START/poll/read per fused program'),
    ('matrix_index21', 'HOST_IMPLICIT_STATE', 'round-robin selection of matrix context/views'),
    ('cookie21', 'HOST_IMPLICIT_STATE', 'host increments queue epoch; must become PL generation'),
    ('context21', 'HOST_IMPLICIT_STATE', 'host selects resident B context by Python string'),
    ('param_state21', 'HOST_IMPLICIT_STATE', 'host re-checks parameter generation between calls'),
    ('repeat_lengths', 'HOST_IMPLICIT_STATE', 'host scalar-repeat inference for write_words'),
    ('fp32_refs', 'HOST_IMPLICIT_STATE', 'host dedup table for FP32 parameter copies'),
    ('plan_index', 'PL_PROGRAM_INDEX', 'generated immutable per-program entry table'),
    ('vm211_run', 'PS_PROGRAM_START', 'PS starts one program and waits for completion'),
    ('plan[4]=1', 'PS_START_MMIO', 'single plan doorbell write'),
    ('async_state', 'PS_ONLY_STATE', 'PS async completion state, no arithmetic'),
    ('fusion_calls', 'HOST_RUNTIME_CONTROL', 'per-fused-call timing/identity'),
    ('np.', 'HOST_PYTHON_NUMERIC', 'host-side numpy use; must be absent from runtime path'),
    ('plan_count', 'PL_PLAN_CONTROL', 'linear instruction count'),
    ('dependency', 'PL_DEPENDENCY', 'V022 linear dependency field'),
    ('parameter_ready', 'PL_GUARD', 'parameter generation guard'),
    ('generation', 'PL_GUARD', 'generation latch/compare'),
]

CLASS_NOTES = {
    'HOST_RUNTIME_DATA': 'W023 moves to PL DMA descriptor/addressing; host only preloads once.',
    'HOST_RUNTIME_CONTROL': 'W023 moves to one superplan START; no per-program MMIO.',
    'HOST_RUNTIME_LAYOUT': 'W023 requires offline compile or PL layout engine; no host packing at runtime.',
    'HOST_NN_DISPATCH': 'W023 must bind concrete program/weight/tensor addresses offline.',
    'HOST_SHAPE_DECISION': 'W023 must freeze row/column windows at compile time.',
    'HOST_PER_PROGRAM_START': 'W023 removes; one START covers the whole plan.',
    'HOST_IMPLICIT_STATE': 'W023 must encode as explicit plan generation/tensor ids.',
    'PL_PROGRAM_INDEX': 'Keep as read-only; superplan nodes point at these programs.',
    'PS_PROGRAM_START': 'Replace with one PL superplan; PS only starts/observes.',
    'PS_START_MMIO': 'Keep one START for the whole superplan.',
    'PS_ONLY_STATE': 'Allowed: PS completion/IRQ only, no neural control flow.',
    'HOST_PYTHON_NUMERIC': 'Must be absent from runtime; numeric only in PL.',
    'PL_PLAN_CONTROL': 'Existing linear executor remains a SEQ engine.',
    'PL_DEPENDENCY': 'V022 only supports previous-instruction chain; W023 adds 128-bit masks.',
    'PL_GUARD': 'Keep and extend to whole-plan header.',
}


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    actions = []
    for rel in FILES:
        p = WORK / rel
        if not p.exists():
            actions.append(dict(file=rel, line=0, symbol='<missing>',
                                classification='UNREADABLE',
                                snippet='source not present in supplied tree'))
            continue
        text = p.read_text(errors='replace').splitlines()
        for lineno, line in enumerate(text, 1):
            for sym, cls, why in PATTERNS:
                if sym in line:
                    actions.append(dict(file=rel, line=lineno, symbol=sym,
                                        classification=cls, why=why,
                                        disposition=CLASS_NOTES[cls],
                                        snippet=line.strip()[:240]))
    # De-duplicate repeated identical file/line/symbol.
    seen = set()
    uniq = []
    for a in actions:
        k = (a['file'], a['line'], a['symbol'])
        if k in seen:
            continue
        seen.add(k)
        uniq.append(a)
    counts = {}
    for a in uniq:
        counts[a['classification']] = counts.get(a['classification'], 0) + 1
    (OUT / 'host_actions.json').write_text(json.dumps(dict(
        scope='static source audit; FusionExecutor/profiled_backend absent',
        files=FILES, counts=counts, actions=uniq), indent=1) + '\n')
    print(json.dumps(counts, indent=2))
    print('actions', len(uniq))


if __name__ == '__main__':
    main()
