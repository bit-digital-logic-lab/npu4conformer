# REPORT — ds_integration_audit: integration readiness and whole-graph PL gaps

Date: 2026-10-29
Directory: `/home/yang/Desktop/项目/v023_repair/ds_integration_audit`
Scope: **logic simulation only**. No synthesis, Vivado, STA, DRC, board, VNC,
network or push. Other workers' directories, `work/` and the sealed ZIP were
read-only. All new files are under this audit directory.

## 0. Verdict

**System integration is NOT ready.** Module-level smoke checks pass for the
parts that were actually run, but the following delivery-level gaps block an
honest system PASS:

1. the sealed 68 plans were not re-lowered to the new global addresses, and
   698 allocated tensors alias the sealed `0x03000000..0x04000000` matrix
   scratch;
2. the matrix queue-to-cluster adapter is missing, so a real
   matrix -> conversion/vector -> layout chain cannot be run from a graph node;
3. `plan_v023`'s child abort/drain contract cannot be connected to the
   delivered matrix/vector/layout engines (none has abort/drained);
4. WCPG treats SEQ/MAT/VEC/LAY as independent engines although a V022 SEQ
   program owns all of them, and a hung direct child has no terminal watchdog.

This audit does not claim full CASE0000, 591 true dataflow, FMA/op17,
full-model accuracy, or 300/600 MHz.

## 1. What was independently executed

Run `bash scripts/run_smoke.sh`; per-stage rc is in `logs/smoke_results.csv`.
The smoke run exited **0** (`SMOKE_RESULT=PASS`) because every stage it covers
passed; that is not a system acceptance. The blockers in §5 are interface and
delivery gaps, not failed tests.

| evidence | result | independent? |
|---|---|---|
| DMA `axi_dma_v023_multi` audit | 8/8 checks: tail 40 beats -> 16+16+8, 4 GiB crossing, WSTRB tail 51 B, early RLAST error, abort read (accepted R drained, no new AR), abort before AR, abort write (accepted W+B drained), no error | **yes** (own BFM/TB/golden) |
| DMA `axi_dma_v023_bounded` audit | same 8 cases pass | **yes** |
| DMA `axi_dma_v020_multi_v2` (matrix) audit | functional tail/4 GiB/WSTRB/early-RLAST pass; **no abort/drained ports** | **yes** for function; static fail for abort |
| real graph chain LAY copy -> VEC ADD 1.0 -> VEC MUL 2.0 | 64/64 words match a locally computed float32 golden, 4/4 nodes, one START/one DONE, no fault, 885 cycles; sealed baseline same test 2,353 cycles | **yes** for the chain golden; only ADD/MUL |
| vector exact regression (isolated copy) | 67/67 exact including former `add_tail5/add_tail7/a48_tail3/f32_to_i16_tail7`; 7 stress; rc=0 (`logs/vector_regression_copy.log`) | rerun of worker harness/gold, **not** an independent golden |
| layout full regression (isolated copy) | official 8 normal + 12 error, fuzz 57, independent-golden 32, random 100, prefetch 11: all `fails=0`; rc=0 (`logs/layout_run_all_copy_rc.log`) | rerun of worker harness/golden |
| matrix cluster K32 AXI run | `PASS`, 2,704 cycles, armax=8, wr_bytes=6144, rc=0 | run of worker TB/golden, **not** independent arithmetic |
| graph allocation/relocation parser | 0 live conflicts; 698 tensors alias sealed scratch; 89,118 old refs; 98 moves to 0x03000000 | **yes** |
| bounded dependency search | host modules missing; import probe fails; local int16 ONNX candidates found but different release | **yes** |

Source hashes: `PINNED_SHA256.txt` (32 files). The smoke script refuses to run
if the hashes drift unless `ALLOW_SHA_DRIFT=1` is set.

## 2. Module interfaces and filelist reality

Full filelist: `analysis/filelist_integrated.f`. Machine-readable checks:
`analysis/interface_audit.json`.

Found facts:

- `ddr_layout_engine_v023.sv` and `ddr_layout_engine_v023_burst.sv` both define
  `ddr_layout_engine`. Only one may be compiled. The burst file is the
  integration candidate (`4e45a39d…`).
- The vector candidate wrapper is `ddr_vector_axi_pipe`, while
  `wc_graph_top` instantiates `ddr_vector_axi`. A shim or a one-line top edit
  is required; this audit used an edited copy.
