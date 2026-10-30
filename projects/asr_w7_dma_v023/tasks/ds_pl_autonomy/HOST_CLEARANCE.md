# HOST CLEARANCE — still-host work and W023 disposition

Scope: the read-only supplied tree is `work/`. The upstream `FusionExecutor`,
`profiled_backend`, packed ONNX models and the outside-DAG source are **not**
present there; the audit therefore combines source inspection with the sealed
manifest/image. Numeric semantics (W7 S6/J54/M30, A16, C48, FP32 FTZ/RNE/FMA,
Q/DQ boundaries) are not changed by any item below.

Machine-readable ledger: `analysis/host_clearance.json`.
Raw source hits: `analysis/host_actions.json`.

## 1. What W023 actually removes

The candidate proves, in logic simulation:

* one START and one DONE/IRQ for a plan (not one per program);
* autonomous superplan header/node/payload fetch by PL DMA;
* 128-bit dependency scoreboards with multiple predecessors;
* real layout→vector DDR data movement, and a real V022 linear subplan;
* parameter/generation guards, VEC/LAY descriptor ACL, error drain;
* the compiled 68-node real-program plan runs under a SEQ control stub with
  **68 dispatches, one START, one DONE** (Icarus and Verilator).

It does **not** yet remove the whole host DAG. The 68 closed programs are
disjoint islands: every one of their 68 inputs is produced by an operation
outside the closed set. Executing the 68 nodes with a single START without
lowering those producers would read stale/uninitialized DDR.

## 2. Ledger (summary)

| id | host action | source | W023 status |
|---|---|---|---|
| H01 | ONNX graph / per-node Python dispatch | `scripts/run_case0000.py:62-67` | NOT_IMPLEMENTED (upstream executor/model absent) |
| H02 | one START + poll + output read per fused program | `host/fusion_backend.py:28-52` | CANDIDATE_COVERED for plan control; real 68 still blocked by H01/H14 |
| H03 | per-program input upload | `host/fusion_backend.py:23-24` | MUST_MOVE |
| H04 | per-program output download | `host/fusion_backend.py:48-51` | MUST_MOVE |
| H05 | runtime M/N window choice | `host/base_v021.py:24-48,191-197` | OFFLINE_ONLY |
| H06 | A16/W7 pack + matrix descriptors | `host/base_v021.py:62-105`, `host/backend_v021.py:9-33` | OFFLINE_ONLY |
| H07 | C48→INT64 conversion | `host/base_v021.py:107-113,178-180` | MUST_MOVE |
| H08 | unfused INT16 matmul + dynamic W7 encoding | `host/base_v021.py:181-209` | NOT_IMPLEMENTED |
| H09 | nonmatrix `write_words` + FP32 dedup | `host/backend_v021.py:71-82` | MUST_MOVE |
| H10 | resident matrix context/view round-robin | `host/backend_v021.py:40-70` | MUST_MOVE |
| H11 | host cookie/epoch and stale checks | `host/base_v021.py:126,153-168` | MUST_MOVE |
| H12 | parameter generation re-check | `host/backend_v021.py:46-49` | CANDIDATE_COVERED (generation latch/guards) |
| H13 | PS per-program start/poll | `ps/vm_pl.c:16-39` | CANDIDATE_COVERED |
| H14 | 591 legacy queues / 593 descriptors | `work/CURRENT_WORK.txt:23`, `ps/plan_index.h:8-76` | NOT_IMPLEMENTED |
| H15 | PS per-program matrix index lookup | `ps/vm_pl.c:17-19` | MUST_MOVE |
| H16 | offline plan compilation | `scripts/compile_pl_plans.py` | OFFLINE_ONLY (desired) |
| H17 | per-program temp arena base | `scripts/compile_pl_plans.py:32-34` | MUST_MOVE (36 live ranges overlap) |
| H18 | per-program output/scratch address reuse | `scripts/compile_pl_plans.py:59-71` | MUST_MOVE |
| H19 | matrix queue copy to scratch by PL layout move | `scripts/compile_pl_plans.py:72-75` | OFFLINE_ONLY / keep in PL |
| H20 | host scale/Tensor reconstruction | `host/fusion_backend.py:50-51` | MUST_MOVE |

Counts: `CANDIDATE_COVERED=3`, `OFFLINE_ONLY=4`, `MUST_MOVE=10`,
`NOT_IMPLEMENTED=3`.

## 3. Per-matrix decisions that must disappear

For every unfused matrix call the host still decides:

1. batch broadcast shape and output allocation (`base_v021.py:187-189`);
2. effective K (INT16 decomposition) (`base_v021.py:190`);
3. M row window via `choose_row_step` (`base_v021.py:29-48,191`);
4. N column window via `column_step` (`base_v021.py:24-27,196`);
5. W7 codes from the runtime B operand (`_encode`, `base_v021.py:200-204`);
6. A/W tile bytes and 64-B queue descriptors (`pack_task`, `62-105`);
7. queue epoch/cookie (`cookie21`);
8. start/wait/read of C (`native21`, `151-180`);
9. C48→INT64 (`unpack_c`, `107-113`);
10. scale lookup/Tensor reconstruction (`fusion_backend.py:50-51`).

