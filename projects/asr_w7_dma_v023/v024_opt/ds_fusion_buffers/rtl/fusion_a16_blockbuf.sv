`timescale 1ns/1ps
// fusion_a16_blockbuf.sv
// 128 x 128-bit (2 KiB) on-chip A16 tile buffer.
//
// The epilogue packer emits one 128-bit word per two C48 beats.  For the live
// matrix stream the words arrive in quadrant-major order, so each word carries
// its row-major destination index on tag[6:0].  This buffer scatters the words
// into a row-major tile, then drains them in ascending order.  No C48 or
// intermediate FP32 ever goes to DDR.
//
// Address modes:
//   ADDR_TAG    : write address = wr_tag[6:0] (fused reorder path)
//   ADDR_LINEAR : write address = internal counter (unfused row-major readback
//                 / odd-tail unit tests)
//
// The buffer accepts one word per cycle, refuses a duplicate write address,
// and reports `full` only after `cfg_words` distinct words were written.
// Draining starts when the top asserts `drain_start` (normally on full) and
// completes after the last word handshake.  The memory is never rewritten
// while draining; the next tile waits for `drain_done`.
module fusion_a16_blockbuf #(
  parameter integer WORDS = 128
)(
  input  wire         clk,
  input  wire         rst_n,
  input  wire         flush,
  input  wire         start,          // clear for a new tile

  input  wire         wr_valid,
  output wire         wr_ready,
  input  wire [127:0] wr_data,
  input  wire [6:0]   wr_tag,
  input  wire         addr_mode,      // 0: tag, 1: linear

  input  wire [7:0]   cfg_words,      // 1..128 valid words per tile
  input  wire         drain_start,

  output wire         full,
  output wire         drain_busy,
  output reg          drain_done,
  input  wire         rd_ready,
  output wire         rd_valid,
  output wire [127:0] rd_data,
  output wire         rd_last,

  output reg  [31:0]  stat_words_written,
  output reg  [31:0]  stat_words_read,
  output reg          err_duplicate,
  output reg  [7:0]   err_code
);
  localparam [7:0] ERR_DUP = 8'h61;
  localparam [7:0] ERR_CNT = 8'h62;

  reg [127:0] mem [0:WORDS-1];
  reg [WORDS-1:0] seen;
  reg [7:0] linear_ptr;
  reg [7:0] seen_count;
  reg [7:0] rd_ptr;
  reg filling;
  reg draining;
  reg full_r;

  wire [6:0] waddr = addr_mode ? linear_ptr[6:0] : wr_tag;
  wire       dup   = seen[waddr];
  wire       can_wr = filling && (seen_count < cfg_words) && !dup && !flush;
  assign wr_ready = can_wr;

  assign full = full_r && !draining;

  wire wr_fire = wr_valid && wr_ready;
  wire rd_fire = rd_valid && rd_ready;

  assign drain_busy = draining;
  assign rd_valid = draining && (rd_ptr < cfg_words);
  assign rd_data  = mem[rd_ptr];
  assign rd_last  = draining && (rd_ptr + 8'd1 == cfg_words);

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      seen <= {WORDS{1'b0}};
      linear_ptr <= 8'd0;
      seen_count <= 8'd0;
      rd_ptr <= 8'd0;
      filling <= 1'b0;
      draining <= 1'b0;
      full_r <= 1'b0;
      drain_done <= 1'b0;
      stat_words_written <= 32'd0;
      stat_words_read <= 32'd0;
      err_duplicate <= 1'b0;
      err_code <= 8'd0;
    end else if (flush || start) begin
      seen <= {WORDS{1'b0}};
      linear_ptr <= 8'd0;
      seen_count <= 8'd0;
      rd_ptr <= 8'd0;
      filling <= 1'b1;
      draining <= 1'b0;
      full_r <= 1'b0;
      drain_done <= 1'b0;
      if (start) begin
        stat_words_written <= 32'd0;
        stat_words_read <= 32'd0;
        err_duplicate <= 1'b0;
        err_code <= 8'd0;
      end
    end else begin
      drain_done <= 1'b0;

      if (wr_fire) begin
        mem[waddr] <= wr_data;
        seen[waddr] <= 1'b1;
        seen_count <= seen_count + 8'd1;
        linear_ptr <= linear_ptr + 8'd1;
        stat_words_written <= stat_words_written + 32'd1;
        if (seen_count + 8'd1 == cfg_words) begin
          full_r <= 1'b1;
          filling <= 1'b0;
        end
      end
      if (wr_valid && !wr_ready && dup && filling) begin
        err_duplicate <= 1'b1;
        err_code <= ERR_DUP;
      end

      if (drain_start && full_r && !draining) draining <= 1'b1;

      if (rd_fire) begin
        rd_ptr <= rd_ptr + 8'd1;
        stat_words_read <= stat_words_read + 32'd1;
        if (rd_ptr + 8'd1 == cfg_words) begin
          draining <= 1'b0;
          full_r <= 1'b0;
          drain_done <= 1'b1;
          filling <= 1'b1;
          seen <= {WORDS{1'b0}};
          linear_ptr <= 8'd0;
          seen_count <= 8'd0;
          rd_ptr <= 8'd0;
        end
      end

      if (cfg_words == 8'd0 || cfg_words > WORDS) begin
        err_code <= ERR_CNT;
      end
    end
  end
endmodule
