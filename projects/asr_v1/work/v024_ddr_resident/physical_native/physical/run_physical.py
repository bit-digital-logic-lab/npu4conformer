import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
from datetime import datetime

root = Path(__file__).resolve().parent
base = root.parent
build, reports, logs = [root / x for x in ("build", "reports", "logs")]
for folder in (build, reports, logs):
    folder.mkdir(exist_ok=True)

def digest(path):
    with path.open("rb") as f:
        return hashlib.file_digest(f, "sha256").hexdigest()

def persist(path, value):
    stage = path.with_suffix(".new")
    stage.write_text(json.dumps(value, indent=2), encoding="utf-8")
    stage.replace(path)

def now():
    return datetime.now().astimezone().isoformat()

resume = sys.argv[1] if len(sys.argv) > 1 else "input"
if resume not in ("input", "optimized", "placed", "physopt", "routed"):
    raise RuntimeError("Unknown checkpoint")
state_path = reports / "state.json"
previous = json.loads(state_path.read_text()) if state_path.exists() else {}
if previous.get("stage") == "PASS":
    raise RuntimeError("Already finished")
script = root / "implement.tcl"
signed = json.loads((base / "reports/resident_join.json").read_text())
input_hash = digest(base / "build/ps_ddr_synth.dcp")
clock_file = base / "build/shell_timing.xdc"
if (signed["stage"] != "SYNTH_SYSTEM_PASS" or signed["system_sha256"] != input_hash
        or signed["inputs"][str(clock_file)] != digest(clock_file)):
    raise RuntimeError("Input receipt mismatch")
prior = previous.get("checkpoints", {})
if resume != "input" and (previous.get("input_sha256") != input_hash
        or prior.get(resume) != digest(build / (resume + ".dcp"))):
    raise RuntimeError("Checkpoint not tied to previous completed stage")
stamp = datetime.now().strftime("%Y%m%d_%H%M%S")
log = logs / (stamp + ".log")
record = dict(stage="STARTING", started=now(), resume=resume, thread_limit=8,
              input_sha256=input_hash, script_sha256=digest(script), clock_sha256=digest(clock_file),
              checkpoints=prior, log=str(log), runner_pid=os.getpid())
lock = root / "run.lock"
with lock.open("x") as f:
    f.write(str(os.getpid()))
try:
    persist(state_path, record)
    cmd = ["cmd.exe", "/d", "/c", "C:/Academic_Application/Vivado/2025.2/Vivado/bin/vivado.bat",
           "-mode", "batch", "-nojournal", "-log", str(log), "-source", str(script), "-tclargs", resume]
    with log.with_suffix(".out").open("x") as out:
        p = subprocess.Popen(cmd, cwd=root, stdout=out, stderr=subprocess.STDOUT, creationflags=subprocess.CREATE_NO_WINDOW)
        record.update(stage="RUNNING", launcher_pid=p.pid)
        persist(state_path, record)
        rc = p.wait()
    lines = log.read_text(errors="replace").splitlines()
    for stage in ("optimized", "placed", "physopt", "routed"):
        if "CHECKPOINT_PASS " + stage in lines:
            prior[stage] = digest(build / (stage + ".dcp"))
    record.update(exit_code=rc, finished=now())
    if rc != 0 or any(s.startswith("ERROR:") for s in lines) or not any(s.startswith("PHYSICAL_2493_PASS ROUTED=") for s in lines):
        raise RuntimeError("Physical run failed; inspect " + str(log))
    bit = build / "candidate_A51A2493.bit"
    record.update(stage="PASS", bit_sha256=digest(bit))
except BaseException as e:
    record.update(stage="FAILED", error=str(e))
    raise
finally:
    persist(state_path, record)
    persist(log.with_suffix(".json"), record)
    lock.unlink(missing_ok=True)
