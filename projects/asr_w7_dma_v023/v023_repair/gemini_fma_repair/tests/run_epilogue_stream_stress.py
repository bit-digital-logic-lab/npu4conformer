#!/usr/bin/env python3
"""
run_epilogue_stream_stress.py
Comprehensive End-to-End Test Harness for epilogue_stream_engine_v023.
Covers:
- Non-trivial scale and bias (FMA MODE_SCALE_BIAS = 1)
- Scale-only mode (MODE_SCALE_ONLY = 2)
- Conv-only bypass (MODE_CONV_ONLY = 0)
- ReLU activation and bypass
- Banker's Rounding (RNE), halfway tie-breaking, and cancellation
- Saturation clamping to [-32768, 32767]
- Odd-length bursts and tail-beat handling in 128-bit packer
- Pseudo-random backpressure stalls on downstream interfaces
- Mid-burst synchronous abort and clean recovery
"""

import os
import sys
import subprocess
import random
import struct

sys.path.append('/home/yang/Desktop/项目/v023_repair/gemini_fma_repair')
from reference.fma_reference import fma_exact_rational, u32_to_f32, f32_to_u32

def c48_to_f32(c48_val: int) -> int:
    """Exact conversion of signed 48-bit integer to IEEE-754 FP32 bit pattern."""
    if c48_val == 0:
        return 0
    sign = 1 if c48_val < 0 else 0
    mag = abs(c48_val)
    # Find MSB
    msb = mag.bit_length() - 1 # 0 to 47
    exp = msb + 127
    if msb >= 23:
        shift = msb - 23
        mant24 = mag >> shift
        round_b = (mag >> (shift - 1)) & 1 if shift > 0 else 0
        sticky = 1 if (shift > 1 and (mag & ((1 << (shift - 1)) - 1)) != 0) else 0
    else:
        shift = 23 - msb
        mant24 = mag << shift
        round_b = 0
        sticky = 0
    # RNE
    if round_b and (sticky or (mant24 & 1)):
        mant24 += 1
        if mant24 == (1 << 24):
            mant24 = 1 << 23
            exp += 1
    return (sign << 31) | (exp << 23) | (mant24 & 0x7fffff)

def f32_to_i16_sat(u_f32: int) -> int:
    """Exact conversion of IEEE-754 FP32 bit pattern to INT16 with RNE and saturation."""
    s = (u_f32 >> 31) & 1
    e = (u_f32 >> 23) & 0xff
    m = u_f32 & 0x7fffff
    if e == 255: # NaN or Inf
        return 0 if m != 0 else (-32768 if s else 32767)
    if e == 0: # FTZ / zero
        return 0
    val = u32_to_f32(u_f32)
    # Banker's rounding in python
    rounded = int(round(val))
    if rounded > 32767: rounded = 32767
    elif rounded < -32768: rounded = -32768
    return rounded & 0xffff

def simulate_pipeline_element(c48: int, mode: int, relu_en: bool, scale_u: int, bias_u: int) -> int:
    f32_in = c48_to_f32(c48)
    if mode == 0:
        f32_fma = f32_in # conv bypass
    elif mode == 2:
        f32_fma = fma_exact_rational(f32_in, scale_u, 0)
    else: # mode 1: scale + bias
        f32_fma = fma_exact_rational(f32_in, scale_u, bias_u)
    
    # ReLU
    if relu_en:
        # if negative, clamp to 0
        if (f32_fma >> 31) & 1:
            f32_fma = 0
    
    return f32_to_i16_sat(f32_fma)

