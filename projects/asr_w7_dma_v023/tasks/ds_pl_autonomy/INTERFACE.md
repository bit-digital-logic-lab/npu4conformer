# INTERFACE — W023 whole-plan controller / candidate top

This document is the integration contract for the new modules in this task.
It describes only the candidate additions; the sealed V022 RTL, host image,
weights and numerical semantics are unchanged.

## 1. New files

| file | role |
|---|---|
| `rtl/wc_superplan_ctrl.sv` | engine-agnostic whole-plan scheduler: header/node fetch, 128-bit dependency scoreboard, four engine handshakes, ACL/generation guards, drain, single DONE/IRQ |
| `rtl/wc_plan_csr.sv` | AXI-Lite START/status wrapper for the controller |
| `rtl/wc_plan_top_v023.sv` | candidate integration: controller + sealed V022 linear-plan executor + real DDR vector/layout engines + external matrix handshake |
| `tb/wc_axi_bfm.sv` | independent 128-bit AXI BFM (sparse address windows, randomized stalls, parameter-write fatal) |
| `tb/tb_wc_ctrl.sv`, `tb/tb_wc_top.sv`, `tb/tb_wc_before.sv`, `tb/tb_wc_ctrl68_before.sv` | control, real-chain, and before/after tests |
| `scripts/wc_compile.py` | static superplan compiler |
| `scripts/wc_verify_plan.py` | independent binary/topology/hazard verifier |
| `scripts/wc_analysis.py`, `scripts/wc_host_audit.py` | read-only source/plan analysis |
| `scripts/wc_fixtures.py`, `scripts/wc_ctrl68_fixture.py` | deterministic/random-BFM fixtures |

## 2. Physical DDR boundary (important distinction)

The current board build (`work/scripts/build_full.tcl:55-62`) connects the PL
AXI masters through `ddr_connect` to `ps/S_AXI_HP0_FPD`:

```
plans/{read,write,fetch,layout_read,layout_write}_axi -> ddr_connect -> ps/S_AXI_HP0_FPD
```

Therefore the correct statement is:

* **PS CPU does not participate** in the run-time data path after the single
  START; it only starts and observes completion/error.
* The PL traffic still passes through the **PS hard DDR controller / HP0 port**.
  It does **not** bypass that controller. There is no MIG/external-DDR port in
  this build, and no such change is made or claimed here.
* In logic simulation the DDR endpoint is modelled as an independent AXI slave
  (`wc_axi_bfm`). That is a logic model, not a board DDR timing model.

For a future truly independent DDR port, a MIG/board-specific adapter would be
required at the same AXI boundary; this is an integration option, not verified
hardware.

## 3. Superplan binary format (WCPL v1)

All words are little-endian 32-bit. The header is 64 B; each node is 64 B.

### 3.1 Header (words 0..15)

| word | field | required |
|---:|---|---|
| 0 | magic `0x5743504c` (`WCPL`) | exact |
| 1 | version `0x00010001` | exact |
| 2 | node_count | 1..128 |
| 3 | flags | bit0 parameter-RO, bit1 generation check; current RTL ignores flags and always enforces guards |
| 4 | param_end | `<= 0x40000000`; covers plans/payloads |
| 5 | plan_bytes | `64 + 64*node_count` |
| 6 | generation | 0 = ignore; otherwise must equal runtime `generation` |
| 7 | plan hash | FNV-1a over header words 0..6,8..15 and all node words |
| 8..15 | reserved | zero |

The hash is an **integrity check**, not a signature. It detects truncation /
bit flips between compile and run; it does not authenticate the image.

### 3.2 Node descriptor (words 0..15)

| word | field | meaning |
|---:|---|---|
| 0 | magic `0x57434e44` (`WCND`) | exact |
| 1 | type | 1 MAT, 2 VEC, 3 LAY, 4 SEQ |
| 2 | node_id | equals array index |
| 3 | dep_mask[31:0] | predecessor bits 0..31 |
| 4 | dep_mask[63:32] | bits 32..63 |
| 5 | dep_mask[95:64] | bits 64..95 |
| 6 | dep_mask[127:96] | bits 96..127 |
| 7 | base / payload address | MAT: queue base; VEC/LAY: payload address; SEQ: linear V022 plan base |
| 8 | count | MAT: queue descriptors; VEC/LAY: 0; SEQ: instruction count |
| 9..11 | reserved | zero |
| 12 | flags | zero in v1 |
| 13 | epoch | non-zero informational tag |
| 14..15 | reserved | zero |

