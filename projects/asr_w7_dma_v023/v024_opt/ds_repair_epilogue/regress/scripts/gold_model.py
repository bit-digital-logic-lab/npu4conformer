"""Independent Python gold for the v024 per-column epilogue.

This model is intentionally written from the interface contract, not from the
RTL.  It uses ref/refmodel.py (the v023 independent exact FP32 model, copied
read-only from primary_stream_fix) for integer->FP32, single-rounding FMA,
ReLU and FP32->INT16.  No RTL file is imported or parsed.

Contract implemented:
  * C48 signed 48-bit -> FP32 RNE/FTZ
  * if cfg_fma_mode==0: bypass; ==2: fma(x,scale,0); else fma(x,scale,bias)
  * relu: NaN -> 0x7fc00000; sign or zero -> +0
  * A16 = f32_to_i16_rne_sat (NaN -> 0)
  * per-column table hit if cfg_table_en, cval_bc == cfg_bc, bank bc matches,
    cval_col[1:0]==0, column in 0..31 and the entry valid; otherwise scalar
    preload (if valid) else cfg_scale/cfg_bias.
"""

from __future__ import annotations

import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, os.path.join(ROOT, "ref"))
import refmodel as R  # noqa: E402


def _s48(v: int) -> int:
    v &= (1 << 48) - 1
    return v - (1 << 48) if v >= (1 << 47) else v


def _relu(bits: int) -> int:
    if R.is_nan(bits):
        return R.FP32_QNAN
    if (bits >> 31) or R.is_zero(bits):
        return 0
    return bits & 0xFFFFFFFF


