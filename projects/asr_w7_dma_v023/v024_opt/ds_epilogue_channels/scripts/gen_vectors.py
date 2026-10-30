#!/usr/bin/env python3
"""Deterministic stimulus generator for the v024 per-column epilogue tests.

Writes, for each scenario:
  vectors/<name>.cmd   testbench command stream (CFG/BEAT/ABORT/...)
  vectors/<name>.par   parameter-DMA process stream
  vectors/<name>.json  scenario description consumed by gold_model.py

No random module is used; every value is a pure function of a fixed seed and
the beat index, so the reference lock is reproducible.
"""

from __future__ import annotations

import json
import os

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
VEC = os.path.join(ROOT, "vectors")
os.makedirs(VEC, exist_ok=True)

M48 = (1 << 48) - 1
M64 = (1 << 64) - 1

SCALES = [
    0x3F800000, 0xBF800000, 0x3F000000, 0x40000000, 0x3FC00000, 0x3E800000,
    0x40400000, 0xBF400000, 0x3F800001, 0x3F7FFFFF, 0x40200000, 0xC0000000,
    0x3FA00000, 0x3F200000, 0x40800000, 0xBE800000, 0x3F800000, 0xBF000000,
    0x3F400000, 0x40100000, 0x3F900000, 0xBF800001, 0x3E000000, 0x41000000,
    0xBF7FFFFF, 0x3F600000, 0x3FB00000, 0xC0200000, 0x3F100000, 0x3FF00000,
    0xBEC00000, 0x3F880000,
]
BIASES = [
    0x00000000, 0x3F000000, 0xBF000000, 0x3F800000, 0xBF800000, 0x3E800000,
    0xBF000001, 0x3F7FFFFF, 0x40000000, 0xC0000000, 0x3FC00000, 0xBE800000,
    0x40400000, 0xBF400000, 0x3F800001, 0x00000001, 0x3F000001, 0xBF000001,
    0x3FA00000, 0xBFA00000, 0x3E000000, 0xBE000000, 0x40800000, 0xC0800000,
    0x3F400000, 0xBF400000, 0x3F900000, 0xBF900000, 0x3F600000, 0xBF600000,
    0x3F200000, 0xBF200000,
]


def c48_word(seed: int, idx: int) -> int:
    x = (seed * 0x9E3779B97F4A7C15 + idx * 0xBF58476D1CE4E5B9 + 0x123456789ABC) & M64
    x ^= x >> 30
    x = (x * 0xBF58476D1CE4E5B9) & M64
    x ^= x >> 27
    # Mostly 20-bit signed magnitudes, with periodic large values to exercise
    # saturation and wide integer->FP32 rounding.
    if idx % 37 == 0:
        v = (x & 0x3FFFFFFFFFFF) - 0x200000000000
    else:
        v = (x & 0xFFFFF) - 0x80000
    return v & M48


def table_params(bank: int, bc: int, after: int, scales=None, biases=None,
                 cols=None):
    scales = scales or SCALES
    biases = biases or BIASES
    cols = list(range(32)) if cols is None else cols
    out = []
    for col in cols:
        out.append({
            "after": after, "addr": 0x80 | (bank << 6) | col,
            "bc": bc & 0xFFFF, "data": scales[col] & 0xFFFFFFFF,
            "expect": 1, "maxc": 400, "accept": 1,
        })
    for col in cols:
        out.append({
            "after": after, "addr": 0x80 | (bank << 6) | 0x20 | col,
            "bc": bc & 0xFFFF, "data": biases[col] & 0xFFFFFFFF,
            "expect": 1, "maxc": 400, "accept": 1,
        })
    return out


def legacy_param(addr: int, data: int, after: int = 0):
    return {
        "after": after, "addr": addr & 0xFF, "bc": 0,
        "data": data & 0xFFFFFFFF, "expect": 1, "maxc": 400, "accept": 1,
    }


def reject_param(bank: int, bc: int, col: int, after: int, maxc: int = 8):
    return {
        "after": after, "addr": 0x80 | (bank << 6) | col,
        "bc": bc & 0xFFFF, "data": 0xDEADBEEF, "expect": 0,
        "maxc": maxc, "accept": 0,
    }


