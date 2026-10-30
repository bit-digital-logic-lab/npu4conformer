# INTERFACE — V0.23 numeric closeout (vector/FMA/approx)

Status: local logic-simulation integration candidate. It is **not** a full-model
or board acceptance. Only the vector numerical path (op17 FMA, op3 DIV, op4
SQRT) is integrated and exercised here.

## 1. Provenance and read-only rule

- `snapshot/integrated/` is a verbatim copy of the read-only
  `v023_repair/integrated` RTL/TB/script snapshot used as the base.
- `rtl/` is the working copy. `primary_stream_fix`, `work/`, the ZIP and every
  other worker directory were not modified.
- Real numeric cores replace the compile-only forbidden stub:
  - `rtl/asr_fma_ip.sv` and `rtl/fp32_fma_pipe.sv` — copied from
    `gemini_fma_round2/candidate/`; SHA-256 matches the round-2 candidate and
    the primary-acceptance result.
  - `rtl/approx_div_sqrt.sv`, `approx_recip_lut.sv`, `approx_rsqrt_lut.sv` —
    copied from `gemini_approx_round2/candidate/rtl/`; SHA-256 matches the
    round-2 candidate and the primary-acceptance result.
- `rtl/fma_forbidden_stub.sv` is deleted. It is not present in the delivered
  filelist and `scripts/check_unique_modules.py` asserts its absence.

Numeric source SHA-256 (full values in `reports/NUMERIC_SOURCE_SHA256.txt`):

| file | SHA-256 |
|---|---|
| `rtl/fp32_fma_pipe.sv` | `1ed8801a4536ad79c385b90033d5dbd76ad58eed04288a7c500a26e0a740ab12` |
| `rtl/asr_fma_ip.sv` | `634eea1a15d1f8dbc7a2f8bae8eebd2b0e892da5978ed974ccb7645ff9b10599` |
| `rtl/approx_div_sqrt.sv` | `444fa2a42f47a7cde2ad736ead3177225319c6af3bb1c2ab27309233bee7a864` |
| `rtl/approx_recip_lut.sv` | `b5d1ee5cbaca06a55ce6da67fc6c0fbbd88869c6e6aa5508f1c909c03bb4f41a` |
| `rtl/approx_rsqrt_lut.sv` | `cf0d0d03ec839b138acad933fe4561975e0690180ea1099721df3e33ec07e153` |

## 2. Unique build

Entry: `filelist_closeout_numeric.f`.

- Exactly one definition of `asr_fma_ip`, `fp32_fma_pipe`, `approx_div_sqrt`,
  `ddr_layout_engine`, `ddr_vector_engine_pipe`, `task_queue` and every other
  delivered module.
- The old `fma_forbidden_stub.sv` is removed; op17 now reaches the real
  round-2 FMA core.
- `optional/approx/*` and the old integrated experiment are **not** added;
  the three round-2 approx files are copied under unique names (their module
  names were already unique).
- `scripts/check_unique_modules.py` parses the filelist and writes
  `reports/unique_modules.json`; it fails on any duplicate module, missing
  required module, or the forbidden stub.

## 3. RTL changes relative to the integrated snapshot

### 3.1 `ddr_vector_engine_pipe`

- New `abort` input and `aborted` output (one-cycle `done` still exists).
- `approx_div_sqrt` is instantiated with `.flush(core_flush)`; the round-2
  module’s default is retained for legacy callers but this path is explicit.
- Abort semantics:
  - the FMA/approx/ALU/lane pipelines see a one-cycle `core_flush`
    (`aresetn/rst_n = rst_n && !core_flush`);
  - no new load chunk starts and no new AW starts;
  - an already accepted read burst is drained; an already accepted write burst
    is fully drained (W beats and B response) before `done`;
  - computed-but-unwritten results are dropped; `done` is asserted only when
    `ls==LIDLE`, `cs==CIDLE`, `ws==WIDLE`, both DMA request ports are ready and
    the write response has returned (the run log prints `done_cycle` and
    `last_b_cycle`).
- `is_fma` still uses the single-outstanding FMA path, so the exact core is
  used one value at a time (II is not claimed for op17).

### 3.2 `v023_vector_axi` / `v023_vector_guard`

