# V5: original INT16-QDQ model, ONNX-compatible FPGA arithmetic

Status 2026-09-23: **original case_0000 accepted on physical XC7A35T**.
Full Encoder -> Decoder completed in 1947.081 s (32 min 27 s). Encoder memory
is bit-exact to the original golden; all 5,000 Decoder outputs meet the original
unchanged tolerance. Independent final checking also passes. This establishes
one case, not all inputs. See `RESULT_20260923_zh.md` and
`reports/case_0000_v5_b001_full_chain_001/result.json`.

## Frozen predecessor

`../releases/v4_20260922_board004/FREEZE_MANIFEST.json` records 1,712
hash-verified files, including the V4 Ethernet implementation, board_004
bitstream, reports and frozen V2 dependencies. V4 has a working Ethernet link
and passing isolated Decoder, but its complete Encoder does NOT meet the
original golden tolerance. It is preserved as a reproducible, non-accepted
full-model baseline. No Flash programming is part of this work.

## What changes and what does not

- Original ONNX files, INT16 weights, Q/DQ scales, shapes and golden vectors are
  unchanged. The original tolerance is `abs(error) <= .001 + .001*abs(golden)`
  for every float element, with exact integers, matching shapes/dtypes and
  finite values. No tolerances were fitted or relaxed.
- ONNX QDQ graphs perform floating-point Conv/MatMul after DequantizeLinear.
  V5 follows that behavior using an FPGA FP32 fused multiply-add datapath.
  This is **not a claim of exclusively INT16 arithmetic**: INT16 quantization
  remains, while the intervening arithmetic matches the graph's float nodes.
- MatMul/Conv use original accumulation order and K-block boundaries;
  LayerNorm uses FP64-equivalent exact QDQ mean, eight FMA variance lanes and
  fused affine output. Sigmoid/Softmax use the pinned ORT implementation order.
- SRAM is 32,768 words (128 KiB). Matrix tiles, nonlinear polynomial stages
  when issued as resident commands, and partial sums execute on FPGA.
  Host memory stores tensors between graph nodes. No CPU numeric fallback.
- Encoder uses V5. Decoder retains previously validated V2 numerical commands
  in the same engine, receiving the **actual V5 Encoder output** in full-chain
  acceptance. Golden Encoder memory is never injected into full-chain runs.
- Network framing remains ASR4 for transport compatibility. New numerical
  capability command 0x4f returns ASR5/version5; JTAG USR_ACCESS is A5160005.
  Legacy top/bit filenames retain `v4` to minimize incidental build changes;
  only the V5 directory and A5160005 marker identify this new implementation.

## Numerical command additions

| Opcode | Meaning | Payload |
|---|---|---|
| 0x46 | FP32 FMA GEMM block, separately add prior C | 7 little-endian u16: A, BT, D, M, N, K, accumulate |
| 0x47 | FP32 vector FMA with exact/in-place vectors or broadcast scalars | 5 u16: A, B, C, D, count; u8 broadcast mask |
| 0x48 | Exact 512-element QDQ mean rounded to FP32 | 3 u16: A, D, 512 |
| 0x4f | V5 capability | no payload |
| 0x43/op16 | Scale FP32 by signed-i32 power of two, FTZ | existing VEC layout |

Mean rejects nonfinite/subnormal inputs, exponent span above 20, or unrepresentable
result. For its accepted domain, 512 aligned 24-bit significands require at most
53 bits; every FP64 accumulation is exact. Hardware performs the exact signed
sum and round-to-nearest-even. This contract is verified against actual QDQ
LayerNorm inputs, not assumed for arbitrary float reductions.

## Evidence hierarchy

1. `reports/cpu_native_001`: offline whole Encoder arithmetic, bit-exact
   original golden. Not FPGA evidence.
2. `reports/offline_host_pipeline_001`: the actual physical host scheduler
   driven by an explicitly offline emulated command engine, bit-exact original
   golden. Not FPGA evidence; no deployment script imports this emulator.
3. `build/numeric_sim_001/report.json`: 262 command-level XSIM tests with the
   actual generated AMD FMA IP, including cancellation, round-to-nearest,
   broadcast/alias checks, K-block accumulation and QDQ mean. All pass.
4. `reports/board_001_numeric_smoke_001/result.json`: physical matrix, FMA,
   LayerNorm, Sigmoid, Softmax, BatchNorm tests pass (explicit FTZ edge test).
5. `reports/board_001_sram_smoke_001.json`: 20 full SRAM round trips pass.
6. `reports/case_0000_v5_b001_full_chain_001/result.json`: original physical
   full-chain acceptance passes, original hashes unchanged, clean session.
7. `reports/case_0000_v5_independent_final_check.json`: independent scalar
   comparison with the original expected.npz passes; Decoder is bit-exact to
   the historical UART Decoder-only output.
8. `reports/b001_checkpoint_complete_encoder_001/diagnostic_report.json`:
   93 physical Encoder checkpoint tensors compared with the original ORT graph;
   92 bit-exact, one Softmax tensor differs only by <=1.028e-38 (FTZ). All
   downstream saved tensors and final Encoder outputs are bit-exact.

Official reference source is pinned to the installed ORT build commit f2c39fe;
URLs and SHA256 are recorded in `reference/ort_f2c39fe/SOURCE_MANIFEST.json`.

## Why the UART version appeared successful

The original golden UART pass was **Decoder-only**, using the user's golden
Encoder memory as input. It therefore established that Decoder at that input
met tolerance, not that the FPGA Encoder matched ONNX. V4's Decoder outputs
are bit-exact to that UART run, but its full Encoder fails 2,220 of 15,872
elements. Independent original-ORT graph-tail testing shows first-Conv
rounding differences can propagate through later quantization boundaries.
The shared old numerical path was therefore already at risk; changing UART
to Ethernet exposed an unverified scope, not evidence that Ethernet corrupted
the numerical results. Historical generated smoke references verified basic
arithmetic/transport only and cannot substitute for original-model acceptance.

## Reproduction

Use Python environment `D:/app/ananconda/envs/asronnx312_int16/python.exe`.
`scripts/run_golden_ethernet.py --scope full_chain --validate-only` is read-only.
Hardware execution additionally requires `--allow-hardware`, a fresh `--out`
under this directory's reports, and `--bitstream` pointing to the deployed
artifact. Its report records original source hashes and prohibits fallback.

The accepted release directory is an immutable archive, not a relocatable run
directory. To reproduce, restore the archived files to the original `asr/v5`
layout and the embedded dependency to `asr/releases/v2_20260922_pre_golden`,
after checking hashes and preserving any newer working copy. Original ONNX and
golden files remain at their recorded paths; they were never rewritten/copied
over. Programming is volatile JTAG only, so a power cycle requires reloading
the accepted bitstream. Do not reprogram while another inference is active.
