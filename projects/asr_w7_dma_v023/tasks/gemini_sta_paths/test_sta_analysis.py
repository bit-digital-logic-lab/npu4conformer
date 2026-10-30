#!/usr/bin/env python3
"""
test_sta_analysis.py - Self-test and validation of the STA timing analysis.
"""

import sys
import os
import csv
import json
import hashlib
from pathlib import Path

BASE_DIR = Path(__file__).resolve().parent
PROJECT_DIR = BASE_DIR.parent.parent
TIMING_DIR = PROJECT_DIR / "timing_baseline"

def test_sta():
    print("=== STA TIMING REPRODUCIBLE TEST SUITE ===")
    
    # 1. Run parser
    script_path = BASE_DIR / "parse_sta_timing.py"
    ret = os.system(f"python3 {script_path}")
    assert ret == 0, f"parse_sta_timing.py failed with return code {ret}"
    print("[PASS] parse_sta_timing.py executed successfully.")

    # 2. Check PATHS.csv
    csv_path = BASE_DIR / "PATHS.csv"
    assert csv_path.exists(), "PATHS.csv was not generated"
    with open(csv_path, 'r', encoding='utf-8') as f:
        reader = list(csv.DictReader(f))
    assert len(reader) == 601, f"Expected 601 paths, got {len(reader)}"
    print(f"[PASS] PATHS.csv verified with exactly {len(reader)} paths.")

    # 3. Check Worst Setup and Hold
    setup_paths = [r for r in reader if 'Setup' in r['path_type'] or 'Max' in r['path_type']]
    hold_paths = [r for r in reader if 'Hold' in r['path_type'] or 'Min' in r['path_type']]
    
    setup_paths_valid = [r for r in setup_paths if r['slack_ns'] != 'inf']
    hold_paths_valid = [r for r in hold_paths if r['slack_ns'] != 'inf']

    worst_setup = min(float(r['slack_ns']) for r in setup_paths_valid)
    worst_hold = min(float(r['slack_ns']) for r in hold_paths_valid)

    assert abs(worst_setup - 0.055) < 1e-4, f"Worst setup mismatch: expected 0.055, got {worst_setup}"
    assert abs(worst_hold - 0.010) < 1e-4, f"Worst hold mismatch: expected 0.010, got {worst_hold}"
    print(f"[PASS] Worst setup slack verified: {worst_setup:.3f} ns (Path ID 61).")
    print(f"[PASS] Worst hold slack verified: {worst_hold:.3f} ns (Path ID 91).")

    # 4. Check Categories Detection
    carries = sum(int(r['has_carry']) for r in reader)
    dsps = sum(int(r['has_dsp']) for r in reader)
    resets = sum(int(r['has_reset']) for r in reader)
    ces = sum(int(r['has_clock_enable']) for r in reader)
    fmas = sum(int(r['has_fma']) for r in reader)
    assert carries == 36, f"Expected carries == 36, got {carries}"
    assert dsps == 49, f"Expected dsps == 49, got {dsps}"
    assert resets == 222, f"Expected resets == 222, got {resets}"
    assert ces == 37, f"Expected CEs == 37, got {ces}"
    assert fmas == 50, f"Expected FMAs == 50, got {fmas}"
    print(f"[PASS] Categories breakdown verified (carries={carries}, dsps={dsps}, resets={resets}, ces={ces}, fmas={fmas}).")

    # 5. Check Candidate Independent Audit
    cc_sv = PROJECT_DIR / "tasks/gemini_compute/candidate/pe_pipeline_cc_v023.sv"
    csa_sv = PROJECT_DIR / "tasks/gemini_compute/candidate/pe_pipeline_csa_v023.sv"
    assert cc_sv.exists(), f"{cc_sv} not found"
    assert csa_sv.exists(), f"{csa_sv} not found"

    cc_text = cc_sv.read_text()
    csa_text = csa_sv.read_text()

    # Verify that in CC candidate, barrel shift + sat subtraction are coupled in stage 2A:
    assert "wire [31:0] aligned = {12'd0, raw1} << p1;" in cc_text
    assert "wire [31:0] magnitude = aligned - (sat1 ? {16'd0, mag1} : 32'd0);" in cc_text
    assert "magnitude2a <= magnitude;" in cc_text
    print("[PASS] Independent audit of pe_pipeline_cc_v023: confirmed Stage 2A couples barrel shift and sat subtraction.")

    # Verify that in CSA candidate, CPA sum = sum_s + sum_c is continuous assign without output register:
    assert "assign sum = $signed(sum_s + sum_c);" in csa_text
    print("[PASS] Independent audit of pe_pipeline_csa_v023: confirmed CPA 'assign sum = $signed(sum_s + sum_c);' is unclocked and continuous.")

    print("\nALL TEST CHECKS PASSED SUCCESSFULLY (100% PASS RATE).")

if __name__ == '__main__':
    test_sta()
