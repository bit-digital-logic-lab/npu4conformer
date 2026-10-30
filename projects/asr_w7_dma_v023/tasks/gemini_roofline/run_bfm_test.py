"""Compile and execute the Matrix Prefetch DMA BFM simulation with iverilog.

Measures Before (Serial) vs After (Overlapped Ping-Pong Prefetch) under identical workload
and DDR conditions. Verifies bit-exact numerical equality against independent golden.
Outputs bfm_run.log and bfm_results.json.
"""

import json
import subprocess
import time
from pathlib import Path

TASKS_DIR = Path('/home/yang/Desktop/项目/tasks/gemini_roofline')
RTL_DIR = TASKS_DIR / 'rtl'
TB_DIR = TASKS_DIR / 'tb'

def run_bfm():
    iverilog_bin = '/home/yang/yosys-sta/oss-cad-suite/bin/iverilog'
    vvp_bin = '/home/yang/yosys-sta/oss-cad-suite/bin/vvp'

    sim_out = TASKS_DIR / 'sim_matrix_prefetch.vvp'
    log_out = TASKS_DIR / 'bfm_run.log'

    cmd_compile = [
        iverilog_bin,
        '-g2012',
        '-o', str(sim_out),
        str(RTL_DIR / 'matrix_prefetch_dma_engine.sv'),
        str(TB_DIR / 'tb_matrix_prefetch_dma.sv')
    ]

    print("Compiling RTL + TB with iverilog...")
    t0 = time.time()
    res_compile = subprocess.run(cmd_compile, capture_output=True, text=True)
    compile_time = time.time() - t0

    if res_compile.returncode != 0:
        print("Compilation failed!")
        print("STDOUT:", res_compile.stdout)
        print("STDERR:", res_compile.stderr)
        return False

    print(f"Compilation succeeded in {compile_time:.2f}s. Running simulation...")

    cmd_sim = [vvp_bin, str(sim_out)]
    t1 = time.time()
    res_sim = subprocess.run(cmd_sim, capture_output=True, text=True)
    sim_time = time.time() - t1

    log_out.write_text(f"=== Compilation Log ===\n{res_compile.stdout}\n{res_compile.stderr}\n\n=== Simulation Log ===\n{res_sim.stdout}\n{res_sim.stderr}")

    print("Simulation Output:")
    print(res_sim.stdout)

    if res_sim.returncode != 0:
        print("Simulation failed with non-zero exit code!")
        return False

    # Parse simulation output
    serial_cycles = None
    overlap_cycles = None
    serial_dma_wait = None
    overlap_dma_wait = None
    speedup = None
    pass_numerical = False

    for line in res_sim.stdout.splitlines():
        if "Serial Mode Completed:" in line:
            parts = line.split()
            serial_cycles = int(parts[4])
            serial_dma_wait = int(parts[8])
        elif "Overlapped Mode Completed:" in line:
            parts = line.split()
            overlap_cycles = int(parts[4])
            overlap_dma_wait = int(parts[8])
        elif "Effective Speedup" in line:
            speedup = float(line.split(':')[1].replace('x', '').strip())
        elif "[BFM-PASS]" in line:
            pass_numerical = True

    results = {
        "status": "PASS" if pass_numerical and res_sim.returncode == 0 else "FAIL",
        "compiler": "iverilog 2012",
        "workload": {
            "num_tiles": 4,
            "tile_a_bytes": 2048,
            "tile_w_bytes": 1024,
            "tile_c_bytes": 6144,
            "ddr_latency_cycles": 8,
            "bus_width_bits": 128
        },
        "before_serial": {
            "total_cycles": serial_cycles,
            "dma_wait_cycles": serial_dma_wait
        },
        "after_overlapped": {
            "total_cycles": overlap_cycles,
            "dma_wait_cycles": overlap_dma_wait
        },
        "metrics": {
            "dma_wait_reduction_percent": round((1.0 - overlap_dma_wait / serial_dma_wait) * 100, 2) if serial_dma_wait else None,
            "speedup_factor": speedup,
            "numerical_bit_exact": pass_numerical
        },
        "execution_time_seconds": round(sim_time, 3)
    }

    results_out = TASKS_DIR / 'bfm_results.json'
    results_out.write_text(json.dumps(results, indent=2))
    print(f"BFM results written to {results_out}")
    return True

if __name__ == '__main__':
    run_bfm()
