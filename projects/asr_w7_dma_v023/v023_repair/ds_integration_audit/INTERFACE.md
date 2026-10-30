# INTERFACE — ds_integration_audit handoff to ds_integration

Status: **BLOCKED for whole-system integration**; module-level smoke evidence is
available. This file is the only coordination channel from this audit task to
`ds_integration`. No file in `ds_integration/` or any other worker directory was
modified.

Scope: logic simulation only. No synthesis, Vivado, STA, board, VNC, network or
push. Pinned source hashes: `PINNED_SHA256.txt` (32 files). Re-run:
`bash scripts/run_smoke.sh`.

## 1. What may be integrated now

| item | evidence | condition |
|---|---|---|
| `ds_control_fixes` `axi_dma_v023_multi` | independent audit TB, 8 cases, tag/4 GiB/WSTRB/abort/drain/tail pass | use only where its exact port shape fits |
| `ds_control_fixes` `axi_dma_v023_bounded` | independent audit TB, same cases pass | plan-fetch path |
| `ds_control_fixes` plan/CSR/scan/address | worker regression + primary acceptance re-run | plan v023 drain ports must actually be wired |
| `ds_vector` exact candidate | independent copy of worker regression: 67/67 exact, including the four former tail failures | FMA/op17 still not covered; approx is a separate wrapper |
| `ds_vector` + `ds_layout` + `wc_graph_ctrl` | independent real chain LAY copy -> VEC ADD 1.0 -> VEC MUL 2.0, 64/64 words vs locally computed float32 golden, 885 cycles, one START/one DONE | only this chain, not a whole model |
| `ds_layout` burst candidate | independent copy of worker run_all: official 8 normal + 12 error, fuzz 57, independent golden 32, random 100, prefetch 11, all fails=0 | one layout instance only; shared-DMA arbitration untested |
| `ds_matrix` cluster | independent Verilator run of `tb_p2_cluster_axi` K32: PASS, 2704 cycles, armax=8 | arithmetic golden is the worker's fixture, not independently re-derived here |

Do **not** cite `ds_graph` mode 2 (591-node replay) as a model run. It is a
synthetic host-order control replay with a MAT stub.

## 2. Recommended filelist

See `analysis/filelist_integrated.f`. Key choices:

- Layout: use **only** `ds_layout/rtl/ddr_layout_engine_v023_burst.sv`.
  Both layout files define module `ddr_layout_engine`; including both is a
  duplicate-definition error. The `_v023.sv` file is the diagnostic stepper.
- Vector: candidate wrapper module is `ddr_vector_axi_pipe`, not
  `ddr_vector_axi`. Either change the graph instance or add a one-line shim.
  This audit used a copied `wc_graph_top` with `ddr_vector_axi_pipe vec(...)`.
- Shared DMA: vector/layout wrappers and graph fetch still instantiate
  `work/rtl/axi_dma_v019.sv` (single outstanding). The new `axi_dma_v023_multi`
  is a different top-level port shape and is not a drop-in replacement for
  `axi_dma_v019`.
- Matrix: `matrix_p2_cluster_v2` is **not** a drop-in replacement for the
  `pl_execution_plan_v022`/graph MAT queue handshake. It takes `cfg_*` fields,
  not a 16-word V022 queue descriptor.
- FMA: `work/tests/fma_forbidden_stub.sv` is compile-only. Do not claim op17.

## 3. Wiring facts that must be respected

### 3.1 Graph top

`wc_graph_top` has:

```
seq_valid, seq_ready, seq_base, seq_count, seq_done, seq_fault, seq_error
matrix_valid, matrix_ready, matrix_queue_base, matrix_queue_count,
matrix_done, matrix_fault
```

It has **no** `seq_abort`, `seq_drained`, `matrix_abort`, `matrix_drained`.
`matrix_fault` is accepted, but `ctrl_mat_error` is tied to `0`, so a matrix
fault code is lost (the controller still raises code `0x05`).

### 3.2 Plan v023 child contract

`pl_execution_plan_v023` adds `child_abort`, `child_drained`, `dma_abort`,
`drain_timeout`, `isolation_req`, `drained`. The graph SEQ handshake cannot
carry the child-side pair. An adapter is required; none exists in the delivered
candidates.

