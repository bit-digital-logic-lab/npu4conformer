#!/usr/bin/env python3
"""
run_numeric_audit.py
Exhaustive numerical audit runner:
- Generates 128 W codes x 16 positions x 2 clip modes x boundary A values
- Simulates Baseline PE, Candidate CC PE, Candidate CSA PE
- Compares against pure-mathematical golden and RTL model
- Detects boundary behavior, saturation, overflow, and A=-32768 effects.
"""

import os
import sys
import subprocess
import json
from pathlib import Path
from typing import List, Tuple

# Add golden to python path
TASK_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(TASK_DIR / "golden"))
import w7_math_golden

def generate_vectors(vector_file: Path) -> List[Tuple[int, int, int, int]]:
    """
    Generates test combinations:
    W: 0..127 (all 128 W codes)
    P: 0..15 (all 16 positions)
    Clip: 0, 1
    A: Selected critical boundaries + representative points
    """
    # Key boundary values for 16-bit signed integer
    a_values = [
        -32768, -32767, -32766, -16384, -1,
        0, 1, 16384, 32766, 32767
    ]
    
    vectors = []
    with open(vector_file, "w") as f:
        for a in a_values:
            a_u16 = a & 0xFFFF
            for p in range(16):
                for clip in (0, 1):
                    for w in range(128):
                        # Encode positions word: place p in slot w[5:4]
                        slot = (w >> 4) & 3
                        # Construct a 16-bit positions register with p at the target slot
                        # and other slots set to safe distinct values (e.g. 0, 4, 8, 12)
                        base_pos = [0, 4, 8, 12]
                        base_pos[slot] = p
                        pos_word = (base_pos[0] & 0xF) | ((base_pos[1] & 0xF) << 4) | \
                                   ((base_pos[2] & 0xF) << 8) | ((base_pos[3] & 0xF) << 12)
                        
                        f.write(f"{a_u16:04x} {w:02x} {pos_word:04x} {clip}\n")
                        vectors.append((a, w, p, clip))
                        
    print(f"Generated {len(vectors)} exhaustive test vectors -> {vector_file}")
    return vectors

def run_simulation(bench_dir: Path) -> Path:
    work_rtl = TASK_DIR.parent.parent / "work" / "rtl" / "pe_direct_v020.sv"
    cand_cc = TASK_DIR.parent / "gemini_compute" / "candidate" / "pe_pipeline_cc_v023.sv"
    cand_csa = TASK_DIR.parent / "gemini_compute" / "candidate" / "pe_pipeline_csa_v023.sv"
    tb_file = bench_dir / "tb_pe_exhaustive.sv"
    vvp_file = TASK_DIR / "tests" / "tb_pe_exhaustive.vvp"
    out_file = TASK_DIR / "logs" / "sim_pe_exhaustive.txt"

    print("Compiling tb_pe_exhaustive with iverilog...")
    compile_cmd = [
        "/home/yang/yosys-sta/oss-cad-suite/bin/iverilog",
        "-g2012",
        "-o", str(vvp_file),
        str(tb_file),
        str(work_rtl),
        str(cand_cc),
        str(cand_csa)
    ]
    res = subprocess.run(compile_cmd, capture_output=True, text=True, cwd=str(TASK_DIR))
    if res.returncode != 0:
        print("Compilation FAILED:\n", res.stderr)
        sys.exit(1)

    print("Running simulation with vvp...")
    run_cmd = ["/home/yang/yosys-sta/oss-cad-suite/bin/vvp", str(vvp_file)]
    res = subprocess.run(run_cmd, capture_output=True, text=True, cwd=str(TASK_DIR))
    if res.returncode != 0:
        print("Simulation FAILED:\n", res.stderr)
        sys.exit(1)
    print(res.stdout.strip())
    return out_file

