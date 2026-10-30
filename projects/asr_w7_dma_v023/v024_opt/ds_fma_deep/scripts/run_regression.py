#!/usr/bin/env python3
"""ds_fma_deep regression orchestrator.

- Sequential (-j1) compile and run; every simulation has a wall-clock watchdog.
- Numeric golden is the independent Fraction-based model in
  v023_repair/ds_numeric_adversarial/ref/refmodel.py (read-only, SHA frozen).
- No stored PASS is reused: every suite is re-simulated here and every mismatch
  makes the process exit non-zero.
- Records source SHA-256, what was tested, and what was not.
"""
import hashlib
import json
import os
import re
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
WORK = os.path.dirname(HERE)
ROOT = "/home/yang/Desktop/项目"
REF_DIR = os.path.join(ROOT, "v023_repair", "ds_numeric_adversarial", "ref")
sys.path.insert(0, REF_DIR)
import refmodel as R  # noqa: E402

SIM = os.path.join(WORK, "sim")
LOG = os.path.join(WORK, "logs")
VEC = os.path.join(WORK, "vectors")
CAND = os.path.join(WORK, "candidate")
TESTS = os.path.join(WORK, "tests")

for d in (SIM, LOG, VEC):
    os.makedirs(d, exist_ok=True)

# ---------------------------------------------------------------------------
# Frozen reference metadata.  If any of these change, abort: a moving golden
# would make the result meaningless.
# ---------------------------------------------------------------------------
BASELINE = os.path.join(WORK, "reference", "baseline_4stage_fp32_fma_pipe.sv")
BASELINE_SHA = "1ed8801a4536ad79c385b90033d5dbd76ad58eed04288a7c500a26e0a740ab12"

FROZEN = {
    "refmodel.py": ("/home/yang/Desktop/项目/v023_repair/ds_numeric_adversarial/ref/refmodel.py",
                    "38eb7ed944f05d6ac45ff68b69fbaa4b0b5b895f0eef46fa33e138395ceb64e2"),
    "baseline_4stage_fp32_fma_pipe.sv": (BASELINE, BASELINE_SHA),
    "fma_adversarial_8734.vec": (os.path.join(VEC, "fma_adversarial_8734.vec"),
                                 "5a995d68158bf82714fc79110156d3b6af21c3fb09b2d3f67f51c5ef4961cdd7"),
    "fma_random_gemini_20000.vec": (os.path.join(VEC, "fma_random_gemini_20000.vec"),
                                    "bc6ff4e57d0d1601aef34dfe46b4c1bacb673de82fb9aa6382be7dcd351485f5"),
}
TRUSTED_FMA_SHA = "1ed8801a4536ad79c385b90033d5dbd76ad58eed04288a7c500a26e0a740ab12"
LATENCY = 7


def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as fh:
        for chunk in iter(lambda: fh.read(65536), b""):
            h.update(chunk)
    return h.hexdigest()


def check_frozen():
    out = {}
    ok = True
    for name, (path, want) in FROZEN.items():
        if not os.path.exists(path):
            raise SystemExit(f"FROZEN INPUT MISSING: {path}")
        got = sha256(path)
        out[name] = {"path": path, "sha256": got, "expected": want, "match": got == want}
        if got != want:
            ok = False
    if not ok:
        raise SystemExit("FROZEN REFERENCE/VECTOR SHA MISMATCH — refusing to run")
    return out


def run(cmd, logname, timeout):
    path = os.path.join(LOG, logname)
    with open(path, "w") as fh:
        p = subprocess.Popen(cmd, stdout=fh, stderr=subprocess.STDOUT,
                             cwd=WORK, start_new_session=True)
        try:
            p.communicate(timeout=timeout)
            rc = p.returncode
        except subprocess.TimeoutExpired:
            try:
                os.killpg(os.getpgid(p.pid), 9)
            except Exception:
                p.kill()
            rc = -9
            fh.write(f"\nWATCHDOG: wall-clock timeout after {timeout}s\n")
    with open(path) as fh:
        return rc, fh.read()


