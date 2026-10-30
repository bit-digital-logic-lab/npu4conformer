// shared sealed DMA (vector/layout wrappers + graph fetch)
work/rtl/axi_dma_v019.sv
// shared exact FP32 ALU and divider
work/rtl/asr_fp32_alu.sv
// shared divider
work/rtl/u16_divmod.sv
// FMA vendor stub (compile-only; op17 not covered)
work/tests/fma_forbidden_stub.sv
// graph controller
v023_repair/ds_graph/rtl/wc_graph_ctrl.sv
// graph top (needs integrator copy with ddr_vector_axi_pipe instance)
v023_repair/ds_graph/rtl/wc_graph_top.sv
// vector candidate (unique modules)
v023_repair/ds_vector/candidate/rtl/ddr_vector_engine_pipe.sv
// vector descriptor validator
v023_repair/ds_vector/candidate/rtl/vector_desc_check_pipe.sv
// vector fixed lane
v023_repair/ds_vector/candidate/rtl/asr_fp32_lane_fixed.sv
// vector AXI wrapper (module ddr_vector_axi_pipe)
v023_repair/ds_vector/candidate/rtl/ddr_vector_axi_pipe.sv
// layout AXI wrapper
work/rtl/ddr_layout_axi.sv
// layout candidate: burst version ONLY (same module name as step version)
v023_repair/ds_layout/rtl/ddr_layout_engine_v023_burst.sv
// matrix unified cluster
v023_repair/ds_matrix/candidate/rtl/matrix_p2_cluster_v2.sv
// matrix engine
v023_repair/ds_matrix/candidate/rtl/block_engine_prefetch_v2.sv
// matrix storage
v023_repair/ds_matrix/candidate/rtl/block_storage_stream_v2.sv
// matrix DMA (no abort/drain yet)
v023_repair/ds_matrix/candidate/rtl/axi_dma_v020_multi_v2.sv
// control plan v023
v023_repair/ds_control_fixes/candidate/rtl/pl_execution_plan_v023.sv
// control CSR v023
v023_repair/ds_control_fixes/candidate/rtl/plan_submit_csr_v023.sv
// control ready scan
v023_repair/ds_control_fixes/candidate/rtl/ready_scan_banked_v1.sv
// control pipelined block address
v023_repair/ds_control_fixes/candidate/rtl/block_address_v023.sv
// control multi DMA (abort/drain capable)
v023_repair/ds_control_fixes/candidate/rtl/axi_dma_v023_multi.sv
// control bounded DMA (plan fetch)
v023_repair/ds_control_fixes/candidate/rtl/axi_dma_v023_bounded.sv
