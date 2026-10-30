`timescale 1ns/1ps
// fusion_a16_writer.sv
// Streams a row-major A16 tile from the on-chip block buffer to the ds_ddr
// multi-outstanding write DMA and waits for the AXI B response drain boundary.
//
// Contract:
//   * one request for the whole tile; axi_dma_v020_multi_v2 splits it into
//     <=16-beat, <=4 KiB AXI bursts;
//   * the last word may be partial (`last_bytes` 1..16) and gets the matching
//     WSTRB mask; all other beats use 16'hffff;
//   * `done` is asserted only after the DMA reports done, which itself is
//     qualified by b_out==0 (all BRESP received).  This is the AXI write
//     response drain boundary used by the top-level completion.
module fusion_a16_writer #(
  parameter integer MAX_BURST = 16
)(
  input  wire         clk,
  input  wire         rst_n,
  input  wire         flush,

  input  wire         start,
  input  wire [31:0]  base_addr,
  input  wire [7:0]   words,
  input  wire [4:0]   last_bytes,     // 1..16 valid bytes in the final word

  // block buffer read side
  input  wire         buf_rd_valid,
  output wire         buf_rd_ready,
  input  wire [127:0] buf_rd_data,
  input  wire         buf_rd_last,

  // write DMA request / data
  output reg          dma_req_valid,
  input  wire         dma_req_ready,
  output reg  [31:0]  dma_req_addr,
  output reg  [15:0]  dma_req_beats,
  output wire         dma_wr_valid,
  input  wire         dma_wr_ready,
  output wire [127:0] dma_wr_data,
  output wire [15:0]  dma_wr_strb,
  input  wire         dma_done,
  input  wire         dma_error,

  output wire         busy,
  output reg          done,
  output reg          fault,
  output reg  [7:0]   error_code,

  output reg  [31:0]  stat_beats,
  output reg  [31:0]  stat_bytes,
  output reg  [31:0]  stat_drain_cycles,
  output reg  [31:0]  cyc_last_w,
  output reg  [31:0]  cyc_dma_done
);
  localparam [2:0] S_IDLE   = 3'd0;
  localparam [2:0] S_REQ    = 3'd1;
  localparam [2:0] S_STREAM = 3'd2;
  localparam [2:0] S_DRAIN  = 3'd3;
  localparam [2:0] S_ERROR  = 3'd4;

  reg [2:0]  state;
  reg [15:0] beats_left;
  reg [4:0]  tail_bytes;
  reg [31:0] cycle_count;

  assign busy = (state != S_IDLE) && (state != S_ERROR);

  assign dma_wr_valid = (state == S_STREAM) && buf_rd_valid && !flush;
  assign dma_wr_data  = buf_rd_data;
  assign dma_wr_strb  = (buf_rd_last && (tail_bytes != 5'd16))
                        ? ((16'h0001 << tail_bytes) - 16'h0001)
                        : 16'hffff;
  assign buf_rd_ready = (state == S_STREAM) && dma_wr_ready && !flush;

  wire beat_fire = dma_wr_valid && dma_wr_ready;

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state <= S_IDLE;
      dma_req_valid <= 1'b0;
      dma_req_addr <= 32'd0;
      dma_req_beats <= 16'd0;
      beats_left <= 16'd0;
      tail_bytes <= 5'd16;
      done <= 1'b0;
      fault <= 1'b0;
      error_code <= 8'd0;
      stat_beats <= 32'd0;
      stat_bytes <= 32'd0;
      stat_drain_cycles <= 32'd0;
      cyc_last_w <= 32'd0;
      cyc_dma_done <= 32'd0;
      cycle_count <= 32'd0;
    end else begin
      cycle_count <= cycle_count + 32'd1;
      done <= 1'b0;
      if (flush) begin
        state <= S_IDLE;
        dma_req_valid <= 1'b0;
        fault <= 1'b1;
        error_code <= 8'h71;
      end else begin
        if (dma_error) begin
          fault <= 1'b1;
          error_code <= 8'h72;
          state <= S_ERROR;
        end
        case (state)
          S_IDLE: begin
            if (start && (words != 8'd0) && (last_bytes >= 5'd1) &&
                (last_bytes <= 5'd16)) begin
              dma_req_valid <= 1'b1;
              dma_req_addr  <= base_addr;
              dma_req_beats <= {8'd0, words};
              beats_left    <= {8'd0, words};
              tail_bytes    <= last_bytes;
              stat_beats    <= 32'd0;
              stat_bytes    <= 32'd0;
              stat_drain_cycles <= 32'd0;
              state         <= S_REQ;
            end
          end
          S_REQ: begin
            if (dma_req_valid && dma_req_ready) begin
              dma_req_valid <= 1'b0;
              state <= S_STREAM;
            end
          end
          S_STREAM: begin
            if (beat_fire) begin
              beats_left <= beats_left - 16'd1;
              stat_beats <= stat_beats + 32'd1;
              stat_bytes <= stat_bytes + ((buf_rd_last && (tail_bytes != 5'd16))
                                          ? {27'd0, tail_bytes} : 32'd16);
              if (buf_rd_last || (beats_left == 16'd1)) begin
                cyc_last_w <= cycle_count;
                state <= S_DRAIN;
              end
            end
          end
          S_DRAIN: begin
            stat_drain_cycles <= stat_drain_cycles + 32'd1;
            if (dma_done) begin
              cyc_dma_done <= cycle_count;
              done <= 1'b1;
              state <= S_IDLE;
            end
          end
          S_ERROR: begin
            done <= 1'b0;
          end
          default: state <= S_IDLE;
        endcase
      end
    end
  end
endmodule