def compile_tb(name, sources):
    exe = os.path.join(SIM, name + ".vvp")
    cmd = ["iverilog", "-g2012", "-o", exe] + sources
    rc, out = run(cmd, "compile_%s.log" % name, 180)
    if rc != 0:
        raise RuntimeError(f"compile {name} failed rc={rc}\n{out[-2000:]}")
    return exe


def read_vecs(path, nfields=6):
    rows = []
    with open(path) as fh:
        for line in fh:
            p = line.split()
            if len(p) == nfields:
                rows.append(tuple(int(x, 16) for x in p))
    return rows


def parse_kv(text, key):
    m = re.search(rf"^{key}=(-?\d+)", text, re.M)
    return int(m.group(1)) if m else None


def suite_fma(exe, vec_path, label, bp):
    out_rel = os.path.join("logs", label + "_out.txt")
    logname = label + ".log"
    cmd = ["vvp", exe, "+VEC_FILE=" + os.path.relpath(vec_path, WORK),
           "+OUT_FILE=" + out_rel, "+BP=%d" % bp, "+MAX_CYCLES=5000000"]
    rc, out = run(cmd, logname, 600)

    res = {"label": label, "bp": bp, "rc": rc, "kind": "epilogue_fma_stage",
           "vectors": 0, "mismatches": 0, "tag_errors": 0, "last_errors": 0,
           "stability_errors": parse_kv(out, "STABILITY_ERRORS") or 0,
           "latency_min": None, "latency_max": None, "latency_hist": {},
           "throughput_span": None, "by_mode": {}, "examples": [], "pass": False,
           "watchdog": "WATCHDOG" in out,
           "log": os.path.join(LOG, logname)}
    if rc != 0 or res["watchdog"]:
        res["error"] = out[-1500:]
        return res

    vecs = read_vecs(vec_path, 6)
    outs = []
    with open(os.path.join(WORK, out_rel)) as fh:
        for line in fh:
            p = line.split()
            if len(p) == 5:
                outs.append((int(p[0]), int(p[1]), int(p[2], 16), int(p[3], 16), int(p[4])))
    res["vectors"] = len(vecs)
    if len(outs) != len(vecs):
        res["error"] = f"output count {len(outs)} != input {len(vecs)}"
        return res

    lat_hist = {}
    out_cycles = []
    for i, ((mode, s, b, x, tag, last), (ic, oc, got, otag, olast)) in enumerate(zip(vecs, outs)):
        if mode not in res["by_mode"]:
            res["by_mode"][mode] = {"total": 0, "mismatches": 0, "latency_set": []}
        res["by_mode"][mode]["total"] += 1
        exp = x if mode == 0 else (R.fma_bits(x, s, 0, ftz=True) if mode == 2
                                   else R.fma_bits(x, s, b, ftz=True))
        if got != exp:
            res["mismatches"] += 1
            res["by_mode"][mode]["mismatches"] += 1
            if len(res["examples"]) < 8:
                res["examples"].append({"i": i, "mode": mode, "x": f"{x:08x}",
                                        "s": f"{s:08x}", "b": f"{b:08x}",
                                        "got": f"{got:08x}", "exp": f"{exp:08x}"})
        if otag != tag:
            res["tag_errors"] += 1
        if olast != last:
            res["last_errors"] += 1
        lat = oc - ic
        lat_hist[lat] = lat_hist.get(lat, 0) + 1
        if lat not in res["by_mode"][mode]["latency_set"]:
            res["by_mode"][mode]["latency_set"].append(lat)
        out_cycles.append(oc)

    res["latency_hist"] = {str(k): v for k, v in sorted(lat_hist.items())}
    res["latency_min"] = min(lat_hist)
    res["latency_max"] = max(lat_hist)
    res["throughput_span"] = max(out_cycles) - min(out_cycles) + 1
    res["by_mode"] = {str(k): {"total": v["total"], "mismatches": v["mismatches"],
                               "latency_set": sorted(v["latency_set"])}
                      for k, v in sorted(res["by_mode"].items())}
    # latency is exactly LATENCY and II=1 only when the downstream never
    # stalls (bp=0).  Under random backpressure the elastic pipeline must
    # instead never be *faster* than LATENCY and must still drain every beat.
    if bp == 0:
        lat_ok = (res["latency_min"] == LATENCY and res["latency_max"] == LATENCY)
        ii_ok = (res["throughput_span"] == len(outs))
    else:
        lat_ok = (res["latency_min"] >= LATENCY)
        ii_ok = (res["throughput_span"] >= len(outs))
    res["latency_ok"] = lat_ok
    res["ii1_ok"] = ii_ok
    res["pass"] = (rc == 0 and res["mismatches"] == 0 and res["tag_errors"] == 0
                   and res["last_errors"] == 0 and res["stability_errors"] == 0
                   and lat_ok and ii_ok)
    return res


