`timescale 1ns/1ps
// PA-003/PA-004 on the single-outstanding v023 DMA used by the plan fetcher.
module tb_dma_bounded_pa003;
 reg clk=0;always #4 clk=~clk;
 reg rst_n=0,request_valid=0,request_write=0;wire request_ready;
 reg [31:0] request_address=0;reg [15:0] request_beats=0;
 wire read_valid;reg read_ready=1;wire [127:0] read_data;wire [15:0] read_index;
 reg write_valid=0;wire write_ready;reg [127:0] write_data=0;reg [15:0] write_strobe=0;wire [15:0] write_index;
 wire done,error,aborted,drained,busy;
 wire [31:0] read_bytes,write_bytes,read_bursts,write_bursts;
 reg abort=0;
 wire [39:0] ar_a;wire [7:0] ar_l;wire [2:0] ar_s;wire [1:0] ar_b;wire ar_v,ar_r;
 wire [127:0] r_d;wire [1:0] r_r;wire r_last,r_v,r_ready;
 wire [39:0] aw_a;wire [7:0] aw_l;wire [2:0] aw_s;wire [1:0] aw_b;wire aw_v,aw_r;
 wire [127:0] w_d;wire [15:0] w_s;wire w_last,w_v,w_ready;
 wire [1:0] b_r;wire b_v,b_ready;
 wire [31:0] bfm_rb,bfm_wb,bfm_rbeats,bfm_wbeats;
 reg stall_r=0;
 axi_dma_v023_bounded dut(.clk(clk),.rst_n(rst_n),.request_valid(request_valid),.request_ready(request_ready),
  .request_write(request_write),.request_address(request_address),.request_beats(request_beats),
  .read_valid(read_valid),.read_ready(read_ready),.read_data(read_data),.read_index(read_index),
  .write_valid(write_valid),.write_ready(write_ready),.write_data(write_data),.write_strobe(write_strobe),.write_index(write_index),
  .done(done),.error(error),.read_bytes(read_bytes),.write_bytes(write_bytes),.read_bursts(read_bursts),.write_bursts(write_bursts),
  .abort(abort),.aborted(aborted),.drained(drained),.busy(busy),
  .m_axi_araddr(ar_a),.m_axi_arlen(ar_l),.m_axi_arsize(ar_s),.m_axi_arburst(ar_b),.m_axi_arcache(),.m_axi_arprot(),
  .m_axi_arvalid(ar_v),.m_axi_arready(ar_r),.m_axi_rdata(r_d),.m_axi_rresp(r_r),.m_axi_rlast(r_last),
  .m_axi_rvalid(r_v),.m_axi_rready(r_ready),
  .m_axi_awaddr(aw_a),.m_axi_awlen(aw_l),.m_axi_awsize(aw_s),.m_axi_awburst(aw_b),.m_axi_awcache(),.m_axi_awprot(),
  .m_axi_awvalid(aw_v),.m_axi_awready(aw_r),.m_axi_wdata(w_d),.m_axi_wstrb(w_s),.m_axi_wlast(w_last),
  .m_axi_wvalid(w_v),.m_axi_wready(w_ready),.m_axi_bresp(b_r),.m_axi_bvalid(b_v),.m_axi_bready(b_ready));
 axi128_multi_bfm bfm(.clk(clk),.rst_n(rst_n),.araddr(ar_a),.arlen(ar_l),.arsize(ar_s),.arburst(ar_b),
  .arvalid(ar_v),.arready(ar_r),.rdata(r_d),.rresp(r_r),.rlast(r_last),.rvalid(r_v),.rready(r_ready),
  .awaddr(aw_a),.awlen(aw_l),.awsize(aw_s),.awburst(aw_b),.awvalid(aw_v),.awready(aw_r),
  .wdata(w_d),.wstrb(w_s),.wlast(w_last),.wvalid(w_v),.wready(w_ready),
  .bresp(b_r),.bvalid(b_v),.bready(b_ready),.inject_read_error(1'b0),.inject_write_error(1'b0),.stall_r(stall_r),
  .read_bursts(bfm_rb),.write_bursts(bfm_wb),.read_beats(bfm_rbeats),.write_beats(bfm_wbeats));
 reg [39:0] hist[0:7];integer hn=0;integer errors=0;
 task chk(input [255:0] w,input c);begin if(!c)begin errors=errors+1;$display("FAIL %0s",w);end end endtask
 always @(posedge clk)if(ar_v&&ar_r)begin hist[hn]=ar_a;hn=hn+1;end
 integer i;
 initial begin
  repeat(5)@(negedge clk);rst_n=1;repeat(2)@(negedge clk);
  request_write=0;request_address=32'hFFFFFFF0;request_beats=2;request_valid=1;
  while(!request_ready)@(negedge clk);@(posedge clk);@(negedge clk);request_valid=0;
  while(!done)@(posedge clk);
  $display("BOUNDED_PA003 hist=%0d a0=%h a1=%h bytes=%0d",hn,hist[0],hist[1],read_bytes);
  chk("bounded wrap",hn==2&&hist[0]==40'hFFFFFFF0&&hist[1]==40'h100000000&&read_bytes==32);
  @(negedge clk);rst_n=0;repeat(4)@(negedge clk);rst_n=1;repeat(2)@(negedge clk);
  request_write=1;request_address=32'h04000000;request_beats=1;request_valid=1;
  while(!request_ready)@(negedge clk);@(posedge clk);@(negedge clk);request_valid=0;
  @(negedge clk);write_valid=1;write_data=0;write_strobe=16'h0007;
  while(!write_ready)@(negedge clk);@(posedge clk);@(negedge clk);write_valid=0;
  while(!done)@(posedge clk);
  $display("BOUNDED_PA004 write_bytes=%0d",write_bytes);
  chk("bounded strobe",write_bytes==3);
  $display("BOUNDED_TEST_END errors=%0d",errors);if(errors==0)$display("BOUNDED_PASS");else $display("BOUNDED_FAIL");$finish;
 end
 initial begin repeat(50000)@(posedge clk);$display("BOUNDED_TIMEOUT");$finish;end
endmodule