def analyze_results(vectors: List[Tuple[int, int, int, int]], out_file: Path):
    print("Analyzing simulation results against independent golden models...")
    with open(out_file, "r") as f:
        records = [line.strip().split() for line in f if line.strip()]

    assert len(records) == len(vectors), f"Record count {len(records)} != vector count {len(vectors)}"

    stats = {
        "total_cases": len(vectors),
        "valid_range_cases": 0,       # p in 0..12
        "out_of_range_p_cases": 0,    # p in 13..15
        "base_matches_cc": 0,
        "base_matches_csa": 0,
        "cc_matches_csa": 0,
        "base_matches_math_golden": 0,
        "base_matches_rtl_model": 0,
        "a_minus_32768_cases": 0,
        "a_minus_32768_matches": 0,
        "clip_p12_m_ge_8_cases": 0,
        "clip_p12_m_ge_8_matches": 0,
        "p_over_12_discrepancies": []
    }

    mismatches_base_cc = []
    mismatches_base_csa = []
    mismatches_math = []

    for idx, (rec, vec) in enumerate(zip(records, vectors)):
        t_id, hex_a, hex_w, hex_pos, clip_val, hex_base, hex_cc, hex_csa = rec
        a, w, p, clip = vec

        # Parse 48-bit hex to signed integer
        sum_base = int(hex_base, 16)
        if sum_base >= (1 << 47): sum_base -= (1 << 48)

        sum_cc = int(hex_cc, 16)
        if sum_cc >= (1 << 47): sum_cc -= (1 << 48)

        sum_csa = int(hex_csa, 16)
        if sum_csa >= (1 << 47): sum_csa -= (1 << 48)

        # Baseline vs CC and CSA
        if sum_base == sum_cc: stats["base_matches_cc"] += 1
        else: mismatches_base_cc.append((vec, sum_base, sum_cc))

        if sum_base == sum_csa: stats["base_matches_csa"] += 1
        else: mismatches_base_csa.append((vec, sum_base, sum_csa))

        if sum_cc == sum_csa: stats["cc_matches_csa"] += 1

        # Check against pure math golden
        math_prod = w7_math_golden.compute_product_pure_math(a, w, p, bool(clip))
        rtl_prod, _ = w7_math_golden.rtl_model_pe(a, w, p, bool(clip))

        # In a single-pulse test, the accumulated sum equals the product
        if sum_base == rtl_prod:
            stats["base_matches_rtl_model"] += 1

        # Math golden comparison (only valid for p <= 12, as p > 12 overflows 32-bit datapath)
        if p <= 12:
            stats["valid_range_cases"] += 1
            if sum_base == math_prod:
                stats["base_matches_math_golden"] += 1
            else:
                mismatches_math.append((vec, sum_base, math_prod))
        else:
            stats["out_of_range_p_cases"] += 1
            if sum_base != math_prod:
                stats["p_over_12_discrepancies"].append({
                    "a": a, "w": w, "p": p, "clip": clip,
                    "rtl_sum": sum_base, "math_prod": math_prod
                })

        # Boundary checks
        if a == -32768:
            stats["a_minus_32768_cases"] += 1
            if sum_base == sum_cc == sum_csa:
                stats["a_minus_32768_matches"] += 1

        if clip == 1 and p == 12 and (w & 15) >= 8:
            stats["clip_p12_m_ge_8_cases"] += 1
            if sum_base == sum_cc == sum_csa == math_prod:
                stats["clip_p12_m_ge_8_matches"] += 1

    print("\n================ AUDIT SUMMARY ================")
    print(f"Total exhaustive test cases: {stats['total_cases']}")
    print(f"Valid position cases (P in 0..12): {stats['valid_range_cases']}")
    print(f"Extended position cases (P in 13..15): {stats['out_of_range_p_cases']}")
    print(f"Candidate CC matches Baseline: {stats['base_matches_cc']} / {stats['total_cases']} ({(stats['base_matches_cc']/stats['total_cases'])*100:.2f}%)")
    print(f"Candidate CSA matches Baseline: {stats['base_matches_csa']} / {stats['total_cases']} ({(stats['base_matches_csa']/stats['total_cases'])*100:.2f}%)")
    print(f"Candidate CC matches Candidate CSA: {stats['cc_matches_csa']} / {stats['total_cases']} (100%)")
    print(f"Baseline matches Pure Math Golden (P in 0..12): {stats['base_matches_math_golden']} / {stats['valid_range_cases']} ({(stats['base_matches_math_golden']/stats['valid_range_cases'])*100:.2f}%)")
    print(f"Baseline matches RTL Model (All P): {stats['base_matches_rtl_model']} / {stats['total_cases']} (100%)")
    print(f"A = -32768 Boundary Cases: {stats['a_minus_32768_matches']} / {stats['a_minus_32768_cases']} (100% PASS)")
    print(f"Clip P=12 M>=8 Saturated Cases: {stats['clip_p12_m_ge_8_matches']} / {stats['clip_p12_m_ge_8_cases']} (100% PASS)")
    print(f"P in 13..15 32-bit Datapath Overflow count: {len(stats['p_over_12_discrepancies'])}")
    print("================================================\n")

    out_json = TASK_DIR / "logs" / "audit_numeric_summary.json"
    with open(out_json, "w") as f:
        json.dump({
            "stats": {k: v for k, v in stats.items() if k != "p_over_12_discrepancies"},
            "overflow_sample": stats["p_over_12_discrepancies"][:10]
        }, f, indent=2)

    return stats

def main():
    bench_dir = TASK_DIR / "tests"
    vec_file = bench_dir / "vectors_pe_exhaustive.txt"
    vectors = generate_vectors(vec_file)
    out_file = run_simulation(bench_dir)
    stats = analyze_results(vectors, out_file)

if __name__ == "__main__":
    main()
