#!/usr/bin/env python3
"""Generate the final result.json from actual fresh run artifacts.

Never writes PASS from an old JSON.  It requires the current RUN_RESULT.json
(all scenarios) and NEGATIVE_CONTROL.json (deliberately broken RTL must fail),
then hashes the frozen reference lock, the unique filelist and the delivered
source/test/scripts.
"""

from __future__ import annotations

import hashlib
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
RESULT = os.path.join(ROOT, "RUN_RESULT.json")
NEG = os.path.join(ROOT, "NEGATIVE_CONTROL.json")
LOCK = os.path.join(ROOT, "REFERENCE_LOCK.json")
OUT = os.path.join(ROOT, "result.json")


def sha(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def main():
    for p in (RESULT, NEG, LOCK):
        if not os.path.exists(p):
            print(f"ERROR: missing {p}; run the suite and negative control first")
            return 1
    with open(RESULT) as f:
        run = json.load(f)
    with open(NEG) as f:
        neg = json.load(f)
    with open(LOCK) as f:
        lock = json.load(f)
    if not run.get("pass"):
        print("ERROR: RUN_RESULT is not PASS")
        return 1
    if not neg.get("pass"):
        print("ERROR: negative control did not reject the broken RTL")
        return 1

    files = {}
    for rel in [
        "filelist_v024.f",
        "INTERFACE.md",
        "REPORT.md",
        "README.md",
        "progress.json",
        "USER_UPDATES.md",
        "REFERENCE_LOCK.json",
        "NEGATIVE_CONTROL.json",
        "RUN_RESULT.json",
        "tb/tb_epilogue_channels.sv",
        "scripts/run_suite.py",
        "scripts/gen_vectors.py",
        "scripts/gold_model.py",
        "scripts/freeze_reference.py",
        "scripts/negative_control.py",
        "scripts/finalize.py",
        "run_all.sh",
        "ref/refmodel.py",
    ]:
        p = os.path.join(ROOT, rel)
        if os.path.exists(p):
            files[rel] = sha(p)
    # Include every RTL file from the unique filelist and every vector.
    with open(os.path.join(ROOT, "filelist_v024.f")) as f:
        for line in f:
            line = line.strip()
            if line and not line.startswith("#"):
                files[line] = sha(os.path.join(ROOT, line))
    for name in sorted(os.listdir(os.path.join(ROOT, "vectors"))):
        if name.endswith((".cmd", ".par", ".json")):
            rel = "vectors/" + name
            files[rel] = sha(os.path.join(ROOT, rel))

    tested = {}
    for c in run.get("cases", []):
        tested[c["name"]] = {
            "rc": c["rc"],
            "pass": c["pass"],
            "beats": c.get("beats"),
            "bp": c.get("bp"),
            "observed": c.get("observed"),
            "expected": c.get("expected"),
            "table": c.get("table"),
            "errors": c.get("errors"),
        }
    out = {
        "task": "ds_epilogue_channels",
        "model": "opencode-go/deepseek-v4.1-flash",
        "rc": 0,
        "pass": True,
        "tool": run.get("tool"),
        "reference_lock": {
            "file": "REFERENCE_LOCK.json",
            "frozen_on": lock.get("frozen_on"),
            "file_count": len(lock.get("files", {})),
            "v023_primary_stream_fix": lock.get("v023_primary_stream_fix"),
        },
        "unique_filelist": "filelist_v024.f",
        "tested": tested,
        "negative_control": {
            "pass": neg.get("pass"),
            "rc": neg.get("rc"),
            "broken_rtl": neg.get("broken_rtl"),
            "unexpectedly_passed": neg.get("unexpectedly_passed"),
        },
        "files": files,
        "not_done": [
            "no synthesis/Vivado/STA; no frequency claim",
            "no board/VNC/push; no whole-model seconds or WER/CER",
            "no AXI/BFM/B-response in this module; completion boundary is the last A16/packed/FP32/spill handshake",
            "no residual add or reassociation; FP32 output is the post-ReLU value for a downstream RNE add",
            "ds_fusion_buffers integration is an INTERFACE contract only; that worker's tree was not edited",
            "only module-level Icarus logic simulation; integration/whole-graph acceptance is separate",
        ],
        "commands": [
            "python3 scripts/gen_vectors.py",
            "python3 scripts/freeze_reference.py --check",
            "python3 scripts/run_suite.py",
            "python3 scripts/negative_control.py",
            "python3 scripts/finalize.py",
            "bash run_all.sh",
        ],
    }
    with open(OUT, "w") as f:
        json.dump(out, f, indent=1, sort_keys=True)
    print(f"wrote {OUT}: {len(files)} files, {len(tested)} cases")
    return 0


if __name__ == "__main__":
    sys.exit(main())
