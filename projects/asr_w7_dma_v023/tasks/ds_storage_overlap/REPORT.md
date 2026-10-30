# REPORT — ds_storage_overlap V1

Date: 2026-10-29 (Asia/Shanghai)
Scope: logic-only verification. **No synthesis, no Vivado, no DRC/STA, no
board, no VNC, no network deployment, no push.** 300/600 MHz are structural
targets only and are **not claimed as achieved timing**.

## 1. Executive result

The two serialization points named in the task were reproduced and removed for
the A/W operand path and the C48 output path:

1. `block_storage_dma_wide4` waits for the **whole** A/W block DMA (`RDMA` ->
   `RCHECK` -> `HEADER` -> `RPRE` -> `RSCALAR`) before presenting any scalar
   data, and `WSCALAR` collects all 1024 C48 values before `WREQ`.
2. `block_engine_banked_v020` loads C (if present), then A (`A_DATA`), then B
   (`B_DATA`), then runs; it cannot use the K tile that is being transferred.

Candidate V1 provides:

- two complete A/W stage banks (`operand_banks_dual_v1`); storage fills stage
  S^1 while the array runs on stage S;
- C48 output accepted 4 values/cycle, packed to 128b beats and **posted** on an
  independent write transaction port; the write port does not wait for BRESP
  before the next segment;
- independent read and write transaction interfaces with explicit queue
  credits and stage/slot ownership;
- an error drain that first satisfies accepted DMA beat counts (zero-strobe
  padding for a truncated posted write), then reports one fault.

Same workload, same BFM stalls, same memory fixtures:

| case (M,N,K; C) | baseline original RTL | candidate V1 | ratio |
|---|---:|---:|---:|
| 32,32,32; C=0, stress DDR (`RD_LAT=5,RD_GAP=12,WR_GAP=12,B=8`) | 6094 cycles | 4155 cycles | 1.47x |
| 64,32,96; C=0, faster DDR (`2,1,1,4`) | 11839 cycles | 5896 cycles | **2.01x** |
| 64,32,96; C=1 existing partial sum | 13132 cycles | 6673 cycles | 1.97x |
| 64,32,96; C=0, write backpressure (`WR_GAP=60,B=40`) | 34620 cycles | 27673 cycles | 1.25x |

The cycle counts are **logic simulation cycle counts**, not wall-clock and not
a board DDR timing claim.

## 2. What was wrong (source evidence)

Read-only originals:

- `work/rtl/block_storage_dma_prefetch.sv`
  - `RDMA` accepts only the block DMA, then `RCHECK` counts beats, then
    `HEADER`, `RPRE`, `RSCALAR`. `data_valid=state==RSCALAR`; scalar data
    cannot start before `rd_done`.
  - `WSCALAR` shifts `out_data[47:0]` into `pack` and only on
    `word_index==1023` checks the final pack and goes `WREQ`; the write request
    is after the whole 1024-value collect.
  - only one request context, one `dma_request_*` port; read and write are
    serialized by the same state machine.
- `work/rtl/block_engine_l1bank_v020.sv`
  - per K block: `C_REQ/C_DATA` (existing C), `A_REQ/A_DATA`,
    `B_REQ/B_DATA`, `CLEAR`, `RUN`, `C_READ/COLLECT`; all transfers complete
    before `RUN`.
  - C writeback is `EVICT_*`/`FLUSH_*` after a block is retired, so the C block
    is collected in cache and written later.
- `work/rtl/operand_banks_v020.sv` is a single A/W bank, so the compute side
  and the next DMA fill cannot use different banks.

Baseline counters quantify the serial phases (same fixture, original RTL,
`run_base_fast_counters.log`):

```
BASE cycles=11839 compute=1584 st_rdwait=1183 st_wrwait=781 st_scalar=5122
```

`st_scalar=5122` cycles are the C48 scalar collect/pack phase; `st_rdwait`
and `st_wrwait` are the DMA waits outside compute. The candidate has no
whole-block scalar phase; its writes are streamed during COLLECT.

## 3. Candidate design

### 3.1 A/W double-bank prefetch

`operand_banks_dual_v1` holds two complete stages. Each stage stores A in 16
row-pair banks of four 128b chunks (8 A16 each) and W in 16 column banks (32
k x 2 n-halves). The DMA write port is 128b/beat; the compute read port is
asynchronous distributed RAM with 16 per-row/column k addresses, preserving
the V020 `k = run_cycle - row/col` skew. The unit test checks all 1024 A16 and
all 1024 W7 values against raw memory.

`block_engine_prefetch_v1` issues A(bk+1)/W(bk+1) into stage S^1 before
`CLEAR/RUN`; the storage read engine fills that stage during RUN/COLLECT. At
the next K tile the engine only waits if the prefetch is late.

