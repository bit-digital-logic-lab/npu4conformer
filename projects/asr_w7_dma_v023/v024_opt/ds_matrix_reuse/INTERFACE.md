# INTERFACE — ds_matrix_reuse v1 (W-reuse pair schedule)

Status: draft contract written before RTL freeze.  Logic simulation only.
No synthesis/STA/CDC/board/frequency claim.

## 1. Purpose and non-claims

The v023 `ds_matrix` candidate has a two-slot C cache
(`c_cache_banked4_pipe`, 2 x 32x32 INT48 = 2 x 256 groups = 2 x 6144 B)
but its schedule still processes one output tile at a time and reloads the
same W block for every `br`.  This candidate adds an **optional** 2x1
super-tile schedule:

- when enabled and at least two row blocks remain for the current `bc`, two
  C tiles (`br`, `br+1`) stay resident in slot 0/1 for every `bk`;
- one `W(bk,bc)` load feeds both row tiles;
- when disabled, the v023 single-tile schedule is used bit-for-bit in
  semantics (W reloaded per tile).

The two C slots are **two accumulators**, not two simultaneous read/write
ports and not two result payloads.  Only one tile is read/written by the
compute path in a cycle.  See `REVIEW.md`.

## 2. Modules

| module | role |
|---|---|
| `block_engine_reuse_v1` | pair/single matrix engine; optional W reuse; same numeric contract as v023. |
| `block_storage_stream_reuse_v1` | v023 storage + independent A/W read-stage select + per-kind stage release; writeback (`cseg/cval/cwr_*`) unchanged. |
| `operand_banks_dual_reuse` | two A and two W stage banks; **separate** `rd_a_stage` / `rd_w_stage`. |
| `c_cache_banked4_pipe` | unmodified v023 2-slot, true-dual-port II=1 C cache. |
| `array16_w7_c48_cfg`, `pe_w7_c48_cfg` | unmodified v023 PIPE_STAGES=3..6 array. |
| `block_address_v020` | unmodified address helper. |
| `axi_dma_v020_multi_v2` | unmodified v023 multi-outstanding DMA. |
| `matrix_reuse_cluster_v1` | engine + storage + read DMA + write DMA; AXI read/write masters separate. |

## 3. `block_engine_reuse_v1`

### 3.1 Parameters

| parameter | default | meaning |
|---|---:|---|
| `SLOTS` | 2 | C cache slots; must be 2 |
| `MAX_DIM` | 4096 | max M/N/K |
| `PIPE_STAGES` | 4 | 3..6, passed to the array |
| `ACCUM_MODE` | 0 | 0 native CARRY |
| `CPA_PIPE` | 1 | CSA final CPA register |

### 3.2 New config bit

`cfg_w_reuse`:

- `0`: single-tile schedule.  `br` outer, `bc` inner as in v023; one C slot
  (slot 0); W is loaded for every tile and every `bk`.
- `1`: if `(nb_r - br_base) >= 2`, run a pair `(br_base, br_base+1)` for all
  `bk` with one W load per `(bk,bc)`; if only one row block remains, run the
  single-tile schedule for that tail.  `nb_r==1` therefore never reuses W and
  is a pure single-tile case.

`cfg_w_reuse=1` is a schedule choice only; numeric semantics are identical.

### 3.3 Stage/read-port contract (new)

```
output wire rd_a_stage;       // A bank selected by compute
output wire rd_w_stage;       // W bank selected by compute (independent)
output wire [1:0] stage_release_a, stage_release_w;
```

- Pair mode: `rd_a_stage = unit` (A0 for br0, A1 for br1);
  `rd_w_stage = wst` (same W stage for both row tiles of one `bk`).
- Single mode: `rd_a_stage = rd_w_stage = curs`; `curs` flips per `bk`.
- `stage_release_a[s]` frees only A stage `s`; `stage_release_w[s]` frees only
  W stage `s`.  The legacy combined `stage_release[s]` is still accepted by
  the storage (OR of both) but the reuse engine drives `0` there.
- A/W stage readiness and captured headers are checked independently.
  A stage is usable only when its kind is ready and its header matches.

### 3.4 Pair schedule (cfg_w_reuse=1, two row blocks)

For each `bk` and `bc`, with `wst` alternating per `bk`:

