# INTERFACE — v024_opt / ds_vector_fma

Status: **in progress** (this file is written before the final RTL/regression is
frozen so the `ds_fma_deep`, `ds_epilogue_channels`, `ds_unified_graph` and
`ds_final_organize` tasks can align early). It will be re-stamped when the
final SHA/rc are known.

Scope: local RTL logic simulation only. No synthesis, no Vivado/STA, no board,
no VNC, no git push. Only this directory is written; `v023_repair`, `work/`,
the ZIP and every other worker directory stay read-only.

## 1. What this task changes

Base: `v023_repair/ds_closeout_numeric` (the newest delivered vector/FMA
numeric closeout), copied verbatim into `rtl/`, `tb/` and `scripts/`. The
numeric cores remain the round-2 candidates:

| file | SHA-256 (copied unchanged) |
|---|---|
| `rtl/fp32_fma_pipe.sv` | `1ed8801a4536ad79c385b90033d5dbd76ad58eed04288a7c500a26e0a740ab12` |
| `rtl/asr_fma_ip.sv` | `634eea1a15d1f8dbc7a2f8bae8eebd2b0e892da5978ed974ccb7645ff9b10599` |
| `rtl/approx_div_sqrt.sv` | `444fa2a42f47a7cde2ad736ead3177225319c6af3bb1c2ab27309233bee7a864` |

Changes are confined to `rtl/ddr_vector_engine_pipe.sv` plus one new wrapper
`rtl/vector_fma_lane.sv`:

1. **op17 FMA is issued II=1, single lane, ready/valid.**
   - The engine now instantiates `fp32_fma_pipe` (through
     `vector_fma_lane`) directly instead of the non-blocking `asr_fma_ip`
     wrapper. It drives `in_valid` / observes `in_ready` and consumes
     `out_valid` / `out_tag`; it does **not** count a fixed number of cycles.
   - A result tag `{bank,7'd0,index[7:0]}` is carried through the pipe and
     checked against the drain index; a tag mismatch is a hard fault.
   - Single-lane issue rate is 1 FP32 element/cycle. A 4-lane variant would
     need four independent FMA cores / 129-bit accumulators; the cost is
     documented in REPORT.md, not paid here. The existing 128-bit beat load
     still moves 4 elements/beat, so the op17 compute phase is intentionally
     **1 element/cycle**, not 4.
   - FMA remains one true RNE rounding (`x*scale+bias`), FTZ, same
     `fp32_fma_pipe` numerics. `W7A16C48` and all matrix RTL are untouched.

2. **4-lane fixed-op short-bank fallback removed.**
   - `is_wide` is no longer gated by `bank_elems > 8`; every fixed op
     (ADD/SUB/MUL/I32_F32/F32_I32/MAX/LT/EQ/ABS/NEG/I48_F32/F32_I16) uses the
     4-lane path for any bank length.
   - The old `tail_wait` / `issue_partial` work-around is deleted. The real
     fix is that collection now starts a fixed number of cycles after the
     **first** issued beat (not after the last one), so short banks do not
     drop the early lane results; partial-issue `lane_in_valid` masks and
     `lanes_now` pack masks remain, including the final partial word and the
     16-bit tail strobe.
   - This is a logic fix, not "delete the >8 condition and hope".

3. **Abort / reset / drain behaviour preserved.** The vector `abort` port,
   one-cycle core flush, accepted-read drain, accepted-write (W+B) drain and
   `done` boundary are unchanged. No AW starts after abort; computed but
   unwritten results are dropped. A new-epoch plan must be bit-exact.

## 2. Latency contract for the FMA deep-pipeline task

`ds_fma_deep` may replace `rtl/fp32_fma_pipe.sv` with a 6–8 stage version.
The vector engine only relies on this port set and protocol:

```
clk, rst_n, flush
in_valid, in_ready, in_a[31:0], in_b[31:0], in_c[31:0],
in_tag[TAG_WIDTH-1:0], in_last
out_valid, out_ready, out_result[31:0], out_tag[TAG_WIDTH-1:0], out_last
```

- Handshake is standard valid/ready on both sides; `in_valid && in_ready`
  transfers one element, `out_valid && out_ready` transfers one result.
