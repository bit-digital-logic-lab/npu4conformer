"""Parameterised Roofline & DDR Performance Model.

Separates frequencies: 125 MHz (measured base), 300 MHz, 600 MHz (structural targets).
Models DDR parameters:
- Bus width: 128-bit vs 64-bit
- f_ddr / f_axi
- AXI burst length (16, 64, 256 beats)
- Round-trip latency (cycles)
- Outstanding depth (1, 2, 4, 8, 16)
- Tiling and prefetch double-buffering (serial vs overlapped)

Computes stage-by-stage dependency sums and within-stage overlap max.
Outputs lower bounds, realistic scheduled times, and gap analysis.
"""

import json
from pathlib import Path

TASKS_DIR = Path('/home/yang/Desktop/项目/tasks/gemini_roofline')

def ddr_efficiency(burst_len, latency, outstanding):
    """Calculate effective bus efficiency given burst length, latency, and outstanding depth."""
    if outstanding <= 1:
        # Serial transactions: pays latency on every burst
        return burst_len / (burst_len + latency)
    else:
        # Pipelined transactions: latency is hidden if outstanding * burst_len >= latency
        stall_cycles_per_burst = max(0, latency - (outstanding - 1) * burst_len)
        return burst_len / (burst_len + stall_cycles_per_burst)

