#!/usr/bin/env python3
"""Build result.json from the actual logs.  The rc argument is the number of
failed build/simulation steps accumulated by run_all.sh."""
import hashlib
import json
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def sha(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for b in iter(lambda: f.read(1 << 20), b""):
            h.update(b)
    return h.hexdigest()


def reldir(path):
    return os.path.relpath(path, ROOT)


def main():
    fails = int(sys.argv[1]) if len(sys.argv) > 1 else 1
    files = []
    for sub in ["rtl", "tests", "scripts", "fixtures"]:
        base = os.path.join(ROOT, sub)
        for dp, _, fns in os.walk(base):
            for fn in sorted(fns):
                files.append(os.path.join(dp, fn))
    for extra in ["README.md", "INTERFACE.md", "USER_UPDATES.md", "progress.json",
                  "REFERENCE_SHA256.json", "filelist.txt", "REPORT.md"]:
        p = os.path.join(ROOT, extra)
        if os.path.isfile(p):
            files.append(p)
    shas = {reldir(p): sha(p) for p in sorted(set(files))}
    fl = []
    fpath = os.path.join(ROOT, "filelist.txt")
    if os.path.isfile(fpath):
        for line in open(fpath):
            line = line.strip()
            if line and not line.startswith("#"):
                fl.append(line)
    metrics = {}
    mp = os.path.join(ROOT, "logs", "metrics.json")
    if os.path.isfile(mp):
        metrics = json.load(open(mp))
    def read_report(name):
        p = os.path.join(ROOT, "reports", name)
        return json.load(open(p)) if os.path.isfile(p) else {}
    result = {
        "task": "ds_storage_write",
        "title": "V0.24 Matrix C48 write coalescing + registered address validator",
        "status": "complete-logic-simulation" if fails == 0 else "failed",
        "run_all_rc": 0 if fails == 0 else 1,
        "failed_steps": fails,
        "date": "2026-10-30",
        "scope": "logic simulation only; no synthesis, Vivado, STA, DRC, CDC, board, VNC or push; no frequency or whole-model seconds claim",
        "acceptance": "subject to main-agent review; worker rc=0 is not automatic acceptance",
        "candidate_rtl": [
            "rtl/block_storage_stream_v3.sv",
            "rtl/block_engine_prefetch_v3.sv",
            "rtl/matrix_p2_cluster_v3.sv",
        ],
        "unmodified_reference_copies": [
            "rtl/operand_banks_dual_v2.sv",
            "rtl/block_address_v020.sv",
            "rtl/array16_w7_c48_cfg.sv",
            "rtl/pe_w7_c48_cfg.sv",
            "rtl/c_cache_banked4_pipe.sv",
            "rtl/axi_dma_v020_multi_v2.sv",
        ],
        "reference_root": "/home/yang/Desktop/项目/v023_repair/ds_matrix",
        "reference_manifest": "REFERENCE_SHA256.json",
        "reference_manifest_sha256": shas.get("REFERENCE_SHA256.json"),
        "filelist": fl,
        "file_sha256": shas,
        "tests": metrics.get("runs", {}),
        "commands_rc": metrics.get("commands", {}),
        "logs": {
            "commands": "logs/commands.log",
            "metrics": "logs/metrics.json",
            "commands_sha256": sha(os.path.join(ROOT, "logs", "commands.log")) if os.path.isfile(os.path.join(ROOT, "logs", "commands.log")) else None,
        },
        "long_wait_compare": read_report("long_wait_compare.json"),
        "cseg_bubble_compare": read_report("cseg_bubble_compare.json"),
        "storage_angles": read_report("storage_angles.json"),
        "tested": [
            "v023 reference SHA freeze and independent integer gold regeneration/cmp",
            "storage-level: 64x96B native -> 24 coalesced requests, C_BASE+0x80 4KiB split -> 25 requests, generic 128B stride, 24B/2-beat tail strobe, bad-segment fault, abort drain",
            "registered ld validator: 4 commands on consecutive cycles, boundary/identity/alignment/wrap rejects",
            "engine: fast K96 C0/C1, 3 seeds, multi-N N64, K32 single-tile, edge M17N19K33, P12 clip, write backpressure",
            "engine fault contracts: read error 09, write error 0a, bad W parity 09, all with cwr_pending=0",
            "candidate and v023 v2 on the same strict AXI128 BFM: K32 fast and long_wait (LAT=48)",
            "v2 WR_OUT=64 long_wait control: cycles unchanged",
            "same-engine cseg+first-cval A/B",
        ],
        "not_tested": [
            "full 512-dim ASR model / CASE0000 / ONNX / host executor",
            "WER/CER or quantized accuracy",
            "synthesis, STA, Fmax, CDC, multi-clock, board DDR/PHY",
            "physical Xilinx HP-port/SmartConnect arbitration",
            "whole-model seconds or a frequency target",
            "generic path with more than 128 B per cseg",
        ],
        "repro": "bash scripts/run_all.sh",
    }
    json.dump(result, open(os.path.join(ROOT, "result.json"), "w"), indent=2, sort_keys=True)
    print("wrote result.json status=%s failed_steps=%0d" % (result["status"], fails))
    return 0


if __name__ == "__main__":
    sys.exit(main())
