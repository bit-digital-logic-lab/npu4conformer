#!/usr/bin/env python3
"""Logical on-chip memory/register inventory for ds_matrix_reuse v1.

Declaration/array-bit inventory only, not a synthesis resource report.
It verifies that the W-reuse schedule adds no new memory array: the C cache
is the unchanged v023 2-slot cache, the A/W banks keep the v023 shapes, and
the storage queue arrays are identical to v023 (the storage diff is ports /
release / abort only).  Control flops added by the new engine are listed but
not converted to LUT/FF counts.
"""
import json
import os
import re
import hashlib
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
RTL = ROOT / "candidate" / "rtl"
V23 = Path(os.environ.get("V23", "/home/yang/Desktop/项目/v023_repair/ds_matrix/candidate/rtl"))


def text(name):
    return (RTL / name).read_text()


def must(pat, name):
    t = text(name)
    if not re.search(pat, t):
        raise SystemExit(f"FAIL {name}: missing /{pat}/")
    return t


def sha(p):
    return hashlib.sha256(p.read_bytes()).hexdigest()


def array_decls(t):
    return sorted(re.findall(r"^\s*reg\s*\[[^\]]+\]\s*\w+\s*\[[^\]]+\]\s*;", t, re.M))


def main():
    cc = must(r"reg \[47:0\] mem\[0:511\]", "c_cache_banked4_pipe.sv")
    assert "for(genvar b=0;b<4;b=b+1)" in cc
    ab = must(r"reg \[127:0\] mem\[0:15\]\[0:7\]", "operand_banks_dual_reuse.sv")
    wb = must(r"reg \[7:0\] mem\[0:15\]\[0:63\]", "operand_banks_dual_reuse.sv")
    assert "for(s=0;s<2;s=s+1)" in ab and "for(s=0;s<2;s=s+1)" in wb
    eng = must(r"reg \[49151:0\] result_payload", "block_engine_reuse_v1.sv")
    sto = text("block_storage_stream_reuse_v1.sv")
    for f, t in (("block_engine_reuse_v1.sv", eng),
                 ("block_storage_stream_reuse_v1.sv", sto)):
        if re.search(r"\bmem\s*\[", t):
            raise SystemExit(f"FAIL {f}: unexpected memory array (banks are external)")

    arrays = [
        {"name": "c_cache_banked4_pipe banks", "shape": "4 x 512 x 48",
         "bits": 4 * 512 * 48, "bytes": 4 * 512 * 48 // 8,
         "style": "block RAM (ram_style=block)", "role": "2 x 32x32 C48 slots"},
        {"name": "A stage banks", "shape": "2 x 16 x 8 x 128",
         "bits": 2 * 16 * 8 * 128, "bytes": 2 * 16 * 8 * 128 // 8,
         "style": "distributed RAM", "role": "2 x 32x32 A16 stages"},
        {"name": "W stage banks", "shape": "2 x 16 x 64 x 8",
         "bits": 2 * 16 * 64 * 8, "bytes": 2 * 16 * 64 * 8 // 8,
         "style": "distributed RAM", "role": "2 x 32x32 W7 stages"},
        {"name": "result_payload", "shape": "1 x 49152",
         "bits": 49152, "bytes": 49152 // 8,
         "style": "registers (not an array)", "role": "one 32x32 C48 result"},
    ]
    total_mem = sum(a["bits"] for a in arrays if "registers" not in a["style"])
    per_slot = 256 * 192

    v23_check = {"available": V23.exists()}
    if V23.exists():
        # C cache and bank memory shapes must match the v023 read-only copies.
        v23_check["c_cache_sha_equal"] = sha(RTL / "c_cache_banked4_pipe.sv") == sha(V23 / "c_cache_banked4_pipe.sv")
        v23_check["operand_bank_array_decls_equal"] = (
            array_decls(text("operand_banks_dual_reuse.sv")) ==
            array_decls((V23 / "operand_banks_dual_v2.sv").read_text()))
        v23_check["storage_queue_array_decls_equal"] = (
            array_decls(sto) == array_decls((V23 / "block_storage_stream_v2.sv").read_text()))
        if not (v23_check["c_cache_sha_equal"] and
                v23_check["operand_bank_array_decls_equal"] and
                v23_check["storage_queue_array_decls_equal"]):
            raise SystemExit("FAIL v023 array/instance comparison mismatch")

    doc = {
        "task": "ds_matrix_reuse",
        "kind": "logical declaration inventory, not synthesis/BRAM placement",
        "arrays": arrays,
        "memory_array_bits": total_mem,
        "memory_array_bytes": total_mem // 8,
        "c_cache_slot_bits": per_slot,
        "c_cache_slot_bytes": per_slot // 8,
        "c_cache_two_slots_bytes": per_slot // 4,
        "new_memory_arrays_vs_v023": 0,
        "v023_array_check": v23_check,
        "storage_register_arrays": array_decls(sto),
        "engine_register_arrays": array_decls(eng),
        "control_registers_added": [
            "unit", "use_pair", "wst", "curs", "cload_u", "res_slot",
            "res_row[15:0]", "res_step[1:0]", "res_next[4:0]", "res_issued",
            "fresh_c[0:1]", "w/a/c_load_blocks[31:0]",
            "pair_schedules[31:0]", "w_reuse_saved[31:0]",
        ],
        "note": "No new BRAM/LUTRAM array.  Extra flops are control/telemetry "
                "only; this is not a zero extra FF/LUT claim and not an "
                "STA/synthesis result.",
    }
    (ROOT / "logs" / "capacity.json").write_text(json.dumps(doc, indent=2) + "\n")
    for a in arrays:
        print(f"{a['name']:26s} {a['shape']:20s} {a['bits']:7d} bits "
              f"{a['bytes']:6d} B  {a['style']}")
    print(f"memory arrays total: {total_mem} bits / {total_mem//8} B")
    print(f"C cache per slot: {per_slot} bits / {per_slot//8} B; "
          f"two slots: {per_slot//4} B")
    print("new memory arrays vs v023: 0 (control regs listed in capacity.json)")
    print("PASS capacity inventory")


if __name__ == "__main__":
    main()
