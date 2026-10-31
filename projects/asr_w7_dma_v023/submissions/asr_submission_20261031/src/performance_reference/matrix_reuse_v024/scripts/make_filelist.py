#!/usr/bin/env python3
"""One unique file list + SHA256SUMS for this task directory."""
import hashlib
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
EXCLUDE = {"prompt.txt", "process.json", "runner.py", "worker.log",
           "supervisor.log", "filelist.txt", "SHA256SUMS.txt"}


def sha(p):
    h = hashlib.sha256()
    with p.open("rb") as f:
        for b in iter(lambda: f.read(1 << 20), b""):
            h.update(b)
    return h.hexdigest()


def main():
    files = []
    for p in sorted(ROOT.rglob("*")):
        if not p.is_file():
            continue
        rel = str(p.relative_to(ROOT))
        if rel in EXCLUDE or rel.startswith("."):
            continue
        files.append(rel)
    (ROOT / "filelist.txt").write_text("\n".join(files) + "\n")
    lines = [f"{sha(ROOT / r)}  {r}" for r in files]
    (ROOT / "SHA256SUMS.txt").write_text("\n".join(lines) + "\n")
    print(f"{len(files)} files")


if __name__ == "__main__":
    main()
