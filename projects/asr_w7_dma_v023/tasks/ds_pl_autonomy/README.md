# ds_pl_autonomy — artifact index

Status: candidate implemented and logic-tested; **not** a whole-CASE, matrix
numeric, FMA, board or timing result.

Start here:

* `REPORT.md` — full result, evidence, coverage, non-claims.
* `INTERFACE.md` — WCPL format and port contracts for integration.
* `HOST_CLEARANCE.md` — host-residual ledger and staged clear list.
* `result.json` — machine-readable summary.
* `FINDINGS.jsonl` — 26 findings with evidence/status/action.
* `progress.json` — phase/status/test summary.
* `SOURCE_BASELINE.json` — read-only source, candidate and artifact SHA256.

Evidence:

* `analysis/analysis.json` — 68-program DAG/hazard/temp analysis.
* `analysis/whole68.json`, `analysis/whole68_serial.bin` — compiled 68-node
  control candidate; `analysis/verify_real68.json` PASS.
* `analysis/whole68_roots.bin`, `analysis/verify_roots_strict.json` — rejected
  parallel counter-example (2,278 conflicts).
* `reports/run_all/run_all.json` — all commands, rc and logs; 18 static checks
  + 24 simulations, all pass (root/parallel strict verifier rc=1 is expected).
* `rtl/wc_superplan_ctrl.sv`, `rtl/wc_plan_top_v023.sv`, `rtl/wc_plan_csr.sv`.
* `tb/` — controller, real-chain, before/after, CSR and BFM tests.
* `scripts/run_all.py` — one-command reproduction.

Critical boundary: the 68 closed programs are tensor-name islands (68 inputs
produced outside the closed set); the 591 outside queues and upstream
FusionExecutor/ONNX are absent. The compiled 68-node plan is a verified
control/serialization skeleton, not a runnable whole model.
