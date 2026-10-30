#!/usr/bin/env bash
# Reproduce the ds_numeric_adversarial audit.  Exit 0 only if result.json says
# overall_pass=true; the current audit is expected to exit 1 (blocking findings).
set -u
cd "$(dirname "$0")"
ROOT="$PWD"
P=/home/yang/Desktop/项目/v023_repair
FMA=$P/gemini_fma_repair/candidate
APX=$P/gemini_approx_repair/candidate/rtl

echo "[1/6] generate vectors"
python3 scripts/gen_vectors.py || exit 2
echo "[2/6] audit actual ASR model"
python3 scripts/audit_model.py || exit 2
echo "[3/6] C reference cross-check"
python3 scripts/crosscheck_c.py || exit 2
echo "[4/6] old baseline"
python3 scripts/run_suite.py --label old_final || true
echo "[5/6] repaired FMA candidate"
python3 scripts/run_suite.py --label fma_repair \
  --i48 "$FMA/epilogue_i48_to_f32.sv" \
  --fma "$FMA/epilogue_fma_stage.sv" \
  --fma-pipe "$FMA/fp32_fma_pipe.sv" \
  --asr-fma "$FMA/asr_fma_ip.sv" \
  --f32i16 "$FMA/epilogue_f32_to_i16.sv" \
  --relu "$FMA/epilogue_relu.sv" \
  --lane "$FMA/epilogue_lane.sv" \
  --stream "$FMA/epilogue_stream_engine_v023.sv" \
  --only fma || true
echo "[6/8] repaired FMA candidate: BP1 / flush / stream"
python3 scripts/run_suite.py --label fma_repair_bp1 \
  --i48 "$FMA/epilogue_i48_to_f32.sv" --fma "$FMA/epilogue_fma_stage.sv" \
  --fma-pipe "$FMA/fp32_fma_pipe.sv" --f32i16 "$FMA/epilogue_f32_to_i16.sv" \
  --relu "$FMA/epilogue_relu.sv" --lane "$FMA/epilogue_lane.sv" \
  --stream "$FMA/epilogue_stream_engine_v023.sv" --only fma --bp 1 || true
python3 scripts/run_suite.py --label fma_repair_flush2 \
  --i48 "$FMA/epilogue_i48_to_f32.sv" --fma "$FMA/epilogue_fma_stage.sv" \
  --fma-pipe "$FMA/fp32_fma_pipe.sv" --f32i16 "$FMA/epilogue_f32_to_i16.sv" \
  --relu "$FMA/epilogue_relu.sv" --lane "$FMA/epilogue_lane.sv" \
  --stream "$FMA/epilogue_stream_engine_v023.sv" --only flush || true
python3 scripts/run_suite.py --label fma_repair_stream2 \
  --i48 "$FMA/epilogue_i48_to_f32.sv" --fma "$FMA/epilogue_fma_stage.sv" \
  --fma-pipe "$FMA/fp32_fma_pipe.sv" --f32i16 "$FMA/epilogue_f32_to_i16.sv" \
  --relu "$FMA/epilogue_relu.sv" --lane "$FMA/epilogue_lane.sv" \
  --stream "$FMA/epilogue_stream_engine_v023.sv" --only stream || true
python3 scripts/run_suite.py --label fma_repair_stream_bp1 \
  --i48 "$FMA/epilogue_i48_to_f32.sv" --fma "$FMA/epilogue_fma_stage.sv" \
  --fma-pipe "$FMA/fp32_fma_pipe.sv" --f32i16 "$FMA/epilogue_f32_to_i16.sv" \
  --relu "$FMA/epilogue_relu.sv" --lane "$FMA/epilogue_lane.sv" \
  --stream "$FMA/epilogue_stream_engine_v023.sv" --only stream --bp 1 || true
python3 scripts/run_suite.py --label fma_repair_stream_bp2b \
  --i48 "$FMA/epilogue_i48_to_f32.sv" --fma "$FMA/epilogue_fma_stage.sv" \
  --fma-pipe "$FMA/fp32_fma_pipe.sv" --f32i16 "$FMA/epilogue_f32_to_i16.sv" \
  --relu "$FMA/epilogue_relu.sv" --lane "$FMA/epilogue_lane.sv" \
  --stream "$FMA/epilogue_stream_engine_v023.sv" --only stream --bp 2 || true
echo "[7/8] repaired approx candidate"
python3 scripts/run_suite.py --label approx_repair2 \
  --approx "$APX/approx_div_sqrt.sv" --recip "$APX/approx_recip_lut.sv" \
  --rsqrt "$APX/approx_rsqrt_lut.sv" --approx-has-flush --only approx || true
python3 scripts/run_suite.py --label approx_repair_bp1 \
  --approx "$APX/approx_div_sqrt.sv" --recip "$APX/approx_recip_lut.sv" \
  --rsqrt "$APX/approx_rsqrt_lut.sv" --approx-has-flush --only approx --bp 1 || true
echo "[8/8] consolidate"
python3 scripts/consolidate.py
python3 - <<'PY'
import json,sys
r=json.load(open("result.json"))
print("overall_pass=",r["overall_pass"])
print("blocking=",len(r["blocking_findings"]))
sys.exit(0 if r["overall_pass"] else 1)
PY