- `matrix_p2_cluster_v2` is a `cfg_*`/result cluster, not a V022 queue decoder.
  A graph MAT node gives only `queue_base/queue_count`; there is no delivered
  adapter that fetches and sequences 16-word queue descriptors.
- `matrix_p2_cluster_v2` has active-high `reset`; plan/graph use `rst_n`.
- Matrix still instantiates combinational `block_address_v020` five times;
  `ds_control_fixes`'s pipelined `block_address_v023` is not integrated.
- Vector/layout wrappers and graph fetch still use single-outstanding
  `axi_dma_v019`; the new multi DMA is a different port shape.

## 3. DMA audit detail (independent)

The independent BFM is `scripts/axi128_audit_bfm.sv`: AR/AW queues, in-order R,
stable data under backpressure, WSTRB byte writes, delayed B, early/late RLAST,
and configurable stalls. It is not derived from a worker TB.

`axi_dma_v023_multi` and `_bounded` passed:

- read 40 beats: 3 ARs with lengths 15/15/7, 640 B, index 40;
- read at `0xFFFFFFF0` for 2 beats: ARs `0xFFFFFFF0`, `0x100000000`
  (no 32-bit wrap);
- write 4 beats with final `WSTRB=0x0007`: `write_bytes=51`, first 3 tail bytes
  correct, untouched bytes retain memory;
- write 4 GiB crossing: AWs `0xFFFFFFF0`, `0x100000000`;
- early RLAST: error, drains, no hang;
- read abort: no new AR after abort; all accepted R beats returned; `aborted=1`,
  `drained=1`, no error;
- write abort: no new AW after abort; accepted W burst and B responses drained;
  `aborted=1`, `drained=1`, no error;
- abort before any AR: `aborted=1`, `drained=1`, zero AR.

`axi_dma_v020_multi_v2` passed the functional cases but has **no**
`abort/aborted/drained` ports. A wrapper in this audit ties them off only so the
same functional TB can run; that is not an abort-capable integration.

## 4. Whole-graph relocation and liveness

Parser: `scripts/audit_graph_relocation.py`; output:
`analysis/graph_relocation_audit.json`.

- The allocator's own claim of 0 live conflicts is independently reproduced
  (1318 tensors, no overlapping live address ranges).
- **But** 698 tensors (349 A + 349 C48), 16,771,840 B, overlap the sealed V022
  matrix queue scratch `0x03000000..0x04000000`. The current 68/591 plans were
  never meant to coexist there.
- Re-parsing the sealed `parameters002` image and `manifest_v022`:
  - 45,055 instructions, 6,231 matrix queue descriptors;
  - 89,118 references to old boundary/temp/scratch addresses;
  - 64,097 of those have a new map in `relocation_map.json`; **25,021** are
    sealed-scratch references with no map;
  - 98 layout moves still target `0x03000000`;
  - only 338 address words happen to equal a new base, and these are
    coincidental param values, not a re-lowered image.
- `relocation_map.json` itself says the sealed payload interior pointers were
  not rewritten. Direct execution under `global_alloc.json` is therefore a
  data-corruption bug, not a performance issue.
- The 68 programs share one 30,277,632 B temp extent; two maximum extents plus
  A/C do not fit the 80 MiB arena. The serial-SEQ ownership policy is plausible
  only if SEQ is truly serialized.

### 4.1 WCPG/engine ownership

`wc_graph_ctrl` refuses a new SEQ while direct engines are active, but permits
MAT/VEC/LAY dispatch while SEQ runs. A V022 SEQ program drives matrix, vector
and layout internally. A mixed plan can therefore start two users of the same
hardware. No arbiter or SEQ-exclusive gate exists.

`wc_graph_ctrl` has no operation watchdog for a direct child. `drain_wait` only
advances after `fault_latched`; a child that never asserts done/fault leaves the
controller in SCAN forever. `drain_timeout` is a status bit in the fault-drain
path, not a terminal finish. `plan_v023` has a WAIT_OP watchdog, but the graph
direct-engine path does not.

## 5. Blockers (ordered, concrete)

1. **No re-lowered sealed payload / scratch alias.** 698 tensors overlap
   `0x03000000..0x04000000`; 89,118 old references and 98 scratch moves remain.
   Reserve the scratch window and rewrite queue descriptors plus vector/layout
   payloads before any combined 68+591 run.
