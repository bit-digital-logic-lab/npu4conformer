#!/usr/bin/env python3
import sys, os, subprocess
from pathlib import Path
from run_tiles_test import generate_tile_vectors

def main():
    bench_dir = Path(__file__).parent
    cand_dir = bench_dir.parent / "candidate"
    work_rtl = bench_dir.parent.parent.parent / "work" / "rtl" / "pe_direct_v020.sv"
    vec_file = bench_dir / "test_vectors_pe.txt"
    out_file = bench_dir / "sim_output_pe_compare.txt"

    num_tiles = 1000
    k_len = 32
    print(f"Generating {num_tiles} tiles of K={k_len} workloads...")
    _, golden_sums = generate_tile_vectors(vec_file, num_tiles=num_tiles, k_len=k_len)

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

    print("Analyzing outputs per tile...")
    with open(out_file, "r") as f:
        records = [line.strip().split() for line in f if line.strip()]

    # Each tile has:
    # 32 data cycles + 5 drain cycles + 1 clear cycle + 1 idle cycle = 39 cycles
    cycles_per_tile = k_len + 5 + 1 + 1
    tile_mismatches = 0

    for t in range(num_tiles):
        tile_end_cycle = t * cycles_per_tile + (k_len + 5 - 1)
        base_hex, cc_hex, csa_hex = records[tile_end_cycle]
        expected_hex = f"{golden_sums[t] & 0xFFFFFFFFFFFF:012x}"

        if base_hex != expected_hex or cc_hex != expected_hex or csa_hex != expected_hex:
            print(f"Mismatch at Tile {t}:")
            print(f"  Expected: {expected_hex}")
            print(f"  Base    : {base_hex}")
            print(f"  CC      : {cc_hex}")
            print(f"  CSA     : {csa_hex}")
            tile_mismatches += 1
            if tile_mismatches >= 10:
                break

    if tile_mismatches == 0:
        print(f"SUCCESS! All {num_tiles} tiles ({num_tiles * k_len} MAC operations) matched 100% bit-exact across Golden, Baseline, CC Candidate, and CSA Candidate!")
    else:
        print(f"FAILED with {tile_mismatches} tile mismatches.")
        sys.exit(1)

if __name__ == "__main__":
    main()