- Added `abort`/`abort_done` pass-through ports. All other ports and the
  descriptor ABI are unchanged.

### 3.3 `wc_graph_ctrl` / `wc_graph_top`

- Added `abort` input and `aborted` output.
- On abort the controller stops dispatching, does not mark an aborted child as
  completed, waits for the active child’s `done` (drain), then exits with
  `done=1, aborted=1, fault=0`.
- Abort is propagated to the vector guard. Layout and matrix children do not
  have abort in this delivery; a plan that is aborting while one of those is
  active waits for that child’s normal completion (or its watchdog). This is
  explicitly a vector-path abort result, not a claim of matrix/layout abort.

### 3.4 `v023_integrated_top`

- Added `abort` input and `aborted` output.
- `USE_APPROX_DIV_SQRT` is now forwarded through `wc_graph_top_v023` to the
  vector guard, so the same top can be built for the exact baseline
  (`0`) or the candidate approx path (`1`).
- `abort` is connected to the graph controller and hence to the vector guard.

## 4. Descriptor and data contract used by the graph tests

All descriptors are fetched by the WCPG controller from the parameter window
(`0x1000_8000` / `0x1001_0000`) through the shared AXI read path. The vector
engine then reads operands and writes results through the same AXI port.

Vector descriptor words (unchanged from the delivered vector ABI):

```
word0 magic 0x22564543
word1 op[39:32] (17 FMA, 3 DIV, 4 SQRT) and all scalar/a16/a48/out16 flags 0
word2 A address      word3 B address      word4 C address
word5 D address      word6 total elements word7 period=0
word8..15 zero
```

- FMA (`op=17`): `A=x`, `B=scale`, `C=bias`, single-rounding `x*scale+bias`.
- DIV (`op=3`): `A=numerator`, `B=divisor`.
- SQRT (`op=4`): `A=radicand`; B/C are not read.
- Inputs/outputs live in the arena (`0x0400_0000` window) because the delivered
  vector descriptor checker accepts arena + parameter windows (this is also
  what the integrated vector path used).
- The graph node base is the 512-bit payload address; the filelist and TB never
  bypass the graph to inject node descriptors.

Plan shapes in `fixtures/closeout_meta.json`:

- `PLAN1` at `0x10008000`: `VEC op17 -> VEC op3 -> VEC op4`, dependencies
  `0 -> 1 -> 2`.
- `PLAN2` at `0x10010000`: one 128-element `VEC op17` node for the second
  epoch after abort/reset.

## 5. Exact vs approximate build switch

```bash
# exact baseline: DIV/SQRT on asr_fp32_alu, FMA still real round-2 core
iverilog -g2012 -DUSE_APPROX=0 ... tb/tb_closeout_numeric.sv

# candidate: DIV/SQRT on approx_div_sqrt (flush connected), FMA unchanged
iverilog -g2012 -DUSE_APPROX=1 ... tb/tb_closeout_numeric.sv
```

`v023_integrated_top` parameter `USE_APPROX_DIV_SQRT` selects the same behavior
for an integrated build.

## 6. Reproduce

```bash
bash run_all.sh
```

It runs sequentially (no parallel compile), uses `timeout` on every simulation
and the in-TB cycle watchdog, and writes `logs/rc.txt`, `logs/check.log`,
`reports/check_summary.json`, `reports/unique_modules.json`,
`SHA256SUMS.txt` and source SHA files.

## 7. Explicit limits

- Graph-level numerical coverage is a representative subset: 2,048 FMA
  (including every non-normal vector and every bias=0 tie/cancellation vector
  from the 6,734 mode-1 set), 512 DIV and 512 SQRT (stratified from the
  7,005/4,002 safe sets, including the 1/31.9998 DIV boundary and max-finite
  SQRT). The full 8,734/15,168 core suites are cited from the independently
  passed round-2 primary acceptance, not re-labelled as graph results.
- No full 591-tensor DAG, sealed-payload re-lowering, host executor, ONNX
  check, WER/CER, CDC, synthesis, STA, board or VNC run.
- No claim that the ~16.6k vs ~45.8k vector-engine cycles are full-model
  latency or board frequency. They are the same plan/load logic-cycle counts.
