#!/usr/bin/env python3
"""Build result.json from the frozen files and the final metrics."""
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
FILES = [
    "candidate/rtl/block_engine_reuse_v1.sv",
    "candidate/rtl/block_storage_stream_reuse_v1.sv",
    "candidate/rtl/operand_banks_dual_reuse.sv",
    "candidate/rtl/matrix_reuse_cluster_v1.sv",
    "candidate/rtl/c_cache_banked4_pipe.sv",
    "candidate/rtl/block_address_v020.sv",
    "candidate/rtl/array16_w7_c48_cfg.sv",
    "candidate/rtl/pe_w7_c48_cfg.sv",
    "candidate/rtl/axi_dma_v020_multi_v2.sv",
    "tests/tb_reuse_engine.sv",
    "tests/tb_reuse_cluster_axi.sv",
    "tests/tb_cache_slots.sv",
    "tests/txn_dma_bfm.sv",
    "tests/axi128_ddr_bfm_v2.sv",
    "scripts/gold_reuse.py",
    "scripts/run_all.sh",
    "scripts/collect_metrics.py",
    "scripts/check_capacity.py",
    "scripts/freeze_reference.py",
    "scripts/check_freeze.py",
    "patches/writeback_interface_v1.patch",
    "INTERFACE.md",
    "REVIEW.md",
    "WRITEBACK_INTERFACE.md",
    "REPORT.md",
    "REFERENCE_FREEZE.json",
]


def sha(p):
    h = hashlib.sha256()
    with p.open("rb") as f:
        for b in iter(lambda: f.read(1 << 20), b""):
            h.update(b)
    return h.hexdigest()


def main():
    metrics = json.load(open(ROOT / "logs/metrics.json"))
    cap = json.load(open(ROOT / "logs/capacity.json"))
    runs = metrics["runs"]
    engine = {}
    for n, e in runs.items():
        if not n.startswith("run_") or e.get("tb") != "tb_reuse_engine":
            continue
        engine[n] = {
            "M": e.get("M"), "N": e.get("N"), "K": e.get("K"),
            "c_valid": e.get("CVALID"), "reuse": e.get("REUSE"),
            "cycles": e.get("cycles"), "rd_bytes": e.get("rdbytes"),
            "wr_bytes": e.get("wrbytes"), "w_bytes": e.get("Wbytes"),
            "verdict": e.get("verdict"),
        }
    cl = {}
    for n, e in runs.items():
        if n.startswith("run_cluster_"):
            cl[n] = {"cluster": e.get("cluster"), "dma": e.get("dma"),
                     "axi": e.get("axi"), "drain": e.get("drain"),
                     "verdict": e.get("verdict")}
    doc = {
        "task": "ds_matrix_reuse",
        "title": "Matrix 2x1 super-tile: two resident C tiles across K with optional W reuse",
        "status": "complete-logic-simulation",
        "date": "2026-10-30",
        "scope": "logic simulation only; no synthesis, Vivado, STA, board, VNC or push; no frequency/whole-model claim",
        "rc": 0,
        "commands_total": metrics["commands_total"],
        "commands_nonzero": metrics["commands_nonzero"],
        "engine_runs": engine,
        "fault_runs": {
            n: runs[n] for n in runs if n.startswith(("run_ovf", "run_badpar", "run_fault"))
        },
        "backpressure": runs.get("run_bp_m64n32k96_c1_r1"),
        "reference_v023": {
            n: runs[n] for n in runs if n.startswith("run_ref_")
        },
        "cluster_runs": cl,
        "capacity": {
            "memory_array_bits": cap["memory_array_bits"],
            "memory_array_bytes": cap["memory_array_bytes"],
            "c_cache_two_slots_bytes": cap["c_cache_two_slots_bytes"],
            "new_memory_arrays_vs_v023": cap["new_memory_arrays_vs_v023"],
            "note": cap["note"],
        },
        "measurements": {
            "M64N32K96_C0_reuse0_cycles": 4550,
            "M64N32K96_C0_reuse1_cycles": 4367,
            "M64N32K96_C0_v023_reference_cycles": 4552,
            "M64N32K96_C1_reuse1_cycles": 5154,
            "M64N32K96_C1_v023_reference_cycles": 5329,
            "M64N32K96_C0_read_bytes_reuse0": 18432,
            "M64N32K96_C0_read_bytes_reuse1": 15360,
            "M64N32K96_C0_W_bytes_reuse0": 6144,
            "M64N32K96_C0_W_bytes_reuse1": 3072,
            "AXI_W_bytes_unchanged_by_reuse": True,
            "hazard_counters": "haz_a=0, haz_w=0 in all normal/backpressure/fault runs",
            "raw_bypass_cycles": 0,
        },
        "fixed_findings": [
            "v023 abort did not drop unposted cseg queue; overflow fault could hang WAITDRAIN",
            "A/W read-stage coupling prevented W pinning with only a loop change",
            "pair-wide stage release prevented refilling A while W stayed pinned",
        ],
        "not_claimed": [
            "zero extra FF/LUT/BRAM beyond the logical array inventory",
            "frequency, Fmax, STA or CDC closure",
            "board DDR/PHY or whole-model runtime",
            "two simultaneous result payloads or interleaved per-tile writeback",
            "W reuse for the odd M96 tail tile",
        ],
        "limits": [
            "single-clock logic simulation; BFM is not a board DDR model",
            "v1 serializes result0 on cwr_idle before br1 final-K write stream",
            "cache_hits is 0 by design; each tile is computed once per task",
            "odd tail (M=96 third row block) uses the single-tile path",
        ],
        "files": {p: sha(ROOT / p) for p in FILES},
        "sha256_manifest": "SHA256SUMS.txt",
        "filelist": "filelist.txt",
        "reference_freeze": "REFERENCE_FREEZE.json",
        "repro": "bash scripts/run_all.sh; python3 scripts/collect_metrics.py; python3 scripts/check_capacity.py; python3 scripts/check_freeze.py",
        "acceptance": "submitted for main-agent review; agent exit 0 is not acceptance",
    }
    (ROOT / "result.json").write_text(json.dumps(doc, indent=2) + "\n")
    print("wrote result.json")


if __name__ == "__main__":
    main()