Dependency rules enforced by the RTL:

* a node may only name lower-numbered predecessors
  (`dep_mask & ~((1<<id)-1) == 0`); forward edges/cycles are unrepresentable;
* dispatch occurs only when `(dep_mask & ~done_mask)==0`;
* one node may have any number of predecessors (up to 128-bit mask);
* completion sets `done_mask[node]`; the whole plan completes when all nodes
  complete or an error is latched and all accepted engine work drains.

### 3.3 Hash

```
h = 0x811c9dc5
for each header word j in 0..15 except 7: h = (h ^ word[j]) * 0x01000193
for each node word j in 0..15:           h = (h ^ word[j]) * 0x01000193
header[7] = h
```

## 4. `wc_superplan_ctrl` port contract

Clock/reset: `clk`, active-low `rst_n`. One START is a single-cycle pulse.

| group | signals | direction/notes |
|---|---|---|
| start/identity | `start`, `plan_base[31:0]`, `param_end[31:0]`, `parameter_ready`, `generation[31:0]` | `plan_base` 64-B aligned; one START; generation latched at start |
| status | `busy`, `done` (pulse), `fault` (level until next start), `error_code[7:0]`, `completed[31:0]`, `node_count[31:0]`, `rejected_starts[31:0]`, `last_node[31:0]`, `done_mask[127:0]` | `done` is asserted only after child drain; `irq` is sticky until next START |
| counters | `cycles`, `fetch_cycles`, `operator_cycles`, `drain_cycles` (64-bit), `drain_timeout` | `drain_timeout` is a status only; it never asserts DONE before drain |
| plan fetch | `fetch_req_valid/ready`, `fetch_address[31:0]`, `fetch_beats[15:0]`, `fetch_read_valid/ready`, `fetch_read_data[127:0]`, `fetch_read_index[15:0]`, `fetch_done`, `fetch_error` | single-outstanding 128-bit read; header 4 beats, node 4 beats, VEC payload 4, LAY payload 8 |
| SEQ engine | `seq_valid/ready`, `seq_base[31:0]`, `seq_count[31:0]`, `seq_done`, `seq_fault`, `seq_error[7:0]` | SEQ points at an immutable V022 linear plan |
| matrix engine | `mat_valid/ready`, `mat_base[31:0]`, `mat_count[31:0]`, `mat_done`, `mat_fault`, `mat_error[7:0]` | queue descriptors live in scratch; external matrix engine owns detailed descriptor validation |
| vector engine | `vec_valid/ready`, `vec_descriptor[511:0]`, `vec_done`, `vec_fault`, `vec_error[7:0]` | payload is fetched by the controller, then ACL-checked |
| layout engine | `lay_valid/ready`, `lay_descriptor[1023:0]`, `lay_done`, `lay_fault`, `lay_error[7:0]` | payload is fetched and ACL-checked |
| misc | `direct_idle` | no direct MAT/VEC/LAY engine active |

### Guards / error codes

| code | meaning |
|---:|---|
| 0x01 | bad START/header bounds/alignment/parameter not ready |
| 0x02 | parameter_ready lost or generation changed during the plan |
| 0x03 | plan/payload fetch DMA error or beat mismatch |
| 0x04 | bad header/node magic, id, reserved word, forward dependency, or hash |
| 0x05 | child fault without a child error code |
| engine code | child `*_error` is propagated (e.g. 0x55 in the drain test) |
| 0x07 | descriptor ACL/size/overlap failure in the top-level payload check |
| 0x09 | fetch/operation watchdog |
| 0xFF | illegal FSM state |

ACL policy in the controller/top:

* plans and VEC/LAY payloads must lie in `[PARAM_BASE, param_end)`,
  `param_end <= 0x40000000`;
* MAT queue base must lie in `[0x03000000, 0x08000000)`;
* VEC/LAY destination must lie in `[0x03000000, 0x08000000)` and must not
  overlap a source; sources may be in the parameter image (read-only) or the
  owned arena;
* writes to the parameter window are fatal in the BFM; the RTL engines do not
  issue them.

## 5. `wc_plan_top_v023` integration

The top adds the controller above the sealed V022 linear executor and shares
**one arithmetic copy** of the real vector/layout engines:

