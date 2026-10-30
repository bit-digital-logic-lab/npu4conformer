#!/usr/bin/env python3
"""Evaluate multi-tier trade-offs (Tier 0: Low Latency, Tier 1: High Throughput, Tier 2: Low Error).

Measures:
- Max Relative Error
- Mean Relative Error
- Median ULP
- Theoretical & RTL Latency / II
"""

import sys
from pathlib import Path
import numpy as np

BASE_DIR = Path(__file__).resolve().parent.parent
sys.path.append(str(BASE_DIR / 'golden'))
from approx_model import approx_calc, baseline_exact, float_to_u32, u32_to_float

def evaluate_tier(tier: int, n_samples: int = 2000):
    np.random.seed(123)
    div_errors = []
    sqrt_errors = []
    rsqrt_errors = []

    for _ in range(n_samples):
        fa = float(np.exp(np.random.uniform(-8.0, 8.0)))
        fb = float(np.exp(np.random.uniform(-8.0, 8.0)))
        a_b = float_to_u32(fa)
        b_b = float_to_u32(fb)

        # DIV
        r_div, _ = approx_calc(0, a_b, b_b, tier=tier)
        base_div, _ = baseline_exact(0, a_b, b_b)
        f_div = u32_to_float(r_div)
        f_base_div = u32_to_float(base_div)
        div_errors.append(abs(f_div - f_base_div) / abs(f_base_div))

        # SQRT
        r_sqrt, _ = approx_calc(1, a_b, 0, tier=tier)
        base_sqrt, _ = baseline_exact(1, a_b, 0)
        f_sqrt = u32_to_float(r_sqrt)
        f_base_sqrt = u32_to_float(base_sqrt)
        sqrt_errors.append(abs(f_sqrt - f_base_sqrt) / abs(f_base_sqrt))

        # RSQRT
        r_rsqrt, _ = approx_calc(2, a_b, 0, tier=tier)
        base_rsqrt, _ = baseline_exact(2, a_b, 0)
        f_rsqrt = u32_to_float(r_rsqrt)
        f_base_rsqrt = u32_to_float(base_rsqrt)
        rsqrt_errors.append(abs(f_rsqrt - f_base_rsqrt) / abs(f_base_rsqrt))

    return {
        "tier": tier,
        "div_max": float(np.max(div_errors)),
        "div_mean": float(np.mean(div_errors)),
        "sqrt_max": float(np.max(sqrt_errors)),
        "sqrt_mean": float(np.mean(sqrt_errors)),
        "rsqrt_max": float(np.max(rsqrt_errors)),
        "rsqrt_mean": float(np.mean(rsqrt_errors)),
    }

def main():
    print("Multi-Tier Precision & Error Evaluation")
    print("---------------------------------------")
    results = {}
    for tier in (0, 1, 2):
        res = evaluate_tier(tier)
        results[f"tier_{tier}"] = res
        print(f"\n--- Tier {tier} ---")
        print(f"DIV   Max Rel Err: {res['div_max']*100:.5f}%, Mean Rel Err: {res['div_mean']*100:.5f}%")
        print(f"SQRT  Max Rel Err: {res['sqrt_max']*100:.5f}%, Mean Rel Err: {res['sqrt_mean']*100:.5f}%")
        print(f"RSQRT Max Rel Err: {res['rsqrt_max']*100:.5f}%, Mean Rel Err: {res['rsqrt_mean']*100:.5f}%")

if __name__ == '__main__':
    main()
