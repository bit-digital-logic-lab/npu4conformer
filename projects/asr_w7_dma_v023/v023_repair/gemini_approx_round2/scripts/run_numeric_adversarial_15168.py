#!/usr/bin/env python3
"""Run independent ds_numeric_adversarial 15,168-vector black-box verification.

All inputs/testbenches/reference models from ds_numeric_adversarial are read-only.
All simulation outputs, logs, executables, and results are written strictly
inside gemini_approx_round2.
Both wall-clock watchdog and cycle watchdogs are enforced.
Compilation is run with -j1.
"""

import os
import sys
import subprocess
import time
from collections import defaultdict, Counter
from decimal import Decimal

MY_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
AUDIT_DIR = "/home/yang/Desktop/项目/v023_repair/ds_numeric_adversarial"
LOGS = os.path.join(MY_DIR, "logs")
os.makedirs(LOGS, exist_ok=True)

# Add audit ref to path for independent reference model
sys.path.insert(0, os.path.join(AUDIT_DIR, "ref"))
import refmodel as R

def run_cmd(cmd, log_path, timeout=300, cwd=None):
    start = time.time()
    with open(log_path, "w") as f:
        try:
            p = subprocess.Popen(cmd, stdout=f, stderr=subprocess.STDOUT, cwd=cwd)
            try:
                p.wait(timeout=timeout)
                rc = p.returncode
            except subprocess.TimeoutExpired:
                p.kill()
                p.wait()
                f.write(f"\nWATCHDOG: wall-clock timeout ({timeout}s) expired!\n")
                return -1, "TIMEOUT", timeout
        except Exception as e:
            f.write(f"\nEXECUTION ERROR: {e}\n")
            return -2, str(e), time.time() - start
    elapsed = time.time() - start
    with open(log_path, "r", errors="replace") as f:
        out = f.read()
    return rc, out, elapsed

def parse_stability(text):
    for line in text.splitlines():
        if "STABILITY_ERRORS=" in line:
            try:
                return int(line.split("STABILITY_ERRORS=")[1].split()[0])
            except Exception:
                return None
    return None

def read_hex_lines(path, expected_tokens):
    out = []
    with open(path, "r") as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            parts = line.split()
            if len(parts) >= expected_tokens:
                out.append(parts[:expected_tokens])
    return out

def expected_special(op, a, b):
    FLAG_INVALID, FLAG_DIV0, FLAG_OVER, FLAG_UNDER, FLAG_APPROX = 1, 2, 4, 8, 0x10
    a_sub, b_sub = R.is_sub(a), R.is_sub(b)
    under = FLAG_UNDER if (a_sub or (op == 0 and b_sub)) else 0
    if a_sub:
        a = (a & 0x80000000)
    if b_sub:
        b = (b & 0x80000000)
    if op == 0:
        if R.is_nan(a) or R.is_nan(b) or (R.is_zero(a) and R.is_zero(b)) or (
                R.is_inf(a) and R.is_inf(b)):
            return R.FP32_QNAN, under | FLAG_INVALID
        if R.is_zero(b):
            return ((R.FP32_NEG_INF if (a >> 31) ^ (b >> 31) else R.FP32_POS_INF),
                    under | (0 if R.is_inf(a) else FLAG_DIV0))
        if R.is_inf(a):
            return ((R.FP32_NEG_INF if (a >> 31) ^ (b >> 31) else R.FP32_POS_INF), under)
        if R.is_zero(a) or R.is_inf(b):
            return ((R.FP32_NEG_ZERO if (a >> 31) ^ (b >> 31) else R.FP32_POS_ZERO), under)
        return None
    if R.is_nan(a) or ((a >> 31) and not R.is_zero(a)):
        return R.FP32_QNAN, under | FLAG_INVALID
    if R.is_zero(a):
        if op == 1:
            return a, under
        # IEEE: 1/sqrt(-0) = -inf
        return ((R.FP32_NEG_INF if (a >> 31) else R.FP32_POS_INF), under | FLAG_DIV0)
    if R.is_inf(a):
        return (R.FP32_POS_INF if op == 1 else R.FP32_POS_ZERO), under
    return None

