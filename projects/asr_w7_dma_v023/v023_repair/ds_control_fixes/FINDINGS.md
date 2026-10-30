# FINDINGS — ds_control_fixes

All findings below are logic-simulation findings. No synthesis, STA, Vivado,
board, VNC, or push was performed. `work/`, the ZIP, old competition trees and
other workers' files stayed read-only. Every new file is under this directory.

## F-001 (PA-001, confirmed, fixed) — interleaved 64-bit CSR readback

- Original: `work/rtl/plan_submit_csr.sv`.
- Defect: all 64-bit counter low-word reads overwrite one shared
  `snapshot_high` register. Reading low(cycles), low(fetch), high(cycles)
  returns fetch's high word.
- Before evidence: `logs/csr_orig.log`
  - `PA001_INTERLEAVED read20,read30,read24 -> aabbccdd` (expected `11223344`)
  - `PA001_INTERLEAVED_BUG`, 9 failing checks.
- Fix: `candidate/rtl/plan_submit_csr_v023.sv`, one high-word snapshot bank per
  64-bit register. A low read samples that register atomically; a following
  high read returns that sample even after other registers are read. START
  clears the bank. High-only reads sample current high if no low was seen.
- After evidence: `logs/csr_v023.log`, `PA001_PASS`, 0 errors.
- Software contract remains: read low then high for each counter. This is a
  telemetry fix; it does not change plan/engine numerics.

## F-002 (PA-002, confirmed, fixed) — unbounded FETCH / ERROR_DRAIN

- Original: `work/rtl/pl_execution_plan_v022.sv`.
- Defect:
  1. FETCH watchdog sets `error_code=09` but does not fault or leave FETCH.
  2. WAIT_OP timeout enters ERROR_DRAIN and waits forever for a child done.
- Before evidence: `logs/plan_before.log`
  - dead read: 1000 cycles, `busy=1 done=0 fault=0 err=09 state=3`
  - dead child: `busy=1 done=0 fault=1 err=09 state=10`
  - `PA002_FETCH_UNBOUNDED_CONFIRMED`,
    `PA002_ERROR_DRAIN_UNBOUNDED_CONFIRMED`.
- Fix: `candidate/rtl/pl_execution_plan_v023.sv`
  - FETCH/VFETCH timeout: assert `dma_abort`, enter `DRAIN`, keep
    `dma_read_ready` asserted so an already accepted AXI burst can return.
  - WAIT_OP timeout: assert `child_abort`, enter `DRAIN`, wait for
    `child_done` or explicit `child_drained`.
  - Second deadline (`DRAIN_WATCHDOG`) ends in `drain_timeout=1`,
    `isolation_req=1`, `drained=0`, fault `0A`. It never reports a successful
    or safe drain without an observed completion/drain.
  - `isolation_req` latches and rejects new START until reset; recovery is
    tested after reset.
  - Request-wait timeout (no AXI accepted) ends safely with error `0B`,
    `drained=1`, no isolation.
- After evidence: `logs/plan_v023.log`, 10 phases, `PA002_PASS`:
  normal, dead read -> isolation, rejected START, reset recovery, late R ->
  safe drain, dead child -> isolation, child drain-only -> safe, child fault,
  request timeout, no accepted DMA in request timeout.
- Important boundary: abort is not AXI cancellation. Only `dma_done` or
  `child_drained` proves accepted work is gone. `drained=0 + isolation_req=1`
  is an explicit unsafe terminal state for external firewall/reset.

## F-003 (PA-003, confirmed, fixed) — 32-bit DMA address wrap at 4 GiB

- Original candidate: `tasks/ds_ddr/candidate/axi_dma_v020_multi.sv`.
- Before evidence: `logs/dma_before.log`; request
  `0xFFFFFFF0` x 2 beats produced AR `0xFFFFFFF0` then `0x00000000`
  (`PA003_WRAP_BUG_CONFIRMED`).
- Fix: 40-bit running address in
  `candidate/rtl/axi_dma_v023_multi.sv` and
  `candidate/rtl/axi_dma_v023_bounded.sv`. The 32-bit request port is kept for
  source compatibility; bursts crossing 4 GiB continue at `0x1_0000_0000` in
  the 40-bit AXI address.
- After evidence: `logs/dma_v023.log` and `logs/dma_bounded.log`:
  AR `0xFFFFFFF0`, then `0x100000000`; 2 bursts, 32 bytes, no wrap.

## F-004 (PA-004, confirmed, fixed) — `write_bytes` ignored WSTRB

- Before evidence: same `logs/dma_before.log`; one beat with WSTRB `0x0007`
  reported `write_bytes=16` instead of 3 (`PA004_STRB_COUNT_BUG_CONFIRMED`).
