# Unselected optimisations and rejected paths

This file records what was **not** copied into `rtl/`, and why. All originals
remain in their own directories; nothing was moved or deleted.

Selection rule: a candidate enters `rtl/` only if it is in the frozen
`ds_unified_graph` unique filelist after the unified regression. Module-level
PASS alone is not enough. The independent reviewer's findings are treated as
blocking until closed with a new frozen SHA and an independent rerun.

## A. Accepted at module/cluster level but not merged into this top

| Candidate | Original directory | Candidate SHA / result | Why not in `rtl/` |
|---|---|---|---|
| storage v3 write coalescer + registered validator | `v024_opt/ds_storage_write` | `block_storage_stream_v3.sv` `ddb87745…`; native 24 req/384 beats/6144 B PASS | AR-008 generic path crosses 4 KiB and a back-to-back pair stalls (`cseg_ready=X`). In the unified plan the two-descriptor legacy queue also hit MAT watchdog `0x0E`; fallback output was all zero. Not forced in. |
| layout 128-bit fast path / mode-2 gate | `v024_opt/ds_layout_wide` | `ddr_layout_engine_wide.sv` `5477651c…`; local PASS, official copy 0.176× | In the unified plan the mode-0 copies exceeded the 20,000-cycle MAT watchdog and roughly doubled Icarus wall time; fused run ended `0x0E`. |
| matrix 2×1 W reuse | `v024_opt/ds_matrix_reuse` | cluster result rc 0; AR-009 accepted | Read bytes 18,432→15,360 and W 6,144→3,072 B are real, but the ABI adds `cfg_w_reuse` and split A/W stage release; not re-verified in both fused and legacy tops. Capacity uses a second A stage + two C tiles, not "zero BRAM". |
| fusion dual-bank A16 | `v024_opt/ds_fusion_buffers` | `matrix_stream_fusion_top_dual.sv`; 39/39 PASS; AR-010 accepted | Dual top is broadcast-parameter only and would need a new top to merge with the V0.24 per-column table. Single-bank top is the selected integrated path. |
| per-channel epilogue ping-pong + FP32 spill | `v024_opt/ds_epilogue_channels` / `ds_repair_epilogue` | engine `4fff5c3f…` / repair `f4857c19…` | AR-006 simultaneous A16+FP32 backpressure was still open in the independent advisory test; the repair's "corrected ready" run changes the consumer contract. Not independently closed at freeze time. V0.24 uses its own per-column table engine. |
| graph lookahead / prefetch | `v024_opt/ds_graph_prefetch` | own result rc 1; AR-011 accepts accounting only | The patch is a whole controller variant without the explicit `MATF` descriptor; lookahead saved only 114 cycles (0.48%) with `LOOKAHEAD_EN=0` default. The 59.8% attribution was an arithmetic error. |
| vector op17 II=1 + 4-lane tail | `v024_opt/ds_vector_fma` / `ds_resume_vector` | `dad7cac0…`; AR-005 accepted tails | Adds `abort/aborted` ports and needs a `v023_vector_guard` edit; this top's numeric branch uses op3/op4 on the unchanged approximate core. 4-lane op17 was costed, not implemented. |
| FMA 7-stage core, pre-repair | `v024_opt/ds_fma_deep` | `b062284a…` | AR-001: accepted a beat while `flush=1`. Superseded by `ds_repair_fmaflush` `3c1114bc…`, which is the selected core. |
| old stream epilogue | `v023_repair/ds_closeout_fusion` / `primary_stream_fix` | `b99a664b…` etc. | Old stream has only two broadcast words and known tag/backpressure defects; not selected because of FMA pass. V0.24 uses `epilogue_stream_engine_v024`. |

## B. Explicitly rejected / not copied

- **59.8% non-engine overhead claim** — rejected. The exclusive-union ledger is
  435 cycles / 1.83% (`383+44+8+23339=23774`); 12,641 was a last-op subtraction
  error. No 12k-cycle lookahead saving is claimed.
- **"zero extra BRAM" / "1-cycle collect" / "8× layout" / "FMA halved"** — not
  used as acceptance metrics. Only measured bytes/cycles are reported.
- **54.8 KB as vector-only traffic** — rejected; it was the whole small-chain
  AXI read+write, not vector-exclusive.
- **multi-HP bandwidth addition / CREDIT8 implies one transaction** — rejected;
  no board topology change and no multi-HP sum.
- **automatic fusion swallowing** — rejected; fusion is explicit `MATF`/`A16C`
  plus `FUSION_ALLOW`, otherwise legacy C48.
- **strict IEEE FMA** — not claimed. AR-002 documents signed-zero and
  `inf*subnormal` differences from the declared project contract.
- **old 7.745 ns on new RTL / 250–300 MHz** — not claimed. No synthesis/STA.
- **4×4 / duplicate worker trees** — not copied. Only one selected source per
  module is in `rtl/`; the two matrix queue engines and two tops are distinct
  modules (main `v024_unified_top`, baseline-smoke `v023_integrated_top`), not
  duplicate definitions.

## C. Original evidence kept

The independent failed experiments remain in:

- `v024_opt/ds_adversarial_review/{FINDINGS.md,logs,mutants,reports}`;
- each worker's own `logs/`, `result.json`, `exit.json` (including
  `ds_storage_write` exit 1 and `ds_graph_prefetch` exit 1);
- `v023_repair/**` (read-only).

This export does not rewrite those histories.
