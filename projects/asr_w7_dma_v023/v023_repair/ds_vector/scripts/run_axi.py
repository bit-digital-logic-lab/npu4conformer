#!/usr/bin/env python3
"""Same-load AXI wrapper regression: frozen two DMA cores + baseline vs candidate engine."""
import hashlib, json, re, subprocess, sys
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
SIMROOT=Path("/tmp/opencode/ds_vector")
SIMROOT.parent.mkdir(parents=True,exist_ok=True)
if SIMROOT.is_symlink() and not SIMROOT.exists(): SIMROOT.unlink()
if not SIMROOT.exists(): SIMROOT.symlink_to(ROOT)
if not SIMROOT.exists(): SIMROOT=ROOT
FIX=SIMROOT/"fixtures"/"work_copy"/"add_scalar"
LOGS=ROOT/"logs"/"axi"; LOGS.mkdir(parents=True,exist_ok=True)
BASE=[ROOT/"tb/tb_vector_axi_generic.sv",ROOT/"baseline/tb/axi128_memory_bfm.sv",
      ROOT/"baseline/tb/fma_forbidden_stub.sv",ROOT/"baseline/rtl/ddr_vector_axi.sv",
      ROOT/"baseline/rtl/ddr_vector_engine.sv",ROOT/"baseline/rtl/asr_fp32_alu.sv",
      ROOT/"baseline/rtl/axi_dma_v019.sv"]
PIPE=[ROOT/"tb/tb_vector_axi_generic.sv",ROOT/"baseline/tb/axi128_memory_bfm.sv",
      ROOT/"baseline/tb/fma_forbidden_stub.sv",ROOT/"candidate/rtl/ddr_vector_axi_pipe.sv",
      ROOT/"candidate/rtl/ddr_vector_engine_pipe.sv",ROOT/"candidate/rtl/asr_fp32_lane_fixed.sv",
      ROOT/"candidate/rtl/vector_desc_check_pipe.sv",ROOT/"baseline/rtl/asr_fp32_alu.sv",
      ROOT/"baseline/rtl/axi_dma_v019.sv"]

def compile_one(name,src,macro):
    exe=Path("/tmp")/f"v023_axi_{name}.vvp"
    cmd=["iverilog","-g2012","-D",f"DUT_AXI={macro}","-o",str(exe),"-s","tb_vector_axi_generic"]+[str(p) for p in src]
    cp=subprocess.run(cmd,cwd=str(ROOT),capture_output=True,text=True)
    (LOGS/f"compile_{name}.log").write_text(f"$ {' '.join(cmd)}\nrc={cp.returncode}\n{cp.stdout}\n{cp.stderr}\n",encoding="utf-8")
    if cp.returncode: raise RuntimeError(cp.stderr)
    return exe

def read_hex(p):
    vals=[]
    for line in p.read_text().splitlines():
        line=line.split("//")[0].strip()
        if line: vals.append(int(line,16))
    return bytes(vals)

def run(exe,mode,tag,folder=None,nbytes=4004):
    folder = folder or FIX
    cmd=["vvp",str(exe),f"+folder={folder}",f"+nbytes={nbytes}",f"+mode={mode}"]
    cp=subprocess.run(cmd,cwd=str(SIMROOT),capture_output=True,text=True,timeout=300)
    (LOGS/f"{tag}.log").write_text(f"$ {' '.join(cmd)}\nrc={cp.returncode}\n{cp.stdout}\n{cp.stderr}\n",encoding="utf-8")
    line=next((l for l in cp.stdout.splitlines() if l.startswith("V022_VECTOR_AXI_PASS")), "")
    m=re.search(r"cycles=\s*(\d+).*read_compute_overlap=\s*(\d+).*write_compute_overlap=\s*(\d+).*read_requests=\s*(\d+).*write_requests=\s*(\d+)",line)
    return dict(rc=cp.returncode,line=line,folder=folder,
                cycles=int(m.group(1)) if m else None,
                rcov=int(m.group(2)) if m else None,wcov=int(m.group(3)) if m else None,
                rreq=int(m.group(4)) if m else None,wreq=int(m.group(5)) if m else None,
                out=read_hex(folder/"out.hex") if (folder/"out.hex").exists() else b"")

def main():
    b=compile_one("base",BASE,"ddr_vector_axi")
    p=compile_one("pipe",PIPE,"ddr_vector_axi_pipe")
    rows=[];fail=[]
    for mode in range(10):
        rb=run(b,mode,f"base_m{mode}"); rp=run(p,mode,f"pipe_m{mode}")
        ok=rb["rc"]==0 and rp["rc"]==0
        match=None
        if mode==0:
            match=rb["out"][:4004]==rp["out"][:4004]; ok=ok and match
        rows.append(dict(mode=mode,baseline_rc=rb["rc"],candidate_rc=rp["rc"],
                         baseline_cycles=rb["cycles"],candidate_cycles=rp["cycles"],
                         baseline_overlap=(rb["rcov"],rb["wcov"]),
                         candidate_overlap=(rp["rcov"],rp["wcov"]),
                         requests=(rp["rreq"],rp["wreq"]),byte_match=match,ok=ok))
        if not ok: fail.append(mode)
        print("MODE",mode,"PASS" if ok else "FAIL",rb["cycles"],rp["cycles"],
              "match",match,"overlap",(rp["rcov"],rp["wcov"]),flush=True)
    # additional work fixtures through the AXI wrapper
    wmeta=json.loads((FIX.parent/"meta.json").read_text()) if (FIX.parent/"meta.json").exists() else []
    for c in wmeta:
        if c["name"]=="add_scalar":
            continue
        folder=FIX.parent/c["name"]; nb=c["output_bytes"]
        rb=run(b,0,f"base_{c['name']}",folder,nb); rp=run(p,0,f"pipe_{c['name']}",folder,nb)
        ok=rb["rc"]==0 and rp["rc"]==0 and rb["out"][:nb]==rp["out"][:nb]
        rows.append(dict(mode=0,fixture=c["name"],baseline_rc=rb["rc"],candidate_rc=rp["rc"],
                         baseline_cycles=rb["cycles"],candidate_cycles=rp["cycles"],
                         baseline_overlap=(rb["rcov"],rb["wcov"]),
                         candidate_overlap=(rp["rcov"],rp["wcov"]),
                         requests=(rp["rreq"],rp["wreq"]),byte_match=ok,ok=ok))
        if not ok: fail.append(c["name"])
        print("FIXTURE",c["name"],"PASS" if ok else "FAIL",rb["cycles"],rp["cycles"],flush=True)

    sha={}
    for x in BASE+PIPE: sha[str(x.relative_to(ROOT))]=hashlib.sha256(x.read_bytes()).hexdigest()
    res=dict(passed=not fail,failures=fail,
             scope="Actual two axi_dma_v019 + candidate engine + shared-memory AXI BFM; logic simulation, not board DDR timing. Write-side compute overlap may be zero for the faster candidate.",
             tests=rows,source_sha256=sha)
    (ROOT/"axi_result.json").write_text(json.dumps(res,indent=2)+"\n",encoding="utf-8")
    print("V023_VECTOR_AXI_REGRESSION","PASS" if not fail else "FAIL",flush=True)
    return 0 if not fail else 1

if __name__=="__main__": sys.exit(main())
