# REPORT — V0.23 numeric closeout: real FMA/approx in the vector graph path

**Date**: 2026-10-29  
**Directory**: `/home/yang/Desktop/项目/v023_repair/ds_closeout_numeric`  
**Scope**: local RTL logic simulation only. No synthesis, no Vivado/STA, no
board, no VNC, no git push. `primary_stream_fix`, `work/`, the original ZIP and
all other worker directories were read-only. This is a **vector-numeric
integration result**, not a full-model or board acceptance.

## 0. Conclusion

The real round-2 FMA core and round-2 approximate DIV/SQRT core are now wired
into the system vector path in this isolated snapshot:

- `fma_forbidden_stub.sv` is deleted and `asr_fma_ip` is the real
  `gemini_fma_round2/candidate` core (`fp32_fma_pipe` + wrapper), with the
  candidate SHA-256 unchanged.
- `approx_div_sqrt` from `gemini_approx_round2/candidate/rtl` is compiled and
  `.flush(core_flush)` is explicitly connected.
- A WCPG plan issues `VEC op17 (FMA) -> VEC op3 (DIV) -> VEC op4 (SQRT)`; the
  graph fetches descriptors from the parameter/DDR window, the vector engine
  reads operands and writes results through the shared AXI128 concentrator.
- Same plan/descriptors/data are run twice: exact baseline
  (`USE_APPROX_DIV_SQRT=0`) and candidate (`=1`).
- Exact path: 2,048/2,048 FMA, 512/512 DIV, 512/512 SQRT bit-exact against the
  independent reference.
- Candidate path: FMA remains bit-exact (same core); DIV max relative error
  **0.11094%**, SQRT max **5.62e-6**, no factor-2/10% case and no >0.2% case.
- Abort and reset both drain without old-epoch output: no AW/B in the
  quiescent window, the old output region is byte-unchanged, and the new epoch
  (128 FMA values) is 128/128 bit-exact.

`result.json` has `pass=true`. That PASS is only for the vector numerical path
described here; it is not a full V0.23/CASE0000 acceptance.

## 1. Stale gate reconciliation

The old `integrated/REPORT.md` says “do not integrate FMA; op17 uses a forbidden
stub” and “do not integrate approx”, based on the first-round failures. Those
findings are superseded by the independently rerun round-2 evidence:

| Evidence | Result |
|---|---|
| `primary_acceptance/round2/result_primary_fma.json` | 8,734 vectors, 0 mismatches, tag/stability 0, pass |
| `primary_acceptance/round2/result_primary_approx.json` | 15,168 vectors, 0 special mismatch; DIV max 0.1114666%, SQRT 5.78e-6, RSQRT 5.72e-6; latency 5, II 1; pass |
| `primary_acceptance/round2/REPORT.md` | states the round-2 FMA/approx pass; stream param contract still separately reported |

This task therefore does not wait on the old first-round gate and does not
relabel a stub as a core. The core SHAs used here are exactly the round-2
candidate SHAs that the primary rerun tested:

```
1ed8801a... fp32_fma_pipe.sv
634eea1a... asr_fma_ip.sv
444fa2a4... approx_div_sqrt.sv
b5d1ee5c... approx_recip_lut.sv
cf0d0d03... approx_rsqrt_lut.sv
```

## 2. What was integrated

Base: a copied snapshot of `v023_repair/integrated` (`snapshot/integrated/`).
The running integrated directory was not modified.

### 2.1 Unique build

`filelist_closeout_numeric.f` is the only build entry. It contains exactly one
`asr_fma_ip` (the real core, not the stub), one `fp32_fma_pipe`, one
`approx_div_sqrt`, one `ddr_layout_engine` (burst candidate), one
`ddr_vector_engine_pipe`, one `task_queue`, and the rest of the integrated
modules. `scripts/check_unique_modules.py` reports:

