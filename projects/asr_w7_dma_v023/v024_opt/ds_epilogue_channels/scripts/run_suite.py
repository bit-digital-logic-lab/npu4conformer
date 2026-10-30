#!/usr/bin/env python3
"""Real-RTL regression for the v024 per-column epilogue.

Compiles the RTL testbench once (serial compile, no parallel make), then runs
each scenario under its own wall-clock watchdog.  Every run is compared against
the independent Python gold in scripts/gold_model.py; a single mismatch,
stability error, unexpected parameter acceptance, missing/extra beat, drain
failure or watchdog makes the whole suite exit non-zero.

The runner never reads an old result JSON to decide PASS.  It deletes
RUN_RESULT.json at start and writes a fresh one at the end.
"""

from __future__ import annotations

import json
import os
import re
import signal
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
VEC = os.path.join(ROOT, "vectors")
BUILD = os.path.join(ROOT, "build")
LOGS = os.path.join(ROOT, "logs")
RESULT = os.path.join(ROOT, "RUN_RESULT.json")
sys.path.insert(0, HERE)
import gold_model as G  # noqa: E402

RTL = [
    "rtl/epilogue_i48_to_f32.sv",
    "rtl/epilogue_fma_stage.sv",
    "rtl/epilogue_f32_to_i16.sv",
    "rtl/epilogue_relu.sv",
    "rtl/epilogue_lane.sv",
    "rtl/fp32_fma_pipe.sv",
    "rtl/epilogue_stream_engine_v024.sv",
    "tb/tb_epilogue_channels.sv",
]
TOP = "tb_epilogue_channels"
EXE = os.path.join(BUILD, "tb_epilogue_channels")


def run_cmd(cmd, log_path, timeout, cwd=None):
    with open(log_path, "w") as lf:
        lf.write("CMD: " + " ".join(cmd) + "\n")
        lf.flush()
        p = subprocess.Popen(cmd, stdout=lf, stderr=subprocess.STDOUT,
                             start_new_session=True, cwd=cwd)
        try:
            rc = p.wait(timeout=timeout)
        except subprocess.TimeoutExpired:
            lf.write(f"\nWATCHDOG: wall-clock timeout after {timeout}s; killing pid {p.pid}\n")
            lf.flush()
            try:
                os.killpg(os.getpgid(p.pid), signal.SIGKILL)
            except Exception:
                pass
            p.wait()
            return 124, "WATCHDOG_TIMEOUT"
        lf.flush()
    with open(log_path, "r", errors="replace") as f:
        out = f.read()
    return rc, out


def compile_tb():
    os.makedirs(BUILD, exist_ok=True)
    os.makedirs(LOGS, exist_ok=True)
    cmd = ["iverilog", "-g2012", "-Wall", "-o", EXE] + RTL + ["-s", TOP]
    rc, out = run_cmd(cmd, os.path.join(LOGS, "compile.log"), 180, cwd=ROOT)
    if rc != 0:
        raise RuntimeError(f"compile failed rc={rc}\n{out}")
    return rc


def parse_out(path):
    a16, packed, fp32, spill = [], [], [], []
    with open(path, errors="replace") as f:
        for line in f:
            p = line.split()
            if not p:
                continue
            if p[0] == "A":
                a16.append((int(p[1]), int(p[2], 16), int(p[3], 16), int(p[4])))
            elif p[0] == "P":
                packed.append((int(p[1]), int(p[2], 16), int(p[3], 16), int(p[4])))
            elif p[0] == "F":
                fp32.append((int(p[1]), int(p[2], 16), int(p[3], 16), int(p[4])))
            elif p[0] == "S":
                spill.append((int(p[1]), int(p[2], 16), int(p[3], 16), int(p[4])))
    return {"a16": a16, "packed": packed, "fp32": fp32, "spill": spill}


def parse_kv(out, key):
    m = re.search(rf"{re.escape(key)}=(-?\d+)", out)
    return int(m.group(1)) if m else None


