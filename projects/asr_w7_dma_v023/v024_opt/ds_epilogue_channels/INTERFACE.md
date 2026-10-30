# INTERFACE — ds_epilogue_channels (v024 candidate)

Status: module-level logic candidate. Read-only source is
`v023_repair/primary_stream_fix` (`epilogue_stream_engine_v023`, the
`primary_stream_fix` fork, not the old Gemini biasvalid-bug version).
This tree only writes under `v024_opt/ds_epilogue_channels`.

This document is published before RTL completion so `ds_fusion_buffers` can
wire the optional interface without editing this tree. The RTL file names and
final port list are frozen in `REPORT.md`/`FILELIST.json`; any later mismatch
must be treated as a bug.

---

## 1. What is new versus `primary_stream_fix`

`primary_stream_fix` supports two broadcast parameter words only:
`param_wr_addr=0` -> scale, `=1` -> bias; no per-channel lookup; no
`cfg_spill_fp32`. This candidate adds:

1. Two ping-pong banks, each with 32 scale + 32 bias entries (one 32-column
   block per bank).
2. A per-column table read for the four lanes (4 x scale + 4 x bias reads per
   beat), with explicit block-column (`bc`) and column-base sideband.
3. A DMA write port that can preload the inactive bank while the active bank
   is streaming. Writes to the active bank are accepted only when the engine
   is fully drained.
4. An optional independent `4 x FP32` output channel with its own
   `valid/ready`. A16, packed A16, C48 spill and FP32 are four independent
   consumers.
5. Scalar compatibility: with `cfg_table_en=0`, or with an invalid/unwritten
   table entry, the engine uses the old broadcast `param_wr_addr=0/1` preload
   value if valid, otherwise `cfg_scale/cfg_bias`.

The arithmetic chain is unchanged: C48 -> FP32 (RNE/FTZ) -> one-rounding
FP32 FMA(scale,bias) -> optional ReLU -> FP32 or RNE/saturating INT16. No
residual add and no reassociation is implemented here; see section 6.

---

## 2. New/changed ports

All handshakes are `valid && ready`, synchronous to `clk`, active-low reset
`rst_n`, synchronous `abort` (one-cycle flush, same meaning as v023).

### 2.1 Configuration (extended)

```systemverilog
input  wire                   cfg_valid;
output wire                   cfg_ready;
input  wire [1:0]             cfg_fma_mode;   // 0 conv-only, 1 scale+bias, 2 scale-only
input  wire                   cfg_relu_en;
input  wire                   cfg_spill_c48;
input  wire                   cfg_spill_fp32;  // 1 = enable 4xFP32 output
input  wire                   cfg_table_en;    // 1 = use per-column table
input  wire                   cfg_bank;        // active ping-pong bank (0/1)
input  wire [15:0]            cfg_bc;          // block-column id of active bank
input  wire [31:0]            cfg_scale;
input  wire [31:0]            cfg_bias;
input  wire [TAG_WIDTH-1:0]   cfg_tag;
```

`cfg_ready` is asserted only when the engine is fully drained
(`in_flight_beats==0`, no packer half/word, no FP32 pending, no active input
burst, not in abort). A config request may be asserted early; it waits.
A beat is never accepted on the same cycle as a config handshake, and the
four lanes capture their scale/bias at input, so a later config cannot change
an in-flight beat.

### 2.2 Parameter DMA write (one 32-bit write port)

```systemverilog
input  wire                   param_wr_valid;
output wire                   param_wr_ready;
input  wire [7:0]             param_wr_addr;
input  wire [15:0]            param_wr_bc;
input  wire [31:0]            param_wr_data;
```

Address encoding (one write port, backward compatible):

| `param_wr_addr` | Meaning |
|---|---|
| `8'h00` | legacy broadcast scale (same as primary_stream_fix addr 0) |
| `8'h01` | legacy broadcast bias (same as primary_stream_fix addr 1) |
| `8'h80 + {bank,kind,col[4:0]}` | table entry; `addr[7]=1`, `addr[6]=bank`, `addr[5]=kind` (0=scale, 1=bias), `addr[4:0]=column 0..31` |

