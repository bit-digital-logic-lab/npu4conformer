`timescale 1ns/1ps
// V0.23 matrix P2 cluster: engine + storage + two independent streaming DMA
// masters.  The read DMA drives only AR/R; the write DMA drives only AW/W/B.
// The storage keeps separate read and write transaction ports, so the two
// masters can be active concurrently.  This is a logic-level integration
// wrapper; it is not a DDR timing model and no synthesis/STA is implied.
module matrix_p2_cluster_v2 #(
 parameter integer EXTERNAL_ARRAY=0,
 parameter integer SLOTS=2,
 parameter integer MAX_DIM=4096,
 parameter integer PIPE_STAGES=4,
 parameter integer ACCUM_MODE=0,
 parameter integer CPA_PIPE=1,
 parameter integer MAX_OUT=8,
 parameter integer FIFO_BEATS=128,
 parameter [31:0] ARENA_BASE=32'h03000000,
 parameter [31:0] ARENA_END=32'h08000000,
 parameter integer WR_OUT=8
)(
 output wire ext_reset,ext_flush,ext_clear,output wire [255:0] ext_a,output wire [111:0] ext_w,output wire [15:0] ext_av,ext_wv,ext_positions,output wire ext_clip,
 input wire [12287:0] ext_sums,input wire ext_drain,input wire [7:0] ext_pd,ext_ad,
 input wire clk,reset,start,
 input wire [31:0] cfg_a_base,cfg_b_base,cfg_c_base,cfg_epoch,
 input wire [15:0] cfg_m,cfg_n,cfg_k,cfg_layer,cfg_a_id,cfg_b_id,cfg_c_id,
 input wire [15:0] cfg_target_high,cfg_allowed_ops,cfg_requested_op,
 input wire [15:0] cfg_positions,input wire cfg_clip,
 input wire cfg_c_valid,input wire [15:0] cfg_c_completed,
 input wire [31:0] param_end,
 output wire busy,done,fault,output wire [7:0] error_code,
 output wire [63:0] task_cycles,
 output wire [31:0] compute_cycles,read_blocks,write_blocks,cache_hits,cache_misses,
 output wire [31:0] prefetch_hits,prefetch_wait_cycles,
 output wire [31:0] overlap_compute_read_cycles,overlap_compute_write_cycles,
 output wire [31:0] c_collect_groups,c_collect_cycles,c_raw_bypass_cycles,
 output wire [7:0] pe_drain_cycles,array_drain_cycles,
 output wire result_valid,input wire result_ready,
 output wire [31:0] result_cache_address,result_epoch,
 output wire [15:0] result_target_low,result_layer,result_matrix,result_block_row,result_block_col,result_op_tag,
 output wire [49151:0] result_data,
 output wire result_block_valid,result_in_operation,
 output wire [15:0] result_allowed_ops,result_completed_ops,
 // AXI read master (only AR/R are meaningful)
 output wire [39:0] rd_m_axi_araddr,output wire [7:0] rd_m_axi_arlen,
 output wire [2:0] rd_m_axi_arsize,output wire [1:0] rd_m_axi_arburst,
 output wire rd_m_axi_arvalid,input wire rd_m_axi_arready,
 input wire [127:0] rd_m_axi_rdata,input wire [1:0] rd_m_axi_rresp,
 input wire rd_m_axi_rlast,rd_m_axi_rvalid,output wire rd_m_axi_rready,
 // AXI write master (only AW/W/B are meaningful)
 output wire [39:0] wr_m_axi_awaddr,output wire [7:0] wr_m_axi_awlen,
 output wire [2:0] wr_m_axi_awsize,output wire [1:0] wr_m_axi_awburst,
 output wire wr_m_axi_awvalid,input wire wr_m_axi_awready,
 output wire [127:0] wr_m_axi_wdata,output wire [15:0] wr_m_axi_wstrb,
 output wire wr_m_axi_wlast,wr_m_axi_wvalid,input wire wr_m_axi_wready,
 input wire [1:0] wr_m_axi_bresp,input wire wr_m_axi_bvalid,output wire wr_m_axi_bready,
 // DMA telemetry
 output wire [31:0] rd_ar_outstanding_max,rd_read_bytes,rd_read_bursts,
 output wire [31:0] wr_b_outstanding_max,wr_write_bytes,wr_write_bursts,
 output wire [63:0] rd_read_fifo_high
);
 // engine <-> storage
 wire ld_valid,ld_ready;wire [1:0] ld_kind;wire ld_stage;wire [31:0] ld_address,ld_epoch;
 wire [15:0] ld_layer,ld_matrix,ld_block_row,ld_block_col,ld_allowed_ops,ld_completed_ops;
 wire [1:0] ld_encoding;wire ld_block_valid,ld_in_operation;
 wire [1:0] stage_a_ready,stage_w_ready,stage_a_fault,stage_w_fault;
 wire [1:0] stage_a_bvalid,stage_w_bvalid,stage_a_inop,stage_w_inop;
 wire [63:0] stage_a_epoch,stage_w_epoch;
 wire [31:0] stage_a_layer,stage_w_layer,stage_a_matrix,stage_w_matrix;
 wire [31:0] stage_a_row,stage_w_row,stage_a_col,stage_w_col;
 wire [31:0] stage_a_allowed,stage_w_allowed,stage_a_completed,stage_w_completed;
 wire [3:0] stage_a_encoding,stage_w_encoding;
 wire [1:0] stage_release;
 wire rd_stage,rd_row_half,rd_col_half;wire [79:0] a_k,w_k;
 wire [255:0] a_values;wire [111:0] w_values;
 wire c_hdr_valid,c_hdr_exists,c_hdr_bvalid,c_hdr_inop,c_hdr_error;
 wire [7:0] c_hdr_code;wire [63:0] c_hdr_epoch;
 wire [31:0] c_hdr_layer,c_hdr_matrix,c_hdr_row,c_hdr_col,c_hdr_allowed,c_hdr_completed;
 wire [3:0] c_hdr_encoding;wire c_hdr_ready;
 wire c_ld_valid,c_ld_last,c_ld_done,c_ld_error;wire [127:0] c_ld_data;
 wire [15:0] c_ld_index;wire [7:0] c_ld_code;wire c_ld_ready;
 wire cseg_valid,cseg_ready;wire [31:0] cseg_address,cseg_epoch;
 wire [15:0] cseg_layer,cseg_matrix,cseg_row,cseg_col,cseg_beats;
 wire cval_valid,cval_ready;wire [191:0] cval_data;wire cval_last;
 wire [7:0] cwr_pending;wire cwr_idle,cwr_done,cwr_error;wire [7:0] cwr_code;
 wire abort_storage,storage_drain_done,rd_active,wr_active;
 // storage <-> DMA transaction ports
 wire rd_req_valid,rd_req_ready;wire [31:0] rd_req_addr;wire [15:0] rd_req_beats;
 wire rd_valid,rd_ready;wire [127:0] rd_data;wire [15:0] rd_index;wire rd_done,rd_error;
 wire wr_req_valid,wr_req_ready;wire [31:0] wr_req_addr;wire [15:0] wr_req_beats;
 wire wr_valid,wr_ready;wire [127:0] wr_data;wire [15:0] wr_strobe;wire wr_done,wr_error;
 // unused DMA sides
 wire rd_unused_ready;wire [127:0] rd_unused_data;wire [15:0] rd_unused_index;
 wire wr_unused_ready;wire [127:0] wr_unused_data;wire [15:0] wr_unused_strobe,wr_unused_index;

 block_engine_prefetch_v2 #(.SLOTS(SLOTS),.MAX_DIM(MAX_DIM),.PIPE_STAGES(PIPE_STAGES),
  .ACCUM_MODE(ACCUM_MODE),.CPA_PIPE(CPA_PIPE),.EXTERNAL_ARRAY(EXTERNAL_ARRAY)) eng(
  .ext_reset(ext_reset),.ext_flush(ext_flush),.ext_clear(ext_clear),.ext_a(ext_a),.ext_w(ext_w),.ext_av(ext_av),.ext_wv(ext_wv),.ext_positions(ext_positions),.ext_clip(ext_clip),.ext_sums(ext_sums),.ext_drain(ext_drain),.ext_pd(ext_pd),.ext_ad(ext_ad),
  
  .clk(clk),.reset(reset),.start(start),
  .cfg_a_base(cfg_a_base),.cfg_b_base(cfg_b_base),.cfg_c_base(cfg_c_base),.cfg_epoch(cfg_epoch),
  .cfg_m(cfg_m),.cfg_n(cfg_n),.cfg_k(cfg_k),.cfg_layer(cfg_layer),.cfg_a_id(cfg_a_id),
  .cfg_b_id(cfg_b_id),.cfg_c_id(cfg_c_id),.cfg_target_high(cfg_target_high),
  .cfg_allowed_ops(cfg_allowed_ops),.cfg_requested_op(cfg_requested_op),
  .cfg_positions(cfg_positions),.cfg_clip(cfg_clip),.cfg_c_valid(cfg_c_valid),
  .cfg_c_completed(cfg_c_completed),
  .busy(busy),.done(done),.fault(fault),.error_code(error_code),.task_cycles(task_cycles),
  .compute_cycles(compute_cycles),.read_blocks(read_blocks),.write_blocks(write_blocks),
  .cache_hits(cache_hits),.cache_misses(cache_misses),
  .prefetch_hits(prefetch_hits),.prefetch_wait_cycles(prefetch_wait_cycles),
  .overlap_compute_read_cycles(overlap_compute_read_cycles),
  .overlap_compute_write_cycles(overlap_compute_write_cycles),
  .c_collect_groups(c_collect_groups),.c_collect_cycles(c_collect_cycles),
  .c_raw_bypass_cycles(c_raw_bypass_cycles),.pe_drain_cycles(pe_drain_cycles),
  .array_drain_cycles(array_drain_cycles),.array_drain_done(),
  .ld_valid(ld_valid),.ld_ready(ld_ready),.ld_kind(ld_kind),.ld_stage(ld_stage),
  .ld_address(ld_address),.ld_epoch(ld_epoch),.ld_layer(ld_layer),.ld_matrix(ld_matrix),
  .ld_block_row(ld_block_row),.ld_block_col(ld_block_col),.ld_allowed_ops(ld_allowed_ops),
  .ld_completed_ops(ld_completed_ops),.ld_encoding(ld_encoding),.ld_block_valid(ld_block_valid),
  .ld_in_operation(ld_in_operation),
  .stage_a_ready(stage_a_ready),.stage_w_ready(stage_w_ready),.stage_a_fault(stage_a_fault),
  .stage_w_fault(stage_w_fault),.stage_a_bvalid(stage_a_bvalid),.stage_w_bvalid(stage_w_bvalid),
  .stage_a_inop(stage_a_inop),.stage_w_inop(stage_w_inop),.stage_a_epoch(stage_a_epoch),
  .stage_w_epoch(stage_w_epoch),.stage_a_layer(stage_a_layer),.stage_w_layer(stage_w_layer),
  .stage_a_matrix(stage_a_matrix),.stage_w_matrix(stage_w_matrix),.stage_a_row(stage_a_row),
  .stage_w_row(stage_w_row),.stage_a_col(stage_a_col),.stage_w_col(stage_w_col),
  .stage_a_allowed(stage_a_allowed),.stage_w_allowed(stage_w_allowed),
  .stage_a_completed(stage_a_completed),.stage_w_completed(stage_w_completed),
  .stage_a_encoding(stage_a_encoding),.stage_w_encoding(stage_w_encoding),
  .stage_release(stage_release),.rd_stage(rd_stage),.rd_row_half(rd_row_half),
  .rd_col_half(rd_col_half),.a_k(a_k),.w_k(w_k),.a_values(a_values),.w_values(w_values),
  .c_hdr_valid(c_hdr_valid),.c_hdr_exists(c_hdr_exists),.c_hdr_bvalid(c_hdr_bvalid),
  .c_hdr_inop(c_hdr_inop),.c_hdr_error(c_hdr_error),.c_hdr_code(c_hdr_code),
  .c_hdr_epoch(c_hdr_epoch),.c_hdr_layer(c_hdr_layer),.c_hdr_matrix(c_hdr_matrix),
  .c_hdr_row(c_hdr_row),.c_hdr_col(c_hdr_col),.c_hdr_allowed(c_hdr_allowed),
  .c_hdr_completed(c_hdr_completed),.c_hdr_encoding(c_hdr_encoding),.c_hdr_ready(c_hdr_ready),
  .c_ld_valid(c_ld_valid),.c_ld_ready(c_ld_ready),.c_ld_data(c_ld_data),.c_ld_index(c_ld_index),
  .c_ld_last(c_ld_last),.c_ld_done(c_ld_done),.c_ld_error(c_ld_error),.c_ld_code(c_ld_code),
  .cseg_valid(cseg_valid),.cseg_ready(cseg_ready),.cseg_address(cseg_address),
  .cseg_epoch(cseg_epoch),.cseg_layer(cseg_layer),.cseg_matrix(cseg_matrix),.cseg_row(cseg_row),
  .cseg_col(cseg_col),.cseg_beats(cseg_beats),.cval_valid(cval_valid),.cval_ready(cval_ready),
  .cval_data(cval_data),.cval_last(cval_last),.cwr_pending(cwr_pending),.cwr_idle(cwr_idle),
  .cwr_done(cwr_done),.cwr_error(cwr_error),.cwr_code(cwr_code),.rd_active(rd_active),
  .wr_active(wr_active),.abort_storage(abort_storage),.storage_drain_done(storage_drain_done),
  .result_valid(result_valid),.result_ready(result_ready),.result_cache_address(result_cache_address),
  .result_epoch(result_epoch),.result_target_low(result_target_low),.result_layer(result_layer),
  .result_matrix(result_matrix),.result_block_row(result_block_row),.result_block_col(result_block_col),
  .result_op_tag(result_op_tag),.result_data(result_data),.result_block_valid(result_block_valid),
  .result_in_operation(result_in_operation),.result_allowed_ops(result_allowed_ops),
  .result_completed_ops(result_completed_ops));

 block_storage_stream_v2 #(.ARENA_BASE(ARENA_BASE),.ARENA_END(ARENA_END),.WR_OUT(WR_OUT)) sto(
  .clk(clk),.rst_n(!reset),.abort(abort_storage),.param_end(param_end),
  .cfg_a_base(cfg_a_base),.cfg_b_base(cfg_b_base),.cfg_c_base(cfg_c_base),.cfg_epoch(cfg_epoch),
  .cfg_m(cfg_m),.cfg_n(cfg_n),.cfg_k(cfg_k),.cfg_layer(cfg_layer),.cfg_a_id(cfg_a_id),
  .cfg_b_id(cfg_b_id),.cfg_c_id(cfg_c_id),.cfg_allowed(cfg_allowed_ops),
  .cfg_c_valid(cfg_c_valid),.cfg_c_completed(cfg_c_completed),
  .ld_valid(ld_valid),.ld_ready(ld_ready),.ld_kind(ld_kind),.ld_stage(ld_stage),
  .ld_address(ld_address),.ld_epoch(ld_epoch),.ld_layer(ld_layer),.ld_matrix(ld_matrix),
  .ld_block_row(ld_block_row),.ld_block_col(ld_block_col),.ld_allowed_ops(ld_allowed_ops),
  .ld_completed_ops(ld_completed_ops),.ld_encoding(ld_encoding),.ld_block_valid(ld_block_valid),
  .ld_in_operation(ld_in_operation),
  .stage_a_ready(stage_a_ready),.stage_w_ready(stage_w_ready),.stage_a_fault(stage_a_fault),
  .stage_w_fault(stage_w_fault),.stage_a_bvalid(stage_a_bvalid),.stage_w_bvalid(stage_w_bvalid),
  .stage_a_inop(stage_a_inop),.stage_w_inop(stage_w_inop),.stage_a_epoch(stage_a_epoch),
  .stage_w_epoch(stage_w_epoch),.stage_a_layer(stage_a_layer),.stage_w_layer(stage_w_layer),
  .stage_a_matrix(stage_a_matrix),.stage_w_matrix(stage_w_matrix),.stage_a_row(stage_a_row),
  .stage_w_row(stage_w_row),.stage_a_col(stage_a_col),.stage_w_col(stage_w_col),
  .stage_a_allowed(stage_a_allowed),.stage_w_allowed(stage_w_allowed),
  .stage_a_completed(stage_a_completed),.stage_w_completed(stage_w_completed),
  .stage_a_encoding(stage_a_encoding),.stage_w_encoding(stage_w_encoding),
  .stage_release(stage_release),.rd_stage(rd_stage),.rd_row_half(rd_row_half),
  .rd_col_half(rd_col_half),.a_k(a_k),.w_k(w_k),.a_values(a_values),.w_values(w_values),
  .c_hdr_valid(c_hdr_valid),.c_hdr_ready(c_hdr_ready),.c_hdr_exists(c_hdr_exists),
  .c_hdr_bvalid(c_hdr_bvalid),.c_hdr_inop(c_hdr_inop),.c_hdr_error(c_hdr_error),
  .c_hdr_code(c_hdr_code),.c_hdr_epoch(c_hdr_epoch),.c_hdr_layer(c_hdr_layer),
  .c_hdr_matrix(c_hdr_matrix),.c_hdr_row(c_hdr_row),.c_hdr_col(c_hdr_col),
  .c_hdr_allowed(c_hdr_allowed),.c_hdr_completed(c_hdr_completed),.c_hdr_encoding(c_hdr_encoding),
  .c_ld_valid(c_ld_valid),.c_ld_ready(c_ld_ready),.c_ld_data(c_ld_data),.c_ld_index(c_ld_index),
  .c_ld_last(c_ld_last),.c_ld_done(c_ld_done),.c_ld_error(c_ld_error),.c_ld_code(c_ld_code),
  .cseg_valid(cseg_valid),.cseg_ready(cseg_ready),.cseg_address(cseg_address),
  .cseg_epoch(cseg_epoch),.cseg_layer(cseg_layer),.cseg_matrix(cseg_matrix),.cseg_row(cseg_row),
  .cseg_col(cseg_col),.cseg_beats(cseg_beats),.cval_valid(cval_valid),.cval_ready(cval_ready),
  .cval_data(cval_data),.cval_last(cval_last),.cwr_pending(cwr_pending),.cwr_idle(cwr_idle),
  .cwr_done(cwr_done),.cwr_error(cwr_error),.cwr_code(cwr_code),
  .rd_req_valid(rd_req_valid),.rd_req_ready(rd_req_ready),.rd_req_address(rd_req_addr),
  .rd_req_beats(rd_req_beats),.rd_valid(rd_valid),.rd_ready(rd_ready),.rd_data(rd_data),
  .rd_index(rd_index),.rd_done(rd_done),.rd_error(rd_error),
  .wr_req_valid(wr_req_valid),.wr_req_ready(wr_req_ready),.wr_req_address(wr_req_addr),
  .wr_req_beats(wr_req_beats),.wr_valid(wr_valid),.wr_ready(wr_ready),.wr_data(wr_data),
  .wr_strobe(wr_strobe),.wr_done(wr_done),.wr_error(wr_error),
  .idle(),.drain_done(storage_drain_done),.read_blocks(),.write_segments(),.read_bytes(),
  .write_bytes(),.error_count(),.read_wait_cycles(),.write_wait_cycles(),.ov_same_cycle(),
  .rd_active_wr_active_cycles(),.rd_active(rd_active),.wr_active(wr_active),.dbg_rstate(),.dbg_wwait());

 axi_dma_v020_multi_v2 #(.MAX_OUT(MAX_OUT),.FIFO_BEATS(FIFO_BEATS)) rdma(
  .clk(clk),.rst_n(!reset),.request_valid(rd_req_valid),.request_ready(rd_req_ready),
  .request_write(1'b0),.request_address(rd_req_addr),.request_beats(rd_req_beats),
  .read_valid(rd_valid),.read_ready(rd_ready),.read_data(rd_data),.read_index(rd_index),
  .write_valid(1'b0),.write_ready(rd_unused_ready),.write_data(128'd0),.write_strobe(16'd0),
  .write_index(),
  .done(rd_done),.error(rd_error),.read_bytes(rd_read_bytes),.write_bytes(),
  .read_bursts(rd_read_bursts),.write_bursts(),.ar_outstanding_max(rd_ar_outstanding_max),
  .b_outstanding_max(),.read_bubble_cycles(),.write_bubble_cycles(),.read_fifo_high(rd_read_fifo_high),
  .m_axi_araddr(rd_m_axi_araddr),.m_axi_arlen(rd_m_axi_arlen),.m_axi_arsize(rd_m_axi_arsize),
  .m_axi_arburst(rd_m_axi_arburst),.m_axi_arcache(),.m_axi_arprot(),
  .m_axi_arvalid(rd_m_axi_arvalid),.m_axi_arready(rd_m_axi_arready),
  .m_axi_rdata(rd_m_axi_rdata),.m_axi_rresp(rd_m_axi_rresp),.m_axi_rlast(rd_m_axi_rlast),
  .m_axi_rvalid(rd_m_axi_rvalid),.m_axi_rready(rd_m_axi_rready),
  .m_axi_awaddr(),.m_axi_awlen(),.m_axi_awsize(),.m_axi_awburst(),.m_axi_awcache(),
  .m_axi_awprot(),.m_axi_awvalid(),.m_axi_awready(1'b0),.m_axi_wdata(),.m_axi_wstrb(),
  .m_axi_wlast(),.m_axi_wvalid(),.m_axi_wready(1'b0),.m_axi_bresp(2'd0),
  .m_axi_bvalid(1'b0),.m_axi_bready());

 axi_dma_v020_multi_v2 #(.MAX_OUT(MAX_OUT),.FIFO_BEATS(FIFO_BEATS)) wdma(
  .clk(clk),.rst_n(!reset),.request_valid(wr_req_valid),.request_ready(wr_req_ready),
  .request_write(1'b1),.request_address(wr_req_addr),.request_beats(wr_req_beats),
  .read_valid(),.read_ready(1'b1),.read_data(rd_unused_data),.read_index(rd_unused_index),
  .write_valid(wr_valid),.write_ready(wr_ready),.write_data(wr_data),.write_strobe(wr_strobe),
  .write_index(),
  .done(wr_done),.error(wr_error),.read_bytes(),.write_bytes(wr_write_bytes),
  .read_bursts(),.write_bursts(wr_write_bursts),.ar_outstanding_max(),
  .b_outstanding_max(wr_b_outstanding_max),.read_bubble_cycles(),.write_bubble_cycles(),
  .read_fifo_high(),
  .m_axi_araddr(),.m_axi_arlen(),.m_axi_arsize(),.m_axi_arburst(),.m_axi_arcache(),
  .m_axi_arprot(),.m_axi_arvalid(),.m_axi_arready(1'b0),.m_axi_rdata(128'd0),
  .m_axi_rresp(2'd0),.m_axi_rlast(1'b0),.m_axi_rvalid(1'b0),.m_axi_rready(),
  .m_axi_awaddr(wr_m_axi_awaddr),.m_axi_awlen(wr_m_axi_awlen),.m_axi_awsize(wr_m_axi_awsize),
  .m_axi_awburst(wr_m_axi_awburst),.m_axi_awcache(),.m_axi_awprot(),
  .m_axi_awvalid(wr_m_axi_awvalid),.m_axi_awready(wr_m_axi_awready),
  .m_axi_wdata(wr_m_axi_wdata),.m_axi_wstrb(wr_m_axi_wstrb),.m_axi_wlast(wr_m_axi_wlast),
  .m_axi_wvalid(wr_m_axi_wvalid),.m_axi_wready(wr_m_axi_wready),
  .m_axi_bresp(wr_m_axi_bresp),.m_axi_bvalid(wr_m_axi_bvalid),.m_axi_bready(wr_m_axi_bready));
endmodule