class Scenario:
    def __init__(self, name: str, bp: int = 0):
        self.name = name
        self.bp = bp
        self.events = []
        self.params = []
        self.beat_count = 0
        self.expect_param_rejects = 0
        self.expect_table_hits_min = 0
        self.expect_table_misses_min = 0
        self.notes = ""

    def cfg(self, mode=1, relu=0, spill48=0, spillfp32=0, table_en=0,
            bank=0, bc=0, scale=0x3F800000, bias=0, tag=0, pending=False):
        c = {
            "mode": mode, "relu": relu, "spill48": spill48,
            "spillfp32": spillfp32, "table_en": table_en, "bank": bank,
            "bc": bc & 0xFFFF, "scale": scale & 0xFFFFFFFF,
            "bias": bias & 0xFFFFFFFF, "tag": tag & 0xFFFF,
        }
        if pending:
            self.events.append({"op": "CFG_START", "cfg": c})
        else:
            self.events.append({"op": "CFG", "cfg": c})

    def cfg_apply(self):
        self.events.append({"op": "CFG_APPLY"})

    def block(self, n: int, bc: int, seed: int, last_end: bool = True,
              col_pattern=None):
        for i in range(n):
            if col_pattern is None:
                col = (i % 8) * 4
            else:
                col = col_pattern[i % len(col_pattern)]
            ev = {
                "op": "BEAT",
                "beat": {
                    "l0": c48_word(seed, i * 4 + 0),
                    "l1": c48_word(seed, i * 4 + 1),
                    "l2": c48_word(seed, i * 4 + 2),
                    "l3": c48_word(seed, i * 4 + 3),
                    "tag": self.beat_count & 0xFFFF,
                    "bc": bc & 0xFFFF,
                    "col": col & 31,
                    "last": 1 if (last_end and i == n - 1) else 0,
                },
            }
            self.events.append(ev)
            self.beat_count += 1

    def abort(self):
        self.events.append({"op": "ABORT"})

    def add_params(self, ps):
        self.params.extend(ps)


def _barrier_counts(sc: Scenario):
    """For each event index, how many params are due by that event."""
    counts = {}
    beats = 0
    due = 0
    for idx, ev in enumerate(sc.events):
        if ev["op"] == "BEAT":
            beats += 1
        due = sum(1 for p in sc.params if int(p.get("after", 0)) <= beats)
        if ev["op"] in ("CFG", "CFG_START", "CFG_APPLY"):
            counts[idx] = due
    return counts


def write_scenario(sc: Scenario):
    barriers = _barrier_counts(sc)
    cmd_lines = []
    beats = 0
    for idx, ev in enumerate(sc.events):
        if idx in barriers and barriers[idx] > 0:
            cmd_lines.append(f"PARAMBARRIER {barriers[idx]}")
        op = ev["op"]
        if op in ("CFG", "CFG_START"):
            c = ev["cfg"]
            cmd_lines.append(
                "CFG " + " ".join(str(x) for x in [
                    c["mode"], c["relu"], c["spill48"], c["spillfp32"],
                    c["table_en"], c["bank"], c["bc"],
                    f'{c["scale"]:08x}', f'{c["bias"]:08x}', f'{c["tag"]:04x}',
                ])
            ) if op == "CFG" else cmd_lines.append(
                "CFGSTART " + " ".join(str(x) for x in [
                    c["mode"], c["relu"], c["spill48"], c["spillfp32"],
                    c["table_en"], c["bank"], c["bc"],
                    f'{c["scale"]:08x}', f'{c["bias"]:08x}', f'{c["tag"]:04x}',
                ])
            )
        elif op == "CFG_APPLY":
            cmd_lines.append("CFGWAIT")
        elif op == "BEAT":
            b = ev["beat"]
            cmd_lines.append(
                "BEAT " + " ".join([
                    f'{b["l0"]:012x}', f'{b["l1"]:012x}',
                    f'{b["l2"]:012x}', f'{b["l3"]:012x}',
                    f'{b["tag"]:04x}', str(b["bc"]), str(b["col"]),
                    str(b["last"]),
                ])
            )
            beats += 1
        elif op == "ABORT":
            cmd_lines.append("ABORT")
        else:
            raise ValueError(op)
    cmd_lines.append("END")
    with open(os.path.join(VEC, sc.name + ".cmd"), "w") as f:
        f.write("\n".join(cmd_lines) + "\n")
    with open(os.path.join(VEC, sc.name + ".par"), "w") as f:
        for p in sc.params:
            f.write("PARAM %d %02x %d %08x %d %d\n" % (
                p["after"], p["addr"], p["bc"], p["data"],
                p["expect"], p["maxc"]))
        if not sc.params:
            f.write("")
    desc = {
        "name": sc.name,
        "bp": sc.bp,
        "events": sc.events,
        "params": sc.params,
        "expect_param_rejects": sc.expect_param_rejects,
        "expect_table_hits_min": sc.expect_table_hits_min,
        "expect_table_misses_min": sc.expect_table_misses_min,
        "beats": sc.beat_count,
        "notes": sc.notes,
    }
    with open(os.path.join(VEC, sc.name + ".json"), "w") as f:
        json.dump(desc, f, indent=1, sort_keys=True)
    print(f"wrote {sc.name}: beats={sc.beat_count} params={len(sc.params)}")


