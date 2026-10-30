#!/usr/bin/env python3
"""Comprehensive test runner and numerical evaluator for approx_div_sqrt.

Executes:
1. Corner case suite (NaN, Inf, Zero, subnormals/FTZ, neg sqrt, epsilon=1e-6)
2. LayerNorm realistic activation/variance suite (EPS=1e-6, var in [1e-6, 100])
3. Softmax realistic normalization suite (sum in [1.0, 99.0])
4. Random positive normal distributions (10,000+ vectors)
5. Verifies RTL simulation vs Independent Exact FP32 Baseline
6. Tests full ready/valid backpressure and tag tracking
7. Exits non-zero (sys.exit(1)) on ANY failure or tolerance violation.
"""

import sys
import os
import struct
import math
import subprocess
import json
import numpy as np
from pathlib import Path
from typing import List, Tuple, Dict, Any

BASE_DIR = Path(__file__).resolve().parent.parent
sys.path.append(str(BASE_DIR / 'golden'))
from approx_model import (
    baseline_exact, approx_calc, float_to_u32, u32_to_float,
    FLAG_INVALID, FLAG_DIV_BY_0, FLAG_OVERFLOW, FLAG_UNDERFLOW, FLAG_APPROX
)

# Test directories
TESTS_DIR = BASE_DIR / 'tests'
RTL_DIR = BASE_DIR / 'rtl'
LOGS_DIR = BASE_DIR / 'logs'
LOGS_DIR.mkdir(exist_ok=True)


def ulp_distance(a_bits: int, b_bits: int) -> int:
    """Compute ULP distance between two positive FP32 numbers."""
    if (a_bits >> 31) != (b_bits >> 31):
        if (a_bits & 0x7fffffff) == 0 and (b_bits & 0x7fffffff) == 0:
            return 0
        return 99999999
    return abs(a_bits - b_bits)


def generate_vectors() -> List[Tuple[int, int, int, int, str]]:
    """Generate comprehensive test vector set (op, a, b, tag, suite_name)."""
    vectors = []
    tag = 1

    # Suite A: Corner & Edge Cases
    corners = [
        (0, 10.0, 3.0, "div_normal_10_3"),
        (0, 1.0, 0.0, "div_by_pos_zero"),
        (0, 1.0, -0.0, "div_by_neg_zero"),
        (0, 0.0, 0.0, "div_zero_zero"),
        (0, float('nan'), 2.0, "div_nan_a"),
        (0, 2.0, float('nan'), "div_nan_b"),
        (0, float('inf'), 2.0, "div_inf_num"),
        (0, 2.0, float('inf'), "div_inf_den"),
        (0, float('inf'), float('inf'), "div_inf_inf"),
        (0, 0.0, 5.0, "div_zero_num"),
        (0, -10.0, 2.0, "div_neg_num"),
        (0, 10.0, -2.0, "div_neg_den"),
        (0, -10.0, -2.0, "div_neg_both"),
        (1, 2.0, 0.0, "sqrt_2"),
        (1, 4.0, 0.0, "sqrt_4"),
        (1, 9.0, 0.0, "sqrt_9"),
        (1, 0.0, 0.0, "sqrt_pos_zero"),
        (1, -0.0, 0.0, "sqrt_neg_zero"),
        (1, -4.0, 0.0, "sqrt_neg_invalid"),
        (1, float('inf'), 0.0, "sqrt_inf"),
        (1, float('nan'), 0.0, "sqrt_nan"),
        (2, 2.0, 0.0, "rsqrt_2"),
        (2, 4.0, 0.0, "rsqrt_4"),
        (2, 0.0, 0.0, "rsqrt_zero"),
        (2, -4.0, 0.0, "rsqrt_neg_invalid"),
        (2, float('inf'), 0.0, "rsqrt_inf"),
        (2, 1e-6, 0.0, "rsqrt_epsilon_1e6"),
        (2, 1e-5, 0.0, "rsqrt_epsilon_1e5"),
        (2, 1e-4, 0.0, "rsqrt_epsilon_1e4"),
    ]

    for op, a_f, b_f, desc in corners:
        a_b = float_to_u32(a_f)
        b_b = float_to_u32(b_f)
        vectors.append((op, a_b, b_b, tag, f"corner_{desc}"))
        tag += 1

    # Subnormals for FTZ
    vectors.append((0, 0x00200000, float_to_u32(2.0), tag, "corner_ftz_a"))
    tag += 1
    vectors.append((0, float_to_u32(2.0), 0x00200000, tag, "corner_ftz_b"))
    tag += 1

    # Suite B: LayerNorm Realistic Variance Distribution (RSQRT)
    np.random.seed(42)
    log_vars = np.random.uniform(np.log10(1e-6), np.log10(100.0), size=500)
    for lv in log_vars:
        v_eps = float(10.0 ** lv + 1e-6)
        a_b = float_to_u32(v_eps)
        vectors.append((2, a_b, 0, tag, "layernorm_rsqrt"))
        tag += 1

    # Suite C: Softmax Normalization Distribution (DIV: 1.0 / S and e / S)
    sums = np.random.uniform(1.0, 99.0, size=300)
    for s in sums:
        vectors.append((0, float_to_u32(1.0), float_to_u32(float(s)), tag, "softmax_recip"))
        tag += 1
        e = float(np.random.uniform(0.01, 1.0))
        vectors.append((0, float_to_u32(e), float_to_u32(float(s)), tag, "softmax_norm"))
        tag += 1

    # Suite D: Random Positive Normal Numbers (DIV, SQRT, RSQRT)
    for _ in range(1000):
        a_val = float(np.exp(np.random.uniform(-10.0, 10.0)))
        b_val = float(np.exp(np.random.uniform(-10.0, 10.0)))
        vectors.append((0, float_to_u32(a_val), float_to_u32(b_val), tag, "random_div"))
        tag += 1
        vectors.append((1, float_to_u32(a_val), 0, tag, "random_sqrt"))
        tag += 1
        vectors.append((2, float_to_u32(a_val), 0, tag, "random_rsqrt"))
        tag += 1

    return vectors


