# INTERFACE — ds_fma_deep (V0.24)

Status: **published early; contract is latency-variable and ready/valid based.**
Owner: `ds_fma_deep`. Consumers: `ds_vector_fma`, `ds_epilogue_channels`,
`ds_fusion_buffers`, `ds_unified_graph`, `ds_final_organize`.

This file is the only coordination surface. No other worker tree is modified.

## 1. What changed relative to gemini_fma_round2

| Item | gemini_fma_round2 (trusted) | ds_fma_deep V0.24 |
|---|---|---|
| `fp32_fma_pipe` pipeline depth | 4 register stages | **7 register stages** |
| latency `in_valid` -> `out_valid` | 4 cycles | **7 cycles** |
| throughput | II=1 | **II=1 (unchanged)** |
| arithmetic | single-rounding IEEE-754 RNE, FTZ, 129-bit accumulator | **bit-identical behaviour preserved** |
| LZC | 129-iteration linear `find_msb` | **grouped/tree LZC: 9x16 groups + tree lzc16** |
| ports | valid/ready, tag, last, flush | **unchanged (same names/widths)** |

The public port list of `fp32_fma_pipe`, `epilogue_fma_stage`, `asr_fma_ip`,
`epilogue_lane` and `epilogue_stream_engine_v023` is **not changed**. Only the
internal register boundary placement and therefore the latency changes.

## 2. Contract for consumers (important)

1. **Never hard-code 4 cycles.** Drive and consume with `valid`/`ready` and
   `tag`/`last`. Measure latency if you need it.
2. `in_ready` may deassert only according to the pipeline handshake; with
   `out_ready=1` and continuous `in_valid`, `in_ready` stays high and one
   result leaves per cycle (II=1).
3. `out_valid && !out_ready` freezes `out_result`, `out_tag`, `out_last`
   exactly (stability contract).
4. `flush` (synchronous, 1 cycle) clears every valid stage immediately; it
   does not require a drain and does not corrupt the following epoch.
5. `out_tag` / `out_last` are delayed with the data by exactly the same number
   of cycles as the result (single tag pipeline).
6. FTZ / RNE / special-value semantics are unchanged from the trusted model:
   - subnormal inputs and outputs flushed to signed zero (FTZ);
   - canonical qNaN `0x7fc00000`;
   - `inf*0 -> NaN`, `inf + (-inf) -> NaN`;
   - exact non-zero cancellation -> `+0`;
   - `x*0 + c` (c finite non-zero) -> `c` bit-exact bypass.

## 3. Latency budget if you instantiate `epilogue_lane`

`epilogue_lane` = `i48_to_f32` (2) + `epilogue_fma_stage` (**7**) + `relu` (1)
+ `f32_to_i16` (2) = **12 cycles** (previously 9).  `epilogue_stream_engine_v023`
contains no fixed-latency assumption, but any testbench that waits a fixed
number of cycles must be re-derived from the handshake.

`asr_fma_ip` remains a non-blocking AXIS wrapper; its result latency is now 7
cycles instead of 4. The official wrapper contract does not fix the latency,
so no port change is required.

## 4. Pipeline register-boundary map (for integration / timing review)

| Stage | Registered outputs (combinational work *before* the register) |
|---|---|
| S1 | decode/FTZ/special flags, 24x24 mantissa product, exponents, `c_norm`, tag/last |
| S2 | product normalization (1-bit), dominant-operand select (48-bit compare + 10-bit exponent compare), `shift`, `exp_base`, effective sign/sub |
| S3 | 128-bit right alignment shifter + shifted-out sticky OR |
| S4 | 129-bit add/sub with sticky borrow injection |
| S5 | grouped/tree LZC of the 129-bit accumulator (`msb_pos`) |
| S6 | normalization shift + 24-bit mantissa + round bit + normalized sticky + result exponent |
| S7 | RNE round-up, overflow/underflow FTZ, special/zero/bypass mux -> output register |

No stage contains a 129-bit linear priority chain.

## 5. Files a consumer may take

Only files under `candidate/`. SHAs are frozen in `result.json` and
`FILELIST.txt`. `scripts/`, `tests/`, `logs/` are verification artefacts and
are not part of the integration payload.

Candidate `fp32_fma_pipe.sv` SHA-256:
`b062284af692349ac0afe1de14ac0d10f0cbbab97a5b33f849b50a93caccac82`.
The untouched wrappers keep their round-2 SHAs (recorded in `result.json`).

## 6. Per-consumer notes

- **`ds_vector_fma`**: `op17` may issue one element per cycle into
  `fp32_fma_pipe`; observe `in_ready` and consume `out_valid/out_tag`. The pipe
  latency is 7 and is **not** a fixed 4. The `EXTRA_STAGES` latency-insensitivity
  build in your INTERFACE is compatible with this port set. Update your SHA
  table to the candidate SHA above if you take this file.
- **`ds_epilogue_channels`**: the per-column scale/bias table sits outside this
  pipe, so no arithmetic change is required. `epilogue_lane` total latency is
  now 12 (2+7+1+2). Keep `cfg_scale/cfg_bias` stable for beats already accepted;
  a ping-pong config swap still needs the same in-flight rule as before.
- **`ds_fusion_buffers` / `ds_unified_graph`**: if you instantiate
  `epilogue_lane` or `epilogue_stream_engine_v023`, use valid/ready only; the
  lane latency is 12 and the stream engine has no internal fixed-latency
  counter. Do not derive `done` from a 9-cycle lane latency.
- **All**: this task writes only `ds_fma_deep/`. Take the file by SHA; do not
  patch another worker's tree.
