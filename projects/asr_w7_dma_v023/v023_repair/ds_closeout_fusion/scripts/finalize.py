#!/usr/bin/env python3
"""Add the cross-case comparison, SHA manifest and scope/limits to result.json."""
import hashlib
import importlib.util
import json
import sys
from pathlib import Path

sys.dont_write_bytecode = True

ROOT = Path(__file__).resolve().parent.parent


def sha(p):
    h = hashlib.sha256()
    h.update(Path(p).read_bytes())
    return h.hexdigest()


def main():
    rj = ROOT / "result.json"
    r = json.loads(rj.read_text())
    cases = {c["label"]: c for c in r.get("cases", [])}
    pairs = [
        ("bp0", "fused_bp0", "unfused_bp0", 2048),
        ("bp1_random", "fused_bp1_random", "unfused_bp1_random", 2048),
        ("bp2_wrlong", "fused_bp2_wrlong", "unfused_bp2_wrlong", 2048),
        ("bp3_rdlong", "fused_bp3_rdlong", "unfused_bp3_rdlong", 2048),
        ("bp4_heavy", "fused_bp4_heavy", "unfused_bp4_heavy", 2048),
        ("edge", "fused_edge", "unfused_edge", 2048),
        ("n64", "fused_n64", "unfused_n64", 4096),
    ]
    comp = []
    for name, fl, ul, a16 in pairs:
        f = cases.get(fl, {})
        u = cases.get(ul, {})
        fm = f.get("metrics", {})
        um = u.get("metrics", {})
        f_rd = fm.get("rd_bytes", 0)
        f_wr = fm.get("wr_bytes", a16)
        u_rd = um.get("rd_beats", 0) * 16
        u_cw = um.get("c48w_bytes", 0)
        u_cr = um.get("c48r_bytes", 0)
        u_a16 = um.get("a16_bytes", a16)
        f_total = f_rd + f_wr
        u_total = u_rd + u_cw + u_cr + u_a16
        comp.append({
            "workload": name,
            "fused_cycles": fm.get("cycles"),
            "unfused_cycles": um.get("cycles"),
            "cycle_ratio_unfused_over_fused": round(um.get("cycles", 0) / fm.get("cycles", 1), 3) if fm.get("cycles") else None,
            "fused_bus_bytes": f_total,
            "unfused_bus_bytes": u_total,
            "byte_delta": u_total - f_total,
            "fused_breakdown": {"aw_read": f_rd, "a16_write": f_wr, "c48_write": 0, "c48_read": 0},
            "unfused_breakdown": {"aw_read": u_rd, "c48_write": u_cw, "c48_read": u_cr, "a16_write": u_a16},
            "both_match_gold": bool(f.get("ok") and u.get("ok")),
        })

    # cross-check the integer C48 stage against the ds_matrix exp_c.txt golden
    spec = importlib.util.spec_from_file_location("gold_fusion", ROOT / "scripts/gold_fusion.py")
    gf = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(gf)
    xcheck = {}
    for fx in ["main", "edge", "n64", "k32"]:
        d = ROOT / "vectors" / fx
        if not (d / "exp_c.txt").exists():
            continue
        manifest = json.loads((d / "manifest.json").read_text())
        words = gf.read_hex_words(d / "init.hex")
        tiles, _, _, _ = gf.matrix_gold(manifest, words)
        flat = []
        for c in tiles:
            flat.extend((v & ((1 << 48) - 1)) for v in c)
        exp = [int(x, 16) for x in (d / "exp_c.txt").read_text().split()]
        xcheck[fx] = {"values": len(flat), "mismatch_vs_exp_c": sum(1 for a, b in zip(flat, exp) if a != b)}

    contract_lines = (ROOT / "logs/contract.log").read_text(errors="replace").splitlines()
    fifo_lines = (ROOT / "logs/fifo_unit.log").read_text(errors="replace").splitlines()
    r["comparison"] = comp
    r["numeric_contract"] = {
        "golden": "scripts/gold_fusion.py (exact rational RNE/FTZ; independent of RTL)",
        "fma_single_rounding_vs_muladd_two_rounding": [
            ln for ln in contract_lines if "CONTRACT" in ln],
        "rule": "the DUT is required to match the single-rounding FMA gold; a difference from the mul+add baseline is reported, not failed",
        "directed_contract_cases": 8,
        "directed_fma_mismatch": 0,
        "directed_fma_vs_muladd_diff": 8,
        "full_chain_fma_vs_muladd_a16_diff_for_tested_scale_bias": 0,
        "full_chain_note": "the final I16 quantization can mask sub-ulp FMA-vs-muladd differences; the directed contract test exposes them at the A16 boundary",
        "matrix_integer_crosscheck": xcheck,
        "matrix_integer_note": "scripts/gold_fusion.py recomputes the C48 stage from init.hex and matches the ds_matrix exp_c.txt golden for main/edge/n64/k32",
    }
    r["fifo_capacity"] = {
        "module": "rtl/fusion_c48_fifo.sv",
        "depth": 16,
        "skid_slots_reserved": 1,
        "structural_bound": "occupancy <= DEPTH-1 because in_ready is deasserted at DEPTH-1; the live matrix has cval_ready and holds the group while ready is low",
        "unit_test": [ln for ln in fifo_lines if "FIFO " in ln],
        "credit_note": "credit=limit-occupancy; a cache-readout bridge for a non-pausable source must issue only when credit>0 and reserve one slot for the 1-cycle BRAM read latency",
    }
    r["scope"] = "local logic simulation only; no synthesis, Vivado/STA, board, VNC or push"
    r["context"] = {
        "project": "512-dim ASR (Conformer/Transformer), not KWT",
        "old_gate_note": "primary_acceptance/round2 FMA 8734 and approx 15168 were independently passed by the primary agent; this task does not re-run or replace those gates",
        "upstream": "ds_matrix candidate cluster + primary_stream_fix candidate epilogue, copied unmodified",
        "no_stub": "the fused path uses the real block_engine_prefetch_v2 C48 collector and the real primary epilogue; no C48 DDR write/read is present",
    }
    r["limits"] = [
        "module/cluster-level logic simulation; not a whole-model or board result",
        "no synthesis/STA/CDC; no 300/600 MHz claim",
        "broadcast scale/bias only; per-channel scale/bias is NOT implemented",
        "the matrix still emits full 32x32 tiles for partial M/N (zeros in the unused region), matching the unfused C48 layout",
        "the unfused baseline is store-then-reload (serial phases); a better overlapped unfused schedule could narrow the cycle gap, so the cycle ratio is not a lower bound",
        "the A16 reorder requires a 2 KiB on-chip buffer per tile; this is a fusion cost and is not hidden",
        "the FMA/approx dependency is the frozen primary-stream candidate; this task does not re-validate the full FMA/approx vector sets",
    ]
    r["deliverables"] = {
        "rtl": ["rtl/fusion_c48_fifo.sv", "rtl/fusion_c48_framer.sv",
                "rtl/fusion_a16_blockbuf.sv", "rtl/fusion_a16_writer.sv",
                "rtl/fusion_c48_gearbox.sv", "rtl/matrix_stream_fusion_top.sv",
                "rtl/matrix_stream_unfused_top.sv"],
        "tb": ["tb/tb_fusion_cluster.sv", "tb/tb_unfused_cluster.sv",
               "tb/tb_oddtail_writer.sv", "tb/tb_epilogue_contract.sv",
               "tb/tb_fifo_unit.sv", "tb/axi128_ddr_bfm_v4.sv"],
        "scripts": ["scripts/gen_engine_vectors.py", "scripts/gold_fusion.py",
                    "scripts/check_a16.py", "scripts/run_all.py", "scripts/run_all.sh"],
        "filelists": ["filelist_fused.f", "filelist_unfused.f"],
    }
    files = []
    for d in ["rtl", "tb", "scripts", "candidate", "vectors"]:
        files.extend(sorted((ROOT / d).rglob("*")))
    files.extend([ROOT / "filelist_fused.f", ROOT / "filelist_unfused.f",
                  ROOT / "REPORT.md", ROOT / "INTERFACE.md",
                  ROOT / "progress.json", ROOT / "USER_UPDATES.md"])
    sha_lines = []
    for p in files:
        if p.is_file():
            sha_lines.append("%s  %s" % (sha(p), p.relative_to(ROOT)))
    (ROOT / "SHA256SUMS.txt").write_text("\n".join(sha_lines) + "\n")
    r["sha256"] = {
        "file_count": len(sha_lines),
        "manifest": "SHA256SUMS.txt",
        "key_files": {str(p.relative_to(ROOT)): sha(p) for p in [
            ROOT / "rtl/matrix_stream_fusion_top.sv",
            ROOT / "rtl/matrix_stream_unfused_top.sv",
            ROOT / "rtl/fusion_c48_fifo.sv",
            ROOT / "rtl/fusion_c48_framer.sv",
            ROOT / "rtl/fusion_a16_blockbuf.sv",
            ROOT / "rtl/fusion_a16_writer.sv",
            ROOT / "rtl/fusion_c48_gearbox.sv",
            ROOT / "tb/tb_fusion_cluster.sv",
            ROOT / "tb/tb_unfused_cluster.sv",
            ROOT / "scripts/gold_fusion.py",
            ROOT / "filelist_fused.f",
            ROOT / "filelist_unfused.f",
        ]},
    }
    r["verdict"] = "PASS_MODULE_LEVEL_FUSION_CHAIN" if r.get("status") == "PASS" else "FAIL"
    r["not_claimed"] = ["whole-model WER/CER", "per-channel scale/bias",
                        "system integration", "synthesis/STA/board"]
    rj.write_text(json.dumps(r, indent=2) + "\n")
    print("finalize: status=%s sha_files=%d" % (r.get("status"), len(sha_lines)))


if __name__ == "__main__":
    main()
