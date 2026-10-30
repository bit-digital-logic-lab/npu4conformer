#!/usr/bin/env python3
"""
audit_projections.py - Independent mathematical audit of performance projections
and theoretical lower bounds for CASE0000.
"""

import json
import math
from pathlib import Path

def audit():
    board_result_path = Path("/home/yang/Desktop/项目/work/BOARD_RESULT.json")
    with open(board_result_path, "r") as f:
        board_data = json.load(f)

    run = board_data["runs"][0]
    closed = run["closed_plan"]
    unfused = run["unfused"]
    ethernet = run["ethernet"]

    print("=== 1. BOARD MEASUREMENT RECONCILIATION ===")
    total_elapsed = run["elapsed_seconds"]
    closed_seconds = closed["whole_plan_seconds"]
    residual_seconds = total_elapsed - closed_seconds
    residual_ratio = residual_seconds / total_elapsed

    print(f"Total Measured Time: {total_elapsed:.3f} s")
    print(f"Closed 68 Plan Time: {closed_seconds:.3f} s ({closed_seconds/total_elapsed*100:.2f}%)")
    print(f"Outside Host DAG / UDP Residual: {residual_seconds:.3f} s ({residual_ratio*100:.2f}%)")
    print(f"Ethernet Batches: {ethernet['batches']}, Exchange Wall Time: {ethernet['exchange_wall_seconds']:.3f} s")

    # Detailed Closed Plan Breakdown
    pe_seconds = closed["matrix_pe_seconds"]
    queue_seconds = closed["matrix_queue_seconds"]
    vector_seconds = closed["vector_seconds"]
    layout_seconds = closed["layout_seconds"]
    fetch_seconds = closed["plan_fetch_seconds"]
    sum_components = queue_seconds + vector_seconds + layout_seconds + fetch_seconds
    print(f"\nClosed 68 Plan Components:")
    print(f"  Matrix PE pure compute: {pe_seconds:.3f} s ({pe_seconds/closed_seconds*100:.2f}%)")
    print(f"  Matrix Queue total:     {queue_seconds:.3f} s ({queue_seconds/closed_seconds*100:.2f}%)")
    print(f"  Vector total:           {vector_seconds:.3f} s ({vector_seconds/closed_seconds*100:.2f}%)")
    print(f"  Layout total:           {layout_seconds:.3f} s ({layout_seconds/closed_seconds*100:.2f}%)")
    print(f"  Plan fetch:             {fetch_seconds:.3f} s ({fetch_seconds/closed_seconds*100:.2f}%)")
    print(f"  Sum of components:      {sum_components:.3f} s (Matches whole_plan: {abs(sum_components - closed_seconds) < 0.01})")

    print("\n=== 2. COMPUTE LOWER BOUND AUDIT ===")
    # Total MACs across whole model:
    # Closed 68: 3,461,011,968 useful MACs, 3,991,404,544 padded MACs
    # Unfused 591: 1,099,624,448 useful MACs, 1,393,033,216 padded MACs
    # Total padded MACs = 5,384,437,760
    # In systolic array 16x16 = 256 PEs, each PE does 1 MAC/cycle (or 2 MACs if double pump).
    # Baseline pe_direct does 1 MAC/cycle = 256 MACs/cycle.
    total_padded_macs = 5384437760
    closed_padded_macs = 3991404544
    unfused_padded_macs = 1393033216

    freqs = [125e6, 250e6, 300e6, 600e6]
    print(f"Systolic Array: 16x16 = 256 PEs (1 MAC/cycle/PE = 256 MACs/cycle)")
    print(f"Total Model Padded MACs: {total_padded_macs:,}")
    print(f"Closed 68 Subgraph Padded MACs: {closed_padded_macs:,}")
    print(f"Unfused 591 Queues Padded MACs: {unfused_padded_macs:,}")

    print("\nPure Compute Lower Bound (100% array utilization, 0 stalls, 0 bubbles):")
    for f in freqs:
        f_mhz = f / 1e6
        # Whole model
        cycles_whole = total_padded_macs / 256
        t_whole = cycles_whole / f
        # Closed 68
        cycles_68 = closed_padded_macs / 256
        t_68 = cycles_68 / f
        # Unfused 591
        cycles_591 = unfused_padded_macs / 256
        t_591 = cycles_591 / f
        print(f"  @{f_mhz:3.0f} MHz: Whole={t_whole:.4f} s | 68-Subset={t_68:.4f} s | 591-Subset={t_591:.4f} s")

    print("\n=== 3. MEMORY LOWER BOUND AUDIT ===")
    # Closed 68 plan vector + layout bytes: read 452.3MB + write 355.6MB = 807.9 MB
    # Matrix DMA bytes (from BOARD_RESULT and gemini_roofline):
    # Closed 68 matrix: A(2B)+W(1B)+C(6B)
    # Total traffic measured across CASE0000:
    # Closed 68: vector+layout = 807,885,856 bytes
    # Closed 68 matrix DMA: ~202.5 MB
    # Unfused 591 DMA: ~148.6 MB
    # Total DDR traffic in baseline: ~1,010,393,248 bytes (~1.01 GB)
    total_ddr_traffic = 1010393248
    closed_68_vector_layout_traffic = 807885856
    
    # Let's compute memory transfer lower bound under single HP0 (128-bit):
    # At 125 MHz: 128 bit * 125 MHz = 2.0 GB/s
    # At 250 MHz: 128 bit * 250 MHz = 4.0 GB/s
    # At 300 MHz: 128 bit * 300 MHz = 4.8 GB/s
    # Theoretical physical DDR4-1600 peak = 12.8 GB/s (64-bit @ 800 MHz)
    # Realistic DDR4 efficiency under random/strided banking: ~70% = ~8.96 GB/s
    print(f"Total Measured DDR Traffic: {total_ddr_traffic:,} bytes ({total_ddr_traffic/1e6:.1f} MB)")
    print(f"Closed 68 Vector+Layout Traffic alone: {closed_68_vector_layout_traffic:,} bytes ({closed_68_vector_layout_traffic/1e6:.1f} MB)")
    
    print("\nMemory Transfer Lower Bound (Single HP port, 100% bus efficiency, 0 turnaround bubble):")
    for f, bw in [(125e6, 2.0e9), (250e6, 4.0e9), (300e6, 4.8e9)]:
        f_mhz = f / 1e6
        bw_gb = bw / 1e9
        t_transfer = total_ddr_traffic / bw
        t_transfer_68_vec = closed_68_vector_layout_traffic / bw
        print(f"  HP0 @ {f_mhz:.0f} MHz ({bw_gb:.1f} GB/s): Whole Traffic={t_transfer:.4f} s | 68-Vec/Lay Alone={t_transfer_68_vec:.4f} s")

    print("\nPhysical DDR4 Channel Limits:")
    print(f"  Physical DDR4-1600 64-bit Peak: 12.8 GB/s -> Transfer Lower Bound: {total_ddr_traffic / 12.8e9:.4f} s")
    print(f"  Realistic DDR4 Efficiency (70% = 8.96 GB/s): Transfer Lower Bound: {total_ddr_traffic / 8.96e9:.4f} s")

    print("\n=== 4. FALLACY AUDIT OF USER ATTACHMENT CLAIMS ===")
    print("Claim 1: 'P0 591下沉+PL自主调度: 153.8s -> ~12.5s'")
    print("  Debunk: 12.487s is the time of the 68 CONV/FFN subgraphs alone.")
    print("  If 591 matrix tasks are executed on PL, their computation is NOT zero.")
    print(f"  At 125 MHz, 591 tasks have {unfused_padded_macs:,} padded MACs = {unfused_padded_macs / (256 * 125e6):.4f} s pure PE compute.")
    print("  In V0.22, 591 queues took 0.762s in matrix queue alone + vector ops (Softmax, LayerNorm) + layout DMA.")
    print("  Therefore, total PL execution time cannot simply remain 12.5s; it must include the 591 tasks!")
    print("  Moreover, without an offline tensor arena allocator, the 591 tasks cannot overlap with the 68 tasks.")
    
    print("\nClaim 2: 'P1 Vector/Layout流水化+融合: 10.17s -> <0.8s'")
    print("  Debunk: 10.17s = 6.82s (Vector) + 3.35s (Layout).")
    print("  Epilogue fusion can ONLY fuse linear C48 -> FP32 -> FMA -> ReLU -> A16 chains.")
    print("  Attention Softmax, LayerNorm, multi-head transpose, and multi-consumer tensors CANNOT be completely eliminated.")
    print("  Furthermore, DDR bandwidth of 2.0 GB/s requires at least 0.404s just to read/write 807 MB of vector/layout data.")
    print("  With DRAM row misses and AXI turnaround, achieving <0.8s across all ops is an unverified speculative hope.")

    print("\nClaim 3: 'P3 多HP分流使PL总带宽提升至8~12 GB/s'")
    print("  Debunk: Multi-HP peak CANNOT be simply summed as DDR guarantee!")
    print("  Single DDR4-1600 physical PHY is 64-bit @ 800MHz = 12.8 GB/s maximum physical peak.")
    print("  All HP ports (HP0, HP1, HP2) multiplex through the PS interconnect switch to the single DDRC.")
    print("  Summing HP0 (4 GB/s) + HP1 (4 GB/s) + HP2 (4 GB/s) = 12 GB/s exceeds realistic DDR4 achievable bandwidth.")
    print("  Bank thrashing from concurrent random accesses degrades real throughput to 60-75% (~7.7 - 9.6 GB/s).")

if __name__ == "__main__":
    audit()
