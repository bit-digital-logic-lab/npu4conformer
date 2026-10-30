#!/usr/bin/env python3
"""Run the unmodified layout testbench against original and candidate RTL.

Both binaries get the same fixture/mode; the canonical PASS line and the
mutated/fault outcome are compared.  Cycle counts are expected to differ
because the candidate adds address-pipeline stages.
"""
import json, re, subprocess, sys
from pathlib import Path

HERE = Path(__file__).resolve().parents[1]
FIX = Path("/tmp/opencode/dscc_fixtures")
BIN = {"orig": HERE / "build" / "layout_orig.vvp",
       "cand": HERE / "build" / "layout_cand.vvp"}
LOG = HERE / "logs" / "layout_equiv.log"

cases = json.loads((FIX / "meta.json").read_text())
# Normal fixtures.
runs = [("normal", c["name"], c["output_bytes"], 0) for c in cases]
# Error/ACL/lifecycle modes from the original tb; one small fixture is enough.
runs += [("error", "copy_i16", 2002, m) for m in range(1, 13)]

def run(which, folder, nbytes, mode):
    cmd = [str(BIN[which]), f"+folder={folder}", f"+nbytes={nbytes}", f"+mode={mode}"]
    p = subprocess.run(cmd, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    return p.returncode, p.stdout.strip()

lines = []
fails = 0
for kind, name, nbytes, mode in runs:
    folder = str(FIX / name)
    a = run("orig", folder, nbytes, mode)
    b = run("cand", folder, nbytes, mode)
    ok = a[0] == b[0]
    # Canonical text excludes the cycle count.
    def canon(t):
        for line in t.splitlines():
            if "V022_LAYOUT_AXI_PASS" in line or "FATAL" in line:
                line = re.sub(r"cycles=\s*\d+", "cycles=<lat>", line)
                line = re.sub(r"Time:\s*\d+", "Time:<t>", line)
                return " ".join(line.split())
        return " ".join(t.split())
    ok_text = canon(a[1]) == canon(b[1])
    ok = ok and ok_text
    fails += 0 if ok else 1
    lines.append(f"{'PASS' if ok else 'FAIL'} {kind} {name} mode={mode}")
    lines.append(f"  orig rc={a[0]} {a[1]}")
    lines.append(f"  cand rc={b[0]} {b[1]}")

text = "\n".join(lines) + f"\nSUMMARY runs={len(runs)} fails={fails}\n"
LOG.write_text(text)
print(text)
sys.exit(1 if fails else 0)
