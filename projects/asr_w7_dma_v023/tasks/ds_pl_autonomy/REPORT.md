# REPORT — PL autonomous whole-plan control (W023 candidate)

Date: 2026-10-29  
Task: `ds_pl_autonomy`  
Scope: remove the per-program host/PS control gap for the closed V022
CONV/FFN set, design a static whole-plan compiler + PL descriptor/dependency
controller, and prove the control/data-chain path in logic simulation.

This is **not** a whole-CASE result and **not** a board/timing result. See
§7 for the exact coverage boundary.

## 1. Result in one paragraph

The supplied V022 board executes 68 closed CONV/FFN programs, but the host
starts/polls/reads each program separately and the 68 programs are tensor-name
islands: all of their inputs come from the non-fused host/legacy DAG. A static
compiler now emits a 4,416-byte WCPL superplan containing the 68 real program
pointers, a 128-bit dependency mask per node, and an integrity hash. A new
`wc_superplan_ctrl` fetches the header/nodes/payloads from DDR, schedules
multiple engines by dependency, enforces parameter/generation and VEC/LAY
address ACLs, drains accepted work on error, and emits one DONE/IRQ. The
compiled 68-node plan runs in Icarus and Verilator with one START, 68
dispatches, one DONE and zero errors under a SEQ control stub. A real
layout→vector→vector chain and a real V022 SEQ subplan (layout+vector) are
bit-exact against an independent Python float32 golden. The parallel/root
version of the same 68 nodes is rejected: all 2,278 unordered pairs overlap in
DDR, and temp arenas peak at 36 simultaneously-live ranges. Whole-CASE
autonomy is therefore **not claimed**; the outside 591 legacy queues and the
missing upstream executor/model remain the blocker.

## 2. Read-only inputs and constraints

Read before coding:

* `EXECUTION_CONTRACT.md`
* `work/DESIGN_CONTRACT_zh.txt`
* `work/CURRENT_WORK.txt`
* `IC_GIT_REFERENCES.txt`

No file under `work/` was modified. The sealed
`model_a_v0_22(1).zip` SHA256 is
`327ea1b4b228a0415b370a208e2a6881e6547a49473b360105724a12655eda84`.
The manifest used for analysis is byte-identical to the sealed image
(`assets/manifest_v022.json`, SHA in `SOURCE_BASELINE.json`).

Preserved without change:

* W7 S6/J54/M30, original low-bit positions, clip, parity;
* A16 operands, C48 accumulator/output conversion;
* FP32 FTZ/RNE and the original FMA ordering (no FMA/op17 is executed in
  these tests because the vendor `asr_fma_ip` netlist is absent);
* every Q/DQ boundary, weight, model tolerance, and the sealed parameter image.

No synthesis, Vivado, bitstream, board, VNC, network deployment or push was
performed. 300/600 MHz are structural targets only.

## 3. What the host still does (audit)

`analysis/host_actions.json` contains 200 source hits; the ledger is
`analysis/host_clearance.json` (20 actions: 3 candidate-covered, 4
offline-only, 10 must-move, 3 not-implemented).

Main residual runtime actions:

* `run_case0000.py:62-67` runs the ONNX graph through the host executor.
  The executor/model are **absent** from the supplied tree.
* `fusion_backend.py:23-52` packs/uploads each fused input, sends one
  `0xe400` START, polls every 50 ms, then reads each float/Q output.
* `base_v021.py:24-48,181-209` chooses M/N windows, decomposes INT16, encodes
  W7 and calls per-matrix queues for unfused calls.
* `base_v021.py:62-113` packs A/W tiles, emits queue descriptors, and
  converts C48→INT64 on the host.
* `backend_v021.py:40-82` carries implicit weight/context round-robin,
  cookies/epochs, FP32 dedup tables and `write_words` copies.
* `ps/vm_pl.c:16-39` performs one PS program start/poll per closed program.

The exact outside-node list cannot be recovered here because
`fusion_executor.py`, `profiled_backend.py` and the packed ONNX models are not
present. `work/CURRENT_WORK.txt:23` records the remaining 591 queues / 593
descriptors. This is quoted, not independently re-derived.

## 4. Candidate architecture

### 4.1 Static superplan

Format: 64-B header + N×64-B node descriptors, little-endian, FNV-1a
integrity hash (see `INTERFACE.md`). A node is MAT, VEC, LAY or SEQ. The real
68 nodes are SEQ: each points at an immutable V022 linear plan. Dependencies
are 128-bit predecessor masks; only lower-numbered predecessors are legal, so
cycles are unrepresentable. The compiler also emits a root/parallel candidate
to demonstrate why serialization is required.

### 4.2 Controller

`wc_superplan_ctrl`:

1. one START; validates plan bounds/alignment/parameter readiness;
2. PL DMA-fetches the header, then all node descriptors into a 128-entry
   register file, verifying magic/type/id/reserved words/topology/hash;
3. scans ready nodes and dispatches to SEQ/MAT/VEC/LAY; multiple engine
   classes can overlap;
