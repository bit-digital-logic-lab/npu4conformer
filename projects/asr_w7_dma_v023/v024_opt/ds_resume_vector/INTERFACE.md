# INTERFACE — v024_opt / ds_resume_vector

Status: **resumed verification**. The canonical `rtl/ddr_vector_engine_pipe.sv`
SHA-256 is `dad7cac0…` and the wrapper `rtl/vector_fma_lane.sv` is
`09175e59…`. Final rc and the complete SHA map are in `result.json`;
`REPORT.md` is generated from the same run data.

Scope: local RTL logic simulation only. No synthesis, no Vivado/STA, no board,
no VNC, no git push. Only this directory is written; `ds_vector_fma`,
`v023_repair`, `work/`, the ZIP and every other worker directory stay
read-only.

## 1. What this task changes

Base: the read-only `v024_opt/ds_vector_fma` tree (itself based on
`v023_repair/ds_closeout_numeric`). The numeric cores are unchanged:

| file | SHA-256 |
|---|---|
| `rtl/fp32_fma_pipe.sv` (trusted 4-stage) | `1ed8801a…` |
| `rtl/asr_fma_ip.sv` | `634eea1a…` |
| `rtl/approx_div_sqrt.sv` | `444fa2a2…` |

Changes are confined to `rtl/ddr_vector_engine_pipe.sv` plus the new
`rtl/vector_fma_lane.sv`:

1. **op17 FMA is issued II=1, single lane, valid/ready.**
   - The engine instantiates the real `fp32_fma_pipe` through
     `vector_fma_lane`, drives `in_valid`/observes `in_ready`, and consumes
     `out_valid`/`out_tag`. It does not count a fixed latency.
   - A tag `{bank,7'd0,index[7:0]}` is carried with each element and checked
     against the drain index; a mismatch is fault `0x06`.
   - Single-lane issue is 1 FP32 element/cycle. A 4-lane FMA would require
     four independent 129-bit accumulator cores; it is costed but not
     implemented.

2. **4-lane fixed-op short-bank fallback removed.**
   - The old `bank_elems > 8` scalar fallback is gone for every fixed op.
   - Collection drains on the lanes' own `out_valid` (lane 0 is valid for
     every issued group), not a fixed delay after the last issue.
   - Partial issue uses the exact 1/2/3/4-lane mask; `lanes_now` packs exactly
     the valid lanes, including the final partial word and 16-bit tail.
   - Bank completion requires `drained_beats+1 == issued_beats`; otherwise
     fault `0x06` (no silent drop/duplicate).

3. **Abort / reset / drain preserved.** One-cycle `core_flush`, accepted-read
   drain and accepted-write (W+B) drain remain. No AW starts after abort;
   computed-but-unwritten results are dropped. A new-epoch plan must be
   bit-exact.

## 2. Latency contract and the 7-stage core

`vector_fma_lane` exposes the `fp32_fma_pipe` port set:

```
clk, rst_n, flush
in_valid, in_ready, in_a[31:0], in_b[31:0], in_c[31:0],
in_tag[TAG_WIDTH-1:0], in_last
out_valid, out_ready, out_result[31:0], out_tag[TAG_WIDTH-1:0], out_last
```

- Standard valid/ready on both sides; results are in-order.
- Latency is not a parameter of the engine and is never hard-coded.
- Two builds are gated:
  - canonical 4-stage `rtl/fp32_fma_pipe.sv`;
  - `filelist_vector_fma7.f` with the frozen
    `fma7/fp32_fma_pipe.sv`
    (`b062284af692349ac0afe1de14ac0d10f0cbbab97a5b33f849b50a93caccac82`,
    ds_fma_deep 7-stage candidate).
- A third build (`-DFMA_EXTRA_STAGES=3`) inserts three valid/tag-only elastic
  stages after the real 4-stage FMA to prove latency insensitivity.
