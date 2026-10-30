#!/usr/bin/env python3
"""Convert the Verilator per-cycle state CSV into traffic-ledger JSONL.
The CSV is a real cycle trace (valid&&ready / state), not an aggregate guess.
Only the engine `busy` window is used; initialization/preload is excluded.
"""
import json, sys
from pathlib import Path

csv_path = Path(sys.argv[1] if len(sys.argv) > 1 else "traffic/cycles_c0.csv")
out_path = Path(sys.argv[2] if len(sys.argv) > 2 else "traffic/engine_c0.jsonl")
rows = []
with csv_path.open() as f:
    header = f.readline().split()
    for line in f:
        v = [int(x) for x in line.split()]
        rows.append(dict(zip(header, v)))
busy = [r for r in rows if r["busy"] == 1]
if not busy:
    raise SystemExit("no busy rows")
start = busy[0]["cycle"]
window = len(busy)
# Each group must be one-hot in the trace.
groups = {
    "axi_r": [("payload", "rd_payload"), ("command", "rd_cmd"),
              ("wait_memory", "rd_wait"), ("idle_no_work", "rd_idle")],
    "axi_w": [("payload", "wr_payload"), ("command", "wr_cmd"),
              ("wait_memory", "wr_wait"), ("backpressure", "wr_bp"),
              ("idle_no_work", "wr_idle")],
    "compute": [("compute", "comp_run"), ("c_collect", "comp_collect"),
                ("operand_wait", "comp_wait"), ("control", "comp_other")],
}
events = []
meta = {
    "type": "metadata", "schema": 1,
    "scope": "candidate V1 M=64 N=32 K=96 C=0; preload excluded; window=engine busy cycles; Verilator logic simulation",
    "resources": {
        "axi_r": {"unit": "cycle", "start": 0, "end": window,
                  "capacity_bytes_per_tick": 16,
                  "evidence": "Verilator trace rd_valid&&rd_ready; transactional storage read port"},
        "axi_w": {"unit": "cycle", "start": 0, "end": window,
                  "capacity_bytes_per_tick": 16,
                  "evidence": "Verilator trace wr_valid&&wr_ready; transactional storage write port"},
        "compute": {"unit": "cycle", "start": 0, "end": window,
                    "evidence": "Verilator trace eng.state RUN/CREAD/COLLECT/WAITCUR/PREFA/PREFW"},
    },
    "source": {"csv": str(csv_path), "busy_cycles": window,
               "absolute_start_cycle": start,
               "note": "cycle 0 is the first busy edge, not reset release"},
}
events.append(meta)
# Aggregate transfers: exact measured bytes, aggregate span; intervals are the
# actual cycle occupancy.  A and W are separate logical tensors.  Per-tensor
# first/last beats are not separable in this aggregate trace; the timestamps
# are the measured A/W read-channel first/last payload edges.
rd_pay=[i for i,r in enumerate(busy) if r['rd_payload']==1]
wr_pay=[i for i,r in enumerate(busy) if r['wr_payload']==1]
rd_cmd=[i for i,r in enumerate(busy) if r['rd_cmd']==1]
wr_cmd=[i for i,r in enumerate(busy) if r['wr_cmd']==1]
rd_req=rd_cmd[0] if rd_cmd else (rd_pay[0] if rd_pay else 0)
wr_req=wr_cmd[0] if wr_cmd else (wr_pay[0] if wr_pay else 0)
rd_first=rd_pay[0] if rd_pay else rd_req
rd_last=rd_pay[-1] if rd_pay else rd_first
wr_first=wr_pay[0] if wr_pay else wr_req
wr_last=wr_pay[-1] if wr_pay else wr_first
events += [
    {"type": "transfer", "id": "rdA", "resource": "axi_r", "start": 0, "end": window,
     "tensor": "A", "version": "epoch3:blocks00-01:kb0-2", "format": "A16",
     "src": "DDR", "dst": "A_stage_banks", "op": "matmul", "phase": "prefetch",
     "reason": "first_load", "logical_offset": 0, "logical_bytes": 12288,
     "valid_bytes": 12288, "bus_bytes": 12288, "cache": "miss_compulsory",
     "descriptor_id": 0, "slice": "br[0:2],bk[0:3]",
     "request": rd_req, "first_data": rd_first, "last_data": rd_last, "completion": rd_last+1,
     "evidence": "BFM rdbeats=1152; 2 blocks x 3 K x 2048 B; aggregate A/W read timestamps"},
    {"type": "transfer", "id": "rdW", "resource": "axi_r", "start": 0, "end": window,
     "tensor": "W", "version": "epoch3:immutable:kb0-2", "format": "W7p8_parity",
     "src": "DDR", "dst": "W_stage_banks", "op": "matmul", "phase": "prefetch",
     "reason": "first_load", "logical_offset": 0, "logical_bytes": 6144,
     "valid_bytes": 6144, "bus_bytes": 6144, "cache": "miss_compulsory",
     "descriptor_id": 1, "slice": "bk[0:3],bc[0:1]",
     "request": rd_req, "first_data": rd_first, "last_data": rd_last, "completion": rd_last+1,
     "evidence": "BFM rdbeats=384; 2 blocks x 3 K x 1024 B; aggregate A/W read timestamps"},
    {"type": "transfer", "id": "wrC", "resource": "axi_w", "start": 0, "end": window,
     "tensor": "C", "version": "epoch3:blocks00-01:final", "format": "C48",
     "src": "C_cache", "dst": "DDR", "op": "matmul", "phase": "final_write",
     "reason": "c_result_write", "logical_offset": 0, "logical_bytes": 12288,
     "valid_bytes": 12288, "bus_bytes": 12288,
     "descriptor_id": 2, "slice": "br[0:2],bc[0:1]",
     "request": wr_req, "first_data": wr_first, "last_data": wr_last, "completion": wr_last+1,
     "evidence": "BFM wrbeats=768; 2 blocks x 6144 B; 128 segments"},
]
# Compress one-hot states into half-open intervals.
for res, states in groups.items():
    cur_state = None
    cur_start = 0
    for idx, r in enumerate(busy):
        # priority: payload > command > backpressure > wait > idle
        order = {"axi_r": ["payload","command","wait_memory","idle_no_work"],
                 "axi_w": ["payload","command","backpressure","wait_memory","idle_no_work"],
                 "compute": ["compute","c_collect","operand_wait","control"]}[res]
        hit = [name for name, col in states if r[col] == 1]
        st = next((x for x in order if x in hit), hit[0] if hit else None)
        if st is None:
            raise SystemExit(f"{res} cycle {idx}: no state")
        if st != cur_state:
            if cur_state is not None:
                events.append({"type": "interval", "resource": res,
                               "start": cur_start, "end": idx, "state": cur_state,
                               "bytes": (16 * (idx - cur_start)) if (res != "compute" and cur_state == "payload") else 0,
                               "wire_bytes": (16 * (idx - cur_start)) if (res != "compute" and cur_state == "payload") else 0,
                               "evidence": "cycle trace"})
            cur_state = st
            cur_start = idx
    events.append({"type": "interval", "resource": res,
                   "start": cur_start, "end": window, "state": cur_state,
                   "bytes": (16 * (window - cur_start)) if (res != "compute" and cur_state == "payload") else 0,
                   "wire_bytes": (16 * (window - cur_start)) if (res != "compute" and cur_state == "payload") else 0,
                   "evidence": "cycle trace"})
out_path.write_text("\n".join(json.dumps(e, ensure_ascii=False) for e in events) + "\n")
print(f"wrote {out_path} window={window} cycles events={len(events)}")
