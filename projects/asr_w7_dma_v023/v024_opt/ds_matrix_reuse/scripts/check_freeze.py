#!/usr/bin/env python3
"""Verify REFERENCE_FREEZE.json without regenerating anything."""
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def sha(p):
    h = hashlib.sha256()
    with p.open("rb") as f:
        for b in iter(lambda: f.read(1 << 20), b""):
            h.update(b)
    return h.hexdigest()


def main():
    doc = json.loads((ROOT / "REFERENCE_FREEZE.json").read_text())
    bad = 0
    for rel, e in doc["files"].items():
        p = ROOT / rel
        if not p.exists() or sha(p) != e["sha256"]:
            print(f"FAIL {rel}: missing or SHA changed")
            bad += 1
    for path, e in doc["v023_readonly_reference"].items():
        p = Path(path)
        if not p.exists() or sha(p) != e["sha256"]:
            print(f"FAIL v023 reference {path}")
            bad += 1
    for name, f in doc["fixtures"].items():
        d = ROOT / "fixtures" / name
        if sha(d / "init.hex") != f["sha256_init"] or sha(d / "exp_c.txt") != f["sha256_exp"]:
            print(f"FAIL fixture {name}")
            bad += 1
    if bad:
        raise SystemExit(f"FAIL freeze check: {bad} mismatches")
    print(f"PASS freeze check: {len(doc['files'])} files, "
          f"{len(doc['fixtures'])} fixtures, "
          f"{len(doc['v023_readonly_reference'])} v023 reference files")


if __name__ == "__main__":
    main()
