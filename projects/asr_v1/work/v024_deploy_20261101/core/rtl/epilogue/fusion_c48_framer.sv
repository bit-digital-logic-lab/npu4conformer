`timescale 1ns/1ps
// fusion_c48_framer.sv
// Converts the ds_matrix C48 collector stream into a tile-framed epilogue
// stream.
//
// Matrix C48 facts (from block_engine_prefetch_v2 / block_storage_stream_v2):
//   * 64 segments per 32x32 output tile (16 segments per 16x16 quadrant).
//   * one cseg command per segment, then four cval beats (4 C48 values each).
//   * cval_last is segment-last (pipe_grp[1:0]==3), NOT tile-last.
//   * stream order is quadrant-major, while the logical C48 tensor is
//     row-major: quadrant q=0..3 is emitted as rows (q>>1)*16 .. +15,
//     columns (q&1)*16 .. +15.
//
// The framer:
//   1. replaces segment-last with a real tile-last (beat 255 of 256);
//   2. emits a destination address for the 16-byte A16 packer word:
//        word = row*4 + col_half*2 + pair_in_segment   (0..127)
//      which is exactly the row-major A16 word index.  Pair p of a segment
//      produces one 128-bit packed A16 word in the epilogue packer.
//   3. keeps tile row/col (cseg_row/cseg_col = block indices br/bc) so the
//      writer can compute the A16 tile base address.
//   4. checks the producer protocol (segment cadence, segment-last) and
//      reports a sticky error without ever dropping a beat.
module fusion_c48_framer #(
  parameter integer TILE_BEATS   = 256,
  parameter integer SEG_BEATS    = 4,
  parameter integer SEG_PER_TILE = 64,
  parameter integer TAG_WIDTH    = 16
)(
  input  wire                 clk,
  input  wire                 rst_n,
  input  wire                 flush,
  input  wire                 start,          // new task / tile 0

  // matrix collector side
  input  wire                 cseg_valid,
  output wire                 cseg_ready,
  input  wire [15:0]          cseg_row,
  input  wire [15:0]          cseg_col,
  input  wire                 cval_valid,
  output wire                 cval_ready,
  input  wire [191:0]         cval_data,
  input  wire                 cval_last,

  // framed stream towards FIFO / epilogue
  output wire                 out_valid,
  input  wire                 out_ready,
  output wire [191:0]         out_data,
  output wire [TAG_WIDTH-1:0] out_tag,
  output wire                 out_last,

  // tile metadata / telemetry
  output reg  [15:0]          tile_row,
  output reg  [15:0]          tile_col,
  output reg  [15:0]          beat_in_tile,
  output reg  [15:0]          seg_in_tile,
  output reg  [31:0]          tile_count,
  output reg  [31:0]          cseg_count,
  output reg                  err_sticky,
  output reg  [7:0]           err_code
);
  localparam [7:0] ERR_SEG_CADENCE = 8'h51;
  localparam [7:0] ERR_SEG_LAST    = 8'h52;
  localparam [7:0] ERR_SEG_COUNT   = 8'h53;

  // cseg is a pure metadata command and is accepted immediately; the C48
  // data path itself is backpressured through out_ready.
  assign cseg_ready = rst_n && !flush && !err_sticky;

  wire cseg_fire = cseg_valid && cseg_ready;
  wire cval_fire = cval_valid && cval_ready;

  // combinational destination word index for the current beat
  wire [5:0] seg_now      = beat_in_tile[7:2];
  wire [1:0] beat_in_seg  = beat_in_tile[1:0];
  wire [4:0] row_now      = {1'b0, seg_now[5]} ? (5'd16 + {1'b0, seg_now[3:0]})
                                                : {1'b0, seg_now[3:0]};
  wire       col_half_now = seg_now[4];
  wire [6:0] word_now     = {row_now, 2'b00} + {5'd0, col_half_now, 1'b0}
                            + {6'd0, beat_in_seg[1]};

  assign out_valid = cval_valid && !flush && !err_sticky;
  assign out_data  = cval_data;
  assign out_tag   = {{(TAG_WIDTH-7){1'b0}}, word_now};
  assign out_last  = (beat_in_tile == (TILE_BEATS-1));

  assign cval_ready = out_ready && !flush && !err_sticky;

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      tile_row    <= 16'd0;
      tile_col    <= 16'd0;
      beat_in_tile<= 16'd0;
      seg_in_tile <= 16'd0;
      tile_count  <= 32'd0;
      cseg_count  <= 32'd0;
      err_sticky  <= 1'b0;
      err_code    <= 8'd0;
    end else if (flush || start) begin
      beat_in_tile<= 16'd0;
      seg_in_tile <= 16'd0;
      tile_count  <= 32'd0;
      cseg_count  <= 32'd0;
      err_sticky  <= 1'b0;
      err_code    <= 8'd0;
      if (start) begin
        tile_row <= 16'd0;
        tile_col <= 16'd0;
      end
    end else begin
      if (cseg_fire) begin
        cseg_count <= cseg_count + 32'd1;
        // A segment command must line up with a 4-beat segment boundary.
        if (beat_in_tile[1:0] != 2'd0) begin
          err_sticky <= 1'b1;
          err_code   <= ERR_SEG_CADENCE;
        end
        if (seg_in_tile == 16'd0) begin
          tile_row <= cseg_row;
          tile_col <= cseg_col;
        end
        if (seg_in_tile >= SEG_PER_TILE) begin
          err_sticky <= 1'b1;
          err_code   <= ERR_SEG_COUNT;
        end else begin
          seg_in_tile <= seg_in_tile + 16'd1;
        end
      end

      if (cval_fire) begin
        // Segment-last is expected exactly on the fourth beat of a segment.
        if (cval_last != (beat_in_seg == 2'd3)) begin
          err_sticky <= 1'b1;
          err_code   <= ERR_SEG_LAST;
        end
        if (beat_in_tile == (TILE_BEATS-1)) begin
          if (seg_in_tile != SEG_PER_TILE) begin
            err_sticky <= 1'b1;
            err_code   <= ERR_SEG_COUNT;
          end
          beat_in_tile <= 16'd0;
          seg_in_tile  <= 16'd0;
          tile_count   <= tile_count + 32'd1;
        end else begin
          beat_in_tile <= beat_in_tile + 16'd1;
        end
      end
    end
  end
endmodule
