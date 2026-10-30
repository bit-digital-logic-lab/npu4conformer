# INTERFACE — ds_repair_epilogue

Status: repaired module-level candidate.  The port list is **identical** to
`ds_epilogue_channels/rtl` so the unified integration can substitute this tree
without an adapter.  Scope is local Icarus logic simulation only; no synthesis,
Vivado/STA, board, VNC or push.

Source of the repaired candidate: `ds_epilogue_channels` (read-only), engine
SHA `4fff5c3f21b3924c…`, lane `c633576dd01da04e…`.  Only the engine changed in
this tree (`rtl/epilogue_stream_engine_v024.sv`); the other six RTL files are
byte-identical copies and are listed in `SHA256SUMS.txt`.

---

## 1. Module / file list (same as the candidate)

```
rtl/epilogue_i48_to_f32.sv          int48 -> FP32 (RNE/FTZ), carries scale/bias
rtl/epilogue_fma_stage.sv           single-rounding FP32 FMA(scale,bias)
rtl/epilogue_f32_to_i16.sv          FP32 -> INT16 (RNE, saturating)
rtl/epilogue_relu.sv                ReLU (NaN canonical, -0/+0 -> +0)
rtl/epilogue_lane.sv                one 4-lane epilogue lane + FP32 tap
rtl/fp32_fma_pipe.sv                frozen FMA pipe (unchanged)
rtl/epilogue_stream_engine_v024.sv  two-bank per-column engine (repaired)
```

Top module: `epilogue_stream_engine_v024 #(.TAG_WIDTH(16))`.  All ports and
widths are unchanged from `ds_epilogue_channels/INTERFACE.md` §2:

* config: `cfg_valid/ready`, `cfg_fma_mode[1:0]`, `cfg_relu_en`,
  `cfg_spill_c48`, `cfg_spill_fp32`, `cfg_table_en`, `cfg_bank`, `cfg_bc[15:0]`,
  `cfg_scale[31:0]`, `cfg_bias[31:0]`, `cfg_tag[TAG_WIDTH-1:0]`;
* parameter DMA: `param_wr_valid/ready`, `param_wr_addr[7:0]`,
  `param_wr_bc[15:0]`, `param_wr_data[31:0]`;
* input: `cval_valid/ready`, `cval_data[191:0]`, `cval_tag`,
  `cval_bc[15:0]`, `cval_col[4:0]`, `cval_last`;
* outputs: `a16_*`, `a16_packed_*`, `fp32x4_*`, `spill_*` (each with its own
  `valid/ready`, payload, tag and last);
* telemetry: `stat_c48_beats_in`, `stat_a16_beats_out`, `stat_spill_beats`,
  `stat_ddr_bytes_saved`, `stat_fp32_beats_out`, `stat_table_hits`,
  `stat_table_misses`, `stat_col_align_err`, `stat_param_rejects`.

Parameter address encoding, per-column/bank layout, bc/column mapping, numeric
contract (`C48 -> FP32 -> FMA -> ReLU -> {FP32,INT16}`), abort semantics and the
config-drain rule are unchanged.  See the candidate `INTERFACE.md` §2–§6 for the
full mapping; this document only lists the repaired fork/valid rules.

---

## 2. Repaired output fork (per-consumer pending / ack)

### 2.1 A16 (64-bit) — own pending register

`a16_valid` is driven by a dedicated `a16_pend_*` register loaded from the lane
beat.  It is cleared only by its **own** `a16_valid && a16_ready` handshake (or
`abort`/reset).  It is no longer the shared packer source beat, so packed-path
backpressure cannot withdraw or hold the A16 handshake.

### 2.2 Packed A16 (128-bit) — own source lifetime

The packer has its own source beat `src_*` and its own `p128_*` output register.
`a16_packed_valid` is cleared only by its own handshake (or `abort`/reset).

A lane beat is accepted only when **both** consumers have room:

```
a16_slot  = !a16_pend_valid || a16_ready;
p128_slot = !p128_valid     || a16_packed_ready;
```