def suite_asr(exe, vec_path, label):
    out_rel = os.path.join("logs", label + "_out.txt")
    logname = label + ".log"
    cmd = ["vvp", exe, "+VEC_FILE=" + os.path.relpath(vec_path, WORK),
           "+OUT_FILE=" + out_rel, "+MAX_CYCLES=5000000"]
    rc, out = run(cmd, logname, 600)
    res = {"label": label, "rc": rc, "kind": "asr_fma_ip", "vectors": 0,
           "mismatches": 0, "examples": [], "pass": False,
           "watchdog": "WATCHDOG" in out,
           "log": os.path.join(LOG, logname)}
    if rc != 0 or res["watchdog"]:
        res["error"] = out[-1500:]
        return res
    vecs = read_vecs(vec_path, 6)
    outs = []
    with open(os.path.join(WORK, out_rel)) as fh:
        for line in fh:
            p = line.split()
            if len(p) == 2:
                outs.append(int(p[1], 16))
    res["vectors"] = len(vecs)
    if len(outs) != len(vecs):
        res["error"] = f"output count {len(outs)} != input {len(vecs)}"
        return res
    for i, ((mode, s, b, x, tag, last), got) in enumerate(zip(vecs, outs)):
        exp = (R.fma_bits(x, 0x3f800000, 0, ftz=True) if mode == 0 else
               (R.fma_bits(x, s, 0, ftz=True) if mode == 2 else
                R.fma_bits(x, s, b, ftz=True)))
        if got != exp:
            res["mismatches"] += 1
            if len(res["examples"]) < 8:
                res["examples"].append({"i": i, "mode": mode, "got": f"{got:08x}",
                                        "exp": f"{exp:08x}"})
    res["pass"] = (rc == 0 and res["mismatches"] == 0)
    return res


def run_fma_raw(exe, vec_path, label, bp):
    """Run tb_fma and return per-tag outputs (got, tag, last, lat)."""
    out_rel = os.path.join("logs", label + "_out.txt")
    cmd = ["vvp", exe, "+VEC_FILE=" + os.path.relpath(vec_path, WORK),
           "+OUT_FILE=" + out_rel, "+BP=%d" % bp, "+MAX_CYCLES=5000000"]
    rc, out = run(cmd, label + ".log", 600)
    rows = []
    with open(os.path.join(WORK, out_rel)) as fh:
        for line in fh:
            p = line.split()
            if len(p) == 5:
                rows.append((int(p[2], 16), int(p[3], 16), int(p[4]), int(p[1]) - int(p[0])))
    return rc, out, rows


def suite_equiv(exe_base, exe_cand, vec_path, label):
    """Cross-check candidate vs the trusted 4-stage RTL (NOT the golden)."""
    rc_a, out_a, rows_c = run_fma_raw(exe_cand, vec_path, label + "_cand", 0)
    rc_b, out_b, rows_b = run_fma_raw(exe_base, vec_path, label + "_base", 0)
    res = {"label": label, "kind": "equivalence_vs_trusted_4stage",
           "rc": max(rc_a, rc_b), "vectors": len(rows_c),
           "mismatches": 0, "base_latency_min": None, "base_latency_max": None,
           "watchdog": ("WATCHDOG" in out_a) or ("WATCHDOG" in out_b),
           "log": os.path.join(LOG, label + "_cand.log"), "pass": False}
    if rc_a != 0 or rc_b != 0 or res["watchdog"]:
        res["error"] = (out_a[-800:] + "\n---\n" + out_b[-800:])
        return res
    if len(rows_c) != len(rows_b):
        res["error"] = f"row count {len(rows_c)} vs {len(rows_b)}"
        return res
    for i, (a, b) in enumerate(zip(rows_c, rows_b)):
        if a[0] != b[0]:          # data must be identical
            res["mismatches"] += 1
            if len(res.get("examples", [])) < 8:
                res.setdefault("examples", []).append(
                    {"i": i, "cand": f"{a[0]:08x}", "base": f"{b[0]:08x}"})
    lats = [r[3] for r in rows_b]
    if lats:
        res["base_latency_min"] = min(lats)
        res["base_latency_max"] = max(lats)
    res["pass"] = (res["mismatches"] == 0 and not res["watchdog"])
    return res


