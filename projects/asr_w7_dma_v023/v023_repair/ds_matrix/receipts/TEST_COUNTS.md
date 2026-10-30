# Test count / rc receipt

- `logs/commands.log`: 62 commands, all `rc=0`.
- 23 build commands, 27 `run_*` RTL/regression groups, 12 auxiliary commands
  (2 skill selftests, 2 golden regen, 2 golden compare, 6 trace/ledger/activity).
- `logs/metrics.txt` is rebuilt by `python3 scripts/collect_metrics.py`.
- Key RTL groups:
  - cache_pipe, strobe, dma_multi, storage_unit, storage_axi
  - engine PIPE 3/4/5/6 K96 C0; PIPE4 K96 C1; seeds 1/2/3
  - K1, multi-N N64, edge M17 N19 K33, positions 0xCCCC clip=1, write backpressure, read error, write error, bad parity
  - V020 baseline fast/C1/backpressure (read-only work RTL)
  - AXI cluster K32, AXI cluster K96 C1
  - Icarus K32 PIPE4 cross-check (4147 cycles, same as Verilator)
- Golden regeneration: `eng_k1` and `eng_c1` `init.hex`/`exp_c.txt` are
  byte-identical to the fixtures.
- Traffic/activity: 2 trace generations, 2 traffic-ledger analyses,
  2 module-activity renders; both skills' own selftests pass.
