# INTERFACE — ds_control_fixes integration contract

This document is the handoff to the main integrator and to the matrix/graph
workers. No file outside this directory was modified. All candidates are logic
simulation artifacts; no STA/Fmax claim is made.

## 1. Files

| file | module | replaces / role |
|---|---|---|
| `candidate/rtl/plan_submit_csr_v023.sv` | `plan_submit_csr_v023` | drop-in replacement for `work/rtl/plan_submit_csr.sv` (same ports) |
| `candidate/rtl/pl_execution_plan_v023.sv` | `pl_execution_plan_v023` | supersedes `pl_execution_plan_v022`; adds bounded-drain ports |
| `candidate/rtl/axi_dma_v023_bounded.sv` | `axi_dma_v023_bounded` | single-outstanding bounded DMA for plan fetch; PA-003/004 fixed |
| `candidate/rtl/axi_dma_v023_multi.sv` | `axi_dma_v023_multi` | multi-outstanding DMA for matrix/DDR; PA-003/004 fixed |
| `candidate/rtl/ready_scan_banked_v1.sv` | `ready_scan_banked_v1` | 128-node banked/pipelined ready-mask scanner |
| `candidate/rtl/block_address_v023.sv` | `block_address_v023` | 3-stage pipelined block address former |
| `candidate/rtl/block_storage_dma_wide4_v023.sv` | `block_storage_dma_wide4` | SHA-pinned copy of `ds_critical_control` 7-stage validator |

Source hashes: `reports/SOURCE_SHA256.txt`, `reports/TEST_SHA256.txt`.
Reproduce: `bash scripts/run_all.sh` (writes only under this task directory).

## 2. `plan_submit_csr_v023` (PA-001)

Ports, register map, START/IRQ/B-response semantics are unchanged from
`plan_submit_csr`. Only the 64-bit readback snapshot changed.

- Each 64-bit bank has its own captured high word.
- Low-word read: captures `{high, low}` for that bank at the read handshake.
- High-word read: returns that bank's captured high word even if other banks
  were read in between.
- High-only read (no prior low): captures and returns the current high.
- START clears all snapshot banks; software should still read low then high.

Software contract:

```
read  cycles_lo   (0x20)
read  cycles_hi   (0x24)   // paired high, regardless of other reads between
```

Do not infer a coherent 64-bit value from two independent high/low reads if a
counter can change between them; use the pair order above.

## 3. `pl_execution_plan_v023` (PA-002)

### 3.1 Ports

All `pl_execution_plan_v022` ports are retained. Added:

```systemverilog
output reg         child_abort;     // stop accepting new child work
input  wire        child_drained;   // child has no accepted AXI work left
output reg         dma_abort;       // advisory: stop issuing NEW DMA bursts
output reg         drain_timeout;   // second deadline expired
output reg         isolation_req;   // request external firewall/reset
output reg         drained;         // 1 only after observed completion/drain
output wire        unsafe_state;    // == isolation_req
output wire [3:0]  state_code;      // 0 IDLE .. 10 FINISH, for observability
output reg  [63:0] drain_cycles;    // added to the existing counters
```

Parameter added: `DRAIN_WATCHDOG` (default `250000000`). Existing `WATCHDOG`
still bounds request/fetch/operator waits.

### 3.2 Semantics

State sequence:

```
IDLE -> PRECHECK -> REQ -> FETCH -> CHECK -> [VREQ -> VFETCH] ->
DISPATCH -> WAIT_OP -> ... -> FINISH
                        \-> DRAIN -> FINISH
```

- REQ/VREQ timeout: no AXI request was accepted (`dma_request_ready=0`), so the
  plan reports fault `0B`, `drained=1`, no isolation.
- FETCH/VFETCH timeout: `dma_abort=1`, `DRAIN` source = DMA. `dma_read_ready`
  remains asserted in DRAIN so the already accepted AXI burst can return and
  be consumed/drained. `dma_done` ends DRAIN with fault `09`, `drained=1`.
- WAIT_OP timeout: `child_abort=1`, `DRAIN` source = child. End on
  `matrix_done`/`vector_done`/`layout_done` or `child_drained`; fault `09`,
  `drained=1`.
- Any normal completion sets `drained=1`; `drained` is cleared at START.
- If DRAIN exceeds `DRAIN_WATCHDOG`: `drain_timeout=1`, `isolation_req=1`,
  `drained=0`, `fault=1`, `error_code=0A`, `done=1`. This is a bounded fault
  notification, not a claim that AXI is drained.
