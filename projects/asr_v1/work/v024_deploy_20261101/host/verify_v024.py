#!/usr/bin/env python3
"""Prepare frozen V024 data and strictly verify a physical-board receipt.

Standard library only. This module never connects to, programs or resets hardware.
"""
from __future__ import annotations
import argparse
import copy
import hashlib
import json
import math
import re
import struct
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
CORE = HERE.parent / "core"
PINNED = {
    "sim/fixtures/mem_v024_fused.hex": "fd05f8f4ff4f3754c3a9c89786887b69168c3cbe015be44e6d6718deae52e26b",
    "sim/fixtures/gold_a16.hex": "da364d27fee9848fcfc8e637ce006557dafd4aead4031f4c7d8bd549ef9e3b8e",
    "sim/fixtures/v024_ref.json": "3a04e69ffbf809abb25490d11182d0d3a74de8ed61d9cdc0eaf46e84327c0db8",
}
REGIONS = {
    "arena": (0x04000000, 0x40000, 65536, "fused_arena64k.bin"),
    "param": (0x10000000, 0xC0000, 65536, "fused_param64k.bin"),
    "pc": (0x10003000, 0xC3000, 256, "fused_pc64.bin"),
}
EXPECTED_TERMINAL = {
    "board_magic": 0xA51A2480, "capacity": 128, "csr_magic": 0xA51A22D0,
    "csr_status": 2, "error": 0,
    "completed": 7, "rd_pending": 0,
    "wr_pending": 0, "b_pending": 0, "c48_bytes": 0,
    "a16_bytes": 2048, "csr_error": 0, "csr_completed": 7,
    "csr_requires_reset_isolation": 0, "csr_quiesced": 1,
    "csr_rd_pending": 0, "csr_wr_pending": 0, "csr_b_pending": 0,
    "plan_base_readback": 0x10008000, "plan_count_readback": 1,
    "parameter_ready": 1, "release_reset_readback": 1,
    "calibration_pass": 1, "arena_verified_words": 16384,
    "param_verified_words": 16384, "pc_verified_words": 64,
    "output_words": 8192, "start_issued": 1, "poll_timed_out": 0,
}

class VerificationError(ValueError):
    pass

def need(test: bool, message: str):
    if not test:
        raise VerificationError(message)

def sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()

def normalized_bytes(path: Path) -> bytes:
    # Frozen repository text hashes use LF; Windows extraction may produce CRLF.
    return path.read_bytes().replace(b"\r\n", b"\n")

def hex_words(path: Path, count: int) -> list[int]:
    lines = path.read_text(encoding="ascii").splitlines()
    need(len(lines) == count, f"{path.name}: expected {count} words, got {len(lines)}")
    for i, line in enumerate(lines):
        need(re.fullmatch(r"[0-9a-fA-F]{8}", line) is not None,
             f"{path.name}: invalid 32-bit hex word at line {i + 1}")
    return [int(s, 16) for s in lines]

def packed(words: list[int]) -> bytes:
    return struct.pack(f"<{len(words)}I", *words)

def uint_words(values, count: int, name: str) -> list[int]:
    need(isinstance(values, list) and len(values) == count,
         f"{name}: expected exactly {count} values")
    need(all(type(v) is int and 0 <= v <= 0xFFFFFFFF for v in values),
         f"{name}: values must be unsigned 32-bit integers")
    return values