2. **No matrix queue adapter.** `matrix_p2_cluster_v2` cannot consume a graph
   MAT node. The required adapter must DMA 16-word queue descriptors, drive
   `cfg_*`, sequence `start/done`, handle reset polarity, and expose drain.
   Without it, no honest matrix -> conversion -> vector -> layout chain.
3. **No child abort/drain on matrix/vector/layout.** `plan_v023` cannot satisfy
   its child contract. `child_abort` has nowhere to go; timeouts can only
   request isolation.
4. **SEQ/direct-engine concurrency is unsafe.** Add a SEQ-exclusive gate for
   MAT/VEC/LAY, or re-lower SEQ into direct nodes.
5. **Hung direct child has no terminal watchdog.** Add a per-dispatch deadline
   and a defined terminal error/finish (with isolation), not just a flag.
6. **Matrix DMA/cluster lack abort/drained; matrix still uses combinational
   `block_address_v020`.** `axi_dma_v023_multi` could be adapted, but the
   cluster's exact port shape is not a drop-in.
7. **Full 591 tensor DAG / original executor missing.** `work/host` imports
   fail on `profiled_backend`, `lowbit_executor`, `vm_abi`. The local
   `model_a_int16` ONNX bundle is a different (W16A16, v5/XC7A35T) release and
   is not proof of the V022 W7p8/A16/C48 graph.
8. **FMA and approximate math are not in this system smoke.** FMA/op17 remains
   a worker/vendor-IP gap. DIV/SQRT approximation was measured by others
   (about 0.108% max relative DIV, ~0.0006% SQRT/RSQRT); this audit did not
   re-measure it and makes no full-model accuracy claim.

## 6. Explicitly not claimed

- Not full CASE0000, not a 591 true-dataflow run. `ds_graph` mode 2 is a
  synthetic host-order control replay with a MAT stub; it is not a model.
- Not a matrix arithmetic independent golden; the matrix cluster run compares
  to the worker's fixture.
- Not an independent vector/layout arithmetic golden; those were reruns of the
  worker harnesses. The independent arithmetic evidence here is the small
  LAY->ADD->MUL chain.
- Not FMA/op17, not approximate DIV/SQRT in this system, not quantized model
  accuracy, not softmax/LayerNorm end-to-end.
- Not synthesis/STA/CDC/board, not 300/600 MHz, not a bypass of the PS hard DDR
  controller. The logical DDR is an AXI BFM.
- Not a mixed-engine concurrent run; no SEQ+MAT/VEC/LAY overlap was executed.

## 7. Reproduction

```bash
cd /home/yang/Desktop/项目/v023_repair/ds_integration_audit
bash scripts/pin_sources.sh            # refresh PINNED_SHA256.txt manually only
bash scripts/run_smoke.sh              # 14 stages, timeouts per simulator
```

Separate checks:

```bash
python3 scripts/audit_interfaces.py
python3 scripts/audit_graph_relocation.py
python3 scripts/audit_dependencies.py
python3 scripts/verify_graph_chain.py
cat analysis/interface_audit.json
cat analysis/graph_relocation_audit.json
cat analysis/dependency_search.json
```

Exit codes are recorded in `logs/smoke_results.csv`; the audit script exits 0
because the covered tests pass, while `result.json` carries
`"verdict": "blocked"`.

## 8. Files

- `INTERFACE.md` — handoff contract to `ds_integration`
- `result.json` — machine-readable verdict, evidence, blockers, SHA
- `PINNED_SHA256.txt` — read-only source hashes; `SELF_SHA256.txt` — this audit's scripts/reports
- `analysis/interface_audit.json`, `analysis/graph_relocation_audit.json`,
  `analysis/dependency_search.json`, `analysis/graph_chain_verify.json`,
  `analysis/filelist_integrated.f`
- `scripts/run_smoke.sh`, `scripts/audit_interfaces.py`,
  `scripts/audit_graph_relocation.py`, `scripts/audit_dependencies.py`,
  `scripts/axi128_audit_bfm.sv`, `scripts/tb_dma_audit.sv`,
  `scripts/audit_dma_dut_*.sv`, `scripts/verify_graph_chain.py`
- `logs/` — per-stage logs and `smoke_results.csv`, `EXIT_CODES.txt`
- `rtl/wc_graph_top_audit.sv`, `tb/tb_graph_real_audit.sv` — copied graph top/TB with the candidate vector wrapper and local-golden output dump
- `copies/vector`, `copies/layout` — isolated rerun copies (no writes to the
  worker directories)