- `isolation_req` latches. START while `isolation_req=1` is rejected
  (`rejected_starts++`) and does not run; recovery requires reset/firewall.
- `child_abort`/`dma_abort` are level requests. They never cancel an accepted
  AXI transaction. Only `dma_done`/`child_drained` are drain evidence.

### 3.3 Child contract (matrix/vector/layout engines)

- `child_abort=1`: stop accepting new descriptors; do not start new AXI bursts.
- `child_done`: existing completion, implies the child has no accepted work
  left.
- `child_drained`: assert when all accepted child AXI transactions have
  completed/been consumed, even if the child cannot produce a normal `done`.
- A child that can assert neither must not be reported safe; the plan will
  time out and request isolation.

### 3.4 DMA contract

`dma_abort=1` means “do not issue NEW AR/AW”. A DMA must continue to accept all
R/B responses of accepted bursts and then assert `dma_done`. It must not drop a
response to make `done` appear early. `axi_dma_v023_bounded` implements this for
the plan fetch path.

## 4. `axi_dma_v023_bounded` (plan fetch; PA-003/004)

Ports are `axi_dma_v019` plus:

```systemverilog
input  wire abort;
output reg  aborted;
output reg  drained;
output reg  busy;
```

- Running address internal width is 40 bits; `m_axi_*addr` is 40 bits.
  `request_address` stays 32-bit; a 4 GiB crossing continues at
  `0x1_0000_0000`.
- `write_bytes` increments by `popcount(write_strobe)`.
- `abort` in AR/AW before acceptance: no transaction, finish with
  `aborted=1`, `drained=1`.
- `abort` during RDATA/WDATA/BRESP: drain the accepted burst, then finish with
  `aborted=1`, `drained=1`.
- `drained=1` only after the FINISH cycle; it is not a timeout.
- No internal channel timeout. The plan’s DRAIN deadline covers a dead slave.

## 5. `axi_dma_v023_multi` (matrix/DDR worker; PA-003/004)

Port shape matches `axi_dma_v020_multi` plus the same `abort/aborted/drained/busy`
group. Parameters: `MAX_OUT` (power of two), `FIFO_BEATS`,
`MAX_BURST<=16`; elaboration guards added for the v020 hazards.

- 40-bit `next_addr`; no 4 GiB wrap (PA-003).
- `write_bytes += popcount(WSTRB)` (PA-004).
- Multiple outstanding AR; R returned in AR order (no RID). B credit cannot
  underflow on a spurious B; it latches `err_sticky`.
- On read abort: stop new AR; wait until `tag_cnt==0` (all accepted R bursts
  returned), then flush the on-chip FIFO tail and finish `aborted/drained=1`.
  This drops on-chip bytes only, never an AXI response.
- On write abort: stop new AW; an accepted burst must still receive its W beats
  from the upstream; finish when W beats and B credits are zero. The upstream
  must not stop W mid-burst.
- On error: stop new requests; accepted R/B are drained (read FIFO may be
  flushed once tags are gone).

Matrix worker integration checklist:

1. Keep the existing 16-beat/4 KiB split and per-C K order.
2. Use the new `write_bytes` for telemetry/roofline; do not add a second
   fixed-16 multiplier.
3. Connect `abort` to the plan/engine abort request and expose `drained`.
4. If only single-outstanding is needed, use `axi_dma_v023_bounded`.

## 6. `ready_scan_banked_v1` (graph/plan worker; structural)

```systemverilog
module ready_scan_banked_v1 #(
 parameter integer MAX_NODES=128,
 parameter integer BANK_NODES=32,
 parameter integer BANKS=4
)(
 input clk,rst_n,
 input scan_start,
 input scan_ack,
 input [MAX_NODES-1:0] pending,
 input [MAX_NODES*128-1:0] dep_mask_flat, // node i at i*128 +:128
 input [MAX_NODES*3-1:0] node_type_flat,  // node i at i*3 +:3
 input [127:0] done_mask,
 input [3:0] engine_free,                 // [0]=SEQ,[1]=MAT,[2]=VEC,[3]=LAY
 output reg cand_valid,
 output reg scan_done,
 output reg [6:0] cand_id,
 output reg [2:0] cand_type,
 output reg [1:0] cand_bank,
 output reg [31:0] scan_cycles,
 output wire scan_busy
);
```

- Type field is **3 bits**: 1=MAT, 2=VEC, 3=LAY, 4=SEQ. A 2-bit field cannot
  represent SEQ=4 (a bug caught during bring-up).