def run_roofline_modeling():
    # Load model analysis data
    model_data = json.loads((TASKS_DIR / 'model_analysis.json').read_text())
    summary = model_data['model_summary']
    closed = summary['closed_plans']
    unfused = summary['unfused_dag']

    # Frequencies to evaluate
    frequencies = [125e6, 300e6, 600e6]
    freq_names = ['125MHz_base', '300MHz_target', '600MHz_target']

    # Array configurations: 16x16 (256 PEs), 8x16 (128 PEs), 8x8 (64 PEs)
    arrays = {
        '16x16_256PE': 256,
        '8x16_128PE': 128,
        '8x8_64PE': 64
    }

    # DDR Configurations
    # 1. Measured Baseline (128-bit, 16-beat burst, outstanding=1 or low, latency ~48 cycles @ 125MHz)
    # 2. Optimized 128-bit (128-bit, 64-beat burst, outstanding=8, latency ~48 cycles)
    # 3. Optimized 64-bit (64-bit, 64-beat burst, outstanding=8, latency ~48 cycles)
    ddr_configs = {
        '128bit_serial_bl16_os1': {'bus_width_bits': 128, 'bl': 16, 'os': 1, 'lat_ns': 384},
        '128bit_pipelined_bl16_os4': {'bus_width_bits': 128, 'bl': 16, 'os': 4, 'lat_ns': 384},
        '128bit_pipelined_bl64_os8': {'bus_width_bits': 128, 'bl': 64, 'os': 8, 'lat_ns': 384},
        '64bit_pipelined_bl64_os8': {'bus_width_bits': 64, 'bl': 64, 'os': 8, 'lat_ns': 384},
    }

    results = {}

    for f_idx, f_pl in enumerate(frequencies):
        fname = freq_names[f_idx]
        results[fname] = {}

        for arr_name, num_pes in arrays.items():
            results[fname][arr_name] = {}

            # Pure compute bound (ideal peak):
            # Compute time = Useful MACs / (num_pes * f_pl)
            ideal_compute_seconds = summary['total_useful_macs'] / (num_pes * f_pl)
            # Padded compute time on physical array (considering 32x32 tiles and padding)
            # Accounting for average PE utilization:
            padded_compute_seconds = summary['total_padded_macs'] / (num_pes * f_pl)

            for ddr_name, ddr_cfg in ddr_configs.items():
                w_bytes = ddr_cfg['bus_width_bits'] // 8
                # Latency in PL cycles:
                lat_cycles = max(4, int(ddr_cfg['lat_ns'] * 1e-9 * f_pl))
                eff = ddr_efficiency(ddr_cfg['bl'], lat_cycles, ddr_cfg['os'])
                eff_bw_bytes_sec = w_bytes * f_pl * eff

                # Now calculate execution time under different architectural regimes:

                # -------------------------------------------------------------
                # Regime 1: Ideal Whole-Graph Roofline Lower Bound
                # Compulsory DDR bytes only. Overlap max(Ideal_Compute, Ideal_DMA).
                # -------------------------------------------------------------
                r1_bytes = model_data['ddr_traffic_hierarchies']['regime_1_ideal_whole_graph']['total_ddr_bytes']
                r1_dma_sec = r1_bytes / eff_bw_bytes_sec
                r1_roofline_bound_sec = max(ideal_compute_seconds, r1_dma_sec)

                # -------------------------------------------------------------
                # Regime 2: Block-Resident / Inter-Layer Pipelined
                # Sequential sum over blocks; within each block, compute and DMA overlap.
                # Total = Sum_blocks( max(T_comp_block, T_dma_block) ) + bubble
                # We model 12 encoder blocks + 6 decoder blocks = 18 major blocks + embeddings
                # -------------------------------------------------------------
                r2_bytes = model_data['ddr_traffic_hierarchies']['regime_2_inter_layer_block_resident']['total_ddr_bytes']
                r2_dma_sec = r2_bytes / eff_bw_bytes_sec
                # In block pipelining, 18 blocks share the work:
                # Average block compute = padded_compute_seconds / 18
                # Average block dma = r2_dma_sec / 18
                # Overlapped block time = max(comp, dma) * 18 + pipeline fill/drain bubble (2 blocks)
                block_comp = padded_compute_seconds / 18
                block_dma = r2_dma_sec / 18
                r2_scheduled_sec = max(block_comp, block_dma) * 18 + min(block_comp, block_dma) * 0.15 * 18 + block_dma * 1.0

                # -------------------------------------------------------------
                # Regime 3: Per-Operator Overlapped (PL autonomous, all operators in PL)
                # Operators run sequentially on PL, but within each operator, A/W/C prefetch overlaps compute.
                # -------------------------------------------------------------
                r3_bytes = model_data['ddr_traffic_hierarchies']['regime_3_per_operator_phase1']['total_ddr_bytes']
                r3_dma_sec = r3_bytes / eff_bw_bytes_sec
                # Vector ops time at this clock:
                # Measured 125MHz vector cycles: 851,939,384 cycles
                vec_sec = 851939384 / f_pl
                # Layout cycles: 419,186,668 cycles
                lay_sec = 419186668 / f_pl
                # Matrix compute time:
                mat_comp_sec = padded_compute_seconds
                # Within operators, DMA and compute overlap up to 75% efficiency:
                r3_scheduled_sec = max(mat_comp_sec + vec_sec + lay_sec, r3_dma_sec) * 1.15

                # -------------------------------------------------------------
                # Regime 4: Serial Execution (Current Phase 1 Hardware Model without Host UDP)
                # Serial: T = T_compute + T_dma (no prefetch overlap, like block_engine_banked_v020)
                # -------------------------------------------------------------
                r4_serial_sec = padded_compute_seconds + vec_sec + lay_sec + r3_dma_sec

                results[fname][arr_name][ddr_name] = {
                    "f_pl_mhz": int(f_pl / 1e6),
                    "bus_width_bits": ddr_cfg['bus_width_bits'],
                    "ddr_efficiency_percent": round(eff * 100, 2),
                    "effective_bandwidth_gb_s": round(eff_bw_bytes_sec / 1e9, 3),
                    "ideal_compute_bound_seconds": round(ideal_compute_seconds, 4),
                    "padded_compute_seconds": round(padded_compute_seconds, 4),
                    "regime_1_ideal_whole_graph_bound_seconds": round(r1_roofline_bound_sec, 4),
                    "regime_2_block_resident_scheduled_seconds": round(r2_scheduled_sec, 4),
                    "regime_3_per_operator_overlapped_seconds": round(r3_scheduled_sec, 4),
                    "regime_4_per_operator_serial_seconds": round(r4_serial_sec, 4),
                    "speedup_regime2_vs_regime4": round(r4_serial_sec / r2_scheduled_sec, 2),
                    "is_bandwidth_bound_regime1": r1_dma_sec > ideal_compute_seconds,
                    "is_bandwidth_bound_regime2": block_dma > block_comp
                }

    out_file = TASKS_DIR / 'roofline_results.json'
    out_file.write_text(json.dumps(results, indent=2))
    print(f"Roofline modeling completed and written to {out_file}")
    return results

if __name__ == '__main__':
    run_roofline_modeling()
