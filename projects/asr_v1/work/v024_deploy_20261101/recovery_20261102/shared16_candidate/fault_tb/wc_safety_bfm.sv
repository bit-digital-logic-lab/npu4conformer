`timescale 1ns/1ps
// Safety AXI4 128-bit slave model.
//
// This is the *environment* side of the abnormal-closeout tests.  It can
// deliberately withhold a read data beat or a write response for an address
// window.  A held transaction is never silently retired: the accepted AR/AW
// stays owned by this model and the DUT's pending counter stays non-zero.
//
// Windows (same sparse map as wc_graph_bfm):
//   0x03000000..0x0303ffff -> 0x00000..0x3ffff  scratch
//   0x04000000..0x0403ffff -> 0x40000..0x7ffff  arena
//   0x08000000..0x0803ffff -> 0x80000..0xbffff  external
//   0x10000000..0x1003ffff -> 0xc0000..0xfffff  parameter/plan (read-only)
module wc_safety_bfm #(
 parameter integer MEM_WORDS = 262144,
 parameter integer PROTECT_PARAM = 1
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
 // telemetry / test controls
 output reg [31:0] read_bursts, write_bursts, read_beats, write_beats,
 output reg [31:0] held_r_bursts, held_b_bursts, returned_b,
 output reg        r_is_held, b_is_held
);
 reg [31:0] memw[0:MEM_WORDS-1];
 integer cycle = 0;
 reg [1023:0] memfile;
 reg [31:0] lfsr;
 integer seed;
 reg [39:0] hold_r_lo, hold_r_hi, hold_b_lo, hold_b_hi;
 integer hold_r_en, hold_b_en;
 integer release_after;
 reg bheld_pending;

 initial begin
  if (!$value$plusargs("seed=%d", seed)) seed = 1;
  lfsr = seed | 1;
  if (!$value$plusargs("hold_r_lo=%h", hold_r_lo)) hold_r_lo = 0;
  if (!$value$plusargs("hold_r_hi=%h", hold_r_hi)) hold_r_hi = 0;
  if (!$value$plusargs("hold_b_lo=%h", hold_b_lo)) hold_b_lo = 0;
  if (!$value$plusargs("hold_b_hi=%h", hold_b_hi)) hold_b_hi = 0;
  if (!$value$plusargs("release_after=%d", release_after)) release_after = 0;
  hold_r_en = (hold_r_lo != 0) && (hold_r_hi > hold_r_lo);
  hold_b_en = (hold_b_lo != 0) && (hold_b_hi > hold_b_lo);

  if ($value$plusargs("memfile=%s", memfile)) $readmemh(memfile, memw);
 end
 always @(posedge clk) lfsr <= {lfsr[30:0], lfsr[31]^lfsr[21]^lfsr[1]^lfsr[0]};

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
 function automatic r_hold(input [39:0] a);
  begin r_hold = hold_r_en && (a >= hold_r_lo) && (a < hold_r_hi); end
 endfunction
 function automatic b_hold(input [39:0] a);
  begin b_hold = hold_b_en && (a >= hold_b_lo) && (a < hold_b_hi); end
 endfunction

 reg ra, vis, wa, bp, bd_pending;
 reg [39:0] rab, wab;
 reg [8:0] rn, wn, ri, wi;
 reg [2:0] bd;
 reg rheld, bheld;

 assign arready = rst_n && !ra && ((cycle % 7) != 0) && (lfsr[2:0] != 0);
 assign rvalid  = ra && vis;
 assign rlast   = (ri + 1 == rn);
 integer fault_payload=0; initial if ($value$plusargs("fault_payload=%d",fault_payload)) begin end
 assign rresp = fault_payload && rab==40'h0010009000 ? 2'b10 : 2'b00;
 assign awready = rst_n && !wa && !bp && !bd_pending && bd == 0 && ((cycle % 9) != 0);
 assign wready  = wa && ((cycle % 5) != 0) && (lfsr[5:3] != 0);
 assign bvalid  = bp;
 assign bresp   = 2'b00;

 genvar lane;
 generate
  for (lane = 0; lane < 16; lane = lane + 1) begin : rd
   wire [31:0] off = (win_offset(rab) + ri*16 + lane) >> 2;
   wire [7:0]  by  = (win_offset(rab) + ri*16 + lane) & 3;
   assign rdata[lane*8 +: 8] = ra ? memw[off][by*8 +: 8] : 8'h00;
  end
 endgenerate

 always @(posedge clk) begin
  if (!rst_n) begin
   cycle <= 0; read_bursts <= 0; write_bursts <= 0; read_beats <= 0; write_beats <= 0;
   held_r_bursts <= 0; held_b_bursts <= 0; returned_b <= 0;
   r_is_held <= 0; b_is_held <= 0;
   ra <= 0; vis <= 0; wa <= 0; bp <= 0; bd <= 0; bd_pending <= 0;
   ri <= 0; wi <= 0; rab <= 0; wab <= 0; rn <= 0; wn <= 0;
   rheld <= 0; bheld <= 0; bheld_pending <= 0;
  end else begin
   cycle <= cycle + 1;
   if (arvalid && arready) begin
    if (!valid_address(araddr)) $fatal(1, "AR outside model windows %h", araddr);
    if (araddr[3:0] != 0 || arsize != 4 || arburst != 1 || arlen > 15 ||
        ({1'b0, araddr[11:0]} + ((arlen + 1) * 16)) > 4096)
     $fatal(1, "AR burst framing");
    rab <= araddr; rn <= arlen + 1; ri <= 0; ra <= 1; vis <= 0;
    rheld <= r_hold(araddr);
    if (r_hold(araddr)) begin
     held_r_bursts <= held_r_bursts + 1; r_is_held <= 1;
    end
    read_bursts <= read_bursts + 1;
   end
   // A held read stays owned by the model until release_after (if set).
   if (ra && !vis && (!rheld || (release_after!=0 && cycle>=release_after)) &&
       ((cycle % 4) != 0)) vis <= 1;
   if (rvalid && rready) begin
    read_beats <= read_beats + 1; vis <= 0;
    if (ri + 1 == rn) begin ra <= 0; r_is_held <= 0; end
    else ri <= ri + 1;
   end
   if (awvalid && awready) begin
    if (!valid_address(awaddr)) $fatal(1, "AW outside model windows %h", awaddr);
    if (PROTECT_PARAM && in_param(awaddr)) $fatal(1, "WRITE TO READ-ONLY PARAMETER %h", awaddr);
    if (awaddr[3:0] != 0 || awsize != 4 || awburst != 1 || awlen > 15 ||
        ({1'b0, awaddr[11:0]} + ((awlen + 1) * 16)) > 4096)
     $fatal(1, "AW burst framing");
    wab <= awaddr; wn <= awlen + 1; wi <= 0; wa <= 1;
    bheld <= b_hold(awaddr);
    write_bursts <= write_bursts + 1;
   end
   if (wvalid && wready) begin
    if (wlast != (wi + 1 == wn)) $fatal(1, "WLAST mismatch");
    for (integer l = 0; l < 16; l = l + 1) begin
     if (wstrb[l])
      memw[(win_offset(wab) + wi*16 + l) >> 2][((win_offset(wab) + wi*16 + l) & 3)*8 +: 8] <= wdata[l*8 +: 8];
    end
    write_beats <= write_beats + 1;
    if (wi + 1 == wn) begin
     wa <= 0;
     if (bheld) begin
      // Accepted write, response withheld.  Do NOT schedule a B now.
      held_b_bursts <= held_b_bursts + 1; b_is_held <= 1;
      bheld_pending <= 1;
     end else begin
      bd <= 3; bd_pending <= 1;
     end
    end else wi <= wi + 1;
   end
   if (bheld_pending && release_after!=0 && cycle>=release_after) begin
    bheld_pending <= 0; bd <= 3; bd_pending <= 1; b_is_held <= 0;
   end
   if (bd != 0) begin
    bd <= bd - 1;
    if (bd == 1) bp <= 1;
   end
   if (bvalid && bready) begin bp <= 0; returned_b <= returned_b + 1; bd_pending <= 0; end
  end
 end
endmodule
