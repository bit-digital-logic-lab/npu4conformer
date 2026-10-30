#!/usr/bin/env python3
"""Freeze the reference metadata used by this task (read-only inputs + own model)."""
import hashlib, json, time
from pathlib import Path

HERE = Path(__file__).resolve().parents[1]
P = Path("/home/yang/Desktop/项目")
def sha(p):
    h = hashlib.sha256()
    with open(p, "rb") as f:
        for b in iter(lambda: f.read(1 << 20), b""):
            h.update(b)
    return h.hexdigest()

refs = {
    "frozen_at": time.strftime("%Y-%m-%d %H:%M:%S"),
    "baseline_rtl": {
        "local": "rtl/ddr_layout_engine_baseline_burst.sv",
        "sha256": sha(HERE/"rtl/ddr_layout_engine_baseline_burst.sv"),
        "source": str(P/"v023_repair/ds_layout/rtl/ddr_layout_engine_v023_burst.sv"),
        "source_sha256": sha(P/"v023_repair/ds_layout/rtl/ddr_layout_engine_v023_burst.sv"),
        "selected_by": str(P/"v023_repair/ds_closeout_safety/filelist_safety.f"),
    },
    "read_only_inputs": {
        "v023/ds_layout/REPORT.md": sha(P/"v023_repair/ds_layout/REPORT.md"),
        "v023/ds_layout/INTERFACE.md": sha(P/"v023_repair/ds_layout/INTERFACE.md"),
        "v023/ds_closeout_safety/REPORT.md": sha(P/"v023_repair/ds_closeout_safety/REPORT.md"),
        "v023/ds_closeout_safety/INTERFACE.md": sha(P/"v023_repair/ds_closeout_safety/INTERFACE.md"),
        "v024/REVIEW_DECISIONS.md": sha(P/"v024_opt/REVIEW_DECISIONS.md"),
        "work/rtl/u16_divmod.sv": sha(P/"work/rtl/u16_divmod.sv"),
        "work/rtl/axi_dma_v019.sv": sha(P/"work/rtl/axi_dma_v019.sv"),
        "work/rtl/ddr_layout_axi.sv": sha(P/"work/rtl/ddr_layout_axi.sv"),
        "work/tests/layout_fixtures/meta.json": sha(P/"work/tests/layout_fixtures/meta.json"),
    },
    "own_reference_assets": {
        "scripts/layout_model.py": sha(HERE/"scripts/layout_model.py"),
        "scripts/metrics.py": sha(HERE/"scripts/metrics.py"),
        "scripts/gen_gold_fixtures.py": sha(HERE/"scripts/gen_gold_fixtures.py"),
        "scripts/gen_edge_fixtures.py": sha(HERE/"scripts/gen_edge_fixtures.py"),
        "tests/axi128_memory_bfm.sv": sha(HERE/"tests/axi128_memory_bfm.sv"),
        "tests/ddr_layout_axi_ref.sv": sha(HERE/"tests/ddr_layout_axi_ref.sv"),
        "fixtures/official/meta.json": sha(HERE/"fixtures/official/meta.json"),
        "fixtures/gold/meta.json": sha(HERE/"fixtures/gold/meta.json"),
        "fixtures/edge/meta.json": sha(HERE/"fixtures/edge/meta.json"),
    },
    "candidate": {
        "local": "rtl/ddr_layout_engine_wide.sv",
        "sha256": sha(HERE/"rtl/ddr_layout_engine_wide.sv"),
    },
}
(HERE/"REFERENCE_FREEZE.json").write_text(json.dumps(refs, indent=1) + "\n")
print("frozen", refs["candidate"]["sha256"])
