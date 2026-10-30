#!/usr/bin/env python3
"""
verify_real_array_golden.py
Verifies sim_real_array_output.hex against independent Python golden model for K=64 (cross-K).
"""

import sys
from golden_block_engine import compute_block_quadrants, to_s48, MASK48

def main():
    M, N, K = 32, 32, 64
    a_mat = [[0 for _ in range(K)] for _ in range(M)]
    w_mat = [[0 for _ in range(N)] for _ in range(K)]

    for r in range(M):
        for k in range(K):
            val = ((r * 19 + k * 23 + 11) & 0x7FFF) - 0x2000
            a_mat[r][k] = val & 0xFFFF

    for k in range(K):
        for c in range(N):
            val = (k * 11 + c * 17 + 5) & 0x7F
            w_mat[k][c] = val

    positions = 0x3210
    clip = 1

    gold_c = compute_block_quadrants(a_mat, w_mat, M, N, K, positions, clip)

    sim_words = []
    with open("bench/sim_real_array_output.hex", "r") as f:
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
        print(f"[SUCCESS] All 1024 elements (M=32, N=32, K=64) MATCH GOLDEN MODEL BIT-FOR-BIT!")
        print(f"[SUCCESS] Verified multi-K (cross-K) accumulation and real array saturation clipping!")
        sys.exit(0)
    else:
        print(f"[FAILURE] {mismatches} mismatches detected between SIM and GOLDEN!")
        sys.exit(1)

if __name__ == "__main__":
    main()
