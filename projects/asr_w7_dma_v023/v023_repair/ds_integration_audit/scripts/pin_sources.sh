#!/usr/bin/env bash
# Record SHA-256 of every read-only input used by the audit.  Does not modify them.
set -euo pipefail
cd "$(dirname "$0")/.."
out=${1:-PINNED_SHA256.txt}
files=(
  ../ds_graph/rtl/wc_graph_ctrl.sv
  ../ds_graph/rtl/wc_graph_top.sv
  ../ds_vector/candidate/rtl/ddr_vector_engine_pipe.sv
  ../ds_vector/candidate/rtl/ddr_vector_axi_pipe.sv
  ../ds_vector/candidate/rtl/asr_fp32_lane_fixed.sv
  ../ds_vector/candidate/rtl/vector_desc_check_pipe.sv
  ../ds_vector/candidate/rtl/ddr_vector_engine_approx.sv
  ../ds_layout/rtl/ddr_layout_engine_v023_burst.sv
  ../ds_layout/rtl/ddr_layout_engine_v023.sv
  ../ds_matrix/candidate/rtl/matrix_p2_cluster_v2.sv
  ../ds_matrix/candidate/rtl/block_engine_prefetch_v2.sv
  ../ds_matrix/candidate/rtl/block_storage_stream_v2.sv
  ../ds_matrix/candidate/rtl/operand_banks_dual_v2.sv
  ../ds_matrix/candidate/rtl/axi_dma_v020_multi_v2.sv
  ../ds_matrix/candidate/rtl/block_address_v020.sv
  ../ds_matrix/candidate/rtl/array16_w7_c48_cfg.sv
  ../ds_matrix/candidate/rtl/pe_w7_c48_cfg.sv
  ../ds_matrix/candidate/rtl/c_cache_banked4_pipe.sv
  ../ds_control_fixes/candidate/rtl/pl_execution_plan_v023.sv
  ../ds_control_fixes/candidate/rtl/plan_submit_csr_v023.sv
  ../ds_control_fixes/candidate/rtl/ready_scan_banked_v1.sv
  ../ds_control_fixes/candidate/rtl/block_address_v023.sv
  ../ds_control_fixes/candidate/rtl/axi_dma_v023_multi.sv
  ../ds_control_fixes/candidate/rtl/axi_dma_v023_bounded.sv
  ../../work/rtl/axi_dma_v019.sv
  ../../work/rtl/asr_fp32_alu.sv
  ../../work/rtl/u16_divmod.sv
  ../../work/rtl/ddr_layout_axi.sv
  ../../work/rtl/ddr_vector_axi.sv
  ../../work/rtl/ddr_layout_engine.sv
  ../../work/tests/fma_forbidden_stub.sv
  ../ds_graph/tests/fixtures/mem_graph.hex
)
sha256sum "${files[@]}" > "$out"
echo "wrote $out ($(wc -l < "$out") files)"
