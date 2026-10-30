`timescale 1ns/1ps
// fusion_c48_fifo.sv
// Elastic C48 beat FIFO between the matrix C48 collector and the epilogue.
//
// Capacity contract
// -----------------
//   * The matrix C48 collector is pausable: block_engine_prefetch_v2 only
//     commits a group when cval_ready is high (commit_now in COLLECT).  It
//     holds cval_valid/data/last while ready is low.  Therefore a compliant
//     producer emits at most one beat per cycle and stops when ready drops.
//   * This FIFO asserts in_ready only while occupancy < DEPTH-1.  One slot is
//     deliberately kept free (SKID=1) so that a producer which registers its
//     ready decision (one extra beat after ready falls) still cannot overflow.
//   * With a compliant producer, occupancy <= DEPTH-1 unconditionally; this is
//     a structural bound, not a statistical one.  overflow_sticky is driven by
//     an explicit handshake check and must remain 0.
//   * For a truly non-pausable source (no output ready), a FIFO alone cannot
//     bound anything.  The supported construction is a credit-gated cache
//     readout: the read address advances only while `credit != 0`
//     (credit = DEPTH-1-occupancy).  This module exposes the same credit so a
//     readout bridge can gate its BRAM read address.  In this project the
//     live matrix interface DOES have cval_ready, so the credit path is an
//     additional safety net, not a substitute for the handshake.
module fusion_c48_fifo #(
  parameter integer DEPTH = 16,
  parameter integer TAG_WIDTH = 16
)(
  input  wire                 clk,
  input  wire                 rst_n,
  input  wire                 flush,          // reset / fatal drain

  // producer (matrix framer)
  input  wire                 in_valid,
  output wire                 in_ready,
  input  wire [191:0]         in_data,
  input  wire [TAG_WIDTH-1:0] in_tag,
  input  wire                 in_last,

  // consumer (epilogue stream engine)
  output wire                 out_valid,
  input  wire                 out_ready,
  output wire [191:0]         out_data,
  output wire [TAG_WIDTH-1:0] out_tag,
  output wire                 out_last,

  // telemetry / checks
  output wire [7:0]           occupancy,
  output reg  [7:0]           high_water,
  output wire [7:0]           credit,
  output reg                  overflow_sticky,
  output reg  [31:0]          in_beats,
  output reg  [31:0]          out_beats,
  output reg  [31:0]          stall_cycles
);
  localparam integer AW = $clog2(DEPTH);
  localparam integer SKID = 1;

  reg [191:0]         mem_data [0:DEPTH-1];
  reg [TAG_WIDTH-1:0] mem_tag  [0:DEPTH-1];
  reg                 mem_last [0:DEPTH-1];

  reg [AW:0] wr_ptr;
  reg [AW:0] rd_ptr;
  wire [AW:0] count = wr_ptr - rd_ptr;
  wire [AW:0] limit = DEPTH - SKID;

  assign occupancy = count;
  assign credit    = (count < limit) ? (limit - count) : 9'd0;
  assign in_ready  = rst_n && !flush && (count < limit);
  assign out_valid = rst_n && !flush && (count != 0);

  assign out_data = mem_data[rd_ptr[AW-1:0]];
  assign out_tag  = mem_tag[rd_ptr[AW-1:0]];
  assign out_last = mem_last[rd_ptr[AW-1:0]];

  wire in_fire  = in_valid  && in_ready;
  wire out_fire = out_valid && out_ready;

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      wr_ptr <= {(AW+1){1'b0}};
      high_water <= 8'd0;
      overflow_sticky <= 1'b0;
      in_beats <= 32'd0;
    end else if (flush) begin
      wr_ptr <= {(AW+1){1'b0}};
    end else begin
      if (in_fire) begin
        // A write is only legal when a free slot exists.  A duplicate write
        // in the same cycle as a full FIFO would be a real overflow; flag it
        // and do not corrupt the stored beats.
        if (count >= limit) begin
          overflow_sticky <= 1'b1;
        end else begin
          mem_data[wr_ptr[AW-1:0]] <= in_data;
          mem_tag [wr_ptr[AW-1:0]] <= in_tag;
          mem_last[wr_ptr[AW-1:0]] <= in_last;
          wr_ptr <= wr_ptr + 1'b1;
          in_beats <= in_beats + 32'd1;
        end
      end
      if (count > high_water) high_water <= count;
    end
  end

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      rd_ptr <= {(AW+1){1'b0}};
      out_beats <= 32'd0;
      stall_cycles <= 32'd0;
    end else if (flush) begin
      rd_ptr <= {(AW+1){1'b0}};
    end else begin
      if (out_fire) begin
        rd_ptr <= rd_ptr + 1'b1;
        out_beats <= out_beats + 32'd1;
      end
      if (out_valid && !out_ready) stall_cycles <= stall_cycles + 32'd1;
    end
  end

  // Elaboration guards: power-of-two depth keeps the pointer arithmetic and
  // the occupancy bound exact (no modulo ambiguity).
  initial begin
    if (DEPTH < 4 || (DEPTH & (DEPTH-1)) != 0)
      $fatal(1, "fusion_c48_fifo: DEPTH must be a power of two >= 4");
    if (SKID < 1 || SKID >= DEPTH)
      $fatal(1, "fusion_c48_fifo: invalid SKID");
  end
endmodule
