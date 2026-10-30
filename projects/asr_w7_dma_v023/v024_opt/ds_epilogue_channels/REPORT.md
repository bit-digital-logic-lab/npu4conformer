# REPORT — ds_epilogue_channels (v024 per-column epilogue)

Date: 2026-10-30  
Tree: `/home/yang/Desktop/项目/v024_opt/ds_epilogue_channels`  
Model: `opencode-go/deepseek-v4.1-flash`  
Scope: **module-level Icarus Verilog logic simulation only**. No synthesis,
Vivado/STA, board, VNC or push. No frequency or whole-model seconds claim.
Only this tree was written; `v023_repair`, `work`, the ZIP and other worker
trees are read-only. `ds_fusion_buffers` was not edited; collaboration is via
`INTERFACE.md`.

---

## 0. Result

**10/10 real-RTL scenarios pass with 0 value mismatches, 0 stability errors,
0 parameter-handshake errors, and every run drains the last A16 / packed /
FP32 / spill beat.**  The negative control (a deliberately broken copy with all
lanes forced to column 0) **fails** the comparison with non-zero status, so the
suite is not a self-fulfilling PASS.  Reference metadata is frozen in
`REFERENCE_LOCK.json` (34 files) and checked before each run.

`result.json` is generated from the fresh `RUN_RESULT.json` and
`NEGATIVE_CONTROL.json`, not from an old PASS file.  `run_all.sh` exits
non-zero on any failure.

This is **not** whole-model, synthesis, timing or board acceptance.  See §9.

---

## 1. Base and what changed

Base (read-only, frozen SHAs in `REFERENCE_LOCK.json`):

```
v023_repair/primary_stream_fix/candidate/epilogue_stream_engine_v023.sv
  336e859f7c061e6c71b25761a299e00656f0fc2d8d18fcf77bdb40c0e98b2e18
epilogue_lane.sv  d00b4d57776a605cbed790d19e9a7be7bb4b0f1751d4f6b617a9ca35489435f7
epilogue_i48_to_f32.sv 637a7b327d35760bc5d741128d04f77bcddde87cc40886dcf24aff09cebd29bf
...
```

The old Gemini `biasvalid` version was **not** used.  The v023 A16/packed fork,
scalar preload semantics, config-drain protection and abort behavior are
preserved.

New/changed:

- `rtl/epilogue_stream_engine_v024.sv`:
  2 banks × 32 columns × (32-bit scale, 32-bit bias), per-entry valid,
  bank `bc` tag, explicit column sideband, DMA write decode, inactive-bank
  preload, active-bank drain protection, four-channel output, telemetry.
- `rtl/epilogue_lane.sv`: per-lane scale/bias, independent post-ReLU FP32 fork.
- `rtl/epilogue_i48_to_f32.sv`: carries the scale/bias sideband through the
  two data pipeline stages, so the FMA sees the values of its own beat.
- `rtl/epilogue_stream_engine_v024.sv` A16/packed fork: replaced the v023-style
  A16 register with a two-consumer source beat held until both A16 and the
  packer have taken it (see §6, bug 3).

The other RTL files are copies of the frozen primary_stream_fix candidate and
are listed in `filelist_v024.f` (7 files / 7 unique modules).

---

## 2. Interface contract (summary; full text in `INTERFACE.md`)

### 2.1 Per-column table

- Two banks, each 32 scale + 32 bias entries, per-entry valid.
- Table state: `2*32*32*2 = 4096 b` data + `2*32*2 = 128 b` valid +
  `2*(16+1) = 34 b` bc/valid = **4258 b (532.25 B)**.
- Parameter DMA address:
  - `addr=0/1`: legacy broadcast scale/bias (primary_stream_fix compatible).
  - `addr[7]=1`: table write; `addr[6]=bank`, `addr[5]=kind` (0 scale,
    1 bias), `addr[4:0]=column`; `param_wr_bc` writes the bank's bc tag.