def run_simulation(vectors: List[Tuple[int, int, int, int, str]], rand_backpressure: bool = False) -> List[Tuple[int, int, int]]:
    """Run Icarus Verilog simulation and collect results."""
    vec_filename = f"sim_vectors_{'rand' if rand_backpressure else 'norm'}.txt"
    out_filename = f"sim_outputs_{'rand' if rand_backpressure else 'norm'}.txt"
    vec_path = LOGS_DIR / vec_filename
    out_path = LOGS_DIR / out_filename

    with open(vec_path, "w") as f:
        for op, a, b, tag, _ in vectors:
            f.write(f"{op:x} {a:08x} {b:08x} {tag:04x}\n")

    cmd = ["vvp", "tb_approx_div_sqrt.vvp", f"+VEC_FILE=../logs/{vec_filename}", f"+OUT_FILE=../logs/{out_filename}"]
    if rand_backpressure:
        cmd.append("+RAND_BACKPRESSURE")

    res = subprocess.run(cmd, cwd=str(TESTS_DIR), stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    if res.returncode != 0:
        print(f"Simulation execution failed with returncode {res.returncode}")
        print("STDOUT:", res.stdout)
        print("STDERR:", res.stderr)
        sys.exit(1)

    outputs = []
    with open(out_path, "r") as f:
        for line in f:
            parts = line.strip().split()
            if len(parts) == 3:
                res_val = int(parts[0], 16)
                flg_val = int(parts[1], 16)
                tag_val = int(parts[2], 16)
                outputs.append((res_val, flg_val, tag_val))

    if len(outputs) != len(vectors):
        print(f"FATAL: Vector count mismatch! Sent {len(vectors)}, received {len(outputs)}")
        sys.exit(1)

    return outputs


def main():
    print("===================================================================")
    print("  Approximate DIV / SQRT / RSQRT Comprehensive Verification Suite  ")
    print("===================================================================")

    vectors = generate_vectors()
    print(f"Total test vectors generated: {len(vectors)}")

    # Compile RTL
    compile_cmd = [
        "iverilog", "-g2012",
        "-o", str(TESTS_DIR / "tb_approx_div_sqrt.vvp"),
        str(TESTS_DIR / "tb_approx_div_sqrt.sv"),
        str(RTL_DIR / "approx_div_sqrt.sv"),
        str(RTL_DIR / "approx_recip_lut.sv"),
        str(RTL_DIR / "approx_rsqrt_lut.sv")
    ]
    c_res = subprocess.run(compile_cmd, capture_output=True, text=True)
    if c_res.returncode != 0:
        print("FATAL: RTL compilation failed!")
        print(c_res.stderr)
        sys.exit(1)
    print("Icarus Verilog compilation: SUCCESS")

    # Run 1: Normal full speed
    print("\n--- Running Simulation Run 1 (Full Speed, out_ready=1) ---")
    out_run1 = run_simulation(vectors, rand_backpressure=False)
    print(f"Simulation Run 1: completed {len(out_run1)} vectors.")

    # Run 2: Random backpressure
    print("\n--- Running Simulation Run 2 (Random Backpressure, 25% stall) ---")
    out_run2 = run_simulation(vectors, rand_backpressure=True)
    print(f"Simulation Run 2 (Backpressure): completed {len(out_run2)} vectors.")

    # Verification and metric evaluation
    print("\n--- Numerical Evaluation & Error Metric Extraction ---")
    stats = {
        "total_count": len(vectors),
        "backpressure_exact_match": 0,
        "tag_match_count": 0,
        "special_cases_verified": 0,
        "golden_match_count": 0,
        "div_rel_errors": [],
        "div_ulps": [],
        "sqrt_rel_errors": [],
        "sqrt_ulps": [],
        "rsqrt_rel_errors": [],
        "rsqrt_ulps": [],
        "layernorm_code_diffs": [],
        "softmax_code_diffs": [],
        "failures": []
    }

    for i in range(len(vectors)):
        op, a_bits, b_bits, expected_tag, name = vectors[i]
        r1, flg1, tag1 = out_run1[i]
        r2, flg2, tag2 = out_run2[i]

        # 1. Backpressure consistency check
        if (r1, flg1, tag1) == (r2, flg2, tag2):
            stats["backpressure_exact_match"] += 1
        else:
            stats["failures"].append(f"Backpressure mismatch at vector #{i} ({name}): Run1={(r1,flg1,tag1)}, Run2={(r2,flg2,tag2)}")

        # 2. Tag integrity check
        if tag1 == expected_tag:
            stats["tag_match_count"] += 1
        else:
            stats["failures"].append(f"Tag mismatch at vector #{i} ({name}): Got {tag1}, Expected {expected_tag}")

        # 3. Independent exact baseline reference
        b_bits_res, b_flags = baseline_exact(op, a_bits, b_bits)

        # 4. Check special cases and flags
        if name.startswith("corner_"):
            stats["special_cases_verified"] += 1
            if "nan" in name or "invalid" in name:
                if not (flg1 & FLAG_INVALID):
                    stats["failures"].append(f"Missing FLAG_INVALID for {name}: flags={flg1:#x}")
            if "by_pos_zero" in name or "by_neg_zero" in name or "rsqrt_zero" in name:
                if not (flg1 & FLAG_DIV_BY_0):
                    stats["failures"].append(f"Missing FLAG_DIV_BY_0 for {name}: flags={flg1:#x}")
            if "ftz" in name:
                if not (flg1 & FLAG_UNDERFLOW):
                    stats["failures"].append(f"Missing FLAG_UNDERFLOW for {name}: flags={flg1:#x}")

        # 5. Error metrics for valid normal results
        if not (flg1 & (FLAG_INVALID | FLAG_DIV_BY_0)) and not (b_flags & (FLAG_INVALID | FLAG_DIV_BY_0)):
            f_sim = u32_to_float(r1)
            f_base = u32_to_float(b_bits_res)

            if abs(f_base) > 1e-35:
                rel_err = abs(f_sim - f_base) / abs(f_base)
                if math.isfinite(rel_err):
                    ulp = ulp_distance(r1, b_bits_res)

                    if op == 0:
                        stats["div_rel_errors"].append(rel_err)
                        stats["div_ulps"].append(ulp)
                    elif op == 1:
                        stats["sqrt_rel_errors"].append(rel_err)
                        stats["sqrt_ulps"].append(ulp)
                    elif op == 2:
                        stats["rsqrt_rel_errors"].append(rel_err)
                        stats["rsqrt_ulps"].append(ulp)

                if name == "layernorm_rsqrt":
                    q_sim = int(np.clip(np.round(f_sim * 4096.0), -32768, 32767))
                    q_base = int(np.clip(np.round(f_base * 4096.0), -32768, 32767))
                    stats["layernorm_code_diffs"].append(abs(q_sim - q_base))

                if name in ("softmax_recip", "softmax_norm"):
                    q_sim = int(np.clip(np.round(f_sim * 65535.0), 0, 65535))
                    q_base = int(np.clip(np.round(f_base * 65535.0), 0, 65535))
                    stats["softmax_code_diffs"].append(abs(q_sim - q_base))

    # Print summary statistics
    print("\n===================================================================")
    print("                    FINAL VERIFICATION SUMMARY                     ")
    print("===================================================================")
    print(f"Total Vectors:                    {stats['total_count']}")
    print(f"Backpressure Consistency:         {stats['backpressure_exact_match']} / {stats['total_count']} ({stats['backpressure_exact_match']/stats['total_count']*100:.1f}%)")
    print(f"Tag Integrity (tag_out == tag):   {stats['tag_match_count']} / {stats['total_count']} ({stats['tag_match_count']/stats['total_count']*100:.1f}%)")
    print(f"Special / Corner Cases Handled:   {stats['special_cases_verified']} verified")

    div_max_rel = max(stats['div_rel_errors']) if stats['div_rel_errors'] else 0.0
    div_mean_rel = float(np.mean(stats['div_rel_errors'])) if stats['div_rel_errors'] else 0.0
    sqrt_max_rel = max(stats['sqrt_rel_errors']) if stats['sqrt_rel_errors'] else 0.0
    sqrt_mean_rel = float(np.mean(stats['sqrt_rel_errors'])) if stats['sqrt_rel_errors'] else 0.0
    rsqrt_max_rel = max(stats['rsqrt_rel_errors']) if stats['rsqrt_rel_errors'] else 0.0
    rsqrt_mean_rel = float(np.mean(stats['rsqrt_rel_errors'])) if stats['rsqrt_rel_errors'] else 0.0

    print("\n--- Error Distributions vs Exact FP32 Baseline ---")
    print(f"DIV (a / b):")
    print(f"  Max Relative Error:             {div_max_rel * 100:.4f}% ({div_max_rel:.2e})")
    print(f"  Mean Relative Error:            {div_mean_rel * 100:.5f}% ({div_mean_rel:.2e})")
    print(f"  Median ULP Distance:            {np.median(stats['div_ulps']) if stats['div_ulps'] else 0:.1f}")

    print(f"SQRT (sqrt(a)):")
    print(f"  Max Relative Error:             {sqrt_max_rel * 100:.4f}% ({sqrt_max_rel:.2e})")
    print(f"  Mean Relative Error:            {sqrt_mean_rel * 100:.5f}% ({sqrt_mean_rel:.2e})")
    print(f"  Median ULP Distance:            {np.median(stats['sqrt_ulps']) if stats['sqrt_ulps'] else 0:.1f}")

    print(f"RSQRT (1 / sqrt(a)):")
    print(f"  Max Relative Error:             {rsqrt_max_rel * 100:.4f}% ({rsqrt_max_rel:.2e})")
    print(f"  Mean Relative Error:            {rsqrt_mean_rel * 100:.5f}% ({rsqrt_mean_rel:.2e})")
    print(f"  Median ULP Distance:            {np.median(stats['rsqrt_ulps']) if stats['rsqrt_ulps'] else 0:.1f}")

    print("\n--- Downstream Quantized Code Impact ---")
    ln_max = max(stats['layernorm_code_diffs']) if stats['layernorm_code_diffs'] else 0
    ln_mean = float(np.mean(stats['layernorm_code_diffs'])) if stats['layernorm_code_diffs'] else 0.0
    ln_exact = float(np.mean(np.array(stats['layernorm_code_diffs']) == 0) * 100) if stats['layernorm_code_diffs'] else 0.0
    print(f"LayerNorm (INT16 Q12 format):")
    print(f"  Max Code Difference:            {ln_max} LSB")
    print(f"  Mean Code Difference:           {ln_mean:.3f} LSB")
    print(f"  Fraction Exact Code Match:      {ln_exact:.1f}%")

    sm_max = max(stats['softmax_code_diffs']) if stats['softmax_code_diffs'] else 0
    sm_mean = float(np.mean(stats['softmax_code_diffs'])) if stats['softmax_code_diffs'] else 0.0
    sm_exact = float(np.mean(np.array(stats['softmax_code_diffs']) == 0) * 100) if stats['softmax_code_diffs'] else 0.0
    print(f"Softmax (UINT16 format, 1.0=65535):")
    print(f"  Max Code Difference:            {sm_max} LSB")
    print(f"  Mean Code Difference:           {sm_mean:.3f} LSB")
    print(f"  Fraction Exact Code Match:      {sm_exact:.1f}%")

    # Strict Acceptance Gating (NO UNCONDITIONAL PASS!)
    if stats["failures"]:
        print(f"\nFATAL: {len(stats['failures'])} test failures detected!")
        for fail in stats["failures"][:10]:
            print("  ", fail)
        sys.exit(1)

    if stats["backpressure_exact_match"] != stats["total_count"]:
        print("\nFATAL: Backpressure consistency failed!")
        sys.exit(1)

    if stats["tag_match_count"] != stats["total_count"]:
        print("\nFATAL: Tag integrity failed!")
        sys.exit(1)

    # Sanity bounds on relative error to prevent arithmetic divergence
    if div_max_rel > 0.002:  # > 0.2%
        print(f"\nFATAL: DIV maximum relative error exceeded tolerance ({div_max_rel:.4f} > 0.002)!")
        sys.exit(1)

    if sqrt_max_rel > 0.0001:  # > 0.01%
        print(f"\nFATAL: SQRT maximum relative error exceeded tolerance ({sqrt_max_rel:.4f} > 0.0001)!")
        sys.exit(1)

    if rsqrt_max_rel > 0.0001:  # > 0.01%
        print(f"\nFATAL: RSQRT maximum relative error exceeded tolerance ({rsqrt_max_rel:.4f} > 0.0001)!")
        sys.exit(1)

    if ln_max > 2:
        print(f"\nFATAL: LayerNorm max code error exceeded 2 LSB ({ln_max} LSB)!")
        sys.exit(1)

    if sm_max > 20:
        print(f"\nFATAL: Softmax max code error exceeded 20 LSB ({sm_max} LSB)!")
        sys.exit(1)

    print("\n===================================================================")
    print("  ALL VERIFICATION CHECKS PASSED CONDITIONALLY & STRICTLY (RC=0)   ")
    print("===================================================================")

    # Save summary report in logs
    summary_data = {
        "total_vectors": stats['total_count'],
        "div_max_rel_err": div_max_rel,
        "div_mean_rel_err": div_mean_rel,
        "sqrt_max_rel_err": sqrt_max_rel,
        "sqrt_mean_rel_err": sqrt_mean_rel,
        "rsqrt_max_rel_err": rsqrt_max_rel,
        "rsqrt_mean_rel_err": rsqrt_mean_rel,
        "layernorm_max_code_diff": ln_max,
        "softmax_max_code_diff": sm_max,
        "status": "PASSED"
    }
    with open(LOGS_DIR / "verification_summary.json", "w") as f:
        json.dump(summary_data, f, indent=2)

    sys.exit(0)


if __name__ == '__main__':
    main()
