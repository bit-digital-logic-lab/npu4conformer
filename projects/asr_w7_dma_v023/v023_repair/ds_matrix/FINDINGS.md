# FINDINGS — ds_matrix V0.23 P2 unified candidate

All statements below are logic-simulation results (Icarus 14 / Verilator 5.047),
not synthesis, STA, board-DDR or whole-model results.  Source SHAs are in
`logs/source_sha256.txt`; every command/rc is in `logs/commands.log`.

## F-001 — the mature storage candidate needed a real interface/width audit, not a file copy

The three ds_storage_overlap modules were copied and then adapted:

- `block_storage_stream_v2`: same A/W double-stage load and posted C48 stream,
  plus PA-003/PA-004 address/strobe checks.
- `operand_banks_dual_v2`: unchanged bank mapping; the A row-half/chunk mapping
  was re-derived and checked against the 32x32 A16 layout in `tb_storage_unit`.
- `block_engine_prefetch_v2`: new II=1 collect and parameterized array.

The one functional bug found during integration was in the engine's C-cache
slot address, not in the copied storage:

`{slot[0],1'b0}` is only a 2-bit concatenation.  For slot 1 it selected group 2,
not group 256.  With the old C fixture (`eng_c1`, two output blocks) block 1
read/wrote block 0's cache groups; `run_pipe4_c1` failed with 7135 mismatches.
It was fixed to `{slot[0],8'd0}+...`.  This is exactly why the old-C case was
rerun instead of trusting the V1 report.

## F-002 — C read-modify-write is now II=1 for groups, with one stall per 16-value segment

Old `C_READ -> COLLECT` is two cycles per 4-value group.  New
`c_cache_banked4_pipe` has separate synchronous read and write ports; group
g+1 is read while group g is written.  The 256:4 array MUX is registered with
the read address (`pipe_sums`), and the result is taken from the write/bypass
datapath, not read back from BRAM.

Measured K=96, M=64, N=32, PIPE=4:

| item | V020 baseline | V1 old candidate | this candidate |
|---|---:|---:|---:|
| task cycles | 11839 | 5896 (reported) | **4552** |
| C groups | 1536 | 1536 | 1536 |
| C collect cycles | not exposed | not exposed | **2448** |
| speed vs baseline | 1.00x | 2.01x | **2.60x** |

2448 cycles for 1536 groups is 1.59 cycles/group because every 16-value
segment still spends one cycle accepting the `cseg` command.  That is measured,
not a 1.00 estimate.

## F-003 — configurable PE depth and real drain, no hard-coded 61/65

`array16_w7_c48_cfg` is instantiated with `PIPE_STAGES`.  RUN exits on
`run_cycle >= k_local+14 && array_drain_done`, where `k_local` is the remaining
K in that tile.  Same output golden in every case:

| PIPE_STAGES | PE drain | ARRAY_DRAIN | RUN cycles/quadrant (measured) | task cycles K96 |
|---:|---:|---:|---:|---:|
| 3 | 4 | 19 | 67 | 4528 |
| 4 | 5 | 20 | 68 | 4552 |
| 5 | 6 | 21 | 69 | 4576 |
| 6 | 7 | 22 | 70 | 4600 |

The +1 cycle versus the nominal 66/67/68/69 is the array quiet-counter sampling
boundary; it is conservative (never early).  The 16x16 result payload is
bit-identical to the independent integer golden for all four settings.

## F-004 — flush no longer discards the tail

`flush` is `reset || state==FAIL` only.  Leaving RUN for C_READ does not flush.
Quadrant-to-quadrant clearing uses `clear_sum` in CLEAR after `drain_done`, so
the pipe is empty.  The matching golden for PIPE=4/5/6 is the evidence that the
bottom-right PE tail is not lost.

## F-005 — PA-004: write bytes now follow WSTRB

`axi_dma_v020_multi_v2` and `block_storage_stream_v2` count
`popcount(WSTRB)`.  Directed result:

`STROBE mem=00 01 02 00 write_bytes=3 err=0` (old metric reported 16).
`tb_dma_multi` W2: 4 beats with last WSTRB=0x0007 -> `write_bytes=51`.
The AXI cluster reports `wr_bytes=6144` for 64 full 96-byte segments.

## F-006 — PA-003: 40-bit DMA address, no 4 GiB wrap

`next_addr` is 40-bit; `m_axi_araddr`/`m_axi_awaddr` use the full 40 bits.
Directed test `request_address=0xFFFFFFF0, beats=2` produces
`a0=0x00FFFFFFF0`, `a1=0x0100000000`, not `a1=0`.  The storage also rejects
any C segment whose 64-bit end or 32-bit address would overflow.

## F-007 — multi-outstanding DMA is actually exercised

