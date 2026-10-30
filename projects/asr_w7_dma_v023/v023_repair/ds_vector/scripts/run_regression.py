#!/usr/bin/env python3
"""Same-load baseline vs v023 candidate regression.

Compiles the frozen baseline engine and the candidate with the same generic TB,
runs identical fixtures through both, and compares output bytes.  All logs and
source SHA are stored in this task directory.  Logic simulation only.
"""
import hashlib, json, os, re, subprocess, sys, time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SIMROOT = Path("/tmp/opencode/ds_vector")
SIMROOT.parent.mkdir(parents=True, exist_ok=True)
if SIMROOT.is_symlink() and not SIMROOT.exists():
    SIMROOT.unlink()
if not SIMROOT.exists():
    SIMROOT.symlink_to(ROOT)
if not SIMROOT.exists():
    SIMROOT = ROOT
FIX = SIMROOT / "fixtures" / "regression"
WORKFIX = SIMROOT / "fixtures" / "work_copy"
LOGS = ROOT / "logs" / "regression"
LOGS.mkdir(parents=True, exist_ok=True)

BASE_SRC = [ROOT/"tb/tb_vector_generic.sv", ROOT/"baseline/rtl/ddr_vector_engine.sv",
            ROOT/"baseline/rtl/asr_fp32_alu.sv", ROOT/"baseline/tb/fma_forbidden_stub.sv"]
PIPE_SRC = [ROOT/"tb/tb_vector_generic.sv", ROOT/"candidate/rtl/ddr_vector_engine_pipe.sv",
            ROOT/"candidate/rtl/asr_fp32_lane_fixed.sv",
            ROOT/"candidate/rtl/vector_desc_check_pipe.sv",
            ROOT/"baseline/rtl/asr_fp32_alu.sv", ROOT/"baseline/tb/fma_forbidden_stub.sv"]

def compile_one(name, src, macro, log):
    exe = Path("/tmp") / f"v023_{name}.vvp"
    cmd = ["iverilog", "-g2012", f"-D", f"DUT_MODULE={macro}", "-o", str(exe), "-s", "tb_vector_generic"] + [str(p) for p in src]
    t = time.time()
    cp = subprocess.run(cmd, cwd=str(ROOT), capture_output=True, text=True)
    log.write_text(f"$ {' '.join(cmd)}\nrc={cp.returncode}\n{cp.stdout}\n{cp.stderr}\n", encoding="utf-8")
    if cp.returncode != 0:
        raise RuntimeError(f"compile {name} failed: {cp.stderr}")
    return exe, time.time()-t

def read_hex(p):
    vals = []
    for line in p.read_text().splitlines():
        line = line.split("//")[0].strip()
        if line:
            vals.append(int(line, 16))
    return bytes(vals)

def run(exe, folder, nbytes, mode=0, expect_fault=0, no_dma=0, tag=""):
    cmd = ["vvp", str(exe), f"+folder={folder}", f"+nbytes={nbytes}",
           f"+mode={mode}", f"+expect_fault={expect_fault}", f"+expect_no_dma={no_dma}"]
    t = time.time()
    cp = subprocess.run(cmd, cwd=str(SIMROOT), capture_output=True, text=True, timeout=300)
    (LOGS / f"{folder.name}_{tag}.log").write_text(
        f"$ {' '.join(cmd)}\nrc={cp.returncode}\n{cp.stdout}\n{cp.stderr}\n", encoding="utf-8")
    line = next((l for l in cp.stdout.splitlines() if l.startswith("V023_VECTOR_PASS")), "")
    m = re.search(r"cycles=\s*(\d+).*rcov=\s*(\d+).*wcov=\s*(\d+).*rreq=\s*(\d+).*wreq=\s*(\d+).*count=\s*(\d+)", line)
    got = dict(rc=cp.returncode, pass_line=line, cycles=int(m.group(1)) if m else None,
               rcov=int(m.group(2)) if m else None, wcov=int(m.group(3)) if m else None,
               rreq=int(m.group(4)) if m else None, wreq=int(m.group(5)) if m else None,
               count=int(m.group(6)) if m else None, wall=time.time()-t,
               out=read_hex(folder/"out.hex") if (folder/"out.hex").exists() else None)
    return got