def parse_table(out):
    m = re.search(r"TABLE hits=(\d+) misses=(\d+) align_err=(\d+) rejects=(\d+) saved=(\d+)", out)
    if not m:
        return {}
    return {
        "hits": int(m.group(1)), "misses": int(m.group(2)),
        "align_err": int(m.group(3)), "rejects": int(m.group(4)),
        "saved": int(m.group(5)),
    }


def parse_stats(out):
    m = re.search(r"STATS in=(\d+) a16=(\d+) pack=(\d+) fp32=(\d+) spill=(\d+)", out)
    if not m:
        return {}
    return {
        "in": int(m.group(1)), "a16": int(m.group(2)),
        "pack": int(m.group(3)), "fp32": int(m.group(4)),
        "spill": int(m.group(5)),
    }


def cmp_channel(name, obs, exp, sc, abort, abort_cycle, epoch_of_tag,
                require_post=True):
    """Compare observed (cycle,data,tag,last) against expected tag->(data,last)."""
    errs = []
    seen = set()
    for cycle, data, tag, last in obs:
        if tag in seen:
            errs.append(f"{name}: duplicate tag {tag:04x}")
            continue
        seen.add(tag)
        if tag not in exp:
            errs.append(f"{name}: unexpected tag {tag:04x} cycle={cycle}")
            continue
        ev = exp[tag]
        if len(ev) == 2:
            edata, elast = ev
        else:
            edata, etag, elast = ev
            if etag != tag:
                errs.append(f"{name}: tag {tag:04x} expected tag field {etag:04x}")
        if data != edata:
            errs.append(f"{name}: tag {tag:04x} data got={data:x} exp={edata:x}")
        if last != elast:
            errs.append(f"{name}: tag {tag:04x} last got={last} exp={elast}")
        if abort and abort_cycle is not None and abort_cycle >= 0 and cycle > abort_cycle:
            if epoch_of_tag.get(tag, 0) == 0:
                errs.append(f"{name}: pre-abort tag {tag:04x} appeared after abort cycle {abort_cycle}")
    if not abort:
        missing = sorted(set(exp) - seen)
        if missing:
            errs.append(f"{name}: missing {len(missing)} tags, first={missing[:5]}")
    elif require_post:
        ep1 = {t for t in exp if epoch_of_tag.get(t, 0) == 1}
        missing = sorted(ep1 - seen)
        if missing:
            errs.append(f"{name}: missing {len(missing)} post-abort tags, first={missing[:5]}")
    return errs