def main():
    work_dir = '/home/yang/Desktop/项目/v023_repair/gemini_fma_repair'
    sim_dir = os.path.join(work_dir, 'sim')
    tests_dir = os.path.join(work_dir, 'tests')
    candidate_dir = os.path.join(work_dir, 'candidate')
    os.makedirs(sim_dir, exist_ok=True)

    stim_file = os.path.join(sim_dir, 'stimulus.txt')
    out_file = os.path.join(sim_dir, 'output.txt')
    packed_file = os.path.join(sim_dir, 'output_packed.txt')

    random.seed(42)

    # Test batches to run:
    # Each batch is (name, mode, relu_en, spill, scale_u, bias_u, tag, burst_len, c48_list, backpressure, trigger_abort_midway)
    batches = []

    # 1. Non-trivial scale and bias (FMA MODE 1)
    # scale = 0.125 (0x3e000000), bias = 5.0 (0x40a00000)
    # 5 beats (odd length = 20 elements -> tests packer tail)
    c48_batch1 = []
    for _ in range(5 * 4):
        c48_batch1.append(random.randint(-1000, 1000))
    batches.append(("non_trivial_fma_scale_bias", 1, 0, 0, 0x3e000000, 0x40a00000, 0x1001, 5, c48_batch1, 0, False))

    # 2. Scale-only mode (FMA MODE 2)
    # scale = 1.75 (0x3fe00000)
    # 4 beats (16 elements)
    c48_batch2 = []
    for _ in range(4 * 4):
        c48_batch2.append(random.randint(-500, 500))
    batches.append(("scale_only_mode", 2, 0, 0, 0x3fe00000, 0x00000000, 0x1002, 4, c48_batch2, 0, False))

    # 3. Conv-only bypass mode (MODE 0)
    # 6 beats (24 elements)
    c48_batch3 = []
    for _ in range(6 * 4):
        c48_batch3.append(random.randint(-2000, 2000))
    batches.append(("conv_only_bypass", 0, 0, 0, 0x3f800000, 0x00000000, 0x1003, 6, c48_batch3, 0, False))

    # 4. ReLU activation enabled (MODE 1, relu=1)
    # scale = 0.5 (0x3f000000), bias = -10.0 (0xc1200000)
    # 7 beats (odd length = 28 elements)
    c48_batch4 = []
    for _ in range(7 * 4):
        c48_batch4.append(random.randint(-100, 100))
    batches.append(("relu_active_test", 1, 1, 0, 0x3f000000, 0xc1200000, 0x1004, 7, c48_batch4, 0, False))

    # 5. Extremes and Saturation
    # Values exceeding [-32768, 32767]
    c48_batch5 = [
        100000, 200000, 5000000, 100000000, # positive saturation
        -100000, -200000, -5000000, -100000000, # negative saturation
        0, 1, -1, 32767,
        -32768, 32768, -32769, 65536
    ]
    batches.append(("extremes_saturation", 0, 0, 0, 0x3f800000, 0x00000000, 0x1005, 4, c48_batch5, 0, False))

    # 6. Tie-breaking and halfway rounding
    # C48 values that create exact halfway floats
    c48_batch6 = [
        2, 3, 5, 7,
        10, 11, 14, 15,
        20, 21, 22, 23
    ] # 3 beats (12 elements, odd length)
    # scale = 0.5 (0x3f000000), bias = 0.0 -> creates .5 fractions
    batches.append(("tie_breaking_halfway", 2, 0, 0, 0x3f000000, 0x00000000, 0x1006, 3, c48_batch6, 0, False))

    # 7. Random backpressure test (stalls on a16_ready and packed_ready)
    # 20 beats (80 elements)
    c48_batch7 = []
    for _ in range(20 * 4):
        c48_batch7.append(random.randint(-2000, 2000))
    batches.append(("random_backpressure_burst", 1, 0, 0, 0x3e800000, 0x40400000, 0x1007, 20, c48_batch7, 1, False))

    # 8. Mid-burst abort test
    # Burst 8A will be aborted midway, then Burst 8B will run cleanly
    c48_batch8a = [100] * 16
    batches.append(("aborted_burst_1", 0, 0, 0, 0x3f800000, 0x00000000, 0xdead, 4, c48_batch8a, 0, True))

    c48_batch8b = [200] * 12 # 3 beats cleanly after abort (odd length)
    batches.append(("recovery_after_abort_1", 1, 0, 0, 0x3f000000, 0x41200000, 0x1008, 3, c48_batch8b, 0, False))

    # 9. Second abort stress cycle
    c48_batch9a = [300] * 20
    batches.append(("aborted_burst_2", 1, 0, 0, 0x3e000000, 0x40000000, 0xbeef, 5, c48_batch9a, 1, True))

    # 10. Large multi-beat randomized stress under continuous random backpressure
    # 35 beats (140 elements, odd length)
    c48_batch10 = []
    for _ in range(35 * 4):
        c48_batch10.append(random.randint(-30000, 30000))
    batches.append(("continuous_bp_heavy_stress", 1, 1, 0, 0x3d800000, 0x3f800000, 0x1010, 35, c48_batch10, 1, False))

    # Write stimulus file and generate expected golden outputs
    gold_64_beats = [] # (tag, data64_hex, last)
    gold_128_beats = [] # (tag, data128_hex, last)

    with open(stim_file, 'w') as f_stim:
        for name, mode, relu_en, spill, sc, bi, tag, nbeats, c48_elems, bp, do_abort in batches:
            if do_abort:
                # Trigger abort during this burst
                f_stim.write(f"C {mode} {relu_en} {spill} {sc:08x} {bi:08x} {tag:04x}\n")
                f_stim.write("B 0\n")
                # send 1 beat, then abort
                c0 = c48_elems[0] & 0xffffffffffff
                c1 = c48_elems[1] & 0xffffffffffff
                c2 = c48_elems[2] & 0xffffffffffff
                c3 = c48_elems[3] & 0xffffffffffff
                c_hex = (c3 << 144) | (c2 << 96) | (c1 << 48) | c0
                f_stim.write(f"D {c_hex:048x} {tag:04x} 0\n")
                f_stim.write("A\n") # Abort!
                f_stim.write("W 20\n")
                # Do not record in gold since it is aborted
                continue

            f_stim.write(f"C {mode} {relu_en} {spill} {sc:08x} {bi:08x} {tag:04x}\n")
            f_stim.write(f"B {bp}\n")

            # Process beats
            batch_64_beats = []
            for b in range(nbeats):
                is_last = 1 if (b == nbeats - 1) else 0
                lane_i16 = []
                c48_words = []
                for lane in range(4):
                    idx = b * 4 + lane
                    c_val = c48_elems[idx]
                    c48_words.append(c_val & 0xffffffffffff)
                    res_i16 = simulate_pipeline_element(c_val, mode, relu_en, sc, bi)
                    lane_i16.append(res_i16)

                c_hex = (c48_words[3] << 144) | (c48_words[2] << 96) | (c48_words[1] << 48) | c48_words[0]
                f_stim.write(f"D {c_hex:048x} {tag:04x} {is_last}\n")

                # Pack 64-bit beat
                d64 = (lane_i16[3] << 48) | (lane_i16[2] << 32) | (lane_i16[1] << 16) | lane_i16[0]
                batch_64_beats.append((tag, f"{d64:016x}", is_last))

            # Simulate 128-bit packer for this batch
            batch_128_beats = []
            half = None
            for tag_b, hex64, last_b in batch_64_beats:
                val64 = int(hex64, 16)
                if half is None:
                    if last_b:
                        # Odd beat at last: emit {64'd0, val64}
                        p128 = val64
                        batch_128_beats.append((tag_b, f"{p128:032x}", 1))
                        half = None
                    else:
                        half = val64
                else:
                    p128 = (val64 << 64) | half
                    batch_128_beats.append((tag_b, f"{p128:032x}", last_b))
                    half = None

            gold_64_beats.extend(batch_64_beats)
            gold_128_beats.extend(batch_128_beats)
            f_stim.write("W 30\n")

        f_stim.write("E\n")

    print(f"Stimulus generated. Total expected 64-bit beats: {len(gold_64_beats)}, 128-bit beats: {len(gold_128_beats)}")

    # Compile simulation
    vvp_file = os.path.join(sim_dir, 'tb_epilogue_stream_engine_stress.vvp')
    src_files = [
        os.path.join(candidate_dir, 'epilogue_i48_to_f32.sv'),
        os.path.join(candidate_dir, 'fp32_fma_pipe.sv'),
        os.path.join(candidate_dir, 'epilogue_fma_stage.sv'),
        os.path.join(candidate_dir, 'epilogue_relu.sv'),
        os.path.join(candidate_dir, 'epilogue_f32_to_i16.sv'),
        os.path.join(candidate_dir, 'epilogue_lane.sv'),
        os.path.join(candidate_dir, 'epilogue_stream_engine_v023.sv'),
        os.path.join(tests_dir, 'tb_epilogue_stream_engine_stress.sv')
    ]

    cmd_compile = ['iverilog', '-g2012', '-o', vvp_file] + src_files
    print("Compiling testbench...")
    cp_comp = subprocess.run(cmd_compile, capture_output=True, text=True)
    if cp_comp.returncode != 0:
        print("Compilation FAILED:\n", cp_comp.stderr)
        sys.exit(1)
    print("Compilation SUCCESS.")

    # Run simulation (-j1 single process)
    cmd_run = ['vvp', 'tb_epilogue_stream_engine_stress.vvp', '+stim=stimulus.txt', '+out=output.txt', '+packed_out=output_packed.txt']
    print("Running simulation with watchdog...")
    cp_run = subprocess.run(cmd_run, cwd=sim_dir, capture_output=True, text=True, timeout=60)
    print(cp_run.stdout)
    if cp_run.returncode != 0:
        print("Simulation returned non-zero code:", cp_run.returncode)
        sys.exit(1)

    # Verify outputs
    with open(out_file, 'r') as f:
        actual_64_lines = [l.strip().split() for l in f if l.strip()]
    with open(packed_file, 'r') as f:
        actual_128_lines = [l.strip().split() for l in f if l.strip()]

    print(f"Verifying {len(actual_64_lines)} actual 64-bit beats against {len(gold_64_beats)} expected...")
    errors_64 = 0
    if len(actual_64_lines) != len(gold_64_beats):
        print(f"ERROR: Count mismatch! got {len(actual_64_lines)} beats, expected {len(gold_64_beats)}")
        errors_64 += 1

    for i in range(min(len(actual_64_lines), len(gold_64_beats))):
        act_tag, act_hex, act_last = actual_64_lines[i]
        exp_tag, exp_hex, exp_last = gold_64_beats[i]
        exp_tag_str = f"{exp_tag:04x}"
        exp_last_str = str(exp_last)
        if (act_hex != exp_hex) or (act_tag != exp_tag_str) or (act_last != exp_last_str):
            print(f"Mismatch at beat {i}: act({act_tag}, {act_hex}, {act_last}) vs exp({exp_tag_str}, {exp_hex}, {exp_last_str})")
            errors_64 += 1
            if errors_64 >= 10: break

    print(f"Verifying {len(actual_128_lines)} actual 128-bit beats against {len(gold_128_beats)} expected...")
    errors_128 = 0
    if len(actual_128_lines) != len(gold_128_beats):
        print(f"ERROR: Packed count mismatch! got {len(actual_128_lines)} beats, expected {len(gold_128_beats)}")
        errors_128 += 1

    for i in range(min(len(actual_128_lines), len(gold_128_beats))):
        act_tag, act_hex, act_last = actual_128_lines[i]
        exp_tag, exp_hex, exp_last = gold_128_beats[i]
        exp_tag_str = f"{exp_tag:04x}"
        exp_last_str = str(exp_last)
        if (act_hex != exp_hex) or (act_tag != exp_tag_str) or (act_last != exp_last_str):
            print(f"Mismatch at packed beat {i}: act({act_tag}, {act_hex}, {act_last}) vs exp({exp_tag_str}, {exp_hex}, {exp_last_str})")
            errors_128 += 1
            if errors_128 >= 10: break

    print("=======================================================")
    print(f"STRESS VERIFICATION SUMMARY: 64-bit errors={errors_64}, 128-bit errors={errors_128}")
    print("=======================================================")

    if errors_64 == 0 and errors_128 == 0:
        print("ALL END-TO-END STREAM STRESS TESTS PASSED 100% BIT-EXACT")
        return 0
    else:
        print("STRESS VERIFICATION FAILED")
        return 1

if __name__ == '__main__':
    sys.exit(main())
