# INTERFACE — V0.23 integrated candidate

Status: runnable exact-path logic candidate; whole-V0.23 acceptance is blocked
(see `REPORT.md`). Single clock. No CDC/async-FIFO claim.

## 1. Unique build/filelist

Default entry: `filelist_integrated.f`. It contains exactly one definition of:

- `ddr_layout_engine` (`ddr_layout_engine_v023_burst.sv`; the stepping-only file
  is not compiled);
- `asr_fma_ip` (`fma_forbidden_stub.sv`, compile-only, aborts if op17 is used);
- shared `axi_dma_v019` and `task_queue`;
- vector/layout/matrix/control candidates and the integration adapters
  (`v023_*`).

Do not add `optional/approx/*` to the default build. `optional/filelist_approx_candidate.f`
is an explicitly rejected experiment. `filelist_baseline.f` is the sealed exact
baseline used by `tb/tb_v023_baseline_chain.sv`.

## 2. Top: `v023_integrated_top`

Parameters:

```systemverilog
PIPE_STAGES=4, MAX_PREFETCH=16, USE_APPROX_DIV_SQRT=0,
MATRIX_WATCHDOG=500000, VEC_WATCHDOG=200000, LAY_WATCHDOG=200000,
PARAM_END=32'h10040000
```

Clock/reset: one `clk` and active-low `rst_n` for every block. There is no
second clock and no xpm/async FIFO in this build.

CSR (AXI4-Lite, 24-bit address, `plan_submit_csr_v023`):

| offset | write | read |
|---|---|---|
| 0x04 | — | `{29'd0, fault, done_latched, busy}` |
| 0x08 | plan base | plan base |
| 0x0C | plan count (ignored by WCPG; use 1) | plan count |
| 0x10 | 1 = START | — |
| 0x14/0x18 | — | completed / last node |
| 0x1C | — | error_code |
| 0x20/0x24 | — | 64-bit cycles low/high snapshot |
| 0x28.. | — | last ticket / rejected starts |
| 0x30/0x34 | — | fetch cycles low/high |
| 0x38/0x3C | — | operator cycles low/high |
| 0x40/0x44 | — | vector cycles low/high |
| 0x48/0x4C | — | layout cycles low/high |
| 0x50..0x5C | — | vector/layout read/write bytes |
| 0x60/0x64 | — | read overlap low/high |
| 0x68/0x6C | — | write overlap low/high |
| 0x70/0x74 | — | vector/layout elements |
| 0x78/0x7C | — | numeric flags / vector+layout error |
| 0x80/0x84 | — | layout hits / misses |
| 0x90/0x94 | — | parameter_ready / generation |
| 0x98/0x9C | — | param_end / CSR magic `0x10102201` |
| 0xA0/0xA4 | — | matrix cycles low/high |
| 0xA8/0xAC | — | matrix PE cycles low/high |

Software reads the low word then the high word. Each 64-bit bank has an
independent high snapshot (PA-001 fix).

Data AXI: one AXI4 128-bit slave port (`m_ar*`, `m_r*`, `m_aw*`, `m_w*`,
`m_b*`). Internally `v023_axi_shared` arbitrates five read masters
(graph fetch, vector read, layout read, matrix read, matrix queue fetch) and
three write masters (vector, layout, matrix).

Telemetry outputs include `busy/done/fault/irq/error_code/completed/last_node/
cycles`, engine busy, matrix cycles/error, vector/layout bytes/cycles,
AXI burst/beat/peak/stall/tag counters.

## 3. Shared DMA contract (`v023_axi_shared`)

- `NR=5`, `NW=3`, `CREDIT=8`, `QDEPTH=32`, all in the single clock domain.
- Read ARs are tagged by owner in a global in-order FIFO. Multiple outstanding
  ARs from the matrix multi-DMA are routed back to that master in AXI order.
- Writes: W beats follow the oldest accepted AW; B responses follow AW order.
- Per-master outstanding credit is bounded by `CREDIT`. AR/AW are accepted only
  when the global FIFO has room.
- `tag_errors` counts RLAST/length mismatch or orphan responses. It was 0 in
  the integrated run.
- The observed `rd_peak/wr_peak` in this workload was 1. The xbar supports 8
  outstanding per master, but this run did not exercise a >1 peak; do not claim
  a measured multi-outstanding peak here. The independent DMA audit tested the
  multi-DMA itself at 8 AR / 2 B.

