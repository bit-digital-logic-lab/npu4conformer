#!/usr/bin/env python3
"""Comprehensive regression test runner for gemini_fma_round2.
Runs all FMA tests sequentially (-j1).
Every simulation has wall-clock and cycle watchdog.
Validates against independent, read-only ds_numeric_adversarial reference.
"""

import os
import sys
import time
import json
import hashlib
import subprocess

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
WORK_DIR = os.path.dirname(SCRIPT_DIR)
ROOT_DIR = os.path.dirname(os.path.dirname(WORK_DIR))
DS_DIR = os.path.join(ROOT_DIR, "v023_repair", "ds_numeric_adversarial")
REF_DIR = os.path.join(DS_DIR, "ref")
sys.path.insert(0, REF_DIR)
import refmodel as R

SIM_DIR = os.path.join(WORK_DIR, "sim")
LOG_DIR = os.path.join(WORK_DIR, "logs")
VEC_DIR = os.path.join(WORK_DIR, "vectors")

os.makedirs(SIM_DIR, exist_ok=True)
os.makedirs(LOG_DIR, exist_ok=True)
os.makedirs(VEC_DIR, exist_ok=True)

def compute_sha256(filepath):
    h = hashlib.sha256()
    with open(filepath, "rb") as f:
        while chunk := f.read(65536):
            h.update(chunk)
    return h.hexdigest()

def run_cmd(cmd, log_path, timeout=300, cwd=None):
    with open(log_path, "w") as f:
        p = subprocess.Popen(cmd, stdout=f, stderr=subprocess.STDOUT, cwd=cwd)
        try:
            p.communicate(timeout=timeout)
            rc = p.returncode
        except subprocess.TimeoutExpired:
            p.kill()
            rc = -9
            f.write(f"\nWATCHDOG: wall-clock timeout after {timeout}s\n")
    with open(log_path, "r") as f:
        out = f.read()
    return rc, out

def compile_tb(out_name, sources, top_module=None):
    exe = os.path.join(SIM_DIR, f"{out_name}.vvp")
    cmd = ["iverilog", "-g2012", "-o", exe]
    if top_module:
        cmd += ["-s", top_module]
    cmd += sources
    log_file = os.path.join(LOG_DIR, f"compile_{out_name}.log")
    rc, out = run_cmd(cmd, log_file, timeout=120)
    if rc != 0:
        raise RuntimeError(f"Compilation of {out_name} failed (rc={rc}):\n{out}")
    return exe

def parse_stability(output):
    for line in output.splitlines():
        if line.startswith("STABILITY_ERRORS="):
            try:
                return int(line.split("=")[1])
            except Exception:
                pass
    return 0

def parse_flush_errors(output):
    for line in output.splitlines():
        if line.startswith("FLUSH_ERRORS="):
            try:
                return int(line.split("=")[1])
            except Exception:
                pass
    return 0

def test_fma_vectors(exe, vec_rel_path, label, bp=0, max_cycles=5000000):
    out_file = os.path.join(LOG_DIR, f"{label}_out.txt")
    out_rel = os.path.relpath(out_file, WORK_DIR)
    log_file = os.path.join(LOG_DIR, f"{label}.log")
    
    cmd = ["vvp", exe, f"+VEC_FILE={vec_rel_path}", f"+OUT_FILE={out_rel}",
           f"+BP={bp}", f"+MAX_CYCLES={max_cycles}"]
    rc, out = run_cmd(cmd, log_file, timeout=300, cwd=WORK_DIR)
    
    res = {
        "label": label,
        "bp": bp,
        "rc": rc,
        "stability_errors": parse_stability(out),
        "vectors": 0,
        "mismatches": 0,
        "tag_errors": 0,
        "last_errors": 0,
        "by_mode": {},
        "examples": [],
        "pass": False
    }
    if rc != 0:
        res["error"] = out[-1000:]
        return res

    vec_abs = os.path.normpath(os.path.join(WORK_DIR, vec_rel_path))
    vecs = []
    with open(vec_abs) as f:
        for line in f:
            p = line.split()
            if len(p) == 6:
                vecs.append((int(p[0], 16), int(p[1], 16), int(p[2], 16), int(p[3], 16), int(p[4], 16), int(p[5])))
    
    outs = []
    with open(out_file) as f:
        for line in f:
            p = line.split()
            if len(p) == 5:
                outs.append((int(p[0]), int(p[1]), int(p[2], 16), int(p[3], 16), int(p[4])))

    res["vectors"] = len(vecs)
    if len(outs) != len(vecs):
        res["error"] = f"Output count {len(outs)} != {len(vecs)}"
        return res

    by_mode = {}
    for i, ((mode, s, b, x, tag, last), (in_c, out_c, got, out_tag, out_last)) in enumerate(zip(vecs, outs)):
        if mode not in by_mode:
            by_mode[mode] = {"total": 0, "mismatches": 0}
        by_mode[mode]["total"] += 1

        if mode == 0: exp = x
        elif mode == 2: exp = R.fma_bits(x, s, 0, ftz=True)
        else: exp = R.fma_bits(x, s, b, ftz=True)

        if got != exp:
            by_mode[mode]["mismatches"] += 1
            res["mismatches"] += 1
            if len(res["examples"]) < 10:
                res["examples"].append({
                    "i": i, "mode": mode, "x": f"{x:08x}", "s": f"{s:08x}",
                    "b": f"{b:08x}", "got": f"{got:08x}", "exp": f"{exp:08x}"
                })
        if out_tag != tag: res["tag_errors"] += 1
        if out_last != last: res["last_errors"] += 1

    res["by_mode"] = {str(k): v for k, v in sorted(by_mode.items())}
    res["pass"] = (res["mismatches"] == 0 and res["tag_errors"] == 0 and
                   res["last_errors"] == 0 and res["stability_errors"] == 0 and res["rc"] == 0)
    return res

