"""Exclusive, reversible profile run on the qualified, already loaded 2493 board."""
from datetime import datetime
import hashlib
import json
from pathlib import Path
import re
import subprocess
import sys
import time
from urllib.request import urlopen

import psutil

HERE=Path(__file__).resolve().parent
PS=HERE.parent
BASE=PS.parent
sys.path[:0]=[str(PS),str(BASE/"operator_ui")]
from board_adapter import _board_lock
from verify_receipt import verify
from analyze_profile import compute

X=Path("C:/Academic_Application/Vivado/2025.2/Vivado/bin/xsdb.bat")
DIGEST="c18836aa2255963e5be655b1cf9baebebcb0654348989f3961ad07465e8a4ceb"
GOLD=BASE/"native_host/runs/20261102_220416/1089-134686-0003"


def write(path,data):
    path.write_text(json.dumps(data,ensure_ascii=False,indent=2),encoding="utf-8")


def xsdb(log,script,*args):
    print("XSDB",log,flush=True)
    with log.open("xb") as h:
        done=subprocess.run(["cmd.exe","/d","/c",str(X),str(script),*map(str,args)],cwd=log.parent,
                            stdout=h,stderr=subprocess.STDOUT,stdin=subprocess.DEVNULL,
                            creationflags=subprocess.CREATE_NO_WINDOW)
    text=log.read_text(errors="replace")
    missing=(script.name=="reload_profile.tcl" and "RELOAD_PASS " not in text or
             script.name=="run_xsdb.tcl" and "NATIVE_COMMAND_PASS " not in text)
    if done.returncode or missing:
        raise RuntimeError(f"XSDB exit={done.returncode} log={log}: {text[-1200:]}")


def release_http(run):
    status=json.load(urlopen("http://127.0.0.1:8765/api/status",timeout=5))
    write(run/"http_before.json",status)
    hybrid=status["hybrid"]; sid=hybrid["session_id"]
    if status["app"]!="axu15egb-asr-operator-v024" or status["busy"] or not hybrid["ready"] or not re.fullmatch("[a-f0-9]{32}",sid):
        raise RuntimeError("operator or board not ready and idle")
    listeners={c.pid for c in psutil.net_connections(kind="tcp") if c.status=="LISTEN" and
               c.laddr.ip=="127.0.0.1" and c.laddr.port==8765}
    if len(listeners)!=1:
        raise RuntimeError("unidentified operator listener")
    server=psutil.Process(listeners.pop())
    args=server.cmdline()
    # A server.py relative argument must resolve under the process's own cwd.
    if not any((Path(server.cwd())/a).resolve()==(BASE/"operator_ui/server.py").resolve() for a in args[1:]):
        raise RuntimeError(f"refusing to terminate other application: {server.pid}, {args}")
    control=PS/"resident_runs"/sid
    pid=int((control/"READY").read_text().split()[0])
    if pid!=hybrid["xsdb_pid"]:
        raise RuntimeError("mismatched XSDB session")
    # Request the identified XSDB to disconnect gracefully first; only the
    # verified HTTP Python process is terminated, never the shared hw_server.
    (control/"STOP").touch()
    live=psutil.Process(pid)
    try:
        live.wait(timeout=10)
    except psutil.TimeoutExpired as exc:
        raise RuntimeError("resident XSDB did not acknowledge graceful shutdown") from exc
    server.terminate();server.wait(timeout=10)
    write(run/"http_stopped.json",dict(session_id=sid,xsdb_pid=pid,server_pid=server.pid,shared_hw_server_preserved=True))


def test_set(folder):
    for mode in ("boot","selftest","pltest"):
        if mode!="boot":
            xsdb(folder/(mode+".log"),PS/"run_xsdb.tcl",mode,folder/mode)
        rec=verify(mode,folder/mode)
        write(folder/mode/"verified.json",rec)


def main():
    stamp=datetime.now().strftime("%Y%m%d_%H%M%S")
    p=PS/"runs"/(stamp+"_profile");p.mkdir()
    b=PS/"runs"/(stamp+"_restored");b.mkdir()
    active=BASE/"native_model/ACTIVE_BOARD_WEIGHTS.json"
    proof=json.loads(active.read_text(encoding="utf-8-sig"))
    if proof["runtime_boot"]!="20261102_215234" or not proof["passed"]:
        raise RuntimeError("baseline commissioning identifier changed")
    write(p/"initial_active_weights.json",proof)
    src=GOLD/"raw/board_encoder/encoder_output_f32.bin"
    if hashlib.sha256(src.read_bytes()).hexdigest()!=DIGEST:
        raise RuntimeError("qualified reference hash mismatch")
    previous_cleanup=[]
    if len(sys.argv)==1:
        release_http(p)
    elif len(sys.argv)==3 and sys.argv[1]=="--already-closed":
        previous=Path(sys.argv[2]).resolve()
        if previous.parent!=(PS/"runs").resolve() or not (previous/"http_stopped.json").is_file():
            raise RuntimeError("missing prior operator disconnect")
        if any(c.status=="LISTEN" and c.laddr.port==8765 and c.laddr.ip=="127.0.0.1" for c in psutil.net_connections(kind="tcp")):
            raise RuntimeError("operator HTTP reopened")
        write(p/"http_stopped.json",json.loads((previous/"http_stopped.json").read_text()))
        prior=previous/"boot/reload.log"
        if prior.is_file() and "RELOAD_FAILED phase=executing_cache_cleanup no register match: x0" in prior.read_text():
            previous_cleanup=[prior]
    else:
        raise ValueError("unexpected arguments")
    with _board_lock():
        xsdb(p/"reload.log",HERE/"reload_profile.tcl","profile",p/"boot",*previous_cleanup)
        try:
            test_set(p)
            xsdb(p/"encode.log",PS/"run_xsdb.tcl","encode",p/"encode",GOLD/"features_f32.bin")
            rec=verify("encode",p/"encode")
            write(p/"encode/verified.json",rec)
            xsdb(p/"read_profile.log",HERE/"read_profile.tcl",p/"encode")
            perf=compute(p/"encode")
            got=rec["output_sha256"]
            perf.update(encoder_output_sha256=got,baseline_output_sha256=DIGEST,bit_identical=got==DIGEST)
            write(p/"encode/profile.json",perf)
            if got!=DIGEST:
                raise ValueError("instrumented output does not match baseline")
        finally:
            xsdb(b/"reload.log",HERE/"reload_profile.tcl","baseline",b/"boot")
            test_set(b)
            new=dict(proof,runtime_boot=b.name,weight_full_readback_runtime_boot=proof["runtime_boot"],
                     preserved_across_processor_only_reload=str(b/"boot/reload.log"),
                     previous_profile_reload=str(p/"boot/reload.log"))
            tmp=active.with_suffix(".new");write(tmp,new);tmp.replace(active)
            write(b/"restored.json",new)
    print(json.dumps(dict(profile=str(p), restored=str(b), verified=True)),flush=True)


if __name__=="__main__":
    main()