- `scan_start` in IDLE latches `pending`, `done_mask`, `engine_free`; the
  dependency masks are immutable plan descriptors and are not re-latched.
  Scans B0..B3, each with a 32-node local priority encoder; PICK chooses the
  lowest ready bank, hence the lowest node index in the snapshot.
- Latency is 6 cycles to `cand_valid`/`scan_done`; `cand_valid` is held until
  `scan_ack` (or until the candidate’s live pending bit disappears).
- A dependency becoming done during the scan is intentionally picked next
  scan; the snapshot keeps the result consistent.
- The loader must still enforce lower-index-only `dep_mask` and the 128-node
  limit; this module only evaluates readiness.

Integration in `wc_superplan_ctrl`: replace the SCAN `for` loop with this
scanner, drive `scan_start` in the SCAN state, map type 1..4 to the four engine
active bits, and dispatch on `cand_valid`/`cand_type` then pulse `scan_ack`.
Do not edit another worker’s file; the graph owner should apply this through
their own candidate.

## 7. `block_address_v023` (matrix worker)

```systemverilog
in_valid / in_ready
operands: base[31:0], rows[15:0], cols[15:0], block_row[15:0],
          block_col[15:0], encoding[1:0]
out_valid / out_ready
outputs: address[31:0], valid_rows[15:0], valid_cols[15:0],
         extent_bytes[39:0], valid
```

- 3-stage elastic pipeline; latency 3 cycles when not stalled; outputs held
  under `out_ready=0`.
- Arithmetic matches v020 exactly, including the 40-bit assignment context for
  `offset`/`extent`; do not “simplify” to 32-bit.
- The matrix engine must instantiate one per A/B/C address (or time-multiplex
  with a valid tag), wait for `out_valid`, and only then present the storage
  request. Do not feed `address` combinationally as in v020.
- The block engine’s `req_address`/`stored_addr` path still needs its own
  register boundary; this module only replaces the address former.
- If the engine cannot accept the 3-cycle latency, keep v020 until the
  storage/engine schedule is reworked; equivalence alone is not a performance
  argument.

## 8. Storage descriptor handshake (matrix worker)

`block_storage_dma_wide4_v023.sv` keeps the `block_storage_dma_prefetch`
ports, with the 7-stage validator from `ds_critical_control`:

- `req_ready = idle && rst_n`; request fields are frozen at acceptance.
- Read: ~8 cycles of validator; bad descriptor goes to HEADER with no DMA;
  good descriptor goes to RREQ, drains the DMA, then HEADER.
- Write: data packing starts immediately; validator runs in parallel; WVAL
  waits for the verdict; WACK is the sole write error exit.
- `header_in_operation` is `bad`; a good read has `header_in_operation=0`.
- `header_ready`/`data_ready`/`out_ready` are real backpressure inputs.
- `abort_scalar` remains valid only in HEADER/RPRE/RSCALAR as in the source.
- W7/A16/C48 packing, parity checks, ACL and error order are unchanged.
- The 71-case equivalence evidence and its exact source hash are in
  `tasks/ds_critical_control/`; this task only re-ran the handshake cases in
  `logs/storage_handshake.log`.

## 9. Integration order (recommended)

1. CSR: replace `plan_submit_csr`; run `logs/csr_v023.log` sequence.
2. Plan: replace `pl_execution_plan_v022` with v023; wire `child_abort` to
   engines, `child_drained` from their AXI drain monitors, `dma_abort` to the
   bounded fetch DMA; expose `isolation_req` to the supervisor. Do not treat a
   drain timeout as a successful completion.
3. DMA: use v023 multi in matrix/DDR paths; run PA-003/004/abort/recovery.
4. Scanner: graph owner integrates `ready_scan_banked_v1` into their own
   controller candidate; verify dependency masks and 3-bit type.
5. Address: matrix owner replaces the combinational `block_address_v020`
   instances with `block_address_v023` and adds the request-state wait; then
   re-run the matrix queue tests.
6. Only after integration, run the same-load before/after simulation. Do not
   use the 153→12.5→0.15 s attachment numbers as acceptance criteria.

## 10. Out of scope / not claimed

- No synthesis, STA, DRC, bitstream, board, VNC, push.
- No Fmax/600 MHz claim. Structural path shortening is not STA evidence.
- No full-model quantization/accuracy evaluation; division/root approximation
  is another worker’s scope and its error must be measured there.
- BFMs are protocol models, not DDR timing.
- Host-once/PL-autonomy and W7/A16/C48/QDQ contracts are untouched; this task
  adds no runtime host control.
