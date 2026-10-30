`timescale 1ns/1ps
// fusion_a16_blockbuf_dual.sv
// Ping-pong 2 x (128 x 128-bit) = 4 KiB on-chip A16 tile buffer.
//
// Compared with the single 2 KiB fusion_a16_blockbuf, this module keeps two
// independent tile banks so tile t can drain through the A16 writer/DMA while
// tile t+1 is scattered by the epilogue.  It does not add any AXI port and it
// does not move any extra byte through DDR; the only added cost is one more
// 2 KiB on-chip bank plus the bank-select/state logic.
//
// Bank states: EMPTY -> FILLING -> FULL -> DRAINING -> EMPTY.
// The writer drains one bank at a time; the epilogue fills the other.  A bank
// is never rewritten while DRAINING, and a bank is never drained before the
// tile-last packed word has been written.
//
// Address modes:
//   ADDR_TAG    : write address = wr_tag[6:0] (fused row-major reorder path)
//   ADDR_LINEAR : write address = per-bank internal counter (baseline/odd-tail)
//
// Protocol errors are sticky: duplicate write address (0x61), wrong word count
// (0x62), or fill/drain requested in the wrong bank state (0x63).
module fusion_a16_blockbuf_dual #(
  parameter integer WORDS = 128,
  parameter integer BANKS = 2
)(
  input  wire         clk,
  input  wire         rst_n,
  input  wire         flush,
  input  wire         start,

  // epilogue packed-word write side
  input  wire         wr_valid,
  output wire         wr_ready,
  input  wire [127:0] wr_data,
  input  wire [6:0]   wr_tag,
  input  wire         wr_last,
  input  wire         addr_mode,      // 0: tag, 1: linear
  input  wire [7:0]   cfg_words,      // 1..WORDS valid words per tile
  input  wire         fill_bank,
  input  wire         fill_start,

  // writer drain side
  input  wire         drain_bank,
  input  wire         drain_start,
  output wire         rd_valid,
  input  wire         rd_ready,
  output wire [127:0] rd_data,
  output wire         rd_last,

  // bank status
  output wire [BANKS-1:0] bank_full,
  output wire [BANKS-1:0] bank_empty,
  output wire [BANKS-1:0] bank_busy,
  output reg  [BANKS-1:0] drain_done_pulse,

  output reg  [31:0]  stat_words_written,
  output reg  [31:0]  stat_words_read,
  output reg          err_duplicate,
  output reg          err_sequence,
  output reg  [7:0]   err_code
);
  localparam [1:0] ST_EMPTY    = 2'd0;
  localparam [1:0] ST_FILLING  = 2'd1;
  localparam [1:0] ST_FULL     = 2'd2;
  localparam [1:0] ST_DRAINING = 2'd3;

  localparam [7:0] ERR_DUP = 8'h61;
  localparam [7:0] ERR_CNT = 8'h62;
  localparam [7:0] ERR_SEQ = 8'h63;

  reg [127:0] mem [0:BANKS*WORDS-1];
  reg [WORDS-1:0] seen [0:BANKS-1];
  reg [7:0] cnt      [0:BANKS-1];
  reg [7:0] rd_ptr   [0:BANKS-1];
  reg [1:0] st       [0:BANKS-1];

  wire [6:0] waddr = addr_mode ? cnt[fill_bank][6:0] : wr_tag;
  wire       dup   = seen[fill_bank][waddr];
  wire       can_wr = (st[fill_bank] == ST_FILLING) &&
                      (cnt[fill_bank] < cfg_words) && !dup && !flush;
  assign wr_ready = can_wr;

  wire wr_fire = wr_valid && wr_ready;
  wire rd_fire = rd_valid && rd_ready;

  assign bank_full  = {st[1] == ST_FULL,     st[0] == ST_FULL};
  assign bank_empty = {st[1] == ST_EMPTY,    st[0] == ST_EMPTY};
  assign bank_busy  = {st[1] != ST_EMPTY,    st[0] != ST_EMPTY};

  assign rd_valid = (st[drain_bank] == ST_DRAINING) &&
                    (rd_ptr[drain_bank] < cfg_words);
  assign rd_data  = mem[drain_bank*WORDS + rd_ptr[drain_bank]];
  assign rd_last  = rd_valid && (rd_ptr[drain_bank] + 8'd1 == cfg_words);

  integer i;
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      for (i = 0; i < BANKS; i = i + 1) begin
        seen[i] <= {WORDS{1'b0}};
        cnt[i] <= 8'd0;
        rd_ptr[i] <= 8'd0;
        st[i] <= ST_EMPTY;
      end
      drain_done_pulse <= {BANKS{1'b0}};
      stat_words_written <= 32'd0;
      stat_words_read <= 32'd0;
      err_duplicate <= 1'b0;
      err_sequence <= 1'b0;
      err_code <= 8'd0;
    end else if (flush || start) begin
      for (i = 0; i < BANKS; i = i + 1) begin
        seen[i] <= {WORDS{1'b0}};
        cnt[i] <= 8'd0;
        rd_ptr[i] <= 8'd0;
        st[i] <= ST_EMPTY;
      end
      drain_done_pulse <= {BANKS{1'b0}};
      if (start) begin
        stat_words_written <= 32'd0;
        stat_words_read <= 32'd0;
        err_duplicate <= 1'b0;
        err_sequence <= 1'b0;
        err_code <= 8'd0;
      end
    end else begin
      drain_done_pulse <= {BANKS{1'b0}};

      // ----------------------------------------------------------------
      // fill-side start
      // ----------------------------------------------------------------
      if (fill_start) begin
        if (st[fill_bank] == ST_EMPTY) begin
          seen[fill_bank] <= {WORDS{1'b0}};
          cnt[fill_bank] <= 8'd0;
          rd_ptr[fill_bank] <= 8'd0;
          st[fill_bank] <= ST_FILLING;
        end else begin
          err_sequence <= 1'b1;
          err_code <= ERR_SEQ;
        end
      end

      // ----------------------------------------------------------------
      // packed-word write
      // ----------------------------------------------------------------
      if (wr_fire) begin
        mem[fill_bank*WORDS + waddr] <= wr_data;
        seen[fill_bank][waddr] <= 1'b1;
        cnt[fill_bank] <= cnt[fill_bank] + 8'd1;
        stat_words_written <= stat_words_written + 32'd1;
        if (wr_last) begin
          if (cnt[fill_bank] + 8'd1 != cfg_words) begin
            err_sequence <= 1'b1;
            err_code <= ERR_CNT;
          end
          st[fill_bank] <= ST_FULL;
        end else if (cnt[fill_bank] + 8'd1 == cfg_words) begin
          // cfg_words reached without tile-last: flag it and close the bank so
          // the test cannot deadlock; the sticky error still fails the case.
          err_sequence <= 1'b1;
          err_code <= ERR_CNT;
          st[fill_bank] <= ST_FULL;
        end
      end
      if (wr_valid && !wr_ready && dup && (st[fill_bank] == ST_FILLING)) begin
        err_duplicate <= 1'b1;
        err_code <= ERR_DUP;
      end

      // ----------------------------------------------------------------
      // drain-side start
      // ----------------------------------------------------------------
      if (drain_start) begin
        if (st[drain_bank] == ST_FULL) begin
          st[drain_bank] <= ST_DRAINING;
        end else begin
          err_sequence <= 1'b1;
          err_code <= ERR_SEQ;
        end
      end

      // ----------------------------------------------------------------
      // drain-side read
      // ----------------------------------------------------------------
      if (rd_fire) begin
        rd_ptr[drain_bank] <= rd_ptr[drain_bank] + 8'd1;
        stat_words_read <= stat_words_read + 32'd1;
        if (rd_ptr[drain_bank] + 8'd1 == cfg_words) begin
          st[drain_bank] <= ST_EMPTY;
          drain_done_pulse[drain_bank] <= 1'b1;
          seen[drain_bank] <= {WORDS{1'b0}};
          cnt[drain_bank] <= 8'd0;
          rd_ptr[drain_bank] <= 8'd0;
        end
      end

      if (cfg_words == 8'd0 || cfg_words > WORDS) begin
        err_sequence <= 1'b1;
        err_code <= ERR_CNT;
      end
    end
  end
endmodule
