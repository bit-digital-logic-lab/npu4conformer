`timescale 1ns/1ps
// Adversarial test of the READ-ONLY snapshot axi_dma_v020_multi
// (see reports/multi001/result.json for the exact SHA).
// Focus: multi-outstanding AR, FIFO full + same-cycle push/pop, per-channel
// stalls, early/late RLAST, RRESP/BRESP drain, WVALID bubble gating, tail
// accounting, 4KiB split, zero/unaligned and 32-bit address wrap.
module tb_dma_multi;
 reg clk=0;always #4 clk=~clk;
 integer cyc=0;always @(posedge clk)cyc<=cyc+1;
 reg rst_n=0;
 reg req_valid=0;wire req_ready;reg req_write=0;reg [31:0] req_addr=0;reg [15:0] req_beats=0;
 wire rd_valid;reg rd_ready=1;wire [127:0] rd_data;wire [15:0] rd_index;
 reg wr_valid=0;wire wr_ready;reg [127:0] wr_data=0;reg [15:0] wr_strobe=16'hffff;wire [15:0] wr_index;
 wire done,error;wire [31:0] rd_bytes,wr_bytes,rd_bursts,wr_bursts;
 wire [31:0] ar_max,b_max;wire [63:0] rbub,wbub,rfifo;
 wire [39:0] araddr;wire [7:0] arlen;wire [2:0] arsize;wire [1:0] arburst;
 wire [3:0] arcache;wire [2:0] arprot;wire arvalid;wire arready;
 wire [127:0] rdata;wire [1:0] rresp;wire rlast,rvalid;wire rready;
 wire [39:0] awaddr;wire [7:0] awlen;wire [2:0] awsize;wire [1:0] awburst;
 wire [3:0] awcache;wire [2:0] awprot;wire awvalid;wire awready;
 wire [127:0] wdata;wire [15:0] wstrb;wire wlast,wvalid;wire wready;
 reg [1:0] bresp=0;reg bvalid=0;wire bready;
 axi_dma_v020_multi_v2 dut(.clk(clk),.rst_n(rst_n),
  .request_valid(req_valid),.request_ready(req_ready),.request_write(req_write),
  .request_address(req_addr),.request_beats(req_beats),
  .read_valid(rd_valid),.read_ready(rd_ready),.read_data(rd_data),.read_index(rd_index),
  .write_valid(wr_valid),.write_ready(wr_ready),.write_data(wr_data),.write_strobe(wr_strobe),.write_index(wr_index),
  .done(done),.error(error),.read_bytes(rd_bytes),.write_bytes(wr_bytes),.read_bursts(rd_bursts),.write_bursts(wr_bursts),
  .ar_outstanding_max(ar_max),.b_outstanding_max(b_max),.read_bubble_cycles(rbub),.write_bubble_cycles(wbub),.read_fifo_high(rfifo),
  .m_axi_araddr(araddr),.m_axi_arlen(arlen),.m_axi_arsize(arsize),.m_axi_arburst(arburst),.m_axi_arcache(arcache),.m_axi_arprot(arprot),
  .m_axi_arvalid(arvalid),.m_axi_arready(arready),.m_axi_rdata(rdata),.m_axi_rresp(rresp),.m_axi_rlast(rlast),.m_axi_rvalid(rvalid),.m_axi_rready(rready),
  .m_axi_awaddr(awaddr),.m_axi_awlen(awlen),.m_axi_awsize(awsize),.m_axi_awburst(awburst),.m_axi_awcache(awcache),.m_axi_awprot(awprot),
  .m_axi_awvalid(awvalid),.m_axi_awready(awready),.m_axi_wdata(wdata),.m_axi_wstrb(wstrb),.m_axi_wlast(wlast),.m_axi_wvalid(wvalid),.m_axi_wready(wready),
  .m_axi_bresp(bresp),.m_axi_bvalid(bvalid),.m_axi_bready(bready));
 integer errors=0; integer trace=0; integer check_en=1;
 task chk(input [255:0] what,input cond);begin if(!cond)begin errors=errors+1;$display("FAIL %0s",what);$fflush();end end endtask
 function [127:0] gen(input [39:0] a);integer l;begin for(l=0;l<16;l=l+1)gen[l*8+:8]=a[7:0]+l;end endfunction
 function [7:0] pat(input [39:0] a);begin pat=a[7:0];end endfunction
 function integer midx(input [39:0] a);begin midx=a[19:0];end endfunction
 reg [7:0] mem[0:524287];
 // ----- read slave -----
 reg [31:0] lfsr=32'h1;
 function [31:0] xs(input [31:0] x);reg [31:0] t;begin t=x^(x<<13);t=t^(t>>17);t=t^(t<<5);xs=t;end endfunction
 wire [31:0] nr=xs(lfsr);
 always @(posedge clk) lfsr<=xs(lfsr);
 reg [39:0] qa[0:15];reg [7:0] ql[0:15];integer qh=0,qt=0,qc=0;
 reg [39:0] ca0=0,ca1=0;integer ar_count=0;
 reg r_act=0;reg [39:0] ca=0;reg [7:0] cb=0;reg [7:0] clen=0;reg [7:0] tgt=0;reg [2:0] rw=0;
 integer r_mode=0;integer rresp_at=-1;reg [31:0] rd_seen=0;
 assign rvalid = r_act && (rw==0);
 assign rlast = r_act && (cb+1==tgt);
 assign rdata = gen(ca + cb*16);
 assign rresp = (rresp_at>=0 && rd_seen==rresp_at)?2'b10:2'b00;
 assign arready = rst_n && (qc<16) && !(nr[0]);
 always @(posedge clk)begin
  if(!rst_n)begin r_act<=0;qh<=0;qt<=0;qc<=0;rw<=0;rd_seen<=0;ca0<=0;ca1<=0;ar_count<=0;end
  else begin
   if(arvalid&&arready)begin if(trace)$display("AR t=%0t a=%h l=%0d qc=%0d",$time,araddr,arlen,qc);$fflush();
    if(ar_count==0)ca0<=araddr;else if(ar_count==1)ca1<=araddr;
    ar_count<=ar_count+1;
    qa[qt]=araddr;ql[qt]=arlen+1;qt<=(qt+1)%16;end
   if(!r_act && qc>0)begin
    ca<=qa[qh];clen<=ql[qh];
    if(trace)$display("BSTART t=%0t ca=%h tgt=%0d",$time,qa[qh],ql[qh]);$fflush();
    tgt<= (r_mode==1)?(ql[qh]-1):(r_mode==2)?(ql[qh]+1):ql[qh];
    qh<=(qh+1)%16;cb<=0;rw<=nr[2:0];r_act<=1;
   end else if(r_act)begin
    if(rw>0)rw<=rw-1;
    if(rvalid&&rready)begin
     rd_seen<=rd_seen+1;
     if(rlast)r_act<=0;else cb<=cb+1;
    end
   end
   qc<=qc+(arvalid&&arready?1:0)-((!r_act&&qc>0)?1:0);
  end
 end
 // ----- write slave: AW queue, one W context, delayed B queue -----
 reg [39:0] wa[0:15];reg [7:0] wl[0:15];reg [7:0] wid[0:15];integer wh=0,wt=0,wc=0;
 reg w_act=0;reg [39:0] cwa=0;reg [7:0] cwl=0;reg [7:0] wb=0;reg [7:0] cwid=0;
 reg [31:0] btime[0:15];reg [7:0] bid[0:15];integer bh=0,bt=0,bc=0;
 integer awidx=0;integer bresp_burst=-1;integer bdelay=2;integer now=0;
 wire aw_hs = awvalid&&awready;
 wire w_hs  = wvalid&&wready;
 wire b_hs  = bvalid&&bready;
 wire w_push = w_hs&&wlast;
 wire wstart = !w_act&&wc>0;
 wire bpush = w_push;
 assign wready = w_act && !(nr[8]);
 assign awready = rst_n && (wc<16) && !(nr[9]);
 always @(posedge clk)begin
  now<=now+1;
  if(!rst_n)begin w_act<=0;wh<=0;wt<=0;wc<=0;bh<=0;bt<=0;bc<=0;bvalid<=0;end
  else begin
   if(aw_hs)begin wa[wt]=awaddr;wl[wt]=awlen+1;wid[wt]=awidx;wt<=(wt+1)%16;awidx<=awidx+1;end
   if(wstart)begin cwa<=wa[wh];cwl<=wl[wh];cwid<=wid[wh];wh<=(wh+1)%16;wb<=0;w_act<=1;end
   else if(w_act)begin
    if(w_hs)begin
     if(trace)$display("WH t=%0t wb=%0d strb=%h d0=%h last=%0d",$time,wb,wstrb,wdata[7:0],wlast);$fflush();
     for(integer k=0;k<16;k=k+1)if(wstrb[k])begin mem[midx(cwa)+wb*16+k]<=wdata[k*8+:8]; if(trace&&(midx(cwa)+wb*16+k)==20'h20033)$display("WR51 t=%0t wb=%0d k=%0d strb=%h",$time,wb,k,wstrb);$fflush(); end
     if(wlast)begin w_act<=0;btime[bt]=now+bdelay;bid[bt]=cwid;bt<=(bt+1)%16;end
     else wb<=wb+1;
    end
   end
   wc<=wc+(aw_hs?1:0)-(wstart?1:0);
   if(b_hs)begin bvalid<=0;bh<=(bh+1)%16;end
   else if(!bvalid && bc>0 && now>=btime[bh])begin bvalid<=1;bresp<=(bid[bh]==bresp_burst)?2'b10:2'b00;end
   bc<=bc+(bpush?1:0)-(b_hs?1:0);
  end
 end
// ----- W producer: optional valid bubbles, tail strobe -----
 reg wact=0;integer wn=0,wbeat=0,wtail=-1;integer wgap=0;reg [7:0] bub=0;reg [31:0] wbase=0;
 always @* begin
  wr_valid = wact && (wbeat<wn) && (bub==0);
  wr_data = gen(wbase+wbeat*16);
  if(wbeat==wn-1 && wtail>=0)wr_strobe=(16'h1<<wtail)-1;else wr_strobe=16'hffff;
 end
 always @(posedge clk)begin
  if(!rst_n)begin wact<=0;bub<=0;end
  else if(wact)begin
   if(bub>0)bub<=bub-1;
   else if(wr_valid&&wr_ready)begin
    if(wbeat+1==wn)wact<=0;
    else begin wbeat<=wbeat+1;bub<=wgap;end
   end
  end
 end
 task do_reset;begin
  rst_n=0;req_valid=0;rd_ready=1;wact=0;bub=0;wgap=0;r_mode=0;rresp_at=-1;bresp_burst=-1;bdelay=2;awidx=0;
  repeat(5)@(negedge clk);rst_n=1;repeat(2)@(negedge clk);
 end endtask
 task issue_req(input w,input [31:0] a,input [15:0] b);begin
  @(negedge clk);req_write=w;req_addr=a;req_beats=b;req_valid=1;
  while(!req_ready)@(negedge clk);
  @(posedge clk);@(negedge clk);req_valid=0;
 end endtask
 integer b_rd,b_wr,b_rb,b_wb;
 task snap;begin b_rd=rd_bytes;b_wr=wr_bytes;b_rb=rd_bursts;b_wb=wr_bursts;end endtask
 integer derr=0;
 always @(negedge clk) begin
  #1;
  if(rst_n&&check_en&&rd_valid&&rd_ready)begin
   if(trace)$display("POP t=%0t idx=%0d d0=%h",$time,rd_index,rd_data[7:0]);$fflush();
   if(rd_data!==gen(req_addr+rd_index*16))begin derr=derr+1;if(derr<4)$display("FAIL RDATA idx=%0d got=%h exp=%h",rd_index,rd_data,gen(req_addr+rd_index*16));end
  end
 end
  integer i;
 initial begin
  for(i=0;i<524288;i=i+1)mem[i]=0;
  // R1 multi-outstanding read
  do_reset;snap;
  issue_req(0,32'h04000000,64);
  while(!done)@(posedge clk);@(negedge clk);
  chk("R1 no error",!error);chk("R1 bytes",rd_bytes-b_rd==1024);chk("R1 index",rd_index==64);chk("R1 multi AR",ar_max>=2);
  $display("R1 read64 err=%0d bytes=%0d bursts=%0d armax=%0d fifohi=%0d rbub=%0d",error,rd_bytes-b_rd,rd_bursts-b_rb,ar_max,rfifo,rbub);$fflush();
  // R2 FIFO full with stopped consumer
  do_reset;snap;
  @(negedge clk);rd_ready=0;
  issue_req(0,32'h04000000,256);
  repeat(600)@(posedge clk);
  chk("R2 fifo high",rfifo==128);
  @(negedge clk);rd_ready=1;
  while(!done)@(posedge clk);
  @(negedge clk);
  chk("R2 no error",!error);chk("R2 index",rd_index==256);chk("R2 bytes",rd_bytes-b_rd==4096);
  $display("R2 fifo_full err=%0d fifohi=%0d bytes=%0d index=%0d",error,rfifo,rd_bytes-b_rd,rd_index);$fflush();
  // R3 same-cycle push/pop
  do_reset;snap;
  fork
   begin issue_req(0,32'h04002000,256);while(!done)@(posedge clk);end
   begin repeat(700)begin @(negedge clk);rd_ready=~rd_ready;end end
  join
  @(negedge clk);rd_ready=1;
  chk("R3 no error",!error);chk("R3 bytes",rd_bytes-b_rd==4096);
  $display("R3 pushpop err=%0d bytes=%0d index=%0d fifohi=%0d",error,rd_bytes-b_rd,rd_index,rfifo);$fflush();
  // R4 4KiB split
  do_reset;snap;lfsr=32'h55;
  issue_req(0,32'h04000FF0,16);
  while(!done)@(posedge clk);@(negedge clk);
  chk("R4 split",rd_bursts-b_rb==2);
  $display("R4 4k bursts=%0d bytes=%0d",rd_bursts-b_rb,rd_bytes-b_rd);$fflush();
  // R5 RRESP error
  do_reset;snap;rresp_at=17;trace=1;
  issue_req(0,32'h04003000,64);
  while(!done)@(posedge clk);@(negedge clk);
  chk("R5 rresp",error==1);
  $display("R5 rresp err=%0d bytes=%0d",error,rd_bytes-b_rd);$fflush();trace=0;
  // R6/R7 early/late rlast
  do_reset;snap;check_en=0;r_mode=1;
  issue_req(0,32'h04004000,32);
  while(!done)@(posedge clk);@(negedge clk);
  chk("R6 early",error==1);$display("R6 early err=%0d",error);$fflush();
  do_reset;snap;r_mode=2;
  issue_req(0,32'h04004800,32);
  while(!done)@(posedge clk);@(negedge clk);
  chk("R7 late",error==1);$display("R7 late err=%0d",error);$fflush();check_en=1;
  // W1 normal write 64
  do_reset;snap;bdelay=2;
  issue_req(1,32'h04100000,64);
  @(negedge clk);wbase=32'h04100000;wn=64;wtail=-1;wbeat=0;bub=0;wgap=0;wact=1;
  while(wact)@(negedge clk);
  while(!done)@(posedge clk);@(negedge clk);
  chk("W1 no error",!error);chk("W1 bytes",wr_bytes-b_wr==1024);
  for(i=0;i<1024;i=i+1)chk("W1 mem",mem[midx(32'h04100000)+i]==pat(32'h04100000+i));
  $display("W1 write64 err=%0d bytes=%0d bursts=%0d bmax=%0d",error,wr_bytes-b_wr,wr_bursts-b_wb,b_max);$fflush();
  // W2 WVALID bubbles + tail strobe
  do_reset;snap;trace=1;
  issue_req(1,32'h04200000,4);
  @(negedge clk);wbase=32'h04200000;wn=4;wtail=3;wbeat=0;bub=0;wgap=3;wact=1;
  while(wact)@(negedge clk);
  while(!done)@(posedge clk);@(negedge clk);
  chk("W2 no error",!error);
  for(i=0;i<3;i=i+1)chk("W2 tail data",mem[midx(32'h04200000)+48+i]==pat(32'h04200000+48+i));
  for(i=0;i<48;i=i+1)chk("W2 full data",mem[midx(32'h04200000)+i]==pat(32'h04200000+i));
  $display("W2 bubble_tail err=%0d bytes=%0d",error,wr_bytes-b_wr);$fflush();trace=0;
  chk("W2 write_bytes WSTRB",(wr_bytes-b_wr)==51);
  $display("W2 write_bytes=%0d (expect 51)",wr_bytes-b_wr);$fflush();
  // W3 delayed Bs: b_outstanding_max
  do_reset;snap;bdelay=20;
  issue_req(1,32'h04300000,64);
  @(negedge clk);wbase=32'h04300000;wn=64;wtail=-1;wbeat=0;bub=0;wgap=0;wact=1;
  while(wact)@(negedge clk);
  while(!done)@(posedge clk);@(negedge clk);
  chk("W3 no error",!error);chk("W3 bmax>=2",b_max>=2);
  $display("W3 delayedB err=%0d bmax=%0d bytes=%0d",error,b_max,wr_bytes-b_wr);$fflush();
  // W4 BRESP error on second AW
  do_reset;snap;bdelay=3;bresp_burst=1;
  issue_req(1,32'h04400000,64);
  @(negedge clk);wbase=32'h04400000;wn=64;wtail=-1;wbeat=0;bub=0;wgap=0;wact=1;
  for(i=0;i<20000 && !done;i=i+1)@(posedge clk);
  @(negedge clk);wact=0;bub=0;
  chk("W4 bresp",error==1);
  $display("W4 bresp err=%0d aws=%0d",error,awidx);$fflush();
  // Z zero/unaligned
  do_reset;snap;
  issue_req(0,32'h04000000,0);while(!done)@(posedge clk);@(negedge clk);
  chk("Z1 zero",error==1 && rd_bursts==b_rb);
  issue_req(0,32'h04000008,4);while(!done)@(posedge clk);@(negedge clk);
  chk("Z2 unaligned",error==1);
  $display("Z zero_unaligned");$fflush();
  // X 4GiB crossing: internal 40-bit address must not wrap to zero.
  do_reset;snap;lfsr=32'h77;
  issue_req(0,32'hFFFFFFF0,2);
  while(!done)@(posedge clk);@(negedge clk);
  $display("X wrap bursts=%0d err=%0d a0=%h a1=%h",rd_bursts-b_rb,error,ca0,ca1);$fflush();
  chk("X no wrap to zero",(rd_bursts-b_rb)==2 && ca0==40'h0000FFFFFFF0 && ca1==40'h0100000000);
  errors=errors+derr;
  $display("MULTI_TEST_END errors=%0d",errors);$fflush();
  $finish;
 end
 initial begin : gtimeout
  repeat(2000000)@(posedge clk);$display("MULTI_TIMEOUT errors=%0d",errors);$fflush();$finish;
 end
endmodule
