# ds_matrix — V0.23 matrix P2 unified candidate

Logic-simulation task only.  No synthesis, Vivado, DRC/STA, board, VNC,
network or push.  Original `work/`, ZIP, old competition repository and other
worker directories are read-only.

Start here:

- `REPORT.md` — results, before/after, AXI/traffic/activity evidence, limits.
- `INTERFACE.md` — module/port contract and plan-wrapper adaptation.
- `FINDINGS.md` / `FINDINGS.jsonl` — per-finding evidence and the real bug
  found by the old-C regression.
- `result.json` — machine-readable status, hashes, test metrics.
- `progress.json` — phase status.
- `candidate/rtl/` — `block_engine_prefetch_v2`, `block_storage_stream_v2`,
  `operand_banks_dual_v2`, `c_cache_banked4_pipe`, `axi_dma_v020_multi_v2`,
  `matrix_p2_cluster_v2`, plus unmodified reference copies.
- `tests/`, `fixtures/`, `logs/` — BFM, directed tests, independent golden and
  every command/rc.
- `traffic/`, `activity/` — traffic-ledger reports and offline activity
  waveforms from the real `valid&&ready` trace.

Key measured result (same fixture/BFM, M64 N32 K96 C=0):

| implementation | cycles |
|---|---:|
| V020 baseline | 11839 |
| ds_storage_overlap V1 | 5896 (reported) |
| this candidate PIPE=4 | **4552** |

Reproduce:

```bash
bash scripts/run_all.sh
python3 scripts/collect_metrics.py
```

No full-model, timing, CDC or physical-DDR claim is made.  The old-C case
exposed a real C-cache slot-base bug; it is fixed and retained in the
regression.
