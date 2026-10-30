# REPORT — CSR / error / critical-control repairs (ds_control_fixes)

Date: 2026-10-29 (UTC+8)
Directory: `/home/yang/Desktop/项目/v023_repair/ds_control_fixes`
Scope: logic simulation only. **No synthesis, Vivado, STA, bitstream, board,
VNC, or push.** `work/`, the ZIP, old competition trees and other workers'
files were read-only. All new RTL/TB/scripts/logs are in this directory.

## 1. What was delivered

| item | result |
|---|---|
| PA-001 CSR interleaved 64-bit snapshot | confirmed before, fixed, tested |
| PA-002 FETCH/ERROR_DRAIN watchdog unbounded | confirmed before, bounded DRAIN + isolation, tested |
| PA-003 4 GiB DMA address wrap | confirmed before, 40-bit address in both v023 DMAs |
| PA-004 `write_bytes` ignored WSTRB | confirmed before, popcount in both v023 DMAs |
| 128-node ready-mask combinational scan | banked/pipelined scanner, 405 scenarios |
| `block_address` upstream cascaded multiply | 3-stage elastic pipeline, 3000-vector equivalence |
| storage descriptor handshake | pipelined address + 7-stage storage, handshake/DMA/error tests |
| regression | `bash scripts/run_all.sh` → rc=0, `RUN_ALL_PASS` |

No other worker file was edited. The storage candidate is a SHA-pinned copy of
`tasks/ds_critical_control/candidate/rtl/block_storage_dma_wide4_pipe_v1.sv`;
the graph scanner is a new module because `wc_superplan_ctrl.sv` belongs to the
graph worker.

## 2. Baseline and source hashes

Read-only sources and candidate snapshots are hashed in
`reports/SOURCE_SHA256.txt`; the re-run manifest is `reports/TEST_SHA256.txt`.
Key baselines:

| source | SHA-256 |
|---|---|
| `work/rtl/plan_submit_csr.sv` | `a0c914cf42ab68c3b10941c7c95f42a320ce18c2089213ed8fa7daaec621a79b` |
| `work/rtl/pl_execution_plan_v022.sv` | `e23c06c0757291a69a6d4ca03ed75a82681dc7764ae8a2f4bd6bb0284d0cb3bf` |
| `work/rtl/block_address_v020.sv` | `9d2bba3f38965133122ca37da9d1ffe06de10807b45c6c6758f08fbe7a3ce63b` |
| `work/rtl/axi_dma_v019.sv` | `930775c6ab8f1461ccd081f6b81f68b34f2da8f0fdf96c68b51b05f01da9b531` |
| v020_multi candidate | `7123c26fd3d91643497485c1ed7c9dedc3a4f06cf488bef36f711468dd6488e3` |
| ds_critical_control storage candidate | `2f8444b13020b753f613a990b5b15d86eb650697884b4ee4c68eea2760149efd` |
| ds_pl_autonomy `wc_superplan_ctrl.sv` | `53de6011ae2e7c630f282d0a3272995b91e991832113df0e7a933d3790db896c` |

## 3. PA-001 — CSR 64-bit snapshot

**Before** (`logs/csr_orig.log`): the original shares one `snapshot_high`
latch. Sequence `read 0x20, read 0x30, read 0x24` returns fetch's high word
`aabbccdd` instead of cycles' `11223344`; 9 checks fail (`PA001_FAIL`).

**Fix** (`candidate/rtl/plan_submit_csr_v023.sv`): one high-word snapshot per
64-bit register; low read samples atomically; high read returns that register's
sample; START clears the bank; high-only read samples current high. All other
register/START/IRQ semantics unchanged.

**After** (`logs/csr_v023.log`): baseline pairs, interleaved pairs for all nine
64-bit banks, high change after low, START clearing, magic/completed/generation,
bad-strobe rejection and busy-START rejection all pass; `PA001_PASS`, 0 errors.

This is telemetry only; it does not affect plan or engine numerics. Software
should still read low then high.

## 4. PA-002 — bounded FETCH / ERROR_DRAIN

**Before** (`logs/plan_before.log`, original v022 + v019):
- dead read: after 1000 cycles `busy=1 done=0 fault=0 err=09 state=3`
  (`PA002_FETCH_UNBOUNDED_CONFIRMED`).
- dead operator: `busy=1 done=0 fault=1 err=09 state=10`
  (`PA002_ERROR_DRAIN_UNBOUNDED_CONFIRMED`).

**Fix** (`candidate/rtl/pl_execution_plan_v023.sv`):
- FETCH timeout → `dma_abort=1`, `DRAIN`; `dma_read_ready` stays asserted so an
  accepted burst returns and drains.
- WAIT_OP timeout → `child_abort=1`, `DRAIN`; finish on child done or
  `child_drained`.
- Second `DRAIN_WATCHDOG` deadline → `drain_timeout=1`, `isolation_req=1`,
  `drained=0`, fault `0A`. It never claims a safe drain without evidence.
