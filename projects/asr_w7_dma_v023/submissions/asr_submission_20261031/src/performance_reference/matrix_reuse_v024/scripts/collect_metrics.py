#!/usr/bin/env python3
"""Collect the ds_matrix_reuse regression evidence into metrics.json."""
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
LOGS = ROOT / "logs"


def kv(line):
    out = {}
    for k, v in re.findall(r"([A-Za-z_][A-Za-z0-9_]*)=([^\s]+)", line):
        out[k] = v
    return out


def main():
    cmds = []
    for line in (LOGS / "commands.log").read_text().splitlines():
        m = re.match(r"(\S+) rc=(\d+)$", line)
        if m:
            cmds.append({"name": m.group(1), "rc": int(m.group(2))})
    runs = {}
    for c in cmds:
        p = LOGS / (c["name"] + ".log")
        if not p.exists():
            continue
        text = p.read_text(errors="replace")
        entry = {"rc": c["rc"]}
        for line in text.splitlines():
            if line.startswith("PASS ") or line.startswith("PASS_FAULT "):
                parts = line.split()
                tag = parts[0]
                entry["verdict"] = tag
                entry["tb"] = parts[1] if len(parts) > 1 else ""
                entry.update(kv(line))
            elif line.startswith("FAIL"):
                entry.setdefault("fail_lines", []).append(line[:240])
            elif line.startswith("INFO done "):
                entry["done"] = kv(line)
            elif line.startswith("INFO reuse "):
                entry["reuse"] = kv(line)
            elif line.startswith("INFO bfm "):
                entry["bfm"] = kv(line)
            elif line.startswith("INFO store "):
                entry["store"] = kv(line)
            elif line.startswith("INFO hazard "):
                entry["hazard"] = kv(line)
            elif line.startswith("INFO cluster "):
                entry["cluster"] = kv(line)
            elif line.startswith("INFO dma "):
                entry["dma"] = kv(line)
            elif line.startswith("INFO axi "):
                entry["axi"] = kv(line)
            elif line.startswith("INFO drain "):
                entry["drain"] = kv(line)
            elif line.startswith("TIMEOUT"):
                entry["timeout"] = line
        runs[c["name"]] = entry
    failures = [c for c in cmds if c["rc"] != 0]
    bad_verdict = [n for n, e in runs.items()
                   if n.startswith(("run_", "build_")) and "verdict" not in e
                   and not n.startswith("build_")]
    doc = {
        "task": "ds_matrix_reuse",
        "commands_total": len(cmds),
        "commands_nonzero": len(failures),
        "failures": failures,
        "runs_missing_verdict": bad_verdict,
        "runs": runs,
    }
    (LOGS / "metrics.json").write_text(json.dumps(doc, indent=2) + "\n")
    print(json.dumps({k: doc[k] for k in
                      ("commands_total", "commands_nonzero", "failures",
                       "runs_missing_verdict")}, indent=2))
    for name, e in runs.items():
        if e["rc"] == 0 and "verdict" in e:
            print(f"{name:42s} {e['verdict']:14s} "
                  f"cycles={e.get('cycles','-')} "
                  f"rdbytes={e.get('rdbytes','-')} "
                  f"wrbytes={e.get('wrbytes','-')} "
                  f"Wbytes={e.get('Wbytes','-')}")


if __name__ == "__main__":
    main()
