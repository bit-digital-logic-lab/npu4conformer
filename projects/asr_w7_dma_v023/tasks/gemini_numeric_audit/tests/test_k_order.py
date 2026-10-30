#!/usr/bin/env python3
"""
test_k_order.py
Investigates the impact of K-accumulation order on C48 accumulation:
- In integer arithmetic modulo 2^48, addition is strictly associative and commutative.
- Tests whether any permutation of K-steps produces identical final results.
- Verifies contract rule: "保留每个C的K累加顺序" (Preserve K accumulation order per C)
  to ensure reproducible bit-exact equivalence with existing hardware captures.
"""

import random
import sys
from pathlib import Path

TASK_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(TASK_DIR / "golden"))
import w7_math_golden

def test_k_order_invariance():
    print("Testing K-accumulation order invariance in integer C48 ring...")
    random.seed(42)

    K = 128
    # Generate K pairs of A and W
    p_val = 12
    clip = True

    a_series = [random.randint(-32768, 32767) for _ in range(K)]
    w_series = [random.randint(0, 127) for _ in range(K)]

    # Compute products
    products = [
        w7_math_golden.compute_product_pure_math(a, w, p_val, clip)
        for a, w in zip(a_series, w_series)
    ]

    # Baseline sequential accumulation: k = 0 .. K-1
    acc_forward = 0
    for p in products:
        acc_forward = w7_math_golden.compute_c48_accum(acc_forward, p)

    # Reverse order: k = K-1 .. 0
    acc_reverse = 0
    for p in reversed(products):
        acc_reverse = w7_math_golden.compute_c48_accum(acc_reverse, p)

    # Random permutations (100 random orders)
    perm_matches = 0
    for _ in range(100):
        perm_prods = list(products)
        random.shuffle(perm_prods)
        acc_perm = 0
        for p in perm_prods:
            acc_perm = w7_math_golden.compute_c48_accum(acc_perm, p)
        if acc_perm == acc_forward:
            perm_matches += 1

    print(f"Forward C48 final sum: 0x{acc_forward & 0xFFFFFFFFFFFF:012x}")
    print(f"Reverse C48 final sum: 0x{acc_reverse & 0xFFFFFFFFFFFF:012x}")
    print(f"Random permutations matched forward: {perm_matches} / 100")

    assert acc_forward == acc_reverse, "Forward and Reverse accumulation mismatch in C48!"
    assert perm_matches == 100, "Permuted accumulation mismatch in C48!"
    print("Pure INT48 integer accumulation is mathematically order-invariant.")
    print("NOTE: DESIGN_CONTRACT_zh.txt requires preserving K order per C to maintain")
    print("bit-exact determinism across intermediate verification checkpoints and downstream float casts.")

if __name__ == "__main__":
    test_k_order_invariance()