def test_approx_adversarial(bp=0, has_flush=True):
    exe = os.path.join(LOGS, f"tb_approx_bp{bp}_flush{int(has_flush)}.vvp")
    compile_log = os.path.join(LOGS, f"compile_approx_bp{bp}_flush{int(has_flush)}.log")
    cmd = [
        "iverilog", "-g2012",
        "-Ptb_approx.TIER=1",
        "-s", "tb_approx",
        "-o", exe,
        os.path.join(AUDIT_DIR, "tb/tb_approx.sv"),
        os.path.join(MY_DIR, "candidate/rtl/approx_div_sqrt.sv"),
        os.path.join(MY_DIR, "candidate/rtl/approx_recip_lut.sv"),
        os.path.join(MY_DIR, "candidate/rtl/approx_rsqrt_lut.sv")
    ]
    if has_flush:
        cmd.insert(2, "-DHAS_FLUSH")

    rc, out, dur = run_cmd(cmd, compile_log, 120)
    if rc != 0:
        return {"rc": rc, "error": f"Compilation failed: {out}", "pass": False}

    out_file = os.path.join(LOGS, f"approx_bp{bp}_flush{int(has_flush)}.out")
    sim_log = os.path.join(LOGS, f"approx_bp{bp}_flush{int(has_flush)}.log")
    vec_file = os.path.join(AUDIT_DIR, "vectors/approx.vec")

    rel_out = os.path.relpath(out_file, MY_DIR)
    rel_vec = os.path.relpath(vec_file, MY_DIR)

    sim_cmd = [
        "vvp", exe,
        f"+VEC_FILE={rel_vec}",
        f"+OUT_FILE={rel_out}",
        f"+BP={bp}",
        "+MAX_CYCLES=10000000"
    ]
    rc, out, dur = run_cmd(sim_cmd, sim_log, 300, cwd=MY_DIR)
    res = {
        "rc": rc, "bp": bp, "has_flush": has_flush, "vectors": 0, "special_mismatch": 0,
        "tag_errors": 0, "order_errors": 0, "flags_errors": 0,
        "flag_semantic_errors": 0, "underflow_results": 0, "overflow_results": 0,
        "max_rel_err": {}, "mean_rel_err": {}, "worst_cases_gt_10pct": [],
        "latency": {}, "ii": {}, "stability_errors": parse_stability(out),
        "examples": [], "pass": False
    }
    if rc != 0:
        res["error"] = out[-2000:]
        return res

    vecs = read_hex_lines(vec_file, 4)
    outs = read_hex_lines(out_file, 5)
    res["vectors"] = len(vecs)
    if len(outs) != len(vecs):
        res["error"] = f"output count {len(outs)} != {len(vecs)}"
        return res

    by_tag = {}
    for o in outs:
        in_cyc, out_cyc = int(o[0]), int(o[1])
        result = int(o[2], 16)
        flags = int(o[3], 16)
        tag = int(o[4], 16)
        by_tag[tag] = (in_cyc, out_cyc, result, flags)

    max_rel = defaultdict(lambda: Decimal(0))
    sum_rel = defaultdict(lambda: Decimal(0))
    cnt_rel = defaultdict(int)
    lat = defaultdict(list)
    in_cycles = []
    mism = []
    worst_gt_10pct = []

    for i, v in enumerate(vecs):
        op = int(v[0], 16)
        a = int(v[1], 16)
        b = int(v[2], 16)
        tag = int(v[3], 16)
        if tag not in by_tag:
            res["order_errors"] += 1
            continue
        in_cyc, out_cyc, got, flags = by_tag[tag]
        lat[op].append(out_cyc - in_cyc)
        in_cycles.append(in_cyc)

        exp = expected_special(op, a, b)
        if exp is not None:
            eres, eflags = exp
            if got != eres or (flags & 0xEF) != eflags:
                res["special_mismatch"] += 1
                if len(mism) < 30:
                    mism.append({
                        "i": i, "op": op, "a": v[1], "b": v[2],
                        "got": f"{got:08x}", "exp": f"{eres:08x}",
                        "flags": f"{flags:02x}", "exp_flags": f"{eflags:02x}"
                    })
            continue

        if R.is_nan(got):
            res["special_mismatch"] += 1
            continue

        if op == 0:
            true = R.true_div_decimal(a, b)
        elif op == 1:
            true = R.true_sqrt_decimal(a)
        else:
            true = R.true_rsqrt_decimal(a)

        if R.is_zero(got):
            res["underflow_results"] += 1
            if not (flags & 0x08):
                res["flag_semantic_errors"] += 1
                if len(mism) < 30:
                    mism.append({"i": i, "op": op, "a": v[1], "b": v[2],
                                 "got": f"{got:08x}", "flags": f"{flags:02x}",
                                 "note": "zero result without UNDERFLOW"})
        elif R.is_inf(got):
            res["overflow_results"] += 1
            if not (flags & 0x04):
                res["flag_semantic_errors"] += 1
                if len(mism) < 30:
                    mism.append({"i": i, "op": op, "a": v[1], "b": v[2],
                                 "got": f"{got:08x}", "flags": f"{flags:02x}",
                                 "note": "inf result without OVERFLOW"})
        else:
            err = R.rel_error(got, true)
            if err is not None:
                max_rel[op] = max(max_rel[op], err)
                sum_rel[op] += err
                cnt_rel[op] += 1
                if err > Decimal("0.10"):
                    op_name = ["div", "sqrt", "rsqrt"][op]
                    worst_gt_10pct.append({
                        "op": op_name, "a": v[1], "b": v[2],
                        "got": f"{got:08x}", "flags": f"{flags:02x}",
                        "rel_err": float(err), "true": float(true)
                    })
            if flags != 0x10:
                res["flag_semantic_errors"] += 1
                if len(mism) < 30:
                    mism.append({"i": i, "op": op, "a": v[1], "b": v[2],
                                 "got": f"{got:08x}", "flags": f"{flags:02x}",
                                 "note": "normal result flags != 0x10"})

    res["examples"] = mism
    res["worst_cases_gt_10pct"] = worst_gt_10pct
    for op, name in ((0, "div"), (1, "sqrt"), (2, "rsqrt")):
        if cnt_rel[op]:
            res["max_rel_err"][name] = float(max_rel[op])
            res["mean_rel_err"][name] = float(sum_rel[op] / cnt_rel[op])
        if lat[op]:
            ls = sorted(lat[op])
            res["latency"][name] = {"min": ls[0], "median": ls[len(ls)//2],
                                    "max": ls[-1], "n": len(ls)}
    if len(in_cycles) > 1:
        diffs = [in_cycles[i+1] - in_cycles[i] for i in range(len(in_cycles)-1)]
        c = Counter(diffs)
        res["ii"] = {"min": min(diffs), "max": max(diffs),
                     "common": c.most_common(5)}

    res["pass"] = (
        res["special_mismatch"] == 0 and
        res["tag_errors"] == 0 and
        res["order_errors"] == 0 and
        res["flags_errors"] == 0 and
        res["flag_semantic_errors"] == 0 and
        len(res["worst_cases_gt_10pct"]) == 0 and
        (res["stability_errors"] or 0) == 0
    )
    return res

def test_flush():
    exe = os.path.join(LOGS, "tb_approx_flush.vvp")
    compile_log = os.path.join(LOGS, "compile_approx_flush.log")
    cmd = [
        "iverilog", "-g2012",
        "-s", "tb_approx_flush",
        "-o", exe,
        os.path.join(AUDIT_DIR, "tb/tb_approx_flush.sv"),
        os.path.join(MY_DIR, "candidate/rtl/approx_div_sqrt.sv"),
        os.path.join(MY_DIR, "candidate/rtl/approx_recip_lut.sv"),
        os.path.join(MY_DIR, "candidate/rtl/approx_rsqrt_lut.sv")
    ]
    rc, out, _ = run_cmd(cmd, compile_log, 60)
    if rc != 0:
        return {"rc": rc, "error": f"Flush compilation failed: {out}", "pass": False}
    sim_log = os.path.join(LOGS, "approx_flush.log")
    rc, out, _ = run_cmd(["vvp", exe], sim_log, 60, cwd=MY_DIR)
    errs = None
    for line in out.splitlines():
        if "APPROX_FLUSH_ERRORS=" in line:
            errs = int(line.split("APPROX_FLUSH_ERRORS=")[1].split()[0])
    return {"rc": rc, "flush_errors": errs, "pass": (rc == 0 and errs == 0)}

def main():
    import json
    print("=" * 70)
    print(" Running ds_numeric_adversarial Black-Box Verification (15,168 vectors)")
    print("=" * 70)

    print("\n[1/4] Testing APPROX under BP=0 (full throughput)...")
    res_bp0 = test_approx_adversarial(bp=0, has_flush=True)
    print(f"  Vectors: {res_bp0['vectors']}")
    print(f"  Special mismatches: {res_bp0['special_mismatch']}")
    print(f"  Worst cases >10%: {len(res_bp0['worst_cases_gt_10pct'])}")
    print(f"  Max rel errors: {res_bp0.get('max_rel_err')}")
    print(f"  Mean rel errors: {res_bp0.get('mean_rel_err')}")
    print(f"  Latency: {res_bp0.get('latency')}")
    print(f"  II: {res_bp0.get('ii')}")
    print(f"  Stability errors: {res_bp0.get('stability_errors')}")
    print(f"  Result: {'PASS' if res_bp0['pass'] else 'FAIL'}")

    print("\n[2/4] Testing APPROX under BP=1 (random 50% backpressure)...")
    res_bp1 = test_approx_adversarial(bp=1, has_flush=True)
    print(f"  Vectors: {res_bp1['vectors']}")
    print(f"  Special mismatches: {res_bp1['special_mismatch']}")
    print(f"  Worst cases >10%: {len(res_bp1['worst_cases_gt_10pct'])}")
    print(f"  Stability errors: {res_bp1.get('stability_errors')}")
    print(f"  Result: {'PASS' if res_bp1['pass'] else 'FAIL'}")

    print("\n[3/4] Testing Flush functionality (tb_approx_flush.sv)...")
    res_flush = test_flush()
    print(f"  Flush errors: {res_flush.get('flush_errors')}")
    print(f"  Result: {'PASS' if res_flush['pass'] else 'FAIL'}")

    print("\n[4/4] Testing Integration Contract: Unconnected flush port (HAS_FLUSH=0)...")
    res_unconn = test_approx_adversarial(bp=0, has_flush=False)
    print(f"  Unconnected flush vectors: {res_unconn['vectors']}")
    print(f"  Result: {'PASS' if res_unconn['pass'] else 'FAIL'}")

    overall_pass = res_bp0["pass"] and res_bp1["pass"] and res_flush["pass"] and res_unconn["pass"]
    print("\n" + "=" * 70)
    print(f" OVERALL ADVERSARIAL VERDICT: {'ALL PASS (rc=0)' if overall_pass else 'FAIL (rc=1)'}")
    print("=" * 70)

    summary = {
        "overall_pass": overall_pass,
        "bp0": res_bp0,
        "bp1": res_bp1,
        "flush": res_flush,
        "unconnected_flush": res_unconn
    }
    with open(os.path.join(MY_DIR, "result_adversarial.json"), "w") as f:
        json.dump(summary, f, indent=2)

    sys.exit(0 if overall_pass else 1)

if __name__ == "__main__":
    main()
