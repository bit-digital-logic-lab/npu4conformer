`timescale 1ns/1ps
// PA-003 / PA-004 regression on the v023 multi-outstanding DMA.
module tb_dma_pa003_pa004;
 reg clk=0;always #4 clk=~clk;
 reg rst_n=0;
 reg request_valid=0;wire request_ready;reg request_write=0;
 reg [31:0] request_address=0;reg [15:0] request_beats=0;
 wire read_valid;reg read_ready=1;wire [127:0] read_data;wire [15:0] read_index;
 reg write_valid=0;wire write_ready;reg [127:0] write_data=0;reg [15:0] write_strobe=0;wire [15:0] write_index;
 wire done,error;
 wire [31:0] read_bytes,write_bytes,read_bursts,write_bursts,ar_max,b_max;
 wire [63:0] rbc,wbc,fifo_high;
 reg abort=0;wire aborted,drained,busy;
 wire [39:0] ar_a;wire [7:0] ar_l;wire [2:0] ar_s;wire [1:0] ar_b;wire ar_v,ar_r;
 wire [127:0] r_d;wire [1:0] r_r;wire r_last,r_v,r_ready;
 wire [39:0] aw_a;wire [7:0] aw_l;wire [2:0] aw_s;wire [1:0] aw_b;wire aw_v,aw_r;
 wire [127:0] w_d;wire [15:0] w_s;wire w_last,w_v,w_ready;
 wire [1:0] b_r;wire b_v,b_ready;
 wire [31:0] bfm_rb,bfm_wb,bfm_rbeats,bfm_wbeats;
 reg stall_r=0,inject_re=0,inject_we=0;

 axi_dma_v023_multi #(.MAX_OUT(8),.FIFO_BEATS(128),.MAX_BURST(16)) dut(
  .clk(clk),.rst_n(rst_n),
  .request_valid(request_valid),.request_ready(request_ready),.request_write(request_write),
  .request_address(request_address),.request_beats(request_beats),
  .read_valid(read_valid),.read_ready(read_ready),.read_data(read_data),.read_index(read_index),
  .write_valid(write_valid),.write_ready(write_ready),.write_data(write_data),.write_strobe(write_strobe),.write_index(write_index),
  .done(done),.error(error),.read_bytes(read_bytes),.write_bytes(write_bytes),.read_bursts(read_bursts),.write_bursts(write_bursts),
  .ar_outstanding_max(ar_max),.b_outstanding_max(b_max),.read_bubble_cycles(rbc),.write_bubble_cycles(wbc),.read_fifo_high(fifo_high),
  .abort(abort),.aborted(aborted),.drained(drained),.busy(busy),
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
  .bresp(b_r),.bvalid(b_v),.bready(b_ready),
  .inject_read_error(inject_re),.inject_write_error(inject_we),.stall_r(stall_r),
  .read_bursts(bfm_rb),.write_bursts(bfm_wb),.read_beats(bfm_rbeats),.write_beats(bfm_wbeats));

 // AR/AW history
 reg [39:0] ar_hist_addr[0:31];reg [7:0] ar_hist_len[0:31];integer ar_hist_n=0;
 reg [39:0] aw_hist_addr[0:31];reg [7:0] aw_hist_len[0:31];integer aw_hist_n=0;
 always @(posedge clk)begin
  if(ar_v&&ar_r)begin ar_hist_addr[ar_hist_n]=ar_a;ar_hist_len[ar_hist_n]=ar_l;ar_hist_n=ar_hist_n+1;end
  if(aw_v&&aw_r)begin aw_hist_addr[aw_hist_n]=aw_a;aw_hist_len[aw_hist_n]=aw_l;aw_hist_n=aw_hist_n+1;end
 end

 reg done_seen=0;
 always @(posedge clk)if(done)done_seen<=1;
 integer errors=0;
 task chk(input [255:0] what,input cond);begin if(!cond)begin errors=errors+1;$display("FAIL %0s",what);$fflush();end end endtask
 task do_reset;begin
  rst_n=0;request_valid=0;read_ready=1;write_valid=0;abort=0;stall_r=0;done_seen=0;
  ar_hist_n=0;aw_hist_n=0;
  repeat(5)@(negedge clk);rst_n=1;repeat(2)@(negedge clk);
 end endtask
 task start_read(input [31:0] a,input [15:0] beats);begin
  @(negedge clk);request_write=0;request_address=a;request_beats=beats;request_valid=1;
  while(!request_ready)@(negedge clk);
  @(posedge clk);@(negedge clk);request_valid=0;
 end endtask
 task wait_done(input integer maxc);begin : wd
  integer k;k=0;
  while(!done&&k<maxc)begin @(posedge clk);k=k+1;end
 end endtask
 task start_write(input [31:0] a,input [15:0] beats,input [15:0] strobe_first,input [15:0] strobe_last);begin
  @(negedge clk);request_write=1;request_address=a;request_beats=beats;request_valid=1;
  while(!request_ready)@(negedge clk);
  @(posedge clk);@(negedge clk);request_valid=0;
  // drive W beats; data pattern is byte index.
  for(integer i=0;i<beats;i=i+1)begin
   @(negedge clk);write_valid=1;write_data={16{8'(i)}};write_strobe=(i==0)?strobe_first:((i==beats-1)?strobe_last:16'hffff);
   while(!write_ready)@(negedge clk);
   @(posedge clk);@(negedge clk);write_valid=0;
  end
 end endtask
 integer i;
 initial begin
  // ---------- PA-003: 4 GiB crossing ----------
  do_reset;start_read(32'hFFFFFFF0,16'd2);wait_done(2000);
  $display("PA003 read addr=%h beats=2 -> done=%0d err=%0d bursts=%0d bytes=%0d ar_n=%0d",
   32'hFFFFFFF0,done,error,read_bursts,read_bytes,ar_hist_n);
  for(i=0;i<ar_hist_n;i=i+1)$display("  AR[%0d]=%h len=%0d",i,ar_hist_addr[i],ar_hist_len[i]);
  chk("PA003 done",done==1&&error==0);
  chk("PA003 two bursts",read_bursts==2&&ar_hist_n==2);
  chk("PA003 first addr",ar_hist_addr[0]==40'h00FFFFFFF0&&ar_hist_len[0]==0);
  chk("PA003 second addr no wrap",ar_hist_addr[1]==40'h0100000000&&ar_hist_len[1]==0);
  chk("PA003 bytes",read_bytes==32);

  // ---------- PA-004: WSTRB byte count ----------
  do_reset;start_write(32'h04000000,16'd1,16'h0007,16'h0007);wait_done(2000);
  $display("PA004 write 1 beat wstrb=0007 -> done=%0d err=%0d write_bytes=%0d (expect 3)",done,error,write_bytes);
  chk("PA004 done",done==1&&error==0);
  chk("PA004 wstrb count",write_bytes==3);
  chk("PA004 mem bytes",bfm.peek(0)==8'h00&&bfm.peek(1)==8'h00&&bfm.peek(2)==8'h00&&bfm.peek(3)==8'h00);
  // Note: pattern byte i=0, so 0007 writes three zero bytes; check a nonzero tail case.
  do_reset;start_write(32'h04000010,16'd4,16'hffff,16'h0007);wait_done(2000);
  $display("PA004 write 4 beats last wstrb=0007 -> write_bytes=%0d (expect 51)",write_bytes);
  chk("PA004 4-beat count",write_bytes==51);
  chk("PA004 4-beat mem tail",bfm.peek(16+48)==8'h03&&bfm.peek(16+49)==8'h03&&bfm.peek(16+50)==8'h03&&bfm.peek(16+51)==8'h00);

  // ---------- multi-outstanding and normal completion ----------
  do_reset;start_read(32'h04000000,16'd256);wait_done(20000);
  $display("MULTI 256beat done=%0d err=%0d rb=%0d bytes=%0d ar_max=%0d fifo_high=%0d",done,error,read_bursts,read_bytes,ar_max,fifo_high);
  chk("multi done",done==1&&error==0);
  chk("multi bytes",read_bytes==4096);
  chk("multi outstanding",ar_max>1);

  // ---------- abort read: accepted ARs drain, no new AR after abort ----------
  do_reset;start_read(32'h04000000,16'd256);
  repeat(40)@(posedge clk);
  abort=1;repeat(8)@(posedge clk);
  // no new AR should be issued after abort; watch for 20 cycles
  begin : no_new_ar
   integer n0;n0=ar_hist_n;
   repeat(30)@(posedge clk);
   chk("abort no new AR",ar_hist_n==n0);
  end
  wait_done(5000);
  $display("ABORT_READ done=%0d done_seen=%0d busy=%0d err=%0d aborted=%0d drained=%0d rb=%0d bfm_rbeats=%0d",done,done_seen,busy,error,aborted,drained,read_bursts,bfm_rbeats);
  chk("abort done",done_seen==1&&busy==0);
  chk("abort flags",aborted==1&&drained==1);
  abort=0;

  // ---------- abort with delayed R: accepted response must drain ----------
  do_reset;start_read(32'h04000000,16'd64);
  repeat(20)@(posedge clk);
  stall_r=1;abort=1;
  repeat(40)@(posedge clk);
  stall_r=0;
  wait_done(5000);
  $display("ABORT_LATE done=%0d aborted=%0d drained=%0d bfm_rbeats=%0d",done,aborted,drained,bfm_rbeats);
  chk("abort late done",done==1&&aborted==1&&drained==1);

  // ---------- recovery ----------
  do_reset;start_read(32'h04000000,16'd16);wait_done(2000);
  $display("DMA_RECOVER done=%0d err=%0d bytes=%0d",done,error,read_bytes);
  chk("recover",done==1&&error==0&&read_bytes==256);

  $display("PA003_PA004_TEST_END errors=%0d",errors);$fflush();
  if(errors==0)$display("PA003_PA004_PASS");else $display("PA003_PA004_FAIL");
  $finish;
 end
 initial begin repeat(200000)@(posedge clk);$display("PA003_GLOBAL_TIMEOUT");$finish;end
endmodule
