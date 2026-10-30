# ds_control_fixes

V023 control/CSR/error repair worker. Logic simulation only.

- `REPORT.md` — results, evidence, limitations.
- `FINDINGS.md` — per-issue before/after findings.
- `INTERFACE.md` — integration contract for the main agent and matrix/graph workers.
- `candidate/rtl/` — replacement modules.
- `tb/`, `scripts/run_all.sh` — self-contained regression.
- `logs/`, `reports/` — reproducible logs and source/test hashes.

Run:

```bash
bash scripts/run_all.sh
```

Read-only baselines: `work/rtl/` and the referenced old task candidates; their
SHA-256 values are in `reports/SOURCE_SHA256.txt`.