## 4. Matrix child (`v023_matrix_queue_engine`)

The WCPG MAT node supplies `queue_base/queue_count`. `task_queue` (BACKEND=21)
fetches each 64-byte V022 descriptor with `axi_dma_v019`, checks magic
`0x51415352`, backend, dependency and bounds, and the adapter maps:

```
word0 magic, word1 {backend,auth}, word2 cookie, word3 predecessor,
word4 A base, word5 B base, word6 C base, word7 m, word8 n, word9 k,
word10 epoch, word11 layer|a_id, word12 b_id|c_id,
word13 positions[15:0]|clip[16], word14 target_high|allowed,
word15 c_valid|c_completed
```

It drives `matrix_p2_cluster_v2` (`PIPE_STAGES=4` by default) one operation at
a time. `cfg_requested_op=1`. A/C must be in the arena; B may be in the arena
or parameter window. A per-child watchdog terminates the child contract with
`fault=1,error_code=0x0E` and `isolation_req=1` if the cluster never completes.
The cluster has no abort/drain port, so this is an isolation exit, not a false
`drained` claim. The queue adapter is a **direct-config sequencer**, not a
re-lowered sealed payload; it does not rewrite the sealed V022 plan image.

## 5. Vector/layout child guards

`v023_vector_guard` / `v023_layout_guard` preserve the wrapper ports and add a
cycle watchdog. On timeout they pulse `done`, hold `fault=1`, set
`error_code=0x0E` and latch `isolation_req`. They do not cancel accepted AXI
transactions. The delivered engines have no abort/drain port; `plan_v023`’s
child-abort/drain contract is therefore still not satisfiable by these engines.

Vector descriptor ABI is unchanged: magic `0x22564543`, op in `[39:32]`,
flags in `[46:40]`, A/B/C/D at words 2..5, count word 6, period word 7. The
tested ops are 14 (I48->F32), 2 (MUL), 0 (ADD), 15 (F32->I16, out16).
Layout descriptor ABI is unchanged: magic `0x224c4159`, mode, src, dst, total,
bytes. The tested mode is 0 copy; C48 handling is the candidate burst engine.

## 6. CSR / error codes observed

- `0x03`: matrix queue descriptor/backend/magic fault (bad queue test).
- `0x07`: WCPG ACL/payload rejection (bad vector op19 test); layout prep
  completed, zero vector data writes.
- `0x0E`: child watchdog isolation (code path present; not fault-injected here).
- Other codes follow `wc_graph_ctrl`/matrix worker contracts. `done_latched` and
  `irq` are separate from the one-cycle graph `done` pulse.

## 7. Integration-only edits to copied graph files

`rtl/wc_graph_ctrl.sv` (copy, not worker source) has two integration fixes:

1. exposes `seq_active` and gates MAT/VEC/LAY dispatch readiness while a SEQ
   program is active (SEQ-exclusive ownership);
2. fixes `vec_ok` so op14 (I48->F32) is not rejected when `a48=1`; the original
   ACL required `!a48` while also treating op14 as needing B. This was found by
   the integrated chain and is documented in `REPORT.md`.

`rtl/wc_graph_top.sv` (copy) instantiates `v023_vector_guard`,
`v023_layout_guard`, exposes telemetry and accepts `matrix_error`. It is not a
worker file.

## 8. Not in the accepted path

- FMA/op17 (forbidden stub; no arithmetic claim).
- Approx DIV/SQRT (optional snapshot only; independent audit rejects it).
- Epilogue stream engine (old/new; independent audit finds tag/backpressure/
  parameter/reconfiguration defects).
- Sealed 68/591 payload re-lowering, full 591 tensor DAG, host executor.
- Mixed SEQ + direct engines, child abort/drain, real DDR/PS topology, CDC,
  synthesis/STA/board.

## 9. Reproduce

```bash
cd /home/yang/Desktop/项目/v023_repair/integrated
bash scripts/run_all.sh
```

Individual:

```bash
python3 scripts/gen_integrated_fixture.py
iverilog -g2012 -s tb_v023_integrated -o build/tb_integrated.vvp \
  -f filelist_integrated.f tb/wc_graph_bfm.sv tb/tb_v023_integrated.sv
vvp build/tb_integrated.vvp +memfile=fixtures/mem_integrated.hex \
  +outfile=logs/integrated_out.hex +watchdog=50000
python3 scripts/check_integrated.py
```