The packer may absorb one beat into an empty half register even while the
128-bit word output is backpressured; only the beat that completes or flushes a
word waits for `p128_slot`.  The source is released as soon as the packer has
captured the beat, independently of the A16 acknowledgment.

### 2.3 FP32 (4 x 32-bit) — per-lane pending (unchanged)

The four lanes are lockstep.  Each lane has its own one-beat FP32 pending
register; `fp32x4_valid` is asserted only when all four lanes hold the same
beat, and is cleared only by the `fp32x4` handshake (or `abort`/reset).  A16 and
FP32 are the same post-ReLU beat; neither can consume it behind the other's
back.

### 2.4 Spill (192-bit) — tee of the accepted input

`spill_*` remains the direct C48 tee.  It fires on the same cycle as `cval_fire`
when `cfg_spill_c48=1`; its valid is stable while `spill_ready=0`.

### 2.5 Valid stability

For all four outputs, once `valid=1` the payload/tag/last are held and `valid`
stays high until that channel's `ready` handshake.  The only exceptions are
`abort` and reset (documented flush).  The formal gate checks this every cycle.

---

## 3. Config / parameter writes versus a pending input beat

A config request may be asserted early, but it now waits for a **presented but
not yet accepted** input beat as well as for the pipeline to drain:

```
cfg_ready = engine_idle && !cval_valid;
```

The same rule applies to legacy broadcast writes (`addr 0/1`) and to table
writes targeting the **active** bank.  Without it, a config/param handshake
could fire over a pending `cval_valid`, re-parameterize that beat and withdraw
`spill_valid` without a handshake.  Table writes to the **inactive** bank are
still accepted while the active bank streams (ping-pong preload), because they
cannot change the pending active-bank beat.

This is the only observable timing change versus the candidate: `cfg_ready` and
active/legacy `param_wr_ready` may stay low one beat longer while an input beat
is pending.  A16 output latency is one register deeper (registered pending), but
the handshake contract and per-beat throughput are unchanged.

---

## 4. Abort / reset / drain

* `rst_n=0`: tables, per-entry valid, bank tags, scalar preload valid,
  config, packer, A16 and FP32 pending all clear.  Same as the candidate.
* `abort=1` for one cycle: all output valids deassert, packer/A16/FP32 pending
  clear, `config_loaded=0`, table and scalar valid bits clear, inputs are not
  accepted.  The next epoch needs a new `cfg` and a table reload if
  `cfg_table_en=1`.
* `cfg_ready` waits for `in_flight_beats==0`, no packer half/word, no A16/FP32
  pending, no active burst, `!abort`, and `!cval_valid`.  A config held during a
  burst does not stop the remaining input from draining.

---

## 5. Integration notes

1. The file names, module names and ports are unchanged; the unified tree can
   replace the candidate engine and keep the same wiring.
2. Keep `cval_col` 4-aligned and `cval_bc == cfg_bc` for table hits; the
   scalar fallback and `stat_col_align_err`/`stat_table_misses` are unchanged.
3. Preload the inactive bank with `param_wr_addr={1'b1,bank,kind,col}` and
   `param_wr_bc=next_bc`, then issue `cfg` at the block boundary.  Do not assert
   `cfg` and expect it to fire over a pending input beat; it will wait.
4. Tie unused outputs ready (`fp32x4_ready=1` if not consumed,
   `a16_ready=1`/`a16_packed_ready=1` if only FP32 is consumed).  The engine
   never silently drops an unready output.
5. `ds_fusion_buffers`' optional `pch_*` spelling still needs the documented
   adapter (address kind bit, FP32/A16 coexistence).  This tree does not edit
   `ds_fusion_buffers`.

---

## 6. Verification entry point

```bash
cd /home/yang/Desktop/项目/v024_opt/ds_repair_epilogue
bash run_all.sh     # rc=0 only if gate + negative control + regression + evidence pass
```

See `REPORT.md` for the matrix, old/new SHA evidence and the unverified scope.
