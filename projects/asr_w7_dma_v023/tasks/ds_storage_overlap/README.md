# ds_storage_overlap — index

Task: remove whole-block A/W transfer serialization and the C48 collect/write
serialization in the V0.20 storage/engine pair, with real logic-simulation
evidence.  No synthesis, board, network or push.

Start here:

- `REPORT.md` — results, before/after, traffic ledger, limits.
- `INTERFACE.md` — new module port contract and upper-layer adaptation.
- `result.json` — machine-readable status, source SHA, tests, metrics.
- `FINDINGS.jsonl` — per-finding evidence.
- `progress.json` — phase/step status.
- `candidate/rtl/` — `block_storage_stream_v1`, `operand_banks_dual_v1`,
  `block_engine_prefetch_v1` plus unmodified numeric copies.
- `tests/` — transactional DMA BFM, independent integer golden,
  unit/overlap/baseline/AXI testbenches.
- `fixtures/` — deterministic init/expected vectors with manifests.
- `logs/` — all build/run commands, rc, per-test logs, metrics.
- `traffic/` — cycle trace, ledger JSONL and traffic-ledger report.

Reproduce:

```
bash scripts/run_all.sh
bash scripts/run_traffic_ledger.sh
```

Key measured before/after (same fixture, same BFM, logic cycles):

| case | original RTL | candidate |
|---|---:|---:|
| 64x32x96, C=0, fast DDR BFM | 11839 | 5896 |
| 64x32x96, C=1 existing C | 13132 | 6673 |
| 64x32x96, C=0, write backpressure | 34620 | 27673 |

The next bottleneck is C collect (3840 of 5896 busy cycles), not DMA.