The 68 closed CONV/FFN programs already freeze their matrix descriptors in
`compile_pl_plans.py` (offline), so items 5–7 are frozen **for those 68**.
They are not frozen for the outside 591 queues. W023's compiler binds SEQ
program pointers but does not yet relocate their A/C arenas or bind the
outside matrix calls.

## 4. Address alias / overwrite / cycle evidence

From `analysis/analysis.json` and `analysis/whole68.json`:

* 68 programs, 636 original nodes, 45,055 V022 instructions, 6,231 matrix
  descriptors.
* Tensor-name dependence between the 68 programs: **0 edges** (all 68 are
  roots and leaves). The graph is disconnected because outside ops sit between
  them.
* DDR hazards: **2,278 / 2,278** unordered program pairs have WAW, RAW and WAR
  overlap. 15 distinct write spans are shared (4 output-address groups with
  6/12/24 writers).
* Temporary arenas: 994 overlapping pairs; peak **36** live temp ranges at one
  address; summed pairwise overlap 709,431,296 bytes (double-counted; the peak
  count is the actionable number).
* The parallel/root candidate `whole68_roots.bin` is rejected by the verifier
  with 2,278 unordered conflicts. The serial candidate
  `whole68_serial.bin` has zero unordered conflicts and passes.
* No directed cycle exists in the name graph (there are no edges). The binary
  format also forbids cycles structurally: a node may only depend on lower
  indices; forward edges are rejected. `test_compiler_random.py` checks 200
  random DAGs plus a deliberate two-node cycle and a bad hash.

**Consequence:** the 68 programs cannot be dispatched in parallel as they
stand. They can be serialized (control-safe), or their A/C/temp/queue arenas
must be relocated to disjoint ranges by a liveness allocator. W023 implements
the serial proof and the rejection test; it does not implement the full
relocator.

## 5. Host implicit state

These are not derivable from the plan binary and must be bound offline or
replaced by explicit PL state:

| state | source | required replacement |
|---|---|---|
| `cookie21` / queue epoch | `base_v021.py:126,153-168`; `fusion_backend.py:46-47` | plan generation + per-node epoch in header; retire host cookie |
| `matrix_index21` / `context21` | `backend_v021.py:40,45,54-58` | concrete weight/context id per matrix node |
| `param_state21` | `backend_v021.py:48` | header generation latch (candidate has this) |
| `repeat_lengths` / `fp32_refs` | `backend_v021.py:40-43,72-79` | explicit copy nodes/parameter ids |
| `context['matrices'][...]` round-robin | `backend_v021.py:58` | static node→weight binding |
| host input/output tensor identity | `fusion_backend.py:17-24,48-51` | tensor-address table in the superplan |

## 6. Staged clear list

### Stage A — done in this task (logic only)

1. One START / one DONE / one IRQ plan controller.
2. PL fetch of header, nodes, VEC/LAY payloads.
3. 128-bit dependency masks and multi-predecessor joins.
4. Real layout→vector DDR chain and real V022 linear subplan.
5. Parameter read-only guard, VEC/LAY ACL, generation guard, drain/error.
6. Compile and verify the 68-node serial candidate; prove the root/parallel
   candidate is unsafe.

### Stage B — required before any whole-CASE claim

1. Recover the upstream `FusionExecutor`, packed ONNX and outside-DAG source.
2. Build a whole-graph tensor/arena allocator with liveness; relocate every
   A/C/temp/queue range or prove a total order.
3. Lower all outside nodes (layout/im2col, LayerNorm, softmax, GELU/activation,
   embedding, concat/slice/transpose, Q/DQ, final head) to PL SEQ/direct nodes.
4. Bind every matrix node to a concrete weight/context; remove
   `matrix_index21/context21`.
5. Preload inputs/weights/plan once; after START, no host upload/download;
   host reads only final outputs.
6. Replace host/PS polling with the plan IRQ; PS no numerical control flow.
7. Extend the board integration for the sixth AXI master (or a shared fetch
   arbiter) and re-run STA/DRC/Vivado/board work in a separate authorized task.

### Stage C — evidence that is still missing

* Whole-CASE0000 output on board vs V21 and strict ONNX.
* Matrix arithmetic / W7/A16/C48 numerical chain in this candidate.
* Vendor `asr_fma_ip`/op17 (netlist absent; forbidden stub used).
* 300/600 MHz timing (no synthesis/STA here; not claimed).
* True bypass of the PS hard DDR controller (not present; MIG/external-DDR
  integration would be required).

## 7. Correct boundary statement

> The candidate removes **PS CPU per-program control** and **per-program
> MMIO/DDR staging** for the closed plan. It does not remove the PS hard DDR
> controller from the physical path, does not execute the outside DAG, and
> does not claim whole-CASE autonomy. The 68-program artifact is a verified
> control/serialization skeleton, not a runnable whole model.