def main():
    (LOGS / "compile").mkdir(exist_ok=True)
    base_exe, ct_b = compile_one("base", BASE_SRC, "ddr_vector_engine", LOGS/"compile/base.log")
    pipe_exe, ct_p = compile_one("pipe", PIPE_SRC, "ddr_vector_engine_pipe", LOGS/"compile/pipe.log")
    meta = json.loads((FIX/"meta.json").read_text())
    rows = []
    failures = []
    for c in meta:
        name, nbytes = c["name"], c["output_bytes"]
        folder = FIX/name
        fault = c.get("expect_fault", 0); nodma = c.get("no_dma", 0)
        b = run(base_exe, folder, nbytes, 0, fault, nodma, "base")
        q = run(pipe_exe, folder, nbytes, 0, fault, nodma, "pipe")
        ok = (b["rc"] == 0 and q["rc"] == 0)
        match = None; gold_match = None
        if ok and not fault:
            bb = b["out"] or b""; qq = q["out"] or b""
            match = bb[:nbytes] == qq[:nbytes]
            if (folder/"gold.hex").exists():
                g = read_hex(folder/"gold.hex")
                gold_match = (g == qq[:nbytes])
            ok = ok and match
        elif ok and fault:
            ok = True
        row = dict(name=name, kind=c.get("kind", "normal"), count=c["count"],
                   output_bytes=nbytes, expect_fault=fault,
                   baseline_cycles=b["cycles"], candidate_cycles=q["cycles"],
                   baseline_rc=b["rc"], candidate_rc=q["rc"],
                   byte_match=match, gold_match=gold_match,
                   baseline_req=(b["rreq"], b["wreq"]), candidate_req=(q["rreq"], q["wreq"]))
        if b["cycles"] and q["cycles"]:
            row["speedup_cycles"] = round(b["cycles"]/q["cycles"], 3)
            row["candidate_cycles_per_element"] = round(q["cycles"]/max(c["count"], 1), 4)
        rows.append(row)
        if not ok:
            failures.append(name)
            print("FAIL", name, b["rc"], q["rc"], b["pass_line"][:80], q["pass_line"][:80], flush=True)
        else:
            print("PASS", name, f"cyc {b['cycles']}->{q['cycles']}", f"match={match}", flush=True)


    # independent work fixtures (frozen V0.22 gold for exact ops)
    wmeta = json.loads((WORKFIX/"meta.json").read_text()) if (WORKFIX/"meta.json").exists() else []
    for c in wmeta:
        name, nbytes = c["name"], c["output_bytes"]
        folder = WORKFIX/name
        b = run(base_exe, folder, nbytes, 0, 0, 0, "work_base")
        q = run(pipe_exe, folder, nbytes, 0, 0, 0, "work_pipe")
        ok = b["rc"] == 0 and q["rc"] == 0 and (b["out"] or b"")[:nbytes] == (q["out"] or b"")[:nbytes]
        gold_ok = None
        if (folder/"gold.hex").exists():
            gold_ok = read_hex(folder/"gold.hex") == (q["out"] or b"")[:nbytes]
        row = dict(name="work_"+name, kind="work_gold", count=c["count"],
                   output_bytes=nbytes, baseline_cycles=b["cycles"], candidate_cycles=q["cycles"],
                   baseline_rc=b["rc"], candidate_rc=q["rc"], byte_match=ok, gold_match=gold_ok)
        if b["cycles"] and q["cycles"]:
            row["speedup_cycles"] = round(b["cycles"]/q["cycles"],3)
            row["candidate_cycles_per_element"] = round(q["cycles"]/max(c["count"],1),4)
        rows.append(row)
        if not ok: failures.append(row["name"])
        print("PASS" if ok else "FAIL", row["name"], b["cycles"], q["cycles"], "gold", gold_ok, flush=True)

    # same normal fixture under extra DMA backpressure / config snapshot / busy-start
    stress = []
    if (WORKFIX/"add_scalar").exists():
        fixture = WORKFIX/"add_scalar"; nbytes = 4004
    else:
        fixture = FIX/"add_1001"; nbytes = 4004
    for mode, tag in [(0,"m0"),(9,"m9"),(10,"m10"),(11,"m11"),(12,"m12"),(13,"m13"),(14,"m14")]:
        b = run(base_exe, fixture, nbytes, mode, 0, 0, f"base_{tag}")
        q = run(pipe_exe, fixture, nbytes, mode, 0, 0, f"pipe_{tag}")
        ok = b["rc"] == 0 and q["rc"] == 0
        match = None
        if ok:
            match = (b["out"] or b"")[:nbytes] == (q["out"] or b"")[:nbytes]
            ok = match
        stress.append(dict(mode=mode, baseline_cycles=b["cycles"], candidate_cycles=q["cycles"],
                           byte_match=match, ok=ok))
        if not ok:
            failures.append(f"stress_mode_{mode}")
        print("STRESS", mode, "PASS" if ok else "FAIL", b["cycles"], q["cycles"], flush=True)

    source_sha = {}
    for p in BASE_SRC + PIPE_SRC:
        source_sha[str(p.relative_to(ROOT))] = hashlib.sha256(p.read_bytes()).hexdigest()
    result = dict(passed=not failures, failures=failures,
                  scope="Actual RTL logic simulation; transactional DMA BFM; NOT board DDR timing, synthesis, or full model.",
                  compile_seconds=dict(baseline=ct_b, candidate=ct_p),
                  tests=rows, stress=stress,
                  counts=dict(regression_cases=len(rows), stress_cases=len(stress),
                              passed_cases=(len(rows)+len(stress))-len(failures)),
                  source_sha256=source_sha)
    (ROOT/"regression_result.json").write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    print("V023_VECTOR_REGRESSION", "PASS" if not failures else "FAIL", len(rows), "cases", flush=True)
    return 0 if not failures else 1

if __name__ == "__main__":
    sys.exit(main())
