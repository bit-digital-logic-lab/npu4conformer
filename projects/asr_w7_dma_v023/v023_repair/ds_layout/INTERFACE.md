# INTERFACE — ds_layout integration contract

## 1. Files and module

| role | file | module |
|---|---|---|
| integration candidate | `rtl/ddr_layout_engine_v023_burst.sv` | `ddr_layout_engine` |
| stepping-only evidence | `rtl/ddr_layout_engine_v023.sv` | `ddr_layout_engine` |
| unchanged wrapper reference | `tests/ddr_layout_axi_ref.sv` (copy of `work/rtl/ddr_layout_axi.sv`) | `ddr_layout_axi` |

The candidate replaces `work/rtl/ddr_layout_engine.sv` directly.  Port names,
directions, widths and the 1024-bit descriptor are unchanged.  One parameter
was added **with a default**, so existing instantiations keep working:

```verilog
module ddr_layout_engine #(
  parameter integer MAX_PREFETCH = 16   // 16 = merge contiguous run, 1 = one line/miss
)( ... same ports as work/rtl/ddr_layout_engine.sv ... );
```

Recommended integration:

- drop-in: use `ddr_layout_engine_v023_burst.sv` wherever
  `work/rtl/ddr_layout_engine.sv` is instantiated (`ddr_layout_axi` already
  instantiates it by module name);
- if read bandwidth must not grow at all, instantiate with
  `#(.MAX_PREFETCH(1))`; measured read beats then equal the original while
  cycles remain ≈0.60× on the sampled set (see `logs/prefetch_policy.log`).

## 2. Port contract (unchanged names)

Control/status:

```
clk, rst_n, start, descriptor[1023:0], param_end[31:0]
ready, busy, done, fault, error_code[7:0]
processed_elements[31:0], rejected_starts[31:0],
cache_hits[31:0], cache_misses[31:0], cycles[63:0]
```

Read channel (one outstanding request):

```
rd_request_valid, rd_request_ready,
rd_address[31:0], rd_beats[15:0],
rd_valid, rd_ready, rd_data[127:0], rd_index[15:0], rd_done, rd_error
```

Write channel (one outstanding burst):

```
wr_request_valid, wr_request_ready,
wr_address[31:0], wr_beats[15:0],
wr_valid, wr_ready, wr_data[127:0], wr_strobe[15:0], wr_done, wr_error
```

Semantics are the same as `work/rtl/axi_dma_v019.sv`:

- `request_valid && request_ready` accepts one request (address + beats).
- Read data beats arrive with `rd_valid && rd_ready`; `rd_index` counts
  0,1,2,… within the request; `rd_done` is asserted after the last beat
  (the tested inline DMA asserts it one cycle after the last beat).
- Write beats are presented with `wr_valid && wr_ready`; `wr_done` after the
  write response.
- Errors must be reported **after draining every accepted beat**; the engine
  then enters `DRAIN` and returns `done=1` with `fault=1`/`error_code`.

## 3. Behaviour changes the integrator must know

### 3.1 Burst sizes and alignment

- `rd_beats` and `wr_beats` are **1..16** (not always 1).
- Every request address is 16-byte aligned.
- The engine itself never issues a request that crosses a 4 KiB page:
  `rd_address[11:0] + rd_beats*16 <= 4096`, same for writes.
- A shared DMA / arbiter must still **independently enforce** the same rule;
  do not rely on the engine's arithmetic if the DMA can coalesce requests.

### 3.2 Latency / ordering

- Mode-2 descriptors perform two one-time `u16_divmod` divisions at `INIT`
  (≈32 cycles) to decompose `k_offset`; there are no per-row/per-tile
  divisions.
- Per element, address generation is add/compare only.  Cache/pack state
  timing is otherwise unchanged.
- Writes are posted into a 16-entry × 128-bit buffer and emitted as ascending
  contiguous bursts.  The buffer flushes on 16 beats, on the last line of a
  4 KiB page, on `next_line != prev_line+16`, and at end-of-descriptor.
- Reads may fetch a contiguous line run ahead of use.  All prefetched lines are
  capped by the current source segment, the page and the declared source
  extent.  They are installed into the existing 64-line cache.
- 6-byte C48 values that cross a 16-byte line are handled explicitly:
  the source side re-enters `LOOKUP` for the second half (`source_part`), and
  `source_part/value_hi` are cleared at every new element; the destination
  side uses `take` to split the fragment across two lines with independent
  strobes.  The 16-beat write buffer stores those lines as separate beats; it
  never re-packs a straddling value.  This was the primary-acceptance C48
  item and is covered by a negative control (see REPORT §5.1).

### 3.3 Counter semantics (important for golden comparisons)

