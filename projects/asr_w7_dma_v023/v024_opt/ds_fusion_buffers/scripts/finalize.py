#!/usr/bin/env python3
"""Add traffic ledger, same-load comparisons, cost, SHA manifest and limits."""
import hashlib
import importlib.util
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.dont_write_bytecode = True


def sha(p):
    return hashlib.sha256(Path(p).read_bytes()).hexdigest()


def main():
    rj = ROOT / "result.json"
    r = json.loads(rj.read_text())
    cases = {c["label"]: c for c in r.get("cases", [])}
    met = lambda lab: cases.get(lab, {}).get("metrics", {})

    # Preserve the ORIGINAL upstream status/exit separately from our rerun copy
    # (the rerun overwrote result.json inside upstream_repro/).
    orig = Path("/home/yang/Desktop/项目/v023_repair/ds_closeout_fusion")
    uv = r.get("upstream_verification", {})
    try:
        if (orig / "result.json").exists():
            ores = json.loads((orig / "result.json").read_text())
            uv["original_result_status"] = ores.get("status")
            uv["original_totals"] = ores.get("totals")
        if (orig / "exit.json").exists():
            uv["original_exit_code"] = json.loads((orig / "exit.json").read_text()).get("exit_code")
    except Exception as e:
        uv["original_read_error"] = str(e)
    r["upstream_verification"] = uv

    # ---------------- DDR traffic ledger (real handshakes only) ----------
    ledger = []
    for lab, c in cases.items():
        m = c.get("metrics", {})
        if c.get("kind") in ("dual", "single"):
            rec = {
                "label": lab, "kind": c["kind"], "tiles": m.get("tiles"),
                "aw_read_bytes": m.get("rd_bytes"),
                "a16_write_bytes": m.get("wr_bytes"),
                "c48_write_bytes": 0,
                "c48_read_bytes": 0,
                "total_bus_bytes": (m.get("rd_bytes", 0) + m.get("wr_bytes", 0)),
                "onchip_extra_bytes": 2048 * (1 if c["kind"] == "dual" else 0),
                "out_of_a16_window": "monitored by TB (must be 0)",
                "b_count": m.get("b_count"), "last_b": m.get("last_b"),
                "dma_done": m.get("dma_done"),
            }
        elif c.get("kind") == "unfused":
            rec = {
                "label": lab, "kind": "unfused", "tiles": m.get("tiles"),
                "aw_read_bytes": (m.get("rd_beats", 0) * 16),
                "c48_write_bytes": m.get("c48w_bytes"),
                "c48_read_bytes": m.get("c48r_bytes"),
                "a16_write_bytes": m.get("a16_bytes"),
                "total_bus_bytes": (m.get("rd_beats", 0) * 16 + m.get("c48w_bytes", 0) +
                                    m.get("c48r_bytes", 0) + m.get("a16_bytes", 0)),
                "onchip_extra_bytes": 0,
                "b_count": m.get("b_count"), "last_b": m.get("last_b"),
                "dma_done": m.get("dma_done"),
            }
        else:
            continue
        ledger.append(rec)

    # ---------------- same-load comparisons -----------------------------
    pairs = [
        ("main", "d_bp0_main", "s_bp0_main", "u_bp0_main"),
        ("n64",  "d_b0_n64",   "s_b0_n64",   "u_n64"),
        ("n96",  "d_b0_n96",   "s_b0_n96",   "u_n96"),
        ("m64",  "d_b0_m64",   "s_b0_m64",   "u_m64"),
        ("edge", "d_b0_edge",  "s_b0_edge",  "u_edge"),
    ]
    comp = []
    for name, dl, sl, ul in pairs:
        d, s, u = met(dl), met(sl), met(ul)
        fd = d.get("rd_bytes", 0) + d.get("wr_bytes", 0)
        fu = u.get("rd_beats", 0) * 16 + u.get("c48w_bytes", 0) + \
             u.get("c48r_bytes", 0) + u.get("a16_bytes", 0)
        tiles = d.get("tiles", 0)
        comp.append({
            "workload": name,
            "tiles": tiles,
            "dual_cycles": d.get("cycles"),
            "single_cycles": s.get("cycles"),
            "unfused_cycles": u.get("cycles"),
            "dual_task_cycles": d.get("task_cycles"),
            "single_task_cycles": s.get("task_cycles"),
            "unfused_matrix_cycles": u.get("matrix_cycles"),
            "single_over_dual_cycles": round(s.get("cycles", 0) / d.get("cycles", 1), 3)
                if d.get("cycles") else None,
            "unfused_over_dual_cycles": round(u.get("cycles", 0) / d.get("cycles", 1), 3)
                if d.get("cycles") else None,
            "fused_bus_bytes": fd,
            "unfused_bus_bytes": fu,
            "c48_roundtrip_eliminated_bytes": 2 * 6144 * tiles,
            "fused_extra_ddr_bytes": 0,
            "dual_onchip_extra_bytes": 2048,
            "dual_b_count": d.get("b_count"),
            "dual_last_b": d.get("last_b"),
            "dual_dma_done": d.get("dma_done"),
            "single_last_b": s.get("last_b"),
            "unfused_last_b": u.get("last_b"),
            "both_match_gold": bool(cases.get(dl, {}).get("ok") and
                                    cases.get(sl, {}).get("ok") and
                                    cases.get(ul, {}).get("ok")),
        })

    long_b = []
    for name, dl, sl in [
        ("n64_long_B_3000", "d_bextra_n64", "s_n64_b3000"),
        ("main_long_B_120", "d_bextra_main", "s_b120_main"),
    ]:
        d, s = met(dl), met(sl)
        long_b.append({
            "workload": name,
            "dual_cycles": d.get("cycles"),
            "single_cycles": s.get("cycles"),
            "dual_overlap_cycles": d.get("overlap"),
            "dual_bank_occ_max": d.get("bank_occ_max"),
            "single_task_cycles": s.get("task_cycles"),
            "dual_task_cycles": d.get("task_cycles"),
            "dual_last_b": d.get("last_b"),
            "dual_dma_done": d.get("dma_done"),
            "dual_b_count": d.get("b_count"),
            "dual_done_after_last_b": bool(d.get("last_b") and d.get("dma_done") and
                                           d.get("dma_done") >= d.get("last_b")),
        })

    # Independent integer-stage crosscheck: gold_fusion.py recomputes C48 from
    # init.hex and is compared with gen_engine_vectors.py's exp_c.txt.  These are
    # two separate Python implementations, neither derived from the RTL.
    spec = importlib.util.spec_from_file_location("gold_fusion", ROOT / "scripts/gold_fusion.py")
    gf = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(gf)
    xcheck = {}
    for d in sorted((ROOT / "vectors").iterdir()):
        if not (d / "manifest.json").exists() or not (d / "exp_c.txt").exists():
            continue
        manifest = json.loads((d / "manifest.json").read_text())
        words = gf.read_hex_words(d / "init.hex")
        tiles, _, _, _ = gf.matrix_gold(manifest, words)
        flat = []
        for c in tiles:
            flat.extend((v & ((1 << 48) - 1)) for v in c)
        exp = [int(x, 16) for x in (d / "exp_c.txt").read_text().split()]
        xcheck[d.name] = {"values": len(flat),
                          "mismatch_vs_exp_c": sum(1 for a, b in zip(flat, exp) if a != b)}

    contract_lines = (ROOT / "logs/contract.log").read_text(errors="replace").splitlines()
    credit_lines = (ROOT / "logs/fifo_credit.log").read_text(errors="replace").splitlines()
    fifo_lines = (ROOT / "logs/fifo_unit.log").read_text(errors="replace").splitlines()

    # ---------------- unique-module filelist proof ------------------------
    def modules_in_filelist(name):
        files = []
        mods = []
        for line in (ROOT / name).read_text().splitlines():
            line = line.strip()
            if not line or line.startswith("//"):
                continue
            p = ROOT / line
            files.append(line)
            mods.extend(re.findall(r"\bmodule\s+([A-Za-z_]\w*)", p.read_text(errors="replace")))
        dup = sorted({m for m in mods if mods.count(m) > 1})
        return {"file": name, "files": len(files), "modules": len(mods),
                "unique_modules": len(set(mods)), "duplicates": dup}

    r["filelists"] = [modules_in_filelist(n) for n in
                      ("filelist_fused_dual.f", "filelist_fused_single.f",
                       "filelist_unfused.f")]

    r["ledger"] = ledger
    r["comparison"] = comp
    r["long_b"] = long_b
    r["numeric_contract"] = {
        "golden": "scripts/gold_fusion.py exact-rational RNE/FTZ, independent of RTL",
        "directed_contract": [l for l in contract_lines if "CONTRACT" in l],
        "rule": "DUT must match single-rounding FMA gold; difference from mul+add is reported, not failed",
        "matrix_integer_crosscheck": xcheck,
        "matrix_integer_note": "two independent Python implementations: gold_fusion.py recomputes C48 from init.hex; exp_c.txt comes from gen_engine_vectors.py",
    }
    r["fifo_credit"] = {
        "module": "rtl/fusion_c48_fifo.sv (unchanged)",
        "depth": 16, "reserved_skid": 1,
        "bound": "occupancy <= DEPTH-1 = 15; credit = 15-occupancy",
        "unit_test": [l for l in fifo_lines if "FIFO " in l],
        "non_pausable_source_test": [l for l in credit_lines if "CREDIT " in l],
        "contract": "stale registered credit, no retraction, 512 beats incl. tail last; "
                    "a future C-cache readout may use credit gating + one reserved slot",
    }
    r["cost"] = {
        "second_a16_bank_bytes": 2048,
        "total_a16_bank_bytes": 4096,
        "top_level_axi_ports_added": 0,
        "internal_banks": 2,
        "bank_port_shape": "each bank 1 write + 1 read (128-bit)",
        "extra_ddr_bytes": 0,
        "extra_c48_ddr_bytes": 0,
        "added_logic": "1-bit bank index, write/read bank mux, per-bank empty/full/draining state",
        "not_counted": "no synthesis/STA; BRAM primitive packing and Fmax are not claimed",
    }
    r["scope"] = "local logic simulation only; no synthesis/Vivado/STA/board/VNC/push"
    r["limits"] = [
        "module/cluster-level logic simulation; not a whole-model or board result",
        "no synthesis/STA/CDC; no frequency claim",
        "broadcast scale/bias only; per-channel scale/bias and cfg_spill_fp32 are interface-only",
        "one A16 write DMA: compute/writeout overlap, not two simultaneous writes",
        "partial M/N still emits a full 32x32 tile with zeros in the unused region",
        "the unfused baseline is frozen store-then-reload; a better overlapped unfused schedule could narrow the cycle gap",
        "the frozen unfused baseline does not complete in this simulation environment for cfg_b_extra>1; accepted baseline uses b_extra=0 (v4-equivalent) plus one b_extra=1 smoke",
        "long-B and dual-bank overlap are exercised on the fused single vs dual tops with the same v5 BFM and same gold",
        "no full 591 DAG/executor, approx integration, WER/CER",
    ]
    r["not_claimed"] = [
        "whole-model WER/CER", "per-channel scale/bias", "cfg_spill_fp32",
        "synthesis/STA/CDC/board", "300/600 MHz", "whole-model seconds",
        "unfused baseline with cfg_b_extra>1",
    ]
    r["deliverables"] = {
        "rtl": ["rtl/fusion_a16_blockbuf_dual.sv", "rtl/matrix_stream_fusion_top_dual.sv",
                "rtl/fusion_a16_blockbuf.sv", "rtl/fusion_a16_writer.sv",
                "rtl/fusion_c48_fifo.sv", "rtl/fusion_c48_framer.sv",
                "rtl/fusion_c48_gearbox.sv", "rtl/matrix_stream_fusion_top.sv",
                "rtl/matrix_stream_unfused_top.sv"],
        "tb": ["tb/tb_fusion_dual.sv", "tb/tb_fusion_single_ref.sv",
               "tb/tb_unfused_baseline.sv", "tb/tb_fifo_credit.sv",
               "tb/axi128_ddr_bfm_v4.sv", "tb/axi128_ddr_bfm_v5.sv",
               "tb/tb_fifo_unit.sv", "tb/tb_oddtail_writer.sv",
               "tb/tb_epilogue_contract.sv"],
        "scripts": ["scripts/run_all.py", "scripts/run_all.sh", "scripts/finalize.py",
                    "scripts/gen_engine_vectors.py", "scripts/gold_fusion.py",
                    "scripts/check_a16.py"],
        "filelists": ["filelist_fused_dual.f", "filelist_fused_single.f",
                      "filelist_unfused.f"],
    }

    files = []
    for d in ["rtl", "tb", "scripts", "candidate", "vectors"]:
        files.extend(sorted((ROOT / d).rglob("*")))
    files.extend([ROOT / "filelist_fused_dual.f", ROOT / "filelist_fused_single.f",
                  ROOT / "filelist_unfused.f", ROOT / "REPORT.md", ROOT / "INTERFACE.md",
                  ROOT / "progress.json", ROOT / "USER_UPDATES.md",
                  ROOT / "reference_freeze_v023_fusion.json"])
    lines = []
    for p in files:
        if p.is_file():
            lines.append("%s  %s" % (sha(p), p.relative_to(ROOT)))
    (ROOT / "SHA256SUMS.txt").write_text("\n".join(lines) + "\n")
    r["sha256"] = {
        "file_count": len(lines), "manifest": "SHA256SUMS.txt",
        "key_files": {str(p.relative_to(ROOT)): sha(p) for p in [
            ROOT / "rtl/matrix_stream_fusion_top_dual.sv",
            ROOT / "rtl/fusion_a16_blockbuf_dual.sv",
            ROOT / "rtl/matrix_stream_fusion_top.sv",
            ROOT / "rtl/fusion_a16_blockbuf.sv",
            ROOT / "tb/tb_fusion_dual.sv",
            ROOT / "tb/axi128_ddr_bfm_v5.sv",
            ROOT / "scripts/gold_fusion.py",
            ROOT / "filelist_fused_dual.f",
            ROOT / "INTERFACE.md",
        ]},
    }
    rcfile = ROOT / "logs/run_all_rc.txt"
    r["reproduce"] = {
        "script": "scripts/run_all.sh",
        "run_all_rc": int(rcfile.read_text().strip()) if rcfile.exists() else None,
        "result_status": r.get("status"),
    }
    r["verdict"] = "PASS_DUAL_BANK_A16_OVERLAP" if r.get("status") == "PASS" else "FAIL"
    rj.write_text(json.dumps(r, indent=2) + "\n")
    print("finalize: status=%s sha_files=%d" % (r.get("status"), len(lines)))
    return 0 if r.get("status") == "PASS" else 1


if __name__ == "__main__":
    sys.exit(main())
