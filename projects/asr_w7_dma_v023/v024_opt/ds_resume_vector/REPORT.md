# REPORT — ds_vector_fma: op17 FMA II=1 + 4-lane short-bank tail fix

**Date**: 2026-10-30  
**Directory**: `/home/yang/Desktop/项目/v024_opt/ds_vector_fma`  
**Model**: `opencode-go/deepseek-v4.1-flash`  
**Scope**: local RTL logic simulation only. No synthesis, no Vivado/STA, no
board, no VNC, no git push. `v023_repair`, `work/`, the ZIP and every other
worker directory are read-only. This is a vector-op17 integration result, not a
full-model or board acceptance.

## 0. Conclusion

The delivered `ds_closeout_numeric` vector engine had two concrete problems in
the reviewed area:

1. op17 (FP32 FMA) was single-outstanding: each element waited for the FMA
   result before the next element was issued, even though the real
   `fp32_fma_pipe` is II=1.
2. the 4-lane fixed-op path was gated to `bank_elems > 8`; short banks fell
   back to a scalar path, and simply removing the gate was unsafe because the
   `flush_wait` collection alignment could drop the first lane groups of a
   short bank.

This delivery:

- Instantiates the real round-2 `fp32_fma_pipe` directly through
  `vector_fma_lane`, issues op17 at **1 element/cycle (II=1, single lane)**,
  drains on `out_valid`, and carries a `{bank,index}` tag that is checked
  against the drain index. Latency is never counted in cycles; a 6–8 stage
  `ds_fma_deep` pipe can replace the core without touching the engine.
- Removes the `bank_elems > 8` fallback for every fixed op. The fix is in the
  collection alignment: the 4-lane path now drains on the lanes' own
  `out_valid` (lane 0 is valid for every issued group) and checks
  `drained_beats == issued_beats` at bank completion, instead of starting a
  fixed-delay drain after the last issue. The partial-issue mask, final
  partial word, 16-bit tail strobe and `lanes_now` pack are exercised for
  totals 1..17 and beyond.
- Keeps the real FMA single-RNE/FTZ numerics and leaves `W7A16C48` and every
  matrix module untouched.
- Re-runs the complete independent 8,734-vector FMA set, the official
  `work/tests/fma_fixture` 1,001-vector fixture, tail lengths 0/1..17/127/255/
  257/1001, scalar/tiled/periodic B, random BFM backpressure, abort/reset new
  epochs, short-bank fixed-op lanes and a latency+3 build. Gold is recomputed
  by `ds_numeric_adversarial/ref/refmodel.py` (exact Fraction/integer), not by
  the RTL or a same-source golden.

The pass/fail evidence is in `result.json`, `reports/check.log`,
`reports/regression.tsv`, `reports/unique_modules.json` and `logs/rc.txt`.
The final state is reported honestly at the bottom of this file.

## 1. Base and provenance

Base: `v023_repair/ds_closeout_numeric` (the newest vector-numeric closeout
REPORT/INTERFACE/RTL/TB/scripts). Copied into this directory; the v023 tree
was not modified.

Numeric cores (copied unchanged, SHA-256):

| file | SHA-256 |
|---|---|
| `rtl/fp32_fma_pipe.sv` | `1ed8801a4536ad79c385b90033d5dbd76ad58eed04288a7c500a26e0a740ab12` |
| `rtl/asr_fma_ip.sv` | `634eea1a15d1f8dbc7a2f8bae8eebd2b0e892da5978ed974ccb7645ff9b10599` |
| `rtl/approx_div_sqrt.sv` | `444fa2a42f47a7cde2ad736ead3177225319c6af3bb1c2ab27309233bee7a864` |

Only `rtl/ddr_vector_engine_pipe.sv` was changed; `rtl/vector_fma_lane.sv` was
added. The single canonical filelist is `filelist_vector_fma.f`; the baseline
comparison uses a separate read-only filelist and is not the deliverable.

## 2. RTL changes

### 2.1 op17: real FMA pipeline, II=1, single lane, ready/valid

Old path (`v023 ds_closeout_numeric`): op17 went through `asr_fma_ip` with
`fma_outstanding` allowing one element at a time. The FMA core was II=1 but the
engine only issued the next element after the previous result was collected.

New path:

