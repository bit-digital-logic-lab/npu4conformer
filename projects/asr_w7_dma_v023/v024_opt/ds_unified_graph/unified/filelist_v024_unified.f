// V0.24 unified candidate — unique compile list (single clock logic build).
// Exactly one definition of each module.  The reliable base is the byte-copied
// ds_closeout_safety tree; V0.24 additions are epilogue_*_v024, the fused MAT
// engine/top, and v024_* wrappers.  No optional FMA/approx candidate is
// duplicated: the approximate DIV/SQRT core is included exactly once and only
// the VEC branch uses it.
rtl/fma_forbidden_stub.sv
// ---- base integrated path (reliable closeout_safety snapshot) ----
rtl/axi_dma_v019.sv
rtl/asr_fp32_alu.sv
rtl/u16_divmod.sv
rtl/asr_fp32_lane_fixed.sv
rtl/vector_desc_check_pipe.sv
rtl/ddr_vector_engine_pipe.sv
rtl/v023_vector_axi.sv
rtl/v023_vector_guard.sv
rtl/ddr_layout_engine_v023_burst.sv
rtl/v023_layout_axi.sv
rtl/v023_layout_guard.sv
rtl/block_address_v020.sv
rtl/c_cache_banked4.sv
rtl/c_cache_banked4_pipe.sv
rtl/pe_w7_c48_cfg.sv
rtl/array16_w7_c48_cfg.sv
rtl/operand_banks_dual_v2.sv
rtl/block_storage_stream_v2.sv
rtl/block_engine_prefetch_v2.sv
rtl/axi_dma_v020_multi_v2.sv
rtl/matrix_p2_cluster_v2.sv
rtl/task_queue.sv
rtl/wc_graph_ctrl.sv
rtl/wc_graph_top.sv
rtl/plan_submit_csr_v023.sv
rtl/v023_axi_shared.sv
// control-fix modules in the delivered set (not extra data paths)
rtl/pl_execution_plan_v023.sv
rtl/ready_scan_banked_v1.sv
rtl/block_address_v023.sv
rtl/axi_dma_v023_multi.sv
rtl/axi_dma_v023_bounded.sv
// ---- V0.24 fusion path ----
rtl/fp32_fma_pipe.sv
rtl/epilogue_relu.sv
rtl/epilogue_f32_to_i16.sv
rtl/epilogue_i48_to_f32_v024.sv
rtl/epilogue_fma_stage_v024.sv
rtl/epilogue_lane_v024.sv
rtl/epilogue_stream_engine_v024.sv
rtl/fusion_c48_framer.sv
rtl/fusion_c48_fifo.sv
rtl/fusion_a16_blockbuf.sv
rtl/fusion_a16_writer.sv
rtl/matrix_stream_fusion_top_v024.sv
rtl/v024_matrix_queue_engine.sv
// ---- approximate DIV/SQRT core (single definition) ----
rtl/approx_recip_lut.sv
rtl/approx_rsqrt_lut.sv
rtl/approx_div_sqrt.sv
// ---- V0.24 top ----
rtl/v024_unified_top.sv