- `tb/tb_fma7_latency.sv` independently measures the 7-stage wrapper:
  first-result latency 7, II=1, output backpressure preserves tags, one-cycle
  flush with `in_valid=0` drops all in-flight results, and the next epoch is
  exact.
- The vector engine never issues while `core_flush` is asserted. AR-001
  (`fp32_fma_pipe` keeps `in_ready=1` during `flush`) remains a core-level
  finding owned by `ds_repair_fmaflush`; it is not silently claimed fixed.

## 3. Descriptor contract used by the tests

Unchanged V023 vector ABI, 16 words / 512 bits:

```
word0 magic 0x22564543
word1 op[39:32]=17 (FMA) plus a16/out16/bscalar/ascalar/cscalar/a48/btiled
word2 A (x)   word3 B (scale)   word4 C (bias)   word5 D
word6 total   word7 period     word8..15 zero
```

- FMA: `D[i] = RNE_once(A[i] * B[i] + C[i])`, one rounding, FTZ, project
  NaN/Inf rules.
- `bscalar`/`cscalar` broadcast; `period` repeats B `B[i & (period-1)]`;
  `btiled` uses the delivered 32-element tile.
- A/B/C/D live in `0x0400_0000..0x0404_0000`; plans/payloads live in the
  parameter window. The graph controller fetches the descriptor itself; the
  TB writes only CSR START.
- Descriptor count is >0. "tail 0" means a total that is an exact multiple of
  CHUNK=256, not a zero-count job.

## 4. Build / run

Canonical filelist: `filelist_vector_fma.f`; 7-stage filelist:
`filelist_vector_fma7.f`. Compiles are sequential (`iverilog`), every
simulation has a shell `timeout` and an in-TB cycle watchdog.

```bash
bash run_all.sh          # fixtures, two core builds, all cases, negative
                         # control, backpressure, baseline, REPORT/result
```

`run_all.sh` exits 0 only when `make_result.py` passes its exact-set gate:
every expected manifest/latency/7-stage case is present, no missing/extra/
duplicate case, every sim/check/stage rc is 0, frozen/unique/negative/
backpressure/baseline checks pass. `result.json` and
`reports/run_all_status.json` carry the same rc.

Normal completion must drain the last AXI B response before `done`
(`b_count_at_done=0`, `b_after_done=0`, `aw_after_done=0`,
`last_b_cycle < done_cycle`).

## 5. Test surface

- 122 deterministic cases generated from independent `refmodel.py` gold.
- Full 8,734 adversarial FMA vectors (modes 0/1/2 mapped to op17), through
  the graph + shared AXI128 + real FMA core.
- FMA tails 256 (tail 0), 257..273 (tails 1..17), 383, 511, 513, 1001.
- 4-lane fixed-op MUL/ADD/F32_I16 totals 1..17 (including the previously
  untested 10..16), 31/32/33, 63/64/65, 127, 255/256/257, 511, 513, 1001.
- bscalar, cscalar, periodic B 32/128, btiled 32-element tile 1024/2048.
- Official `work/tests/fma_fixture` 1,001-vector fixture.
- `EXTRA_STAGES=3` on full/official/tails/fixed-op cases.
- Actual 7-stage core on full/official/tails/fixed-op plus abort/reset.
- Random AXI BFM backpressure seeds on both core builds.
- Abort mid-op and reset mid-op, then a new-epoch 257-value plan, on both
  core builds.
- Negative control: two corrupted gold words must be rejected.
- Same-input/same-BFM baseline comparison (full8734, tail270, official).

## 6. Explicit limits

This is vector-op17 integration and BFM-level evidence, not a full model, not
CASE0000, not a 591-tensor DAG, not synthesis/STA, not a board or frequency
claim. Matrix `W7A16C48` numerics are not changed or re-verified here.
Multi-tile btiled (period > 32 with tile switching) is existing behaviour and
is not claimed. No 300/600 MHz or whole-model seconds are claimed. Module PASS
is not a unified-graph or system PASS.
