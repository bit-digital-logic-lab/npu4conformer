#!/usr/bin/env python3
"""Generate random legal/illegal descriptor traffic for the storage harness.

One line = 30 hex fields consumed by tb_storage_equiv.sv.  Cases are derived
from a valid A/B/C descriptor, then mutated one field at a time so the
original and candidate must agree on both accept and reject paths.
"""
from pathlib import Path

HERE = Path(__file__).resolve().parents[1]
OUT = HERE / "fixtures" / "storage_stim.hex"

ARENA_BASE = 0x03000000
ARENA_END = 0x08000000
PARAM_BASE = 0x10000000
PARAM_END = 0x40000000

# flag bits
RERR = 1 << 0
RIDX = 1 << 1
OIDX = 1 << 2
OLST = 1 << 3
ABH = 1 << 4
ABD = 1 << 5
WERR = 1 << 6
GAP = 1 << 7
RRST = 1 << 8
WRST = 1 << 9
SRST = 1 << 10
SWST = 1 << 11

BASE = dict(
    a_base=0x03000000, b_base=0x03010000, c_base=0x03020000,
    cfg_epoch=0x12345678, m=64, n=64, k=64, cfg_layer=7,
    a_id=1, b_id=2, c_id=3, cfg_allowed=1, c_valid=1, c_completed=0,
    param_end=0x20000000,
)

cases = []

def add(name, **kw):
    d = dict(BASE)
    d.update(kw)
    cases.append((name, d))

