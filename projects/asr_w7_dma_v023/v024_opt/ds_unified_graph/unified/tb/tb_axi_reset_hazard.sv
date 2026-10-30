`timescale 1ns/1ps
// Shared-AXI isolation and reset-reuse hazard proof.
//
// The slave below deliberately ignores the DUT reset: it models an external
// memory/PS port that still owns an old transaction.  Two properties are
// shown:
//   1. isolate=1 stops new AR/AW/W, keeps rd_pending/wr_pending/b_pending,
//      and only real responses move the counters (quiesced is the drain proof);
//   2. resetting only the DUT while the slave still owns an old R beat makes
//      the next AR consume that stale beat as its own data.  Therefore a port
//      with an old transaction must not be reused without a full system reset.
module tb_axi_reset_hazard;
 reg clk=0;
 always #4 clk=~clk;
 reg rst_n=0;
 reg isolate=0;

 reg m_arvalid=0; wire m_arready;
 reg [39:0] m_araddr=0; reg [7:0] m_arlen=0; reg [2:0] m_arsize=4;
 reg [1:0] m_arburst=1;
 wire [127:0] m_rdata; wire [1:0] m_rresp; wire m_rlast; wire m_rvalid;
 reg m_rready=1;
 reg m_awvalid=0; wire m_awready;
 reg [39:0] m_awaddr=0; reg [7:0] m_awlen=0; reg [2:0] m_awsize=4;
 reg [1:0] m_awburst=1;
 reg [127:0] m_wdata=0; reg [15:0] m_wstrb=16'hffff; reg m_wlast=0; reg m_wvalid=0;
 wire m_wready; reg m_bready=1;
 wire [1:0] m_bresp; wire m_bvalid;

 wire s_arvalid,s_arready; wire [39:0] s_araddr; wire [7:0] s_arlen;
 wire [2:0] s_arsize; wire [1:0] s_arburst;
 wire [127:0] s_rdata; wire [1:0] s_rresp; wire s_rlast,s_rvalid; wire s_rready;
 wire s_awvalid,s_awready; wire [39:0] s_awaddr; wire [7:0] s_awlen;
 wire [2:0] s_awsize; wire [1:0] s_awburst;
 wire [127:0] s_wdata; wire [15:0] s_wstrb; wire s_wlast,s_wvalid,s_wready;
 wire [1:0] s_bresp; wire s_bvalid,s_bready;
 wire [31:0] rd_bursts,wr_bursts,r_beats,w_beats,rd_peak,wr_peak,rd_stall,wr_stall,tag_errors;
 wire [31:0] rd_pending,wr_pending,b_pending,iso_blocked;
 wire quiesced;

 v023_axi_shared #(.NR(1),.NW(1),.CREDIT(8),.QDEPTH(32)) dut(
  .clk(clk),.rst_n(rst_n),.isolate(isolate),
  .m_arvalid(m_arvalid),.m_arready(m_arready),.m_araddr(m_araddr),.m_arlen(m_arlen),
  .m_arsize(m_arsize),.m_arburst(m_arburst),
  .m_rdata(m_rdata),.m_rresp(m_rresp),.m_rlast(m_rlast),.m_rvalid(m_rvalid),.m_rready(m_rready),
  .s_araddr(s_araddr),.s_arlen(s_arlen),.s_arsize(s_arsize),.s_arburst(s_arburst),
  .s_arvalid(s_arvalid),.s_arready(s_arready),.s_rdata(s_rdata),.s_rresp(s_rresp),
  .s_rlast(s_rlast),.s_rvalid(s_rvalid),.s_rready(s_rready),
  .m_awvalid(m_awvalid),.m_awready(m_awready),.m_awaddr(m_awaddr),.m_awlen(m_awlen),
  .m_awsize(m_awsize),.m_awburst(m_awburst),
  .m_wdata(m_wdata),.m_wstrb(m_wstrb),.m_wlast(m_wlast),.m_wvalid(m_wvalid),.m_wready(m_wready),
  .m_bready(m_bready),.m_bresp(m_bresp),.m_bvalid(m_bvalid),
  .s_awaddr(s_awaddr),.s_awlen(s_awlen),.s_awsize(s_awsize),.s_awburst(s_awburst),
  .s_awvalid(s_awvalid),.s_awready(s_awready),.s_wdata(s_wdata),.s_wstrb(s_wstrb),
  .s_wlast(s_wlast),.s_wvalid(s_wvalid),.s_wready(s_wready),.s_bresp(s_bresp),
  .s_bvalid(s_bvalid),.s_bready(s_bready),
  .rd_bursts(rd_bursts),.wr_bursts(wr_bursts),.r_beats(r_beats),.w_beats(w_beats),
  .rd_peak(rd_peak),.wr_peak(wr_peak),.rd_stall_cycles(rd_stall),
  .wr_stall_cycles(wr_stall),.tag_errors(tag_errors),
  .rd_pending(rd_pending),.wr_pending(wr_pending),.b_pending(b_pending),
  .quiesced(quiesced),.iso_blocked(iso_blocked)
 );

 // ---- external slave: survives DUT reset on purpose ----
 // Two-entry response queue so a new AR can be accepted while an older R is
 // still owned by this external port (AXI permits multiple outstanding).
 reg [39:0] q_addr[0:3];
 reg [2:0] q_head=0, q_tail=0, q_count=0;
 integer release_now=0;
 assign s_arready = (q_count < 4);
 assign s_rvalid  = (q_count != 0) && release_now;
 assign s_rdata   = {96'd0, q_addr[q_head][31:0]};
 assign s_rresp   = 2'b00;
 assign s_rlast   = 1'b1; // all test bursts are one beat
 always @(posedge clk) begin
  if (s_arvalid && s_arready) begin
   q_addr[q_tail] <= s_araddr;
   q_tail <= q_tail + 1;
   q_count <= q_count + 1;
  end
  if (s_rvalid && s_rready) begin
   q_head <= q_head + 1;
   q_count <= q_count - 1;
  end
 end

 // write side: always ready, immediate B (not the focus of this test)
 assign s_awready=1'b1; assign s_wready=1'b1;
 assign s_bvalid=1'b0;

 integer errors=0;
 reg [127:0] seen;
 task issue_ar(input [39:0] a);
 begin
  @(posedge clk); m_araddr<=a; m_arlen<=0; m_arvalid<=1;
  while(!m_arready) @(posedge clk);
  m_arvalid<=0; // deassert on the handshake edge, not one cycle later
 end
 endtask
 task issue_ar_try(input [39:0] a);
 begin
  @(posedge clk); m_araddr<=a; m_arlen<=0; m_arvalid<=1;
  repeat(3) @(posedge clk);
  m_arvalid<=0;
 end
 endtask
 task wait_r(output [127:0] d);
 begin
  while(!m_rvalid) @(posedge clk);
  d = m_rdata;
  @(posedge clk);
 end
 endtask

 initial begin
  rst_n=0; repeat(5) @(posedge clk); rst_n=1; repeat(2) @(posedge clk);

  // ---- property 1: isolation stops new requests, keeps pending ----
  issue_ar(40'h00_0000_1000);
  repeat(3) @(posedge clk);
  if (rd_pending != 1) begin $display("HAZARD_PENDING_NOT_1 %0d",rd_pending); errors=errors+1; end
  isolate=1;
  repeat(2) @(posedge clk);
  issue_ar_try(40'h00_0000_2000);
  repeat(3) @(posedge clk);
  $display("HAZARD_ISO s_arvalid=%0d m_arready=%0d rd_pending=%0d quiesced=%0d iso_blocked=%0d",
    s_arvalid,m_arready,rd_pending,quiesced,iso_blocked);
  if (s_arvalid || m_arready || rd_pending!=1 || quiesced) begin
   $display("HAZARD_ISO_FAIL"); errors=errors+1;
  end
  release_now=1;
  wait_r(seen);
  repeat(2) @(posedge clk);
  $display("HAZARD_DRAIN rd_pending=%0d quiesced=%0d data=%h",rd_pending,quiesced,seen[31:0]);
  if (rd_pending!=0 || !quiesced || seen[31:0]!=40'h00_0000_1000) begin
   $display("HAZARD_DRAIN_FAIL"); errors=errors+1;
  end
  isolate=0;

  // ---- property 2: reset only the DUT while the slave owns an old R ----
  // The slave ignores rst_n, so its old transaction survives the DUT reset.
  release_now=0;
  issue_ar(40'h00_0000_3000);
  repeat(3) @(posedge clk);
  if (rd_pending != 1) begin $display("HAZARD_PRE_RESET_PENDING %0d",rd_pending); errors=errors+1; end
  rst_n=0; repeat(4) @(posedge clk); rst_n=1; repeat(2) @(posedge clk);
  // The DUT counters were cleared by reset, but the slave still owns 0x3000.
  $display("HAZARD_POST_RESET rd_pending=%0d slave_pend=%0d",rd_pending,q_count);
  issue_ar(40'h00_0000_4000);
  release_now=1; // old 0x3000 response is released now
  wait_r(seen);
  $display("HAZARD_STALE new_ar=4000 stale_data=%h",seen[31:0]);
  if (seen[31:0] == 40'h00_0000_3000) begin
   $display("HAZARD_STALE_CONSUMED (expected: port must not be reused)");
  end else begin
   $display("HAZARD_NO_STALE_CONSUMED"); errors=errors+1;
  end
  // This test *expects* the hazard; a system that claims safe reuse must
  // either prove quiesced before reset or reset the slave too.
  if (errors) $display("HAZARD_RESULT FAIL errors=%0d",errors);
  else $display("HAZARD_RESULT PASS (isolation contract proven; reset reuse is unsafe by construction)");
  $finish;
 end
 always @(posedge clk) begin
  if ($time > 20000000) begin $display("HAZARD_TIMEOUT"); $finish; end
 end
endmodule
