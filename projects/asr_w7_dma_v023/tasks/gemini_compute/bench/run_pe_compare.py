#!/usr/bin/env python3
import sys, os, subprocess
from pathlib import Path

def main():
    bench_dir = Path(__file__).parent
    cand_dir = bench_dir.parent / "candidate"
    work_rtl = bench_dir.parent.parent.parent / "work" / "rtl" / "pe_direct_v020.sv"
    out_file = bench_dir / "sim_output_pe_compare.txt"

    print("Compiling tb_pe_compare with iverilog...")
    compile_cmd = [
        "/home/yang/yosys-sta/oss-cad-suite/bin/iverilog",
        "-g2012",
        "-o", str(bench_dir / "pe_compare_sim.vvp"),
        str(bench_dir / "tb_pe_compare.sv"),
        str(work_rtl),
        str(cand_dir / "pe_pipeline_cc_v023.sv"),
        str(cand_dir / "pe_pipeline_csa_v023.sv")
    ]
    res = subprocess.run(compile_cmd, capture_output=True, text=True, cwd=str(bench_dir.parent))
    if res.returncode != 0:
        print("Compilation failed:")
        print(res.stderr)
        sys.exit(1)

    print("Running simulation with vvp...")
    run_cmd = ["/home/yang/yosys-sta/oss-cad-suite/bin/vvp", str(bench_dir / "pe_compare_sim.vvp")]
    res = subprocess.run(run_cmd, capture_output=True, text=True, cwd=str(bench_dir.parent))
    if res.returncode != 0:
        print("Simulation failed:")
        print(res.stderr)
        sys.exit(1)
    print(res.stdout)

    print("Analyzing outputs from all three PEs...")
    with open(out_file, "r") as f:
        records = [line.strip().split() for line in f if line.strip()]

    total = len(records)
    print(f"Total recorded cycles: {total}")

    # Check 1: CC candidate vs CSA candidate (must match 100% on EVERY cycle)
    csa_cc_mismatches = 0
    for i, (base_hex, cc_hex, csa_hex) in enumerate(records):
        if cc_hex != csa_hex:
            csa_cc_mismatches += 1
            if csa_cc_mismatches <= 5:
                print(f"Cycle {i}: CC={cc_hex} != CSA={csa_hex}")

    if csa_cc_mismatches == 0:
        print(f"PERFECT! Candidate A (CC) and Candidate B (CSA) matched 100% ({total}/{total} cycles)!")
    else:
        print(f"ERROR: Candidate A vs B had {csa_cc_mismatches} mismatches!")
        sys.exit(1)

    # Check 2: Final drained sum across baseline, CC, and CSA
    final_base, final_cc, final_csa = records[-1]
    print(f"Final drained sums:")
    print(f"  Baseline   : 0x{final_base}")
    print(f"  Candidate A: 0x{final_cc}")
    print(f"  Candidate B: 0x{final_csa}")

    if final_base == final_cc == final_csa:
        print("PERFECT! Final accumulated results are 100% BIT-IDENTICAL across Baseline, CC, and CSA!")
    else:
        print("ERROR: Final drained sums did not match!")
        sys.exit(1)

if __name__ == "__main__":
    main()
