`timescale 1ns/1ps
// vector_fma_lane.sv
// Thin latency adapter around the real round-2 fp32_fma_pipe.
//
// EXTRA_STAGES=0 is a transparent pass-through.  EXTRA_STAGES=N>0 inserts N
// valid/tag/data-only elastic pipeline stages AFTER the real FMA.  This is a
// regression vehicle for the vector engine's latency-variable contract and a
// drop-in shape for ds_fma_deep: the engine only uses valid/ready, never a
// fixed cycle count.
//
// No arithmetic is added or changed here.  The real FMA is still
// rtl/fp32_fma_pipe.sv (single RNE, FTZ, NaN/Inf rules).
module vector_fma_lane #(
 parameter integer EXTRA_STAGES = 0,
 parameter integer TAG_WIDTH = 16
)(
 input  wire                  clk,
 input  wire                  rst_n,
 input  wire                  flush,
 input  wire                  in_valid,
 output wire                  in_ready,
 input  wire [31:0]           in_a,
 input  wire [31:0]           in_b,
 input  wire [31:0]           in_c,
 input  wire [TAG_WIDTH-1:0]  in_tag,
 input  wire                  in_last,
 output wire                  out_valid,
 input  wire                  out_ready,
 output wire [31:0]           out_result,
 output wire [TAG_WIDTH-1:0]  out_tag,
 output wire                  out_last
);
 wire                  pipe_out_valid;
 wire                  pipe_out_ready;
 wire [31:0]           pipe_out_result;
 wire [TAG_WIDTH-1:0]  pipe_out_tag;
 wire                  pipe_out_last;

 fp32_fma_pipe #(.TAG_WIDTH(TAG_WIDTH)) u_pipe (
  .clk        (clk),
  .rst_n      (rst_n),
  .flush      (flush),
  .in_valid   (in_valid),
  .in_ready   (in_ready),
  .in_a       (in_a),
  .in_b       (in_b),
  .in_c       (in_c),
  .in_tag     (in_tag),
  .in_last    (in_last),
  .out_valid  (pipe_out_valid),
  .out_ready  (pipe_out_ready),
  .out_result (pipe_out_result),
  .out_tag    (pipe_out_tag),
  .out_last   (pipe_out_last)
 );

 generate
  if (EXTRA_STAGES == 0) begin : g_pass
   assign pipe_out_ready = out_ready;
   assign out_valid      = pipe_out_valid;
   assign out_result     = pipe_out_result;
   assign out_tag        = pipe_out_tag;
   assign out_last       = pipe_out_last;
  end else begin : g_extra
   reg                  v [0:EXTRA_STAGES-1];
   reg [31:0]           r [0:EXTRA_STAGES-1];
   reg [TAG_WIDTH-1:0]  t [0:EXTRA_STAGES-1];
   reg                  l [0:EXTRA_STAGES-1];
   wire [EXTRA_STAGES:0] ready;
   genvar gi;
   assign ready[EXTRA_STAGES] = out_ready;
   for (gi = 0; gi < EXTRA_STAGES; gi = gi + 1) begin : g_r
    assign ready[gi] = !v[gi] || ready[gi+1];
   end
   assign pipe_out_ready = ready[0];
   assign out_valid      = v[EXTRA_STAGES-1];
   assign out_result     = r[EXTRA_STAGES-1];
   assign out_tag        = t[EXTRA_STAGES-1];
   assign out_last       = l[EXTRA_STAGES-1];

   integer j;
   always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
     for (j = 0; j < EXTRA_STAGES; j = j + 1) begin
      v[j] <= 1'b0; r[j] <= 32'd0; t[j] <= {TAG_WIDTH{1'b0}}; l[j] <= 1'b0;
     end
    end else if (flush) begin
     for (j = 0; j < EXTRA_STAGES; j = j + 1) v[j] <= 1'b0;
    end else begin
     if (ready[0]) begin
      v[0] <= pipe_out_valid;
      if (pipe_out_valid) begin
       r[0] <= pipe_out_result; t[0] <= pipe_out_tag; l[0] <= pipe_out_last;
      end
     end
     for (j = 1; j < EXTRA_STAGES; j = j + 1) begin
      if (ready[j]) begin
       v[j] <= v[j-1];
       if (v[j-1]) begin
        r[j] <= r[j-1]; t[j] <= t[j-1]; l[j] <= l[j-1];
       end
      end
     end
    end
   end
  end
 endgenerate
endmodule
