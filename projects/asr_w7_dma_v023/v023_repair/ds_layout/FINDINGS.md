# FINDINGS — ds_layout (V0.23 Layout: incremental stepping + burst aggregation)

All findings below are from **logic simulation only** (Icarus 14 / Verilator lint).
No synthesis, no Vivado, no STA, no board, no push.  `work/`, the ZIP and other
task directories were read-only; every new file is under
`v023_repair/ds_layout/`.

## 0.1 Primary-acceptance update (2026-10-29)

The global acceptance is **NOT PASS** (`../primary_acceptance/REPORT.md`).
This directory provides module-level Layout evidence only and does not reuse
earlier PASS claims.  The one Layout item in that report — “ds_layout still
fixing C48 across cache lines” — is addressed and demonstrated with a
negative control in `REPORT.md` §5.1: removing the per-element
`source_part` clear reproduces byte-18 mismatches on `unpack_c48_compact`
and `copy_tail_6b`; the delivered RTL passes both.  FMA, approx-tier, vector
tail, graph and integration items are outside this directory and are not
claimed here.

## 1. What was actually changed

Two candidates exist, both with module name `ddr_layout_engine`:

| file | purpose |
|---|---|
| `rtl/ddr_layout_engine_v023.sv` | **Stage A**: incremental stepping / stride precompute, no runtime `u16_divmod`, still 1-beat I/O. Used to prove stepping bit-exactness in isolation. |
| `rtl/ddr_layout_engine_v023_burst.sv` | **Stage B** (integration candidate): Stage A + 16-beat posted write bursts + bounded sequential read prefetch (`parameter integer MAX_PREFETCH = 16`). |

Ports, parameters (apart from the new `MAX_PREFETCH` parameter) and descriptor
format are unchanged from `work/rtl/ddr_layout_engine.sv`.

### 1.1 Stepping, not “+1 cycle per element”

The original per-element loop is `NEXT -> CALC -> ADDRESS -> LOOKUP ->
CACHE_READ -> CACHE_CAPTURE -> VALUE -> PACK` plus `u16_divmod` waits at row /
tile boundaries.  The candidate keeps the same functional states for cache /
packing but:

- maintains `source_address` and `destination_address` by **precomputed byte
  deltas**; `index*bytes` is not computed per element;
- maintains `out_y/out_x`, `iy/ix`, `kc/ky/kx`, `rr/cc` by add/compare only;
- removes the runtime `u16_divmod` row/tile calls; the divider is used **once
  per descriptor** (two divisions) only to decompose `k_offset` in mode 2;
- moves the tile-start address recomputation to `PREP0..2` (once per tile).

Measured cycles per element (official fixtures) fell, it did not rise:

| fixture | elements | orig cyc/elem | Stage A | Stage B |
|---|---:|---:|---:|---:|
| copy_i16 | 1001 | 10.142 | 8.139 | 6.531 |
| pack_matrix_edges | 4096 | 6.676 | 5.448 | 4.227 |
| unpack_row_fp32 | 1155 | 12.280 | 10.208 | 7.305 |
| unpack_nchw_fp32 | 1155 | 13.258 | 11.292 | 9.266 |
| unpack_c48_compact | 1155 | 15.414 | 13.511 | 8.842 |
| conv_padding | 2048 | 6.910 | 5.126 | 4.026 |
| case0000_embed_conv0 | 78848 | 7.149 | 5.246 | 4.189 |
| depthwise_31 | 1024 | 8.755 | 6.463 | 5.410 |

## 2. Correctness evidence (what passed)

All comparisons are on **identical descriptors, DDR image and BFM**.

| suite | cases | result | reference |
|---|---:|---|---|
| official layout fixtures | 8 | 8/8 byte-exact | fixture `gold.hex` |
| official error/ACL/lifecycle modes | 12 | 12/12 same outcome | original RTL |
| descriptor fuzz (legal + 30 illegal) | 57 | 57/57 functional equal | original RTL (fault/error/processed/memhash) |
| independent Python golden fixtures | 32 | 32/32 byte-exact | `scripts/layout_model.py` |
| randomised legal shapes | 100 | 100/100 byte-exact | Python golden model |

The golden model is written from the descriptor contract and expands every mode
element by element; it is not derived from the RTL.  It covers copy, pack,
im2col padding/stride/dilation/slice, transpose, compact C48, 4 KiB crossings,
tails and non-contiguous destination rows.

Functional equality fields for the original-vs-candidate fuzz are
`fault`, `error_code`, `processed_elements` and a 256 KiB DDR hash.  Request /
hit counters are deliberately **not** equality fields because burst aggregation
changes them.

## 3. Traffic: writes collapse, reads depend on prefetch

Official 8-fixture aggregate:

