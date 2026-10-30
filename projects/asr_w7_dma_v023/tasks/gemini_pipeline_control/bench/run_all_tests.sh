#!/bin/bash
set -euo pipefail

echo "================================================================="
echo "  Gemini Pipeline Control - Complete Verification Suite"
echo "  Target Device: AMD Xilinx Zynq UltraScale+ (xczu15eg-ffvb1156-2-I)"
echo "================================================================="

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$DIR"

echo ""
echo "=== Test 1: Skid Buffer Random Backpressure (5,000 beats) ==="
iverilog -g2012 -Wall -s tb_skid_backpressure -o bench/tb_skid_backpressure.vvp \
    candidate/skid_buffer.sv bench/tb_skid_backpressure.sv
vvp bench/tb_skid_backpressure.vvp | tee bench/test1_skid.log

echo ""
echo "=== Test 2: Latency Sweep (LATENCY = 3, 4, 5, 6, 8 across 4 quadrants) ==="
iverilog -g2012 -Wall -s tb_pipeline_latency_sweep -o bench/tb_pipeline_latency_sweep.vvp \
    candidate/skid_buffer.sv \
    candidate/pe_delay_stub.sv \
    candidate/block_engine_pipeline_ctrl_v023.sv \
    bench/storage_engine_bfm.sv \
    bench/tb_pipeline_latency_sweep.sv \
    /home/yang/Desktop/项目/work/rtl/c_cache_banked4.sv \
    /home/yang/Desktop/项目/work/rtl/operand_banks_v020.sv \
    /home/yang/Desktop/项目/work/rtl/block_address_v020.sv \
    /home/yang/Desktop/项目/work/rtl/pe_direct_v020.sv \
    /home/yang/Desktop/项目/work/rtl/array16_direct_v020.sv \
    /home/yang/Desktop/项目/tasks/ds_pe_pipeline/candidate/pe_w7_c48_cfg.sv \
    /home/yang/Desktop/项目/tasks/ds_pe_pipeline/candidate/array16_w7_c48_cfg.sv
vvp bench/tb_pipeline_latency_sweep.vvp | tee bench/test2_latency_sweep.log
python3 bench/verify_golden.py | tee -a bench/test2_latency_sweep.log

echo ""
echo "=== Test 3: Real Array Integration & Cross-K Accumulation (M=32, N=32, K=64) ==="
iverilog -g2012 -Wall -s tb_full_array_integration -o bench/tb_full_array_integration.vvp \
    candidate/skid_buffer.sv \
    candidate/pe_delay_stub.sv \
    candidate/block_engine_pipeline_ctrl_v023.sv \
    bench/storage_engine_bfm.sv \
    bench/tb_full_array_integration.sv \
    /home/yang/Desktop/项目/work/rtl/c_cache_banked4.sv \
    /home/yang/Desktop/项目/work/rtl/operand_banks_v020.sv \
    /home/yang/Desktop/项目/work/rtl/block_address_v020.sv \
    /home/yang/Desktop/项目/work/rtl/pe_direct_v020.sv \
    /home/yang/Desktop/项目/work/rtl/array16_direct_v020.sv \
    /home/yang/Desktop/项目/tasks/ds_pe_pipeline/candidate/pe_w7_c48_cfg.sv \
    /home/yang/Desktop/项目/tasks/ds_pe_pipeline/candidate/array16_w7_c48_cfg.sv
vvp bench/tb_full_array_integration.vvp | tee bench/test3_full_array.log
python3 bench/verify_real_array_golden.py | tee -a bench/test3_full_array.log

echo ""
echo "=== Test 4: Double-Buffer Ping-Pong (SLOTS=2) & Flush (M=32, N=64, K=32) ==="
iverilog -g2012 -Wall -s tb_double_buffer -o bench/tb_double_buffer.vvp \
    candidate/skid_buffer.sv \
    candidate/pe_delay_stub.sv \
    candidate/block_engine_pipeline_ctrl_v023.sv \
    bench/storage_engine_bfm.sv \
    bench/tb_double_buffer.sv \
    /home/yang/Desktop/项目/work/rtl/c_cache_banked4.sv \
    /home/yang/Desktop/项目/work/rtl/operand_banks_v020.sv \
    /home/yang/Desktop/项目/work/rtl/block_address_v020.sv \
    /home/yang/Desktop/项目/work/rtl/pe_direct_v020.sv \
    /home/yang/Desktop/项目/work/rtl/array16_direct_v020.sv \
    /home/yang/Desktop/项目/tasks/ds_pe_pipeline/candidate/pe_w7_c48_cfg.sv \
    /home/yang/Desktop/项目/tasks/ds_pe_pipeline/candidate/array16_w7_c48_cfg.sv
vvp bench/tb_double_buffer.vvp | tee bench/test4_double_buffer.log
python3 bench/verify_double_buffer_golden.py | tee -a bench/test4_double_buffer.log

echo ""
echo "================================================================="
echo "  ALL 4 VERIFICATION SUITES PASSED 100% BIT-EXACT!"
echo "================================================================="
