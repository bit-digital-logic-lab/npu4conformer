#!/usr/bin/env python3
import sys, os, subprocess, random
from pathlib import Path

# Add candidate directory to sys.path
sys.path.append(str(Path(__file__).parent.parent / "candidate"))
from golden_pe import compute_pe_single, accumulate_c48

class CycleAccuratePEModel:
    """Cycle-accurate model of pe_direct_v020 to verify bit-exact pipeline timing."""
    def __init__(self):
        self.reset()

    def reset(self):
        self.sum = 0
        self.valid = [0, 0, 0]
        self.pipeline_prod = [0, 0, 0]

    def step(self, a_in, w_in, pos, clip, av_in, wv_in, clear_sum, flush):
        # Sample current sum before clock edge
        curr_sum_sample = self.sum

        # Calculate input product if valid
        pair_valid = 1 if (av_in and wv_in and not flush) else 0
        if pair_valid:
            prod = compute_pe_single(a_in, w_in, pos, clip)
        else:
            prod = 0

        # Pipeline stages
        # Stage 0: takes input at posedge clk
        # Stage 1: raw product
        # Stage 2: aligned, magnitude, product2
        # Stage 3: accumulation into sum
        
        # Accumulation update:
        # if (clear_sum) sum <= 0
        # else if (!flush && valid[2]) sum <= sum + product2
        if clear_sum:
            self.sum = 0
        elif not flush and self.valid[2]:
            self.sum = accumulate_c48(self.sum, self.pipeline_prod[2])

        if flush:
            self.valid = [0, 0, 0]
            self.pipeline_prod = [0, 0, 0]
        else:
            # Advance pipeline
            self.pipeline_prod[2] = self.pipeline_prod[1]
            self.valid[2] = self.valid[1]

            self.pipeline_prod[1] = self.pipeline_prod[0]
            self.valid[1] = self.valid[0]

            self.pipeline_prod[0] = prod
            self.valid[0] = pair_valid

        return curr_sum_sample

def generate_test_vectors(filename, num_random=5000):
    lines = []
    # 1. Exhaustive W7 (0..127) with corner A values
    a_corners = [-32768, -32767, -32766, -1, 0, 1, 2, 32766, 32767, -256, 256, -16, 16]
    pos_cases = [0x0000, 0x1111, 0x4444, 0x8888, 0xCCCC, 0xC840, 0x048C]

    print("Generating corner & exhaustive vectors...")
    for a in a_corners:
        a_u16 = a & 0xFFFF
        for p_val in pos_cases:
            for clip in [0, 1]:
                # Test a burst of W7 values
                for w in range(128):
                    lines.append((a_u16, w, p_val, clip, 1, 1, 0, 0)) # normal valid
                # Insert a bubble
                lines.append((0, 0, p_val, clip, 0, 1, 0, 0))
                lines.append((0, 0, p_val, clip, 1, 0, 0, 0))

    # 2. Test clear_sum and flush scenarios
    lines.append((100, 5, 0xC000, 1, 1, 1, 0, 0))
    lines.append((200, 10, 0xC000, 1, 1, 1, 0, 0))
    lines.append((300, 15, 0xC000, 1, 1, 1, 0, 0))
    lines.append((0, 0, 0xC000, 0, 0, 0, 1, 0)) # clear_sum
    lines.append((400, 20, 0xC000, 1, 1, 1, 0, 0))
    lines.append((500, 25, 0xC000, 1, 1, 1, 0, 1)) # flush
    lines.append((600, 30, 0xC000, 1, 1, 1, 0, 0))

    # 3. Random stress vectors
    print(f"Generating {num_random} random stress vectors...")
    random.seed(42)
    for _ in range(num_random):
        a_rnd = random.randint(-32768, 32767) & 0xFFFF
        w_rnd = random.randint(0, 127)
        # Random valid positions where each nibble <= 12
        p0 = random.randint(0, 12)
        p1 = random.randint(0, 12)
        p2 = random.randint(0, 12)
        p3 = random.randint(0, 12)
        pos_rnd = p0 | (p1 << 4) | (p2 << 8) | (p3 << 12)
        clip_rnd = random.randint(0, 1)
        av_rnd = 1 if random.random() > 0.15 else 0
        wv_rnd = 1 if random.random() > 0.15 else 0
        clr_rnd = 1 if random.random() < 0.01 else 0
        flush_rnd = 1 if random.random() < 0.01 else 0
        lines.append((a_rnd, w_rnd, pos_rnd, clip_rnd, av_rnd, wv_rnd, clr_rnd, flush_rnd))

    with open(filename, "w") as f:
        for item in lines:
            f.write(f"{item[0]:04x} {item[1]:02x} {item[2]:04x} {item[3]} {item[4]} {item[5]} {item[6]} {item[7]}\n")
    print(f"Written {len(lines)} test vectors to {filename}")
    return lines

def main():
    bench_dir = Path(__file__).parent
    vec_file = bench_dir / "test_vectors_pe.txt"
    out_file = bench_dir / "sim_output_pe.txt"
    work_rtl = bench_dir.parent.parent.parent / "work" / "rtl" / "pe_direct_v020.sv"

    vectors = generate_test_vectors(vec_file, num_random=10000)

    # Compile with iverilog
    print("Compiling pe_direct_v020 with iverilog...")
    compile_cmd = [
        "/home/yang/yosys-sta/oss-cad-suite/bin/iverilog",
        "-g2012",
        "-o", str(bench_dir / "pe_sim.vvp"),
        str(bench_dir / "tb_pe_baseline.sv"),
        str(work_rtl)
    ]
    res = subprocess.run(compile_cmd, capture_output=True, text=True, cwd=str(bench_dir.parent))
    if res.returncode != 0:
        print("Compilation failed:")
        print(res.stderr)
        sys.exit(1)

    print("Running simulation with vvp...")
    run_cmd = ["/home/yang/yosys-sta/oss-cad-suite/bin/vvp", str(bench_dir / "pe_sim.vvp")]
    res = subprocess.run(run_cmd, capture_output=True, text=True, cwd=str(bench_dir.parent))
    if res.returncode != 0:
        print("Simulation failed:")
        print(res.stderr)
        sys.exit(1)
    print(res.stdout)

    # Read output and verify against Python model
    print("Verifying simulation output against Python Golden Model...")
    with open(out_file, "r") as f:
        rtl_outputs = [line.strip() for line in f if line.strip()]

    model = CycleAccuratePEModel()
    mismatches = 0
    total_checks = len(vectors)

    for i, vec in enumerate(vectors):
        # Execute Python step
        expected_sum = model.step(vec[0], vec[1], vec[2], vec[3], vec[4], vec[5], vec[6], vec[7])
        expected_hex = f"{expected_sum & 0xFFFFFFFFFFFF:012x}"
        actual_hex = rtl_outputs[i].lower()

        if expected_hex != actual_hex:
            print(f"MISMATCH at step {i}: Expected {expected_hex}, Got {actual_hex} (Input: A={vec[0]:04x}, W={vec[1]:02x}, Pos={vec[2]:04x}, Clip={vec[3]})")
            mismatches += 1
            if mismatches >= 10:
                print("Too many mismatches, aborting.")
                break

    if mismatches == 0:
        print(f"SUCCESS! All {total_checks} test steps matched bit-for-bit between Python Golden and RTL pe_direct_v020!")
    else:
        print(f"FAILURE: {mismatches} mismatches found.")
        sys.exit(1)

if __name__ == "__main__":
    main()