So `addr` bits are `[7]=table, [6]=bank, [5]=kind, [4:0]=col`. Addresses with
`addr[7]=0` and `addr[7:2]!=0` are not accepted (`ready=0`). A table write
also writes `param_wr_bc` into `bank_bc[bank]` and sets that bank's bc-valid
bit; one DMA sequence must write all 32 scale and all 32 bias words for that
bank before the bank is selected.

`param_wr_ready` rules:

* `!abort`, `!cfg_valid`.
* Legacy broadcast writes: only when `engine_idle` (same conservative rule as
  v023).
* Table writes to the **inactive** bank: accepted while the active bank is
  streaming. This is the ping-pong preload path. These writes do not stall
  `cval`.
* Table writes to the **active** bank: only when `engine_idle`.
* A table write is never accepted in the same cycle as a config handshake.
* `param_wr_bc/addr/data` must remain stable while `valid && !ready`.

Because the four lanes capture scale/bias into their FMA input registers on
`cval_fire`, rewriting the inactive bank (or draining then rewriting the old
bank) cannot alter any in-flight beat. The active-bank/engine_idle rule is the
additional structural protection and is checked by the testbench.

### 2.3 Upstream C48 stream (extended sideband)

```systemverilog
input  wire                   cval_valid;
output wire                   cval_ready;
input  wire [191:0]           cval_data;       // lanes [47:0],[95:48],[143:96],[191:144]
input  wire [TAG_WIDTH-1:0]   cval_tag;        // opaque A16/packed word tag, passed through
input  wire [15:0]            cval_bc;         // block-column id of this beat
input  wire [4:0]             cval_col;        // first column of the 4 lanes, 0,4,...,28
input  wire                   cval_last;       // block/tile last beat
```

`cval_tag` is **not** used for parameter lookup; it is echoed to A16, packed,
FP32 and C48 spill. `cval_col` must be 4-aligned. If `cval_col[1:0]!=0` or
`cval_bc != cfg_bc` or the selected entry is not valid, the table lookup for
that lane misses and the scalar fallback is used; `stat_table_misses` and
`stat_col_align_err` count it.

#### bc / column mapping versus the existing framer

`v023_repair/ds_closeout_fusion/rtl/fusion_c48_framer.sv` emits, for one 32x32
tile:

```
word = row*4 + col_half*2 + pair          (0..127)
out_tag[6:0] = word                        (tag bits above 6 are zero)
```

Each beat carries 4 consecutive columns. For the two beats that share one
`word` tag, the first/second beat in the pair selects the upper/lower 4-column
half:

```
col_base = col_half*16 + pair*8 + beat_in_pair*4
cval_bc  = tile_col                       // framer's cseg_col / tile_col
cval_col = col_base                       // 0,4,...,28
```

`beat_in_pair = beat_in_tile[0]` in the framer's own counter (0,1,0,1,...).
The engine does not require the integrator to keep that counter: it consumes
the explicit `cval_col`/`cval_bc` sideband, which is the authoritative
mapping. If `ds_fusion_buffers` prefers to derive the sideband from
`beat_in_tile`, the formula above is the contract.

### 2.4 Outputs

```systemverilog
// A16 register beat (unchanged semantics)
output wire                   a16_valid;
input  wire                   a16_ready;
output wire [63:0]            a16_data;
output wire [TAG_WIDTH-1:0]   a16_tag;
output wire                   a16_last;

// packed 8 x INT16 (unchanged semantics; independent consumer)
output wire [127:0]           a16_packed;
output wire                   a16_packed_valid;
input  wire                   a16_packed_ready;
output wire                   a16_packed_last;
output wire [TAG_WIDTH-1:0]   a16_packed_tag; // first half tag

// optional 4 x FP32, independent valid/ready
output wire                   fp32x4_valid;
input  wire                   fp32x4_ready;
output wire [127:0]           fp32x4_data;    // lane3..lane0, 32 bits each
output wire [TAG_WIDTH-1:0]   fp32x4_tag;
output wire                   fp32x4_last;

// C48 spill (unchanged)
output wire                   spill_valid;
input  wire                   spill_ready;
output wire [191:0]           spill_data;
output wire [TAG_WIDTH-1:0]   spill_tag;
output wire                   spill_last;
```

