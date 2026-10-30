`timescale 1ns/1ps
// PA-003/PA-004 before-fix reproduction on the read-only v020_multi candidate.
module tb_dma_pa003_pa004_before;
 reg clk=0;always #4 clk=~clk;
 reg rst_n=0;
 reg request_valid=0;wire request_ready;reg request_write=0;
 reg [31:0] request_address=0;reg [15:0] request_beats=0;
 wire read_valid;reg read_ready=1;wire [127:0] read_data;wire [15:0] read_index;
 reg write_valid=0;wire write_ready;reg [127:0] write_data=0;reg [15:0] write_strobe=0;wire [15:0] write_index;
 wire done,error;wire [31:0] read_bytes,write_bytes,read_bursts,write_bursts,ar_max,b_max;
 wire [63:0] rbc,wbc,fifo_high;
 wire [39:0] ar_a;wire [7:0] ar_l;wire [2:0] ar_s;wire [1:0] ar_b;wire ar_v,ar_r;
 wire [127:0] r_d;wire [1:0] r_r;wire r_last,r_v,r_ready;
 wire [39:0] aw_a;wire [7:0] aw_l;wire [2:0] aw_s;wire [1:0] aw_b;wire aw_v,aw_r;
 wire [127:0] w_d;wire [15:0] w_s;wire w_last,w_v,w_ready;
 wire [1:0] b_r;wire b_v,b_ready;
 wire [31:0] bfm_rb,bfm_wb,bfm_rbeats,bfm_wbeats;
 reg stall_r=0;
 axi_dma_v020_multi #(.MAX_OUT(8),.FIFO_BEATS(128),.MAX_BURST(16)) dut(
  .clk(clk),.rst_n(rst_n),
  .request_valid(request_valid),.request_ready(request_ready),.request_write(request_write),
  .request_address(request_address),.request_beats(request_beats),
  .read_valid(read_valid),.read_ready(read_ready),.read_data(read_data),.read_index(read_index),
  .write_valid(write_valid),.write_ready(write_ready),.write_data(write_data),.write_strobe(write_strobe),.write_index(write_index),
  .done(done),.error(error),.read_bytes(read_bytes),.write_bytes(write_bytes),.read_bursts(read_bursts),.write_bursts(write_bursts),
  .ar_outstanding_max(ar_max),.b_outstanding_max(b_max),.read_bubble_cycles(rbc),.write_bubble_cycles(wbc),.read_fifo_high(fifo_high),
  .m_axi_araddr(ar_a),.m_axi_arlen(ar_l),.m_axi_arsize(ar_s),.m_axi_arburst(ar_b),.m_axi_arcache(),.m_axi_arprot(),
  .m_axi_arvalid(ar_v),.m_axi_arready(ar_r),.m_axi_rdata(r_d),.m_axi_rresp(r_r),.m_axi_rlast(r_last),
  .m_axi_rvalid(r_v),.m_axi_rready(r_ready),
  .m_axi_awaddr(aw_a),.m_axi_awlen(aw_l),.m_axi_awsize(aw_s),.m_axi_awburst(aw_b),.m_axi_awcache(),.m_axi_awprot(),
  .m_axi_awvalid(aw_v),.m_axi_awready(aw_r),.m_axi_wdata(w_d),.m_axi_wstrb(w_s),.m_axi_wlast(w_last),
  .m_axi_wvalid(w_v),.m_axi_wready(w_ready),.m_axi_bresp(b_r),.m_axi_bvalid(b_v),.m_axi_bready(b_ready));
 axi128_multi_bfm #(.QDEP(16)) bfm(
  .clk(clk),.rst_n(rst_n),.araddr(ar_a),.arlen(ar_l),.arsize(ar_s),.arburst(ar_b),
  .arvalid(ar_v),.arready(ar_r),.rdata(r_d),.rresp(r_r),.rlast(r_last),.rvalid(r_v),.rready(r_ready),
  .awaddr(aw_a),.awlen(aw_l),.awsize(aw_s),.awburst(aw_b),.awvalid(aw_v),.awready(aw_r),
  .wdata(w_d),.wstrb(w_s),.wlast(w_last),.wvalid(w_v),.wready(w_ready),
  .bresp(b_r),.bvalid(b_v),.bready(b_ready),.inject_read_error(1'b0),.inject_write_error(1'b0),.stall_r(stall_r),
  .read_bursts(bfm_rb),.write_bursts(bfm_wb),.read_beats(bfm_rbeats),.write_beats(bfm_wbeats));
 reg [39:0] ar_hist_addr[0:15];reg [7:0] ar_hist_len[0:15];integer ar_hist_n=0;
 always @(posedge clk)if(ar_v&&ar_r)begin ar_hist_addr[ar_hist_n]=ar_a;ar_hist_len[ar_hist_n]=ar_l;ar_hist_n=ar_hist_n+1;end
 integer errors=0;
 task chk(input [255:0] what,input cond);begin if(!cond)begin errors=errors+1;$display("FAIL %0s",what);$fflush();end end endtask
 task do_reset;begin rst_n=0;request_valid=0;write_valid=0;ar_hist_n=0;repeat(5)@(negedge clk);rst_n=1;repeat(2)@(negedge clk);end endtask
 task wait_done(input integer maxc);begin : wd integer k;k=0;while(!done&&k<maxc)begin @(posedge clk);k=k+1;end end endtask
 integer i;
 initial begin
  do_reset;request_write=0;request_address=32'hFFFFFFF0;request_beats=2;request_valid=1;
  while(!request_ready)@(negedge clk);@(posedge clk);@(negedge clk);request_valid=0;
  wait_done(3000);
  $display("BEFORE_PA003 done=%0d err=%0d bursts=%0d bytes=%0d",done,error,read_bursts,read_bytes);
  for(i=0;i<ar_hist_n;i=i+1)$display("  AR[%0d]=%h len=%0d",i,ar_hist_addr[i],ar_hist_len[i]);
  if(ar_hist_n>=2&&ar_hist_addr[1]==40'h0000000000)$display("PA003_WRAP_BUG_CONFIRMED");
  if(ar_hist_n>=2&&ar_hist_addr[1]==40'h0100000000)$display("PA003_WRAP_FIXED");
  do_reset;request_write=1;request_address=32'h04000000;request_beats=1;request_valid=1;
  while(!request_ready)@(negedge clk);@(posedge clk);@(negedge clk);request_valid=0;
  @(negedge clk);write_valid=1;write_data=128'd0;write_strobe=16'h0007;
  while(!write_ready)@(negedge clk);@(posedge clk);@(negedge clk);write_valid=0;
  wait_done(3000);
  $display("BEFORE_PA004 done=%0d err=%0d write_bytes=%0d (correct 3)",done,error,write_bytes);
  if(write_bytes==32'd16)$display("PA004_STRB_COUNT_BUG_CONFIRMED");
  if(write_bytes==32'd3)$display("PA004_STRB_COUNT_FIXED");
  $finish;
 end
 initial begin repeat(100000)@(posedge clk);$display("BEFORE_TIMEOUT");$finish;end
endmodule