def desc(kind, row=0, col=0, write=0, flags=0, seed=1, **kw):
    d = dict(BASE)
    d.update(kw)
    enc = {"A": 0, "B": 1, "C": 2}[kind]
    bytes_ = {0: 2048, 1: 1024, 2: 6144}[enc]
    base = {0: d["a_base"], 1: d["b_base"], 2: d["c_base"]}[enc]
    ncols = ((d["k"] + 31) // 32) if enc == 0 else ((d["n"] + 31) // 32)
    nrows = ((d["k"] + 31) // 32) if enc == 1 else ((d["m"] + 31) // 32)
    expected = base + (row * ncols + col) * bytes_
    matrix = {0: d["a_id"], 1: d["b_id"], 2: d["c_id"]}[enc]
    d.update(dict(
        write=write, enc=enc, req_addr=expected, req_epoch=d["cfg_epoch"],
        req_layer=d["cfg_layer"], req_matrix=matrix, req_row=row, req_col=col,
        req_allowed=d["cfg_allowed"],
        req_completed=1 if write else 0,
        # ABI: reads present req_in_operation=1; writebacks present it as 0.
        block_valid=1, in_op=(0 if write else 1), flags=flags, seed=seed,
    ))
    # Explicit request-field mutations win over the derived defaults.
    for k in ("write", "enc", "req_addr", "req_epoch", "req_layer", "req_matrix",
              "req_row", "req_col", "req_allowed", "req_completed", "block_valid",
              "in_op", "flags", "seed"):
        if k in kw:
            d[k] = kw[k]
    return d

# ---- legal traffic -------------------------------------------------------
for kind in ("A", "B", "C"):
    for row, col in ((0, 0), (0, 1), (1, 0), (1, 1)):
        add(f"legal_{kind}_{row}_{col}", **desc(kind, row, col, seed=row * 4 + col + 1))
# C writes, including the absent-C snapshot (write ABI does not require c_valid)
for row, col in ((0, 0), (1, 1)):
    add(f"legal_C_write_{row}_{col}", **desc("C", row, col, write=1, seed=20 + row * 2 + col))
add("legal_C_write_cvalid0", **desc("C", 0, 0, write=1, c_valid=0, seed=24))
# C read with no valid C: no data, but no fault
add("legal_C_read_absent", **desc("C", 0, 0, c_valid=0, seed=25))
# non-multiple dimensions: last partial block is still a full 32x32 storage block
add("legal_partial_A", **desc("A", 1, 1, m=33, n=35, k=37, seed=26))
add("legal_partial_B", **desc("B", 1, 1, m=33, n=35, k=37, seed=27))
add("legal_partial_C_read", **desc("C", 1, 1, m=33, n=35, k=37, seed=28))
add("legal_partial_C_write", **desc("C", 1, 1, write=1, m=33, n=35, k=37, seed=29))
# B read from the parameter window, exactly inside param_end
add("legal_param_B", **desc("B", 0, 0, b_base=PARAM_BASE, param_end=PARAM_BASE + 0x2000, seed=30))
# allowed_ops=3 is legal when cfg_allowed=3
add("legal_allowed3_A", **desc("A", 0, 0, cfg_allowed=3, req_allowed=3, seed=31))

# ---- field mutations -----------------------------------------------------
add("bad_epoch", **desc("A", 0, 0, req_epoch=0x12345679, seed=40))
add("bad_layer", **desc("A", 0, 0, req_layer=8, seed=41))
add("bad_matrix", **desc("A", 0, 0, req_matrix=9, seed=42))
add("bad_allowed", **desc("A", 0, 0, req_allowed=3, seed=43))
add("bad_block_valid", **desc("A", 0, 0, block_valid=0, seed=44))
add("bad_row", **desc("A", 2, 0, seed=45))
add("bad_col", **desc("A", 0, 2, seed=46))
add("bad_addr_plus16", **desc("A", 0, 0, seed=47))
cases[-1][1]["req_addr"] += 16
add("bad_addr_misaligned", **desc("A", 0, 0, seed=48))
cases[-1][1]["req_addr"] |= 1
add("bad_encoding3", **desc("A", 0, 0, enc=3, seed=49))
add("bad_write_encA", **desc("A", 0, 0, write=1, req_completed=1, seed=50))
add("bad_write_encB", **desc("B", 0, 0, write=1, req_completed=1, seed=51))
add("bad_write_inop", **desc("C", 0, 0, write=1, in_op=1, seed=52))
add("bad_write_completed0", **desc("C", 0, 0, write=1, req_completed=0, seed=53))
add("bad_read_inop", **desc("A", 0, 0, in_op=0, seed=54))
add("bad_read_completed1", **desc("A", 0, 0, req_completed=1, seed=55))
add("bad_C_read_completed1", **desc("C", 0, 0, req_completed=1, seed=56))
add("bad_C_read_cvalid0_completed1", **desc("C", 0, 0, c_valid=0, req_completed=1, seed=57))
# ACL/range boundaries
add("bad_arena_below", **desc("A", 0, 0, a_base=0x02FFF000, seed=58))
add("bad_arena_end_over", **desc("C", 0, 0, c_base=0x07FFF000, seed=59))
add("bad_addr_32bit_overflow", **desc("A", 1, 1, a_base=0xFFFFFF00, seed=60))
add("bad_param_end_over", **desc("B", 0, 0, b_base=PARAM_BASE, param_end=0x40001000, seed=61))
add("bad_param_encA", **desc("A", 0, 0, a_base=PARAM_BASE, param_end=PARAM_BASE + 0x2000, seed=62))
add("bad_param_encC", **desc("C", 0, 0, c_base=PARAM_BASE, param_end=PARAM_BASE + 0x3000, seed=63))
add("bad_param_write_B", **desc("B", 0, 0, write=1, b_base=PARAM_BASE, req_completed=1, param_end=PARAM_BASE + 0x2000, seed=64))

# ---- DMA / stream error and control cases --------------------------------
add("dma_read_error", **desc("A", 0, 0, flags=RERR, seed=70))
add("dma_read_index_bad", **desc("A", 0, 0, flags=RIDX, seed=71))
add("dma_write_error", **desc("C", 0, 0, write=1, flags=WERR, seed=72))
add("write_out_index_bad", **desc("C", 0, 0, write=1, flags=OIDX, seed=73))
add("write_out_last_bad", **desc("C", 0, 0, write=1, flags=OLST, seed=74))
add("abort_at_header", **desc("A", 0, 0, flags=ABH, seed=75))
add("abort_at_data", **desc("A", 0, 0, flags=ABD, seed=76))
add("reset_mid_read", **desc("A", 0, 0, flags=RRST, seed=77))
add("reset_mid_write", **desc("C", 1, 1, write=1, flags=WRST, seed=78))
add("read_backpressure", **desc("A", 1, 0, flags=SRST, seed=79))
add("write_backpressure", **desc("C", 1, 1, write=1, flags=SWST, seed=80))
add("read_req_gap", **desc("A", 0, 1, flags=GAP, seed=81))

# ---- a long mixed sequence (also stresses state cleanup) ------------------
for i in range(12):
    kind = "ABC"[i % 3]
    row, col = (i // 3) % 2, (i // 6) % 2
    add(f"mixed_{i}", **desc(kind, row, col, write=(i % 4 == 2), seed=100 + i))

fields = ["write", "enc", "req_addr", "req_epoch", "req_layer", "req_matrix", "req_row", "req_col",
          "req_allowed", "req_completed", "block_valid", "in_op", "a_base", "b_base", "c_base",
          "cfg_epoch", "m", "n", "k", "cfg_layer", "a_id", "b_id", "c_id", "cfg_allowed",
          "c_valid", "c_completed", "param_end", "flags", "seed", "reserved"]

lines = []
for name, d in cases:
    d = dict(d)
    d.setdefault("reserved", 0)
    d.setdefault("req_allowed", d.get("cfg_allowed", 1))
    d.setdefault("req_completed", 1 if d.get("write") else 0)
    d.setdefault("block_valid", 1)
    d.setdefault("in_op", 0)
    d.setdefault("flags", 0)
    d.setdefault("seed", 1)
    # defaults for descriptors that were mutated after desc()
    if "enc" not in d:
        d["enc"] = 0
    if "req_addr" not in d:
        d["req_addr"] = 0
    if "req_epoch" not in d:
        d["req_epoch"] = d["cfg_epoch"]
    if "req_layer" not in d:
        d["req_layer"] = d["cfg_layer"]
    if "req_matrix" not in d:
        d["req_matrix"] = d["a_id"]
    if "req_row" not in d:
        d["req_row"] = 0
    if "req_col" not in d:
        d["req_col"] = 0
    lines.append(" ".join(f"{int(d.get(f, 0)) & 0xffffffff:08x}" for f in fields))

OUT.write_text("\n".join(lines) + "\n", encoding="ascii")
print(f"wrote {len(lines)} cases to {OUT}")