- `param_wr_ready`:
  - inactive bank: accepted while the active bank streams (ping-pong preload);
  - active bank: only when `engine_idle` (fully drained);
  - never in the same cycle as `cfg`; never while `cfg_valid` is held;
  - request must be held stable while `valid && !ready`.
- Per-entry valid means a partial table falls back to scalar per column.

### 2.2 bc / column mapping

The input sideband is the authoritative mapping:

```systemverilog
cval_bc[15:0]  // block column (bc)
cval_col[4:0]  // first of the 4 lanes, 0,4,...,28
```

`cval_tag` remains the opaque framer word tag and is echoed to A16, packed,
FP32 and C48 spill; it is **not** used for parameter lookup.  For the v023
framer word tag:

```
word = row*4 + col_half*2 + pair
col_base = col_half*16 + pair*8 + beat_in_pair*4
cval_bc  = tile_col
```

`beat_in_pair` is `beat_in_tile[0]` in the framer's own counter.  A
`cval_bc != cfg_bc`, a non-4-aligned `cval_col`, or an invalid entry is a table
miss and uses the scalar fallback; `stat_col_align_err` /
`stat_table_misses` count it.

### 2.3 Outputs

A16 (64-bit, 4 lanes), packed A16 (128-bit), C48 spill (192-bit) keep v023
semantics.  New `fp32x4_valid/ready/data[127:0]/tag/last` is the independent
post-ReLU 4×FP32 channel.  A16 and FP32 are produced in parallel when
`cfg_spill_fp32=1`; an integrator that only wants FP32 ties
`a16_ready=1`/`a16_packed_ready=1` to drain/discard A16.  Unused channels are
never silently dropped.

### 2.4 Read-port / write-port cost (honest)

- Read side per beat: 4 lanes × (scale,bias) = **8 × 32-bit read ports** on the
  active bank, plus a 2:1 bank mux.  Each is a 32:1 mux in register/LUT
  implementation; it is not claimed to infer BRAM/LUTRAM for free.  The lookup
  is combinational before the FMA input register and adds no per-beat cycle.
- Write side: one 32-bit DMA port.  A complete block table is 64 writes
  (32 scale + 32 bias); on the inactive bank this overlaps the current block.
- No extra DDR read is introduced by the table.

---

## 3. FP32 numerical contract (no residual / no reassociation)

For each lane:

```
x   = int48_to_fp32_rne_ftz(c48)
y   = fma_rne_ftz(x, scale, bias)     // one rounding of x*scale+bias
z   = relu(y)                         // NaN -> 0x7fc00000, -0/+0 -> +0
fp32_out = z
a16_out  = f32_to_i16_rne_sat(z)      // [-32768,32767], NaN -> 0
```

`scale/bias` priority: valid per-column table entry > legacy broadcast preload
(if valid) > `cfg_scale/cfg_bias`.  A downstream residual must do its own
IEEE-754 RNE add; this module does **not** fuse or reassociate it.  `fp32_out`
is the exact input to that add.

---

## 4. Verification method

- **Real RTL**: Icarus Verilog 14.0 compiles the 7 RTL files + testbench; each
  scenario is a real `vvp` run.  Compilation is serial (no parallel make).
- **Independent gold**: `scripts/gold_model.py` implements the contract from
  `INTERFACE.md` and uses `ref/refmodel.py` (copied read-only from
  primary_stream_fix), an exact Fraction/IEEE-754 model.  It does not parse or
  import RTL.
- **Same input / same TB BFM**: all scenarios use the same
  `tb/tb_epilogue_channels.sv` command-BFM and parameter-DMA BFM, with a
  per-run cycle watchdog and a Python wall-clock watchdog (180 s).
- **Drain boundary**: after `END` the TB forces all consumers ready and requires
  20 consecutive cycles with no A16/packed/FP32/spill valid; it prints
  `DRAINED` or exits 2 with `DRAIN_FAIL`.  This module has **no AXI/B channel**,
  so no B response is claimed here; the last output handshake is the boundary.