def suite_simple(exe, label, key_errors, extra_args=None):
    logname = label + ".log"
    cmd = ["vvp", exe] + (extra_args or [])
    rc, out = run(cmd, logname, 300)
    val = parse_kv(out, key_errors)
    res = {"label": label, "rc": rc, "kind": "directed", key_errors: val,
           "watchdog": "WATCHDOG" in out, "log": os.path.join(LOG, logname),
           "pass": (rc == 0 and val == 0 and "WATCHDOG" not in out)}
    if rc != 0 or res["watchdog"] or val != 0:
        res["error"] = out[-1500:]
    return res


def suite_unit(exe, label):
    logname = label + ".log"
    rc, out = run(["vvp", exe], logname, 300)
    res = {"label": label, "rc": rc, "kind": "unit_directed",
           "watchdog": "WATCHDOG" in out,
           "log": os.path.join(LOG, logname), "pass": False}
    m = re.search(r"passes=(\d+), fails=(\d+)", out)
    if m:
        res["passes"] = int(m.group(1))
        res["fails"] = int(m.group(2))
        res["pass"] = (rc == 0 and int(m.group(2)) == 0 and "WATCHDOG" not in out)
    if rc != 0 or "WATCHDOG" in out:
        res["error"] = out[-1500:]
    return res


