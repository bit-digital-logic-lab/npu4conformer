`timescale 1ns/1ps
// Independent DMA audit TB.  One source is compiled against three uniform
// wrappers (v023 multi, v023 bounded, matrix v020_multi_v2).  Every run has a
// cycle watchdog and exits non-zero on any failed check or timeout.
module tb_dma_audit;
 reg clk=0; always #4 clk=~clk;
 integer cyc=0; always @(posedge clk) cyc<=cyc+1;
 reg rst_n=0;
 reg req_valid=0; wire req_ready; reg req_write=0;
 reg [31:0] req_addr=0; reg [15:0] req_beats=0;
 wire rd_valid; reg rd_ready=1; wire [127:0] rd_data; wire [15:0] rd_index;
 reg wr_valid; wire wr_ready; reg [127:0] wr_data; reg [15:0] wr_strobe;
 wire [15:0] wr_index;
 wire done,error; wire [31:0] rd_bytes,wr_bytes,rd_bursts,wr_bursts;
 wire [31:0] ar_max,b_max; wire [63:0] rd_fifo_high;
 reg abort=0; wire aborted,drained,busy;
 wire [39:0] araddr; wire [7:0] arlen; wire [2:0] arsize; wire [1:0] arburst;
 wire [3:0] arcache; wire [2:0] arprot; wire arvalid; wire arready;
 wire [127:0] rdata; wire [1:0] rresp; wire rlast,rvalid; wire rready;
 wire [39:0] awaddr; wire [7:0] awlen; wire [2:0] awsize; wire [1:0] awburst;
 wire [3:0] awcache; wire [2:0] awprot; wire awvalid; wire awready;
 wire [127:0] wdata; wire [15:0] wstrb; wire wlast,wvalid; wire wready;
 wire [1:0] bresp; wire bvalid; wire bready;
 // BFM controls
 reg r_stall=0, ar_stall=0, aw_stall=0, w_stall=0;
 reg [2:0] r_delay=1, b_delay=1;
 reg inject_rresp=0, inject_bresp=0, inject_spurious_b=0;
 reg rlast_mode=0;
 wire [31:0] ar_bursts, ar_beats, r_beats, aw_bursts, w_beats, w_bytes;
 wire [31:0] b_responses, max_ar_out, max_b_out, protocol_errors;
 reg [39:0] chk_addr=0; wire [127:0] chk_data;

 audit_dma_dut dut(
  .clk(clk),.rst_n(rst_n),
  .req_valid(req_valid),.req_ready(req_ready),.req_write(req_write),
  .req_addr(req_addr),.req_beats(req_beats),
  .rd_valid(rd_valid),.rd_ready(rd_ready),.rd_data(rd_data),.rd_index(rd_index),
  .wr_valid(wr_valid),.wr_ready(wr_ready),.wr_data(wr_data),
  .wr_strobe(wr_strobe),.wr_index(wr_index),
  .done(done),.error(error),.rd_bytes(rd_bytes),.wr_bytes(wr_bytes),
  .rd_bursts(rd_bursts),.wr_bursts(wr_bursts),.ar_max(ar_max),.b_max(b_max),
  .rd_fifo_high(rd_fifo_high),
  .abort(abort),.aborted(aborted),.drained(drained),.busy(busy),
  .araddr(araddr),.arlen(arlen),.arsize(arsize),.arburst(arburst),
  .arcache(arcache),.arprot(arprot),.arvalid(arvalid),.arready(arready),
  .rdata(rdata),.rresp(rresp),.rlast(rlast),.rvalid(rvalid),.rready(rready),
  .awaddr(awaddr),.awlen(awlen),.awsize(awsize),.awburst(awburst),
  .awcache(awcache),.awprot(awprot),.awvalid(awvalid),.awready(awready),
  .wdata(wdata),.wstrb(wstrb),.wlast(wlast),.wvalid(wvalid),.wready(wready),
  .bresp(bresp),.bvalid(bvalid),.bready(bready));

 axi128_audit_bfm #(.MEM_BYTES(1<<22),.QDEPTH(32)) bfm(
  .clk(clk),.rst_n(rst_n),
  .araddr(araddr),.arlen(arlen),.arsize(arsize),.arburst(arburst),
  .arvalid(arvalid),.arready(arready),
  .rdata(rdata),.rresp(rresp),.rlast(rlast),.rvalid(rvalid),.rready(rready),
  .awaddr(awaddr),.awlen(awlen),.awsize(awsize),.awburst(awburst),
  .awvalid(awvalid),.awready(awready),
  .wdata(wdata),.wstrb(wstrb),.wlast(wlast),.wvalid(wvalid),.wready(wready),
  .bresp(bresp),.bvalid(bvalid),.bready(bready),
  .r_stall(r_stall),.ar_stall(ar_stall),.aw_stall(aw_stall),.w_stall(w_stall),
  .r_delay(r_delay),.b_delay(b_delay),
  .inject_rresp(inject_rresp),.inject_bresp(inject_bresp),
  .inject_spurious_b(inject_spurious_b),.rlast_mode(rlast_mode),
  .ar_bursts(ar_bursts),.ar_beats(ar_beats),.r_beats(r_beats),
  .aw_bursts(aw_bursts),.w_beats(w_beats),.w_bytes(w_bytes),
  .b_responses(b_responses),.max_ar_out(max_ar_out),.max_b_out(max_b_out),
  .protocol_errors(protocol_errors),
  .chk_addr(chk_addr),.chk_data(chk_data));

 integer errors=0;
 reg rd_check_en=1;
 integer done_latched=0;
 // W producer state (declared before tasks)
 reg wact=0; integer wn=0,wbeat=0,wtail=-1; reg [31:0] wbase=0;
 always @(posedge clk) if(done) done_latched<=1;

 task chk(input [255:0] name, input cond);
  begin
   if(!cond) begin errors=errors+1; $display("FAIL %0s (cyc=%0d)",name,cyc); end
   else $display("ok   %0s",name);
   $fflush();
  end
 endtask

 task do_reset;
  begin
   rst_n=0; req_valid=0; req_write=0; req_addr=0; req_beats=0;
   rd_ready=1; wact=0; wbeat=0;
   abort=0; r_stall=0; ar_stall=0; aw_stall=0; w_stall=0;
   r_delay=1; b_delay=1; inject_rresp=0; inject_bresp=0;
   inject_spurious_b=0; rlast_mode=0;
   repeat(5) @(negedge clk);
   rst_n=1; done_latched=0; repeat(2) @(negedge clk);
  end
 endtask

 task issue(input w, input [31:0] a, input [15:0] b);
  begin
   @(negedge clk); req_write=w; req_addr=a; req_beats=b; req_valid=1;
   while(!req_ready) @(negedge clk);
   @(posedge clk); @(negedge clk); req_valid=0;
  end
 endtask

 task wait_done(input integer limit, input [255:0] name);
  integer t;
  begin
   t=0;
   while(!done_latched && t<limit) begin @(posedge clk); t=t+1; end
   if(!done_latched) begin
    errors=errors+1;
    $display("FAIL %0s TIMEOUT after %0d cycles",name,limit);
    $display("DBG ar_bursts=%0d ar_beats=%0d r_beats=%0d rd_bytes=%0d rd_index=%0d",
             ar_bursts,ar_beats,r_beats,rd_bytes,rd_index);
    $display("DBG bfm ar_qc=%0d ar_active=%0d cur_beat=%0d cur_len=%0d rvalid=%0d rready=%0d",
             bfm.ar_qc,bfm.ar_active,bfm.cur_beat,bfm.cur_len,rvalid,rready);
    $fatal(1,"watchdog");
   end
  end
 endtask

 // read data checker: BFM initialises mem[i]=i[7:0]
 reg [39:0] rd_base=0;
 always @(posedge clk) begin
  if(rst_n && rd_check_en && rd_valid && rd_ready) begin
   for(integer lane=0;lane<16;lane=lane+1) begin
    if(rd_data[lane*8+:8] !== ((rd_base + rd_index*16 + lane) & 8'hff)) begin
     errors=errors+1;
     if(errors<8) $display("FAIL rdata idx=%0d lane=%0d got=%02h exp=%02h",rd_index,lane,rd_data[lane*8+:8],(rd_base+rd_index*16+lane)&8'hff);
    end
   end
  end
 end

 // W producer
 always @* begin
  wr_valid = wact && (wbeat<wn);
  for(integer lane=0;lane<16;lane=lane+1)
   wr_data[lane*8+:8] = ((wbase + wbeat*16 + lane) & 8'hff) ^ 8'hA5;
  if(wbeat==wn-1 && wtail>=0) wr_strobe = (16'h0001 << wtail) - 1;
  else wr_strobe = 16'hffff;
 end
 always @(posedge clk) begin
  if(rst_n && wact && wr_valid && wr_ready) begin
   if(wbeat+1==wn) wact<=0; else wbeat<=wbeat+1;
  end
 end

 // AR/AW/W monitors
 reg [39:0] ar_log[0:255]; reg [7:0] arl_log[0:255]; integer ar_n=0;
 reg [39:0] aw_log[0:255]; reg [7:0] awl_log[0:255]; integer aw_n=0;
 integer w_hs_count=0;
 always @(posedge clk) begin
  if(rst_n && arvalid && arready) begin
   ar_log[ar_n%256]<=araddr; arl_log[ar_n%256]<=arlen; ar_n<=ar_n+1;
  end
  if(rst_n && awvalid && awready) begin
   aw_log[aw_n%256]<=awaddr; awl_log[aw_n%256]<=awlen; aw_n<=aw_n+1;
  end
  if(rst_n && wvalid && wready) w_hs_count<=w_hs_count+1;
 end

 task check_word(input [39:0] a, input [127:0] exp);
  begin
   chk_addr=a; #1;
   if(chk_data !== exp) begin
    errors=errors+1;
    $display("FAIL mem @%h got=%h exp=%h",a,chk_data,exp);
   end
  end
 endtask

 task check_written_word(input [39:0] a);
  reg [127:0] exp;
  begin
   for(integer lane=0;lane<16;lane=lane+1)
    exp[lane*8+:8] = ((a + lane) & 8'hff) ^ 8'hA5;
   check_word(a,exp);
  end
 endtask

 task check_tail_word(input [39:0] a, input integer nbytes);
  reg [127:0] exp;
  begin
   for(integer lane=0;lane<16;lane=lane+1)
    exp[lane*8+:8] = (lane<nbytes) ? ((((a + lane) & 8'hff) ^ 8'hA5)) : ((a + lane) & 8'hff);
   check_word(a,exp);
  end
 endtask

 integer i;
 integer sn_ar=0, sn_aw=0;
 reg [7:0] rb0, rb1, rb2;
 initial begin
  // ---------------- T1: read tail 40 beats (16+16+8) ----------------
  do_reset; ar_n=0; aw_n=0; rd_base=32'h04000000;
  issue(0,32'h04000000,40);
  wait_done(20000,"T1");
  chk("T1 done",done_latched);
  chk("T1 error=0",error==0);
  chk("T1 read_bytes=640",rd_bytes==640);
  chk("T1 read_index=40",rd_index==40);
  chk("T1 3 ARs",ar_bursts==3);
  chk("T1 lens",arl_log[0]==15 && arl_log[1]==15 && arl_log[2]==7);
  chk("T1 no overflow",protocol_errors==0);

  // ---------------- T2: 4 GiB crossing, 2 beats ----------------
  do_reset; ar_n=0; rd_base=32'hFFFFFFF0;
  issue(0,32'hFFFFFFF0,2);
  wait_done(5000,"T2");
  chk("T2 done",done_latched);
  chk("T2 error=0",error==0);
  chk("T2 two bursts",ar_bursts==2);
  chk("T2 addr0",ar_log[0]==40'hFFFFFFF0 && arl_log[0]==0);
  chk("T2 addr1",ar_log[1]==40'h100000000 && arl_log[1]==0);
  chk("T2 bytes=32",rd_bytes==32);

  // ---------------- T3: write tail, WSTRB byte count ----------------
  do_reset; ar_n=0; aw_n=0;
  issue(1,32'h04100000,4);
  @(negedge clk); wbase=32'h04100000; wn=4; wtail=3; wbeat=0; wact=1;
  while(wact) @(negedge clk);
  wait_done(20000,"T3");
  chk("T3 done",done_latched);
  chk("T3 error=0",error==0);
  chk("T3 write_bytes=51",wr_bytes==51);
  chk("T3 one AW",aw_bursts==1 && awl_log[0]==3);
  // first 3 beats full, last beat only bytes 0..2
  for(i=0;i<3;i=i+1) check_written_word(32'h04100000+i*16);
  // last word: bytes 0..2 written with ^A5, others retain initial mem value
  check_tail_word(32'h04100000+48,3);

  // ---------------- T4: write 4 GiB crossing ----------------
  do_reset; ar_n=0; aw_n=0;
  issue(1,32'hFFFFFFF0,2);
  @(negedge clk); wbase=32'hFFFFFFF0; wn=2; wtail=-1; wbeat=0; wact=1;
  while(wact) @(negedge clk);
  wait_done(5000,"T4");
  chk("T4 done",done_latched);
  chk("T4 error=0",error==0);
  chk("T4 two AW",aw_bursts==2);
  chk("T4 addr0",aw_log[0]==40'hFFFFFFF0 && awl_log[0]==0);
  chk("T4 addr1",aw_log[1]==40'h100000000 && awl_log[1]==0);

  // ---------------- T5: early RLAST must error, not hang ----------------
  do_reset; rlast_mode=1; rd_base=32'h04000000; rd_check_en=0;
  issue(0,32'h04000000,32);
  wait_done(20000,"T5");
  chk("T5 done",done_latched);
  chk("T5 error",error==1);
  rlast_mode=0; rd_check_en=1;

`ifdef HAS_ABORT
  // ---------------- T6: abort mid-read drains accepted R ----------------
  do_reset; ar_n=0; rd_base=32'h04000000; rd_check_en=0;
  r_delay=7; issue(0,32'h04000000,2048);
  wait(ar_n>=2); // some ARs accepted
  repeat(4) @(negedge clk); abort=1;
  sn_ar=ar_n;
  wait_done(30000,"T6");
  chk("T6 done",done_latched);
  chk("T6 aborted",aborted==1);
  chk("T6 drained",drained==1);
  chk("T6 no new AR after abort",ar_n==sn_ar);
  chk("T6 all accepted R returned",r_beats==ar_beats);
  chk("T6 no error",error==0); rd_check_en=1;
  $display("T6 accepted_AR=%0d accepted_beats=%0d returned=%0d read_bytes=%0d dut_rbursts=%0d bfm_ab=%0d err=%0d",
           sn_ar,ar_beats,r_beats,rd_bytes,rd_bursts,ar_bursts,error);

  // ---------------- T7: abort before any AR accepted ----------------
  do_reset; ar_n=0; ar_stall=1;
  issue(0,32'h04000000,64);
  repeat(4) @(negedge clk); abort=1;
  wait_done(20000,"T7");
  chk("T7 done",done_latched);
  chk("T7 aborted",aborted==1);
  chk("T7 drained",drained==1);
  chk("T7 no AR",ar_n==0);
  ar_stall=0;

  // ---------------- T8: abort mid-write waits accepted burst + B ----------------
  do_reset; aw_n=0; b_delay=6;
  issue(1,32'h04200000,64);
  @(negedge clk); wbase=32'h04200000; wn=64; wtail=-1; wbeat=0; wact=1;
  wait(aw_n>=2); w_stall=1; repeat(4) @(negedge clk); abort=1;
  sn_aw=aw_n; wn=sn_aw*16; repeat(12) @(negedge clk); w_stall=0;
  while(wact) @(negedge clk);
  wait_done(30000,"T8");
  chk("T8 done",done_latched);
  chk("T8 aborted",aborted==1);
  chk("T8 drained",drained==1);
  chk("T8 no new AW after abort",aw_n==sn_aw);
  chk("T8 no error",error==0);
  $display("T8 AW=%0d W_beats=%0d W_bytes=%0d B=%0d",aw_n,w_beats,w_bytes,b_responses);
`endif

  $display("DMA_AUDIT_RESULT errors=%0d",errors);
  if(errors!=0) $fatal(1,"DMA_AUDIT_FAIL");
  $display("DMA_AUDIT_PASS");
  $finish;
 end
endmodule