```
SEQ node  -> pl_execution_plan_v022 -> its fetch DMA + vector/layout/matrix
direct    -> wc_superplan_ctrl       -> same vector/layout/matrix
```

Ownership is conservative:

* `seq_owner` is set when the controller accepts a SEQ node; it is cleared on
  the subplanner's DONE.
* while `seq_owner=1`, direct-engine VALIDs are held off;
* a SEQ node may start only when `direct_idle=1`;
* therefore direct MAT/VEC/LAY nodes may overlap each other, but a SEQ node is
  mutually exclusive with direct nodes. This is a **prototype constraint**, not
  a claim of maximum parallelism.

AXI masters (all 128-bit, 40-bit address, single outstanding per channel):

1. `sf_*` superplan header/node/payload fetch
2. `qf_*` V022 linear-plan fetch
3. `vr_*` vector read
4. `vw_*` vector write
5. `lr_*` layout read
6. `lw_*` layout write

The existing board `plans` block exposes five masters
(`read, write, fetch, layout_read, layout_write`). The candidate top therefore
needs **one additional smartconnect SI** for the superplan fetch (or a fetch
arbiter shared with `seq_fetch`, not implemented here). That is a structural
integration cost, not a board-tested change.

Matrix is an external handshake (`matrix_valid/ready/base/count/done/fault`).
The existing accelerator still owns the matrix queue and its detailed queue
descriptor ACL. The controller checks only the queue base/count.

## 6. `wc_plan_csr` AXI-Lite map

Base `0xA9000000`, 24-bit address, 32-bit data.

| offset | access | value |
|---:|---|---|
| 0x00 | RO | magic `0x57434353` (`WCCS`) |
| 0x04 | RO | `{29'd0,fault,done_sticky,busy}` |
| 0x08 | RW | header/plan base |
| 0x0C | RO | node_count |
| 0x10 | WO | bit0=1 START if `!busy && parameter_ready`; bit0=0 bit1=1 clears DONE sticky |
| 0x14 | RO | completed |
| 0x18 | RO | last_node |
| 0x1C | RO | `{24'd0,error_code}` |
| 0x20/24 | RO | cycles lo/hi (snapshot) |
| 0x28 | RO | rejected_starts |
| 0x2C..0x38 | RO | done_mask[31:0], [63:32], [95:64], [127:96] |
| 0x3C | RO | generation |
| 0x40 | RO | param_end |
| 0x44/48 | RO | fetch_cycles lo/hi |
| 0x4C/50 | RO | operator_cycles lo/hi |
| 0x54/58 | RO | drain_cycles lo/hi |
| 0x5C | RO | drain_timeout |
| 0x60 | RO | version 0x00010001 |

AW and W are accepted independently; the response holds under backpressure.
Writes with `WSTRB!=0xF`, misaligned addresses, or unknown offsets get SLVERR.
START while busy gets SLVERR and does not pulse `start`.

## 7. Numerical semantics / limits

* No arithmetic is added to the controller or CSR. The V022 vector engine and
  its `asr_fp32_alu` are reused unchanged; layout is bit-copy only; the matrix
  engine remains external.
* W7 S6/J54/M30, A16, C48, lowest-bit positions, clip, and every Q/DQ boundary
  are untouched. No weight or tolerance was changed.
* Tests use real vector ADD/MUL and real layout COPY. The vendor `asr_fma_ip`
  netlist is **not present** in the read-only tree; simulations link the
  provided forbidden stub and never execute opcode 17. Vendor-FMA/op17,
  matrix arithmetic, and strict-ONNX outputs are therefore **untested here**.
* `MAX_NODES=128`. The real 68-program candidate fits. A whole CASE with more
  nodes requires hierarchical grouping (e.g. 64-node group descriptors), not
  implemented.
* **Timing:** the `SCAN` state evaluates up to 128 ready/dependency/type
  conditions combinationally in one cycle. This is a structural logic
  prototype, not a 300/600 MHz design. A production revision should bank the
  ready mask (e.g. 4×32 nodes), register bank candidates, and pipeline the
  priority select before STA. No frequency is claimed.
* The DMA controllers are the sealed `axi_dma_v019` at 125 MHz logic; their
  300/600 MHz timing is also outside this task.
* `generation=0` in the 68-program artifact means "ignore"; production must
  bind the sealed generation before a board run.
* The 68-program artifact is **not runnable as a whole CASE**: its inputs are
  produced by the non-fused host/legacy DAG. See `HOST_CLEARANCE.md`.
