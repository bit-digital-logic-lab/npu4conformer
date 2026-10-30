#!/usr/bin/env python3
"""
verify_golden.py
Verifies simulation hex outputs against independent Python golden model.
"""

import sys
from golden_block_engine import compute_block_quadrants, to_s48, MASK48

def main():
    # Reconstruct the deterministic test matrix from tb_pipeline_latency_sweep.sv
    # test_a = ((r * 17 + k_idx * 31) & 0x7FFF) - 0x3FFF
    # test_w = (k_idx * 7 + c * 13) & 0x7F
    a_mat = [[0 for _ in range(32)] for _ in range(32)]
    w_mat = [[0 for _ in range(32)] for _ in range(32)]

    for r in range(32):
        for k in range(32):
            val = ((r * 17 + k * 31) & 0x7FFF) - 0x3FFF
            a_mat[r][k] = val & 0xFFFF

    for k in range(32):
        for c in range(32):
            val = (k * 7 + c * 13) & 0x7F
            w_mat[k][c] = val

    positions = 0x3210
    clip = 1

    gold_c = compute_block_quadrants(a_mat, w_mat, 32, 32, 32, positions, clip)

    # Read sim_latency_sweep_output.hex
    # Result payload ordering in block_engine:
    # collect_ci = (quadrant[1]*16 + collect[7:4])*32 + quadrant[0]*16 + collect[3:0]
    # words are packed at collect_ci: result_payload[collect_ci*48 +: 192]
    # i.e., word index i = r * 32 + c !
    sim_words = []
    with open("bench/sim_latency_sweep_output.hex", "r") as f:
        for line in f:
            line = line.strip()
            if line:
                val = int(line, 16)
                sim_words.append(val)

    assert len(sim_words) == 1024, f"Expected 1024 words, got {len(sim_words)}"

    mismatches = 0
    for r in range(32):
        for c in range(32):
            idx = r * 32 + c
            sim_val = sim_words[idx]
            gold_val = gold_c[r][c] & MASK48
            if sim_val != gold_val:
                print(f"Mismatch at (r={r}, c={c}, idx={idx}): SIM=0x{sim_val:012x} GOLD=0x{gold_val:012x}")
                mismatches += 1

    if mismatches == 0:
        print(f"[SUCCESS] All 1024 elements (32x32 block) MATCH GOLDEN MODEL BIT-FOR-BIT!")
        print(f"[SUCCESS] Tested positions={hex(positions)}, clip={clip}, all 4 quadrants!")
        sys.exit(0)
    else:
        print(f"[FAILURE] {mismatches} mismatches detected between SIM and GOLDEN!")
        sys.exit(1)

if __name__ == "__main__":
    main()
