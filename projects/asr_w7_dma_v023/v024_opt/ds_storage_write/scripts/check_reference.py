#!/usr/bin/env python3
"""Freeze/verify the read-only v023 reference and the local fixtures.

Run before every regression.  Exits non-zero on any SHA mismatch, missing
file, or modified local "unmodified copy".
"""
import hashlib
import json
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
V2 = "/home/yang/Desktop/项目/v023_repair/ds_matrix"
META = os.path.join(ROOT, "REFERENCE_SHA256.json")


def sha(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for block in iter(lambda: f.read(1 << 20), b""):
            h.update(block)
    return h.hexdigest()


def main():
    meta = json.load(open(META))
    bad = 0
    for rel, want in meta["v023"].items():
        p = os.path.join(V2, rel)
        if not os.path.isfile(p):
            print(f"MISSING v023 {rel}")
            bad += 1
            continue
        got = sha(p)
        if got != want:
            print(f"SHA MISMATCH v023 {rel}: {got} != {want}")
            bad += 1
    for rel, want in meta["fixtures"].items():
        p = os.path.join(ROOT, rel)
        if not os.path.isfile(p):
            print(f"MISSING fixture {rel}")
            bad += 1
            continue
        got = sha(p)
        if got != want:
            print(f"SHA MISMATCH fixture {rel}: {got} != {want}")
            bad += 1
    for rel, rec in meta["local_unmodified_copies"].items():
        p = os.path.join(ROOT, rel)
        src = rec["source"]
        if not os.path.isfile(p) or not os.path.isfile(src):
            print(f"MISSING copy/source {rel} / {src}")
            bad += 1
            continue
        if sha(p) != rec["sha256"] or sha(src) != rec["source_sha256"]:
            print(f"SHA MISMATCH unmodified copy {rel}")
            bad += 1
    if bad:
        print(f"REFERENCE_CHECK FAIL ({bad})")
        return 1
    print(f"REFERENCE_CHECK PASS v023={len(meta['v023'])} "
          f"fixtures={len(meta['fixtures'])} copies={len(meta['local_unmodified_copies'])}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