def validate_inputs(core: Path) -> tuple[dict, dict[str, bytes], dict]:
    freeze = json.loads((core / "sim/fixtures/REFERENCE_FREEZE.json").read_text())
    need(isinstance(freeze, dict) and len(freeze) == 10, "freeze manifest must contain 10 reference files")
    for name, pinned in PINNED.items():
        need(freeze.get(name) == pinned, f"frozen contract changed: {name}")
    hashes = {}
    for name, expected in freeze.items():
        path = core / name
        need(path.is_file(), f"frozen reference absent: {name}")
        actual = sha(normalized_bytes(path))
        need(actual == expected, f"frozen reference SHA256 mismatch: {name}")
        hashes[name] = actual
    ref = json.loads((core / "sim/fixtures/v024_ref.json").read_text())
    need(ref.get("dump_base") == 0x04004000 and ref.get("dump_bytes") == 32768,
         "reference output window differs from board contract")
    a16 = uint_words(ref.get("fused_a16_words"), 512, "fused_a16_words")
    need(hex_words(core / "sim/fixtures/gold_a16.hex", 512) == a16,
         "independent gold_a16.hex differs from v024_ref.json")
    for key in ("div_gold", "sqrt_gold"):
        uint_words(ref.get(key), 1024, key)
    for key in ("scales", "biases"):
        uint_words(ref.get(key), 32, key)
    need(ref["tolerances"] == {"div_rel": 0.0012, "sqrt_rel": 6e-6},
         "frozen numerical tolerance changed")
    mapping = json.loads((core / "inputs/MEMORY_MAP.json").read_text())
    entries = mapping.get("regions")
    need(isinstance(entries, list) and len(entries) == 3, "MEMORY_MAP must contain exactly 3 regions")
    by_addr = {int(e["logical_address"], 0): e for e in entries}
    need(len(by_addr) == 3, "duplicate logical region")
    frozen_mem = packed(hex_words(core / "sim/fixtures/mem_v024_fused.hex", 262144))
    blobs = {}
    input_info = {}
    for name, (addr, flat, size, filename) in REGIONS.items():
        need(addr in by_addr, f"missing MEMORY_MAP address: {addr:#x}")
        entry = by_addr[addr]
        need(entry["size"] == size and int(entry["bfm_flat_byte_offset"], 0) == flat,
             f"{name}: size or BFM mapping changed")
        need(entry["binary"].replace("\\", "/") == f"inputs/{filename}",
             f"{name}: unexpected binary path")
        data = (core / "inputs" / filename).read_bytes()
        need(len(data) == size, f"{name}: binary byte length {len(data)} != {size}")
        need(sha(data) == entry["sha256"], f"{name}: input SHA256 mismatch")
        need(data == frozen_mem[flat:flat + size], f"{name}: binary differs from frozen BFM image")
        blobs[name] = data
        input_info[name] = {"address": addr, "bytes": size, "sha256": sha(data)}
    need(blobs["pc"] == packed(ref["scales"] + ref["biases"]),
         "parameter scale/bias binary differs from reference")
    return ref, blobs, {"schema": 1, "freeze_sha256_lf": hashes, "inputs": input_info,
                        "memory_map_sha256": sha((core / "inputs/MEMORY_MAP.json").read_bytes()),
                        "scope": "V024 fused seven-node graph, 128-node controller, BRAM only"}

def prepare(core: Path, out: Path):
    _, blobs, provenance = validate_inputs(core)
    out.mkdir(parents=True, exist_ok=True)
    for name, blob in blobs.items():
        words = struct.unpack(f"<{len(blob) // 4}I", blob)
        (out / f"{name}.hex").write_text("".join(f"{w:08x}\n" for w in words), encoding="ascii")
    (out / "provenance.json").write_text(json.dumps(provenance, indent=2) + "\n", encoding="utf-8")
    print("PREPARE_PASS: frozen references and exact 65536/65536/256 byte input images verified")

def number(receipt: dict, key: str) -> int:
    value = receipt.get(key)
    need(type(value) in (int, str), f"receipt missing integer field: {key}")
    try:
        return int(value, 0) if isinstance(value, str) else value
    except ValueError as exc:
        raise VerificationError(f"receipt invalid integer field {key}: {value!r}") from exc

def compare_fp(got: list[int], gold: list[int], count: int, tol: float, name: str) -> dict:
    need(len(got) == count and len(gold) == count, f"{name}: exact element count mismatch")
    max_rel, max_index = -1.0, -1
    mismatches = []
    for i in range(count):
        actual = struct.unpack("<f", struct.pack("<I", got[i]))[0]
        expected = struct.unpack("<f", struct.pack("<I", gold[i]))[0]
        need(math.isfinite(actual) and math.isfinite(expected), f"{name}[{i}]: non-finite actual/gold")
        relative = abs(actual - expected) / (abs(expected) if expected != 0 else 1.0)
        if relative > max_rel:
            max_rel, max_index = relative, i
        if relative > tol and len(mismatches) < 8:
            mismatches.append({"index": i, "actual": actual, "expected": expected, "relative_error": relative})
    need(not mismatches, f"{name}: tolerance {tol} exceeded: {mismatches}")
    return {"elements": count, "max_relative_error": max_rel,
            "worst_index": max_index, "relative_tolerance": tol, "pass": True}

