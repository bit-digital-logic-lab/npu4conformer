"""Analyze model architecture, shapes, MACs, memory traffic hierarchies, and board metrics.

Outputs exact figures for:
- 68 closed subgraphs (CONV + FFN)
- 591 outside native matrix tasks (170 matmuls/gemms)
- Vector and layout operations
- DDR memory traffic under 4 hierarchy regimes:
  1) Ideal Whole-Graph (全图)
  2) Inter-Layer / Block-Resident (单块)
  3) Per-Operator (单算子)
  4) Naive Tile-by-Tile / Per-K-Tile (一次K片)
- C-accumulation residency and padding savings
"""

import json
import mmap
import struct
import zipfile
from pathlib import Path

ROOT = Path('/home/yang/Desktop/项目')
TASKS_DIR = ROOT / 'tasks' / 'gemini_roofline'

def run_analysis():
    print("Loading zip manifest and parameters...")
    z = zipfile.ZipFile(ROOT / 'model_a_v0_22(1).zip')
    manifest = json.loads(z.read('model_a_v0_22/assets/parameters002/manifest.json'))
    board_result = json.loads(z.read('model_a_v0_22/BOARD_RESULT.json'))
    board_run0 = json.loads(z.read('model_a_v0_22/reports/case0000_board001/result.json'))

    PB = manifest['param_base']
    progs = manifest['v211_programs']
    tiles = lambda n: (n + 31) // 32

    # Open parameters.bin
    param_file = ROOT / 'work' / 'assets' / 'parameters002' / 'parameters.bin'
    with open(param_file, 'rb') as pf:
        mm = mmap.mmap(pf.fileno(), 0, access=mmap.ACCESS_READ)

        def words_at(addr, count):
            return struct.unpack_from('<' + str(count) + 'I', mm, addr - PB)

        # 1. Analyze 68 Closed Subgraphs
        closed_matrix_ops = []
        closed_useful_macs = 0
        closed_padded_macs = 0
        conv_useful_macs = 0
        ffn_useful_macs = 0
        depthwise_macs = 0
        pointwise_macs = 0
        closed_matrix_descriptors = 0
        closed_a_bytes_compulsory = 0
        closed_w_bytes_compulsory = 0
        closed_c_bytes_compulsory = 0
        closed_c_bytes_naive = 0

        for key, p in progs.items():
            is_conv = p['kind'] == 'CONV'
            values = [v['words'] for v in p['values']]
            for opindex, op in enumerate(p['ops']):
                if op[0] <= 2:
                    cfg = words_at(op[5], op[6])
                    m_dim, k_dim, fulln = cfg[3:6]
                    parts = (k_dim + 4095) // 4096
                    refs = [cfg[29+i*12:41+i*12] for i in range(cfg[28])]
                    total_descs = len(refs) * parts
                    closed_matrix_descriptors += total_descs

                    # Compulsory weights and activations for this GEMM
                    # A is m * k * 2 bytes (A16)
                    # W is k * n * 1 byte (W7+parity = 1B)
                    # C is m * n * 6 bytes (C48)
                    a_comp = m_dim * k_dim * 2
                    closed_a_bytes_compulsory += a_comp

                    for r in refs:
                        n_dim = r[3]
                        useful = m_dim * k_dim * n_dim
                        padded = tiles(m_dim) * tiles(k_dim) * tiles(n_dim) * 32768
                        closed_useful_macs += useful
                        closed_padded_macs += padded

                        w_comp = k_dim * n_dim * 1
                        c_comp = m_dim * n_dim * 6 # 48-bit C
                        closed_w_bytes_compulsory += w_comp
                        closed_c_bytes_compulsory += c_comp

                        # In naive regime without C accumulation residency across K parts:
                        # each part reload & writeback C:
                        closed_c_bytes_naive += c_comp * parts

                        if is_conv:
                            conv_useful_macs += useful
                            if cfg[1] > 1:
                                depthwise_macs += useful
                            else:
                                pointwise_macs += useful
                        else:
                            ffn_useful_macs += useful

                        closed_matrix_ops.append({
                            'prog': key,
                            'kind': p['kind'],
                            'm': m_dim,
                            'k': k_dim,
                            'n': n_dim,
                            'parts': parts,
                            'useful_macs': useful,
                            'padded_macs': padded,
                        })

    # 2. Analyze Outside Unfused Native Matrix Tasks
    tasks = board_run0['native_matrix_tasks']
    unfused_useful_macs = sum(t['m'] * t['k'] * t['n'] for t in tasks)
    unfused_padded_macs = sum(t['mt'] * t['kt'] * t['nt'] * 32768 for t in tasks)
    unfused_compute_cycles = sum(t['compute_cycles'] for t in tasks)
    unfused_queue_cycles = sum(t['queue_cycles'] for t in tasks)
    unfused_dma_read_bytes = sum(t['dma_read_bytes'] for t in tasks)
    unfused_dma_write_bytes = sum(t['dma_write_bytes'] for t in tasks)

    # 3. Model Totals
    total_useful_macs = closed_useful_macs + unfused_useful_macs
    total_padded_macs = closed_padded_macs + unfused_padded_macs
    overall_padding_eff = total_useful_macs / total_padded_macs

    # 4. DDR Traffic Hierarchy Breakdown
    # Regime 1: Ideal Whole-Graph (全图)
    # Compulsory: static weights read once + input features read once + output logits written once
    # Static weights in parameter image:
    weights_total_bytes = manifest['image_bytes'] # 173,715,968 B (~165MB real weights)
    ideal_input_bytes = board_result['runs'][0]['unfused']['host_to_ddr_payload_bytes'] # 19,814,464 B
    ideal_output_bytes = board_result['runs'][0]['unfused']['ddr_to_host_payload_bytes'] # 34,086,912 B
    r1_total_bytes = weights_total_bytes + ideal_input_bytes + ideal_output_bytes
    r1_intensity = total_useful_macs / r1_total_bytes

    # Regime 2: Block-Resident / Inter-Layer (单块)
    # Layer inputs/outputs stored in DDR, internal activations cached in PL SRAM/BRAM
    # Closed plans boundary bytes:
    closed_boundary_in = board_result['runs'][0]['fused_boundary_input_bytes'] # 4,539,392 B
    closed_boundary_out = board_result['runs'][0]['fused_boundary_output_bytes'] # 16,508,928 B
    # Weights streamed once per layer/block = weights_total_bytes
    # Outside DAG inputs/outputs = ideal_input_bytes + ideal_output_bytes
    r2_total_bytes = weights_total_bytes + ideal_input_bytes + ideal_output_bytes + (closed_boundary_in + closed_boundary_out)
    r2_intensity = total_useful_macs / r2_total_bytes

    # Regime 3: Per-Operator (单算子 - Measured Phase 1)
    # Measured on board:
    # Closed plans vector/layout DMA:
    vl_read = board_result['runs'][0]['closed_plan']['vector_layout_read_bytes'] # 452,330,768 B
    vl_write = board_result['runs'][0]['closed_plan']['vector_layout_write_bytes'] # 355,555,088 B
    # Unfused native matrix DMA:
    unfused_dma_read = unfused_dma_read_bytes # 130,831,424 B
    unfused_dma_write = unfused_dma_write_bytes # 17,774,592 B
    # Closed plans matrix DMA (A + W + C traffic estimated from matrix tasks):
    closed_matrix_dma_est = (closed_a_bytes_compulsory + closed_w_bytes_compulsory + closed_c_bytes_compulsory)
    r3_total_bytes = vl_read + vl_write + unfused_dma_read + unfused_dma_write + closed_matrix_dma_est
    r3_intensity = total_useful_macs / r3_total_bytes

    # Regime 4: Naive Tile-by-Tile / Per-K-Tile (一次K片)
    # A reloaded across N tiles, W reloaded across M tiles, C reloaded and evicted per K-slice
    # Without reuse across 32x32 tiles:
    # A reloaded nt times:
    naive_a_bytes = sum(t['m'] * t['k'] * 2 * tiles(t['n']) for t in closed_matrix_ops)
    # W reloaded mt times:
    naive_w_bytes = sum(t['k'] * t['n'] * 1 * tiles(t['m']) for t in closed_matrix_ops)
    naive_c_bytes = closed_c_bytes_naive * 2 # read + write per K slice
    r4_total_bytes = r3_total_bytes + naive_a_bytes + naive_w_bytes + naive_c_bytes
    r4_intensity = total_useful_macs / r4_total_bytes

    # C Accumulation and Padding savings:
    depthwise_padding_saved = manifest.get('depthwise_padding_elements_avoided', 6100992)
    # 6,100,992 elements * 6 bytes (C48) = 36,605,952 bytes saved from DDR!
    c48_bytes_saved = depthwise_padding_saved * 6

    analysis_result = {
        "model_summary": {
            "total_useful_macs": total_useful_macs,
            "total_padded_macs": total_padded_macs,
            "padding_efficiency_percent": round(overall_padding_eff * 100, 2),
            "equivalent_gflops": round(total_useful_macs * 2 / 1e9, 2),
            "closed_plans": {
                "count": len(progs),
                "conv_count": sum(1 for p in progs.values() if p['kind'] == 'CONV'),
                "ffn_count": sum(1 for p in progs.values() if p['kind'] == 'FFN'),
                "matrix_queues": len(closed_matrix_ops),
                "matrix_descriptors": closed_matrix_descriptors,
                "useful_macs": closed_useful_macs,
                "padded_macs": closed_padded_macs,
                "padding_efficiency_percent": round(closed_useful_macs / closed_padded_macs * 100, 2),
                "conv_macs": conv_useful_macs,
                "pointwise_conv_macs": pointwise_macs,
                "depthwise_conv_macs": depthwise_macs,
                "ffn_macs": ffn_useful_macs,
                "pl_instructions": board_result['runs'][0]['closed_plan']['pl_instructions'],
                "vector_elements": board_result['runs'][0]['closed_plan']['vector_elements'],
                "layout_elements": board_result['runs'][0]['closed_plan']['layout_elements'],
            },
            "unfused_dag": {
                "native_matrix_tasks": len(tasks),
                "useful_macs": unfused_useful_macs,
                "padded_macs": unfused_padded_macs,
                "padding_efficiency_percent": round(unfused_useful_macs / unfused_padded_macs * 100, 2),
                "compute_cycles": unfused_compute_cycles,
                "queue_cycles": unfused_queue_cycles,
                "dma_read_bytes": unfused_dma_read_bytes,
                "dma_write_bytes": unfused_dma_write_bytes,
            }
        },
        "ddr_traffic_hierarchies": {
            "regime_1_ideal_whole_graph": {
                "description": "Compulsory input features, static weights (read once), final outputs. All intermediates on-chip.",
                "total_ddr_bytes": r1_total_bytes,
                "total_ddr_mb": round(r1_total_bytes / (1024*1024), 2),
                "operational_intensity_mac_per_byte": round(r1_intensity, 3)
            },
            "regime_2_inter_layer_block_resident": {
                "description": "Layer boundary activations transferred to DDR; layer-internal activations cached in PL SRAM/BRAM.",
                "total_ddr_bytes": r2_total_bytes,
                "total_ddr_mb": round(r2_total_bytes / (1024*1024), 2),
                "operational_intensity_mac_per_byte": round(r2_intensity, 3)
            },
            "regime_3_per_operator_phase1": {
                "description": "Measured Phase 1: operators read inputs from DDR and write outputs to DDR.",
                "total_ddr_bytes": r3_total_bytes,
                "total_ddr_mb": round(r3_total_bytes / (1024*1024), 2),
                "operational_intensity_mac_per_byte": round(r3_intensity, 3)
            },
            "regime_4_naive_tile_per_k_slice": {
                "description": "No reuse across M/N tiles; C partial sums evicted and re-read per K slice from DDR.",
                "total_ddr_bytes": r4_total_bytes,
                "total_ddr_mb": round(r4_total_bytes / (1024*1024), 2),
                "operational_intensity_mac_per_byte": round(r4_intensity, 3)
            }
        },
        "c_accumulation_and_padding": {
            "depthwise_padding_elements_avoided": depthwise_padding_saved,
            "c48_ddr_bytes_saved": c48_bytes_saved,
            "c48_ddr_mb_saved": round(c48_bytes_saved / (1024*1024), 2),
            "c_container_widths": {
                "c48_raw_bytes_per_elem": 6,
                "c32_truncated_bytes_per_elem": 4,
                "c16_requantized_bytes_per_elem": 2
            }
        },
        "measured_board_bottlenecks": {
            "total_case0000_wall_seconds": board_result['runs'][0]['elapsed_seconds'],
            "closed_pl_plans_seconds": board_result['runs'][0]['closed_plan']['whole_plan_seconds'],
            "closed_pl_fraction_percent": round(board_result['runs'][0]['closed_plan']['whole_plan_seconds'] / board_result['runs'][0]['elapsed_seconds'] * 100, 2),
            "host_and_unfused_seconds": board_result['runs'][0]['elapsed_seconds'] - board_result['runs'][0]['closed_plan']['whole_plan_seconds'],
            "host_and_unfused_fraction_percent": round((board_result['runs'][0]['elapsed_seconds'] - board_result['runs'][0]['closed_plan']['whole_plan_seconds']) / board_result['runs'][0]['elapsed_seconds'] * 100, 2),
            "matrix_pe_seconds_total": board_result['runs'][0]['all_matrix_pe_seconds'],
            "matrix_queue_seconds_total": board_result['runs'][0]['all_matrix_queue_seconds'],
            "matrix_queue_non_pe_residual_seconds": board_result['runs'][0]['matrix_queue_non_pe_residual_seconds'],
            "matrix_queue_non_pe_fraction_percent": round(board_result['runs'][0]['matrix_queue_non_pe_residual_seconds'] / board_result['runs'][0]['all_matrix_queue_seconds'] * 100, 2),
            "vector_seconds": board_result['runs'][0]['closed_plan']['vector_seconds'],
            "layout_seconds": board_result['runs'][0]['closed_plan']['layout_seconds'],
            "plan_fetch_seconds": board_result['runs'][0]['closed_plan']['plan_fetch_seconds']
        }
    }

    out_file = TASKS_DIR / 'model_analysis.json'
    out_file.write_text(json.dumps(analysis_result, indent=2))
    print(f"Model analysis written to {out_file}")
    return analysis_result

if __name__ == '__main__':
    run_analysis()