| counter | original | candidate |
|---|---|---|
| `processed_elements` | elements | same |
| `cache_hits` | per element | same |
| `cache_misses` | per **line** miss | per **fetch request** (1..16 lines) |
| `cycles` | same definition | same definition |
| wrapper `read_requests` | line reads | fetch bursts |
| wrapper `write_requests` | line writes | bursts (≈1/16) |
| wrapper `read/write_beats` | bytes/16 | **unchanged** on all measured cases |

Do not compare `cache_misses` or request counts against the old RTL as if they
were identical; compare beats/bytes, output bytes and fault/error/processed.

## 4. Shared-DMA contract

The engine is **single-outstanding per direction** and, because of its state
machine, never has a read request and a write request active at the same time.
That makes a shared DMA easy to attach, but the adapter must preserve these
rules.

### 4.1 Virtual-channel signals (per layout client)

If the shared DMA exposes one tagged port, give layout its own virtual channel:

```
// request (from layout)
req_valid, req_ready, req_write, req_addr[31:0], req_beats[15:0], req_tag[TAG_W-1:0]
// read return
rd_valid, rd_ready, rd_data[127:0], rd_index[15:0], rd_last, rd_tag[TAG_W-1:0],
rd_done, rd_error
// write return
wr_valid, wr_ready, wr_data[127:0], wr_strobe[15:0], wr_last, wr_tag[TAG_W-1:0],
wr_done, wr_error
```

Mapping from the engine:

```
req_valid      = rd_request_valid | wr_request_valid
req_write      = wr_request_valid
req_addr       = wr_request_valid ? wr_address : rd_address
req_beats      = wr_request_valid ? wr_beats   : rd_beats
req_tag        = LAYOUT_TAG
rd_ready       = engine rd_ready
wr_ready       = engine wr_ready
```

The engine requires:

1. beats of one accepted request are returned **in order and without
   interleaving** with another channel's beats unless the adapter demultiplexes
   by tag into per-tag FIFOs;
2. `done`/`error` is asserted once per accepted request, after its last beat
   (or after all accepted beats on error);
3. the adapter never drops an accepted beat;
4. `req_ready` may be deasserted at any time before acceptance; the engine
   holds the request stable.

If the shared DMA has multiple outstanding requests, either give layout one
dedicated outstanding slot, or tag and reorder correctly.  The engine itself
does not use more than one outstanding request.

### 4.2 Suggested arbitration

- Writes: grant promptly (they are posted and short); delaying a write burst
  stalls `PACK`.
- Reads: round-robin with other engines; the prefetch burst is up to 16 beats
  and already page-bounded.
- Do not merge two layout requests into one larger burst in the arbiter: it may
  violate 4 KiB / contiguity and it breaks the engine's error accounting.

### 4.3 Error / drain

- On a read error: drain accepted read beats, assert `rd_done=1, rd_error=1`.
- On a write error: complete/drain the write, assert `wr_done=1, wr_error=1`.
- The engine goes to `DRAIN`, waits for both `rd_request_ready` and
  `wr_request_ready`, then sets `done=1` with `fault=1` and the original error
  code (0x02 read, 0x03 write, 0x01 descriptor/extent).
- Do not cancel accepted AXI transactions to shortcut the drain.

## 5. Traffic-ledger / monitor hooks

Use an external monitor (do not change functional ready/valid):

- accept: `rd_request_valid && rd_request_ready`,
  `wr_request_valid && wr_request_ready`;
- read beats: `rd_valid && rd_ready`; write beats: `wr_valid && wr_ready`
  (count bytes by `wr_strobe`, not by beat count);
- first/last beat and completion via `rd_index`/`rd_done`/`wr_done`;
- classify states:
  - `INIT/INIT_DIV*/PREP0..2` → address/descriptor setup, **not** DDR wait;
  - `PF_CALC/RREQ/RDATA` → read memory;
  - `WREQ/WDATA/WWAIT` → write memory;
  - `PACK` → accumulation/compute, not wait;
  - `TAIL_PUSH`, `COMPLETE`, `DRAIN` → drain/completion.
- descriptor attributes: mode 0..4, bytes 2/4/6, tensor src/dst, slice
  (`k_offset`, `col_start`), tile coordinates.
- mark prefetch over-read explicitly: a prefetched line that is later evicted
  unused is still a real read; do not label it cache hit or idle.

## 6. Integration checks the main agent must repeat

1. Compile the whole cluster with the candidate and the real shared-DMA
   arbiter; re-run the 8 official + 30 golden fixtures through `ddr_layout_axi`.
2. Re-run the descriptor fuzz with the real arbiter's backpressure/error
   behaviour (the current BFM has deterministic stalls only).
3. STA / implementation for any frequency claim; this task has none.
4. If the layout engine is placed in a different clock domain, add and verify
   an async FIFO/CDC contract; none was added here.
5. Reset-in-flight is not covered by the module tests; add a reset test in the
   integrated system.
