#!/usr/bin/env python3
"""Small helper: merge a phase into progress.json (keeps prior notes)."""
import json, sys, time
from pathlib import Path
p = Path(__file__).resolve().parents[1] / "progress.json"
d = json.loads(p.read_text()) if p.exists() else {"task": "ds_layout_wide"}
phase, status = sys.argv[1], sys.argv[2]
note = " ".join(sys.argv[3:])
d.setdefault("phases", []).append({"phase": int(phase), "status": status,
                                   "note": note, "time": time.strftime("%Y-%m-%d %H:%M:%S")})
d["phase"] = int(phase); d["status"] = status
p.write_text(json.dumps(d, indent=1) + "\n")
print(f"progress phase {phase}: {status} {note}")