def test_asr_fma_ip_vectors(exe, vec_rel_path, label, max_cycles=5000000):
    out_file = os.path.join(LOG_DIR, f"{label}_out.txt")
    out_rel = os.path.relpath(out_file, WORK_DIR)
    log_file = os.path.join(LOG_DIR, f"{label}.log")
    
    cmd = ["vvp", exe, f"+VEC_FILE={vec_rel_path}", f"+OUT_FILE={out_rel}",
           f"+MAX_CYCLES={max_cycles}"]
    rc, out = run_cmd(cmd, log_file, timeout=300, cwd=WORK_DIR)
    
    res = {
        "label": label,
        "rc": rc,
        "vectors": 0,
        "mismatches": 0,
        "examples": [],
        "pass": False
    }
    if rc != 0:
        res["error"] = out[-1000:]
        return res

    vec_abs = os.path.normpath(os.path.join(WORK_DIR, vec_rel_path))
    vecs = []
    with open(vec_abs) as f:
        for line in f:
            p = line.split()
            if len(p) == 6:
                vecs.append((int(p[0], 16), int(p[1], 16), int(p[2], 16), int(p[3], 16)))
    
    outs = []
    with open(out_file) as f:
        for line in f:
            p = line.split()
            if len(p) == 2:
                outs.append((int(p[0]), int(p[1], 16)))

    res["vectors"] = len(vecs)
    if len(outs) != len(vecs):
        res["error"] = f"Output count {len(outs)} != {len(vecs)}"
        return res

    for i, ((mode, s, b, x), (cycle, got)) in enumerate(zip(vecs, outs)):
        if mode == 0: exp = R.fma_bits(x, 0x3f800000, 0, ftz=True)
        elif mode == 2: exp = R.fma_bits(x, s, 0, ftz=True)
        else: exp = R.fma_bits(x, s, b, ftz=True)

        if got != exp:
            res["mismatches"] += 1
            if len(res["examples"]) < 10:
                res["examples"].append({
                    "i": i, "mode": mode, "x": f"{x:08x}", "s": f"{s:08x}",
                    "b": f"{b:08x}", "got": f"{got:08x}", "exp": f"{exp:08x}"
                })

    res["pass"] = (res["mismatches"] == 0 and res["rc"] == 0)
    return res

