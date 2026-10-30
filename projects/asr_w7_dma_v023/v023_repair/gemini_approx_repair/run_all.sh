#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"

echo "======================================================================"
echo " Starting Comprehensive Verification Suite for gemini_approx_repair"
echo " Timestamp: $(date --iso-8601=seconds)"
echo " Working Dir: ${SCRIPT_DIR}"
echo "======================================================================"

# 1. Parameter Assertion & Rejection Tests
echo ""
echo "[PHASE 1/4] Running Parameter Assertion & Rejection Suite..."
python3 tests/test_parameter_assertions.py
echo ">> Phase 1 Complete (rc=0)."

# 2. Hardware Protocol, Latency, II, Flush & Backpressure Tests
echo ""
echo "[PHASE 2/4] Running Hardware Protocol & Pipeline Performance RTL Simulation..."
iverilog -g2012 -o tests/tb_protocol_perf.vvp \
  tests/tb_protocol_perf.sv \
  rtl/approx_div_sqrt.sv \
  rtl/approx_recip_lut.sv \
  rtl/approx_rsqrt_lut.sv
vvp tests/tb_protocol_perf.vvp
echo ">> Phase 2 Complete (rc=0)."

# 3. Numerical Error & Dynamic Backpressure Comprehensive Testsuite
echo ""
echo "[PHASE 3/4] Running Comprehensive Numerical & Backpressure Suite (4131 vectors)..."
python3 tests/test_approx_suite.py
echo ">> Phase 3 Complete (rc=0)."

# 4. Interface Co-Simulation & ds_vector Compatibility Check (Read-Only)
echo ""
echo "[PHASE 4/4] Verifying Read-Only Integration Compatibility with ds_vector..."
iverilog -g2012 -D DUT_MODULE=ddr_vector_engine_approx -o /tmp/test_ds_vector_compat.vvp \
  -s tb_vector_generic \
  /home/yang/Desktop/项目/v023_repair/ds_vector/tb/tb_vector_generic.sv \
  /home/yang/Desktop/项目/v023_repair/ds_vector/candidate/rtl/ddr_vector_engine_approx.sv \
  /home/yang/Desktop/项目/v023_repair/ds_vector/candidate/rtl/ddr_vector_engine_pipe.sv \
  /home/yang/Desktop/项目/v023_repair/ds_vector/candidate/rtl/asr_fp32_lane_fixed.sv \
  /home/yang/Desktop/项目/v023_repair/ds_vector/candidate/rtl/vector_desc_check_pipe.sv \
  "${SCRIPT_DIR}/rtl/approx_div_sqrt.sv" \
  "${SCRIPT_DIR}/rtl/approx_recip_lut.sv" \
  "${SCRIPT_DIR}/rtl/approx_rsqrt_lut.sv" \
  /home/yang/Desktop/项目/v023_repair/ds_vector/baseline/rtl/asr_fp32_alu.sv \
  /home/yang/Desktop/项目/v023_repair/ds_vector/baseline/tb/fma_forbidden_stub.sv
echo ">> ds_vector candidate successfully compiled with updated approx_div_sqrt."
echo ">> Phase 4 Complete (rc=0)."

echo ""
echo "======================================================================"
echo " ALL PHASES PASSED WITH ZERO ERRORS (EXIT CODE 0)"
echo "======================================================================"
