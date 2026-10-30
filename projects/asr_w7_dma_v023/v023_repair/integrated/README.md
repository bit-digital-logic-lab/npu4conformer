# V0.23 integrated candidate (v023_repair/integrated)

Status: **runnable exact-path candidate; final V0.23 integration is NOT accepted.**
This directory is the final integration workspace. It does not modify `work/`,
the sealed ZIP, older task candidates, or any worker directory.

## One entry point

```bash
cd /home/yang/Desktop/项目/v023_repair/integrated
bash scripts/run_all.sh
```

The script generates the deterministic fixture/plan/golden, compiles the unique
integrated filelist, runs the autonomous superplan chain, runs two negative
inputs, compiles/runs the exact sealed-RTL baseline chain, builds/runs the V020
matrix baseline (same M32/N32/K32 fixture), compares final outputs to the
independent golden, and regenerates the project-skill traffic ledger and module
activity waveform. Logs go to `logs/`, build to `build/`, traces to `traces/`.

## What this candidate actually runs

A single CSR `START` submits one preloaded WCPG v2 superplan. The PL controller
then fetches nodes and dispatches real engines; the host does not issue per-node
or per-block DMA. The tested chain is:

```
IN (param A16/W7) -> LAY copy A -> LAY copy W -> MAT (V022 queue descriptor)
  -> VEC I48->F32 -> VEC MUL scale -> VEC ADD bias -> VEC F32->I16
  -> LAY final copy
```

`PIPE_STAGES=4`, exact DIV/SQRT (approx disabled), 1024 matrix output elements
converted to 1024 I16 values. The final 1024 I16 values match an independent
numpy reference bit-for-bit.

Measured result:

| item | result |
|---|---|
| integrated final output | 1024/1024 I16 match independent golden |
| one START / one DONE+IRQ | yes |
| integrated wall (logic cycles) | 23,819 |
| matrix child | 1,880 task cycles, 272 compute cycles, no fault |
| AXI R/W | 29,248 B read / 25,600 B written; ledger-minus-interval = 0 |
| tag errors | 0 |
| negative matrix queue magic | terminal fault 0x03, done=1, no hang |
| negative vector op19 | terminal fault 0x07, done=1, layout prep 3,072 B, zero vector data writes |

## Why final acceptance is still blocked

The four new gate tasks completed with these independent verdicts:

- `gemini_fma_repair`: own tests pass, but `ds_numeric_adversarial` still finds
  137/8,734 normal-input FMA mismatches (RNE tie-even and extreme exponent
  alignment), and the stream engine has A16 tag, packed backpressure, parameter
  preload, and in-flight reconfiguration defects. **Not integrated.**
- `gemini_approx_repair`: structure is honest (single 5-cycle II=1 tier), but
  DIV/RSQRT factor-2 edge errors and RSQRT(-0) sign remain. **Not integrated;
  the exact DIV/SQRT path is the default.**
- `ds_numeric_adversarial`: `overall_pass=false`.
- `ds_integration_audit`: `verdict=blocked` (sealed payload not re-lowered,
  698 tensors alias the sealed scratch, full 591 tensor DAG/executor absent,
  no child abort/drain on matrix/vector/layout, no full mixed-engine arbitration).

Therefore this is a **candidate**, not a final V0.23 acceptance. FMA/op17 uses
`fma_forbidden_stub.sv` (compile-only; it aborts if invoked). No approximate
module is in the default filelist; see `optional/README.md`.

## Layout

- `rtl/` — selected candidates plus integration adapters (`v023_*`).
- `tb/` — autonomous superplan TB, exact baseline chain TB, shared sparse AXI BFM.
- `filelist_integrated.f` — unique default filelist (one `ddr_layout_engine`,
  one `asr_fma_ip` stub, no approx core).
- `filelist_baseline.f` — sealed exact baseline chain.
- `fixtures/` — deterministic matrix fixture, plan, memory images, gold.
- `logs/`, `traces/`, `reports/` — raw evidence, JSONL trace, skill reports.
- `REPORT.md`, `INTERFACE.md`, `result.json` — details and machine verdict.
- `optional/` — blocked candidates, not compiled by the default entry point.

Scope is logic simulation only: no synthesis, Vivado, STA, board, VNC or push.
Single clock; no CDC/xpm_fifo_async assumption or test.