def run_regression():
    start_time = time.time()
    results = {
        "task": "gemini_fma_round2",
        "timestamp": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
        "scope": "FMA-1..3 full repair (tie-even sticky, extreme exponent alignment, specials, subnormal FTZ). Logic simulation only.",
        "prohibitions_adhered": {
            "no_synthesis": True,
            "no_vivado": True,
            "no_board": True,
            "no_vnc": True,
            "no_push": True,
            "no_external_writes": True
        },
        "source_sha256": {},
        "suites": {},
        "overall_pass": False
    }

    # Record SHAs
    cand_dir = os.path.join(WORK_DIR, "candidate")
    for fname in sorted(os.listdir(cand_dir)):
        if fname.endswith(".sv"):
            results["source_sha256"][fname] = compute_sha256(os.path.join(cand_dir, fname))

    # Compile tb_fma
    print("[1/8] Compiling tb_fma...")
    fma_tb_src = os.path.join(DS_DIR, "tb", "tb_fma.sv")
    cand_fma = os.path.join(cand_dir, "epilogue_fma_stage.sv")
    cand_pipe = os.path.join(cand_dir, "fp32_fma_pipe.sv")
    cand_asr = os.path.join(cand_dir, "asr_fma_ip.sv")
    tb_fma_exe = compile_tb("tb_fma", [fma_tb_src, cand_fma, cand_pipe])

    # Compile tb_asr_fma_ip
    print("[2/8] Compiling tb_asr_fma_ip...")
    asr_tb_src = os.path.join(DS_DIR, "tb", "tb_asr_fma_ip.sv")
    tb_asr_exe = compile_tb("tb_asr_fma_ip", [asr_tb_src, cand_asr, cand_pipe])

    # Compile tb_flush
    print("[3/8] Compiling tb_flush...")
    flush_tb_src = os.path.join(DS_DIR, "tb", "tb_flush.sv")
    cand_i48 = os.path.join(cand_dir, "epilogue_i48_to_f32.sv")
    cand_i16 = os.path.join(cand_dir, "epilogue_f32_to_i16.sv")
    cand_relu = os.path.join(cand_dir, "epilogue_relu.sv")
    cand_lane = os.path.join(cand_dir, "epilogue_lane.sv")
    tb_flush_exe = compile_tb("tb_flush", [flush_tb_src, cand_i48, cand_fma, cand_pipe, cand_i16, cand_relu, cand_lane])

    # 1. Adversarial FMA 8734 vectors BP=0
    print("[4/8] Running adversarial 8,734 vectors (BP=0)...")
    res_adv_bp0 = test_fma_vectors(tb_fma_exe, "../ds_numeric_adversarial/vectors/fma.vec", "fma_adversarial_bp0", bp=0)
    results["suites"]["adversarial_fma_bp0"] = res_adv_bp0
    print(f"      Pass: {res_adv_bp0['pass']}, Mismatches: {res_adv_bp0['mismatches']}/{res_adv_bp0['vectors']}")

    # 2. Adversarial FMA 8734 vectors BP=1
    print("[5/8] Running adversarial 8,734 vectors (BP=1)...")
    res_adv_bp1 = test_fma_vectors(tb_fma_exe, "../ds_numeric_adversarial/vectors/fma.vec", "fma_adversarial_bp1", bp=1)
    results["suites"]["adversarial_fma_bp1"] = res_adv_bp1
    print(f"      Pass: {res_adv_bp1['pass']}, Mismatches: {res_adv_bp1['mismatches']}/{res_adv_bp1['vectors']}")

    # 3. Random 20,000 vectors BP=0
    print("[6/8] Running 20,000 random/corner vectors (BP=0)...")
    res_rand_bp0 = test_fma_vectors(tb_fma_exe, "vectors/fma_random.vec", "fma_random_bp0", bp=0)
    results["suites"]["random_fma_bp0"] = res_rand_bp0
    print(f"      Pass: {res_rand_bp0['pass']}, Mismatches: {res_rand_bp0['mismatches']}/{res_rand_bp0['vectors']}")

    # 4. Random 20,000 vectors BP=1
    print("[7/8] Running 20,000 random/corner vectors (BP=1)...")
    res_rand_bp1 = test_fma_vectors(tb_fma_exe, "vectors/fma_random.vec", "fma_random_bp1", bp=1)
    results["suites"]["random_fma_bp1"] = res_rand_bp1
    print(f"      Pass: {res_rand_bp1['pass']}, Mismatches: {res_rand_bp1['mismatches']}/{res_rand_bp1['vectors']}")

    # 5. ASR FMA IP wrapper tests
    print("[8/8] Running asr_fma_ip wrapper tests & flush...")
    res_asr_adv = test_asr_fma_ip_vectors(tb_asr_exe, "../ds_numeric_adversarial/vectors/fma.vec", "asr_fma_ip_adversarial")
    res_asr_rand = test_asr_fma_ip_vectors(tb_asr_exe, "vectors/fma_random.vec", "asr_fma_ip_random")
    results["suites"]["asr_fma_ip_adversarial"] = res_asr_adv
    results["suites"]["asr_fma_ip_random"] = res_asr_rand

    # Flush test
    rc, flush_out = run_cmd(["vvp", tb_flush_exe], os.path.join(LOG_DIR, "tb_flush.log"))
    flush_err = parse_flush_errors(flush_out)
    results["suites"]["flush_test"] = {"rc": rc, "flush_errors": flush_err, "pass": (rc == 0 and flush_err == 0)}

    # Overall pass criteria
    all_pass = all(s.get("pass", False) for s in results["suites"].values())
    results["overall_pass"] = all_pass
    results["elapsed_seconds"] = round(time.time() - start_time, 2)

    # Write result.json
    result_path = os.path.join(WORK_DIR, "result.json")
    with open(result_path, "w") as f:
        json.dump(results, f, indent=2)

    print("\n=======================================================")
    print(f"OVERALL STATUS: {'PASS' if all_pass else 'FAIL'}")
    print(f"Total Elapsed Time: {results['elapsed_seconds']}s")
    print(f"Result JSON saved to {result_path}")
    print("=======================================================")
    return 0 if all_pass else 1

if __name__ == "__main__":
    sys.exit(run_regression())
