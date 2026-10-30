#!/usr/bin/env python3
"""Integrated DIV/SQRT approximation check (ds_vector + gemini_approx).

Compares the approximate wrapper against the frozen exact baseline on identical
fixtures, reports measured relative/ULP error, throughput, and special-case faults.
No claim of whole-model accuracy; only measured vector-level evidence.
"""
import hashlib, json, math, re, struct, subprocess, sys, time
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
LOGS = ROOT / "logs" / "approx"
LOGS.mkdir(parents=True, exist_ok=True)

BASE_SRC = [ROOT/"tb/tb_vector_generic.sv", ROOT/"baseline/rtl/ddr_vector_engine.sv",
            ROOT/"baseline/rtl/asr_fp32_alu.sv", ROOT/"baseline/tb/fma_forbidden_stub.sv"]
APPROX_SRC = [ROOT/"tb/tb_vector_generic.sv", ROOT/"candidate/rtl/ddr_vector_engine_approx.sv",
              ROOT/"candidate/rtl/ddr_vector_engine_pipe.sv",
              ROOT/"candidate/rtl/asr_fp32_lane_fixed.sv",
              ROOT/"candidate/rtl/vector_desc_check_pipe.sv",
              ROOT/"candidate/rtl/gemini_approx/approx_div_sqrt.sv",
              ROOT/"candidate/rtl/gemini_approx/approx_recip_lut.sv",
              ROOT/"candidate/rtl/gemini_approx/approx_rsqrt_lut.sv",
              ROOT/"baseline/rtl/asr_fp32_alu.sv", ROOT/"baseline/tb/fma_forbidden_stub.sv"]

def compile_one(name, src, macro, log):
    exe = Path("/tmp") / f"v023_approx_{name}.vvp"
    cmd = ["iverilog", "-g2012", f"-D", f"DUT_MODULE={macro}", "-o", str(exe),
           "-s", "tb_vector_generic"] + [str(p) for p in src]
    cp = subprocess.run(cmd, cwd=str(ROOT), capture_output=True, text=True)
    log.write_text(f"$ {' '.join(cmd)}\nrc={cp.returncode}\n{cp.stdout}\n{cp.stderr}\n", encoding="utf-8")
    if cp.returncode != 0:
        raise RuntimeError(cp.stderr)
    return exe

def read_hex(p):
    vals = []
    for line in p.read_text().splitlines():
        line = line.split("//")[0].strip()
        if line:
            vals.append(int(line, 16))
    return bytes(vals)

def run(exe, folder, nbytes, mode=0, expect_fault=0, tag=""):
    cmd = ["vvp", str(exe), f"+folder={folder}", f"+nbytes={nbytes}", f"+mode={mode}",
           f"+expect_fault={expect_fault}", "+expect_no_dma=0"]
    cp = subprocess.run(cmd, cwd=str(SIMROOT), capture_output=True, text=True, timeout=300)
    (LOGS / f"{folder.name}_{tag}.log").write_text(
        f"$ {' '.join(cmd)}\nrc={cp.returncode}\n{cp.stdout}\n{cp.stderr}\n", encoding="utf-8")
    line = next((l for l in cp.stdout.splitlines() if l.startswith("V023_VECTOR_PASS")), "")
    m = re.search(r"cycles=\s*(\d+).*count=\s*(\d+).*fault=\s*(\d+).*err=([0-9a-fA-F]+).*flags=([0-9a-fA-F]+)", line)
    return dict(rc=cp.returncode, line=line,
                cycles=int(m.group(1)) if m else None, count=int(m.group(2)) if m else None,
                fault=int(m.group(3)) if m else None, err=m.group(4) if m else None,
                flags=m.group(5) if m else None,
                out=read_hex(folder/"out.hex") if (folder/"out.hex").exists() else b"")