- **Stability**: `valid && !ready` payload/tag/last must hold; checked every
  cycle for all four output channels and for the parameter request.
- **Parameter protection**: the parameter BFM expects an active-bank write to
  be rejected while busy (8-cycle hold), and preloads the inactive bank while
  data streams; `PARAM_ERRORS` must be 0.
- **Abort**: a one-cycle abort must deassert all outputs, clear table validity,
  and the next config/burst must work.  The TB checks no output from the old
  epoch after the abort cycle and requires the full post-abort epoch.
- **Tags unique** per beat, so comparison is by tag, not just by order.
- **Negative control**: `scripts/negative_control.py` copies the RTL to
  `build/neg_rtl`, forces all lanes to `lane_scale[0]/lane_bias[0]`, compiles and
  runs `per_column_bp1`; the regression must report mismatches.  It does
  (60+ A16 mismatches, `pass=False`), and the control script exits 0 only when
  the broken RTL was rejected.

---

## 5. Regression matrix (10/10 PASS)

Every row: `rc=0`, independent gold by tag, 0 A16/packed/FP32/spill mismatch,
0 stability errors, 0 parameter errors, `DRAINED`.

| Case | What it covers | Beats | Observed A16 / packed / FP32 / spill | Table hits / misses / rejects | Drain cycle |
|---|---|---:|---:|---:|---:|
| `scalar_bp0` | legacy broadcast scale+bias, 2 blocks | 512 | 512 / 256 / 0 / 0 | 0 / 0 / 0 | 1568 |
| `per_column_bp1` | 32 distinct per-column scale/bias, bank0 block then bank1 block; bank1 preloaded while bank0 streams; active-bank write rejected | 512 | 512 / 256 / 0 / 0 | 2048 / 0 / 8 | 2109 |
| `cross_short_bp1` | 256-beat block, 9-beat block crossing a row, 1-beat tail, bank0 reuse for a third bc | 266 | 266 / 134 / 0 / 0 | 1064 / 0 / 0 | 1262 |
| `config_wait_bp1` | config request held during a live block (40 beats in), old block completes, next block uses new bank | 384 | 384 / 192 / 0 / 0 | 1536 / 0 / 0 | 1686 |
| `abort_recover` | abort after 16 middle-of-block beats, table cleared, post-abort table_en with no reload must miss and fall back | 24 | 14 / 7 / 0 / 0 total (6/3 pre-abort subset + 8/4 post-abort) | 64 / 32 / 0 | 153 |
| `abort_fp32_bp1` | abort with FP32 pending; post-abort scalar recovery | 24 | 14 / 7 / 8 / 0 total (6/3/8 pre-abort subset + 8/4/0 post-abort) | 64 / 0 / 0 | 153 |
| `fp32_backpressure` | all four channels random independent backpressure; per-column table; ReLU; spill48+FP32 | 256 | 256 / 128 / 256 / 256 | 1024 / 0 / 0 | 1111 |
| `fp32_long_bp5` | long periodic stalls on A16/packed/FP32/spill | 64 | 64 / 32 / 64 / 64 | 256 / 0 / 0 | 527 |
| `partial_table_bp0` | only 24 of 32 columns loaded; per-entry scalar fallback | 32 | 32 / 16 / 0 / 0 | 96 / 32 / 0 | 176 |
| `scalar_bias_only` | legacy bias-only preload (no uninitialized scale); unsupported addr 2 held and rejected | 32 | 32 / 16 / 0 / 0 | 0 / 0 / 0 | 131 |

`abort_recover` pre-abort outputs are a subset (6 of the 16 pre-abort A16,
3 of 8 packed) because the abort flushes the pipeline; the runner compares
every observed tag to the independent gold and requires the full 8-beat
post-abort epoch (8 A16 + 4 packed), so the logged total is 14 A16 + 7 packed.  No
pre-abort tag appears after the abort cycle.

