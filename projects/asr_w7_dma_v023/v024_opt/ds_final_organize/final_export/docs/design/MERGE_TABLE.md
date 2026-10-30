# MERGE TABLE — ds_unified_graph (V0.24)

Selection rule: consume a specialist patch only when (a) its `exit.json` is
present with `exit_code==0` and its `result.json` reports module-level PASS,
(b) it is a drop-in for the frozen base ABI (same module name/port list), and
(c) the merged build passes the unified graph regression again. Otherwise the
patch is listed as **deferred**, with the exact conflict/measured failure and
SHA, and is not silently included.

The reliable base is `v023_repair/ds_closeout_safety` (26-test closeout),
copied byte-for-byte before any edit.

| direction | worker | candidate SHA-256 | decision | evidence / reason |
|---|---|---|---|---|
| numeric FMA flush barrier | `ds_repair_fmaflush` (final, rc 0) | `fp32_fma_pipe.sv` `3c1114bc4007…` | **merged** | 7-stage 129-bit acc, II=1; minimal AR-001 fix (`in_ready=rst_n&&!flush&&…`, `out_valid=…&&!flush`). Same ports. 64/64 directed single-rounding vectors bit-exact; 64/64 differ from mul+add. Supersedes the `ds_fma_deep` `b062284a…` core. |
| storage / collect | `ds_storage_write` (rc 0) | `block_storage_stream_v3.sv` `ddb87745321c…`; `block_engine_prefetch_v3.sv` `f73d8f224f9f…`; `matrix_p2_cluster_v3.sv` `319488cbe468…` | deferred after integration test | The v3 single-task native coalescer passes the worker suite, but in this unified plan the legacy queue with **two descriptors** (the deliberate fusion-refusal fallback) did not complete: the MAT watchdog ended at `error=0x0E` and the fallback I16 output was all zero. The fused top also keeps v2 because its C48 write port is structurally tied off. AR-008 froze an older `b92cb2a7…`; the tested file was the later `ddb87745…`. Not forced in. |
| layout 16 B fast path | `ds_layout_wide` (rc 0, PASS_LOCAL_LOGIC) | `ddr_layout_engine_wide.sv` `5477651c09c9…` | deferred after integration test | Drop-in and functionally correct in the worker tree, but in this unified plan (mode 0 copies from the parameter window) it made the LAY nodes exceed the 20 000-cycle MAT watchdog and roughly doubled Icarus wall time; the fused run ended `error=0x0E`. Not forced in. Base V0.23 burst layout remains. |
| matrix W reuse | `ds_matrix_reuse` (rc 0) | `block_engine_reuse_v1` / `matrix_reuse_cluster_v1` | deferred | ABI adds `cfg_w_reuse`, independent `rd_a_stage/rd_w_stage`, split stage releases. Merging into both the legacy and fused tops was not re-verified. Independent AR-009 confirms the byte-level read drop. |
| fusion dual-bank | `ds_fusion_buffers` (PASS) | `matrix_stream_fusion_top_dual.sv` | deferred | dual 2 KiB top is broadcast-only; merging it with the V0.24 per-channel table engine would need a new top not present in either worker. Single-bank top is used and proven. |
| per-channel ping-pong + FP32 spill | `ds_epilogue_channels` (rc 0) | engine `4fff5c3f…` | deferred | port/ABI adds `cfg_table_en/cfg_bank/cfg_bc`, `param_wr_bc`, and a second 4×FP32 consumer; AR-006/AR-007 remain open. V0.24 implements the required per-column table with scale/bias pipelined through `i48_to_f32` (the AR-004 fix) and no FP32 consumer. |
| graph lookahead | `ds_graph_prefetch` | lookahead `wc_graph_ctrl` (its own result rc 1) | deferred | the patch is a full controller variant without the explicit MATF/A16C descriptor; its own result is `LOCAL_LOGIC_CANDIDATE_ONLY` rc 1. |
| vector op17 / 4-lane tail | `ds_vector_fma` / `ds_resume_vector` | `ddr_vector_engine_pipe.sv` `dad7cac0…` | deferred | candidate adds `abort`/`aborted` ports and a `vector_fma_lane`; `v023_vector_guard` would need edits. The unified numeric branch uses op3/op4 (DIV/SQRT) on the unchanged approx core. |

## Base provenance

`SOURCE_SHA256.json` records the SHA-256 of every `v023_repair/ds_closeout_safety`
RTL/TB/script file before edits, plus the V0.24 new files. Modified base files:

- `wc_graph_ctrl.sv` (+ explicit MATF/A16C fusion descriptor, consumer ledger)
- `wc_graph_top.sv` (+ fusion sideband)
- new copies: `v024_unified_top.sv`, `v024_matrix_queue_engine.sv`

## Honest merge count

Consumed specialist module: the **repaired 7-stage FMA core** (numeric). Storage
v3, layout-wide, reuse, fusion dual-bank, epilogue ping-pong, graph lookahead
and vector op17 are deferred with the measured reasons above. The unified
fusion/per-channel/descriptor work is original to this task and is the main
deliverable.