| metric | original | Stage A | Stage B (default `MAX_PREFETCH=16`) |
|---|---:|---:|---:|
| cycles | 671,563 | 501,666 (0.747) | **397,315 (0.592)** |
| write requests | 11,890 | 11,890 | **746 (0.063)** |
| read requests | 2,638 | 2,638 | **1,778 (0.674)** |
| write beats | 11,890 | 11,890 | **11,890 (equal)** |
| read beats | 2,638 | 2,638 | **2,638 (equal)** |
| write bytes | 190,204 | 190,204 | **190,204 (equal)** |
| read bytes | 42,208 | 42,208 | **42,208 (equal)** |

So the write buffer merges ~16 consecutive lines per request without changing
the number of bytes or beats.  Read beats stay equal on the official set; read
**requests** fall only where the traversal is line-sequential.

### 3.1 Prefetch over-read is real and measured

On the 100 randomised legal shapes (independent golden model):

- 100/100 byte-exact;
- total cycles 3,149,865 → 1,913,759 (**0.608**);
- **9/100** cases read more beats than the original, **+234 beats total**,
  worst case **+168 beats (+38%)** (`r2_21`, reuse-heavy stride-3/dilation-2
  im2col);
- write beats are identical in every case.

The over-read is **not** a non-contiguous merge or an out-of-range read: the
prefetch is capped by the current source segment end, the 4 KiB page and the
declared source extent.  It is extra *contiguous* lines fetched ahead of a
reuse-heavy stream, which can be evicted before use.  It is reported, not
hidden.

`scripts/run_prefetch_policy.py` compiles the same source with
`MAX_PREFETCH=1` (multi-line prefetch off):

| case set | cycles orig | cycles pf16 | cycles pf1 |
|---|---:|---:|---:|
| 8 official + 3 over-read random | 800,079 | 476,048 (0.595) | 482,271 (0.603) |

With `MAX_PREFETCH=1`, **read beats equal the original in all 11 sampled cases**
(e.g. `r2_21` 440 → 440, not 608), while cycles remain ~0.60×.  Integration can
therefore choose: 16 for latency, 1 for no extra read traffic.

## 4. 4 KiB, non-contiguity, tails and errors

- The write buffer only merges lines when `next_line == previous_line + 16`;
  it flushes on `count == 16`, on `line[11:0] == 0xFF0` (last line of a 4 KiB
  page) and on end-of-descriptor.  The BFM independently fatals on any
  `AR`/`AW` that exceeds 16 beats, is not 16-byte aligned, or crosses 4 KiB
  (`tests/axi128_memory_bfm.sv` lines 52–53 and 64–65).  All 4 KiB-crossing
  fixtures pass, so the split is exercised, not assumed.
- Mode 3/4 destination gaps (`full_n > n`) and `col_start` prefixes are
  **not** written; the golden fixtures start from the existing destination
  bytes and would fail if the engine merged across a gap.
- Mode 2 with `dw*bytes > 16` (large dilation) deliberately falls back to
  single-line fetches; two dedicated fixtures (`conv_dil_big`,
  `conv_stride_big`) cover it.
- Tail strobes are preserved: partial last lines are written with the original
  mask; the 32-byte guard after the output is checked by the testbench.
- Error/lifecycle: DMA read error, DMA write error, bad magic/mode/total/bytes/
  alignment/dimensions/extent/overlap/param-end and replayed START all match
  the original outcome (12 official error modes + 30 illegal fuzz descriptors).
- The testbench checks “DONE before drain” for every normal run; the burst
  pipeline drains all accepted AXI traffic before `done`.

## 5. Critical path / frequency — what can and cannot be claimed

- Removed from the element loop: the `(kc*ih+iy)*iw+ix` cascade, the
  `index*bytes` multiply, and all runtime divider waits.  This directly
  addresses the #2 path described in the V0.22 STA report.
- Remaining multipliers are **outside** the element loop: one-time INIT stride
  precompute, per-tile `PREP0..2`, and the miss-time mode-3
  `remaining_elements*bytes` term.  They were not timed by STA.
- No synthesis, no STA, no implementation.  Therefore **no Fmax, no 250/300/
  600 MHz and no board-time claim is made**.  The 600 MHz local-domain idea
  would additionally need a CDC contract (async FIFO, skew/max-delay
  constraints) which is **not implemented or verified here**.
- The engine remains single-clock; no CDC was introduced.

## 6. Not done / open items

1. Shared-DMA **arbitration hardware** is not implemented; only the
   signal-level contract is in `INTERFACE.md`.  The engine is single-
   outstanding per direction and never issues read and write concurrently, so
   a virtual-channel arbiter is feasible, but that arbiter needs its own test.
2. Reset **in the middle of an in-flight 16-beat burst** is not separately
   tested.  DMA read/write errors and normal drain are tested.
3. `MAX_PREFETCH` is a compile-time parameter, not a runtime CSR.
4. No full-model (CASE0000 end-to-end) run was performed; the layout fixtures
   and random shapes are module-level evidence only.  No model-accuracy claim
   is made from this task.
5. No float divide/sqrt exists in Layout, so the user’s approximate-divide
   authorization does not change this task’s arithmetic.  W7p8/A16/C48
   positions, QDQ boundaries and clip were not touched.
