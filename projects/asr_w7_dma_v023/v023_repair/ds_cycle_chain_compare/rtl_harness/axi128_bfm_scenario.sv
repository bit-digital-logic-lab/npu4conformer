`timescale 1ns/1ps
// Shared AXI4-128 logic BFM with selectable storage/back-pressure scenarios.
// This is a testbench memory model, NOT a DDR/PHY timing model.
//
// Same memory windows as integrated/tb/wc_graph_bfm.sv:
//   0x03000000..0x0303ffff -> 0x00000..0x3ffff  scratch
//   0x04000000..0x0403ffff -> 0x40000..0x7ffff  intermediate/arena
//   0x08000000..0x0803ffff -> 0x80000..0xbffff  external boundary I/O
//   0x10000000..0x1003ffff -> 0xc0000..0xfffff  parameter/plan (read-only)
//
// Plusargs:
//   +lat_mode=default|rand_bp|long_wait
//   +seed=<integer>          LFSR seed (default 1)
//   +rd_lat=<integer>        read-burst start latency override
//   +wr_lat=<integer>        write-response latency override
//   +memfile=<path>
//   +inject_read_error=0|1  (kept for parity with the integrated BFM)
//   +inject_write_error=0|1
module axi128_bfm_scenario(
 input wire clk,rst_n,
 input wire [39:0] araddr,input wire [7:0] arlen,
 input wire [2:0] arsize,input wire [1:0] arburst,
 input wire arvalid,output wire arready,
 output wire [127:0] rdata,output wire [1:0] rresp,
 output wire rlast,rvalid,input wire rready,
 input wire [39:0] awaddr,input wire [7:0] awlen,
 input wire [2:0] awsize,input wire [1:0] awburst,
 input wire awvalid,output wire awready,
 input wire [127:0] wdata,input wire [15:0] wstrb,
 input wire wlast,wvalid,output wire wready,
 output wire [1:0] bresp,output wire bvalid,input wire bready,
 input wire inject_read_error,inject_write_error,
 output reg [31:0] read_bursts,write_bursts,read_beats,write_beats,
 output reg [31:0] read_busy_cycles,write_busy_cycles,bresp_wait_cycles,
 output wire idle
);
 reg [31:0] memw[0:262143]; // 1 MiB window image
 reg [1023:0] memfile;

 // scenario configuration
 reg [255:0] lat_mode;        // "default", "rand_bp", "long_wait"
 integer seed;
 reg [31:0] lfsr;
 integer rd_lat_cfg, wr_lat_cfg;
 integer rd_lat_eff, wr_lat_eff;
 integer rd_gap_cfg, wr_gap_cfg;

 initial begin
  if (!$value$plusargs("memfile=%s", memfile)) memfile = "inputs/mem_integrated.hex";
  $readmemh(memfile, memw);
  if (!$value$plusargs("seed=%d", seed)) seed = 1;
  lfsr = seed | 1;
  lat_mode = "default";
  if (!$value$plusargs("lat_mode=%s", lat_mode)) lat_mode = "default";
  // default scenario values
  rd_lat_eff = 0; wr_lat_eff = 0; rd_gap_cfg = 0; wr_gap_cfg = 0;
  if (lat_mode == "rand_bp") begin
   rd_lat_eff = 0; wr_lat_eff = 0; rd_gap_cfg = 2; wr_gap_cfg = 2;
  end else if (lat_mode == "long_wait") begin
   rd_lat_eff = 48; wr_lat_eff = 48; rd_gap_cfg = 1; wr_gap_cfg = 1;
  end
  if (!$value$plusargs("rd_lat=%d", rd_lat_cfg)) rd_lat_cfg = -1;
  if (!$value$plusargs("wr_lat=%d", wr_lat_cfg)) wr_lat_cfg = -1;
  if (rd_lat_cfg >= 0) rd_lat_eff = rd_lat_cfg;
  if (wr_lat_cfg >= 0) wr_lat_eff = wr_lat_cfg;
  if (!$value$plusargs("rd_gap=%d", rd_gap_cfg)) begin end
  if (!$value$plusargs("wr_gap=%d", wr_gap_cfg)) begin end
 end

 always @(posedge clk) begin
  if (!rst_n) lfsr <= seed | 1;
  else lfsr <= {lfsr[30:0], lfsr[31]^lfsr[21]^lfsr[1]^lfsr[0]};
 end

 function automatic integer win_offset(input [39:0] a);
  begin
   if (a >= 40'h0003000000 && a < 40'h0003040000) win_offset = a - 40'h0003000000;
   else if (a >= 40'h0004000000 && a < 40'h0004040000) win_offset = 32'h00040000 + (a - 40'h0004000000);
   else if (a >= 40'h0008000000 && a < 40'h0008040000) win_offset = 32'h00080000 + (a - 40'h0008000000);
   else if (a >= 40'h0010000000 && a < 40'h0010040000) win_offset = 32'h000c0000 + (a - 40'h0010000000);
   else win_offset = -1;
  end
 endfunction
 function automatic in_param(input [39:0] a);
  begin in_param = (a >= 40'h0010000000 && a < 40'h0010040000); end
 endfunction
 function automatic valid_address(input [39:0] a);
  begin valid_address = (^a !== 1'bx) && (win_offset(a) >= 0); end
 endfunction

 // read engine
 reg rbusy;
 reg [39:0] raddr_q;
 reg [8:0] rlen_q, rbeat_q, rwait_q, rgap_q;
 wire r_accept = arvalid && arready;
 wire rd_beat_hs = rvalid && rready;
 wire rd_last_hs = rd_beat_hs && rlast;
 wire [31:0] roff = (win_offset(raddr_q) + rbeat_q*16) >> 2;
 integer lane;
 assign rdata[127:0] = rbusy ? { memw[roff+7], memw[roff+6], memw[roff+5], memw[roff+4],
                                 memw[roff+3], memw[roff+2], memw[roff+1], memw[roff+0] } : 128'd0;
 assign rresp = inject_read_error ? 2'b10 : 2'b00;
 assign rlast = rbusy && (rbeat_q + 1 == rlen_q);
 assign rvalid = rbusy && (rwait_q == 0);

 wire ar_ok;
 assign ar_ok = rst_n && !rbusy &&
   ((lat_mode == "rand_bp") ? (lfsr[2:0] != 3'd0) : 1'b1);
 assign arready = ar_ok;

 // write engine
 reg wbusy;
 reg [39:0] waddr_q;
 reg [8:0] wlen_q, wbeat_q;
 reg bpend;
 reg [8:0] bwait_q, bgap_q;
 wire w_accept = awvalid && awready;
 wire wr_beat_hs = wvalid && wready;
 wire wr_last_hs = wr_beat_hs && wlast;
 wire b_hs = bvalid && bready;
 integer wlane;
 assign awready = rst_n && !wbusy && !bpend &&
   ((lat_mode == "rand_bp") ? (lfsr[5:3] != 3'd0) : 1'b1);
 assign wready = rst_n && wbusy && !bpend &&
   ((lat_mode == "rand_bp") ? (lfsr[8:6] != 3'd0) : 1'b1);
 assign bvalid = rst_n && bpend && (bwait_q == 0);
 assign bresp = inject_write_error ? 2'b10 : 2'b00;
 assign idle = !rbusy && !wbusy && !bpend;

 always @(posedge clk) begin
  if (!rst_n) begin
   rbusy <= 0; wbusy <= 0; bpend <= 0;
   raddr_q <= 0; rlen_q <= 0; rbeat_q <= 0; rwait_q <= 0; rgap_q <= 0;
   waddr_q <= 0; wlen_q <= 0; wbeat_q <= 0; bwait_q <= 0; bgap_q <= 0;
   read_bursts <= 0; write_bursts <= 0; read_beats <= 0; write_beats <= 0;
   read_busy_cycles <= 0; write_busy_cycles <= 0; bresp_wait_cycles <= 0;
  end else begin
   if (rbusy) read_busy_cycles <= read_busy_cycles + 1;
   if (wbusy || bpend) write_busy_cycles <= write_busy_cycles + 1;
   if (bpend && !bvalid) bresp_wait_cycles <= bresp_wait_cycles + 1;

   // ---------------- read ----------------
   if (r_accept) begin
    if (!valid_address(araddr)) $fatal(1, "AR outside model windows %h", araddr);
    if (araddr[3:0] != 0 || arsize != 3'd4 || arburst != 2'd1 || arlen > 8'd15 ||
        ({1'b0,araddr[11:0]} + ((arlen + 1)*16)) > 4096) $fatal(1, "AR burst framing addr=%h len=%0d", araddr, arlen);
    raddr_q <= araddr; rlen_q <= arlen + 1; rbeat_q <= 0;
    rwait_q <= (lat_mode == "rand_bp") ? (lfsr[11:9] & 3) : rd_lat_eff;
    rgap_q <= 0; rbusy <= 1;
    read_bursts <= read_bursts + 1;
   end else if (rbusy) begin
    if (rwait_q != 0) rwait_q <= rwait_q - 1;
    else if (rd_beat_hs) begin
     read_beats <= read_beats + 1;
     if (rd_last_hs) begin
      rbusy <= 0;
     end else begin
      rbeat_q <= rbeat_q + 1;
      rwait_q <= (lat_mode == "rand_bp") ? (lfsr[13:12]) : rd_gap_cfg;
     end
    end
   end

   // ---------------- write ----------------
   if (w_accept) begin
    if (!valid_address(awaddr)) $fatal(1, "AW outside model windows %h", awaddr);
    if (in_param(awaddr)) $fatal(1, "WRITE TO READ-ONLY PARAMETER %h", awaddr);
    if (awaddr[3:0] != 0 || awsize != 3'd4 || awburst != 2'd1 || awlen > 8'd15 ||
        ({1'b0,awaddr[11:0]} + ((awlen + 1)*16)) > 4096) $fatal(1, "AW burst framing addr=%h len=%0d", awaddr, awlen);
    waddr_q <= awaddr; wlen_q <= awlen + 1; wbeat_q <= 0; wbusy <= 1;
    write_bursts <= write_bursts + 1;
   end
   if (wr_beat_hs) begin
    if (wlast !== (wbeat_q + 1 == wlen_q)) $fatal(1, "WLAST mismatch");
    for (wlane = 0; wlane < 16; wlane = wlane + 1) begin
     if (wstrb[wlane])
      memw[(win_offset(waddr_q) + wbeat_q*16 + wlane) >> 2]
          [((win_offset(waddr_q) + wbeat_q*16 + wlane) & 3)*8 +: 8] <= wdata[wlane*8 +: 8];
    end
    write_beats <= write_beats + 1;
    if (wr_last_hs) begin
     wbusy <= 0; bpend <= 1;
     bwait_q <= (lat_mode == "rand_bp") ? (lfsr[15:14]) : wr_lat_eff;
    end else begin
     wbeat_q <= wbeat_q + 1;
    end
   end

   // ---------------- B response ----------------
   if (bpend) begin
    if (bwait_q != 0) bwait_q <= bwait_q - 1;
    else if (b_hs) bpend <= 0;
   end
  end
 end

 // Testbench-only helpers (window offsets, not absolute addresses).
 task poke(input integer off,input [7:0] v); begin memw[off>>2][(off&3)*8 +: 8] = v; end endtask
 task poke32(input integer off,input [31:0] v); begin memw[off>>2] = v; end endtask
 function [31:0] peek32(input integer off); begin peek32 = memw[off>>2]; end endfunction
endmodule
