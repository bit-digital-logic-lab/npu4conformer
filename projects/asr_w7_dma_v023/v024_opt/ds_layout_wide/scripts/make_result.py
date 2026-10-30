#!/usr/bin/env python3
"""Emit result.json from logs/summary.json + frozen hashes.  argv[1] = rc."""
import hashlib, json, sys, time
from pathlib import Path

HERE = Path(__file__).resolve().parents[1]

def sha(p):
    h = hashlib.sha256()
    with open(p, "rb") as f:
        for b in iter(lambda: f.read(1 << 20), b""):
            h.update(b)
    return h.hexdigest()

rc = int(sys.argv[1]) if len(sys.argv) > 1 else 1
summary = json.loads((HERE/"logs"/"summary.json").read_text())
verdict = summary["verdict"]
cand = "rtl/ddr_layout_engine_wide.sv"
base = "rtl/ddr_layout_engine_baseline_burst.sv"
result = {
    "task": "ds_layout_wide",
    "model": "opencode-go/deepseek-v4.1-flash",
    "date": time.strftime("%Y-%m-%d %H:%M:%S"),
    "rc": rc,
    "run_all_log_rc": rc,
    "verdict": verdict,
    "acceptance": "main agent must independently review; agent exit 0 is not acceptance",
    "mode": "logic_simulation_only",
    "constraints": {
        "no_synthesis": True, "no_vivado": True, "no_board": True,
        "no_vnc": True, "no_push": True,
        "compile_serial": True, "watchdog_per_sim": True,
        "independent_gold": "scripts/layout_model.py",
        "baseline_read_only": "v023_repair/ds_layout + ds_closeout_safety",
        "write_scope": "this directory only",
    },
    "candidate": {
        "file": cand, "module": "ddr_layout_engine",
        "sha256": sha(HERE/cand),
        "ports_changed": False,
        "parameters": {"MAX_PREFETCH": 16, "MODE2_PREFETCH": 1, "FASTPATH": 1},
        "fast_counts_internal": ["fast_elements", "fast_beats", "fast_groups"],
    },
    "baseline": {
        "file": base, "module": "ddr_layout_engine",
        "sha256": sha(HERE/base),
        "source": "v023_repair/ds_layout/rtl/ddr_layout_engine_v023_burst.sv",
        "sha256_expected": "4e45a39dcb07daeefc190d383ede885e57718f9a60c9d23eda61c4dae11eb893",
        "also_selected_by": "v023_repair/ds_closeout_safety/filelist_safety.f",
    },
    "metrics_audit": summary.get("metric_audit", {}),
    "tests": {
        "official_normal": 8, "official_error_acl_lifecycle": 12,
        "descriptor_fuzz": 57, "independent_gold": 32,
        "preserved_random": 100, "new_random_short_tail": 52,
        "new_edge_unaligned_4k": 53, "mode2_gate_ab": 45,
        "scalar_fallback_exact_cases": 70,
        "c48_6b_negative_control": "bad fails, fixed passes",
        "checks": summary["checks"],
    },
    "totals": summary["grand_totals"],
    "cycle_ratio_vs_v023": {
        "grand_all_normal_suites": round(summary["grand_totals"]["wide"]["cycles"] /
                                         summary["grand_totals"]["base"]["cycles"], 3),
        "official_copy_mode0": 0.176,
        "official_pack_mode1": 0.693,
        "official_unpack_row_mode3_4b": 0.521,
        "official_mode3_c48_6b": 1.000,
        "official_mode4": 1.000,
        "official_mode2": 1.000,
        "note": "official total 0.963 is dominated by the unchanged mode-2 case0000",
    },
    "evidence": {
        "summary": "logs/summary.json",
        "official_table": "logs/official_table.log",
        "gold_table": "logs/gold_table.log",
        "edge_table": "logs/edge_table.log",
        "random": "logs/random_fuzz.log",
        "fuzz": "logs/layout_fuzz.log",
        "mode2_gate": "logs/mode2_gate.log",
        "scalar": "logs/scalar_fallback.log",
        "c48_negative_control": "logs/c48_negative_control.log",
        "run_all": "logs/run_all.log",
    },
    "filelists": ["filelist_wide.f", "filelist_sim.f"],
    "rerun": "bash scripts/run_all.sh",
    "not_done": [
        "whole 512-dim model / CASE0000 sealed payload not run",
        "no synthesis/STA; no Fmax or board DDR claim",
        "reset-in-flight and multi-outstanding shared-DMA integration not tested here",
        "mode 2 has no beat fast path; its gate does not remove all re-reads",
        "C48 6-byte values always use the scalar path (coverage 0 by design)",
        "whole-project merged top is ds_unified_graph's task, not this one",
    ],
}
(HERE/"result.json").write_text(json.dumps(result, indent=1) + "\n")
print(f"result rc={rc} verdict={verdict} candidate_sha={result['candidate']['sha256']}")
raise SystemExit(0 if rc == 0 and verdict == "PASS_LOCAL_LOGIC" else 1)
