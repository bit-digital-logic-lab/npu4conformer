#!/usr/bin/env python3
"""Same-load cycle comparison: gemini_stream_round2 vs primary_stream_fix.

Module-level logic simulation only (Icarus Verilog).  No synthesis, no Vivado,
no board, no VNC, no push.  Both DUTs are compiled separately but run with the
same dependency set, the same testbench, the same vectors and the same
plusargs.  Only the stream-engine source differs.

before = gemini_stream_round2
after  = primary_stream_fix
delta  = after - before   (negative means fewer cycles after the fix)
percent= 100 * delta / before
"""
import hashlib
import json
import os
import re
import signal
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
BUILD = ROOT / "build"
LOGS = ROOT / "logs"
VEC = ROOT / "vectors"
BUILD.mkdir(exist_ok=True)
LOGS.mkdir(exist_ok=True)
VEC.mkdir(exist_ok=True)
sys.path.insert(0, str(ROOT / "ref"))
import refmodel as R  # noqa: E402

TB = ROOT / "tb/tb_stream_bench.sv"
PRIMARY_DEP = ROOT / "candidate/primary"
DEPS = [
    PRIMARY_DEP / "epilogue_i48_to_f32.sv",
    PRIMARY_DEP / "epilogue_fma_stage.sv",
    PRIMARY_DEP / "fp32_fma_pipe.sv",
    PRIMARY_DEP / "epilogue_f32_to_i16.sv",
    PRIMARY_DEP / "epilogue_relu.sv",
    PRIMARY_DEP / "epilogue_lane.sv",
]
VARIANTS = {
    "gemini_stream_round2": {
        "engine": ROOT / "candidate/gemini/epilogue_stream_engine_v023.sv",
        "defines": [],
        "packed_tag_contract": "shared a16_tag (a16_tag = p128_valid ? p128_tag : a16_tag)",
    },
    "primary_stream_fix": {
        "engine": ROOT / "candidate/primary/epilogue_stream_engine_v023.sv",
        "defines": ["PRIMARY_FORK"],
        "packed_tag_contract": "independent a16_packed_tag port",
    },
}
CONFIGS = {
    "conv": {"mode": 0, "scale": 0x3F800000, "bias": 0x00000000,
             "desc": "INT48->FP32->INT16 conversion bypass, relu=0"},
    "fma_nontrivial": {"mode": 1, "scale": 0x3F000001, "bias": 0x3F800000,
                       "desc": "non-trivial FMA scale/bias (rounding-discriminating), relu=0"},
}
SCENARIOS = {
    "bp0_no_backpressure": {"bp": 0, "desc": "a16_ready=1, a16_packed_ready=1"},
    "bp1_both_random": {"bp": 1, "desc": "a16_ready and a16_packed_ready driven by independent LFSR bits"},
    "bp5_packed_long_stall": {"bp": 5, "desc": "a16_ready=1; packed ready only in last 32 of every 256 cycles (224-cycle stall)"},
}
LENGTHS = (256, 1024, 4096)
BIAS_ONLY = {
    "length": 256,
    "mode": 1,
    "cfg_scale": 0x3FC00000,   # 1.5
    "cfg_bias": 0x00000000,    # 0.0
    "param_addr": 1,           # bias only
    "param_data": 0x40000000,  # 2.0
    "desc": "bias-only preload: expected scale falls back to cfg 1.5, bias=preloaded 2.0",
}
MAX_CYCLES = 2_000_000
WALL_TIMEOUT = 180


def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def write_progress(stage, status, details=None):
    data = {
        "stage": stage,
        "status": status,
        "timestamp": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
        "details": details or {},
    }
    (ROOT / "progress.json").write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n")
    with (ROOT / "progress_history.jsonl").open("a") as f:
        f.write(json.dumps(data, ensure_ascii=False) + "\n")


