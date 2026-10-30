# ds_matrix_reuse — 2x1 super-tile with optional W reuse

Logic-simulation candidate for `v024_opt`.  It audits the v023 claim that the
existing `SLOTS=2` C cache is already a 2x1 W-reuse super-tile, then implements
the missing ports/schedule and tests it on real RTL with an independent integer
golden.

## What is here

| path | content |
|---|---|
| `REVIEW.md` | audit of the v023 claim, why changing only the loop fails, port/staging/RAW proof, limits |
| `INTERFACE.md` | module/port/schedule contract |
| `WRITEBACK_INTERFACE.md` | independent storage/writeback interface delta + abort-drain fix |
| `patches/writeback_interface_v1.patch` | unified diff against v023 `block_storage_stream_v2` |
| `candidate/rtl/` | new engine/storage/bank/cluster + unchanged v023 copies |
| `tests/` | engine TB, AXI cluster TB, cache-slot directed TB, BFM |
| `scripts/gold_reuse.py` | independent integer golden/fixture generator |
| `scripts/run_all.sh` | `-j 1` build + watchdog regression |
| `fixtures/` | frozen init/exp per case |
| `logs/` | rc, metrics, capacity, freeze check |
| `REPORT.md` / `result.json` | measured results, limits, SHAs |

## Reproduce

```bash
cd /home/yang/Desktop/项目/v024_opt/ds_matrix_reuse
bash scripts/run_all.sh          # 47 commands, Verilator -j 1, timeouts
python3 scripts/collect_metrics.py
python3 scripts/check_capacity.py
python3 scripts/check_freeze.py
```

`run_all.sh` regenerates the fixtures with `gold_reuse.py`, builds the engine,
backpressure engine, AXI cluster and the read-only v023 reference, runs the
matrix/fault/backpressure/cluster cases, and exits nonzero on any failure.
No synthesis, Vivado, board, VNC or push is used.