### 3.2 C48 streamed, posted output

Each 96-byte row segment is 16 C48 values = 6 x 128b beats. `COLLECT` produces
four C48 lanes per group; the engine issues one `cseg` command per segment and
four `cval` groups. `block_storage_stream_v1` packs the 48-bit values into a
byte shifter and emits a 128b beat whenever >=16 bytes are present. `cval_ready`
is real backpressure; the COLLECT state holds the group and cache write until
the packer accepts it. The write transaction is posted; `cwr_idle` waits for all
BRESP completions before `done`/result retirement.

Measured streaming/backpressure evidence:

- normal: `write_blocks=128` segments, `wrbeats=768` (12288 B for 2 blocks),
  `ov_wr=1293` cycles, `PASS`.
- write-stall build: `wrstall=22906`, `cycles=27673`, `ov_wr=23225`,
  `PASS`; read prefetch still completes (`prehit=4`, `prewait=396`) while the
  write port is heavily stalled.
- existing partial C (`C_VALID=1`): 2 C loads (768 extra beats), `cycles=6673`,
  `PASS`.

### 3.3 Ownership, ACL and tags

- `stage_release[stage]` frees a stage; the engine pulses it after the last
  compute/collect use, and on the final K block.
- A/W headers are captured at command accept and checked by the engine before
  use: epoch, layer, matrix id, block row/col, allowed ops, encoding, in-op,
  completed. A mismatch never issues DMA.
- C header/valid/completed checks are the original V020 rules. C slot tags
  keep epoch/base/layer/matrix/r/c/rows/cols/allowed/completed. A new
  `tag_done` prevents a completed block from being reused as a fresh
  accumulation without reloading (needed because output is posted).
- The W byte even-parity rule is checked at the storage load boundary; a bad
  byte produces a stage fault, tested with `fixtures/eng_badpar`.
- On fault/abort, accepted read transactions drain; never-posted C segments are
  dropped; the accepted write command is padded with zero strobes to satisfy
  the DMA beat count. Both read-error and write-error tests return `done=1`,
  `fault=1`, `cwr_pending=0`.

## 4. Verification evidence

### 4.1 Tools and tests

- Icarus Verilog 14.0: real-simulator K=96 random BFM run
  (`run_icarus_k3.log`), PASS.
- Verilator 5.047: all other RTL/BFM runs, including unit, overlap,
  backpressure, error drain, C partial, and AXI layer.
- Independent Python integer golden (`tests/gen_engine_vectors.py`) for A16 *
  W7(S/J/M), positions, clip, signed A, W parity, INT48 K-order sum. The golden
  was validated against the unmodified baseline engine, not against candidate
  output first.
- No numerical stub: the tests use `array16_direct_v020` / `pe_direct_v020`
  and the real `c_cache_banked4`; the FMA/IP path is not involved in this
  integer block path. FP32 FTZ/RNE/FMA and QDQ are untouched and **not tested
  here**.

### 4.2 Test cases (all rc=0 in `logs/commands.log`)

| test | result | key metric |
|---|---|---|
| `tb_storage_unit` | PASS | A/W all 2048/1024 values match; C 64 segments / 6144 B match; `ovsame=9`, `rdwr=708` |
| `tb_engine_overlap` C=0 fast | PASS | 5896 cycles, `prehit=4`, `ov_rd=523`, `ov_wr=1293` |
| same, seeds 1/2/3 | PASS | 5897-5898 cycles, same output, seed-dependent stalls |
| same, C_VALID=1 | PASS | 6673 cycles, 1920 read beats, `prehit=4` |
| same, write backpressure | PASS | 27673 cycles, `wrstall=22906`, `ov_wr=23225` |
| read-error injection | PASS_FAULT | code 09, `done=1`, `cwr_pending=0` |
| write-error injection | PASS_FAULT | code 0a, `done=1`, `cwr_pending=0` |
| bad W parity | PASS_FAULT | code 09, `done=1` |
| K=32 candidate | PASS | 4155 cycles |
| M32 N64 K64 (bc=0/1) | PASS | 4324 cycles, 2 output blocks, 128 C segments |
| `tb_storage_axi` | PASS | original `axi_dma_v019` x2 + AXI128 BFM; 8 read bursts / 66 write bursts, 2048 B read / 6144 B write, 0 errors |
| baseline K=32 | PASS | 6094 cycles |
| baseline K=96 fast | PASS | 11839 cycles |
| baseline K=96 C=1 | PASS | 13132 cycles |
| baseline K=96 backpressure | PASS | 34620 cycles |
| Icarus K=96 random BFM | PASS | 2948 cycles, `prehit=2`, `ov_rd=261`, `ov_wr=645` |