def run_cmd(cmd, log_path, timeout):
    log_path = Path(log_path)
    log_path.parent.mkdir(parents=True, exist_ok=True)
    with log_path.open("w") as lf:
        lf.write("CMD: " + " ".join(str(x) for x in cmd) + "\n")
        lf.flush()
        p = subprocess.Popen([str(x) for x in cmd], stdout=lf, stderr=subprocess.STDOUT,
                             start_new_session=True, cwd=str(ROOT))
        try:
            rc = p.wait(timeout=timeout)
        except subprocess.TimeoutExpired:
            lf.write(f"\nWATCHDOG: wall-clock timeout after {timeout}s; killing pgid {p.pid}\n")
            lf.flush()
            try:
                os.killpg(os.getpgid(p.pid), signal.SIGKILL)
            except Exception:
                pass
            p.wait()
            return 124, "WATCHDOG_TIMEOUT"
        lf.flush()
    return rc, log_path.read_text(errors="replace")


def compile_variant(name):
    v = VARIANTS[name]
    exe = BUILD / f"tb_{name}"
    cmd = ["iverilog", "-g2012", "-o", exe]
    for d in v["defines"]:
        cmd += ["-D", d]
    cmd += [TB] + DEPS + [v["engine"]]
    rc, out = run_cmd(cmd, LOGS / f"compile_{name}.log", 120)
    if rc != 0:
        raise RuntimeError(f"compile {name} failed rc={rc}\n{out}")
    return exe


def parse_output(path):
    a16, packed, spill = [], [], []
    if not Path(path).exists():
        return a16, packed, spill
    for line in Path(path).read_text(errors="replace").splitlines():
        p = line.split()
        if not p:
            continue
        if p[0] == "A" and len(p) >= 5:
            a16.append({"cycle": int(p[1]), "data_raw": p[2],
                        "tag_raw": p[3], "last_raw": p[4]})
        elif p[0] == "P" and len(p) >= 5:
            packed.append({"cycle": int(p[1]), "data_raw": p[2],
                           "tag_raw": p[3], "last_raw": p[4]})
        elif p[0] == "S" and len(p) >= 5:
            spill.append({"cycle": int(p[1]), "data_raw": p[2],
                          "tag_raw": p[3], "last_raw": p[4]})
    return a16, packed, spill


def hx_int(tok):
    try:
        return int(tok, 16)
    except (TypeError, ValueError):
        return None


def read_beats(path):
    rows = []
    for line in Path(path).read_text().splitlines():
        p = line.split()
        if len(p) != 6:
            continue
        lanes = [int(x, 16) for x in p[:4]]
        rows.append({"lanes": lanes, "tag": int(p[4], 16), "last": int(p[5])})
    return rows


def expected_stream(beats, mode, scale, bias, relu=0):
    exp_a16 = []
    for row in beats:
        outs = []
        for raw in row["lanes"]:
            sval = raw if raw < (1 << 47) else raw - (1 << 48)
            f = R.i48_to_f32_bits(sval)
            if mode == 0:
                pass
            elif mode == 2:
                f = R.fma_bits(f, scale, 0, ftz=True)
            else:
                f = R.fma_bits(f, scale, bias, ftz=True)
            if relu and (f >> 31) and not R.is_nan(f):
                f = 0
            if relu and R.is_nan(f):
                f = R.FP32_QNAN
            outs.append(R.f32_to_i16(f) & 0xFFFF)
        exp_a16.append({"tag": row["tag"], "last": row["last"], "outs": outs})
    exp_packed = []
    for i in range(0, len(exp_a16), 2):
        first = exp_a16[i]
        if i + 1 < len(exp_a16):
            second = exp_a16[i + 1]
            words = first["outs"] + second["outs"]
            exp_packed.append({"tag": first["tag"], "last": second["last"], "words": words})
        else:
            words = first["outs"] + [0, 0, 0, 0]
            exp_packed.append({"tag": first["tag"], "last": 1, "words": words})
    return exp_a16, exp_packed


