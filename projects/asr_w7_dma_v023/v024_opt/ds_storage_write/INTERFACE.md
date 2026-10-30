# INTERFACE — V0.24 storage write coalescer / pipelined validator

This is the integration contract for `rtl/` in this task. It is a logic-level
interface only: no synthesis, STA, CDC proof, board DDR timing or whole-model
claim. `v023_repair/` is the read-only reference.

## 1. Modules

| module | role |
|---|---|
| `block_storage_stream_v3` | V0.23 `block_storage_stream_v2` plus a registered address validator, C48 metadata FIFO, legal contiguous write coalescer and generic stride fallback. |
| `block_engine_prefetch_v3` | V0.23 `block_engine_prefetch_v2` plus same-cycle `cseg` + first `cval` (parameter `SAME_CYCLE_CSEG=1`; set 0 for the old one-cycle bubble A/B). |
| `matrix_p2_cluster_v3` | cluster wrapper with `v3` engine/storage and the extra write/collect telemetry. |
| `c_cache_banked4_pipe`, `operand_banks_dual_v2`, `block_address_v020`, `array16_w7_c48_cfg`, `pe_w7_c48_cfg`, `axi_dma_v020_multi_v2` | unmodified reference copies from `v023_repair/ds_matrix`; SHAs frozen in `REFERENCE_SHA256.json`. |

## 2. Unchanged engine/storage contract

The `ld_*`, `stage_*`, `c_hdr_*`, `c_ld_*`, `cseg/cval`, `cwr_*`, `rd_*`, `wr_*`
ports keep the V0.23 meaning.  A16/W7/C48 layouts, K order, lane order,
positions/clip, fault codes 1..10 and the drain rule are unchanged.

`cseg_beats` is still 6 for the native 96 B (16 C48) segment.  The engine still
sends one `cseg` per 16 C values and one `cval` per 4 C values.  The only
protocol relaxation is:

> On the final K, `cseg` for the first group of a 16-value segment and that
> group's `cval` may be valid in the same cycle.  A receiver that needs the
> old behaviour must hold `cseg_ready` low for one cycle; `v3` accepts both.

This removes the four per-quadrant command bubbles without changing the data
or address semantics.  Multi-K accumulation emits no `cseg/cval`.

## 3. Registered `ld` validator (`v3`)

The old `ld_expected` cone was

```
base + (row*ncols + col)*block_bytes      // 2 wide multiplies + add
ld_expected == {0,ld_address}             // 64-bit compare
end = expected + block_bytes              // range compare
```

in one cycle.  `v3` splits it into four register boundaries (V1..V4) after the V0 capture:

| stage | registered work |
|---|---|
| V0 | capture `ld_*` and the relevant `cfg_*` snapshot |
| V1 | `idx = block_row*ncols + block_col` (16x16) |
| V2 | `off = idx*block_bytes` (32x32 -> 64) |
| V3 | `expected = base + off`, `end = expected + block_bytes` |
| V4 | identity/alignment/arena/param/wrap/`expected==address` compares -> `bad`, push into the load queue and update stage ownership |

`ld_ready` depends only on queue/credit/stage-reservation counters, never on
the multiply/compare result.  In-flight validations are counted so the load
queue cannot overflow.  Throughput is one accepted `ld` per cycle after the
4-register latency.

`cseg` is accepted into a 4-entry metadata FIFO (`cseg_ready` depends only on
FIFO space and error state).  Its block/address validation is registered from
the FIFO head; a bad entry sets the sticky write error and drops the segment.

## 4. C48 write coalescer

### 4.1 Legal merge rule

The storage may merge a contiguous run of C48 segments into one posted write
request only when all of the following hold:

1. all segments belong to the same 6144 B C block (`cseg_row/cseg_col` match);
2. each segment address is `block_base + unit*96`, `unit in [0,63]`, so the
   native half-row layout is recognised;
3. the merged request is at most **16 beats (256 B)**;
4. the request does not cross a **4 KiB** boundary;
5. the last beat uses a real `WSTRB` byte mask (a short tail is allowed).

The native engine emits 64 x 96 B per block in quadrant order.  A 6144 B
staging buffer reorders the two 96 B half-rows of each row into two 3072 B
contiguous runs (rows 0..15 and rows 16..31).  Each run is emitted as
12 x 256 B (16-beat) requests, so a block needs 24 requests instead of 64.
The coalescer never creates a >16-beat or >4 KiB request; the 4 KiB test is
computed from the **current request address** (`base + off`), not the half-run
base, so a run that reaches 0x...F80 is shortened to 8 beats and the next
request starts at 0x...1000.  `tb_storage_coalesce +split` places the C block at
`C_BASE+0x80` and checks that this produces 25 requests instead of 24, with the
same 6144 bytes.

### 4.2 Generic stride fallback

Any `cseg` whose address is not `block_base + unit*96`, whose `unit >= 64`,
or whose block identity changes is sent through the **generic** path.  The
generic path buffers up to 128 B per segment, waits for `cval_last`, and posts
one request with `beats = ceil(bytes/16)` and a real tail strobe.  It keeps the
old per-segment address/stride semantics and is exercised by
`tb_storage_coalesce` with a non-native stride.

### 4.3 Ordering / backpressure

`cval` is written into the staging buffer at
`unit*96 + group_in_segment*24`; it does not wait for the packer.  A segment is
complete on `cval_last`.  A half-run is flushed when all 32 units of that half
are complete, so the first 3072 B can drain while quadrants 2/3 are still
computing.  `cwr_idle` is asserted only when: no metadata/segment pending, no
staged half pending, no generic segment pending, no write command queued, no
current burst, and `b_out == 0`.  `cwr_pending` is the sum of those credits.

On `abort` or any write error, unposted commands are dropped, the accepted
burst is padded with zero-strobe beats so the DMA beat count is still met, and
`cwr_error` becomes sticky.  The engine still drains to `done/fault`.

## 5. Telemetry (`matrix_p2_cluster_v3`)

| signal | meaning |
|---|---|
| `cseg_cmds` | accepted logical `cseg` commands (=64 per block) |
| `wr_cmds` | posted write requests after coalescing |
| `wr_beats` | W beats actually handed to the DMA |
| `wr_bytes` | sum of `popcount(WSTRB)` (PA-004 rule) |
| `coalesced_segs` | segments absorbed by the staging path |
| `generic_segs` | segments sent through the generic stride path |
| `flush_reqs` | staged-run flush requests |
| `max_b_credit` | max observed storage `b_out` |
| `cval_stall_cycles` | cycles `cval_valid && !cval_ready` |
| `cseg_stall_cycles` | cycles `cseg_valid && !cseg_ready` |
| `cwr_pending` | outstanding write credit (see 4.3) |

`block_engine_prefetch_v3` keeps `c_collect_groups/c_collect_cycles/
c_raw_bypass_cycles`; `c_collect_cycles` now includes only real collect time
(no artificial one-cycle `cseg` stall when the storage can accept both).

## 6. Clocking / limits

Single clock.  The staging buffer is modelled as a 6144 B dual-access array
(write port 24 B/cycle, read port 16 B/beat); no synthesis/port-count claim.
The address validator split is a structural RTL change, not an STA result.
No frequency, CDC, board or whole-model claim is made.
