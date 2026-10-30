# INTERFACE — ds_layout_wide (V0.24 Layout 128-bit fast path)

Status: FINAL for this task (2026-10-30). Candidate SHA256
`5477651c09c98781de3b6fe5d8a913c93fb685414fc4971685f15f87eae5c365`.
Logic simulation only. No synthesis/Vivado/board/VNC/push. No frequency or
whole-model second claims.

## 1. Baseline and candidate

| role | file | module |
|---|---|---|
| frozen baseline | `rtl/ddr_layout_engine_baseline_burst.sv` | `ddr_layout_engine` |
| candidate | `rtl/ddr_layout_engine_wide.sv` | `ddr_layout_engine` |
| divider (unchanged) | `rtl/u16_divmod.sv` | `u16_divmod` |
| wrapper (unchanged) | `tests/ddr_layout_axi_ref.sv` | `ddr_layout_axi` |

Baseline SHA256 = `4e45a39dcb07daeefc190d383ede885e57718f9a60c9d23eda61c4dae11eb893`
(V0.23 `ds_layout/rtl/ddr_layout_engine_v023_burst.sv`, also the layout engine
selected by `ds_closeout_safety/filelist_safety.f`). The candidate keeps the
same module name, port list, directions, widths and the 1024-bit descriptor.
The candidate is a drop-in for `ddr_layout_axi`.

## 2. Parameters

```systemverilog
module ddr_layout_engine #(
  parameter integer MAX_PREFETCH   = 16,  // mode 0/1/3 bounded sequential run
  parameter integer MODE2_PREFETCH = 1,   // im2col: 1 = no multi-line prefetch
  parameter integer FASTPATH       = 1    // 1 = enable 16-byte beat path
)( ... unchanged ports ... );
```

`FASTPATH=0` is the measured scalar fallback (same RTL, control path only).
`MODE2_PREFETCH=16` reproduces the old mode-2 prefetch policy for measurement.
These are compile-time parameters; no new CSR and no descriptor bit is used.

**Port list is unchanged.** Fast-path observability counters
(`fast_elements`, `fast_beats`, `fast_groups`) are internal registers in the
candidate, read only by the testbench through a hierarchical reference for
coverage reporting. They are not part of the integration contract and must not
be used for control. Scalar elements are `processed_elements - fast_elements`.

Compile lists: `filelist_wide.f` (RTL only) and `filelist_sim.f` (logic sim).
The frozen V0.23 baseline is kept as `rtl/ddr_layout_engine_baseline_burst.sv`
and is never compiled into the same binary as the candidate.

## 3. Fast path rules (candidate)

A fast step copies exactly one 16-byte destination beat per activation.

- mode 0 (linear copy), `bytes` in {2,4}: `destination_address[3:0]==0`,
  `total-linear_index >= 16/bytes`; source phase may be anything (the beat is
  assembled from one or two 16-byte cache lines and shifted).
- mode 1 (row-major -> A16 tile), `bytes==2`: destination beat aligned,
  `col[2:0]==0`, `col+8<=32`, `cc+8<=n`, `rr<m`.
- mode 3 (A16 tile -> row-major), `bytes` in {2,4}: destination beat aligned,
  `col % (16/bytes) == 0`, the group stays inside one 32-column source tile row
  (`col[4:0]+16/bytes<=32`) and inside `n`.
- mode 2 (im2col): no fast path. Only the bounded-prefetch gate changes.
- `bytes==6` (C48 packed): never fast path; the original scalar path keeps the
  cross-16B-line `source_part` / `take` handling (negative control retained).
- Any unaligned destination head, short tail, zero-fill (out-of-range) element,
  32-column row/tile transition, or ineligible group falls back to the
  unchanged scalar path. `processed_elements`/`total`/fault/drain semantics are
  identical.
- Every write beat is a 16-byte aligned, single-beat (or merged contiguous
  <=16-beat) burst; no beat crosses 4 KiB. Read prefetch stays bounded by the
  current source segment, the 4 KiB page and the declared source extent.

## 4. Behaviour changes the integrator must know

1. `rd_beats`/`wr_beats` remain 1..16 and addresses 16-byte aligned.
2. The scalar path and all counters keep their V0.23 semantics; `cache_misses`
   is still "fetch requests", not line misses. Fast and scalar writes may share
   one contiguous posted burst; bursts are still cut at 16 beats, at a 4 KiB
   page end, and at any real destination gap (for mode 3, `full_n>n`).
3. `MODE2_PREFETCH=1` changes mode-2 read request/beat counts but not output
   bytes. On 45 mode-2 cases it lowered read beats on 7, was neutral on 38,
   never raised them, and raised read requests by 470 (+9.7%) for +0.17%
   cycles. It does **not** eliminate all re-reads. `MODE2_PREFETCH=16`
   reproduces the V0.23 mode-2 traffic exactly.
4. Fault/abort/drain contract is unchanged: accepted beats drain, then
   `done=1` with `fault=1`/`error_code`; no new early completion.
5. Reset-in-flight is still not covered by unit tests (same caveat as V0.23).
6. No CDC, no new clock domain, no board DDR timing model.

## 5. Evidence contract

- Real RTL simulation with Icarus (`-g2012`), `-j1` compiles, same input image, same BFM
  (`tests/axi128_memory_bfm.sv`), same descriptor, same end-of-test drain check.
- Reference is the independent Python descriptor model (`scripts/layout_model.py`)
  plus the preserved official fixtures; candidate-vs-baseline comparison is a
  regression, never the only reference.
- Each simulation has an external `timeout` and an in-TB watchdog; failure is
  non-zero. A stale JSON or stub is never accepted as PASS.
- Re-run entry point is `scripts/run_all.sh` (sequential compile, one binary at
  a time).