def build_all():
    scenarios = []

    # A. scalar compatibility + legacy broadcast preload
    s = Scenario("scalar_bp0", 0)
    s.add_params([legacy_param(0, 0x40000000), legacy_param(1, 0xBF000000)])
    s.cfg(mode=1, table_en=0, scale=0x3F800000, bias=0)
    s.block(256, 0, 0xA001)
    s.block(256, 0, 0xA002)
    scenarios.append(s)

    # B. per-column table, ping-pong preload during block0, active-bank reject
    s = Scenario("per_column_bp1", 1)
    s.add_params(table_params(0, 100, 0))
    s.add_params(table_params(1, 200, 64))
    s.add_params([reject_param(0, 100, 0, 128, 8)])
    s.expect_param_rejects = 1
    s.cfg(mode=1, table_en=1, bank=0, bc=100, scale=0x3F800000, bias=0)
    s.block(256, 100, 0xB001)
    s.cfg(mode=1, table_en=1, bank=1, bc=200, scale=0x3F800000, bias=0)
    s.block(256, 200, 0xB002)
    s.expect_table_hits_min = 1
    scenarios.append(s)

    # C. cross-row / cross-block / short tail, bank reuse
    s = Scenario("cross_short_bp1", 1)
    s.add_params(table_params(0, 300, 0))
    s.add_params(table_params(1, 400, 0))
    s.add_params(table_params(0, 500, 260))
    s.cfg(mode=1, table_en=1, bank=0, bc=300, scale=0x3F800000, bias=0)
    s.block(256, 300, 0xC001)
    s.cfg(mode=1, table_en=1, bank=1, bc=400, scale=0x3F800000, bias=0)
    s.block(9, 400, 0xC002)          # 8 beats fill one row, 9th crosses to row 1
    s.cfg(mode=1, table_en=1, bank=0, bc=500, scale=0x3F800000, bias=0)
    s.block(1, 500, 0xC003)
    s.expect_table_hits_min = 1
    scenarios.append(s)

    # D. config request held during a live block: must wait, not corrupt beats
    s = Scenario("config_wait_bp1", 1)
    s.add_params(table_params(0, 600, 0))
    s.add_params(table_params(1, 700, 0))
    s.cfg(mode=1, table_en=1, bank=0, bc=600, scale=0x3F800000, bias=0)
    s.block(40, 600, 0xD001)
    s.cfg(mode=1, table_en=1, bank=1, bc=700, scale=0x3F800000, bias=0,
          pending=True)
    s.block(216, 600, 0xD001)
    s.cfg_apply()
    s.block(128, 700, 0xD002)
    s.expect_table_hits_min = 1
    scenarios.append(s)

    # E. abort mid-block, then recover with scalar config
    s = Scenario("abort_recover", 1)
    s.add_params(table_params(0, 800, 0))
    s.cfg(mode=1, table_en=1, bank=0, bc=800, scale=0x3F800000, bias=0)
    s.block(16, 800, 0xE001, last_end=False)
    s.abort()
    # After abort the table is cleared; the same table_en/bank/bc must miss
    # every entry and fall back to the scalar cfg values.
    s.cfg(mode=1, table_en=1, bank=0, bc=800, scale=0x3F000000, bias=0x3F800000)
    s.block(8, 800, 0xE002)
    s.notes = "abort after 16 beats; pre-abort outputs are compared as a subset"
    s.expect_table_hits_min = 1
    s.expect_table_misses_min = 1
    scenarios.append(s)

    # E2. abort while the optional FP32 channel has pending beats
    s = Scenario("abort_fp32_bp1", 1)
    s.add_params(table_params(0, 1100, 0))
    s.cfg(mode=1, relu=1, spill48=0, spillfp32=1, table_en=1, bank=0,
          bc=1100, scale=0x3F800000, bias=0)
    s.block(16, 1100, 0xE101, last_end=False)
    s.abort()
    s.cfg(mode=1, relu=0, spill48=0, spillfp32=0, table_en=0,
          scale=0x3F000000, bias=0x3F800000)
    s.block(8, 0, 0xE102)
    s.expect_table_hits_min = 1
    s.notes = "abort with FP32 pending; post-abort scalar recovery"
    scenarios.append(s)

    # F. all four output channels random independent backpressure
    s = Scenario("fp32_backpressure", 1)
    s.add_params(table_params(0, 900, 0))
    s.cfg(mode=1, relu=1, spill48=1, spillfp32=1, table_en=1, bank=0,
          bc=900, scale=0x3F800000, bias=0)
    s.block(256, 900, 0xF001)
    s.expect_table_hits_min = 1
    scenarios.append(s)

    # G. long stalls on A16/packed/FP32/spill
    s = Scenario("fp32_long_bp5", 5)
    s.add_params(table_params(1, 950, 0))
    s.cfg(mode=1, relu=1, spill48=1, spillfp32=1, table_en=1, bank=1,
          bc=950, scale=0x3F800000, bias=0)
    s.block(64, 950, 0xF002)
    s.expect_table_hits_min = 1
    scenarios.append(s)

    # H. partial table entries fall back to scalar per column
    s = Scenario("partial_table_bp0", 0)
    s.add_params([legacy_param(0, 0x3F800000), legacy_param(1, 0x3F000000)])
    cols = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15,
            16, 18, 20, 22, 24, 26, 28, 30]
    s.add_params(table_params(0, 1000, 0, cols=cols))
    s.cfg(mode=1, table_en=1, bank=0, bc=1000, scale=0x3F800000, bias=0)
    s.block(32, 1000, 0xF003)
    s.expect_table_hits_min = 1
    s.expect_table_misses_min = 1
    scenarios.append(s)

    # I. legacy bias-only preload (no uninitialized scale), unsupported addr held
    s = Scenario("scalar_bias_only", 0)
    s.add_params([legacy_param(1, 0xBF000000)])
    bad = {
        "after": 0, "addr": 0x02, "bc": 0, "data": 0x11223344,
        "expect": 0, "maxc": 4, "accept": 0,
    }
    s.add_params([bad])
    s.cfg(mode=1, table_en=0, scale=0x3F800000, bias=0)
    s.block(32, 0, 0xF004)
    scenarios.append(s)

    return scenarios


def main():
    scenarios = build_all()
    manifest = []
    for s in scenarios:
        write_scenario(s)
        manifest.append({"name": s.name, "bp": s.bp, "beats": s.beat_count,
                         "params": len(s.params)})
    with open(os.path.join(VEC, "manifest.json"), "w") as f:
        json.dump(manifest, f, indent=1, sort_keys=True)


if __name__ == "__main__":
    main()