The `per_column_bp1` active-bank write is rejected for 8 held cycles
(`stat_param_rejects=8`), and the inactive bank preload succeeds during block0
(`table_hits=2048` over 512 beats = 4 lanes).  `partial_table` shows the defined
fallback (`hits=96`, `misses=32`).  `abort_recover` shows table validity was
cleared (`hits=64`, `misses=32` after abort).  `abort_fp32_bp1` shows an abort
with FP32 beats pending: the FP32 stream stops at the abort, and the post-abort
scalar block produces A16/packed but no FP32 (`fp32=8` pre-abort only).

---

## 6. Bugs found by this independent regression

1. **Per-column sideband was misaligned with the I48→FP32 pipeline.**  The
   table read was combinational at the lane input while the converter has two
   register stages, so the FMA could see the next beat's column.  Symptom:
   blocked A16 values even for a correct table.  Fix: carry `in_scale/in_bias`
   through the same two stages as the data inside `epilogue_i48_to_f32`.
2. **Legacy address 2 was accepted.**  The old `legacy_addr_ok` matched any
   `addr[7:2]==0`; an unsupported write to addr 2 fell into the bias branch and
   overwrote bias.  Fix: accept only `8'h00`/`8'h01`; addr 2 is now rejected.
3. **A16/packed fork could re-present one converter beat.**  The v023-style
   A16 register could clear while the packer was stalled, then re-fork the same
   source beat.  Symptom: duplicate A16 tags under packed backpressure.  Fix:
   one source-beat register held until both A16 and the packer have taken it;
   the packer now uses the captured source, not the live converter output.
4. **FP32 fork bypassed the ReLU handshake.**  When FP32 was stalled, the A16
   converter could consume the ReLU output while the ReLU's own `out_ready` was
   low, duplicating a beat.  Fix: gate the A16 input with the FP32 sink and
   require both fork consumers to accept the same beat.  This was exposed by
   `fp32_long_bp5`.

These are real RTL bugs, not test-only workarounds; the negative control
confirms the suite detects a parameter-selection error.

---

## 7. Capacity / cost summary

| Item | Value |
|---|---:|
| Table data (2×32×2×32 b) | 4096 b |
| Per-entry valid (2×32×2) | 128 b |
| Bank bc + valid (2×17) | 34 b |
| Total table state | 4258 b / 532.25 B |
| Read ports per beat | 8 × 32-bit (4 scale + 4 bias) + 2:1 bank mux |
| Write port | 1 × 32-bit DMA |
| Table writes per full block | 64 (32 scale + 32 bias) |
| Per-beat lookup cycles added | 0 (combinational before FMA input register) |
| Extra DDR reads | 0 |

The 8 read ports and 32:1 muxes are non-zero LUT/register cost.  This report
does not claim a BRAM inference or a free table.

---

## 8. Reproduction

```bash
cd /home/yang/Desktop/项目/v024_opt/ds_epilogue_channels
bash run_all.sh
```

`run_all.sh`:

1. `python3 scripts/gen_vectors.py` (deterministic, no `random`);
2. `python3 scripts/freeze_reference.py --check` (31 frozen files);
3. `python3 scripts/run_suite.py` (serial Icarus compile + 10 scenarios);
4. `python3 scripts/negative_control.py` (broken RTL must fail);
5. `python3 scripts/finalize.py` (fresh `result.json`).

A single scenario can be rerun directly, e.g.:

```bash
python3 - <<'PY'
import json,sys
sys.path.insert(0,'scripts'); import run_suite as R
d=json.load(open('vectors/fp32_long_bp5.json'))
print(R.run_case(d))
PY
```

The runner deletes `RUN_RESULT.json` before it starts.  It never reads an old
PASS JSON to decide success.

---

## 9. What was tested / what was not