“PASS_FAULT” means the test expected a drained fault and verified `done=1`,
`fault=1`, no pending accepted transaction. It is not a normal-output pass.

### 4.3 Before/after fairness

The baseline and candidate use the same:

- A16/W7/C48 fixtures from the same Python generator and the same `init.hex`;
- `txn_dma_bfm` with the same seeds/stalls and same 1-beat/cycle shared
  bandwidth arbitration;
- A/B/C bases, block sizes, allowed ops, positions and clip;
- comparison against the same expected C values.

The candidate does add more write **commands** (64 segments/block vs 1
whole-block write) but exactly the same bytes (6144 B/block). This is reported
as a transaction-count cost, not hidden.


### 4.4 Traffic ledger (candidate C0, real cycle trace)

`traffic/make_trace.py` converts the Verilator per-cycle `valid&&ready`/state
trace into the traffic-ledger JSONL contract; `traffic/report_c0/` is the
generated report.  Window = 5896 engine-busy cycles; initialization/preload is
excluded.  Coverage is 100% and the ledger/interval byte difference is 0.

| resource | payload cycles | valid bytes | payload fraction | command | wait | idle |
|---|---:|---:|---:|---:|---:|---:|
| axi_r (storage read) | 1152 | 18432 | 19.5% | 12 | 18 | 4714 |
| axi_w (storage write) | 768 | 12288 | 13.0% | 128 | 921 | 4079 |
| compute | 1584 (RUN) | 0 | — | — | 420 operand wait | 3840 C collect + 52 control |

Unique bytes: A 12288 + W 6144 + C write 12288 = 30720 B.  C read is 0 for
C=0.  The ledger reports **0 duplicate-candidate bytes** for A/W/C; the
`ledger_minus_interval` difference is 0 on both read and write.  This is a
module-level ledger only, not a full-model traffic claim.

**Dependency-corrected analysis.**  A naive “all resources independent” bound
would be max(read 1152, write 768, compute 1584) = 1584 cycles, which is not a
valid bound because C write depends on the final C collect.  Per K tile the
dependency chain is RUN (264 cycles) then C collect (640 cycles); 6 K tiles
(2 output blocks x 3 K) give 6 x 904 = 5424 cycles.  Candidate is 5896 cycles,
only 8.7% above that dependency bound.  Read (192 beats/K) is hidden under
RUN; the final C write (384 beats/block) is hidden under collect.  The baseline
is 11839 cycles, 2.18x above the same dependency bound.

The ledger therefore identifies the **next** bottleneck, not DMA: C collect is
3840 cycles (65% of the window), because `c_cache_banked4` is used as
C_READ (1 cycle) + COLLECT (1 cycle) per four-value group.  A pipelined
1-cycle/group C read-modify-write (with same-address bypass) would cut the
collect term from 640 to 320 cycles/K and has a structural estimate of
6 x (264+320) + ~472 overhead = ~3976 cycles, i.e. about 1.48x more.  This is a
design estimate, not measured; it is left as the next implementation step.
Write command overhead is also visible: 128 segment commands / 921 wait cycles
for 768 beats.  A 192-byte row transaction (both col halves together) would
halve command count, but the current quadrant order produces the two halves at
different times; it needs a small row buffer or a different quadrant schedule.
Two further serial remnants are visible: (a) with C_VALID=1, the 384-beat C
partial load is completed before RUN, although RUN does not read C until
COLLECT; overlapping it with the first K RUN could hide roughly 264 of 384
beats per block; (b) the 396-cycle `operand_wait` is mostly the next block's
A0/W0 load at the block transition; issuing it during the previous block's
final collect/WAITWR would hide it.  Both are follow-ups, not V1 claims.

**Bandwidth/timing context from the new supervisor research:** AMD HP tuning
recommends 128b x 16-beat bursts; the 16-beat length is not a defect, and the
relevant issue is hiding latency with outstanding requests.  This candidate
does not change AXI burst length; ds_ddr owns the 128b/16-beat master and
outstanding count.  The simulated numbers are cycles only.  PS AXI is nominally
<=333 MHz; any 600 MHz local compute domain needs CDC/async FIFO, which this
task does not implement or verify.  The board DDR4/64-bit and HP128@125 MHz
(2 GB/s-class) figures are not used to claim a B/s result here.


**PE/bandwidth sanity (not a sizing or TOPS claim).**  The C=0 fast case
executes 393216 MACs (2 output blocks x 64x32x96) with 30720 unique DDR bytes
(A+W+C write), so the measured module-level intensity is I = 12.8 MAC/B.
Using the supervisor's `P <= B_eff * I / f` form, a 2 GB/s HP and 300 MHz give
about 85 equivalent PE; 600 MHz gives about 43.  This module alone therefore
does **not** support 256 PE at 300/600 MHz with this tile/residency; larger
tiles or more effective bandwidth are required.  The RUN phase is 1584 cycles
(248 MAC/cycle peak), but the whole task is 5896 cycles, i.e. 66.7 MAC/cycle
average; that is a cycle-simulation number, not a TOPS or timing result.
Read and write are modeled on independent channels in this ledger; the
2 GB/s-class HP figure is a shared physical-port context, not additive.