- `isolation_req` latches and rejects START until reset; recovery is tested.
- REQ timeout with no accepted AXI → safe fault `0B`, `drained=1`, no isolation.

**After** (`logs/plan_v023.log`, 10 phases, `PA002_PASS`):

| phase | observed |
|---|---|
| normal | done=1 fault=0 completed=1 drained=1 |
| dead read | DRAIN; then done=1 fault=1 err=0A drained=0 iso=1 timeout=1 |
| START during isolation | rejected, busy=0 |
| recovery after reset | normal done |
| late R (110 cycles) | done=1 fault=1 err=09 drained=1 iso=0, abort seen |
| dead child | DRAIN child_abort; done=1 err=0A drained=0 iso=1 |
| child drain-only late | done=1 err=09 drained=1 iso=0 |
| child fault | done=1 err=05 drained=1 iso=0 |
| request never ready | done=1 err=0B drained=1 iso=0, DMA never accepted |

The key distinction is explicit in the ports: `drained=1` means an observed
`dma_done`/child completion/drain; `drain_timeout=1 + isolation_req=1 +
drained=0` is an unsafe terminal state for the external firewall/reset. Abort
never cancels an accepted AXI transaction.

## 5. PA-003 / PA-004 — DMA wrap and WSTRB byte count

**Before** (`logs/dma_before.log`, v020_multi):
- `0xFFFFFFF0` × 2 beats → AR `0xFFFFFFF0` then `0x00000000`
  (`PA003_WRAP_BUG_CONFIRMED`);
- WSTRB `0x0007` one beat → `write_bytes=16` instead of 3
  (`PA004_STRB_COUNT_BUG_CONFIRMED`).

**Fix**:
- `candidate/rtl/axi_dma_v023_multi.sv` and
  `candidate/rtl/axi_dma_v023_bounded.sv`: 40-bit running address; a crossing
  continues at `0x1_0000_0000` instead of wrapping.
- `write_bytes += popcount(WSTRB)`.
- Multi candidate also adds `abort/aborted/drained/busy`, fixes spurious-B
  credit underflow, and has elaboration guards for v020 parameter hazards.

**After**:
- multi (`logs/dma_v023.log`): two ARs `0xFFFFFFF0`, `0x100000000`; 32 bytes;
  WSTRB counts 3 and 51; 256-beat multi-outstanding read (`ar_max=8`); abort
  read drains accepted R (`bfm_rbeats=128`); delayed-R abort drains; recovery
  read passes; `PA003_PA004_PASS`.
- bounded (`logs/dma_bounded.log`): same wrap and WSTRB results;
  `BOUNDED_PASS`.

Matrix worker contract: see `INTERFACE.md` §5. No matrix worker file was
modified.

## 6. Ready-mask 128-node scan

Existing candidate `tasks/ds_pl_autonomy/rtl/wc_superplan_ctrl.sv` scans all
128 nodes in one combinational first-found loop. No functional counterexample
was demonstrated in that file; this is a structural risk, not a claimed bug.

`candidate/rtl/ready_scan_banked_v1.sv`:
- four 32-node bank scans with registered per-bank first-ready results;
- lowest-bank/lowest-index pick (not first-found arbitrary order);
- dependency/`done_mask`/engine-free snapshot at `scan_start`, with done only
  growing; readiness completing mid-scan is picked next scan;
- `cand_valid` held until `scan_ack`; latency 6 cycles;
- 3-bit node type (1 MAT, 2 VEC, 3 LAY, 4 SEQ). A 2-bit field would silently
  lose SEQ=4; this was caught and fixed during bring-up.

`logs/ready_scan.log`: 5 deterministic + 400 randomized scenarios (all-ready
node 0, node 127 only, engine-class filter, dependency chain, unmet dependency,
done_mask change during scan); `READY_SCAN_PASS`.
No Fmax/timing claim; this only removes the 128-deep scan from one logic slice.

## 7. block_address pipeline and storage handshake

`candidate/rtl/block_address_v023.sv` splits the v020 cone:

```
S1: nrb/ncb/block_bytes, block_row*ncb
S2: +block_col, *block_bytes
S3: +base, extent, valid_rows/cols, valid
```

Arithmetic widths and 40-bit assignment context are preserved; a naive 32-bit
rewrite was rejected after mismatches on high extent bits. Handshake is
3-stage elastic with outputs held under backpressure.

`logs/block_address.log`: 3000 vectors (random, rows/cols=0, encoding=3,
out-of-range block ids, 4 GiB-adjacent base, 16-bit max dimensions) with random
output stalls; every field matches the read-only v020; `BLOCK_ADDRESS_PASS`.

Storage handshake (`logs/storage_handshake.log`, `STORAGE_HANDSHAKE_PASS`):
- address output held under backpressure;
- bad A read → HEADER `in_operation=1`, no DMA;
- good A read → validator wait, exactly 128 DMA beats, drain, HEADER `bad=0`;
- bad write → 1024 scalar words, WACK `write_error=1`, no DMA.
The 71-case storage equivalence remains the source task's evidence; this task
did not re-run it. Source hash is pinned in `reports/SOURCE_SHA256.txt`.

