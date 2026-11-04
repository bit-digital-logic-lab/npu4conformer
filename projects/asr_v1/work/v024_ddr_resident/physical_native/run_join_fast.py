"""Wait for this exact live synthesis, then immediately join shell, core and verified PE array."""
from datetime import datetime
from pathlib import Path
import hashlib
import json
import os
import subprocess
import time

HERE = Path(__file__).resolve().parent
OLD = HERE.parents[1] / "v024_deploy_20261101/recovery_20261102/retained_coeff_physical"
BUILD = HERE / "build"
REPORT = HERE / "reports"
PARENT = REPORT / "parent_20261102_193409_process.json"
SHELL = REPORT / "shell_20261102_193532_process.json"
LEAF = OLD / "build/array16_ooc_clockless.dcp"
SCRIPT = HERE / "join_fast.tcl"
STATE = REPORT / "resident_join.json"
LOCK = REPORT / "resident_join.lock"
VIVADO = "C:/Academic_Application/Vivado/2025.2/Vivado/bin/vivado.bat"


def load(path):
    return json.loads(path.read_text(encoding="utf-8-sig"))


def sha(path):
    with path.open("rb") as f:
        return hashlib.file_digest(f, "sha256").hexdigest()


def need(ok, message):
    if not ok:
        raise RuntimeError(message)


def save(state, **values):
    state.update(values, updated=datetime.now().astimezone().isoformat())
    temp = STATE.with_suffix(".tmp")
    temp.write_text(json.dumps(state,indent=2),encoding="utf-8")
    temp.replace(STATE)


def verify_run(receipt, plan, marker):
    data = load(receipt)
    need(data["status"] == "PROCESS_EXITED" and data["exit_code"] == 0, "failed "+str(receipt))
    need(data["plan_sha256"] == sha(plan), "input plan changed")
    for name, expected in load(plan)["inputs"].items():
        need(sha(Path(name)) == expected, "source changed: "+name)
    log = Path(data["vivado_log"]).read_text(errors="replace")
    need(marker in log.splitlines() and not any(s.startswith("ERROR:") for s in log.splitlines()),"missing pass: "+marker)


def main():
    previous = load(STATE) if STATE.exists() else {}
    if previous.get("stage") == "SYNTH_SYSTEM_PASS":
        need(sha(BUILD/"ps_ddr_synth.dcp") == previous["system_sha256"],"previous system changed")
        return
    with LOCK.open("x") as lock:
        lock.write(str(os.getpid()))
    state = {"stage":"WAIT_FOR_PARENT", "thread_limit":8, "pid":os.getpid()}
    try:
        save(state)
        while True:
            try:
                receipt = load(PARENT)
            except json.JSONDecodeError:
                time.sleep(1)
                continue
            if receipt["status"] == "PROCESS_EXITED":
                break
            need(receipt["status"] == "RUNNING","unexpected parent state")
            time.sleep(3)
        verify_run(PARENT,HERE/"PLAN.json","PARENT_SYNTH_PASS")
        verify_run(SHELL,HERE/"SHELL_PLAN.json","SHELL_SYNTH_PASS ONE_CORE_BB NO_ETH NO_BOARD")
        need("PARAM_END=0x20000000" in (REPORT/"parent_pass.txt").read_text(),"incorrect DDR parameter window")
        need(sha(LEAF) == load(OLD/"reports/READY_FOR_IMPLEMENTATION.json")["leaf_checkpoint_sha256"],"PE checkpoint mismatch")
        pins = {str(p):sha(p) for p in (BUILD/"parent_unlinked.dcp", LEAF, BUILD/"shell_synth.dcp", BUILD/"shell_timing.xdc")}
        core = BUILD/"core_ddr_synth.dcp"
        reuse = (previous.get("inputs") == pins and previous.get("core_sha256")
                 and core.is_file() and sha(core) == previous["core_sha256"])
        stamp=datetime.now().strftime("%Y%m%d_%H%M%S")
        log=HERE/"logs"/("join_"+stamp+".log")
        args=["cmd.exe","/d","/c",VIVADO,"-mode","batch","-nojournal","-log",str(log),"-source",str(SCRIPT)]
        if reuse:
            args += ["-tclargs","reuse_core"]
        save(state,stage="JOIN_RUNNING",inputs=pins,script_sha256=sha(SCRIPT),log=str(log))
        with log.with_suffix(".console.txt").open("x") as out:
            proc=subprocess.Popen(args,cwd=HERE,stdout=out,stderr=subprocess.STDOUT,creationflags=subprocess.CREATE_NO_WINDOW)
            save(state,launcher_pid=proc.pid)
            rc=proc.wait()
        lines=log.read_text(errors="replace").splitlines()
        save(state,exit_code=rc)
        if reuse or "RESIDENT_CORE_LINK_PASS BLACKBOX=0 ARRAY=1 PE=256" in lines:
            save(state,core_sha256=sha(core))
        need(rc == 0 and not any(s.startswith("ERROR:") for s in lines),"Vivado join failed: "+str(log))
        need("JOIN_THREADS_LIMIT=8" in lines and any(s.startswith("RESIDENT_SYSTEM_LINK_PASS BLACKBOX=0 PE=256") for s in lines),
             "missing full-system synthesis marker")
        save(state,stage="SYNTH_SYSTEM_PASS",system_sha256=sha(BUILD/"ps_ddr_synth.dcp"),
             blackboxes=0,pe_count=256,clock_period_ns=20.625,scope="PS DDR, 256 MiB parameter window; synthesized netlist; no PL Ethernet")
    except BaseException as exc:
        save(state,stage="FAILED",error=str(exc))
        raise
    finally:
        LOCK.unlink(missing_ok=True)


if __name__=="__main__":
    main()