```
files=38 modules=38 duplicates={} forbidden_stub_present=false
required_present_once: asr_fma_ip=true fp32_fma_pipe=true approx_div_sqrt=true
                       ddr_layout_engine=true ddr_vector_engine_pipe=true task_queue=true
```

### 2.2 RTL edits (all in this directory’s copy)

- `ddr_vector_engine_pipe.sv`
  - `approx_div_sqrt ... .flush(core_flush)`.
  - new `abort` input and `aborted` output; abort flushes the compute pipeline,
    stops new load/AW issue, drains an already accepted read burst and an
    already accepted write burst (W + B), and only then raises `done`.
  - computed-but-unwritten results are dropped; `b_count_at_done` is printed.
- `v023_vector_axi.sv`, `v023_vector_guard.sv`: `abort`/`abort_done`
  pass-through, no descriptor ABI change.
- `wc_graph_ctrl.sv`, `wc_graph_top.sv`: `abort`/`aborted`; abort stops
  dispatch, does not mark an aborted child complete, waits for the active
  child’s drain, then exits `done=1, aborted=1, fault=0`.
- `v023_integrated_top.sv`: `abort`/`aborted` ports and
  `USE_APPROX_DIV_SQRT` forwarded through `wc_graph_top_v023` to the vector
  guard.

Only the vector child has abort. Matrix/layout do not have an abort/drain port
in this delivery; an abort while those are active would wait for their normal
completion or watchdog. This is stated as a limit, not hidden.

## 3. Graph-level test design

### 3.1 Plan and address map

WCPG v2 plan 1 at `0x10008000` (parameter window):

```
node 0 VEC op17 FMA   -> node 1
node 1 VEC op3  DIV   -> node 2
node 2 VEC op4  SQRT  output
```

Descriptors are 512-bit vector payloads at `0x10009000/40/80`; the graph fetch
DMA reads them through the shared AXI. Operands and results use the arena
window (`0x04000000`, the window accepted by the delivered vector descriptor
checker); results are written back through the same shared AXI. Plan 2 at
`0x10010000` is a single 128-element op17 node used after abort/reset.

Exact addresses and counts are in `fixtures/closeout_meta.json` and
`fixtures/closeout_params.svh`.

### 3.2 Vectors and independent reference

Read-only inputs:

- `ds_numeric_adversarial/vectors/fma.vec` (SHA `5a995d68…`),
- `ds_numeric_adversarial/vectors/approx.vec` (SHA `11273f22…`),
- `ds_numeric_adversarial/ref/refmodel.py` (SHA `38eb7ed9…`).

The checker recomputes gold; it does not use RTL or gemini golden code:

- FMA: `refmodel.fma_bits` — exact Fraction, one RNE rounding, FTZ.
- DIV: `refmodel.round_f32(exact Fraction a/b)`.
- SQRT: exact integer-sqrt rounding implemented in the checker.

FMA used 2,048 vectors: all 153 subnormal, 24 zero, 106 Inf and 140 NaN
mode-1 vectors, all 715 bias=0 tie/cancellation cases, plus evenly spaced
normals (1,625 normal total). DIV used 512 stratified safe vectors including
`1.0 / 31.9998` (`0x3f800000 / 0x41fffad2`). SQRT used 512 stratified safe
vectors including max finite `0x7f7fffff`. The full 6,734 mode-1 FMA and the
full 7,005/4,002 safe DIV/SQRT sets are the round-2 core evidence cited above,
not relabeled as graph coverage.

### 3.3 Same-load builds

Both builds use the same `mem_closeout.hex`, the same plan and the same
descriptors and data:

- exact baseline: `-DUSE_APPROX=0`, op3/op4 go to `asr_fp32_alu`;
- candidate: `-DUSE_APPROX=1`, op3/op4 go to `approx_div_sqrt`.
- op17 always uses the real `asr_fma_ip`/`fp32_fma_pipe`.

## 4. Results

### 4.1 Exact baseline vs independent reference

