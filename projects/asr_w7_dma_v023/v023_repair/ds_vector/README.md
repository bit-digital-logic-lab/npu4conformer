# ds_vector — v023 vector throughput repair

Self-contained candidate + frozen baseline copies + same-load tests.

- `REPORT.md` — what was changed, measured numbers, limitations
- `FINDINGS.md` — detailed observations
- `INTERFACE.md` — engine/approx integration contract
- `result.json` — merged exact/approx/AXI/FMA evidence + SHA
- `candidate/rtl/` — new RTL (default exact; approx wrapper optional)
- `baseline/` — read-only copies of the frozen `work` sources used as reference
- `scripts/` — fixture generation and reproducible test runners
- `logs/` — commands, rc, stdout/stderr

Reproduce:

```bash
python3 scripts/gen_fixtures.py
python3 scripts/run_regression.py
python3 scripts/run_axi.py
python3 scripts/run_approx.py
# or serial: ./run_all.sh
```

Logic simulation only (Icarus). No synthesis/STA/Vivado/board.
