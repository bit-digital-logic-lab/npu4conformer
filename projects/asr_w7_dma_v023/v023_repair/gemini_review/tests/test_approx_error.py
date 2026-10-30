#!/usr/bin/env python3
"""
test_approx_error.py - Independent evaluation of approximate Div and Sqrt/Rsqrt
error distribution and its impact on quantized A16 activations.
"""

import numpy as np
import math

def simulate_reciprocal(b, tier=1):
    """
    Simulate LUT + Newton-Raphson reciprocal 1/b.
    b is positive float32 array.
    """
    m, e = np.frexp(b)  # m in [0.5, 1.0)
    m = m * 2.0
    e = e - 1

    # Tier 0: 7-bit LUT (128 entries)
    lut_idx = np.clip(np.floor((m - 1.0) * 128).astype(int), 0, 127)
    seed = 1.0 / (1.0 + (lut_idx + 0.5) / 128.0)

    if tier == 0:
        inv_m = seed
    elif tier == 1:
        # 1-step Newton-Raphson: x1 = x0 * (2 - m * x0)
        inv_m = seed * (2.0 - m * seed)
    elif tier == 2:
        # 2-step Newton-Raphson
        x1 = seed * (2.0 - m * seed)
        inv_m = x1 * (2.0 - m * x1)
    else:
        inv_m = 1.0 / m

    return np.ldexp(inv_m, -e)

def simulate_div(a, b, tier=1):
    return a * simulate_reciprocal(b, tier)

def simulate_rsqrt(a, tier=1):
    """
    Simulate LUT + Newton-Raphson rsqrt: 1 / sqrt(a).
    """
    m, e = np.frexp(a)  # m in [0.5, 1.0)
    odd_exp = (e % 2 != 0)
    m = np.where(odd_exp, m * 2.0, m)
    e = np.where(odd_exp, e - 1, e)

    # m is now in [0.5, 2.0)
    lut_idx = np.clip(np.floor((m - 0.5) / 1.5 * 128).astype(int), 0, 127)
    seed = 1.0 / np.sqrt(0.5 + (lut_idx + 0.5) / 128.0 * 1.5)

    if tier == 0:
        inv_sqrt_m = seed
    elif tier == 1:
        # 1-step Newton-Raphson: x1 = x0 * (1.5 - 0.5 * m * x0^2)
        inv_sqrt_m = seed * (1.5 - 0.5 * m * (seed ** 2))
    elif tier == 2:
        x1 = seed * (1.5 - 0.5 * m * (seed ** 2))
        inv_sqrt_m = x1 * (1.5 - 0.5 * m * (x1 ** 2))
    else:
        inv_sqrt_m = 1.0 / np.sqrt(m)

    return np.ldexp(inv_sqrt_m, -(e // 2))

def simulate_sqrt(a, tier=1):
    return a * simulate_rsqrt(a, tier)

def quantize_to_a16(val_fp32, scale=100.0):
    """
    Quantize FP32 to INT16 (A16) with scale and clip [-32768, 32767].
    Uses round-to-nearest-even.
    """
    scaled = val_fp32 * scale
    rounded = np.round(scaled)
    clipped = np.clip(rounded, -32768, 32767).astype(np.int16)
    return clipped

def run_tests():
    np.random.seed(42)
    print("=== APPROXIMATE DIV / SQRT / RSQRT ACCURACY AUDIT ===")

    # 1. Division test over wide positive range
    N = 100000
    a = np.random.uniform(0.01, 1000.0, N).astype(np.float32)
    b = np.random.uniform(0.01, 1000.0, N).astype(np.float32)
    golden_div = a / b

    print("\n[1] FP32 Division (A / B) Relative Error Analysis (N=100,000):")
    for tier in [0, 1, 2]:
        approx_div = simulate_div(a, b, tier=tier)
        rel_err = np.abs(approx_div - golden_div) / golden_div
        max_rel_err = np.max(rel_err)
        mean_rel_err = np.mean(rel_err)
        print(f"  Tier {tier}: Max Rel Err = {max_rel_err*100:.4f}%, Mean Rel Err = {mean_rel_err*100:.6f}%")

        # Now test impact on quantized A16 under various scales
        for scale in [1.0, 10.0, 100.0, 1000.0]:
            q_golden = quantize_to_a16(golden_div, scale=scale)
            q_approx = quantize_to_a16(approx_div, scale=scale)
            diff = np.abs(q_approx.astype(int) - q_golden.astype(int))
            diff_count = np.count_nonzero(diff)
            max_diff = np.max(diff) if diff_count > 0 else 0
            print(f"    Scale {scale:6.1f} -> Mismatches: {diff_count:6d} / {N} ({diff_count/N*100:5.2f}%), Max LSB Diff: {max_diff}")

    # 2. RSQRT test (used in LayerNorm: 1 / sqrt(var + eps))
    print("\n[2] FP32 RSQRT 1 / sqrt(A) Relative Error Analysis (N=100,000):")
    var_eps = np.random.uniform(1e-4, 100.0, N).astype(np.float32)
    golden_rsqrt = 1.0 / np.sqrt(var_eps)

    for tier in [0, 1, 2]:
        approx_rsqrt = simulate_rsqrt(var_eps, tier=tier)
        rel_err = np.abs(approx_rsqrt - golden_rsqrt) / golden_rsqrt
        max_rel_err = np.max(rel_err)
        mean_rel_err = np.mean(rel_err)
        print(f"  Tier {tier}: Max Rel Err = {max_rel_err*100:.4f}%, Mean Rel Err = {mean_rel_err*100:.6f}%")

    # 3. Softmax Simulation
    print("\n[3] Softmax Normalization Simulation (Rows of 64 tokens, N=1,000 rows):")
    logits = np.random.uniform(-10.0, 10.0, (1000, 64)).astype(np.float32)
    max_logit = np.max(logits, axis=1, keepdims=True)
    exp_logits = np.exp(logits - max_logit)
    sum_exp = np.sum(exp_logits, axis=1, keepdims=True)
    golden_probs = exp_logits / sum_exp

    for tier in [0, 1, 2]:
        approx_probs = simulate_div(exp_logits, sum_exp, tier=tier)
        rel_err = np.abs(approx_probs - golden_probs) / (golden_probs + 1e-12)
        max_abs = np.max(np.abs(approx_probs - golden_probs))
        
        # Quantize to INT16 (scale = 32767 for probabilities [0, 1])
        q_golden = quantize_to_a16(golden_probs, scale=32767.0)
        q_approx = quantize_to_a16(approx_probs, scale=32767.0)
        diff = np.abs(q_approx.astype(int) - q_golden.astype(int))
        mismatches = np.count_nonzero(diff)
        max_lsb = np.max(diff) if mismatches > 0 else 0
        print(f"  Tier {tier}: Max Abs Err = {max_abs:.2e}, Quantized (A16) Mismatches = {mismatches:6d} / {1000*64} ({mismatches/(1000*64)*100:5.2f}%), Max LSB Diff = {max_lsb}")

if __name__ == "__main__":
    run_tests()
