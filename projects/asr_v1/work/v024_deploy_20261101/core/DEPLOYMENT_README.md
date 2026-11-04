# V0.24 / AXU15EGB bounded core preparation

This directory is an isolated deployment candidate. The original exported project is unchanged.
Board confirmed by the user: AXU15EGB. Target part: xczu15eg-ffvb1156-2-i.

## Configuration and scope

- Genuine V0.24 `v024_unified_top` plus its original arithmetic, matrix, graph, DMA and layout RTL.
- Both unified and legacy regression top now explicitly pass `MAX_NODES=128` to the graph controller.
- WCPG v2 node records retain the original 1024-bit dependency-mask ABI. Counts above 128 and dependencies on a non-earlier node are rejected before execution.
- The fixture sets FLAG_SYNTH_ORDER, but wc_graph_ctrl does not enforce serialization from that bit. last_node reports the actual last completion; 6 is observed in XSim, not guaranteed for arbitrary DDR latency. Board acceptance should require completed=7 and the numerical/status/drain checks without assuming this flag serializes execution.
- This is a bounded small-graph configuration. It does not support submission of the full 591-node ASR graph, and no decomposition/executor is supplied here.
- The exported `fma_forbidden_stub.sv` was not imported. `asr_fma_ip` is generated from AMD Floating Point Operator 7.1 with FMA/Add, Single, NonBlocking, ARESETn, Full_Usage, and 12-cycle latency, following the repository's existing `generate_fma_ip.tcl` recipe.
- All top-level inputs/outputs remain live in OOC synthesis. There is no constant-driven board wrapper that could optimize away the core.
- The OOC clock is a provisional 50 MHz constraint for investigation. It is not a timing-closure or board-frequency claim.

## Inputs and provenance

`SOURCE_IMPORT_SHA256.json` records original source hashes. `reports/RTL_PATCHES.json` records the only production RTL edits (MAX_NODES parameter propagation).

`scripts/sim/gen_v024_graph.py` recreated missing small-graph fixtures. After CRLF-to-LF normalization, all ten input/golden files exactly match the archive's existing `sim/fixtures/REFERENCE_FREEZE.json`; see `reports/FIXTURE_SHA256_VERIFIED.json`.

The four legacy baseline fixture files were copied from the same archive's `projects/asr_w7_dma_v023/v023_repair/ds_closeout_safety/fixtures`. They are baseline compatibility inputs, not a replacement V0.24 implementation.

`inputs/MEMORY_MAP.json` describes binary and 128-bit RAM images for the fused seven-node graph:

- `inputs/fused_arena64k.bin`: logical 0x04000000, 65536 bytes.
- `inputs/fused_param64k.bin`: logical 0x10000000, 65536 bytes.
- `inputs/fused_pc64.bin`: logical 0x10003000, 256 bytes, also present within the parameter image. Write these 64 values through pc_wr before START.

These are compact images of the original BFM address windows. The BFM flat indices are not physical addresses. A real memory wrapper must decode logical windows and reject unmapped ranges.

## Verification

- `scripts/deploy/synth_core_ooc.tcl`: original 1024-node configuration; observed failure `Synth 8-4556`, nd_dep 1048576 bits exceeds 1000000-bit limit. Log retained in `logs/synth_core_ooc.log`. Its genuine FMA IP generation/synthesis succeeded and is reused.
- `scripts/deploy/synth_core128_ooc.tcl`: preserved single-cycle-hash 128-node build, deliberately stopped before completion. It has no completed utilization/timing result.
- `scripts/deploy/sim_core128_all.tcl`: original eleven regression cases plus valid 128 nodes, rejected 129 nodes, and rejected dependency bit 128.
- `scripts/deploy/check_core128_strict.py`: checks all output lengths, frozen fixture hashes, completion/fault/drain markers, boundary behavior, and the independent numerical judge. `reports/REGRESSION128_STRICT.json` records all 14 passing cases.
- `scripts/deploy/sim_supplement.tcl`: real vendor FMA 64-vector / 12-cycle check and same-XSim 1024-node fused reference comparison.