def compare_output(data: bytes, ref: dict, frozen_arena: bytes) -> dict:
    need(len(data) == 32768, f"output.bin must contain exactly 32768 bytes, got {len(data)}")
    need(len(frozen_arena) == 65536, "frozen arena must contain exactly 65536 bytes")
    words = list(struct.unpack("<8192I", data))
    initial = struct.unpack("<8192I", frozen_arena[0x4000:0xc000])
    a16_gold = uint_words(ref["fused_a16_words"], 512, "gold A16")
    a16, div, sqrt, copied = words[0:512], words[1536:2560], words[2560:3584], words[3584:4096]
    for name, actual in (("A16", a16), ("A16 copy", copied)):
        need(len(actual) == 512 and len(a16_gold) == 512, f"{name}: expected 512 packed words / 1024 int16 scalars")
        for i in range(512):
            need(actual[i] == a16_gold[i],
                 f"{name}[packed_word {i}]: 0x{actual[i]:08x} != 0x{a16_gold[i]:08x}")
    for begin, end in ((512, 1536), (4096, 8192)):
        for i in range(begin, end):
            need(words[i] == initial[i],
                 f"unchanged arena output word {i}: 0x{words[i]:08x} != frozen input 0x{initial[i]:08x}")
    return {"dump_words": 8192, "dump_bytes": len(data),
            "a16": {"packed_words": 512, "int16_elements": 1024, "exact_match": True},
            "a16_copy": {"packed_words": 512, "int16_elements": 1024, "exact_match": True},
            "div": compare_fp(div, ref["div_gold"], 1024, 0.0012, "DIV"),
            "sqrt": compare_fp(sqrt, ref["sqrt_gold"], 1024, 6e-6, "SQRT"),
            "unchanged_arena": {"words": 5120, "ranges": [[512, 1536], [4096, 8192]],
                                "reference": "frozen arena input bytes 0x4000:0xc000",
                                "exact_match": True}}

def validate_receipt(receipt: dict) -> int:
    need(receipt.get("schema") == "1", "unsupported board receipt schema")
    need(receipt.get("execution_state") == "completed", "board execution did not complete")
    need(receipt.get("evidence_kind") == "physical_board_jtag_axi", "receipt is not a hardware acquisition")
    for key, expected in EXPECTED_TERMINAL.items():
        actual = number(receipt, key)
        need(actual == expected, f"receipt {key}: got {actual:#x}, expected {expected:#x}")
    # board_status bit 1 observes a one-clock done pulse, not the CSR sticky bit.
    need((number(receipt, "board_status") & ~2) == 0x30,
         "board status must be idle, fault-free, reset-free, quiesced and fused")
    # Nodes run by dependencies; the last completion can vary with AXI latency.
    need(0 <= number(receipt, "last_node") < 7, "last_node is outside the seven-node graph")
    need(receipt.get("read_order") in ("ascending", "descending"), "read byte-order calibration absent")
    need(receipt.get("write_order") in ("ascending", "descending"), "write byte-order calibration absent")
    cycles = number(receipt, "cycles_low") | (number(receipt, "cycles_high") << 32)
    need(cycles > 0, "hardware cycle counter must be positive")
    csr_cycles = number(receipt, "csr_cycles_low") | (number(receipt, "csr_cycles_high") << 32)
    need(cycles == csr_cycles, "board/CSR cycle counters disagree after DONE")
    return cycles