`cfg_spill_fp32=1` enables the FP32 channel. A16 is still produced; the FP32
beat is the same post-ReLU FP32 word that feeds the A16 converter. If only
A16 is used, tie `fp32x4_ready=1` (the channel is idle when disabled, so this
also drains any legacy pending beat after a config change). If only FP32 is
used, tie `a16_ready=1` and `a16_packed_ready=1` so the A16/packed fork can
drain; the engine does not silently drop an unready output.

The four channels are independent: stalling FP32 does not repeat an A16
handshake, and stalling A16/packed does not lose an FP32 beat. Valid/payload
are stable while `valid && !ready`.

### 2.5 Telemetry

```systemverilog
output reg [31:0] stat_c48_beats_in;
output reg [31:0] stat_a16_beats_out;
output reg [31:0] stat_spill_beats;
output reg [31:0] stat_ddr_bytes_saved;
output reg [31:0] stat_fp32_beats_out;
output reg [31:0] stat_table_hits;       // lane lookups that used the table
output reg [31:0] stat_table_misses;     // lane lookups that fell back to scalar
output reg [31:0] stat_col_align_err;    // beats with cval_col[1:0]!=0
output reg [31:0] stat_param_rejects;    // table writes waiting on active bank/idle
```

`stat_ddr_bytes_saved` retains the v023 estimate (48 B per non-spilled C48
beat) and is an estimate, not a bus measurement.

---

## 3. Table capacity and 4-lane read-port cost (honest accounting)

| Item | Size |
|---|---:|
| scale table, 2 banks x 32 cols x 32 b | 2048 b |
| bias table, 2 banks x 32 cols x 32 b | 2048 b |
| per-entry valid, 2 banks x 32 x 2 | 128 b |
| bank `bc` id + valid, 2 x (16+1) | 34 b |
| total state | 4258 b (532.25 B) |

Read side per beat: four lanes each need one 32-bit scale and one 32-bit bias,
i.e. **8 x 32-bit read ports** on the active bank (4 scale + 4 bias), plus a
2:1 bank mux on each. The implementation uses register arrays with
combinational reads; it is not claimed to infer BRAM/LUTRAM or to be free.
With a 32-entry table, each read is a 32:1 mux; the four-lane lookup is on the
input side of the FMA register and adds no extra per-beat cycle. The write
side is one 32-bit DMA port. A complete block table is 64 writes (32 scale +
32 bias) = 64 handshakes; on the inactive bank these overlap the current
block. No extra DDR read is introduced by this table.

---

## 4. Reset, abort, and reconfiguration

* `rst_n=0`: tables, bank tags, scalar preload valid bits, config and all
  pipelines clear.
* `abort=1` for one cycle: all output valid bits deassert, pipeline/packer/
  FP32 pending clear, `config_loaded=0`, table valid bits and bank tags clear,
  scalar preload valid bits clear. Inputs are not accepted. The next burst
  must issue a new `cfg` and reload the table if `cfg_table_en=1`.
* `cfg_ready` waits for full drain. A config request held during a burst does
  not stop the remaining input from draining (same anti-deadlock property as
  v023).
* A table write held while the active bank is busy keeps `valid` high and
  waits; it does not corrupt the active table. It must not be dropped by the
  writer before `ready`.

---

## 5. What is deliberately not implemented

* No residual add, no LayerNorm, no reassociation. The FP32 output is exactly
  `relu(FMA(C48->FP32, scale, bias))` with the existing single-rounding FMA.
* No automatic bank selection from `cval_bc`; the integrator sets `cfg_bank`
  and `cfg_bc`. `cval_bc` is a checked sideband, not an arbiter.