4. for VEC/LAY, fetches the real 64/128-B payload and checks the descriptor
   ACL before dispatch;
5. latches `generation` and re-checks it during fetch/dispatch/drain;
6. on child fault, stops new dispatch, drains every accepted engine, then
   asserts DONE/IRQ with the error; a bounded `drain_timeout` is reported but
   never fakes completion before drain.

`wc_plan_top_v023` places this above the sealed `pl_execution_plan_v022` and
shares one real copy of the vector/layout engines. SEQ and direct nodes are
mutually exclusive in this prototype (conservative ownership), while direct
MAT/VEC/LAY can overlap. Matrix remains the external accelerator handshake.

### 4.3 Error/ACL/generation

Tested error paths: 0x02 generation loss, 0x04 bad hash, 0x07 bad VEC ACL,
0x55 child fault with drain, 0x01/0x03 guards. The BFM makes any write to the
parameter window fatal, so parameter read-only is enforced in every run.
Scratch/intermediate destinations are checked against
`0x03000000..0x08000000`.

## 5. Evidence

All commands/return codes/logs: `reports/run_all/run_all.json`.

### 5.1 Static/compiler

| check | result |
|---|---|
| sealed image SHA / manifest SHA | recorded in `analysis/analysis.json`, `SOURCE_BASELINE.json` |
| 68 plans parsed, 45,055 instructions, 6,231 matrix descriptors | PASS |
| tensor-name DAG | 68 roots / 68 leaves, **0 edges** |
| unordered DDR hazard pairs | **2,278 / 2,278** (WAW=RAW=WAR) |
| temp overlap | 994 pairs; peak **36** live ranges |
| serial 68-node binary | hash/topology/pointer verification PASS, 0 unordered conflicts |
| root/parallel 68-node binary | strict verification **FAIL**, 2,278 conflicts |
| random compiler DAGs | 200/200 pass; forward cycle/bad hash/129 nodes rejected |

### 5.2 Controller (control-only stubs)

| mode | result |
|---|---|
| 0 diamond 7 nodes | PASS, 296 cycles, one DONE, 7/7 |
| 1 child fault while LAY drains | PASS, error 0x55, DONE after 200-cycle drain |
| 2 generation change | PASS, error 0x02, drain |
| 3 bad hash | PASS, error 0x04, zero dispatches |
| 4 bad VEC ACL | PASS, error 0x07, zero dispatches |
| 5 START replay | PASS, `rejected_starts=1`, one DONE |
| 6 eight mixed nodes | PASS, 8/8, one DONE |
| 7 **real compiled 68-node plan** | PASS, 68/68, one DONE, one IRQ, 1,372 cycles |

Mode 7 is the actual `whole68_serial.bin` from the real manifest/image (with a
control-fixture header `param_end=0x40000000`); the SEQ engine is a stub, so
this proves the **plan, topology, fetch and completion**, not arithmetic.

### 5.3 Real operator data chains

`tb_wc_top` uses the sealed real `ddr_layout_axi` and `ddr_vector_axi`
(real `asr_fp32_alu`), with the forbidden FMA stub only to satisfy the missing
vendor port; no FMA/op17 descriptor is used.

| mode | chain | result |
|---|---|---|
| 10 | LAY copy → VEC add 1 → VEC mul 2 | PASS, 64/64 words vs Python float32 golden, 2,267 cycles |
| 11 | one SEQ node (V022 LAY+VEC) | PASS, 64/64 words, 1,583 cycles |
| 12 | LAY → VEC → SEQ(LAY+VEC) → VEC | PASS, 64/64 words, 3,842 cycles |
| CSR | AXI-Lite START/guard/sticky/readback | PASS, 39 checks |

Same-seed engine-local counters for mode 12 vs the before harness:
vector 688 vs 689 cycles, layout 791 vs 787 cycles. The arithmetic work is
comparable; the plan-level difference is the scheduler/fetch/ownership path.

### 5.4 Before/after control metrics (same BFM, aligned ports/seed)

| workload | starts | DONE/IRQ | cycles |
|---|---:|---:|---:|
| 68 nodes, one superplan | 1 | 1 | 1,372 |
| 68 nodes, one start each | 68 | 68 | 2,505 |
| 4 real nodes, one superplan | 1 | 1 | 3,842 |
| 4 real programs, one start each | 4 | 4 | 719 |

Interpretation: the one-START controller removes 67 starts/67 completion
events for the 68-node control workload. For the tiny 4-node real workload the
superplan preload/ownership overhead dominates, so **no blanket speedup is
claimed**. A 200-cycle host gap was completely hidden by the running program
(719 vs 719 cycles), so it is not an additive CASE-time model.

## 6. Findings (26, machine-readable in `FINDINGS.jsonl`)

Highest-impact:

1. **Disconnected graph** — 68 roots/leaves, 0 tensor edges; the 68 programs
   alone cannot be a whole CASE.
2. **Universal DDR conflict** — all 2,278 unordered pairs have WAW/RAW/WAR;
   root-parallel dispatch is corrupting.