- Fix: `write_bytes += pop16(write_strobe)` in both v023 DMAs.
- After evidence: 1 beat partial = 3 bytes; 4 beats with last WSTRB `0x0007`
  = 51 bytes; physical memory bytes match.
- Matrix/DDR worker coordination: `candidate/rtl/axi_dma_v023_multi.sv`
  carries the same port shape as v020_multi plus `abort/aborted/drained/busy`.
  The exact integration contract is in `INTERFACE.md`; no other worker file
  was edited.

## F-005 (PA-00x, structural, fixed) — 128-node combinational ready-mask scan

- Existing candidate `tasks/ds_pl_autonomy/rtl/wc_superplan_ctrl.sv` scans all
  128 nodes in one combinational `for` loop with a first-found priority chain.
  No functional counterexample was demonstrated in that file here; the finding
  is the long single-cycle scan/priority structure, not a proven logic bug.
- New `candidate/rtl/ready_scan_banked_v1.sv`: four 32-node bank scans,
  registered per-bank first-ready result, lowest-bank/lowest-index pick, and a
  held output stage under `scan_ack`. `pending`/`done_mask`/`engine_free` are snapshotted at
  `scan_start`; dependency masks are immutable descriptors. `done_mask` only
  grows, so a snapshot-ready node stays ready.
  A node whose last predecessor completes during the scan is picked next scan.
- The node type field is 3 bits here (1 MAT, 2 VEC, 3 LAY, 4 SEQ). Using 2 bits
  loses SEQ=4; that was caught and fixed during test development.
- Verification: `logs/ready_scan.log`, 5 deterministic + 400 randomized
  scenarios, including node 127 only, engine-class filtering, unmet
  dependency, and `done_mask` changing during scan; `READY_SCAN_PASS`.
- No timing claim: this removes a 128-deep combinational scan from the logic
  slice but does not prove any Fmax.

## F-006 (structural, fixed) — upstream cascaded `block_address` multiply

- Original: `work/rtl/block_address_v020.sv`, one combinational cone:
  `(block_row*ncb + block_col)*block_bytes + base`, plus extent and bounds.
- New `candidate/rtl/block_address_v023.sv`: S1 geometry + `row*ncb`; S2
  `+col` and `*block_bytes`; S3 `+base`, extent, row/col remainder, valid.
  Arithmetic widths/assignment context of v020 are preserved exactly
  (including 40-bit `offset`/`extent` context), unlike a naive 32-bit rewrite.
- Interface: 3-stage elastic `in_valid/in_ready/out_valid/out_ready`; latency
  3 cycles when not stalled; outputs held under backpressure.
- Verification: `logs/block_address.log`, 3000 vectors (random, boundary,
  encoding=3, out-of-range block ids, 4 GiB-adjacent bases) with random output
  stalls; every address/valid_rows/valid_cols/extent/valid matches v020;
  `BLOCK_ADDRESS_PASS`.
- This is a structural candidate; no STA/Fmax claim.

## F-007 (handshake contract, verified) — storage descriptor hierarchy

- `candidate/rtl/block_storage_dma_wide4_v023.sv` is a SHA-pinned copy of
  `tasks/ds_critical_control/candidate/rtl/block_storage_dma_wide4_pipe_v1.sv`
  (7 registered validator stages, unchanged ports/ordering). It was not
  re-architected here; the 71-case equivalence is the source task's evidence.
- New handshake test `logs/storage_handshake.log`:
  - pipelined `block_address` output is stable under output backpressure;
  - bad A read returns HEADER with `header_in_operation=1`, no DMA request;
  - good A read waits for the registered validator, issues exactly 128 DMA
    beats, drains them, then presents HEADER with `bad=0`;
  - bad write consumes 1024 scalar words and exits via WACK with
    `write_error=1`, no DMA request.
  - `STORAGE_HANDSHAKE_PASS`.
- Matrix worker should read `INTERFACE.md` §6 before replacing the engine
  request mux; `block_address_v023` has a handshake, not the old combinational
  `address` port.

## Not claimed / open

- No synthesis, STA, DRC, bitstream, board run, VNC, or push.
- No 250/300/600 MHz or “600 MHz reached” claim. The ready-scan and address
  pipelines are structural risk reductions only.
- No full CASE0000 inference, quantization-effect, or model-metric evaluation
  in this task. Division/root approximation is another worker's scope; no
  numeric contract was changed here.
- The AXI BFMs are protocol models, not DDR timing/bandwidth models.
- The storage candidate's full 71-case regression was not re-run in this
  directory; the source task's logs and hashes are referenced. Only the new
  handshake/latency/error cases above were independently run here.
- `wc_superplan_ctrl.sv` itself was not edited. `ready_scan_banked_v1` is a
  drop-in scanner that the graph/plan owner must integrate; until then the old
  scan remains in that file.