* No per-bank partial-write commit protocol beyond per-entry valid bits: a
  bank becomes usable entry-by-entry. If a bank is selected before all its
  entries are written, missing entries use the scalar fallback.
* No synthesis/STA/board claim. No frequency or whole-model time claim.

---

## 6. FP32 numerical contract (for residual/LayerNorm consumers)

For each lane:

```
x   = int48_to_fp32_rne_ftz(c48)          // exact integer conversion
y   = fma_rne_ftz(x, scale, bias)         // one rounding of x*scale+bias
z   = relu(y)                             // NaN -> 0x7fc00000, -0/+0 -> +0
fp32_out = z
a16_out  = f32_to_i16_rne_sat(z)          // [-32768,32767], NaN -> 0
```

`scale/bias` are the per-column table entry when hit, else the broadcast
preload when valid, else `cfg_scale/cfg_bias`. A downstream residual must
perform its own IEEE-754 RNE add; this module does **not** fuse or reassociate
it. `fp32_out` is the exact input to that add.

---

## 7. Integration checklist for `ds_fusion_buffers`

1. Keep `cval_tag` as the existing framer word tag (0..127) for the A16
   block buffer; add `cval_col`/`cval_bc` sideband from `beat_in_tile` and
   `tile_col` using section 2.3.
2. Preload bank `b` for the next block with `param_wr_addr=0x80|(b<<6)|kind<<5|col`
   and `param_wr_bc=next_bc`. This can run while the current block streams.
3. At block boundary, issue `cfg` with `cfg_table_en=1`, `cfg_bank=b`,
   `cfg_bc=next_bc`, `cfg_spill_fp32` as needed. `cfg_ready` waits for drain.
4. Tie `fp32x4_ready=1` if the FP32 channel is not consumed; tie
   `a16_ready=1`/`a16_packed_ready=1` if only FP32 is consumed. Never leave an
   enabled output unready without a consumer.
5. Do not write the active bank while `in_flight_beats!=0`; the engine will
   hold `param_wr_ready=0`, but the writer must also hold the request.
6. This tree does not edit `ds_fusion_buffers`; the integration must be done
   in that tree after independent acceptance.

---

## 8. Relationship to `ds_fusion_buffers` published optional interface

`ds_fusion_buffers/INTERFACE.md` §4 (published, not implemented there) uses a
different optional spelling:

```systemverilog
pch_wr_valid/ready, pch_wr_addr[5:0]  // [5]=bank, [4:0]=column
pch_wr_data[31:0], pch_scale_sel[5:0], pch_bias_sel[5:0]
cfg_spill_fp32, fp32_valid/ready/data/tag/last
```

Two differences must be reconciled by the main agent, not by editing either
worker tree:

1. **Parameter write port.**  The `ds_fusion_buffers` spelling has one 32-bit
   data word and no explicit scale/bias kind bit, so it cannot distinguish
   scale from bias in one address.  This candidate uses
   `param_wr_addr[7]=table`, `[6]=bank`, `[5]=kind` (0 scale / 1 bias),
   `[4:0]=column`, plus `param_wr_bc` for the bank's block-column tag.  An
   adapter from a future `pch_*` port is:
   `param_wr_addr = 8'h80 | (pch_addr[5]<<6) | (kind<<5) | pch_addr[4:0]`,
   `param_wr_bc = current_bc`, with a `kind` sideband added on the writer side.
   The `pch_wr_ready` rule (drained / no descriptor) is stricter than this
   candidate's inactive-bank preload; either rule is safe, but they are not the
   same throughput contract.
2. **FP32 output.**  This candidate produces A16 and FP32 in parallel when
   `cfg_spill_fp32=1` (A16 is not suppressed).  The `ds_fusion_buffers` text
   says FP32 bypasses A16.  They are compatible if the integrator ties
   `a16_ready=1` and `a16_packed_ready=1` to drain/discard A16 when only FP32 is
   wanted.  This candidate does not silently drop an unready output.

This tree does not edit `ds_fusion_buffers`; its RTL, tests and reports are
independent.  The tested interface is the one in sections 2–7 above.
