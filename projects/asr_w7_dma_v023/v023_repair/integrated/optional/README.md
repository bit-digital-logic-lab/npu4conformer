# Optional/rejected candidates (not in the default integrated filelist)

The default `filelist_integrated.f` deliberately excludes these. They are kept
for evidence and future repair only; the integration gate does not accept them.

## Approx DIV/SQRT

`optional/approx/` is a snapshot of `gemini_approx_repair/candidate/rtl`
(SHA-256 `298a1fb5...`, luts `b5d1ee5c...`, `cf0d0d03...`). It is structurally
single-tier (5 cycles, II=1, flush, illegal-parameter rejection), but the
independent `ds_numeric_adversarial` run still found:

- DIV factor-2: `1.0 / 31.9998` returns `0x3d7fde3c` (rel. err. 99.881%);
- RSQRT factor-2 at `0x7f7fffff`;
- RSQRT(-0) returns `+inf` instead of `-inf`.

DS_vector's exact path is the default and is used by the accepted chain. To
compile an approximate experiment, add `optional/approx/*.sv` to the filelist
and build `v023_integrated_top` with `USE_APPROX_DIV_SQRT=1`; this is not
accepted and is not exercised by `scripts/run_all.sh`.

## FMA / epilogue stream

Not copied into the default build. `gemini_fma_repair` fixes the single primary
counterexample but the independent audit still reports 137/8,734 FMA mismatches
(tie-even and extreme exponent alignment) and stream tag/backpressure/param/
reconfiguration defects. `work/tests/fma_forbidden_stub.sv` (copied as
`rtl/fma_forbidden_stub.sv`) is compile-only and aborts if op17 is invoked.
No op17/FMA path is claimed by the integrated chain.
