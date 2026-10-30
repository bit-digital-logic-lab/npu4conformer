#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"

echo "======================================================================"
echo " Starting Comprehensive Verification Suite for gemini_approx_round2"
echo " Timestamp: $(date --iso-8601=seconds)"
echo " Working Dir: ${SCRIPT_DIR}"
echo "======================================================================"

# 1. Parameter Assertion & Rejection Tests
echo ""
echo "[PHASE 1/5] Running Parameter Assertion & Rejection Suite..."
python3 tests/test_parameter_assertions.py
echo ">> Phase 1 Complete (rc=0)."

# 2. Hardware Protocol, Latency, II, Flush & Backpressure Tests
echo ""
echo "[PHASE 2/5] Running Hardware Protocol & Pipeline Performance RTL Simulation..."
iverilog -g2012 -o tests/tb_protocol_perf.vvp \
  tests/tb_protocol_perf.sv \
  rtl/approx_div_sqrt.sv \
  rtl/approx_recip_lut.sv \
  rtl/approx_rsqrt_lut.sv
vvp tests/tb_protocol_perf.vvp
echo ">> Phase 2 Complete (rc=0)."

# 3. Numerical Error & Dynamic Backpressure Comprehensive Testsuite
echo ""
echo "[PHASE 3/5] Running Numerical & Backpressure Suite (4,131 vectors)..."
python3 tests/test_approx_suite.py
echo ">> Phase 3 Complete (rc=0)."

# 4. Independent Adversarial Black-Box Testsuite (15,168 vectors)
echo ""
echo "[PHASE 4/5] Running Independent ds_numeric_adversarial 15,168-Vector Verification..."
python3 scripts/run_numeric_adversarial_15168.py
echo ">> Phase 4 Complete (rc=0)."

# 5. Interface Co-Simulation & ds_vector Compatibility Check (Read-Only)
echo ""
echo "[PHASE 5/5] Verifying Read-Only Integration Compatibility with ds_vector..."
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

mkdir -p /tmp/compat_fixtures/div_1001 /tmp/compat_fixtures/sqrt_1001
cp /home/yang/Desktop/项目/v023_repair/ds_vector/fixtures/regression/div_1001/* /tmp/compat_fixtures/div_1001/
cp /home/yang/Desktop/项目/v023_repair/ds_vector/fixtures/regression/sqrt_1001/* /tmp/compat_fixtures/sqrt_1001/

vvp /tmp/test_ds_vector_compat.vvp +folder=/tmp/compat_fixtures/div_1001 +nbytes=4004 +mode=0 +expect_fault=0 +expect_no_dma=0
vvp /tmp/test_ds_vector_compat.vvp +folder=/tmp/compat_fixtures/sqrt_1001 +nbytes=4004 +mode=0 +expect_fault=0 +expect_no_dma=0
echo ">> ds_vector candidate successfully co-simulated with updated approx_div_sqrt."
echo ">> Phase 5 Complete (rc=0)."

echo ""
echo "======================================================================"
echo " ALL 5 PHASES PASSED WITH ZERO ERRORS (EXIT CODE 0)"
echo "======================================================================"