**Tested (module level):** per-column distinct scale/bias; 32 columns and 4-lane
boundary; cross-row/cross-block/short tail; ping-pong inactive-bank preload;
active-bank write rejection while busy; config request held during a live
block; abort and recovery; table clear on abort; partial-entry scalar fallback;
legacy broadcast scale/bias; bias-only legacy preload; unsupported legacy
address rejection; A16/packed/FP32/spill independent random and long
backpressure; valid/payload stability; drain of the last output.

**Not tested / not claimed:**

- No synthesis, Vivado/STA, timing, CDC, board, VNC or push.
- No frequency or whole-model seconds; no WER/CER.
- No AXI/BFM/B-response in this module; the completion boundary is the last
  A16/packed/FP32/spill handshake.  AXI write/B drain belongs to
  `ds_fusion_buffers` / the integrated top.
- No residual add, LayerNorm, or reassociation.
- No integration into `ds_fusion_buffers`; its published optional interface
  differs in parameter address spelling and in whether FP32 suppresses A16.
  `INTERFACE.md` §8 records the adapter/difference.  The main agent must choose
  the final integrated contract.
- No full graph / 591-DAG / whole Conformer execution.
- No claim that the table read muxes are cheap; only the port count is stated.

---

## 10. Frozen hashes (key files)

```
epilogue_stream_engine_v024.sv  4fff5c3f21b3924c421e4a91a82db40550b1d782b18348cad6bff125c9fcb305
epilogue_lane.sv                c633576dd01da04ec2686096f9e90acdfc7ca4987925c8bb7d053df204cf3885
epilogue_i48_to_f32.sv          4c862453f53b26e18b832c5fd919da7f8f444b70f9a4affb060deb91a37f5a13
filelist_v024.f                 12b8e6801cae332393c08c70ecdce68b8d5c4d29bed00b5a637ea8304ab6b7e5
REFERENCE_LOCK.json             4af33999c063f87eab35e94f4d9f6829d224fe53c9c0268dd3f1ed62c02d8582
RUN_RESULT.json                 e82a842cdc712ab311bd437f7cf064026ee6e94f58a2543d549e078513b1002a
NEGATIVE_CONTROL.json           66803d0522ff5222d09b1eb0038822fe1dfdb4f58d8e64acab160213aa5910d5
scripts/gold_model.py           5d1344f0748819de75af0116465937c9cf1e11324d42b0e8fe534f1b710b3992
ref/refmodel.py                 38eb7ed944f05d6ac45ff68b69fbaa4b0b5b895f0eef46fa33e138395ceb64e2
scripts/gen_vectors.py          07b24fc80b17b4c5da400eed50304021e67365a3c6effeb8d1faa5c5d28108ea
scripts/run_suite.py            cbac7eba3782c5e4b6ef1ff1ea868cb223f841a416d41094388996c3d13eb6ce
tb/tb_epilogue_channels.sv      2916dc31b96e0b633e3974278cf906ce3c2ec84a7439a9fc235032b9680c0586
```

`RUN_RESULT.json` and `result.json` are regenerated on every run (run times
change), so their current hashes are in `result.json`'s `files` map and are not
hard-coded here.  `REFERENCE_LOCK.json` contains the 34 frozen
gold/vector/v023-source SHAs; the RTL/script hashes above are stable.

---

## 11. Unique filelist

`filelist_v024.f` — 7 files / 7 modules:

```
rtl/epilogue_i48_to_f32.sv
rtl/epilogue_fma_stage.sv
rtl/epilogue_f32_to_i16.sv
rtl/epilogue_relu.sv
rtl/epilogue_lane.sv
rtl/fp32_fma_pipe.sv
rtl/epilogue_stream_engine_v024.sv
```

No duplicate module names.  `asr_fma_ip.sv` is not included because it is a
compile-only wrapper unused by this chain.

---

## 12. Acceptance status

All results here are module-level and must still be accepted by the main agent;
an agent exit code of 0 is not acceptance.  The negative control and frozen
reference are provided so the main agent can re-run and challenge the PASS.