def check_stream(a16, packed, spill, exp_a16, exp_packed, n, stats):
    res = {
        "a16_beats": len(a16), "packed_beats": len(packed), "spill_beats": len(spill),
        "expected_a16_beats": n, "expected_packed_beats": (n + 1) // 2,
        "a16_count_mismatch": len(a16) - n,
        "packed_count_mismatch": len(packed) - ((n + 1) // 2),
        "a16_data_mismatch": 0, "packed_data_mismatch": 0,
        "a16_tag_mismatch": 0, "packed_tag_mismatch": 0,
        "a16_last_mismatch": 0, "packed_last_mismatch": 0,
        "stat_c48_beats_in": stats.get("c48stat"),
        "stat_a16_beats_out": stats.get("a16stat"),
        "stat_count_mismatch": (stats.get("c48stat") != n) or (stats.get("a16stat") != n),
        "examples": [], "pass": False,
    }
    for i, got in enumerate(a16[:n]):
        exp = exp_a16[i]
        data = hx_int(got["data_raw"])
        tag = hx_int(got["tag_raw"])
        last = hx_int(got["last_raw"])
        got_words = None if data is None else [(data >> (16 * k)) & 0xFFFF for k in range(4)]
        if got_words != exp["outs"]:
            res["a16_data_mismatch"] += 1
            if len(res["examples"]) < 12:
                res["examples"].append({"kind": "A16_data", "i": i,
                                        "got": got["data_raw"],
                                        "exp": "".join(f"{x:04x}" for x in reversed(exp["outs"]))})
        if tag != exp["tag"]:
            res["a16_tag_mismatch"] += 1
            if len(res["examples"]) < 12:
                res["examples"].append({"kind": "A16_tag", "i": i,
                                        "got": got["tag_raw"], "exp": f"{exp['tag']:04x}"})
        if last != exp["last"]:
            res["a16_last_mismatch"] += 1
    for i, got in enumerate(packed[:(n + 1) // 2]):
        exp = exp_packed[i]
        data = hx_int(got["data_raw"])
        tag = hx_int(got["tag_raw"])
        last = hx_int(got["last_raw"])
        exp_data = 0
        for k, x in enumerate(exp["words"]):
            exp_data |= (x & 0xFFFF) << (16 * k)
        if data != exp_data:
            res["packed_data_mismatch"] += 1
            if len(res["examples"]) < 12:
                res["examples"].append({"kind": "P_data", "i": i,
                                        "got": got["data_raw"], "exp": f"{exp_data:032x}"})
        if tag != exp["tag"]:
            res["packed_tag_mismatch"] += 1
            if len(res["examples"]) < 12:
                res["examples"].append({"kind": "P_tag", "i": i,
                                        "got": got["tag_raw"], "exp": f"{exp['tag']:04x}"})
        if last != exp["last"]:
            res["packed_last_mismatch"] += 1
    res["pass"] = (
        res["a16_count_mismatch"] == 0 and res["packed_count_mismatch"] == 0
        and res["a16_data_mismatch"] == 0 and res["packed_data_mismatch"] == 0
        and res["a16_tag_mismatch"] == 0 and res["packed_tag_mismatch"] == 0
        and res["a16_last_mismatch"] == 0 and res["packed_last_mismatch"] == 0
        and not res["stat_count_mismatch"]
    )
    return res


def parse_milestones(text):
    m = re.search(
        r"MILESTONE FIRST_IN (-?\d+) LAST_A (-?\d+) LAST_P (-?\d+) IDLE (-?\d+) "
        r"IN_FIRES (\d+) A_FIRES (\d+) P_FIRES (\d+)", text)
    if not m:
        return None
    return {
        "first_in": int(m.group(1)), "last_a": int(m.group(2)),
        "last_p": int(m.group(3)), "idle": int(m.group(4)),
        "in_fires": int(m.group(5)), "a_fires": int(m.group(6)),
        "p_fires": int(m.group(7)),
    }


def parse_stats(text):
    m = re.search(
        r"STATS in=(\d+) a16=(\d+) pack=(\d+) spill=(\d+) c48stat=(\d+) "
        r"a16stat=(\d+) spillstat=(\d+) saved=(\d+)", text)
    if not m:
        return {}
    keys = ["in", "a16", "pack", "spill", "c48stat", "a16stat", "spillstat", "saved"]
    return {k: int(v) for k, v in zip(keys, m.groups())}


def cycles_from(ms):
    first = ms["first_in"]
    last_a = ms["last_a"]
    last_p = ms["last_p"]
    idle = ms["idle"]
    return {
        "first_in": first, "last_a": last_a, "last_p": last_p, "idle": idle,
        "t_last_a16": last_a - first,
        "t_last_packed": last_p - first,
        "t_idle": idle - first,
        "drain_tail": idle - max(last_a, last_p),
        "last_p_minus_last_a": last_p - last_a,
    }


def run_one(variant, length, config_name, scenario_name, bias_only=None):
    exe = BUILD / f"tb_{variant}"
    vec = VEC / f"stream_{length}.vec"
    if bias_only:
        tag = f"{variant}_bias_only_{length}"
        mode = bias_only["mode"]
        scale = bias_only["cfg_scale"]
        bias = bias_only["cfg_bias"]
        param_en, param_addr, param_data = 1, bias_only["param_addr"], bias_only["param_data"]
    else:
        tag = f"{variant}_{length}_{config_name}_{scenario_name}"
        cfg = CONFIGS[config_name]
        mode, scale, bias = cfg["mode"], cfg["scale"], cfg["bias"]
        param_en, param_addr, param_data = 0, 0, 0
    out_file = LOGS / f"{tag}.out"
    log_file = LOGS / f"{tag}.log"
    bp = 0 if bias_only else SCENARIOS[scenario_name]["bp"]
    # Icarus plusarg file names cannot carry the UTF-8 project path; pass
    # ROOT-relative ASCII paths and run with cwd=ROOT.
    cmd = [
        exe, f"+VEC_FILE={vec.relative_to(ROOT)}", f"+OUT_FILE={out_file.relative_to(ROOT)}",
        f"+MODE={mode}", "+RELU=0", "+SPILL=0",
        f"+SCALE={scale:08x}", f"+BIAS={bias:08x}",
        f"+BP={bp}", "+ABORT_AT=-1", f"+PARAM_EN={param_en}",
        f"+PARAM_ADDR={param_addr}", f"+PARAM_DATA={param_data:08x}",
        "+CONTROL_PROBE=0", f"+MAX_CYCLES={MAX_CYCLES}",
    ]
    rc, text = run_cmd(cmd, log_file, WALL_TIMEOUT)
    a16, packed, spill = parse_output(out_file)
    beats = read_beats(vec)
    ms = parse_milestones(text)
    stats = parse_stats(text)
    res = {
        "variant": variant, "length": length, "config": "bias_only" if bias_only else config_name,
        "scenario": "bias_only" if bias_only else scenario_name,
        "rc": rc, "log": str(log_file.relative_to(ROOT)),
        "out": str(out_file.relative_to(ROOT)),
        "milestones": ms, "stats": stats,
        "timed_out": rc == 124,
    }
    if rc == 0 and ms is not None:
        res["cycles"] = cycles_from(ms)
    if bias_only:
        exp_a16, exp_packed = expected_stream(beats, mode, bias_only["cfg_scale"],
                                              bias_only["param_data"], relu=0)
    else:
        cfg = CONFIGS[config_name]
        exp_a16, exp_packed = expected_stream(beats, cfg["mode"], cfg["scale"], cfg["bias"], relu=0)
    res["check"] = check_stream(a16, packed, spill, exp_a16, exp_packed, len(beats), stats)
    res["pass"] = bool(rc == 0 and ms is not None and res["check"]["pass"]
                       and ms["in_fires"] == length and ms["a_fires"] == length
                       and ms["p_fires"] == (length + 1) // 2)
    return res


def metric_pair(before, after):
    b = before["cycles"]
    a = after["cycles"]
    out = {}
    for key in ("t_last_a16", "t_last_packed", "t_idle", "drain_tail"):
        bv, av = b[key], a[key]
        delta = av - bv
        out[key] = {
            "before": bv, "after": av, "delta": delta,
            "percent": (100.0 * delta / bv) if bv else None,
            "speedup": (bv / av) if av else None,
        }
    out["absolute"] = {
        "before": {k: b[k] for k in ("first_in", "last_a", "last_p", "idle")},
        "after": {k: a[k] for k in ("first_in", "last_a", "last_p", "idle")},
    }
    return out


def main():
    t0 = time.time()
    write_progress("SETUP", "RUNNING", {"task": "start"})
    vector_meta = json.loads((VEC / "VECTOR_SHA256.json").read_text()) if (VEC / "VECTOR_SHA256.json").exists() else {}
    if not all((VEC / f"stream_{n}.vec").exists() for n in LENGTHS):
        raise SystemExit("vectors missing; run scripts/gen_vectors.py first")
    source_manifest = {}
    for label, v in VARIANTS.items():
        source_manifest[str(v["engine"].relative_to(ROOT))] = sha256(v["engine"])
    for p in DEPS:
        source_manifest[str(p.relative_to(ROOT))] = sha256(p)
    for p in (TB, ROOT / "ref/refmodel.py", ROOT / "scripts/gen_vectors.py",
              ROOT / "scripts/run_bench.py", ROOT / "scripts/make_report.py",
              ROOT / "run_all.sh"):
        if p.exists():
            source_manifest[str(p.relative_to(ROOT))] = sha256(p)
    (ROOT / "SOURCE_SHA256.json").write_text(json.dumps(source_manifest, indent=2) + "\n")
    write_progress("SETUP", "DONE", {"vectors": vector_meta, "sources": len(source_manifest)})

    write_progress("COMPILE", "RUNNING", {"note": "sequential iverilog, no parallel jobs"})
    exes = {}
    for name in VARIANTS:
        exes[name] = compile_variant(name)
    write_progress("COMPILE", "DONE", {n: str(e.relative_to(ROOT)) for n, e in exes.items()})

    results = []
    total = len(LENGTHS) * len(CONFIGS) * len(SCENARIOS)
    write_progress("SIMULATE", "RUNNING", {"total_comparison_sims": total,
                                           "variants_per_case": 2, "max_cycles": MAX_CYCLES})
    idx = 0
    for length in LENGTHS:
        for config_name in CONFIGS:
            for scenario_name in SCENARIOS:
                idx += 1
                before = run_one("gemini_stream_round2", length, config_name, scenario_name)
                after = run_one("primary_stream_fix", length, config_name, scenario_name)
                both_ok = before["pass"] and after["pass"]
                case = {
                    "length": length, "config": config_name, "scenario": scenario_name,
                    "vector": f"vectors/stream_{length}.vec",
                    "before": before, "after": after,
                    "comparison_valid": both_ok,
                }
                if both_ok:
                    case["metrics"] = metric_pair(before, after)
                    case["status"] = "COMPARED_BOTH_CORRECT"
                else:
                    case["metrics"] = None
                    case["status"] = "INVALID_NO_SPEEDUP_CLAIM"
                    case["reason"] = (
                        f"gemini_pass={before['pass']} primary_pass={after['pass']}; "
                        "correctness gate failed, cycles not used for acceleration"
                    )
                results.append(case)
                write_progress("SIMULATE", "RUNNING", {
                    "completed": idx, "total": total,
                    "last_case": f"{length}/{config_name}/{scenario_name}",
                    "status": case["status"],
                })

    # Bias-only preload: expected to fail on gemini (shared param_loaded gate),
    # expected to pass on primary (independent scale_valid/bias_valid).
    bl = BIAS_ONLY["length"]
    bias_before = run_one("gemini_stream_round2", bl, "bias_only", "bias_only", BIAS_ONLY)
    bias_after = run_one("primary_stream_fix", bl, "bias_only", "bias_only", BIAS_ONLY)
    bias_case = {
        "length": bl, "test": "bias_only_param_preload",
        "expected_semantics": "scale falls back to cfg_scale=1.5; preloaded bias=2.0",
        "before": bias_before, "after": bias_after,
        "comparison_valid": False,
        "status": "EXPECTED_NEGATIVE_CONTROL",
        "note": "Old/gemini version writes bias only but sets a shared param_loaded flag, "
                "so uninitialised param_mem[0] is used as scale. Failure is recorded; "
                "its cycles are NOT reported as an acceleration.",
    }
    write_progress("SIMULATE", "DONE", {"comparison_cases": len(results),
                                        "bias_only": bias_case["status"]})

    write_progress("ANALYZE", "RUNNING", {})
    valid = [r for r in results if r["comparison_valid"]]
    invalid = [r for r in results if not r["comparison_valid"]]
    groups = {}
    for r in valid:
        key = f"{r['config']}/{r['scenario']}"
        groups.setdefault(key, []).append(r)
    aggregate = {}
    for key, rows in groups.items():
        aggregate[key] = {}
        for metric in ("t_last_a16", "t_last_packed", "t_idle", "drain_tail"):
            b = sum(x["metrics"][metric]["before"] for x in rows)
            a = sum(x["metrics"][metric]["after"] for x in rows)
            aggregate[key][metric] = {
                "before_sum": b, "after_sum": a, "delta_sum": a - b,
                "percent": (100.0 * (a - b) / b) if b else None,
                "cases": len(rows),
            }
    bias_expected_ok = (not bias_before["pass"]) and bias_after["pass"]
    all_required_ok = (len(invalid) == 0 and len(valid) == total and bias_expected_ok)
    result = {
        "task": "same-load cycle comparison of epilogue_stream_engine_v023",
        "timestamp": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
        "status": "module_pass_system_pending" if all_required_ok else "module_comparison_failed",
        "system_pass": False,
        "scope": "logic simulation only; module-level stream engine; no synthesis/Vivado/board/VNC/push; no full model",
        "direction": {"before": "gemini_stream_round2", "after": "primary_stream_fix",
                      "delta_definition": "after - before (negative = fewer cycles after)",
                      "percent_definition": "100 * delta / before (negative = improvement)"},
        "constants": {
            "lanes_per_beat": 4, "lengths": list(LENGTHS),
            "configs": {k: {kk: vv for kk, vv in v.items()} for k, v in CONFIGS.items()},
            "scenarios": SCENARIOS,
            "dependency_set": "primary_stream_fix/candidate (gemini_fma_round2 SHA); held identical for both DUTs",
            "packed_tag_contract": {k: v["packed_tag_contract"] for k, v in VARIANTS.items()},
            "max_cycles": MAX_CYCLES, "wall_timeout_s": WALL_TIMEOUT,
            "compile": "iverilog -g2012, one variant at a time (no parallel jobs)",
            "correctness_gate": "rc==0 AND milestone present AND A16/packed data, tag, last and counts all exact; any failure => comparison invalid, no speedup claim",
            "param_passing": "PARAM_EN/PARAM_ADDR/PARAM_DATA are actually passed to vvp; bias-only test uses them",
            "reference": "independent ref/refmodel.py (copied read-only from primary_stream_fix)",
        },
        "vectors": vector_meta,
        "source_sha256": source_manifest,
        "cases": results,
        "bias_only": bias_case,
        "aggregate": aggregate,
        "summary": {
            "comparison_cases": len(results),
            "both_correct": len(valid),
            "invalid_no_speedup_claim": len(invalid),
            "bias_only_gemini_pass": bias_before["pass"],
            "bias_only_primary_pass": bias_after["pass"],
            "bias_only_expected_negative_control": bias_expected_ok,
            "required_checks_pass": all_required_ok,
        },
        "elapsed_seconds": round(time.time() - t0, 3),
    }
    (ROOT / "result.json").write_text(json.dumps(result, indent=2, ensure_ascii=False) + "\n")
    write_progress("ANALYZE", "DONE", {"valid": len(valid), "invalid": len(invalid),
                                       "required_checks_pass": all_required_ok})
    print(json.dumps({
        "status": result["status"],
        "cases": len(results), "both_correct": len(valid), "invalid": len(invalid),
        "bias_only": {"gemini_pass": bias_before["pass"], "primary_pass": bias_after["pass"]},
        "elapsed_seconds": result["elapsed_seconds"],
    }, indent=2))
    return 0 if all_required_ok else 1


if __name__ == "__main__":
    sys.exit(main())
