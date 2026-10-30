`timescale 1ns/1ps
// Multi-outstanding AXI4 128-bit slave model for the shared-port stress test.
//
// Linear (non-wrapping) queues keep the model simple and auditable.  It accepts
// many outstanding ARs/AWs, returns R in AR order (the xbar's owner/tag FIFO
// requires that), and returns B in AW order with random latency so b_pending
// can exceed 1.  This is one slave port; it is not a DDR PHY or multi-HP model.
module axi_multi_bfm #(
 parameter integer QDEPTH = 256
)(
 input wire clk, rst_n,
 input wire [39:0] araddr,
 input wire [7:0]  arlen,
 input wire [2:0]  arsize,
 input wire [1:0]  arburst,
 input wire        arvalid,
 output wire       arready,
 output wire [127:0] rdata,
 output wire [1:0]   rresp,
 output wire         rlast,
 output wire         rvalid,
 input  wire         rready,
 input wire [39:0] awaddr,
 input wire [7:0]  awlen,
 input wire [2:0]  awsize,
 input wire [1:0]  awburst,
 input wire        awvalid,
 output wire       awready,
 input wire [127:0] wdata,
 input wire [15:0]  wstrb,
 input wire         wlast,
 input wire         wvalid,
 output wire        wready,
 output wire [1:0]  bresp,
 output wire        bvalid,
 input  wire        bready,
 output reg [31:0] read_bursts, write_bursts, r_beats, w_beats, b_responses,
 output reg [31:0] max_rd_pending, max_aw_pending, max_b_pending,
 output reg [31:0] data_errors, wlast_errors
);
 reg [31:0] lfsr;
 initial lfsr = 32'h1acebeef;
 always @(posedge clk) lfsr <= {lfsr[30:0], lfsr[31]^lfsr[21]^lfsr[1]^lfsr[0]};

 function [7:0] pat(input [39:0] a, input integer b);
  begin pat = (a + b) & 8'hff; end
 endfunction

 // ------------------------------------------------ read
 reg [39:0] rq_addr[0:QDEPTH-1];
 reg [7:0]  rq_len[0:QDEPTH-1];
 integer rq_head, rq_tail;
 reg [7:0] r_beat;
 reg [2:0] r_delay;
 wire [31:0] rq_count = rq_tail - rq_head;
 assign arready = rst_n && (rq_count < 32) && (lfsr[2:0] != 3'd0);
 assign rvalid = rst_n && (rq_count != 0) && (r_delay == 3'd0);
 assign rlast = rvalid && (r_beat == rq_len[rq_head]);
 assign rresp = 2'b00;
 genvar gl;
 generate
  for (gl = 0; gl < 16; gl = gl + 1) begin : g_rdata
   assign rdata[gl*8 +: 8] = rvalid ? pat(rq_addr[rq_head], r_beat*16 + gl) : 8'h00;
  end
 endgenerate

 // ------------------------------------------------ write
 reg [39:0] wq_addr[0:QDEPTH-1];
 reg [7:0]  wq_len[0:QDEPTH-1];
 integer wq_head, wq_tail;
 reg [7:0] w_beat;
 wire [31:0] wq_count = wq_tail - wq_head;
 assign awready = rst_n && (wq_count < 32) && (lfsr[4:2] != 3'd0);
 assign wready = rst_n && (wq_count != 0) && (lfsr[7:5] != 3'd0);

 // ------------------------------------------------ B
 reg [3:0] bq_delay[0:QDEPTH-1];
 integer bq_head, bq_tail;
 wire [31:0] bq_count = bq_tail - bq_head;
 assign bvalid = rst_n && (bq_count != 0) && (bq_delay[bq_head] == 4'd0);
 assign bresp = 2'b00;

 integer i;
 always @(posedge clk) begin
  if (!rst_n) begin
   rq_head = 0; rq_tail = 0; r_beat = 0; r_delay = 0;
   wq_head = 0; wq_tail = 0; w_beat = 0;
   bq_head = 0; bq_tail = 0;
   read_bursts <= 0; write_bursts <= 0; r_beats <= 0; w_beats <= 0; b_responses <= 0;
   max_rd_pending <= 0; max_aw_pending <= 0; max_b_pending <= 0;
   data_errors <= 0; wlast_errors <= 0;
   for (i = 0; i < QDEPTH; i = i + 1) begin
    rq_addr[i] <= 0; rq_len[i] <= 0; wq_addr[i] <= 0; wq_len[i] <= 0; bq_delay[i] <= 0;
   end
  end else begin
   if (arvalid && arready) begin
    if (arsize != 3'd4 || arburst != 2'b01 || arlen > 8'd15) $fatal(1, "stress AR framing");
    rq_addr[rq_tail] <= araddr;
    rq_len[rq_tail] <= arlen;
    rq_tail <= rq_tail + 1;
    read_bursts <= read_bursts + 1;
   end
   if (rq_count != 0) begin
    if (r_delay != 0) r_delay <= r_delay - 1;
    if (rvalid && rready) begin
     r_beats <= r_beats + 1;
     if (r_beat == rq_len[rq_head]) begin
      rq_head <= rq_head + 1;
      r_beat <= 0;
      r_delay <= lfsr[10:8];
     end else begin
      r_beat <= r_beat + 1;
      r_delay <= (lfsr[12:11] == 2'd0) ? 3'd2 : 3'd0;
     end
    end
   end
   if (awvalid && awready) begin
    if (awsize != 3'd4 || awburst != 2'b01 || awlen > 8'd15) $fatal(1, "stress AW framing");
    wq_addr[wq_tail] <= awaddr;
    wq_len[wq_tail] <= awlen;
    wq_tail <= wq_tail + 1;
    write_bursts <= write_bursts + 1;
   end
   if (wq_count != 0 && wvalid && wready) begin
    for (i = 0; i < 16; i = i + 1) begin
     if (wstrb[i] && (wdata[i*8 +: 8] != pat(wq_addr[wq_head], w_beat*16 + i)))
      data_errors <= data_errors + 1;
    end
    if (wlast != (w_beat == wq_len[wq_head])) wlast_errors <= wlast_errors + 1;
    w_beats <= w_beats + 1;
    if (w_beat == wq_len[wq_head]) begin
     wq_head <= wq_head + 1;
     w_beat <= 0;
     bq_delay[bq_tail] <= {1'b0, lfsr[15:13]};
     bq_tail <= bq_tail + 1;
    end else w_beat <= w_beat + 1;
   end
   if (bq_count != 0) begin
    if (bq_delay[bq_head] != 0) bq_delay[bq_head] <= bq_delay[bq_head] - 1;
    if (bvalid && bready) begin
     bq_head <= bq_head + 1;
     b_responses <= b_responses + 1;
    end
   end
   if (rq_count > max_rd_pending) max_rd_pending <= rq_count;
   if (wq_count > max_aw_pending) max_aw_pending <= wq_count;
   if (bq_count > max_b_pending) max_b_pending <= bq_count;
  end
 end
endmodule