```systemverilog
wire fma_issue=(cs==CITER)&&is_fma&&!fault&&!abort_pending&&
  (compute_index<bank_count[cb])&&fma_in_ready;
assign fma_in_valid=fma_issue;
vector_fma_lane #(.EXTRA_STAGES(`FMA_EXTRA_STAGES)) fused(
  .clk(clk),.rst_n(rst_n),.flush(core_flush),
  .in_valid(fma_in_valid),.in_ready(fma_in_ready),
  .in_a(next_a_v[31:0]),.in_b(next_b_v[31:0]),.in_c(next_c_v[31:0]),
  .in_tag({cb,7'd0,compute_index[7:0]}),.in_last(1'b0),
  .out_valid(fma_out_valid),.out_ready(1'b1),.out_result(fma_result),
  .out_tag(fma_out_tag),.out_last());
```

- One element is issued per cycle as long as `fma_in_ready` is high; issue and
  collect are allowed in the same cycle. There is no fixed 4/6/8-cycle counter.
- The result tag `{bank,7'd0,index[7:0]}` is compared with
  `{cb,7'd0,drain_element[7:0]}` on every collect. A mismatch is fault `0x06`.
- `collect_bad` still rejects an invalid numeric flag. FMA itself returns the
  real core's NaN/Inf semantics; `numeric_flags` is zero for op17, as in the
  base.
- Abort/fault raises the one-cycle `core_flush`; the real pipe's valid stages
  are cleared, computed-but-unwritten results are dropped, and the existing
  accepted-read/accepted-write (W+B) drain is preserved.
- `W7A16C48`, the matrix array/PE/RAM modules and the layout engine are not
  changed.

### 2.2 Why single lane first; 4-lane cost evaluation

The 128-bit load path carries four FP32 elements/beat, but the op17 FMA unit is
a 129-bit-accumulator, single-rounding pipeline. A 4-lane FMA would require:

- 4× `fp32_fma_pipe` instances: four 24×24 multipliers, four 129-bit
  align/add accumulators, four LZC/normalization/round-pack cones;
- 4× the pipeline registers and 4× the tag/result muxing, plus a 4-result
  packer;
- four times the DSP/LUT/FF cost of the dominant numeric block, with the same
  single-rounding correctness burden in each lane.

The engine's measured full-8734 run is 21,165 vector cycles for 8,734
elements (2.42 cycles/element), not 1.00; the gap is AXI read/write stalls and
bank turnaround, not only FMA issue. Single-lane II=1 already removes the old
single-outstanding serialization. A 4-lane version would only pay off if the
FMA compute phase were the measured bottleneck; this delivery therefore keeps
one lane and reports the 4× core cost instead of silently claiming a 4-lane
speedup. See section 6 for the same-input baseline comparison.

### 2.3 4-lane fixed-op short-bank bug: root cause and fix

Old code:

```systemverilog
is_wide <= fixed_op && (start_bank_count > 9'd8);
wire collect_wide = (...) && ((issued_beats>=5) ||
  (issue_done && flush_wait==0)) && (drained_beats<issued_beats);
wire issue_partial = ((bank_count-compute_index)<lanes) && (bank_count<=8);
```

For a bank of 2..8 elements, the lane results appear 3 edges after issue, but
collection was armed from the **last** issue (`issue_done` plus a fixed
`flush_wait`) and the partial issue was additionally delayed by `tail_wait`.
By the time collection started, `lane_result_d` had advanced past the first
groups; the packer then read stale/wrong lane values. That is the real
`<=8` mask/pack bug. Deleting only `bank_count > 8` would expose it.

New collection:

```systemverilog
wire lane_group_valid = lane_out_valid[0]; // lane 0 is valid for any group
wire collect_wide = ((cs==CREAD)||(cs==CDRAIN)) && !fault && !abort_pending &&
  lane_group_valid && (drained_beats<issued_beats);
```

- Drain uses the lane's own `out_valid`, not a cycle count.
- `collect_n = lanes_now = min(bank_count-drain_element, lanes)`, so a partial
  final group packs exactly the valid lanes.
- `lane_in_valid` uses the exact `issue_n` mask (1/2/3/4 lanes).
- At bank completion the engine requires `drained_beats+1 == issued_beats`;
  a lost/extra group is fault `0x06` rather than a silent pack.
- `tail_wait` and `issue_partial` are deleted. The `is_wide >8` gate is gone;
  every fixed op (ADD/SUB/MUL/I32_F32/F32_I32/MAX/LT/EQ/ABS/NEG/I48_F32/
  F32_I16) uses the 4-lane path for 1-element to full-bank lengths.
- For 16-bit output the existing `per_word=8`, partial-word write and
  `wr_strobe` tail are retained; totals 1..9/17/127/255/257/1001 are checked.

### 2.4 Latency-variable interface for `ds_fma_deep`

`vector_fma_lane` exposes exactly the `fp32_fma_pipe` ports and is transparent
at `EXTRA_STAGES=0`. The engine only needs:

```
in_valid/in_ready, in_a/b/c, in_tag, in_last
out_valid/out_ready, out_result, out_tag, out_last
flush (one-cycle clear), rst_n
```

The regression builds the same engine with `-DFMA_EXTRA_STAGES=3`, adding
three valid/tag-only elastic stages after the real FMA. The same full 8,734
vectors, official fixture, tails and lane cases must still be bit-exact. This
is the explicit contract for the deep-pipeline task: change latency, keep
ready/valid and in-order tags; do not change the vector engine.

## 3. Test design and independent reference

### 3.1 Graph path and BFM

Every case is one WCPG v2 plan node. The TB writes only CSR START; the graph
controller fetches the 64-byte header, 192-byte node and 512-bit vector
descriptor from the parameter window through the shared AXI128 path. The
vector engine reads A/B/C from the arena and writes D through the same BFM.
No descriptor is injected directly into the engine. The BFM is the delivered
`wc_graph_bfm.sv` (sparse 1 MiB word model, LFSR read/write stall injection);
the same BFM and the same memory image are used for the new and baseline RTL.

### 3.2 Independent gold

`scripts/check_case.py` reads the exact input list per case and recomputes:

- FMA: `refmodel.fma_bits` — exact `Fraction` product + add, one RNE, FTZ,
  canonical NaN/Inf rules;
- MUL/ADD: exact `Fraction` + `round_f32` with explicit NaN/Inf/zero rules
  (for the fixed-op lane tests);
- F32_I16: `refmodel.f32_to_i16` RNE + saturation, packed little-endian.

It then checks that the generator's `gold.hex` agrees with this recomputation
(so a generator bug cannot pass) and compares the RTL dump word-for-word.
`fixtures/manifest.json` freezes the upstream SHAs of `fma.vec`, `refmodel.py`
and the official fixture memory/gold.

### 3.3 Vector selection

- Full 8,734 `fma.vec` rows: mode 1 (6,734) as `x*scale+bias`, mode 2 (1,000)
  as `x*scale+0`, mode 0 (1,000) as `x*1+0` (the original bypass is identical
  for these normal vectors). This uses every row, not a 2,048 subset.
- Tail pattern: specials at indices 0..16 (zeros, ±Inf, NaN, max finite,
  min normal, subnormal, tie/cancellation, extreme exponent) then deterministic
  random finite/special triples; totals 256 (tail 0), 257..273 (tails 1..17),
  383, 511, 513, 1001.
- Operand modes: `bscalar`, `cscalar`, periodic B period 32/128, btiled
  32-element tile 1024/2048 (the delivered ds_vector btiled pattern).
- Official fixture: the 1,001-vector `work/tests/fma_fixture` memory, gold and
  descriptor, driven through the same plan/vector path.
- Fixed-op lanes: MUL/ADD/F32_I16 totals 1..9, 17, 127, 255, 257, 1001.
- Abort/reset: plan 1 is the full 8,734 FMA; abort/reset after 3,000 vector
  busy cycles; plan 2 is a 257-element new-epoch FMA to a different D region.

## 4. Results

<!-- RESULTS_TABLE -->

## 5. Abort / reset and drain boundary

<!-- ABORT_RESULTS -->

## 6. Same-input baseline comparison

<!-- BASELINE_RESULTS -->

## 7. Build, filelist, reproducibility

- Canonical filelist: `filelist_vector_fma.f` (one definition of each module;
  real `asr_fma_ip`/`fp32_fma_pipe`, `vector_fma_lane`, no forbidden stub).
- `scripts/check_unique_modules.py` writes `reports/unique_modules.json` and
  fails on a duplicate/missing module or a forbidden stub.
- Compiles are sequential (`iverilog`, one at a time), every simulation has a
  shell `timeout` and an in-TB cycle watchdog. Reproduce:

```bash
bash run_all.sh
```

- `logs/rc.txt` contains compile/sim return codes; `reports/check.log` contains
  the per-case independent-check lines; `reports/regression.tsv` is the
  machine-readable case table; `result.json` is assembled from those logs, not
  from an old JSON.
- The negative control intentionally corrupts one expected word and requires
  the checker to exit non-zero. It is recorded in
  `reports/negative_control.txt`; an unexpected pass fails the suite.

## 8. Honest limits

- Vector op17 integration and BFM evidence only: not a full 591-tensor DAG,
  not CASE0000, not ONNX, not WER/CER, not the host executor.
- No synthesis/STA/board/VNC/push; no 250/300/600 MHz or whole-model seconds
  claim.
- Matrix `W7A16C48` is untouched and was not re-verified here.
- Single-lane op17 is delivered; a 4-lane FMA is costed, not implemented.
- Multi-tile btiled (period > 32 with coefficient-tile switching) is existing
  engine behaviour and is not changed or claimed; only the delivered
  single-32-element-tile pattern is exercised.
- The 8,734 vectors are a strong adversarial selection, not an exhaustive
  2^96 FMA proof.
- Only the vector child has abort/drain; matrix/layout abort remains outside
  this task.