1. wait A0 = A(br,bk) and W = W(bk,bc); check both headers/faults.
2. issue A1 = A(br+1,bk) into A stage 1; run br0 quadrants on A0 + W.
3. when br0 is done, release A stage 0; wait A1 ready (header checked).
4. issue A0(next) = A(br,bk+1) into A stage 0 and W(next) into W stage
   `wst^1`; run br1 quadrants on A1 + W.
5. when br1 is done, release A stage 1 and W stage `wst`; if another `bk`,
   flip `wst` and go to 1.

At no step do the DMA write stage and the array read stage of the same kind
point at the same bank.  The TB monitors this directly
(`hazard_a/hazard_w` counters must stay 0).

### 3.5 C tile lifetime and result emission

- Pair start: install tag for slot0=br, slot1=br+1; load old C once per tile
  into its slot if `cfg_c_valid=1`; `fresh_c[slot]` is per slot.
- Every `bk` performs read-modify-write of all 256 groups of each tile;
  the 9-bit cache group is `{slot, group[7:0]}` so slot0 and slot1 never
  alias.  Both tiles are resident for the whole K loop.
- The final K writes the completed tile through `cseg/cval`.  Because a
  single 192-bit read port and a single 49152-bit `result_payload` exist,
  the pair is **not** emitted as two simultaneous results:
  - br0 final K completes → wait `cwr_idle` and `result_ready` → result0;
  - then br1 final K is computed → wait `cwr_idle` and `result_ready` →
    result1.
  The C write stream of the two tiles is therefore never interleaved in v1.
- `result_cache_address = {cfg_target_high,16'd0} + slot*6144`.
- `result_block_row` is the absolute row block (`br` or `br+1`).

### 3.6 Telemetry (added)

```
output reg [31:0] w_load_blocks;    // accepted W load commands
output reg [31:0] a_load_blocks;    // accepted A load commands
output reg [31:0] c_load_blocks;    // accepted C load commands
output reg [31:0] pair_schedules;   // number of 2-row pairs started
output reg [31:0] w_reuse_saved;    // W blocks not loaded because of reuse
output wire pair_mode;              // 1 while a 2-row pair is executing
```

`w_reuse_saved` is incremented for the second row tile of each pair and each
`bk`, i.e. exactly the W loads avoided.  It is evidence only; the AXI byte
count from the BFM is the authority.

### 3.7 Unchanged numeric/error contract

A16 signed, W7 `{S,J[1:0],M[3:0]}`, positions nibble, clip saturation,
INT48 natural wrap, C48 old-C add with overflow fault 8, stage fault 9,
write fault 10.  Error drain uses `abort_storage` → `storage_drain_done`
before `done`; `done` also requires `cwr_idle`.

## 4. `block_storage_stream_reuse_v1`

Same ports as v023 `block_storage_stream_v2` except:

```
input  wire rd_a_stage, rd_w_stage;      // replaces rd_stage
input  wire [1:0] stage_release_a, stage_release_w;
input  wire [1:0] stage_release;          // legacy combined, tie 0 if unused
```

Writeback ports are **unchanged**:
`cseg_valid/ready/address[31:0]/epoch/layer/matrix/row/col/beats[15:0]`,
`cval_valid/ready/data[191:0]/last`, `cwr_pending[7:0]/idle/done/error/code`.
The write engine, packer, WRSTRB accounting, 4 KiB split and posted-B credit
logic are copied from v023 without functional change.  The only write-side
obligation of the pair schedule is that a tile's 64 `cseg` commands are posted
contiguously (no interleaving with the other slot) in v1; this is why result0
waits for `cwr_idle` before br1's final-K write stream starts.

See `patches/writeback_interface_v1.patch` and `WRITEBACK_INTERFACE.md`.

## 5. `matrix_reuse_cluster_v1`

Adds `cfg_w_reuse` and the new telemetry to the v023 cluster wrapper.  AXI
read (`AR/R`) and write (`AW/W/B`) masters remain separate.  `rd_m_axi_*` /
`wr_m_axi_*` shapes are unchanged.

## 6. Clocking / limits

Single clock, logic only.  Ready/credit paths are not STA-cleaned; no CDC is
implemented.  The AXI BFM is a protocol/stall model, not a DDR PHY.  No
synthesis, Vivado, board, VNC or push is used, and no frequency/whole-model
runtime is claimed.
