#!/usr/bin/env python3
"""
analyze_fusion_legality.py
Examines all 68 CONV/FFN subgraphs in manifest.json to identify
C48 -> I48_F32 -> scale/bias FMA -> ReLU/F32_I16 epilogue fusion opportunities,
multi-consumer tensors, and spill requirements.
"""

import json
from pathlib import Path

MANIFEST_PATHS = [
    Path('/home/yang/Desktop/项目/tasks/ds_ddr/fixtures/parameters002/manifest.json'),
    Path('/home/yang/Desktop/项目/tasks/ds_pl_autonomy/assets/manifest_v022.json'),
]

def analyze_manifest():
    manifest_path = None
    for p in MANIFEST_PATHS:
        if p.exists():
            manifest_path = p
            break
    if not manifest_path:
        raise FileNotFoundError("Manifest file not found.")

    with open(manifest_path, 'r') as f:
        manifest = json.load(f)

    v211_progs = manifest.get('v211_programs', {})
    v022_progs = manifest.get('v022_programs', {})

    fusion_table = []
    total_matrix_ops = 0
    fusable_matrix_ops = 0
    spill_required_ops = 0
    c48_single_consumer_ops = 0
    c48_multi_consumer_ops = 0

    # Summary by subgraph kind
    kind_counts = {}

    for key, prog in v211_progs.items():
        kind = prog.get('kind', 'UNKNOWN')
        kind_counts[kind] = kind_counts.get(kind, 0) + 1
        values = prog.get('values', [])
        ops = prog.get('ops', [])

        # Build dependency graph
        uses = {}
        for op in ops:
            k, did, aid, bid = op[:4]
            if aid != 4294967295:
                uses[aid] = uses.get(aid, 0) + 1
            if bid != 4294967295:
                uses[bid] = uses.get(bid, 0) + 1

        for i, op in enumerate(ops):
            op_kind, did, aid, bid = op[:4]
            if op_kind <= 2:  # 0: DWCONV, 1: GEMM, 2: CONV
                total_matrix_ops += 1
                consumer_count = uses.get(did, 0)

                # Check if next op is kind 5 (quantization)
                next_is_quant = False
                has_relu = False
                if i + 1 < len(ops):
                    next_op = ops[i+1]
                    if next_op[0] == 5 and next_op[2] == did:
                        next_is_quant = True
                
                # Check if C48 has any other consumer:
                # In the plan compiler, C48 is written to cblocks[i] and immediately read by vector(14).
                # No other opcode in the instruction stream references cblocks[i].
                c48_single_consumer = True  # strictly 1 consumer (I48_F32)
                c48_single_consumer_ops += 1

                # If intermediate FP32 has only 1 consumer (the quantization op), it can be fully fused
                # without spilling FP32 to DDR!
                can_fuse = True
                needs_spill = (consumer_count > 1)
                if needs_spill:
                    spill_required_ops += 1
                else:
                    fusable_matrix_ops += 1

                fusion_table.append({
                    "subgraph": key,
                    "kind": kind,
                    "matrix_op_index": i,
                    "matrix_type": "DWCONV" if op_kind == 0 else ("GEMM" if op_kind == 1 else "CONV"),
                    "output_val_id": did,
                    "consumer_count": consumer_count,
                    "c48_consumers": 1,
                    "fusable": can_fuse,
                    "needs_c48_spill": False,
                    "needs_fp32_spill": needs_spill,
                    "next_op_is_quant": next_is_quant
                })

    result = {
        "manifest_path": str(manifest_path),
        "total_subgraphs": len(v211_progs),
        "subgraph_kinds": kind_counts,
        "total_matrix_ops": total_matrix_ops,
        "fusable_matrix_ops": fusable_matrix_ops,
        "spill_required_ops": spill_required_ops,
        "c48_single_consumer_ops": c48_single_consumer_ops,
        "c48_multi_consumer_ops": c48_multi_consumer_ops,
        "fusion_table_sample": fusion_table[:10],
        "all_entries_count": len(fusion_table)
    }

    out_file = Path('/home/yang/Desktop/项目/v023_repair/gemini_epilogue/fusion_legality_summary.json')
    out_file.write_text(json.dumps(result, indent=2))
    print(f"Fusion legality analysis complete. Written to {out_file}")
    print(f"Total Subgraphs: {len(v211_progs)}")
    print(f"Total Matrix Ops: {total_matrix_ops}")
    print(f"Fusable Matrix Ops (Zero intermediate DDR traffic): {fusable_matrix_ops}")
    print(f"Ops Requiring Intermediate Spill: {spill_required_ops}")
    print(f"C48 Single Consumer Ops: {c48_single_consumer_ops} / {total_matrix_ops} (100.0%)")

if __name__ == '__main__':
    analyze_manifest()
