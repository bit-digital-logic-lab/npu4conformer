#!/usr/bin/env python3
import sys, os, subprocess
from pathlib import Path

sys.path.append(str(Path(__file__).parent.parent / "candidate"))
from golden_pe import compute_pe_single, accumulate_c48

def main():
    bench_dir = Path(__file__).parent
    cand_dir = bench_dir.parent / "candidate"
    work_rtl_dir = bench_dir.parent.parent.parent / "work" / "rtl"
    out_file = bench_dir / "sim_output_array16.txt"

    print("Compiling tb_array16_compare with iverilog...")
    compile_cmd = [
        "/home/yang/yosys-sta/oss-cad-suite/bin/iverilog",
        "-g2012",
        "-o", str(bench_dir / "array16_compare_sim.vvp"),
        str(bench_dir / "tb_array16_compare.sv"),
        str(work_rtl_dir / "pe_direct_v020.sv"),
        str(work_rtl_dir / "array16_direct_v020.sv"),
        str(cand_dir / "pe_pipeline_cc_v023.sv"),
        str(cand_dir / "pe_pipeline_csa_v023.sv"),
        str(cand_dir / "array16_pipeline_v023.sv")
    ]
    res = subprocess.run(compile_cmd, capture_output=True, text=True, cwd=str(bench_dir.parent))
    if res.returncode != 0:
        print("Compilation failed:")
        print(res.stderr)
        sys.exit(1)

    print("Running simulation with vvp...")
    run_cmd = ["/home/yang/yosys-sta/oss-cad-suite/bin/vvp", str(bench_dir / "array16_compare_sim.vvp")]
    res = subprocess.run(run_cmd, capture_output=True, text=True, cwd=str(bench_dir.parent))
    if res.returncode != 0:
        print("Simulation failed:")
        print(res.stderr)
        sys.exit(1)
    print(res.stdout)

    # Compute expected golden 16x16 matrix in Python
    # Matching exactly the testbench initialization
    positions = 0xC840
    clip = 1

    mat_a = [[0]*32 for _ in range(16)]
    mat_w = [[0]*16 for _ in range(32)]
    for r in range(16):
        for ki in range(32):
            val = ((r * 37 + ki * 13 + 5) & 0x7FFF) - 4000
            mat_a[r][ki] = val

    for ki in range(32):
        for c in range(16):
            mat_w[ki][c] = (c * 23 + ki * 7 + 3) & 0x7F

    golden_c = [[0]*16 for _ in range(16)]
    for r in range(16):
        for c in range(16):
            curr_sum = 0
            for ki in range(32):
                p = compute_pe_single(mat_a[r][ki], mat_w[ki][c], positions, clip)
                curr_sum = accumulate_c48(curr_sum, p)
            golden_c[r][c] = curr_sum

    print("Comparing 16x16 array outputs against Golden...")
    with open(out_file, "r") as f:
        records = [line.strip().split() for line in f if line.strip()]

    mismatches = 0
    for r_str, c_str, base_hex, cc_hex, csa_hex in records:
        r = int(r_str)
        c = int(c_str)
        expected_hex = f"{golden_c[r][c] & 0xFFFFFFFFFFFF:012x}"

        if base_hex != expected_hex or cc_hex != expected_hex or csa_hex != expected_hex:
            print(f"Mismatch at cell ({r}, {c}):")
            print(f"  Golden : 0x{expected_hex}")
            print(f"  Base   : 0x{base_hex}")
            print(f"  CC     : 0x{cc_hex}")
            print(f"  CSA    : 0x{csa_hex}")
            mismatches += 1

    if mismatches == 0:
        print("SUCCESS! All 256 outputs (16x16 PEs, 8,192 MAC operations) matched 100% bit-exact across Python Golden, Baseline array, Candidate A (CC) array, and Candidate B (CSA) array!")
    else:
        print(f"FAILED with {mismatches} mismatches.")
        sys.exit(1)

if __name__ == "__main__":
    main()
