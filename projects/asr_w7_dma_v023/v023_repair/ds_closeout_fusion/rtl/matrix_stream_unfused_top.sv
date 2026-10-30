`timescale 1ns/1ps
// matrix_stream_unfused_top.sv
// Real unfused baseline for the same matrix -> epilogue -> A16 workload:
//
//   matrix_p2_cluster_v2 (unmodified ds_matrix candidate)
//        |  C48 stream -> block_storage_stream_v2 -> C48 posted write DMA
//        v  DDR C48 tensor (6 bytes x 1024 per tile)
//   read-back DMA (C48 tensor, 6 KiB per tile)
//        v
//   fusion_c48_gearbox (3 x 128-bit beats -> 2 x 192-bit groups)
//        v
//   epilogue_stream_engine_v023 -> fusion_a16_blockbuf (linear)
//        v
//   fusion_a16_writer -> axi_dma_v020_multi_v2 (A16 write master)
//
// This path really performs the C48 DDR write and the C48 DDR read-back.  It
// is the traffic/cycle comparison point for the fused top; it is not a claim
// that a store-and-reload schedule is the best possible unfused schedule.
module matrix_stream_unfused_top #(
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
  parameter integer A16_WORDS   = 128
)(
  input  wire         clk,
  input  wire         reset,
  input  wire         start,

  input  wire [31:0]  cfg_a_base,
  input  wire [31:0]  cfg_b_base,
  input  wire [31:0]  cfg_c48_base,
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

  input  wire [1:0]   cfg_fma_mode,
  input  wire         cfg_relu_en,
  input  wire [31:0]  cfg_scale,
  input  wire [31:0]  cfg_bias,

  input  wire         param_wr_valid,
  output wire         param_wr_ready,
  input  wire [7:0]   param_wr_addr,
  input  wire [31:0]  param_wr_data,

  output wire         busy,
  output wire         done,
  output wire         fault,
  output wire [7:0]   error_code,
  output wire [63:0]  matrix_cycles,
  output wire [15:0]  stat_tiles,

  output wire [31:0]  stat_c48_written_bytes,
  output wire [31:0]  stat_c48_readback_bytes,
  output wire [31:0]  stat_a16_bytes,
  output wire [31:0]  stat_drain_cycles,

  // matrix A/W read master
  output wire [39:0]  m_rd_araddr,
  output wire [7:0]   m_rd_arlen,
  output wire [2:0]   m_rd_arsize,
  output wire [1:0]   m_rd_arburst,
  output wire         m_rd_arvalid,
  input  wire         m_rd_arready,
  input  wire [127:0] m_rd_rdata,
  input  wire [1:0]   m_rd_rresp,
  input  wire         m_rd_rlast,
  input  wire         m_rd_rvalid,
  output wire         m_rd_rready,

  // matrix C48 write master
  output wire [39:0]  m_wr_awaddr,
  output wire [7:0]   m_wr_awlen,
  output wire [2:0]   m_wr_awsize,
  output wire [1:0]   m_wr_awburst,
  output wire         m_wr_awvalid,
  input  wire         m_wr_awready,
  output wire [127:0] m_wr_wdata,
  output wire [15:0]  m_wr_wstrb,
  output wire         m_wr_wlast,
  output wire         m_wr_wvalid,
  input  wire         m_wr_wready,
  input  wire [1:0]   m_wr_bresp,
  input  wire         m_wr_bvalid,
  output wire         m_wr_bready,

  // C48 read-back master
  output wire [39:0]  rb_araddr,
  output wire [7:0]   rb_arlen,
  output wire [2:0]   rb_arsize,
  output wire [1:0]   rb_arburst,
  output wire         rb_arvalid,
  input  wire         rb_arready,
  input  wire [127:0] rb_rdata,
  input  wire [1:0]   rb_rresp,
  input  wire         rb_rlast,
  input  wire         rb_rvalid,
  output wire         rb_rready,

  // A16 write master
  output wire [39:0]  a16_awaddr,
  output wire [7:0]   a16_awlen,
  output wire [2:0]   a16_awsize,
  output wire [1:0]   a16_awburst,
  output wire         a16_awvalid,
  input  wire         a16_awready,
  output wire [127:0] a16_wdata,
  output wire [15:0]  a16_wstrb,
  output wire         a16_wlast,
  output wire         a16_wvalid,
  input  wire         a16_wready,
  input  wire [1:0]   a16_bresp,
  input  wire         a16_bvalid,
  output wire         a16_bready
);
  // ---------------------------------------------------------------------
  // matrix cluster (unmodified; real C48 DDR write path)
  // ---------------------------------------------------------------------
  wire cluster_busy, cluster_done, cluster_fault;
  wire [7:0] cluster_code;
  wire [63:0] cluster_cycles;
  wire [31:0] c_compute, c_rdblk, c_wrblk, c_hits, c_miss, c_prehit, c_prewait;
  wire [31:0] c_ovrd, c_ovwr, c_cgrp, c_ccyc, c_craw;
  wire [7:0]  c_pedrain, c_adrain;
  wire [31:0] c_rd_armax, c_rd_bytes, c_rd_bursts, c_wr_bmax, c_wr_bytes, c_wr_bursts;
  wire [63:0] c_rd_fifo_high;
  wire [49151:0] c_result_data;

  matrix_p2_cluster_v2 #(
    .SLOTS(SLOTS), .MAX_DIM(MAX_DIM), .PIPE_STAGES(PIPE_STAGES),
    .ACCUM_MODE(ACCUM_MODE), .CPA_PIPE(CPA_PIPE),
    .MAX_OUT(MAX_OUT), .FIFO_BEATS(FIFO_BEATS),
    .ARENA_BASE(ARENA_BASE), .ARENA_END(ARENA_END), .WR_OUT(WR_OUT)
  ) u_cluster (
    .clk(clk), .reset(reset), .start(start),
    .cfg_a_base(cfg_a_base), .cfg_b_base(cfg_b_base), .cfg_c_base(cfg_c48_base),
    .cfg_epoch(cfg_epoch), .cfg_m(cfg_m), .cfg_n(cfg_n), .cfg_k(cfg_k),
    .cfg_layer(cfg_layer), .cfg_a_id(cfg_a_id), .cfg_b_id(cfg_b_id), .cfg_c_id(cfg_c_id),
    .cfg_target_high(cfg_target_high), .cfg_allowed_ops(cfg_allowed_ops),
    .cfg_requested_op(cfg_requested_op), .cfg_positions(cfg_positions), .cfg_clip(cfg_clip),
    .cfg_c_valid(cfg_c_valid), .cfg_c_completed(cfg_c_completed),
    .param_end(param_end),
    .busy(cluster_busy), .done(cluster_done), .fault(cluster_fault),
    .error_code(cluster_code), .task_cycles(cluster_cycles),
    .compute_cycles(c_compute), .read_blocks(c_rdblk), .write_blocks(c_wrblk),
    .cache_hits(c_hits), .cache_misses(c_miss),
    .prefetch_hits(c_prehit), .prefetch_wait_cycles(c_prewait),
    .overlap_compute_read_cycles(c_ovrd), .overlap_compute_write_cycles(c_ovwr),
    .c_collect_groups(c_cgrp), .c_collect_cycles(c_ccyc), .c_raw_bypass_cycles(c_craw),
    .pe_drain_cycles(c_pedrain), .array_drain_cycles(c_adrain),
    .result_valid(), .result_ready(1'b1),
    .result_cache_address(), .result_epoch(), .result_target_low(),
    .result_layer(), .result_matrix(), .result_block_row(), .result_block_col(),
    .result_op_tag(), .result_data(c_result_data), .result_block_valid(),
    .result_in_operation(), .result_allowed_ops(), .result_completed_ops(),
    .rd_m_axi_araddr(m_rd_araddr), .rd_m_axi_arlen(m_rd_arlen),
    .rd_m_axi_arsize(m_rd_arsize), .rd_m_axi_arburst(m_rd_arburst),
    .rd_m_axi_arvalid(m_rd_arvalid), .rd_m_axi_arready(m_rd_arready),
    .rd_m_axi_rdata(m_rd_rdata), .rd_m_axi_rresp(m_rd_rresp),
    .rd_m_axi_rlast(m_rd_rlast), .rd_m_axi_rvalid(m_rd_rvalid),
    .rd_m_axi_rready(m_rd_rready),
    .wr_m_axi_awaddr(m_wr_awaddr), .wr_m_axi_awlen(m_wr_awlen),
    .wr_m_axi_awsize(m_wr_awsize), .wr_m_axi_awburst(m_wr_awburst),
    .wr_m_axi_awvalid(m_wr_awvalid), .wr_m_axi_awready(m_wr_awready),
    .wr_m_axi_wdata(m_wr_wdata), .wr_m_axi_wstrb(m_wr_wstrb),
    .wr_m_axi_wlast(m_wr_wlast), .wr_m_axi_wvalid(m_wr_wvalid),
    .wr_m_axi_wready(m_wr_wready),
    .wr_m_axi_bresp(m_wr_bresp), .wr_m_axi_bvalid(m_wr_bvalid),
    .wr_m_axi_bready(m_wr_bready),
    .rd_ar_outstanding_max(c_rd_armax), .rd_read_bytes(c_rd_bytes),
    .rd_read_bursts(c_rd_bursts), .wr_b_outstanding_max(c_wr_bmax),
    .wr_write_bytes(c_wr_bytes), .wr_write_bursts(c_wr_bursts),
    .rd_read_fifo_high(c_rd_fifo_high)
  );

  // ---------------------------------------------------------------------
  // readback sequencer + gearbox + epilogue + block buffer + writer
  // ---------------------------------------------------------------------
  localparam [2:0] S_IDLE     = 3'd0;
  localparam [2:0] S_NEXT     = 3'd1;
  localparam [2:0] S_RBREQ    = 3'd2;
  localparam [2:0] S_RUN      = 3'd3;
  localparam [2:0] S_NEXT_TILE= 3'd4;
  localparam [2:0] S_FIN      = 3'd5;
  localparam [2:0] S_FAIL     = 3'd6;

  reg [2:0]  state;
  reg [15:0] tile_idx;
  reg [15:0] ntiles;
  reg [31:0] cycle_count;
  reg [31:0] a16_bytes_acc;

  wire [15:0] blocks_r = (cfg_m + 16'd31) >> 5;
  wire [15:0] blocks_c = (cfg_n + 16'd31) >> 5;
  wire [15:0] ntiles_w = blocks_r * blocks_c;

  reg         rb_req_valid;
  wire        rb_req_ready;
  reg  [31:0] rb_req_addr;
  wire        rb_valid, rb_ready;
  wire [127:0] rb_data;
  wire [15:0] rb_index;
  wire        rb_done, rb_error;

  wire        gb_valid, gb_ready, gb_last, gb_done;
  wire [191:0] gb_data;
  wire [8:0]  gb_groups;
  wire [31:0] gb_beats, gb_groups_out;

  wire        ep_cfg_ready, ep_cfg_valid;
  wire        ep_a16_valid, ep_a16_last;
  wire [63:0] ep_a16_data;
  wire        ep_packed_valid, ep_packed_ready, ep_packed_last;
  wire [127:0] ep_packed;
  wire [15:0] ep_a16_tag, ep_packed_tag;
  wire [31:0] ep_c48_in, ep_a16_out, ep_spill, ep_saved;

  wire        buf_full, buf_drain_busy, buf_rd_valid, buf_rd_last, buf_wr_ready;
  wire        buf_rd_ready;
  wire [127:0] buf_rd_data;
  wire        buf_dup_err;
  wire [7:0]  buf_err_code;
  wire [31:0] buf_words_written, buf_words_read;

  reg         writer_started;
  reg         gb_start;
  wire        writer_start, writer_busy, writer_done, writer_fault;
  wire [7:0]  writer_err_code;
  wire [31:0] writer_beats, writer_bytes, writer_drain;
  wire [31:0] writer_last_w, writer_dma_done;
  wire        wdma_req_valid, wdma_req_ready, wdma_wr_valid, wdma_wr_ready;
  wire [31:0] wdma_req_addr;
  wire [15:0] wdma_req_beats, wdma_wr_strb;
  wire [127:0] wdma_wr_data;
  wire        wdma_done, wdma_error;

  wire        fatal = buf_dup_err | writer_fault | rb_error;
  wire        flush = reset | fatal;
  reg         cfg_pending;

  // epilogue config accepted once, before the first readback.
  always @(posedge clk or posedge reset) begin
    if (reset) cfg_pending <= 1'b0;
    else if (start) cfg_pending <= 1'b1;
    else if (cfg_pending && ep_cfg_ready) cfg_pending <= 1'b0;
  end
  assign ep_cfg_valid = cfg_pending;

  // sequencer
  always @(posedge clk or posedge reset) begin
    if (reset) begin
      state <= S_IDLE;
      tile_idx <= 16'd0;
      ntiles <= 16'd0;
      cycle_count <= 32'd0;
      rb_req_valid <= 1'b0;
      rb_req_addr <= 32'd0;
      writer_started <= 1'b0;
      gb_start <= 1'b0;
    end else begin
      gb_start <= 1'b0;
      cycle_count <= cycle_count + 32'd1;
      case (state)
        S_IDLE: begin
          if (start) begin
            tile_idx <= 16'd0;
            ntiles <= ntiles_w;
            writer_started <= 1'b0;
            state <= S_NEXT;
          end
        end
        S_NEXT: begin
          // wait for the matrix's C48 write path (and all B responses) to drain
          if (cluster_done && !cluster_fault) begin
            if (tile_idx >= ntiles) state <= S_FIN;
            else begin
              rb_req_valid <= 1'b1;
              rb_req_addr  <= cfg_c48_base + ({16'd0, tile_idx} * 32'd6144);
              writer_started <= 1'b0;
              gb_start <= 1'b1;
              state <= S_RBREQ;
            end
          end else if (cluster_fault) state <= S_FAIL;
        end
        S_RBREQ: begin
          if (rb_req_valid && rb_req_ready) begin
            rb_req_valid <= 1'b0;
            state <= S_RUN;
          end
        end
        S_RUN: begin
          if (fatal) state <= S_FAIL;
          else if (writer_done) begin
            writer_started <= 1'b0;
            tile_idx <= tile_idx + 16'd1;
            state <= S_NEXT;
          end
        end
        S_NEXT_TILE: state <= S_NEXT;
        S_FIN: ;
        S_FAIL: ;
        default: state <= S_IDLE;
      endcase
      if (buf_full && !writer_started && !writer_done && (state == S_RUN)) begin
        writer_started <= 1'b1;
      end
      if (flush) begin
        rb_req_valid <= 1'b0;
      end
    end
  end

  assign writer_start = buf_full && !writer_started && (state == S_RUN);

  // readback DMA
  axi_dma_v020_multi_v2 #(.MAX_OUT(MAX_OUT), .FIFO_BEATS(FIFO_BEATS)) u_rbdma (
    .clk(clk), .rst_n(!reset),
    .request_valid(rb_req_valid), .request_ready(rb_req_ready),
    .request_write(1'b0), .request_address(rb_req_addr), .request_beats(16'd384),
    .read_valid(rb_valid), .read_ready(rb_ready), .read_data(rb_data),
    .read_index(rb_index),
    .write_valid(1'b0), .write_ready(), .write_data(128'd0), .write_strobe(16'd0),
    .write_index(),
    .done(rb_done), .error(rb_error), .read_bytes(), .write_bytes(),
    .read_bursts(), .write_bursts(), .ar_outstanding_max(), .b_outstanding_max(),
    .read_bubble_cycles(), .write_bubble_cycles(), .read_fifo_high(),
    .m_axi_araddr(rb_araddr), .m_axi_arlen(rb_arlen), .m_axi_arsize(rb_arsize),
    .m_axi_arburst(rb_arburst), .m_axi_arcache(), .m_axi_arprot(),
    .m_axi_arvalid(rb_arvalid), .m_axi_arready(rb_arready),
    .m_axi_rdata(rb_rdata), .m_axi_rresp(rb_rresp), .m_axi_rlast(rb_rlast),
    .m_axi_rvalid(rb_rvalid), .m_axi_rready(rb_rready),
    .m_axi_awaddr(), .m_axi_awlen(), .m_axi_awsize(), .m_axi_awburst(),
    .m_axi_awcache(), .m_axi_awprot(), .m_axi_awvalid(), .m_axi_awready(1'b0),
    .m_axi_wdata(), .m_axi_wstrb(), .m_axi_wlast(), .m_axi_wvalid(),
    .m_axi_wready(1'b0), .m_axi_bresp(2'd0), .m_axi_bvalid(1'b0), .m_axi_bready()
  );

  fusion_c48_gearbox #(.GROUPS(256)) u_gearbox (
    .clk(clk), .rst_n(!reset), .flush(flush), .start(start | gb_start),
    .in_valid(rb_valid), .in_ready(rb_ready), .in_data(rb_data),
    .out_valid(gb_valid), .out_ready(gb_ready), .out_data(gb_data),
    .out_last(gb_last), .group_count(gb_groups), .done(gb_done),
    .stat_beats_in(gb_beats), .stat_groups_out(gb_groups_out)
  );

  epilogue_stream_engine_v023 #(.TAG_WIDTH(16)) u_epilogue (
    .clk(clk), .rst_n(!reset), .abort(flush),
    .cfg_valid(ep_cfg_valid), .cfg_ready(ep_cfg_ready),
    .cfg_fma_mode(cfg_fma_mode), .cfg_relu_en(cfg_relu_en),
    .cfg_spill_c48(1'b0), .cfg_spill_fp32(1'b0),
    .cfg_scale(cfg_scale), .cfg_bias(cfg_bias), .cfg_tag(16'h0001),
    .param_wr_valid(param_wr_valid), .param_wr_ready(param_wr_ready),
    .param_wr_addr(param_wr_addr), .param_wr_data(param_wr_data),
    .cval_valid(gb_valid), .cval_ready(gb_ready), .cval_data(gb_data),
    .cval_tag(16'd0), .cval_last(gb_last),
    .a16_valid(ep_a16_valid), .a16_ready(1'b1), .a16_data(ep_a16_data),
    .a16_packed(ep_packed), .a16_packed_valid(ep_packed_valid),
    .a16_packed_ready(ep_packed_ready), .a16_packed_last(ep_packed_last),
    .a16_packed_tag(ep_packed_tag), .a16_tag(ep_a16_tag), .a16_last(ep_a16_last),
    .spill_valid(), .spill_ready(1'b1), .spill_data(), .spill_tag(), .spill_last(),
    .stat_c48_beats_in(ep_c48_in), .stat_a16_beats_out(ep_a16_out),
    .stat_spill_beats(ep_spill), .stat_ddr_bytes_saved(ep_saved)
  );

  assign ep_packed_ready = buf_wr_ready;

  fusion_a16_blockbuf #(.WORDS(A16_WORDS)) u_blockbuf (
    .clk(clk), .rst_n(!reset), .flush(flush), .start(start),
    .wr_valid(ep_packed_valid), .wr_ready(buf_wr_ready), .wr_data(ep_packed),
    .wr_tag(7'd0), .addr_mode(1'b1),
    .cfg_words(8'd128), .drain_start(writer_start),
    .full(buf_full), .drain_busy(buf_drain_busy), .drain_done(),
    .rd_ready(buf_rd_ready), .rd_valid(buf_rd_valid), .rd_data(buf_rd_data), .rd_last(buf_rd_last),
    .stat_words_written(buf_words_written), .stat_words_read(buf_words_read),
    .err_duplicate(buf_dup_err), .err_code(buf_err_code)
  );

  fusion_a16_writer u_writer (
    .clk(clk), .rst_n(!reset), .flush(reset | fatal),
    .start(writer_start),
    .base_addr(cfg_a16_base + ({16'd0, tile_idx} * 32'd2048)),
    .words(8'd128), .last_bytes(5'd16),
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
    .stat_drain_cycles(writer_drain),
    .cyc_last_w(writer_last_w), .cyc_dma_done(writer_dma_done)
  );

  // A16 write DMA
  axi_dma_v020_multi_v2 #(.MAX_OUT(MAX_OUT), .FIFO_BEATS(FIFO_BEATS)) u_a16dma (
    .clk(clk), .rst_n(!reset),
    .request_valid(wdma_req_valid), .request_ready(wdma_req_ready),
    .request_write(1'b1), .request_address(wdma_req_addr),
    .request_beats(wdma_req_beats),
    .read_valid(), .read_ready(1'b1), .read_data(), .read_index(),
    .write_valid(wdma_wr_valid), .write_ready(wdma_wr_ready),
    .write_data(wdma_wr_data), .write_strobe(wdma_wr_strb), .write_index(),
    .done(wdma_done), .error(wdma_error), .read_bytes(), .write_bytes(),
    .read_bursts(), .write_bursts(),
    .ar_outstanding_max(), .b_outstanding_max(),
    .read_bubble_cycles(), .write_bubble_cycles(), .read_fifo_high(),
    .m_axi_araddr(), .m_axi_arlen(), .m_axi_arsize(), .m_axi_arburst(),
    .m_axi_arcache(), .m_axi_arprot(), .m_axi_arvalid(), .m_axi_arready(1'b0),
    .m_axi_rdata(128'd0), .m_axi_rresp(2'd0), .m_axi_rlast(1'b0),
    .m_axi_rvalid(1'b0), .m_axi_rready(),
    .m_axi_awaddr(a16_awaddr), .m_axi_awlen(a16_awlen), .m_axi_awsize(a16_awsize),
    .m_axi_awburst(a16_awburst), .m_axi_awcache(), .m_axi_awprot(),
    .m_axi_awvalid(a16_awvalid), .m_axi_awready(a16_awready),
    .m_axi_wdata(a16_wdata), .m_axi_wstrb(a16_wstrb), .m_axi_wlast(a16_wlast),
    .m_axi_wvalid(a16_wvalid), .m_axi_wready(a16_wready),
    .m_axi_bresp(a16_bresp), .m_axi_bvalid(a16_bvalid), .m_axi_bready(a16_bready)
  );

  assign busy  = cluster_busy || writer_busy || (state != S_FIN && state != S_IDLE);
  assign done  = (state == S_FIN) && !fatal && !cluster_fault;
  assign fault = cluster_fault || fatal;
  assign error_code = cluster_fault ? cluster_code :
                      rb_error      ? 8'h81 :
                      writer_fault  ? writer_err_code :
                      buf_dup_err   ? buf_err_code : 8'h00;
  assign matrix_cycles = cluster_cycles;
  assign stat_tiles = ntiles;
  assign stat_c48_written_bytes = c_wr_bytes;
  assign stat_c48_readback_bytes = {16'd0, tile_idx} * 32'd6144;
  assign stat_a16_bytes = a16_bytes_acc;
  assign stat_drain_cycles = writer_drain;
endmodule
