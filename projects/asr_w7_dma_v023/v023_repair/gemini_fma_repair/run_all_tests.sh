#!/usr/bin/env bash
# run_all_tests.sh
# Regression test runner for gemini_fma_repair.
# Executes all test suites strictly sequentially (-j1).
# Every simulation runs with a diagnosable watchdog.

set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
cd "$DIR"

echo "================================================================="
echo "  GEMINI FMA REPAIR: FULL REGRESSION TEST SUITE (-j1)"
echo "  Timestamp: $(date -Iseconds)"
echo "================================================================="

mkdir -p "$DIR/sim"

# 1. Independent Python Reference Model Test
echo ""
echo "[SUITE 1/6] Running Independent Trusted Python Reference Verification..."
python3 "$DIR/reference/fma_reference.py"
echo "[SUITE 1/6] PASSED."

# 2. Pipelined FP32 FMA Core Unit Test
echo ""
echo "[SUITE 2/6] Compiling and running Pipelined FP32 FMA Unit Test..."
iverilog -g2012 -o "$DIR/sim/tb_fp32_fma_pipe.vvp" \
  "$DIR/candidate/fp32_fma_pipe.sv" \
  "$DIR/tests/tb_fp32_fma_pipe.sv"
vvp "$DIR/sim/tb_fp32_fma_pipe.vvp"
echo "[SUITE 2/6] PASSED."

# 3. Primary Acceptance Counterexample Probe
echo ""
echo "[SUITE 3/6] Compiling and running Primary Acceptance Counterexample Probe..."
iverilog -g2012 -o "$DIR/sim/tb_probe_acceptance.vvp" \
  "$DIR/candidate/fp32_fma_pipe.sv" \
  "$DIR/candidate/epilogue_fma_stage.sv" \
  "$DIR/tests/tb_probe_acceptance.sv"
vvp "$DIR/sim/tb_probe_acceptance.vvp"
echo "[SUITE 3/6] PASSED."

# 4. Official Vendor FMA Fixture (1001 Vectors)
echo ""
echo "[SUITE 4/6] Compiling and running Official Vendor FMA Fixture (1001 Vectors)..."
iverilog -g2012 -o "$DIR/sim/tb_asr_fma_fixture.vvp" \
  "$DIR/candidate/fp32_fma_pipe.sv" \
  "$DIR/candidate/asr_fma_ip.sv" \
  "$DIR/tests/tb_asr_fma_fixture.sv"
vvp "$DIR/sim/tb_asr_fma_fixture.vvp"
echo "[SUITE 4/6] PASSED."

# 5. Epilogue Lane Full Integration Test
echo ""
echo "[SUITE 5/6] Compiling and running Epilogue Lane Full Integration Test..."
iverilog -g2012 -o "$DIR/sim/tb_epilogue_lane.vvp" \
  "$DIR/candidate/epilogue_i48_to_f32.sv" \
  "$DIR/candidate/fp32_fma_pipe.sv" \
  "$DIR/candidate/epilogue_fma_stage.sv" \
  "$DIR/candidate/epilogue_relu.sv" \
  "$DIR/candidate/epilogue_f32_to_i16.sv" \
  "$DIR/candidate/epilogue_lane.sv" \
  "$DIR/tests/tb_epilogue_lane.sv"
vvp "$DIR/sim/tb_epilogue_lane.vvp"
echo "[SUITE 5/6] PASSED."

# 6. Epilogue Stream Engine End-to-End Stress Test
echo ""
echo "[SUITE 6/6] Running Epilogue Stream Engine End-to-End Stress Test..."
python3 "$DIR/tests/run_epilogue_stream_stress.py"
echo "[SUITE 6/6] PASSED."

echo ""
echo "================================================================="
echo "  ALL 6 SUITES PASSED CLEANLY (exit code 0)"
echo "================================================================="
exit 0