- Latency is **not** a parameter of this engine and is never hard-coded.
  The engine instantiates `vector_fma_lane #(.EXTRA_STAGES(...))`; its default
  is 0 (transparent). A regression build with `-DFMA_EXTRA_STAGES=3` inserts
  three extra valid/tag-only pipeline stages around the real FMA to prove the
  engine is latency-insensitive.
- Results are in-order (the pipe is in-order). `out_tag` must equal the tag
  supplied with the corresponding input; the engine faults otherwise.
- `flush` must clear every valid bit within one cycle; results already in
  flight are dropped. The engine uses the same one-cycle `core_flush` for
  abort/fault.
- No assumption is made about 4/6/8 cycles, `in_last`, or tag width beyond
  `TAG_WIDTH=16`. `in_last` is tied 0 and `out_last` ignored by this engine.

If the deeper pipe changes `fp32_fma_pipe`'s SHA, update the SHA table in
`REPORT.md`/`result.json`; do not change this handshake.

## 3. Descriptor contract used by the tests

Unchanged V023 vector ABI, 16 words / 512 bits:

```
word0 magic 0x22564543
word1 op[39:32]=17 (FMA) plus a16/out16/bscalar/ascalar/cscalar/a48/btiled flags
word2 A address (x)       word3 B address (scale)   word4 C address (bias)
word5 D address           word6 total elements      word7 period
word8..15 zero
```

- FMA: `D[i] = RNE_once(A[i] * B[i] + C[i])`, one rounding, FTZ.
- `bscalar`: B is one 32-bit value broadcast; `cscalar`: C is one value;
  `period!=0` (power of two, not btiled): B repeats `B[i & (period-1)]`;
  `btiled` with a 32-element tile: B repeats the 32-value tile
  (`(32+31)>>5 == 1`, the delivered ds_vector btiled_1024/2048 pattern).
- A/B/C/D all live in the arena window `0x0400_0000..0x0404_0000`; plans and
  payloads live in the parameter window. The graph controller fetches the
  descriptor itself; the TB never injects a descriptor directly into the
  engine.
- Descriptor count must be >0; a "tail length 0" case means a total that is
  an exact multiple of CHUNK=256 (no partial bank), not a zero-count job.

## 4. Build / run

The single canonical filelist is `filelist_vector_fma.f` (one definition of
each module, real FMA core, no forbidden stub). Compiles are sequential
(`-j1` style); every simulation has a shell `timeout` and an in-TB cycle
watchdog. The final entry point is:

```bash
bash run_all.sh          # writes logs/rc.txt, reports/, result.json
```

Normal completion must have drained the last AXI B response before `done`
(`b_count_at_done=0`, `b_after_done=0`, `aw_after_done=0`,
`last_b_cycle < done_cycle`). Any mismatch, watchdog, fault or stale output
makes the run exit non-zero.

## 5. Test surface (target)

- Full independent 8,734-vector adversarial FMA set, with the original
  mode-0/1/2 semantics mapped to op17 (`mode0`: scale=1,bias=0; `mode2`:
  bias=0; `mode1`: as given) and the exact `refmodel.fma_bits` reference.
- Tail lengths 0 (=256 exact multiple), 1..17, 127, 255, 257, 1001.
- Random AXI backpressure (same BFM, several LFSR seeds) and a separate
  explicit-stall build if needed.
- `bscalar`, `cscalar`, periodic B (period 32/128) and btiled B (32-element
  tile, counts 1024/2048).
- Abort mid-op and reset mid-op, each followed by a new-epoch plan; old
  output region byte-unchanged, no AW/B in the quiescent window, new epoch
  bit-exact.
- Official `work/tests/fma_fixture` 1001-vector fixture (memory/gold/
  descriptor) driven through the same graph + vector path.
- Short-bank 4-lane path for fixed ops: totals 1..17, 127, 255, 257, 1001,
  including `out16` 16-bit tail packing.
- Negative control: a checker run with one intentionally corrupted gold word
  must return non-zero.

## 6. Explicit limits

This is vector-op17 integration and its BFM-level evidence, not a full model,
not CASE0000, not a 591-tensor DAG, not synthesis/STA, not a board or
frequency claim. Matrix `W7A16C48` numerics are not changed or re-verified
here. Multi-tile btiled semantics (period > 32 with tile switching) is not
changed by this task and is not claimed; only the delivered single-tile
pattern is exercised. No 300/600 MHz or whole-model seconds are claimed.