| Op | Vectors | Mismatches | Max ULP |
|---|---:|---:|---:|
| FMA op17 | 2,048 | 0 | 0 |
| DIV op3 | 512 | 0 | 0 |
| SQRT op4 | 512 | 0 | 0 |

The exact DIV/SQRT baseline is the unchanged `asr_fp32_alu`; it is bit-exact on
this normal/finite subset.

### 4.2 Candidate approximate path

FMA is the same real core: 2,048/2,048 bit-exact and 0 differences from the
exact baseline.

DIV/SQRT are approximate by contract; bitwise difference from exact is
expected. The gated result is relative error against the exact reference:

| Op | Vectors | Max rel. error | Mean rel. error | >10% | >0.2% |
|---|---:|---:|---:|---:|---:|
| DIV op3 | 512 | 0.00110940 (0.11094%) | 0.00025164 (0.02516%) | 0 | 0 |
| SQRT op4 | 512 | 5.6229e-6 | 1.0787e-6 | 0 | 0 |

Observed bitwise ULP distances (informational, not a gate for approximate
math): DIV max 17,951 ULP mean 2,933; SQRT max 60 ULP mean 12.5. These are
consistent with the ~0.11%/5.6e-6 relative errors, not with the old factor-2
defect (which was ~100% relative error).

### 4.3 Same-load cycles

| Path | Graph cycles | Vector cycles | Done cycle | Last B response |
|---|---:|---:|---:|---:|
| exact baseline | 45,785 | 16,205 | 45,817 | 45,809 |
| candidate approx | 16,589 | 1,603 | 16,621 | 16,613 |

The difference is dominated by the sequential exact DIV/SQRT ALU versus the
pipelined approx core; op17 FMA remains single-outstanding in both. These are
logic-cycle counts for this plan, not board time, full-model latency or a
frequency claim.

### 4.4 AXI traffic and drain boundary

Both normal runs:

```
rburst=127 wburst=48 rbeats=1972 wbeats=768 tag_err=0
vector read bytes=30720 vector write bytes=12288
b_count_at_done=0 b_after_done=0 aw_after_done=0
```

`last_b_cycle` is 8 cycles before the CSR done edge in each run; the xbar
`b_count` at done is zero. No B or AW occurs after done. The AXI read/write
beats come from the shared port, not from a host-side data path.

## 5. Abort and reset — no old-epoch output

### 5.1 Abort

- abort asserted at cycle 2,500 while `vector_busy=1` (inside the op17 node);
- `abort-drain done=1 abort_done=1 fault=0` at cycle 2,548;
- last B response for the aborted epoch at cycle 2,400, before done;
- a 32-cycle quiescent window after abort: `aw=0 b=0`;
- the old FMA output region was snapshotted at abort done and is byte-identical
  at the end (the TB fails on any change);
- plan 2 starts at 2,603 in a new output region, completes at 3,805 with
  `abort_done=0`, and its 128 FMA values are 128/128 bit-exact;
- `last_b_cycle=3,797` < `done_cycle=3,805`, `b_after_done=0`.

### 5.2 Reset

- reset asserted at cycle 3,000 during the first plan;
- 32-cycle quiescent window after reset: `aw=0 b=0`;
- old FMA output snapshot is unchanged after plan 2;
- plan 2 completes at 4,289 with 128/128 bit-exact FMA values;
- `last_b_cycle=4,281` < `done_cycle=4,289`, `b_after_done=0`.

This demonstrates no old-epoch output after abort/reset in this vector path.
It does not claim matrix/layout abort.

## 6. Patch, filelist, reproducibility

- Integration patch: `patch/closeout_numeric.patch` (1,894 lines, 14 files).
  It adds the five numeric source files, changes the vector/graph/top RTL,
  deletes `rtl/fma_forbidden_stub.sv`, and replaces the unique filelist.
- Unique filelist: `filelist_closeout_numeric.f`
  (`709a4c52…`), 38 files / 38 modules, no duplicates.