## 5. Source hashes

Original read-only sources (SHA-256):

```
d9905c28...f0059  work/rtl/block_storage_dma_prefetch.sv
0a6f24fc...09c20  work/rtl/block_engine_l1bank_v020.sv
9d2bba3f...63b    work/rtl/block_address_v020.sv
93dbf836...d6b    work/rtl/operand_banks_v020.sv
77c66aee...d56    work/rtl/array16_direct_v020.sv
7b43de74...317    work/rtl/pe_direct_v020.sv
db471363...718    work/rtl/c_cache_banked4.sv
930775c6...531    work/rtl/axi_dma_v019.sv
```

Full hashes and candidate/test hashes are in `result.json` and
`logs/before_source_sha256.txt`.

## 6. Findings and limits

### Confirmed

- The original A/W path has a whole-block DMA barrier before scalar output.
- The original C path collects all 1024 C48 values before the write request.
- Two complete A/W stages plus a streamed C48 packer improve cycle count under
  identical BFM conditions (2.01x on the K=96 fast case).
- Read and write ports can be active concurrently; the unit test counted
  `ovsame=9` and `rdwr=708`; the engine counted `ov_rd=523`/`ov_wr=1293` in the
  fast case, and `ov_wr=23225` under write backpressure.
- Real Icarus and real Verilator both pass the same random BFM K=96 case.
- The candidate contract drives the frozen `axi_dma_v019` with two independent
  masters and an AXI128 BFM without protocol errors.

### Assumptions

- The fixture uses small A/W values; the golden and RTL were cross-checked on
  random signed A and random W7 with positions/clip. Extreme INT48 overflow is
  not intentionally exercised; the engine still detects it (code 8).
- `WR_OUT=8` is a chosen credit; ds_ddr may provide fewer/more, in which case
  `cwr_pending`/`cwr_idle` timing changes but data semantics do not.
- The physical DDR controller remains the PS hard controller on the current
  Zynq topology; this task models a transactional DMA terminal and does not
  claim a MIG/direct-DDR bypass.

### Not tested / not claimed

- No synthesis, place/route, STA, DRC, bitstream, board, VNC/NET deployment.
- No 300/600 MHz timing achievement claim.
- No full CASE0000/model accuracy run; the model/weights are not present in
  this task directory. This is a module/task-level result only.
- Control sequencing is FSM-registered, but the combinational ready/credit
  paths (`ld_ready`, `cval_ready`, `wr_valid`, `cwr_pending`, `stage_*_fault`)
  were not timing-analyzed.  For a 600 MHz local domain they need boundary
  registering and CDC/async FIFO; 300/600 MHz remains a structural target, not
  a measured result.
- FP32 FTZ/RNE/FMA and QDQ boundaries are unchanged but not exercised by this
  integer block-engine test.
- The baseline uses the original RTL read-only; its compile with Icarus has a
  known declaration-after-use issue, so the baseline runs use Verilator on the
  unmodified source. Candidate Icarus runs are included.
- `cwr_error` is sticky; a faulting task needs reset/re-init before reuse.
- An exploratory `B_DELAY=200` stress (`logs/run_engine_posted.log`) lost two
  B-response credits in the **testbench BFM**; it is not a DUT result and is
  not used as evidence.  The normal `B_DELAY=4` and backpressure `B_DELAY=40`
  cases pass.  Posted depth beyond the observed `max_b=1` is therefore not
  claimed; the storage logic does not wait for BRESP before issuing the next
  segment command, but a deeper-BRESP stress needs a fixed response-credit
  model.

## 7. Reproduction

```
cd /home/yang/Desktop/项目/tasks/ds_storage_overlap
bash scripts/run_all.sh
bash scripts/run_traffic_ledger.sh
```

Every build/run command and rc is in `logs/commands.log`; per-test logs are
`logs/*.log`; metrics are `logs/metrics.txt`. The script uses `-j 2` for
Verilator and no network.

## 8. Files for integration

- `candidate/rtl/block_storage_stream_v1.sv`
- `candidate/rtl/operand_banks_dual_v1.sv`
- `candidate/rtl/block_engine_prefetch_v1.sv`
- `INTERFACE.md` — port contract and upper-layer adaptation.
- `tests/` — BFM, golden, unit/overlap/baseline/AXI testbenches.
- `fixtures/` — deterministic input/expected vectors with manifests.
