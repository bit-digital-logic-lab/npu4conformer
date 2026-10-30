# Measured performance (logic simulation only)

These are **cycle counts of the named small fixtures**. They are not
whole-model seconds, not board time, and not additive. No frequency is
claimed. A cycle is one `clk` in the Icarus logic model (single clock).

## 1. Unified small graph

| Path | Cycles | Terminal state | Traffic evidence |
|---|---:|---|---|
| fused MAT + per-channel + DIV + SQRT + A16 copy | 18,724 | `done=1,fault=0,error=0`, drained | `FUSION used=1`, C48 DDR = 0 B, A16 = 2,048 B; scale/bias table hit |
| explicit fallback (2 descriptors, untagged consumer) | 16,973 | `done=1,fault=0,error=0`, drained | `used=0`; legacy C48; I16 512/512 |
| multi-consumer fallback | 19,749 | `done=1,fault=0,error=0`, drained | `used=0` |
| MATF without `FUSION_ALLOW` | 383 | `fault=1,error=0x04` | no fused execution |
| fused A16 write B held | 30,720 | `fault=1,error=0x0E`, isolation, `requires_reset=1`, `b_pending=8`, `quiesced=0` | no new AR/AW/W after isolation |

The fused path's 18,724 cycles include the whole small graph (matrix + fused
epilogue + vector DIV/SQRT + layout copy), not just the matrix engine. Do not
compare it one-to-one with a matrix-only benchmark.

## 2. Numeric error in the same graph

| Op | Worst relative error | Frozen tolerance | Bad points |
|---|---:|---:|---:|
| DIV (op3) | 9.102e-4 | 1.2e-3 | 0 |
| SQRT (op4) | 5.089e-6 | 6.0e-6 | 0 |

DIV/SQRT are the approximate core. Exactness is not claimed. The FMA is
single-rounding: 64/64 directed vectors match the single-rounding gold and
64/64 differ from `mul`+`add`.

## 3. Module-level measurements from the independent review

These are cited for context only; they are **not merged** into the unified top
(see `assets_manifest/UNSELECTED.md`).

| Item | Measurement | Scope |
|---|---|---|
| matrix W reuse | read 18,432→15,360 B; W 6,144→3,072 B; cycles 7,612→7,236 | M64/N32/K96 cluster, same fixture/BFM/gold |
| write coalescer native | 64 cseg → 24 posted requests; 384 beats; 6,144 B | storage cluster; native path only |
| layout wide copy | official mode-0 0.176× cycles | layout worker tree, not unified plan |
| graph lookahead | 23,660 vs 23,774 cycles = 114 cycles (0.48%) | worker integrated copy, default off |
| fusion dual-bank | n64/B3000: 7,857 vs 9,165 cycles | cluster; broadcast params only |
| FMA 7-stage | 8,734/8,734 bit-exact, II=1, latency 7 | repaired `3c1114bc…` core |

The 59.8% "control overhead" figure is **not** used; the independent exclusive
ledger is 435 cycles / 1.83%.

## 4. Honest limits

- No synthesis, no STA, no Fmax, no gate count, no power.
- No board DDR/HP timing; the BFM is a logic model.
- No whole-model 512-dim ASR latency or seconds; the old ~150 s is an old
  platform number and cannot be transferred.
- No WER/CER; the old KWT accuracy range does not apply.
