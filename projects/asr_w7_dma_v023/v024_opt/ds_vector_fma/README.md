# ds_vector_fma

v024_opt worker: op17 vector FMA II=1 on the real round-2 `fp32_fma_pipe`,
plus the 4-lane fixed-op short-bank tail/pack fix and fallback removal.

Read in this order:

- `REPORT.md` — RTL changes, independent-reference design, results, limits.
- `INTERFACE.md` — latency-variable ready/valid FMA contract for
  `ds_fma_deep`, descriptor contract, build/test contract.
- `result.json` — machine-readable pass/fail, rc, SHA, tested and unfinished.
- `filelist_vector_fma.f` — the single canonical build entry.
- `logs/rc.txt`, `reports/check.log`, `reports/regression.tsv` — actual run
  evidence (not an old JSON).
- `scripts/` — fixture generator, independent checker, result assembler.
- `USER_UPDATES.md`, `progress.json` — progress notes.

Reproduce (local logic simulation only):

```bash
bash run_all.sh
```

Optional same-input baseline cross-check (old single-outstanding op17):

```bash
bash baseline_compare.sh
```

Not a full-model, synthesis, STA, board or VNC result. `v023_repair`, `work/`,
the ZIP and every other worker directory are read-only.