## 8. Test matrix and rc

`bash scripts/run_all.sh` (rc=0, `RUN_ALL_PASS`):

| log | content | expected result | rc |
|---|---|---|---|
| `logs/csr_orig.log` | original CSR interleaved | bug confirmed, 9 errors | 0 |
| `logs/csr_v023.log` | v023 CSR | `PA001_PASS` | 0 |
| `logs/plan_before.log` | original plan dead R/child | 2 unbounded confirmations | 0 |
| `logs/plan_v023.log` | 10 bounded-drain phases | `PA002_PASS` | 0 |
| `logs/dma_before.log` | v020_multi wrap/strb | 2 bug confirmations | 0 |
| `logs/dma_v023.log` | multi DMA 7 cases | `PA003_PA004_PASS` | 0 |
| `logs/dma_bounded.log` | bounded DMA 2 cases | `BOUNDED_PASS` | 0 |
| `logs/ready_scan.log` | 5 + 400 scan scenarios | `READY_SCAN_PASS` | 0 |
| `logs/block_address.log` | 3000 address vectors | `BLOCK_ADDRESS_PASS` | 0 |
| `logs/storage_handshake.log` | 4 storage/address cases | `STORAGE_HANDSHAKE_PASS` | 0 |
| `logs/lint_*.log` | Verilator lint, 7 modules | rc=0 each | 0 |

Compile logs and final summary are in `logs/` and
`reports/RUN_SUMMARY.txt`. All 7 candidate modules lint with Verilator
`-Wall -Wno-fatal` at rc=0; width/style warnings remain and are documented as
non-functional where applicable.

## 9. Integration notes

1. CSR replacement is drop-in.
2. Plan v023 requires the three drain ports and `DRAIN_WATCHDOG`; wire
   `child_abort` to engines and `isolation_req` to the supervisor/firewall.
3. Use v023 multi in matrix/DDR paths; keep 16-beat/4 KiB split and per-C K
   order. Use v023 bounded for plan fetch.
4. Graph worker integrates `ready_scan_banked_v1` into its own controller
   candidate; no other worker file was changed.
5. Matrix worker replaces each combinational `block_address_v020` with the
   pipelined module and waits for `out_valid` before the storage request; then
   re-runs matrix queue tests.
6. After integration, run the same-load before/after simulation. The attachment
   numbers (153→12.5→0.15 s, 91%, theoretical flow, CSA, 600 MHz) remain
   hypotheses, not acceptance criteria.

## 10. Limitations / not claimed

- No synthesis, STA, DRC, bitstream, board, VNC, push; no Fmax or 600 MHz
  claim. Ready-scan/address changes are structural only.
- No full-model inference, quantization-effect, or model-metric evaluation.
  Division/root approximation is another worker's scope; no numeric contract
  changed here.
- BFMs are protocol models, not DDR timing/bandwidth.
- The storage 71-case regression is referenced from `ds_critical_control`, not
  re-run here; only the handshake cases above were independently run.
- No AXI traffic is cancelled. A dead slave ends in an explicit fault +
  isolation request with `drained=0`, never a false safe-drain completion.
- The old `wc_superplan_ctrl.sv`, `work/`, ZIP, and other task directories were
  not modified. Integration is the main agent's step after this handoff.

## 11. 未完成 / integration still required

This worker delivers isolated candidates and contracts, not the whole V023
system. Not completed here:

1. **Graph controller integration** — `ready_scan_banked_v1` is not inserted
   into `wc_superplan_ctrl.sv` (another worker's file). The graph owner must
   replace the SCAN loop and re-run their controller/68-node tests.
2. **Matrix engine integration** — `block_address_v023` and the storage
   handshake are not wired into `block_engine_*` (matrix worker's file). The
   matrix owner must add the 3-cycle request-state wait, then re-run queue
   tests with W7/A16/C48 unchanged.
3. **Top-level/same-load integration** — no full plan/top-level simulation with
   all workers' candidates together, no CASE0000 inference, no same-load
   before/after end-to-end measurement. The attachment timing predictions are
   hypotheses, not verified here.
4. **DMA replacement in matrix paths** — `axi_dma_v023_multi` is verified in
   isolation only; the matrix owner must instantiate it and connect
   abort/drained.
5. **Storage full regression** — the 71-case equivalence belongs to
   `ds_critical_control`; only handshake/latency/error cases were re-run here.
6. **CSR firmware** — PS software should use the low-then-high pair protocol;
   firmware was not modified (host/PS files are out of scope).
7. **Timing** — no synthesis/STA/DRC and therefore no 250/300/600 MHz claim,
   no CDC signoff, no board/VNC/push.
8. **Numerical approximation** — division/root approximation and its measured
   quantization/model error are another worker's task; this report makes no
   accuracy claim.