def verify(core: Path, run: Path) -> dict:
    ref, blobs, provenance = validate_inputs(core)
    receipt = json.loads((run / "board_receipt.json").read_text(encoding="utf-8"))
    cycles = validate_receipt(receipt)
    for name, blob in blobs.items():
        words = hex_words(run / f"{name}_readback.hex", len(blob) // 4)
        need(packed(words) == blob, f"saved full {name} readback differs from input")
    saved_prov = json.loads((run / "prepared/provenance.json").read_text())
    need(saved_prov == provenance, "prepared inputs do not match current frozen provenance")
    output_hex = hex_words(run / "output.hex", 8192)
    data = packed(output_hex)
    (run / "output.bin").write_bytes(data)
    result = compare_output(data, ref, blobs["arena"])
    result.update({"schema": 1, "pass": True, "evidence_kind": "physical_board_jtag_axi",
                   "scope": provenance["scope"], "cycles": cycles,
                   "output_sha256": sha(data), "board_receipt_sha256": sha((run / "board_receipt.json").read_bytes()),
                   "input_provenance": provenance,
                   "limits": "Not full ASR, DDR bandwidth, WER/CER, end-to-end speech or timing-closure evidence"})
    return result

def selftest(core: Path, out: Path):
    ref, blobs, _ = validate_inputs(core)
    words = list(struct.unpack("<8192I", blobs["arena"][0x4000:0xc000]))
    words[0:512] = ref["fused_a16_words"]
    words[1536:2560] = ref["div_gold"]
    words[2560:3584] = ref["sqrt_gold"]
    words[3584:4096] = ref["fused_a16_words"]
    good = packed(words)
    compare_output(good, ref, blobs["arena"])
    tests = {"exact_frozen_gold": "pass"}
    cases = [("empty", b"", ref), ("truncated_one_byte", good[:-1], ref),
             ("truncated_copy", good[:3584 * 4], ref), ("extra_word", good + b"\0" * 4, ref)]
    for name, offset, value in (("a16_corrupt", 511, words[511] ^ 1),
                               ("copy_last_corrupt", 4095, words[4095] ^ 1),
                               ("div_nan", 1536, 0x7fc00000), ("sqrt_inf", 2560, 0x7f800000),
                               ("div_last_corrupt", 2559, 0), ("sqrt_last_corrupt", 3583, 0),
                               ("unchanged_first_range_first", 512, words[512] ^ 1),
                               ("unchanged_first_range_last", 1535, words[1535] ^ 1),
                               ("unchanged_second_range_first", 4096, words[4096] ^ 1),
                               ("unchanged_second_range_last", 8191, words[8191] ^ 1)):
        changed = words.copy()
        changed[offset] = value
        cases.append((name, packed(changed), ref))
    bad_ref = copy.deepcopy(ref)
    bad_ref["div_gold"] = bad_ref["div_gold"][:-1]
    cases.append(("short_gold", good, bad_ref))
    for name, data, fixture in cases:
        try:
            compare_output(data, fixture, blobs["arena"])
        except VerificationError:
            tests[name] = "correctly_rejected"
        else:
            raise VerificationError(f"self-test {name}: invalid data incorrectly accepted")
    valid_receipt = {key: str(value) for key, value in EXPECTED_TERMINAL.items()}
    valid_receipt.update(schema="1", execution_state="completed", evidence_kind="physical_board_jtag_axi",
                         last_node="5", read_order="descending", write_order="descending",
                         cycles_low="1000", cycles_high="0", csr_cycles_low="1000", csr_cycles_high="0",
                         board_status=str(0x30))
    validate_receipt(valid_receipt)
    tests["terminal_contract_last_node_5_done_pulse_gone_csr_sticky"] = "pass"
    with_pulse = valid_receipt.copy()
    with_pulse["board_status"] = str(0x32)
    validate_receipt(with_pulse)
    tests["terminal_with_done_pulse_also_valid"] = "pass"
    for key, invalid in (("b_pending", "1"), ("rd_pending", "1"), ("wr_pending", "1"),
                         ("board_status", str(0x36)), ("csr_status", "0"), ("completed", "6"),
                         ("last_node", "7"), ("csr_cycles_low", "999"),
                         ("poll_timed_out", "1"), ("pc_verified_words", "63"),
                         ("evidence_kind", "in_memory_test_only")):
        broken = valid_receipt.copy()
        broken[key] = invalid
        try:
            validate_receipt(broken)
        except VerificationError:
            tests[f"terminal_bad_{key}"] = "correctly_rejected"
        else:
            raise VerificationError(f"self-test terminal {key}: bad status incorrectly accepted")
    out.mkdir(parents=True, exist_ok=True)
    (out / "verifier_selftest.json").write_text(json.dumps({"pass": True, "hardware_access": False,
                                                            "cases": tests}, indent=2) + "\n")
    print(f"SELFTEST_PASS: {len(tests)} cases; no hardware access")

def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=("prepare", "verify", "selftest"))
    parser.add_argument("--core", type=Path, default=CORE)
    parser.add_argument("--out", type=Path, default=HERE / "prepared")
    parser.add_argument("--run", type=Path)
    args = parser.parse_args()
    try:
        if args.command == "prepare":
            prepare(args.core.resolve(), args.out.resolve())
        elif args.command == "selftest":
            selftest(args.core.resolve(), args.out.resolve())
        else:
            need(args.run is not None, "--run is required for verify")
            result = verify(args.core.resolve(), args.run.resolve())
            (args.run / "verification.json").write_text(json.dumps(result, indent=2, allow_nan=False) + "\n")
            print(f"BOARD_VERIFY_PASS: A16 1024 + copy 1024 exact; DIV 1024; SQRT 1024; unchanged 5120 words; cycles={result['cycles']}")
        return 0
    except (OSError, ValueError, KeyError, TypeError, struct.error) as exc:
        if args.command == "verify" and args.run and args.run.is_dir():
            (args.run / "verification.json").write_text(json.dumps({"pass": False, "error": str(exc)}, indent=2) + "\n")
        print(f"VERIFY_FAIL: {exc}", file=sys.stderr)
        return 1

if __name__ == "__main__":
    raise SystemExit(main())