AXI cluster K=32: `rd_ar_outstanding_max=8`, BFM `max_rd_outstanding=8`,
read FIFO high=2, `rd_bursts=12`, `rd_bytes=3072`, `wr_bursts=65`,
`wr_bytes=6144`.  The 65th write burst is a real 4 KiB split of one 96-byte
segment at 0x3FC0; it is not an extra tensor.
K=96 C=1: `rd_bursts=120`, `rd_bytes=30720`, `wr_bursts=130`,
`wr_bytes=12288`, `max_rd=8`.

## F-008 — traffic ledger: exact per-master byte reconciliation, W reload duplicate

`traffic/report_k1` and `traffic/report_c1_k96` are generated from the actual
`valid&&ready` trace:

- K32: axi_r 3072 B, axi_w 6144 B; ledger-minus-interval = 0 on both.
- K96 C=1: axi_r 30720 B, axi_w 12288 B; ledger-minus-interval = 0 on both.
- K96 C=1: W reloads the same three W blocks for the second output block:
  6 transfers / 6144 B total, 3072 B unique, **3072 B repeat candidate**.
  This is a candidate, not a proven removable byte count.  The two output
  blocks have the same `bc` and different `br`, so a resident-W schedule (not
  resident-A) is the relevant experiment for this shape.

`ddr_bfm` is a shared BFM channel lane.  Its payload byte count is the union of
axi_r+axi_w (9216 / 43008 B), so its ledger-minus-interval is intentionally
negative (-9216 / -43008); it has no independent tensor identity and is not
added to the per-master ledgers.

## F-009 — Resident-A assessed, not selected

Current dual-stage operand bank: 2 x (2048 A + 1024 W) = 6144 B.  Resident-A
across `bc` needs `nbk` A blocks: K=96 -> 3 x 2048 = 6144 B A alone, plus at
least 2 W stages (2048 B) and the C cache (2 x 6144 B).  For K=4096, nbk=128,
which is not bounded by the current bank.  Read-port count stays 16 rows per
stage but adds a stage-select mux in front of the array read path, which is the
opposite of the "shorter local path" goal without STA.  Measured A read is not
the bottleneck: axi_r payload is 7.1% (K32) / 22.0% (K96 C1) of the window.
Therefore the unified path stays with A/W double-bank prefetch; Resident-A is
left as an optional experiment, not a claimed optimization.

## F-010 — C48 wrap / overflow contract retained

The PE accumulator is the ds_pe_pipeline INT48 native carry chain.  The
ds_pe_pipeline report/test covers 135,000 max-magnitude products and 2^48 wrap;
that exhaustive PE test was **not rerun in this task** (we reused its RTL and
ran the matrix integration tests, including P=12 saturation).  In the engine,
`collected_values` is the low 48 bits of the 49-bit `c_old + sum`, exactly as
V020.  The baseline `c_add[48]!=c_add[47]` overflow
fault (code 8) is retained; it was not silently converted into saturation.

## F-011 — positions/clip edge

`run_p12` uses `positions=0xCCCC` (all J nibbles = 12) and `clip=1`, with the
same independent golden generator.  It passes (4147 cycles), exercising the
P=12 saturation branch.  The testbench takes `+pos=...` so the fixture's
positions are not silently replaced by the default 0x3210.

## F-012 — error drain and backpressure

- read error: `run_errrd` -> `PASS_FAULT code=09 done=1 cwr_pending=0`.
- write error: `run_errwr` -> `PASS_FAULT code=0a done=1 cwr_pending=0`.
- bad W parity: `run_badpar` -> `PASS_FAULT code=09 done=1 cwr_pending=0`.
- write backpressure (`WR_GAP=60,B_DELAY=40`): `run_bp` -> PASS, 26701 cycles,
  `cwr_pending=0`; C collect stalls to 24453 cycles but no group is lost.
- storage unit: `ovsame=9`, `rdwr=708`, A/W 2048/1024 values and 64 C segments
  (6144 B) all match.

## F-013 — limits that must not be rounded up into claims

- No full CASE0000 / ONNX / WER / whole-model accuracy run.  This task only has
  the integer matrix block path; FP32/QDQ/vector/layout are outside it.
- No synthesis, implementation, STA, CDC report or frequency measurement.
  PIPE=4/5/6 is a structural split, not a 300/600 MHz result.
- The AXI BFM is a protocol/memory model with configurable stalls and multiple
  outstanding requests; it is not a PS DDR controller, PHY or board timing
  model.
- The PS hard DDR controller topology is unchanged; "PL autonomous DMA" here
  means the PL storage/DMA engine runs from its own descriptors after one
  start, not that the Zynq PS hard controller is bypassed.
