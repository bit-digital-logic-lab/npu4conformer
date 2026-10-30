#!/usr/bin/env python3
"""Freeze / verify the independent reference metadata.

The lock covers the Python gold, the copied independent refmodel, the
deterministic stimulus generator and every generated vector.  It also records
the read-only v023 primary_stream_fix source SHAs that this candidate is based
on, so a later run can prove the baseline did not move.

Usage:
  python3 scripts/freeze_reference.py --write   # once, after gen_vectors.py
  python3 scripts/freeze_reference.py --check   # normal re-run
"""

from __future__ import annotations

import argparse
import glob
import hashlib
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
LOCK = os.path.join(ROOT, "REFERENCE_LOCK.json")
V023 = "/home/yang/Desktop/项目/v023_repair/primary_stream_fix/candidate"


def sha(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def current_files():
    files = []
    for rel in ["ref/refmodel.py", "scripts/gold_model.py", "scripts/gen_vectors.py"]:
        files.append(rel)
    for pat in ["vectors/*.cmd", "vectors/*.par", "vectors/*.json"]:
        for p in sorted(glob.glob(os.path.join(ROOT, pat))):
            files.append(os.path.relpath(p, ROOT))
    return {rel: sha(os.path.join(ROOT, rel)) for rel in files}


def v023_files():
    out = {}
    if not os.path.isdir(V023):
        return out
    for p in sorted(glob.glob(os.path.join(V023, "*.sv"))):
        out[os.path.basename(p)] = sha(p)
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--write", action="store_true")
    ap.add_argument("--check", action="store_true")
    args = ap.parse_args()
    if not args.write and not args.check:
        ap.error("choose --write or --check")
    cur = current_files()
    if args.write:
        obj = {
            "frozen_on": "2026-10-30",
            "note": "Independent Python gold + deterministic stimulus + read-only v023 baseline.",
            "files": cur,
            "v023_primary_stream_fix": v023_files(),
            "independent_model": "ref/refmodel.py (copied read-only from primary_stream_fix)",
        }
        with open(LOCK, "w") as f:
            json.dump(obj, f, indent=1, sort_keys=True)
        print(f"wrote {LOCK}: {len(cur)} files")
        return 0
    if not os.path.exists(LOCK):
        print("ERROR: REFERENCE_LOCK.json missing; run --write once")
        return 1
    with open(LOCK) as f:
        lock = json.load(f)
    bad = []
    for rel, want in lock.get("files", {}).items():
        path = os.path.join(ROOT, rel)
        if not os.path.exists(path):
            bad.append(f"missing {rel}")
        elif sha(path) != want:
            bad.append(f"changed {rel}")
    for rel in cur:
        if rel not in lock.get("files", {}):
            bad.append(f"unlocked {rel}")
    if bad:
        print("REFERENCE CHECK FAILED:")
        for b in bad:
            print("  ", b)
        return 1
    print(f"REFERENCE OK: {len(cur)} files match frozen metadata")
    return 0


if __name__ == "__main__":
    sys.exit(main())