def run_case(desc):
    name = desc["name"]
    cmd_file = f"vectors/{name}.cmd"
    par_file = f"vectors/{name}.par"
    out_file = os.path.join(LOGS, name + ".out")
    log_file = os.path.join(LOGS, name + ".log")
    if os.path.exists(out_file):
        os.unlink(out_file)
    cmd = [EXE, f"+CMD_FILE={cmd_file}", f"+PAR_FILE={par_file}",
           f"+OUT_FILE={os.path.relpath(out_file, ROOT)}",
           f"+BP={desc.get('bp', 0)}", "+MAX_CYCLES=2000000"]
    t0 = time.time()
    rc, out = run_cmd(cmd, log_file, 180, cwd=ROOT)
    dt = time.time() - t0
    res = {
        "name": name, "rc": rc, "seconds": round(dt, 3),
        "errors": [], "pass": False,
        "beats": desc.get("beats"), "bp": desc.get("bp"),
    }
    if rc != 0:
        res["errors"].append(f"simulation rc={rc}")
        res["log_tail"] = out[-2500:]
        return res
    if "DRAINED" not in out:
        res["errors"].append("no DRAINED marker")
    if "DRAIN_FAIL" in out:
        res["errors"].append("DRAIN_FAIL")
    if "WATCHDOG" in out:
        res["errors"].append("cycle watchdog fired")
    stab = parse_kv(out, "STABILITY_ERRORS")
    perr = parse_kv(out, "PARAM_ERRORS")
    abort_cycle = parse_kv(out, "ABORT_CYCLE")
    if stab is None:
        res["errors"].append("missing STABILITY_ERRORS")
    elif stab != 0:
        res["errors"].append(f"stability errors={stab}")
    if perr is None:
        res["errors"].append("missing PARAM_ERRORS")
    elif perr != 0:
        res["errors"].append(f"parameter handshake errors={perr}")

    obs = parse_out(out_file)
    exp = G.expected(desc)
    abort = any(e["op"] == "ABORT" for e in desc["events"])
    res["observed"] = {k: len(v) for k, v in obs.items()}
    res["expected"] = {k: len(v) for k, v in exp.items() if k != "epoch_of_tag" and k != "epochs"}

    all_errs = []
    all_errs += cmp_channel("a16", obs["a16"], exp["a16"], desc, abort,
                            abort_cycle, exp["epoch_of_tag"])
    all_errs += cmp_channel("packed", obs["packed"], exp["packed"], desc, abort,
                            abort_cycle, exp["epoch_of_tag"])
    all_errs += cmp_channel("fp32", obs["fp32"], exp["fp32"], desc, abort,
                            abort_cycle, exp["epoch_of_tag"])
    all_errs += cmp_channel("spill", obs["spill"], exp["spill"], desc, abort,
                            abort_cycle, exp["epoch_of_tag"])

    stats = parse_stats(out)
    res["tb_stats"] = stats
    if stats:
        for ch, key in (("a16", "a16"), ("packed", "pack"),
                        ("fp32", "fp32"), ("spill", "spill")):
            if stats.get(key) != len(obs[ch]):
                all_errs.append(f"{ch}: TB stat {stats.get(key)} != log count {len(obs[ch])}")

    table = parse_table(out)
    res["table"] = table
    if table:
        if table["align_err"] != 0:
            all_errs.append(f"column alignment errors={table['align_err']}")
        if table["hits"] < desc.get("expect_table_hits_min", 0):
            all_errs.append(
                f"table hits {table['hits']} < expected {desc.get('expect_table_hits_min')}")
        if table["misses"] < desc.get("expect_table_misses_min", 0):
            all_errs.append(
                f"table misses {table['misses']} < expected {desc.get('expect_table_misses_min')}")
        if table["rejects"] < desc.get("expect_param_rejects", 0):
            all_errs.append(
                f"param rejects {table['rejects']} < expected {desc.get('expect_param_rejects')}")
    elif desc.get("expect_param_rejects", 0) or desc.get("expect_table_hits_min", 0):
        all_errs.append("missing TABLE telemetry")

    res["errors"] = all_errs[:60]
    res["pass"] = not all_errs
    return res


def main():
    if os.path.exists(RESULT):
        os.unlink(RESULT)
    if not os.path.isdir(VEC) or not os.path.exists(os.path.join(VEC, "manifest.json")):
        print("ERROR: run scripts/gen_vectors.py first")
        return 1
    compile_tb()
    with open(os.path.join(VEC, "manifest.json")) as f:
        manifest = json.load(f)
    results = []
    for item in manifest:
        name = item["name"]
        with open(os.path.join(VEC, name + ".json")) as f:
            desc = json.load(f)
        print(f"RUN {name} ...", flush=True)
        r = run_case(desc)
        results.append(r)
        print(f"  rc={r['rc']} pass={r['pass']} errors={len(r['errors'])}", flush=True)
        for e in r["errors"][:12]:
            print("   !", e, flush=True)
    overall = all(r["pass"] for r in results)
    summary = {
        "pass": overall,
        "cases": results,
        "case_count": len(results),
        "failed": [r["name"] for r in results if not r["pass"]],
        "model": "opencode-go/deepseek-v4.1-flash",
        "tool": "iverilog 14.0 + vvp (logic simulation only)",
    }
    with open(RESULT, "w") as f:
        json.dump(summary, f, indent=1, sort_keys=True)
    print(f"OVERALL pass={overall} cases={len(results)} failed={summary['failed']}")
    return 0 if overall else 1


if __name__ == "__main__":
    sys.exit(main())