class Gold:
    def __init__(self):
        self.cfg = {
            "mode": 0, "relu": 0, "spill48": 0, "spillfp32": 0,
            "table_en": 0, "bank": 0, "bc": 0,
            "scale": 0x3F800000, "bias": 0,
        }
        self.loaded = False
        self.pre_scale = None
        self.pre_bias = None
        self.tbl = {0: {}, 1: {}}          # (col, kind) -> value
        self.bank_bc = {0: None, 1: None}
        self.epoch = 0
        self.a16 = {}                      # tag -> (data64, last)
        self.fp32 = {}                     # tag -> (data128, last)
        self.spill = {}                    # tag -> (data192, last)
        self.epoch_of_tag = {}
        self.block_a16 = []                # current block's A16 beats for packing
        self.packed = {}                   # first tag -> (data128, tag, last)

    # ---- table / parameter state -----------------------------------------
    def apply_param(self, p):
        if not p.get("accept", 1):
            return
        addr = int(p["addr"]) & 0xFF
        data = int(p["data"]) & 0xFFFFFFFF
        if addr < 2:
            if addr == 0:
                self.pre_scale = data
            else:
                self.pre_bias = data
            return
        bank = (addr >> 6) & 1
        kind = (addr >> 5) & 1
        col = addr & 31
        self.tbl[bank][(col, kind)] = data
        self.bank_bc[bank] = int(p["bc"]) & 0xFFFF

    def abort(self):
        self.loaded = False
        self.pre_scale = None
        self.pre_bias = None
        self.tbl = {0: {}, 1: {}}
        self.bank_bc = {0: None, 1: None}
        self._flush_block()
        self.epoch += 1

    def cfg_set(self, c):
        self.cfg = {
            "mode": int(c["mode"]),
            "relu": int(c["relu"]),
            "spill48": int(c["spill48"]),
            "spillfp32": int(c["spillfp32"]),
            "table_en": int(c["table_en"]),
            "bank": int(c["bank"]),
            "bc": int(c["bc"]) & 0xFFFF,
            "scale": int(c["scale"]) & 0xFFFFFFFF,
            "bias": int(c["bias"]) & 0xFFFFFFFF,
        }
        self.loaded = True

    # ---- per-beat arithmetic ---------------------------------------------
    def scalar_pair(self):
        s = self.pre_scale if self.pre_scale is not None else self.cfg["scale"]
        b = self.pre_bias if self.pre_bias is not None else self.cfg["bias"]
        return s, b

    def lookup(self, beat, lane):
        col = (int(beat["col"]) + lane) & 31
        if not self.cfg["table_en"] or not self.loaded:
            return self.scalar_pair()
        if int(beat["bc"]) & 0xFFFF != self.cfg["bc"]:
            return self.scalar_pair()
        bank = self.cfg["bank"] & 1
        if self.bank_bc.get(bank) != self.cfg["bc"]:
            return self.scalar_pair()
        if int(beat["col"]) & 3:
            return self.scalar_pair()
        s = self.tbl[bank].get((col, 0))
        b = self.tbl[bank].get((col, 1))
        ss, bb = self.scalar_pair()
        return (s if s is not None else ss, b if b is not None else bb)

    def beat(self, beat):
        lanes = [int(beat[f"l{k}"]) & ((1 << 48) - 1) for k in range(4)]
        a16 = 0
        fp32 = 0
        for lane in range(4):
            x = R.i48_to_f32_bits(_s48(lanes[lane]))
            s, b = self.lookup(beat, lane)
            if self.cfg["mode"] == 0:
                y = x
            elif self.cfg["mode"] == 2:
                y = R.fma_bits(x, s, 0, ftz=True)
            else:
                y = R.fma_bits(x, s, b, ftz=True)
            if self.cfg["relu"]:
                y = _relu(y)
            fp32 |= (y & 0xFFFFFFFF) << (32 * lane)
            a16 |= (R.f32_to_i16(y) & 0xFFFF) << (16 * lane)
        tag = int(beat["tag"]) & 0xFFFF
        last = int(beat["last"]) & 1
        self.a16[tag] = (a16, last)
        if self.cfg["spillfp32"]:
            self.fp32[tag] = (fp32, last)
        self.epoch_of_tag[tag] = self.epoch
        if self.cfg["spill48"]:
            spill = 0
            for lane in range(4):
                spill |= (lanes[lane] & ((1 << 48) - 1)) << (48 * lane)
            self.spill[tag] = (spill, last)
        self.block_a16.append((tag, a16, last))
        if last:
            self._flush_block()

    def _flush_block(self):
        for i in range(0, len(self.block_a16), 2):
            tag, a16, last = self.block_a16[i]
            if i + 1 < len(self.block_a16):
                _, a16b, lastb = self.block_a16[i + 1]
                data = (a16 & ((1 << 64) - 1)) | ((a16b & ((1 << 64) - 1)) << 64)
                pl = lastb
            else:
                data = a16 & ((1 << 64) - 1)
                pl = 1
            self.packed[tag] = (data, tag, pl)
        self.block_a16 = []


def expected(scenario):
    g = Gold()
    events = scenario["events"]
    params = sorted(enumerate(scenario.get("params", [])),
                    key=lambda kv: (kv[1].get("after", 0), kv[0]))
    applied = set()
    beats_seen = 0
    pending_cfg = None

    def apply_due():
        nonlocal applied
        for idx, p in params:
            if idx in applied:
                continue
            if int(p.get("after", 0)) <= beats_seen:
                g.apply_param(p)
                applied.add(idx)
            else:
                break

    apply_due()
    for ev in events:
        op = ev["op"]
        if op == "BEAT":
            apply_due()
            g.beat(ev["beat"])
            beats_seen += 1
            apply_due()
        elif op == "ABORT":
            apply_due()
            g.abort()
        elif op == "CFG":
            apply_due()
            g.cfg_set(ev["cfg"])
        elif op == "CFG_START":
            pending_cfg = ev["cfg"]
        elif op == "CFG_APPLY":
            apply_due()
            if pending_cfg is None:
                pending_cfg = ev.get("cfg")
            g.cfg_set(pending_cfg)
            pending_cfg = None
        else:
            raise ValueError(f"unknown event {op}")
    g._flush_block()
    return {
        "a16": g.a16,
        "packed": g.packed,
        "fp32": g.fp32,
        "spill": g.spill,
        "epoch_of_tag": g.epoch_of_tag,
        "epochs": g.epoch + 1,
    }
