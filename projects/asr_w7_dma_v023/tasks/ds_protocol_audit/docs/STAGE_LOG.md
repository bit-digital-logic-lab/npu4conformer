# Stage log — ds_protocol_audit

All stages read this task's `USER_UPDATES.md`; the file was updated once by the
user near the end (new strict-pipeline/STA tasks; DMA/storage control-path
registering for 300/600MHz, frequency not verified). No source outside this
task directory was written.

## Stage 0 — contracts and scope (read-only)

- Read `EXECUTION_CONTRACT.md`, `work/DESIGN_CONTRACT_zh.txt`,
  `work/CURRENT_WORK.txt`, `IC_GIT_REFERENCES.txt`, `任务分工.md`,
  `AGENT_ASSIGNMENTS.json`, this task's `USER_UPDATES.md`.
- Confirmed scope: DMA/AXI/cache/error handling; original zip/work read-only;
  no synthesis/Vivado/board/VNC/network; no numeric changes.
- Captured source SHAs (`snapshots/SHA256SUMS.txt`, later
  `reports/SOURCE_SHA256.txt`).

## Stage 1 — v019 directed edge cases

- Wrote `tb/tb_dma_edge.sv` with an independent AXI slave: 4KiB split,
  AR/AW/W/B stalls, early/late/absent RLAST, RRESP/BRESP errors, WSTRB tail,
  65535-beat transfer, 32-bit wrap, zero/unaligned.
- Result `reports/dma_edge001`: 19 groups, `errors=0`, cycles=70092.
- Confirmed behaviors: 4KiB split correct; early/late RLAST drain/error;
  RRESP/BRESP drain; no internal timeout (T19); 32-bit wrap (PA-003);
  zero-length is an error with no AXI (PA-006).

## Stage 2 — vector/layout fixtures under seeded stalls

- Wrote `tb/axi128_stress_bfm.sv` (xorshift32 gates, R/W/B stalls, delayed B,
  `stall_r`, framing `$fatal`), `tb_vector_stress.sv`, `tb_layout_stress.sv`.
- Result: 15/15 vector runs (5 fixtures x 3 seeds), 16/16 layout runs
  (7 x 2 + case0000 x 2). Byte-exact gold, 32-byte tail guard, C48 6-byte
  fragments, out16/out32 tails, case0000 157696B.
- Also discovered and fixed a TB-only AR-queue count race (`qc` push+pop);
  this was not a DUT bug (see REPORT §5).

## Stage 3 — candidate v020_multi snapshot

- Snapshot `snapshots/axi_dma_v020_multi_snapshot_20261029.sv` (SHA 7123c26f).
  The file changed during the audit: earlier SHA 7653b83e lacked
  `m_axi_wvalid && write_valid`; the current snapshot fixed it (PA-013 history).
- Wrote `tb/tb_dma_multi.sv` with AR queue, FIFO-full/slow consumer, delayed B
  queue, WVALID bubbles, BRESP error, early/late RLAST, wrap.
- Result `reports/multi001`: 13 functional scenarios `errors=0`;
  `ar_max=4`, `b_max=2`, FIFO high=128.
- Confirmed `write_bytes` ignores WSTRB (PA-004); isolated `tb_strobe.sv`
  proves the physical strobe is correct (`mem=00 01 02 00`, `write_bytes=16`).

## Stage 4 — CSR and plan watchdog

- `tb/tb_csr_snapshot.sv`: interleaved 64-bit reads; confirmed
  `CSR_SNAPSHOT_BUG_CONFIRMED` (PA-001). AW/W independent, bad-strobe
  atomicity, busy START rejection pass.
- `tb/tb_plan_stall.sv` with WATCHDOG=400: phase1 AR accepted/R never returns
  (`dma_state=2`, wait=997, fault=0); phase2 child never done (state=10,
  wait=401, fault=1, done=0); phase3 normal completion (PA-002).

## Stage 5 — ACL and finalization

- Added `+acl=1` to both stress TBs: force 0xFFFFFFF0; 64-bit extent rejects
  with `fault=1 err=01 rb=0 wb=0` (PA-009).
- Read the updated `USER_UPDATES.md` at the end; added PA-015 (300/600MHz
  control-path registering suggestions, explicitly unverified; no STA).
- Regenerated all logs via `scripts/run_all.sh`; all rc=0; wrote
  `REPORT.md`, `FINDINGS.jsonl`, `result.json`, `progress.json`, `INTERFACE.md`.
