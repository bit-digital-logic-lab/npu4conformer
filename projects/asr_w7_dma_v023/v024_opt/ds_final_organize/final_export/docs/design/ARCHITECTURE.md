# V0.24 final export — architecture (logic model)

This export is a **single-clock logic-simulation candidate** built from the
`ds_unified_graph` V0.24 stage. It is not a complete 512-dim ASR model, not a
synthesised/placed design, and not a board build.

## 1. Top level

`rtl/graph/v024_unified_top.sv` is the main top. It contains:

- WCPG v2 graph controller with the V0.24 explicit fusion descriptor extension
  (`rtl/graph/wc_graph_ctrl.sv`, `rtl/graph/wc_graph_top.sv`);
- one `v023_axi_shared` AXI128 arbiter (5 read owners, 3 write owners,
  `CREDIT=8`, `QDEPTH=32`, single clock);
- matrix path: `v024_matrix_queue_engine` -> `matrix_stream_fusion_top_v024`
  (fused) or `matrix_p2_cluster_v2` (legacy C48 fallback);
- vector path: `v023_vector_axi` -> `ddr_vector_engine_pipe` with the
  approximate DIV/SQRT core selected for op3/op4;
- layout path: `v023_layout_axi` -> `ddr_layout_engine_v023_burst`;
- a host-preloaded 32-entry scale + 32-entry bias epilogue table inside
  `epilogue_stream_engine_v024`.

`rtl/graph/v023_integrated_top.sv` is the **baseline smoke top** only. It is
used by `sim/tb/tb_safety_integrated.sv` to prove that the default path
(header `FUSION_ALLOW` clear) still terminates and drains. It is not a second
product top.

## 2. Dataflow, fused path

```
host preload (once, before START)
  plan/header/nodes/payload + A/W + 64-word scale/bias table
                 |
        WCPG controller (PL autonomous)
                 |
   MAT node with header FUSION_ALLOW + word14='MATF'
                 |
   matrix_stream_fusion_top_v024
     A/W DMA -> 16x16 W7p8/C48 array -> C48 framer
             -> I48->F32 (S1/S2)
             -> per-column scale/bias + single-rounding FP32 FMA
             -> optional ReLU -> F32->I16 (RNE, saturating)
             -> 2 KiB A16 block buffer -> A16 write DMA -> B drain
                 |
        downstream A16C layout/vector consumer
```

The fused path writes **no C48 to DDR** (`stat_c48_ddr_bytes=0`) and writes
2,048 B of A16 per 32x32 tile. The legacy path writes C48 to DDR and reads it
back; that path remains the fallback and is regression-tested.

## 3. Explicit fusion descriptor (no automatic swallowing)

Fusion is opt-in per node:

- header word 3 bit 16 = `FUSION_ALLOW` (`0x00010000`);
- MAT node word 14 = `MATF` with:
  - `[31:16] = 0x4D41`
  - `[15:14] = 0` (A16 output)
  - `[13]` per-channel table enable
  - `[12]` ReLU enable
  - `[11:10]` FMA mode: 0 conv-only, 1 scale+bias, 2 scale-only
  - `[9:0]` reserved, must be 0
- MAT node word 15 = parameter block base (0 in this candidate; the table is
  preloaded through the existing 8-bit parameter write port);
- every consumer that is meant to take A16 must carry word 14 = `A16C`
  (`0x41313643`).

The controller falls back to the legacy C48 path when any of these holds:

1. header `FUSION_ALLOW` is clear, or word 14/15 are non-zero without it;
2. `queue_count != 1` (multi-task / dynamic parameter lists);
3. a MAT consumer is not tagged `A16C` and is not a terminal output;
4. a fault is active.

A plan that sets `MATF` without `FUSION_ALLOW` terminates with `error=0x04`
and performs no fused work.

## 4. Numerical contract

- Matrix: A16 signed, W7p8 special encoding with positions/clip/parity,
  INT48 accumulation in ascending K order.
- Epilogue: I48 -> FP32 with RNE/FTZ; **single-rounding** FP32 FMA
  (`round(a*b+c)`), not `mul` then `add`; optional ReLU; FP32 -> I16 with RNE
  and saturation.
- DIV/SQRT use the approximate core. Measured maxima in this export:
  DIV relative ~9.1e-4 (tolerance 1.2e-3), SQRT ~5.1e-6 (tolerance 6e-6).
  Exact DIV/SQRT is **not** claimed.
- The FMA core is the repaired `ds_repair_fmaflush` 7-stage, 129-bit
  accumulator, II=1 variant. It is **not** strict IEEE for signed zero and
  `inf * subnormal`; that is the declared project contract (AR-002).

## 5. Safety / drain contract

- Every simulation has a shell `timeout` and an in-TB cycle watchdog.
- Normal completion requires `b_pending==0` and `quiesced==1` after the last
  A16/C48 B response.
- Fault injection must end in `fault=1`, `error=0x0E`, `isolation=1`,
  `requires_reset=1`, `b_pending>0`, `quiesced=0`; no new AR/AW/W after
  isolation.
- `requires_reset` is sticky; START is rejected until reset.
- A timeout is never converted into a success.

## 6. Module map

| Directory | Contents |
|---|---|
| `rtl/matrix` | 16x16 array/PE, P2 prefetch engine, C-cache, operand banks, matrix cluster |
| `rtl/memory` | transactional A/W/C storage and posted C48 write stream |
| `rtl/dma` | AXI128 read/write DMA engines (v019/v020/v023) |
| `rtl/vector` | vector pipe, FP32 lanes, descriptor checker, approximate DIV/SQRT |
| `rtl/layout` | burst layout engine and AXI/guard wrappers |
| `rtl/graph` | WCPG controller/top, V0.24 top, matrix queue engines, CSR/plan helpers |
| `rtl/epilogue` | C48 framer/FIFO, I48->F32, FMA, ReLU, F32->I16, A16 buffer/writer |
| `rtl/common` | shared AXI arbiter, divider helper, compile-only FMA stub |

The compile-only `asr_fma_ip` stub aborts if invoked. It exists because the
vendor FMA simulation library is not present; the product numeric path uses
`fp32_fma_pipe.sv` directly and does not call the stub.