The preserved single-cycle-hash XSim fused simulation takes 18731 testbench cycles (18474 CSR cycles). The selected iterative implementation is documented below. The historical Icarus run reported 18724; do not combine those simulator timings. No board run is claimed by this directory.

## Reproduction

Run commands with this directory as the working directory. Use the bundled Python with NumPy and Vivado 2025.2.

1. Generate fixtures, then run `scripts/deploy/verify_fixture_freeze.py`.
2. The genuine FMA XCI is `build/project/v024_core.srcs/sources_1/ip/asr_fma_ip/asr_fma_ip.xci`.
3. Run Vivado batch with `scripts/deploy/synth_core128_iterhash_ooc.tcl` for the selected bounded core.
4. Run Vivado batch with `scripts/deploy/sim_core128_all.tcl`, then run `scripts/deploy/check_core128_strict.py`.
5. Run Vivado batch with `scripts/deploy/sim_supplement.tcl` for supplementary evidence.

The source-import and configuration helper scripts describe the preparation performed, but are not intended to be rerun over a completed build indiscriminately.


## Selected implementation update

After the 17-case candidate regression and independent source review, the deployment selected the iterative FNV implementation via `filelist_iterhash.f` / `analysis/wc_graph_ctrl_iterhash.sv`. The original RTL is retained for provenance. The original single-cycle-hash OOC synthesis was intentionally stopped before completion; no complete utilization or timing result was obtained. This is not evidence of a measured timing failure. See `reports/CORE128_ORIGINAL_ABORTED.json`.

Current synthesis script: `scripts/deploy/synth_core128_iterhash_ooc.tcl`, two worker threads. Expected complete core checkpoint: `build/v024_core128_iterhash_synth.dcp`. Final reports use prefix `reports/core128_iterhash_`. The source manifest is `reports/DEPLOYMENT_ITERHASH_SOURCE_SHA256.json`.

The iterative-hash fused run produced exactly the same 8192 output words. Its measured testbench/CSR cycles are 19061/18804, versus 18731/18474 for the preserved original implementation. The measured increase is 330 cycles. The hash states themselves add 352 cycles; the rest of the AXI-stalled schedule changes by -22 cycles. These are XSim measurements, not board measurements. Timing closure remains unverified until final implementation reports.

## Completed synthesis and deployment blocker (2026-11-01 20:18)

Vivado 2025.2 completed the selected OOC synthesis and all reports. The genuine FMA IP checkpoint was linked automatically. The saved 146188868-byte core checkpoint has **zero black boxes**, SHA256 `b63bb8c4c20bd1aa6e806c6dbe367367d7ee8ba508bb84c0a5a415bb1b913da5`.

The core does **not fit** the confirmed AXU15EGB target. Total CLB LUTs are 513136 of 341280 (150.36%); logic LUTs alone are 481560. DRC reports **UTLZ-1 Error**. Other measured resources are 445750 FFs, 279 DSPs, and 2 BRAM36 tiles. This is a completed synthesis result with a real resource blocker, not deployment completion. Do not downgrade or disable the resource DRC to create a success claim.

At the provisional 50 MHz OOC constraint, estimated internal setup WNS is +5.763 ns, TNS is zero, and hold WHS is +0.013 ns. There are no unclocked registers, unconstrained internal endpoints, combinational loops, or multiple-clock pins. The OOC boundary has 269 inputs and 1466 outputs without interface delay constraints; clock-source placement and actual routed timing are not yet available. Therefore these numbers establish only the constrained internal synthesized estimate, not board timing closure.

The final evidence is in `reports/core128_iterhash_status.txt`, `reports/core128_iterhash_utilization.rpt`, `reports/core128_iterhash_utilization_hier.rpt`, `reports/core128_iterhash_timing_synth.rpt`, and `reports/core128_iterhash_drc_synth.rpt`. Platform implementation and programming remain incomplete; resource optimization is required before a valid board bitstream can be produced.