def main():
    t0 = time.time()
    frozen = check_frozen()

    # regenerate the local random set deterministically (fresh, independent of
    # the gemini 20k file) and verify it has exactly 20000 rows
    gen = os.path.join(HERE, "gen_random_vectors.py")
    run([sys.executable, gen], "gen_random_vectors.log", 120)
    local_vec = os.path.join(VEC, "fma_random_local_20000.vec")
    if not os.path.exists(local_vec):
        raise SystemExit("local random vector generation failed")
    n_local = sum(1 for ln in open(local_vec) if len(ln.split()) == 6)
    if n_local != 20000:
        raise SystemExit(f"local random vector count {n_local} != 20000")

    sources = {
        "tb_fma": [os.path.join(TESTS, "tb_fma.sv"),
                   os.path.join(CAND, "epilogue_fma_stage.sv"),
                   os.path.join(CAND, "fp32_fma_pipe.sv")],
        "tb_asr_fma_ip": [os.path.join(TESTS, "tb_asr_fma_ip.sv"),
                          os.path.join(CAND, "asr_fma_ip.sv"),
                          os.path.join(CAND, "fp32_fma_pipe.sv")],
        "tb_flush_lat": [os.path.join(TESTS, "tb_flush_lat.sv"),
                         os.path.join(CAND, "epilogue_i48_to_f32.sv"),
                         os.path.join(CAND, "epilogue_fma_stage.sv"),
                         os.path.join(CAND, "fp32_fma_pipe.sv"),
                         os.path.join(CAND, "epilogue_f32_to_i16.sv"),
                         os.path.join(CAND, "epilogue_relu.sv"),
                         os.path.join(CAND, "epilogue_lane.sv")],
        "tb_fma_latency": [os.path.join(TESTS, "tb_fma_latency.sv"),
                           os.path.join(CAND, "epilogue_fma_stage.sv"),
                           os.path.join(CAND, "fp32_fma_pipe.sv")],
        "tb_unit": [os.path.join(TESTS, "tb_fp32_fma_pipe.sv"),
                    os.path.join(CAND, "fp32_fma_pipe.sv")],
        "tb_lzc_tree": [os.path.join(TESTS, "tb_lzc_tree.sv"),
                        os.path.join(CAND, "fp32_fma_pipe.sv")],
        "tb_fma_base": [os.path.join(TESTS, "tb_fma.sv"),
                        os.path.join(CAND, "epilogue_fma_stage.sv"),
                        BASELINE],
    }
    exes = {name: compile_tb(name, srcs) for name, srcs in sources.items()}

    suites = {}
    print("[1] 8734 adversarial, BP=0")
    suites["fma_adv_8734_bp0"] = suite_fma(
        exes["tb_fma"], os.path.join(VEC, "fma_adversarial_8734.vec"), "fma_adv_8734_bp0", 0)
    print("[2] 8734 adversarial, BP=1")
    suites["fma_adv_8734_bp1"] = suite_fma(
        exes["tb_fma"], os.path.join(VEC, "fma_adversarial_8734.vec"), "fma_adv_8734_bp1", 1)
    print("[3] 20000 local random, BP=0")
    suites["fma_random_local_20000_bp0"] = suite_fma(
        exes["tb_fma"], local_vec, "fma_random_local_20000_bp0", 0)
    print("[4] 20000 local random, BP=1")
    suites["fma_random_local_20000_bp1"] = suite_fma(
        exes["tb_fma"], local_vec, "fma_random_local_20000_bp1", 1)
    print("[5] 20000 frozen gemini random, BP=0 (cross-check)")
    suites["fma_random_gemini_20000_bp0"] = suite_fma(
        exes["tb_fma"], os.path.join(VEC, "fma_random_gemini_20000.vec"),
        "fma_random_gemini_20000_bp0", 0)
    print("[6] asr_fma_ip wrapper, 8734 adversarial")
    suites["asr_ip_adv_8734"] = suite_asr(
        exes["tb_asr_fma_ip"], os.path.join(VEC, "fma_adversarial_8734.vec"), "asr_ip_adv_8734")
    print("[7] asr_fma_ip wrapper, 20000 local random")
    suites["asr_ip_random_20000"] = suite_asr(
        exes["tb_asr_fma_ip"], local_vec, "asr_ip_random_20000")
    print("[7b] equivalence vs trusted 4-stage RTL (cross-check, not golden)")
    suites["equiv_adv_8734"] = suite_equiv(
        exes["tb_fma_base"], exes["tb_fma"],
        os.path.join(VEC, "fma_adversarial_8734.vec"), "equiv_adv_8734")
    suites["equiv_random_local_20000"] = suite_equiv(
        exes["tb_fma_base"], exes["tb_fma"], local_vec, "equiv_random_local_20000")
    print("[8] flush (7-stage latency adapted)")
    suites["flush_latency_adapted"] = suite_simple(
        exes["tb_flush_lat"], "flush_latency_adapted", "FLUSH_ERRORS")
    print("[9] explicit latency/II/bypass/stall")
    suites["latency_ii_bypass"] = suite_simple(
        exes["tb_fma_latency"], "latency_ii_bypass", "LATENCY_TEST_ERRORS")
    print("[10] directed unit tests")
    suites["unit_directed"] = suite_unit(exes["tb_unit"], "unit_directed")
    print("[11] exhaustive grouped/tree LZC (574k patterns)")
    suites["lzc_tree_exhaustive"] = suite_simple(
        exes["tb_lzc_tree"], "lzc_tree_exhaustive", "LZC_ERRORS")

    all_pass = all(s.get("pass", False) for s in suites.values())

    filelist = []
    for rel in ["run_all_tests.sh",
                "candidate/fp32_fma_pipe.sv",
                "candidate/epilogue_fma_stage.sv",
                "candidate/asr_fma_ip.sv",
                "candidate/epilogue_lane.sv",
                "candidate/epilogue_i48_to_f32.sv",
                "candidate/epilogue_f32_to_i16.sv",
                "candidate/epilogue_relu.sv",
                "candidate/epilogue_stream_engine_v023.sv",
                "tests/tb_fma.sv", "tests/tb_asr_fma_ip.sv",
                "tests/tb_flush_lat.sv", "tests/tb_fma_latency.sv",
                "tests/tb_fp32_fma_pipe.sv", "tests/tb_lzc_tree.sv",
                "scripts/run_regression.py", "scripts/gen_random_vectors.py",
                "reference/baseline_4stage_fp32_fma_pipe.sv",
                "vectors/fma_adversarial_8734.vec",
                "vectors/fma_random_gemini_20000.vec",
                "vectors/fma_random_local_20000.vec",
                "INTERFACE.md", "REPORT.md", "USER_UPDATES.md",
                "progress.json"]:
        if os.path.exists(os.path.join(WORK, rel)):
            filelist.append(rel)
    for rel in ["result.json", "FILELIST.txt"]:
        if rel not in filelist:
            filelist.append(rel)

    cand_sha = {}
    for name in sorted(os.listdir(CAND)):
        if name.endswith(".sv"):
            cand_sha[name] = sha256(os.path.join(CAND, name))

    result = {
        "task": "ds_fma_deep",
        "model": "opencode-go/deepseek-v4.1-flash",
        "timestamp": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
        "scope": "Retime trusted gemini_fma_round2 4-stage/129-bit-acc fp32 FMA into 7 stages, II=1; numeric semantics preserved. Logic simulation only.",
        "prohibitions_adhered": {
            "no_synthesis": True, "no_vivado": True, "no_board": True,
            "no_vnc": True, "no_push": True, "no_external_writes": True,
        },
        "pipeline": {
            "stages": 7, "latency_cycles": LATENCY, "throughput_ii": 1,
            "lzc": "9x16 grouped + tree lzc16/lzc8 (no 129-bit linear priority)",
        },
        "trusted_baseline_fp32_fma_pipe_sha256": TRUSTED_FMA_SHA,
        "candidate_source_sha256": cand_sha,
        "frozen_inputs": frozen,
        "local_random_vectors": {"path": local_vec, "lines": n_local,
                                 "sha256": sha256(local_vec)},
        "suites": suites,
        "overall_pass": all_pass,
        "rc": 0 if all_pass else 1,
        "process_exit_rc": 0 if all_pass else 1,
        "elapsed_seconds": round(time.time() - t0, 2),
        "rerun_command": "./run_all_tests.sh",
        "filelist": filelist,
        "what_was_tested": [
            "7-stage II=1 fp32 FMA vs independent Fraction refmodel.fma_bits: "
            "8734 adversarial BP0/BP1, 20000 local random BP0/BP1, 20000 frozen gemini random BP0",
            "asr_fma_ip AXIS wrapper vs the same independent ref: 8734 + 20000",
            "bit-exact equivalence vs trusted 4-stage gemini_fma_round2 RTL (cross-check, not golden): 8734 + 20000",
            "epilogue mode0 bypass latency=7/II=1, in-flight flush, post-flush epoch, stall freeze",
            "latency-adapted epilogue lane / i48 / fma / i16 flush test",
            "exhaustive grouped/tree 129-bit LZC: 8x16-bit groups x 65535 words + 20000 random 129-bit patterns",
        ],
        "not_tested": [
            "no synthesis/STA/Vivado; no ns or Fmax claim",
            "no board run, no VNC, no push",
            "no whole-model ASR graph / WER",
            "vector FMA op17 integration and per-channel parameter tables are other workers",
        ],
    }
    with open(os.path.join(WORK, "result.json"), "w") as fh:
        json.dump(result, fh, indent=2, ensure_ascii=False)

    # single canonical filelist
    with open(os.path.join(WORK, "FILELIST.txt"), "w") as fh:
        fh.write("# ds_fma_deep unique filelist (generated by scripts/run_regression.py)\n")
        fh.write("# integration payload = candidate/*.sv only; the rest is verification.\n")
        for rel in filelist:
            fh.write(rel + "\n")

    print("\n================ SUMMARY ================")
    for k, v in suites.items():
        extra = ""
        if v.get("kind") == "epilogue_fma_stage":
            extra = (f" mis={v['mismatches']} lat={v.get('latency_min')}.."
                     f"{v.get('latency_max')} span={v.get('throughput_span')}")
        print(f"{k:34s} pass={v.get('pass')} rc={v.get('rc')}{extra}")
    print("OVERALL:", "PASS" if all_pass else "FAIL")
    print("elapsed %.2fs" % result["elapsed_seconds"])
    return 0 if all_pass else 1


if __name__ == "__main__":
    sys.exit(main())
