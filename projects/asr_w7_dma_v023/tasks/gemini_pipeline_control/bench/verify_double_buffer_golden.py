#!/usr/bin/env python3
"""
verify_double_buffer_golden.py
Verifies sim_double_buffer_output.hex (2 output blocks, 2048 words) against Python golden model.
"""

import sys
from golden_block_engine import compute_block_quadrants, to_s48, MASK48

def main():
    M, N, K = 32, 64, 32
    a_mat = [[0 for _ in range(K)] for _ in range(M)]
    w_mat = [[0 for _ in range(N)] for _ in range(K)]

    for r in range(M):
        for k in range(K):
            val = ((r * 17 + k * 31) & 0x7FFF) - 0x3FFF
            a_mat[r][k] = val & 0xFFFF

    for k in range(K):
        for c in range(N):
            val = (k * 7 + c * 13) & 0x7F
            w_mat[k][c] = val

    positions = 0x3210
    clip = 1

    # Block (0,0): columns 0..31
    w_blk0 = [[w_mat[k][c] for c in range(32)] for k in range(K)]
    gold_b0 = compute_block_quadrants(a_mat, w_blk0, 32, 32, 32, positions, clip)

    # Block (0,1): columns 32..63
    w_blk1 = [[w_mat[k][c+32] for c in range(32)] for k in range(K)]
    gold_b1 = compute_block_quadrants(a_mat, w_blk1, 32, 32, 32, positions, clip)

    gold_words = []
    for r in range(32):
        for c in range(32):
            gold_words.append(gold_b0[r][c] & MASK48)
    for r in range(32):
        for c in range(32):
            gold_words.append(gold_b1[r][c] & MASK48)

    sim_words = []
    with open("bench/sim_double_buffer_output.hex", "r") as f:
        for line in f:
            line = line.strip()
            if line:
                sim_words.append(int(line, 16))

    assert len(sim_words) == 2048, f"Expected 2048 words, got {len(sim_words)}"

    mismatches = 0
    for i in range(2048):
        blk = i // 1024
        word_in_blk = i % 1024
        r = word_in_blk // 32
        c = word_in_blk % 32
        sim_val = sim_words[i]
        gold_val = gold_words[i]
        if sim_val != gold_val:
            print(f"Mismatch at Block {blk} (r={r}, c={c}, idx={i}): SIM=0x{sim_val:012x} GOLD=0x{gold_val:012x}")
            mismatches += 1

    if mismatches == 0:
        print(f"[SUCCESS] All 2048 elements (2 double-buffered 32x32 blocks) MATCH GOLDEN MODEL BIT-FOR-BIT!")
        print(f"[SUCCESS] Multi-block continuous execution, ping-pong slot switching, and dirty flush verified!")
        sys.exit(0)
    else:
        print(f"[FAILURE] {mismatches} mismatches detected between SIM and GOLDEN!")
        sys.exit(1)

if __name__ == "__main__":
    main()