### 3.3 Matrix adapter (missing)

A V022 matrix queue entry is 64 B:

```
word0 0x51415352, word1 header, word2 epoch, word3 dependency,
word4 A base, word5 B/param base, word6 C base, word7 m, word8 n, word9 depth,
word10 epoch, word11.. flags/positions/clip
```

`matrix_p2_cluster_v2` expects scalar `cfg_*` inputs, one operation at a time.
The graph MAT node supplies only `matrix_queue_base` and `matrix_queue_count`.
A queue fetch/decode/sequencer adapter (plus reset-polarity conversion) is
required and is not delivered. This is the main reason a real
matrix->conversion->vector->layout chain cannot be claimed.

### 3.4 Abort/drain mismatch

- `axi_dma_v023_multi` / `_bounded` have `abort/aborted/drained/busy` and pass
  the independent audit.
- `ds_matrix` `axi_dma_v020_multi_v2` has **no** abort/drained ports; the matrix
  cluster exposes neither.
- `ddr_vector_engine_pipe` / `ddr_vector_axi_pipe` have **no** abort/drained.
- `ddr_layout_engine_v023_burst` has **no** abort/drained.

Therefore `plan_v023`'s child contract cannot be satisfied by the delivered
matrix/vector/layout engines. A timeout can only end in isolation, not in a
verified drain.

### 3.5 SEQ occupies all engines

A V022 SEQ program internally drives matrix, vector and layout. WCPG models
SEQ, MAT, VEC and LAY as four independent engines. It refuses a new SEQ while
direct engines are active, but it can dispatch MAT/VEC/LAY while SEQ is active.
A mixed plan needs an explicit SEQ-exclusive gate (or re-lowering of the 68
programs into direct nodes). This is not implemented.

### 3.6 No watchdog on a hung direct child

`wc_graph_ctrl` only counts `drain_wait` after `fault_latched`. A MAT/VEC/LAY
child that never asserts `done` or `fault` (dead AXI slave, internal hang) is
never timed out by the graph controller. `drain_timeout` is a status flag in
the fault-drain path, not a terminal exit. `plan_v023` has its own WAIT_OP
watchdog; the graph direct-engine path does not.

## 4. Address/liveness contract

`ds_graph` allocation has 0 live conflicts among its 1,318 tensors, but:

- 698 tensors (16,771,840 B) overlap the sealed V022 matrix queue scratch
  `0x03000000..0x04000000`;
- the sealed plans still contain 89,118 old boundary/temp/scratch references
  and 98 layout moves to `0x03000000`; only 64,097 of those references have a
  new mapping;
- `relocation_map.json` explicitly says the sealed payload was not rewritten.

Do not execute the sealed 68 plans at the new global addresses. A real
re-lowering pass must rewrite queue descriptors and vector/layout payloads, and
reserve the scratch window. `relocation_map.json` is a map, not a re-lowered
image.

## 5. Blockers (must be closed before a system PASS)

1. Sealed payload is not re-lowered; 591 A/C alias sealed scratch
   (`0x03000000..0x04000000`).
2. Matrix queue-to-cluster adapter missing; no real matrix chain into
   conversion/vector/layout.
3. Plan v023 child abort/drain cannot be wired to matrix/vector/layout.
4. WCPG allows MAT/VEC/LAY concurrent with SEQ although SEQ owns them.
5. No watchdog/terminal exit for a hung direct child.
6. Matrix DMA and cluster have no abort/drained; matrix still uses combinational
   `block_address_v020`, not the v023 pipelined address former.
7. Full 591 tensor DAG and original ONNX/executor are not recovered. A local
   `model_a_int16` ONNX bundle exists but is a different (W16A16, v5/XC7A35T)
   release; it is an unblock lead, not the V022 graph.
8. FMA/op17 and approximate DIV/SQRT are not covered by this system smoke; no
   full-model accuracy or 300/600 MHz claim.

## 6. Commands

```bash
cd v023_repair/ds_integration_audit
bash scripts/run_smoke.sh          # expects PINNED_SHA256.txt to match
# optional drift override: ALLOW_SHA_DRIFT=1 bash scripts/run_smoke.sh
```

Per-stage rc and logs: `logs/smoke_results.csv`, `logs/*.log`.
