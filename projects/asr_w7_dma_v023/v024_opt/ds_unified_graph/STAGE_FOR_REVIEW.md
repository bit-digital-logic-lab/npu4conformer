# STAGE FOR INDEPENDENT REVIEW — ds_unified_graph

Status: **implemented; post-merge regression is being finalised in this
directory. The reviewer may start from the commands below without waiting for
`exit.json`.** This is a logic-simulation candidate only: no synthesis, Vivado,
STA, board, VNC or push.

## What to test

1. Fused small graph: explicit `MATF` MAT node + per-column scale/bias +
   DIV(op3) + SQRT(op4) + A16 layout copy. Independent gold is
   `fixtures/gold_a16.hex`, `fixtures/v024_ref.json`.
2. Explicit-request fallback: a `MATF` node with `queue_count=2` and a
   non-`A16C` consumer must run the **legacy C48** path and still match
   `fixtures/gold_fallback_i16.hex`.
3. Plan rejection: `MATF` word without header `FUSION_ALLOW` must report
   `error=0x04` and terminate.
4. Fault/drain: hold the A16 write B response; the MAT watchdog must end in
   `fault=1,error=0x0E,isolation=1,requires_reset=1,b_pending>0,quiesced=0`;
   no new AR/AW/W after isolation.
5. Directed FMA contract: 64 vectors where single-rounding FMA differs from
   `mul`-then-`add` in FP32; `fixtures/lane_gold.hex` vs `lane_muladd.hex`.

## Exact commands

```bash
cd /home/yang/Desktop/项目/v024_opt/ds_unified_graph/unified
bash scripts/run_v024.sh          # gen -> compile(-j1) -> 5 sims -> judge -> SHA
# individual:
iverilog -g2012 -s v024_unified_top -o build/v024_top.vvp -f filelist_v024_unified.f
iverilog -g2012 -s tb_v024_unified -o build/tb_v024.vvp \
  -f filelist_v024_unified.f tb/wc_safety_bfm.sv tb/tb_v024_unified.sv
vvp build/tb_v024.vvp +memfile=fixtures/mem_v024_fused.hex \
  +outfile=logs/v024_fused_out.hex +watchdog=100000 +mode=0
python3 scripts/check_v024.py
```

`scripts/check_v024.py` verifies `REFERENCE_FREEZE.json` first; a mutated
fixture is a hard failure. It exits non-zero on any numeric mismatch or if the
FMA vectors do not separate single-rounding from `mul+add`.

## Frozen evidence

- `SOURCE_SHA256.json`: base `ds_closeout_safety` hashes and which base files
  were edited (`wc_graph_ctrl.sv`, `wc_graph_top.sv`).
- `REFERENCE_FREEZE.json`: fixture/gold SHA-256.
- `MERGE_TABLE.md`: consumed and deferred worker patches with SHAs/reasons.
  Consumed: the repaired 7-stage FMA core (`ds_repair_fmaflush`). Storage v3,
  layout-wide, W-reuse, fusion-dual, epilogue ping-pong, graph lookahead and
  vector op17 are deferred; storage-v3 multi-task and layout-wide both hit the
  MAT watchdog in this plan.
- `filelist_v024_unified.f`: the only compile list.

## Known limits (do not over-claim)

- Not the full 591-tensor DAG; this is a small graph with MATF + per-column +
  DIV/SQRT + A16 copy.
- Per-channel table is host-preloaded **once** before START (64 words); no
  per-tile host DMA. The PL still autonomously streams A/W/A16.
- DIV is the approximate core: max relative error measured ~9.1e-4; SQRT
  ~5.1e-6. Exact DIV/SQRT is not claimed.
- Fusion is opt-in only; it is never inferred from successors. Multi-task
  (`queue_count != 1`) and untagged consumers fall back to the legacy C48 path.
- The 7-stage FMA core is the **repaired** `ds_repair_fmaflush` variant:
  `in_ready=0` and `out_valid=0` while `flush=1` (AR-001 closed at module
  level). The unified graph does not inject `flush` with in-flight data.
- Deferred patches and open worker findings are listed in `MERGE_TABLE.md`.
- No frequency, whole-model seconds, synthesis, STA, board or CDC claim.