3. **Temp liveness** — 36 temp ranges alive at one address; per-program
   `temp_base=0x04000000+extent_bytes` is not global.
4. **Output alias** — 4 output-address groups with 6/12/24 writers; only the
   host serial order makes this safe.
5. **Plan identity/guards** — V022 has no content hash; W023 adds one, but
   generation=0 in the 68 artifact must be bound before production.
6. **Drain/liveness** — V022 can wait forever before a child accepts work;
   W023 reports bounded drain status but still refuses to fake DONE.
7. **Physical DDR** — PL uses `ps/S_AXI_HP0_FPD`; PS CPU is out of the loop,
   but the PS hard DDR controller is not bypassed.
8. **Missing upstream** — FusionExecutor/model absent; outside DAG not lowerable
   here.

## 7. Coverage and explicit non-claims

| item | status |
|---|---|
| 68/68 closed programs control/topology/one-START | PROVEN (logic, SEQ stub) |
| real layout→vector data chain | PROVEN (logic, 64/64 words) |
| real V022 linear subplan (layout+vector) | PROVEN (logic, 64/64 words) |
| matrix queue arithmetic / W7+A16+C48 | **NOT TESTED** (external engine, only control stub) |
| vendor FMA/op17 | **NOT TESTED** (netlist absent; forbidden stub) |
| outside 591 queues / 593 descriptors | **NOT IMPLEMENTED** (source/model absent) |
| whole CASE0000 / strict ONNX | **NOT RUN** |
| full-model host removal | **NOT ACHIEVED** |
| STA/DRC/bitstream/board/300-600 MHz | **NOT RUN / NOT CLAIMED** |
| 300/600 MHz registered/pipelined control scan | **NOT IMPLEMENTED** (current scan is combinational over ≤128 nodes) |
| true bypass of PS hard DDR controller | **NOT POSSIBLE in this build; needs MIG/adapter** |

The 68-node artifact is a verified **control/serialization skeleton**, not a
runnable whole model. Its `runnable_whole_case=false` field is authoritative.

## 8. Reproduce

```bash
cd tasks/ds_pl_autonomy
python3 scripts/run_all.py
```

`run_all.py` runs 18 static/compile checks and 24 simulations (Icarus +
Verilator), sequentially, `-j2` for Verilator only. All 24 simulations pass;
17 static/compile checks return rc=0 and the intentionally strict root/parallel
verifier returns rc=1 (rejection of the unsafe roots plan), recorded as
expected.

Individual examples:

```bash
# control diamond
iverilog -g2012 -s tb_wc_ctrl -o /tmp/ctrl.vvp \
  rtl/wc_superplan_ctrl.sv ../../work/rtl/axi_dma_v019.sv \
  tb/wc_axi_bfm.sv tb/tb_wc_ctrl.sv
vvp /tmp/ctrl.vvp +mode=0 +plan=10000000 \
  +memfile=tests/fixtures/mem_init.hex +seed=7

# real layout/vector chain
iverilog -g2012 -s tb_wc_top -o /tmp/top.vvp \
  rtl/wc_plan_top_v023.sv rtl/wc_superplan_ctrl.sv \
  ../../work/rtl/pl_execution_plan_v022.sv ../../work/rtl/ddr_vector_axi.sv \
  ../../work/rtl/ddr_vector_engine.sv ../../work/rtl/ddr_layout_axi.sv \
  ../../work/rtl/ddr_layout_engine.sv ../../work/rtl/asr_fp32_alu.sv \
  ../../work/rtl/u16_divmod.sv ../../work/rtl/axi_dma_v019.sv \
  ../../work/tests/fma_forbidden_stub.sv tb/wc_axi_bfm.sv tb/tb_wc_top.sv
vvp /tmp/top.vvp +mode=10 +plan=10008000 \
  +memfile=tests/fixtures/mem_init.hex +seed=7
```

## 9. Source identity

`SOURCE_BASELINE.json` records:

* 28 read-only `work/` sources and the parameter image/manifest hashes;
* 18 candidate RTL/TB/script hashes (including this report's modules);
* sealed zip SHA;
* artifact hashes (`whole68_serial.bin`, `whole68_roots.bin`, fixtures,
  `run_all.json`, findings).

`result.json` contains the summarized facts, test counts and non-claims.

## 10. Integration recommendation

Use `wc_superplan_ctrl` as the new board-level plan controller and
`wc_plan_csr` as the PS-visible window. Keep the sealed V022 linear executor
as the SEQ engine; route its matrix port to the existing accelerator. Before a
board build:

1. add the sixth AXI master (superplan fetch) or a fetch arbiter;
2. bind a production generation (not 0);
3. lower the outside DAG and relocate/alias-check all arenas;
4. keep the strict verifier in the build gate;
5. bank/register the 128-node ready-mask scan and pipeline the priority
   select before any 300/600 MHz STA claim;
6. run full STA/DRC/board tests in a separately authorized task.

Do not claim whole-CASE autonomy until the outside 591 queues are PL nodes and
the whole graph has a verified tensor/arena allocation.
