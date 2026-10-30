# Interface / ABI summary (V0.24 export)

Sources of truth (copied from the stage, unmodified):

- `docs/design/UNIFIED_INTERFACE.md`
- `docs/design/BASE_SOURCE_SHA256.json`
- `docs/design/MERGE_TABLE.md`

## 1. Clock / reset

One clock `clk`, active-low `rst_n` in the RTL. `v024_unified_top` exposes
`clk`/`rst_n` plus AXI4-Lite CSR and AXI4 128-bit data ports. There is no CDC,
no asynchronous FIFO and no second clock in this build.

## 2. CSR (AXI4-Lite, 24-bit address)

Base offsets from `v023_integrated_top` (unchanged unless noted):

| offset | read | write |
|---|---|---|
| `0x04` | `{29'd0, fault, done_latched, busy}` | — |
| `0x08` | plan base | plan base |
| `0x0C` | plan count | plan count |
| `0x10` | — | `1` = START |
| `0x14` / `0x18` | completed / last node | — |
| `0x1C` | error code | — |
| `0x20` / `0x24` | total cycles low/high | — |
| `0x28`.. | ticket / rejected starts | — |
| `0x30` / `0x34` | fetch cycles | — |
| `0x38` / `0x3C` | operator cycles | — |
| `0x40` / `0x44` | vector total cycles | — |
| `0x48` / `0x4C` | layout total cycles | — |
| `0x50`..`0x5C` | vector/layout bytes | — |
| `0x60`..`0x6C` | read/write overlap | — |
| `0x70`..`0x74` | vector/layout elements | — |
| `0x78` / `0x7C` | numeric flags / error | — |
| `0x80` / `0x84` | layout hits / misses | — |
| `0x90`..`0x9C` | parameter ready / generation / magic | — |
| `0xA0` / `0xA4` | matrix total cycles | — |
| `0xA8` / `0xAC` | matrix PE cycles | — |
| `0xB0` | `{30'd0, requires_reset, isolation}` | — |
| `0xB4` | `rd_pending` | — |
| `0xB8` | `wr_pending` | — |
| `0xBC` | `b_pending` | — |
| `0xC0` | blocked requests while isolated | — |
| `0xC4` | `{31'd0, port_quiesced}` | — |
| `0xC8` | lockout rejects | — |

Read the low word first, then the high word; each 64-bit bank has an
independent high snapshot.

START while `requires_reset=1` returns `BRESP=2` (SLVERR), increments
`lockout_rejects`, and issues no AR/AW/W.

## 3. Per-channel table preload

`epilogue_stream_engine_v024` uses the existing 8-bit parameter write port:

- `param_wr_addr 0..31` = scale[col]
- `param_wr_addr 32..63` = bias[col]
- `param_wr_addr 64` = broadcast scale (legacy)
- `param_wr_addr 65` = broadcast bias (legacy)

The 32-entry tables are preloaded **once by the host before START**. There is
no per-tile host DMA and no PL-side autonomous table refill in this candidate.
The column index inside a 32-column tile is
`col = 16*quadrant_col_half + 4*pair_in_segment + lane` (C48 stream is
quadrant-major).

## 4. Vector / layout descriptors

Unchanged from V0.23:

- vector magic `0x22564543`; op in `[39:32]`; flags in `[46:40]`; A/B/C/D at
  words 2..5; total at word 6; period at word 7. Exercised ops: 0 ADD, 2 MUL,
  3 DIV, 4 SQRT, 14 I48->F32, 15 F32->I16, 17 FMA.
- layout magic `0x224c4159`; mode/src/dst/total/bytes. Exercised modes 0..3
  as described in the V0.23 layout interface; this export uses mode 0 copy.

## 5. Fusion descriptor

See `docs/design/ARCHITECTURE.md` §3. The only new ABI is header word 3 bit
16, MAT word 14 `MATF`, MAT word 15 parameter base, and consumer word 14
`A16C`. All other words keep V0.23 semantics.

## 6. Error codes

| code | meaning |
|---|---|
| `0x01` | illegal plan base / parameter window |
| `0x02` | parameter ready / generation invalid |
| `0x03` | fetch / queue DMA error |
| `0x04` | header/node validation or hash error (also MATF without FUSION_ALLOW) |
| `0x05` | generic child fault |
| `0x07` | WCPG payload / ACL rejection |
| `0x08` | root / output provenance error |
| `0x0A` | output not retained |
| `0x0E` | watchdog isolation terminal (not drained; `requires_reset=1`) |
| `0x81` | matrix cfg/operator/overlap illegal |
