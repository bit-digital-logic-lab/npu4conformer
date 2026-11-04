`timescale 1ns/1ps
// matrix_stream_fusion_top.sv
// True on-chip matrix -> C48 -> I48/F32 -> FMA(scale,bias) -> A16 -> AXI
// writeback chain.
//
//   block_engine_prefetch_v2 (unmodified ds_matrix candidate)
//        |  cseg + cval[191:0] (real 4-lane C48, valid/ready/last)
//        v
//   fusion_c48_framer  (segment cadence, tile-last, row-major word index)
//        v
//   fusion_c48_fifo    (elastic, credit/occupancy, 1-slot skid)
//        v
//   epilogue_stream_engine_v023 (unmodified primary_stream_fix candidate:
//        I48->F32 RNE, single-rounding FP32 FMA, optional ReLU, F32->I16 RNE)
//        v  a16_packed[127:0] + row-major word tag + tile-last
//   fusion_a16_blockbuf (2 KiB on-chip scatter buffer, no DDR C48 traffic)
//        v
//   fusion_a16_writer -> axi_dma_v020_multi_v2 (write master)
//
// No C48 value is ever written to or read from DDR on this path.  The storage
// block_storage_stream_v2 is still used for A/W (and optional C) loads, but its
// C48 write port is deliberately tied off.  The engine's cwr_idle is taken from
// that idle write port, so the engine's own completion path is unchanged.
module matrix_stream_fusion_top_v024 #(
  parameter integer EXTERNAL_ARRAY=0,
 parameter integer SLOTS       = 2,
  parameter integer MAX_DIM     = 4096,
  parameter integer PIPE_STAGES = 4,
  parameter integer ACCUM_MODE  = 0,
  parameter integer CPA_PIPE    = 1,
  parameter integer MAX_OUT     = 8,
  parameter integer FIFO_BEATS  = 128,
  parameter [31:0]  ARENA_BASE  = 32'h03000000,
  parameter [31:0]  ARENA_END   = 32'h08000000,
  parameter integer WR_OUT      = 8,
  parameter integer BRIDGE_FIFO = 16,
  parameter integer A16_WORDS   = 128
)(
  output wire ext_reset,ext_flush,ext_clear,output wire [255:0] ext_a,output wire [111:0] ext_w,output wire [15:0] ext_av,ext_wv,ext_positions,output wire ext_clip,
 input wire [12287:0] ext_sums,input wire ext_drain,input wire [7:0] ext_pd,ext_ad,
 input  wire         clk,
  input  wire         reset,
  input  wire         param_rst_n, // Ungated true core reset for retained host coefficient bank
  input  wire         start,

  // matrix configuration
  input  wire [31:0]  cfg_a_base,
  input  wire [31:0]  cfg_b_base,
  input  wire [31:0]  cfg_a16_base,
  input  wire [31:0]  cfg_epoch,
  input  wire [15:0]  cfg_m,
  input  wire [15:0]  cfg_n,
  input  wire [15:0]  cfg_k,
  input  wire [15:0]  cfg_layer,
  input  wire [15:0]  cfg_a_id,
  input  wire [15:0]  cfg_b_id,
  input  wire [15:0]  cfg_c_id,
  input  wire [15:0]  cfg_target_high,
  input  wire [15:0]  cfg_allowed_ops,
  input  wire [15:0]  cfg_requested_op,
  input  wire [15:0]  cfg_positions,
  input  wire         cfg_clip,
  input  wire         cfg_c_valid,
  input  wire [15:0]  cfg_c_completed,
  input  wire [31:0]  param_end,

  // epilogue configuration
  input  wire [1:0]   cfg_fma_mode,
  input  wire         cfg_relu_en,
  input  wire         cfg_perchannel_en,
  input  wire [31:0]  cfg_scale,
  input  wire [31:0]  cfg_bias,

  // broadcast parameter preload (scale/bias)
  input  wire         param_wr_valid,
  output wire         param_wr_ready,
  input  wire [7:0]   param_wr_addr,
  input  wire [31:0]  param_wr_data,

  // status / telemetry
  output wire         busy,
  output wire         done,
  output wire         fault,
  output wire [7:0]   error_code,
  output wire [63:0]  task_cycles,
  output wire [31:0]  compute_cycles,
  output wire [31:0]  read_blocks,
  output wire [31:0]  write_blocks,
  output wire [31:0]  c_collect_groups,
  output wire [31:0]  c_collect_cycles,
  output wire [31:0]  c_raw_bypass_cycles,
  output wire [7:0]   pe_drain_cycles,
  output wire [7:0]   array_drain_cycles,

  // fusion telemetry
  output wire [31:0]  stat_c48_beats,
  output wire [31:0]  stat_a16_words,
  output wire [31:0]  stat_a16_bytes,
  output wire [31:0]  stat_fifo_high,
  output wire [31:0]  stat_fifo_stalls,
  output wire [31:0]  stat_c48_ddr_bytes,      // must be 0 on this path
  output wire [31:0]  stat_drain_cycles,
  output wire [31:0]  stat_last_w_cycle,
  output wire [31:0]  stat_dma_done_cycle,
  output wire [15:0]  stat_tiles,

  // AXI read master (A/W/C loads)
  output wire [39:0]  rd_m_axi_araddr,
  output wire [7:0]   rd_m_axi_arlen,
  output wire [2:0]   rd_m_axi_arsize,
  output wire [1:0]   rd_m_axi_arburst,
  output wire         rd_m_axi_arvalid,
  input  wire         rd_m_axi_arready,
  input  wire [127:0] rd_m_axi_rdata,
  input  wire [1:0]   rd_m_axi_rresp,
  input  wire         rd_m_axi_rlast,
  input  wire         rd_m_axi_rvalid,
  output wire         rd_m_axi_rready,

  // AXI write master (A16 only)
  output wire [39:0]  wr_m_axi_awaddr,
  output wire [7:0]   wr_m_axi_awlen,
  output wire [2:0]   wr_m_axi_awsize,
  output wire [1:0]   wr_m_axi_awburst,
  output wire         wr_m_axi_awvalid,
  input  wire         wr_m_axi_awready,
  output wire [127:0] wr_m_axi_wdata,
  output wire [15:0]  wr_m_axi_wstrb,
  output wire         wr_m_axi_wlast,
  output wire         wr_m_axi_wvalid,
  input  wire         wr_m_axi_wready,
  input  wire [1:0]   wr_m_axi_bresp,
  input  wire         wr_m_axi_bvalid,
  output wire         wr_m_axi_bready,

  output wire [31:0]  rd_read_bytes,
  output wire [31:0]  rd_read_bursts,
  output wire [31:0]  wr_write_bytes,
  output wire [31:0]  wr_write_bursts,
  output wire [31:0]  rd_ar_outstanding_max,
  output wire [31:0]  wr_b_outstanding_max
);
  // ---------------------------------------------------------------------
  // engine <-> storage
  // ---------------------------------------------------------------------
  wire ld_valid, ld_ready;
  wire [1:0] ld_kind;
  wire ld_stage;
  wire [31:0] ld_address, ld_epoch;
  wire [15:0] ld_layer, ld_matrix, ld_block_row, ld_block_col, ld_allowed_ops, ld_completed_ops;
  wire [1:0] ld_encoding;
  wire ld_block_valid, ld_in_operation;
  wire [1:0] stage_a_ready, stage_w_ready, stage_a_fault, stage_w_fault;
  wire [1:0] stage_a_bvalid, stage_w_bvalid, stage_a_inop, stage_w_inop;
  wire [63:0] stage_a_epoch, stage_w_epoch;
  wire [31:0] stage_a_layer, stage_w_layer, stage_a_matrix, stage_w_matrix;
  wire [31:0] stage_a_row, stage_w_row, stage_a_col, stage_w_col;
  wire [31:0] stage_a_allowed, stage_w_allowed, stage_a_completed, stage_w_completed;
  wire [3:0] stage_a_encoding, stage_w_encoding;
  wire [1:0] stage_release;
  wire rd_stage, rd_row_half, rd_col_half;
  wire [79:0] a_k, w_k;
  wire [255:0] a_values;
  wire [111:0] w_values;

  // C load / C stream (storage write side is tied off)
  wire c_hdr_valid, c_hdr_exists, c_hdr_bvalid, c_hdr_inop, c_hdr_error;
  wire [7:0] c_hdr_code;
  wire [63:0] c_hdr_epoch;
  wire [31:0] c_hdr_layer, c_hdr_matrix, c_hdr_row, c_hdr_col, c_hdr_allowed, c_hdr_completed;
  wire [3:0] c_hdr_encoding;
  wire c_hdr_ready;
  wire c_ld_valid, c_ld_last, c_ld_done, c_ld_error;
  wire [127:0] c_ld_data;
  wire [15:0] c_ld_index;
  wire [7:0] c_ld_code;
  wire c_ld_ready;

  wire cseg_valid, cseg_ready;
  wire [31:0] cseg_address, cseg_epoch;
  wire [15:0] cseg_layer, cseg_matrix, cseg_row, cseg_col, cseg_beats;
  wire cval_valid, cval_ready;
  wire [191:0] cval_data;
  wire cval_last;
  wire [7:0] sto_cwr_pending;
  wire sto_cwr_idle, sto_cwr_done, sto_cwr_error;
  wire [7:0] sto_cwr_code;

  // storage <-> read DMA
  wire rd_req_valid, rd_req_ready;
  wire [31:0] rd_req_addr;
  wire [15:0] rd_req_beats;
  wire rd_valid, rd_ready;
  wire [127:0] rd_data;
  wire [15:0] rd_index;
  wire rd_done, rd_error;
  // unused storage write port
  wire sto_wr_req_valid, sto_wr_valid;
  wire [31:0] sto_wr_req_addr;
  wire [15:0] sto_wr_req_beats, sto_wr_strobe;
  wire [127:0] sto_wr_data;
  wire storage_drain_done, storage_idle, storage_rd_active, storage_wr_active;
  wire engine_abort_storage;

  // ---------------------------------------------------------------------
  // framer / fifo / epilogue / block buffer
  // ---------------------------------------------------------------------
  wire framed_valid, framed_ready;
  wire [191:0] framed_data;
  wire [15:0] framed_tag;
  wire framed_last;
  wire [15:0] tile_row, tile_col;
  wire [31:0] frame_cseg_count, frame_tile_count;
  wire        frame_err;
  wire [7:0]  frame_err_code;

  wire fifo_valid, fifo_ready, fifo_last;
  wire [191:0] fifo_data;
  wire [15:0] fifo_tag;
  wire [7:0] fifo_occ, fifo_high, fifo_credit;
  wire fifo_overflow;
  wire [31:0] fifo_in_beats, fifo_out_beats, fifo_stalls;

  wire ep_a16_valid, ep_a16_last, ep_packed_valid, ep_packed_ready, ep_packed_last;
  wire [63:0] ep_a16_data;
  wire [127:0] ep_packed;
  wire [15:0] ep_a16_tag, ep_packed_tag;
  wire ep_cfg_ready;
  wire ep_cfg_valid;
  wire [31:0] ep_c48_in, ep_a16_out, ep_spill_beats, ep_saved;

  wire buf_full, buf_drain_busy, buf_drain_done, buf_rd_valid, buf_rd_last, buf_wr_ready;
  wire [127:0] buf_rd_data;
  wire buf_dup_err;
  wire [7:0] buf_err_code;
  wire [31:0] buf_words_written, buf_words_read;

  wire writer_start, writer_busy, writer_done, writer_fault;
  wire [7:0] writer_err_code;
  wire [31:0] writer_beats, writer_bytes, writer_drain_cycles;
  wire [31:0] writer_last_w_cycle, writer_done_cycle;
  wire wdma_req_valid, wdma_req_ready, wdma_wr_valid, wdma_wr_ready;
  wire [31:0] wdma_req_addr;
  wire [15:0] wdma_req_beats, wdma_wr_strb;
  wire [127:0] wdma_wr_data;
  wire wdma_done, wdma_error;

  // ---------------------------------------------------------------------
  // control
  // ---------------------------------------------------------------------
  wire busy_engine, done_engine, fault_engine;
  wire [7:0] error_engine;
  wire engine_result_valid;

  reg        tile_written;
  reg        writer_started;
  reg [31:0] wr_base_lat;
  reg        cfg_pending;
  reg [31:0] a16_bytes_acc;

  wire engine_result_ready = tile_written;

  wire fatal_other = frame_err | buf_dup_err | fifo_overflow;
  wire fatal = fatal_other | writer_fault;
  wire flush = reset | fatal;


  wire [15:0] blocks_per_row = (cfg_n + 16'd31) >> 5;
  wire [31:0] tile_index = ({16'd0, tile_row} * {16'd0, blocks_per_row}) + {16'd0, tile_col};
  wire [31:0] tile_base  = cfg_a16_base + (tile_index << 11); // 2048 B / tile

  // epilogue configuration handshake: one descriptor per task, accepted while
  // the epilogue is drained (cfg_ready).
  always @(posedge clk or posedge reset) begin
    if (reset) begin
      cfg_pending <= 1'b0;
    end else if (start) begin
      cfg_pending <= 1'b1;
    end else if (cfg_pending && ep_cfg_ready) begin
      cfg_pending <= 1'b0;
    end
  end
  assign ep_cfg_valid = cfg_pending;

  always @(posedge clk or posedge reset) begin
    if (reset) begin
      tile_written   <= 1'b0;
      writer_started <= 1'b0;
      wr_base_lat    <= 32'd0;
      a16_bytes_acc  <= 32'd0;
    end else if (start) begin
      tile_written   <= 1'b0;
      writer_started <= 1'b0;
      wr_base_lat    <= 32'd0;
      a16_bytes_acc  <= 32'd0;
    end else begin
      if (buf_full && !writer_started && !tile_written) begin
        writer_started <= 1'b1;
        wr_base_lat    <= tile_base;
      end
      if (writer_done) begin
        tile_written <= 1'b1;
        a16_bytes_acc <= a16_bytes_acc + writer_bytes;
      end
      if (engine_result_ready && engine_result_valid) begin
        tile_written   <= 1'b0;
        writer_started <= 1'b0;
      end
    end
  end

  // writer starts one cycle after full; block buffer drain starts at the same
  // time and is backpressured by the writer through rd_ready.
  assign writer_start = buf_full && !writer_started && !tile_written;

  // engine result handshake: do not release the matrix tile until the A16 tile
  // has actually drained through AXI B responses.

  // ---------------------------------------------------------------------
  // matrix engine (unmodified ds_matrix candidate)
  // ---------------------------------------------------------------------
  block_engine_prefetch_v2 #(
    .SLOTS(SLOTS), .MAX_DIM(MAX_DIM), .PIPE_STAGES(PIPE_STAGES),
    .ACCUM_MODE(ACCUM_MODE), .CPA_PIPE(CPA_PIPE), .EXTERNAL_ARRAY(EXTERNAL_ARRAY)
  ) u_engine (
    .ext_reset(ext_reset),.ext_flush(ext_flush),.ext_clear(ext_clear),.ext_a(ext_a),.ext_w(ext_w),.ext_av(ext_av),.ext_wv(ext_wv),.ext_positions(ext_positions),.ext_clip(ext_clip),.ext_sums(ext_sums),.ext_drain(ext_drain),.ext_pd(ext_pd),.ext_ad(ext_ad),
  
    .clk(clk), .reset(reset), .start(start),
    .cfg_a_base(cfg_a_base), .cfg_b_base(cfg_b_base), .cfg_c_base(cfg_a16_base),
    .cfg_epoch(cfg_epoch), .cfg_m(cfg_m), .cfg_n(cfg_n), .cfg_k(cfg_k),
    .cfg_layer(cfg_layer), .cfg_a_id(cfg_a_id), .cfg_b_id(cfg_b_id), .cfg_c_id(cfg_c_id),
    .cfg_target_high(cfg_target_high), .cfg_allowed_ops(cfg_allowed_ops),
    .cfg_requested_op(cfg_requested_op), .cfg_positions(cfg_positions), .cfg_clip(cfg_clip),
    .cfg_c_valid(cfg_c_valid), .cfg_c_completed(cfg_c_completed),
    .busy(busy_engine), .done(done_engine), .fault(fault_engine), .error_code(error_engine),
    .task_cycles(task_cycles), .compute_cycles(compute_cycles),
    .read_blocks(read_blocks), .write_blocks(write_blocks),
    .cache_hits(), .cache_misses(),
    .prefetch_hits(), .prefetch_wait_cycles(),
    .overlap_compute_read_cycles(), .overlap_compute_write_cycles(),
    .c_collect_groups(c_collect_groups), .c_collect_cycles(c_collect_cycles),
    .c_raw_bypass_cycles(c_raw_bypass_cycles), .pe_drain_cycles(pe_drain_cycles),
    .array_drain_cycles(array_drain_cycles), .array_drain_done(),
    .ld_valid(ld_valid), .ld_ready(ld_ready), .ld_kind(ld_kind), .ld_stage(ld_stage),
    .ld_address(ld_address), .ld_epoch(ld_epoch), .ld_layer(ld_layer), .ld_matrix(ld_matrix),
    .ld_block_row(ld_block_row), .ld_block_col(ld_block_col), .ld_allowed_ops(ld_allowed_ops),
    .ld_completed_ops(ld_completed_ops), .ld_encoding(ld_encoding),
    .ld_block_valid(ld_block_valid), .ld_in_operation(ld_in_operation),
    .stage_a_ready(stage_a_ready), .stage_w_ready(stage_w_ready),
    .stage_a_fault(stage_a_fault), .stage_w_fault(stage_w_fault),
    .stage_a_bvalid(stage_a_bvalid), .stage_w_bvalid(stage_w_bvalid),
    .stage_a_inop(stage_a_inop), .stage_w_inop(stage_w_inop),
    .stage_a_epoch(stage_a_epoch), .stage_w_epoch(stage_w_epoch),
    .stage_a_layer(stage_a_layer), .stage_w_layer(stage_w_layer),
    .stage_a_matrix(stage_a_matrix), .stage_w_matrix(stage_w_matrix),
    .stage_a_row(stage_a_row), .stage_w_row(stage_w_row),
    .stage_a_col(stage_a_col), .stage_w_col(stage_w_col),
    .stage_a_allowed(stage_a_allowed), .stage_w_allowed(stage_w_allowed),
    .stage_a_completed(stage_a_completed), .stage_w_completed(stage_w_completed),
    .stage_a_encoding(stage_a_encoding), .stage_w_encoding(stage_w_encoding),
    .stage_release(stage_release), .rd_stage(rd_stage), .rd_row_half(rd_row_half),
    .rd_col_half(rd_col_half), .a_k(a_k), .w_k(w_k), .a_values(a_values), .w_values(w_values),
    .c_hdr_valid(c_hdr_valid), .c_hdr_ready(c_hdr_ready), .c_hdr_exists(c_hdr_exists),
    .c_hdr_bvalid(c_hdr_bvalid), .c_hdr_inop(c_hdr_inop), .c_hdr_error(c_hdr_error),
    .c_hdr_code(c_hdr_code), .c_hdr_epoch(c_hdr_epoch), .c_hdr_layer(c_hdr_layer),
    .c_hdr_matrix(c_hdr_matrix), .c_hdr_row(c_hdr_row), .c_hdr_col(c_hdr_col),
    .c_hdr_allowed(c_hdr_allowed), .c_hdr_completed(c_hdr_completed),
    .c_hdr_encoding(c_hdr_encoding),
    .c_ld_valid(c_ld_valid), .c_ld_ready(c_ld_ready), .c_ld_data(c_ld_data),
    .c_ld_index(c_ld_index), .c_ld_last(c_ld_last), .c_ld_done(c_ld_done),
    .c_ld_error(c_ld_error), .c_ld_code(c_ld_code),
    .cseg_valid(cseg_valid), .cseg_ready(cseg_ready), .cseg_address(cseg_address),
    .cseg_epoch(cseg_epoch), .cseg_layer(cseg_layer), .cseg_matrix(cseg_matrix),
    .cseg_row(cseg_row), .cseg_col(cseg_col), .cseg_beats(cseg_beats),
    .cval_valid(cval_valid), .cval_ready(cval_ready), .cval_data(cval_data),
    .cval_last(cval_last),
    .cwr_pending(8'd0), .cwr_idle(sto_cwr_idle), .cwr_done(1'b0),
    .cwr_error(sto_cwr_error), .cwr_code(sto_cwr_code),
    .rd_active(storage_rd_active), .wr_active(storage_wr_active),
    .abort_storage(engine_abort_storage), .storage_drain_done(storage_drain_done),
    .result_valid(engine_result_valid), .result_ready(engine_result_ready),
    .result_cache_address(), .result_epoch(), .result_target_low(),
    .result_layer(), .result_matrix(), .result_block_row(), .result_block_col(),
    .result_op_tag(), .result_data(), .result_block_valid(), .result_in_operation(),
    .result_allowed_ops(), .result_completed_ops()
  );

  // ---------------------------------------------------------------------
  // storage (A/W and optional C load only; C48 write path tied off)
  // ---------------------------------------------------------------------
  block_storage_stream_v2 #(
    .ARENA_BASE(ARENA_BASE), .ARENA_END(ARENA_END),
    .PARAM_BASE(32'h10000000), .PARAM_END(32'h40000000),
    .LD_Q(8), .WR_Q(8), .WR_OUT(WR_OUT)
  ) u_storage (
    .clk(clk), .rst_n(!reset), .abort(engine_abort_storage | fatal),
    .param_end(param_end),
    .cfg_a_base(cfg_a_base), .cfg_b_base(cfg_b_base), .cfg_c_base(cfg_a16_base),
    .cfg_epoch(cfg_epoch), .cfg_m(cfg_m), .cfg_n(cfg_n), .cfg_k(cfg_k),
    .cfg_layer(cfg_layer), .cfg_a_id(cfg_a_id), .cfg_b_id(cfg_b_id), .cfg_c_id(cfg_c_id),
    .cfg_allowed(cfg_allowed_ops), .cfg_c_valid(cfg_c_valid), .cfg_c_completed(cfg_c_completed),
    .ld_valid(ld_valid), .ld_ready(ld_ready), .ld_kind(ld_kind), .ld_stage(ld_stage),
    .ld_address(ld_address), .ld_epoch(ld_epoch), .ld_layer(ld_layer), .ld_matrix(ld_matrix),
    .ld_block_row(ld_block_row), .ld_block_col(ld_block_col), .ld_allowed_ops(ld_allowed_ops),
    .ld_completed_ops(ld_completed_ops), .ld_encoding(ld_encoding),
    .ld_block_valid(ld_block_valid), .ld_in_operation(ld_in_operation),
    .stage_a_ready(stage_a_ready), .stage_w_ready(stage_w_ready),
    .stage_a_fault(stage_a_fault), .stage_w_fault(stage_w_fault),
    .stage_a_bvalid(stage_a_bvalid), .stage_w_bvalid(stage_w_bvalid),
    .stage_a_inop(stage_a_inop), .stage_w_inop(stage_w_inop),
    .stage_a_epoch(stage_a_epoch), .stage_w_epoch(stage_w_epoch),
    .stage_a_layer(stage_a_layer), .stage_w_layer(stage_w_layer),
    .stage_a_matrix(stage_a_matrix), .stage_w_matrix(stage_w_matrix),
    .stage_a_row(stage_a_row), .stage_w_row(stage_w_row),
    .stage_a_col(stage_a_col), .stage_w_col(stage_w_col),
    .stage_a_allowed(stage_a_allowed), .stage_w_allowed(stage_w_allowed),
    .stage_a_completed(stage_a_completed), .stage_w_completed(stage_w_completed),
    .stage_a_encoding(stage_a_encoding), .stage_w_encoding(stage_w_encoding),
    .stage_release(stage_release), .rd_stage(rd_stage), .rd_row_half(rd_row_half),
    .rd_col_half(rd_col_half), .a_k(a_k), .w_k(w_k), .a_values(a_values), .w_values(w_values),
    .c_hdr_valid(c_hdr_valid), .c_hdr_ready(c_hdr_ready), .c_hdr_exists(c_hdr_exists),
    .c_hdr_bvalid(c_hdr_bvalid), .c_hdr_inop(c_hdr_inop), .c_hdr_error(c_hdr_error),
    .c_hdr_code(c_hdr_code), .c_hdr_epoch(c_hdr_epoch), .c_hdr_layer(c_hdr_layer),
    .c_hdr_matrix(c_hdr_matrix), .c_hdr_row(c_hdr_row), .c_hdr_col(c_hdr_col),
    .c_hdr_allowed(c_hdr_allowed), .c_hdr_completed(c_hdr_completed),
    .c_hdr_encoding(c_hdr_encoding),
    .c_ld_valid(c_ld_valid), .c_ld_ready(c_ld_ready), .c_ld_data(c_ld_data),
    .c_ld_index(c_ld_index), .c_ld_last(c_ld_last), .c_ld_done(c_ld_done),
    .c_ld_error(c_ld_error), .c_ld_code(c_ld_code),
    .cseg_valid(1'b0), .cseg_ready(), .cseg_address(32'd0), .cseg_epoch(32'd0),
    .cseg_layer(16'd0), .cseg_matrix(16'd0), .cseg_row(16'd0), .cseg_col(16'd0),
    .cseg_beats(16'd0),
    .cval_valid(1'b0), .cval_ready(), .cval_data(192'd0), .cval_last(1'b0),
    .cwr_pending(sto_cwr_pending), .cwr_idle(sto_cwr_idle), .cwr_done(sto_cwr_done),
    .cwr_error(sto_cwr_error), .cwr_code(sto_cwr_code),
    .rd_req_valid(rd_req_valid), .rd_req_ready(rd_req_ready),
    .rd_req_address(rd_req_addr), .rd_req_beats(rd_req_beats),
    .rd_valid(rd_valid), .rd_ready(rd_ready), .rd_data(rd_data),
    .rd_index(rd_index), .rd_done(rd_done), .rd_error(rd_error),
    .wr_req_valid(sto_wr_req_valid), .wr_req_ready(1'b0),
    .wr_req_address(sto_wr_req_addr), .wr_req_beats(sto_wr_req_beats),
    .wr_valid(sto_wr_valid), .wr_ready(1'b0), .wr_data(sto_wr_data),
    .wr_strobe(sto_wr_strobe), .wr_done(1'b0), .wr_error(1'b0),
    .idle(storage_idle), .drain_done(storage_drain_done),
    .read_blocks(), .write_segments(), .read_bytes(), .write_bytes(),
    .error_count(), .read_wait_cycles(), .write_wait_cycles(),
    .ov_same_cycle(), .rd_active_wr_active_cycles(),
    .rd_active(storage_rd_active), .wr_active(storage_wr_active),
    .dbg_rstate(), .dbg_wwait()
  );

  // ---------------------------------------------------------------------
  // framer -> FIFO
  // ---------------------------------------------------------------------
  fusion_c48_framer #(
    .TILE_BEATS(256), .SEG_BEATS(4), .SEG_PER_TILE(64), .TAG_WIDTH(16)
  ) u_framer (
    .clk(clk), .rst_n(!reset), .flush(reset), .start(start),
    .cseg_valid(cseg_valid), .cseg_ready(cseg_ready),
    .cseg_row(cseg_row), .cseg_col(cseg_col),
    .cval_valid(cval_valid), .cval_ready(cval_ready), .cval_data(cval_data),
    .cval_last(cval_last),
    .out_valid(framed_valid), .out_ready(framed_ready), .out_data(framed_data),
    .out_tag(framed_tag), .out_last(framed_last),
    .tile_row(tile_row), .tile_col(tile_col),
    .beat_in_tile(), .seg_in_tile(), .tile_count(frame_tile_count),
    .cseg_count(frame_cseg_count),
    .err_sticky(frame_err), .err_code(frame_err_code)
  );

  fusion_c48_fifo #(
    .DEPTH(BRIDGE_FIFO), .TAG_WIDTH(16)
  ) u_fifo (
    .clk(clk), .rst_n(!reset), .flush(flush),
    .in_valid(framed_valid), .in_ready(framed_ready), .in_data(framed_data),
    .in_tag(framed_tag), .in_last(framed_last),
    .out_valid(fifo_valid), .out_ready(fifo_ready), .out_data(fifo_data),
    .out_tag(fifo_tag), .out_last(fifo_last),
    .occupancy(fifo_occ), .high_water(fifo_high), .credit(fifo_credit),
    .overflow_sticky(fifo_overflow), .in_beats(fifo_in_beats),
    .out_beats(fifo_out_beats), .stall_cycles(fifo_stalls)
  );

  // ---------------------------------------------------------------------
  // epilogue (unmodified primary_stream_fix candidate)
  // ---------------------------------------------------------------------
  epilogue_stream_engine_v024 #(.TAG_WIDTH(16)) u_epilogue (
    .clk(clk), .rst_n(!reset), .param_rst_n(param_rst_n), .abort(flush),
    .cfg_valid(ep_cfg_valid), .cfg_ready(ep_cfg_ready),
    .cfg_fma_mode(cfg_fma_mode), .cfg_relu_en(cfg_relu_en),
    .cfg_spill_c48(1'b0), .cfg_spill_fp32(1'b0),
    .cfg_scale(cfg_scale), .cfg_bias(cfg_bias), .cfg_tag(16'h0001),
    .cfg_perchannel_en(cfg_perchannel_en),
    .param_wr_valid(param_wr_valid), .param_wr_ready(param_wr_ready),
    .param_wr_addr(param_wr_addr), .param_wr_data(param_wr_data),
    .cval_valid(fifo_valid), .cval_ready(fifo_ready), .cval_data(fifo_data),
    .cval_tag(fifo_tag), .cval_last(fifo_last),
    .a16_valid(ep_a16_valid), .a16_ready(1'b1), .a16_data(ep_a16_data),
    .a16_packed(ep_packed), .a16_packed_valid(ep_packed_valid),
    .a16_packed_ready(ep_packed_ready), .a16_packed_last(ep_packed_last),
    .a16_packed_tag(ep_packed_tag), .a16_tag(ep_a16_tag), .a16_last(ep_a16_last),
    .spill_valid(), .spill_ready(1'b1), .spill_data(), .spill_tag(), .spill_last(),
    .stat_c48_beats_in(ep_c48_in), .stat_a16_beats_out(ep_a16_out),
    .stat_spill_beats(ep_spill_beats), .stat_ddr_bytes_saved(ep_saved)
  );

  // ---------------------------------------------------------------------
  // block buffer (row-major reorder) -> writer
  // ---------------------------------------------------------------------
  assign ep_packed_ready = buf_wr_ready;

  fusion_a16_blockbuf #(.WORDS(A16_WORDS)) u_blockbuf (
    .clk(clk), .rst_n(!reset), .flush(reset), .start(start),
    .wr_valid(ep_packed_valid), .wr_ready(buf_wr_ready), .wr_data(ep_packed),
    .wr_tag(ep_packed_tag[6:0]), .addr_mode(1'b0),
    .cfg_words(8'd128), .drain_start(writer_start),
    .full(buf_full), .drain_busy(buf_drain_busy), .drain_done(buf_drain_done),
    .rd_ready(buf_rd_ready), .rd_valid(buf_rd_valid), .rd_data(buf_rd_data),
    .rd_last(buf_rd_last),
    .stat_words_written(buf_words_written), .stat_words_read(buf_words_read),
    .err_duplicate(buf_dup_err), .err_code(buf_err_code)
  );

  fusion_a16_writer u_writer (
    .clk(clk), .rst_n(!reset), .flush(reset | fatal_other),
    .start(writer_start), .base_addr(tile_base), .words(8'd128),
    .last_bytes(5'd16),
    .buf_rd_valid(buf_rd_valid), .buf_rd_ready(buf_rd_ready),
    .buf_rd_data(buf_rd_data), .buf_rd_last(buf_rd_last),
    .dma_req_valid(wdma_req_valid), .dma_req_ready(wdma_req_ready),
    .dma_req_addr(wdma_req_addr), .dma_req_beats(wdma_req_beats),
    .dma_wr_valid(wdma_wr_valid), .dma_wr_ready(wdma_wr_ready),
    .dma_wr_data(wdma_wr_data), .dma_wr_strb(wdma_wr_strb),
    .dma_done(wdma_done), .dma_error(wdma_error),
    .busy(writer_busy), .done(writer_done), .fault(writer_fault),
    .error_code(writer_err_code),
    .stat_beats(writer_beats), .stat_bytes(writer_bytes),
    .stat_drain_cycles(writer_drain_cycles),
    .cyc_last_w(writer_last_w_cycle), .cyc_dma_done(writer_done_cycle)
  );

  // ---------------------------------------------------------------------
  // read DMA (A/W/C loads) and write DMA (A16 only)
  // ---------------------------------------------------------------------
  axi_dma_v020_multi_v2 #(.MAX_OUT(MAX_OUT), .FIFO_BEATS(FIFO_BEATS)) u_rdma (
    .clk(clk), .rst_n(!reset),
    .request_valid(rd_req_valid), .request_ready(rd_req_ready),
    .request_write(1'b0), .request_address(rd_req_addr), .request_beats(rd_req_beats),
    .read_valid(rd_valid), .read_ready(rd_ready), .read_data(rd_data),
    .read_index(rd_index),
    .write_valid(1'b0), .write_ready(), .write_data(128'd0), .write_strobe(16'd0),
    .write_index(),
    .done(rd_done), .error(rd_error), .read_bytes(rd_read_bytes), .write_bytes(),
    .read_bursts(rd_read_bursts), .write_bursts(),
    .ar_outstanding_max(rd_ar_outstanding_max), .b_outstanding_max(),
    .read_bubble_cycles(), .write_bubble_cycles(),
    .read_fifo_high(),
    .m_axi_araddr(rd_m_axi_araddr), .m_axi_arlen(rd_m_axi_arlen),
    .m_axi_arsize(rd_m_axi_arsize), .m_axi_arburst(rd_m_axi_arburst),
    .m_axi_arcache(), .m_axi_arprot(),
    .m_axi_arvalid(rd_m_axi_arvalid), .m_axi_arready(rd_m_axi_arready),
    .m_axi_rdata(rd_m_axi_rdata), .m_axi_rresp(rd_m_axi_rresp),
    .m_axi_rlast(rd_m_axi_rlast), .m_axi_rvalid(rd_m_axi_rvalid),
    .m_axi_rready(rd_m_axi_rready),
    .m_axi_awaddr(), .m_axi_awlen(), .m_axi_awsize(), .m_axi_awburst(),
    .m_axi_awcache(), .m_axi_awprot(), .m_axi_awvalid(), .m_axi_awready(1'b0),
    .m_axi_wdata(), .m_axi_wstrb(), .m_axi_wlast(), .m_axi_wvalid(),
    .m_axi_wready(1'b0), .m_axi_bresp(2'd0), .m_axi_bvalid(1'b0), .m_axi_bready()
  );

  axi_dma_v020_multi_v2 #(.MAX_OUT(MAX_OUT), .FIFO_BEATS(FIFO_BEATS)) u_wdma (
    .clk(clk), .rst_n(!reset),
    .request_valid(wdma_req_valid), .request_ready(wdma_req_ready),
    .request_write(1'b1), .request_address(wdma_req_addr),
    .request_beats(wdma_req_beats),
    .read_valid(), .read_ready(1'b1), .read_data(), .read_index(),
    .write_valid(wdma_wr_valid), .write_ready(wdma_wr_ready),
    .write_data(wdma_wr_data), .write_strobe(wdma_wr_strb), .write_index(),
    .done(wdma_done), .error(wdma_error), .read_bytes(), .write_bytes(wr_write_bytes),
    .read_bursts(), .write_bursts(wr_write_bursts),
    .ar_outstanding_max(), .b_outstanding_max(wr_b_outstanding_max),
    .read_bubble_cycles(), .write_bubble_cycles(), .read_fifo_high(),
    .m_axi_araddr(), .m_axi_arlen(), .m_axi_arsize(), .m_axi_arburst(),
    .m_axi_arcache(), .m_axi_arprot(), .m_axi_arvalid(), .m_axi_arready(1'b0),
    .m_axi_rdata(128'd0), .m_axi_rresp(2'd0), .m_axi_rlast(1'b0),
    .m_axi_rvalid(1'b0), .m_axi_rready(),
    .m_axi_awaddr(wr_m_axi_awaddr), .m_axi_awlen(wr_m_axi_awlen),
    .m_axi_awsize(wr_m_axi_awsize), .m_axi_awburst(wr_m_axi_awburst),
    .m_axi_awcache(), .m_axi_awprot(),
    .m_axi_awvalid(wr_m_axi_awvalid), .m_axi_awready(wr_m_axi_awready),
    .m_axi_wdata(wr_m_axi_wdata), .m_axi_wstrb(wr_m_axi_wstrb),
    .m_axi_wlast(wr_m_axi_wlast), .m_axi_wvalid(wr_m_axi_wvalid),
    .m_axi_wready(wr_m_axi_wready),
    .m_axi_bresp(wr_m_axi_bresp), .m_axi_bvalid(wr_m_axi_bvalid),
    .m_axi_bready(wr_m_axi_bready)
  );

  // ---------------------------------------------------------------------
  // status
  // ---------------------------------------------------------------------
  assign busy  = busy_engine || writer_busy || buf_full || buf_drain_busy;
  assign done  = done_engine && !fault && !writer_busy && !buf_drain_busy && !tile_written;
  assign fault = fault_engine || fatal;

  assign error_code = fault_engine ? error_engine :
                      frame_err    ? frame_err_code :
                      buf_dup_err  ? buf_err_code :
                      fifo_overflow? 8'h54 :
                      writer_fault ? writer_err_code : 8'h00;

  assign stat_c48_beats        = fifo_in_beats;
  assign stat_a16_words        = buf_words_read;
  assign stat_a16_bytes        = a16_bytes_acc;
  assign stat_fifo_high        = {24'd0, fifo_high};
  assign stat_fifo_stalls      = fifo_stalls;
  assign stat_c48_ddr_bytes    = 32'd0; // structural: no C48 write port wired
  assign stat_drain_cycles     = writer_drain_cycles;
  assign stat_last_w_cycle     = writer_last_w_cycle;
  assign stat_dma_done_cycle   = writer_done_cycle;
  assign stat_tiles            = frame_tile_count[15:0];

endmodule