- Reproduce: `bash run_all.sh`.
- Compile is sequential (one `iverilog` at a time, `-j1` style); every
  simulation has both `timeout` and an in-TB cycle watchdog.
- Run return codes in `logs/rc.txt`:

```
compile_top rc=0
compile_lint rc=0
exact rc=0 seconds=104
approx rc=0 seconds=39
abort rc=0 seconds=9
reset rc=0 seconds=11
check rc=0
make_result rc=0
make_patch rc=0
```

`compile_lint` is `iverilog -Wall`; it emits width/unused warnings (see
`logs/lint_compile.log`) but no fatal error. Lint is not STA.

## 7. Source SHA-256 (full list in `SHA256SUMS.txt`)

| File | SHA-256 |
|---|---|
| `rtl/fp32_fma_pipe.sv` | `1ed8801a4536ad79c385b90033d5dbd76ad58eed04288a7c500a26e0a740ab12` |
| `rtl/asr_fma_ip.sv` | `634eea1a15d1f8dbc7a2f8bae8eebd2b0e892da5978ed974ccb7645ff9b10599` |
| `rtl/approx_div_sqrt.sv` | `444fa2a42f47a7cde2ad736ead3177225319c6af3bb1c2ab27309233bee7a864` |
| `rtl/approx_recip_lut.sv` | `b5d1ee5cbaca06a55ce6da67fc6c0fbbd88869c6e6aa5508f1c909c03bb4f41a` |
| `rtl/approx_rsqrt_lut.sv` | `cf0d0d03ec839b138acad933fe4561975e0690180ea1099721df3e33ec07e153` |
| `rtl/ddr_vector_engine_pipe.sv` | `234e9c34b9ca6ad5eae94cead08d3030d7c0e838a6720500f21347b66e9bec2e` |
| `rtl/v023_vector_axi.sv` | `02ef8dfa3aadcd84481a6f2bbd856d2f8639afb9c48f617c73106dfee1b38e0c` |
| `rtl/v023_vector_guard.sv` | `7fc69b479afa615c5375943880bfa3c1f948976c7e6666542bf13610102b3b83` |
| `rtl/wc_graph_ctrl.sv` | `b1303d74c95d2ba63aa02b62955b56b81bca5eea46c63d4f12abaf6bde90cb11` |
| `rtl/wc_graph_top.sv` | `410224f05b79c1e1800bcb2c187226765c0ecfbc2101dd91cada2f770a7ba9b6` |
| `rtl/v023_integrated_top.sv` | `dec2f842341472b39e3d1113e63c83f016ab49bc0de84616fbc7ccf6e51d8bd0` |
| `tb/tb_closeout_numeric.sv` | `2517c8fd04d5a83d5f8e26e22eebdef7fded186c7c8e07548dae98e26cc22df3` |
| `filelist_closeout_numeric.f` | `709a4c5250205a6274be5d3ed1cbff94b52f9557b88ce43ebbb6839e90f5af08` |
| `run_all.sh` | `0fdf925469ea6236233273c4e930c361b4d0423e1a214564cc72e449f428e779` |

Gate/input SHA values are recorded in `result.json` and
`reports/UPSTREAM_SHA256.txt`.

## 8. Honest limits

- Graph-level numerical coverage is a representative subset (2,048 FMA +
  512 DIV + 512 SQRT). The full 8,734 FMA and 15,168 approx core suites are
  the independently rerun round-2 primary acceptance, not this graph run.
- This is not CASE0000, not the 591-tensor DAG, not sealed-payload re-lowering,
  not the host executor, not ONNX, not WER/CER.
- Only the vector child has abort/drain. Matrix/layout abort, mixed SEQ +
  direct arbitration, hung-child fault injection, real DDR/PS topology, CDC,
  synthesis/STA and board timing remain out of scope.
- No 300/600 MHz, board-latency or full-model speedup claim. The cycle table is
  the same-plan logic-cycle count only.
- `integrated/` was not modified; the patch/filelist are provided for the final
  integrator to apply deliberately.