def floats(b):
    return list(struct.unpack("<%df" % (len(b)//4), b[:len(b)//4*4]))

def metrics(exact, approx):
    rel=[]; ulp=[]; exactn=0
    for e,a in zip(exact, approx):
        if not (math.isfinite(e) and math.isfinite(a)):
            continue
        if e == a:
            exactn += 1
        rel.append(abs(a-e)/max(abs(e), 1e-30))
        ie=struct.unpack("<I",struct.pack("<f",e))[0]
        ia=struct.unpack("<I",struct.pack("<f",a))[0]
        ulp.append(abs(ia-ie))
    return dict(max_rel_error=max(rel) if rel else None,
                mean_rel_error=sum(rel)/len(rel) if rel else None,
                max_ulp=max(ulp) if ulp else None,
                median_ulp=sorted(ulp)[len(ulp)//2] if ulp else None,
                exact_match_rate=exactn/max(len(exact),1))

def main():
    (LOGS/"compile").mkdir(exist_ok=True)
    base_exe = compile_one("base", BASE_SRC, "ddr_vector_engine", LOGS/"compile/base.log")
    ap_exe = compile_one("approx", APPROX_SRC, "ddr_vector_engine_approx", LOGS/"compile/approx.log")
    rows=[]; failures=[]
    for name in ("div_1001","sqrt_1001","div_tail7","sqrt_tail7"):
        folder=FIX/name
        b=run(base_exe, folder, 4004, 0, 0, "base")
        a=run(ap_exe, folder, 4004, 0, 0, "approx")
        m=metrics(floats(b["out"]), floats(a["out"])) if b["rc"]==0 and a["rc"]==0 else {}
        row=dict(name=name, baseline_cycles=b["cycles"], approx_cycles=a["cycles"],
                 baseline_rc=b["rc"], approx_rc=a["rc"], approx_flags=a["flags"], **m)
        if b["cycles"] and a["cycles"]:
            row["cycle_speedup"]=round(b["cycles"]/a["cycles"],3)
            row["approx_cycles_per_element"]=round(a["cycles"]/max(a["count"] or 1,1),4)
        rows.append(row)
        if b["rc"] or a["rc"]:
            failures.append(name)
        print("PASS" if not (b["rc"] or a["rc"]) else "FAIL", name, m, flush=True)

    # special cases: both exact and approx must fault, no silent zero
    special=[]
    for name in ("err_div_zero","err_div_0_0","err_sqrt_neg","err_div_inf_inf"):
        folder=FIX/name
        b=run(base_exe, folder, 4, 0, 1, "base")
        a=run(ap_exe, folder, 4, 0, 1, "approx")
        ok=(b["rc"]==0 and a["rc"]==0 and a["fault"]==1)
        special.append(dict(name=name, baseline_rc=b["rc"], approx_rc=a["rc"],
                            approx_fault=a["fault"], approx_err=a["err"], ok=ok))
        if not ok: failures.append(name)
        print("SPECIAL", name, "PASS" if ok else "FAIL", a["line"], flush=True)

    # backpressure consistency on the approximate core
    bp=[]
    for name in ("div_1001","sqrt_1001"):
        folder=FIX/name
        ref=run(ap_exe, folder, 4004, 0, 0, f"{name}_ref")
        for mode in (11,12,13,14):
            x=run(ap_exe, folder, 4004, mode, 0, f"{name}_m{mode}")
            ok=(x["rc"]==0 and x["out"][:4004]==ref["out"][:4004])
            bp.append(dict(name=name, mode=mode, ok=ok, cycles=x["cycles"]))
            if not ok: failures.append(f"{name}_m{mode}")
            print("BP", name, mode, "PASS" if ok else "FAIL", x["cycles"], flush=True)

    sha={}
    for p in APPROX_SRC:
        sha[str(p.relative_to(ROOT))]=hashlib.sha256(p.read_bytes()).hexdigest()
    result=dict(passed=not failures, failures=failures,
                scope="Integrated vector RTL + gemini_approx Tier-1 core; logic simulation only. Error is against exact baseline on the same vectors; no whole-model accuracy gate claimed.",
                tiers=dict(implementation="single measured 4-stage core; TIER/LATENCY/II source parameters are not structural and are not used to claim 2/4/7 tiers",
                           integrated_outstanding_depth=4),
                tests=rows, special=special, backpressure=bp,
                source_sha256=sha)
    (ROOT/"approx_result.json").write_text(json.dumps(result, indent=2)+"\n", encoding="utf-8")
    print("V023_APPROX_INTEGRATION", "PASS" if not failures else "FAIL", flush=True)
    return 0 if not failures else 1

if __name__=="__main__":
    sys.exit(main())
