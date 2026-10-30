`timescale 1ns/1ps
// Small multi-outstanding AXI128 slave for control/DMA logic tests.
// It accepts up to QDEP AR bursts, returns R data in AR order (no RID), and
// delays R/B responses deterministically from a seeded LFSR.  This is not a
// DDR timing model; it only exercises multiple outstanding tags and backpress.
module axi128_multi_bfm #(parameter QDEP=16)(
 input wire clk,rst_n,
 input wire [39:0] araddr,input wire [7:0] arlen,input wire [2:0] arsize,input wire [1:0] arburst,
 input wire arvalid,output wire arready,
 output reg [127:0] rdata,output reg [1:0] rresp,output reg rlast,rvalid,input wire rready,
 input wire [39:0] awaddr,input wire [7:0] awlen,input wire [2:0] awsize,input wire [1:0] awburst,
 input wire awvalid,output wire awready,
 input wire [127:0] wdata,input wire [15:0] wstrb,input wire wlast,input wire wvalid,output wire wready,
 output reg [1:0] bresp,output reg bvalid,input wire bready,
 input wire inject_read_error,inject_write_error,input wire stall_r,
 output reg [31:0] read_bursts,write_bursts,read_beats,write_beats
);
 reg [7:0] mem[0:262143];
 reg [31:0] lfsr=32'h1234567;
 function [31:0] xs(input [31:0] x);reg [31:0] t;begin t=x^(x<<13);t=t^(t>>17);t=t^(t<<5);xs=t;end endfunction
 function automatic integer off(input [39:0] a);
  begin
   if(a>=40'h0004000000&&a<40'h0004040000)off=a-40'h0004000000;
   else if(a>=40'h0010000000&&a<40'h0010010000)off=196608+(a-40'h0010000000);
   else if(a>=40'h00FFFFF000&&a<40'h0100001000)off=327680+(a-40'h00FFFFF000);
   else if(a<40'h0000001000)off=336896+a; // wrap-observation window (before-fix TB)
   else off=0;
  end
 endfunction
 function [7:0] peek(input integer a);begin peek=mem[a];end endfunction
 task poke(input integer a,input [7:0] d);begin mem[a]=d;end endtask
 function automatic okaddr(input [39:0] a);
  begin okaddr=(a>=40'h0004000000&&a<40'h0004040000)||(a>=40'h0010000000&&a<40'h0010010000)||
    (a>=40'h00FFFFF000&&a<40'h0100001000)||(a<40'h0000001000);
  end
 endfunction
 // AR tag queue
 reg [39:0] qa[0:QDEP-1];reg [8:0] qb[0:QDEP-1];
 reg [4:0] qwr=0,qrd=0,qcnt=0;
 reg [39:0] ca;reg [8:0] cb;reg [8:0] ci;
 reg have=0;reg [7:0] rwait=0;reg sending=0;
 assign arready=rst_n&&(qcnt<QDEP);
 // AW/W state
 reg awpend=0;reg [39:0] wa;reg [8:0] wn,wi;
 reg [7:0] bwait=0;
 assign awready=rst_n&&!awpend&&!bvalid&&!inject_write_error;
 assign wready=rst_n&&awpend&&!inject_write_error;
 integer k;
 integer mi;
 initial for(mi=0;mi<262144;mi=mi+1)mem[mi]=0;
 always @(posedge clk)begin
  if(!rst_n)begin
   qwr<=0;qrd<=0;qcnt<=0;have<=0;sending<=0;rwait<=0;rvalid<=0;rlast<=0;
   rdata<=0;rresp<=0;awpend<=0;wa<=0;wn<=0;wi<=0;bwait<=0;bvalid<=0;bresp<=0;
   read_bursts<=0;write_bursts<=0;read_beats<=0;write_beats<=0;
  end else begin
   lfsr<=xs(lfsr);
   rvalid<=0;rlast<=0;rresp<=inject_read_error?2'b10:0;
   if(arvalid&&arready)begin
    if(!okaddr(araddr))$fatal(1,"AR outside test windows");
    if(araddr[3:0]!=0||arsize!=3'd4||arburst!=2'd1||arlen>15) $fatal(1,"bad AR framing");
    qa[qwr[3:0]]<=araddr;qb[qwr[3:0]]<=arlen+1;qwr<=qwr+1;read_bursts<=read_bursts+1;
   end
   if(!have&&qcnt!=0)begin
    ca<=qa[qrd[3:0]];cb<=qb[qrd[3:0]];ci<=0;qrd<=qrd+1;
    have<=1;sending<=0;rwait<={1'b0,lfsr[5:0]};
   end else if(have&&!sending)begin
    if(rwait==0)sending<=1;else rwait<=rwait-1;
   end else if(sending&&!stall_r)begin
    rvalid<=1;
    rdata[0+:8]<=mem[off(ca)+ci*16+0];rdata[8+:8]<=mem[off(ca)+ci*16+1];
    rdata[16+:8]<=mem[off(ca)+ci*16+2];rdata[24+:8]<=mem[off(ca)+ci*16+3];
    rdata[32+:8]<=mem[off(ca)+ci*16+4];rdata[40+:8]<=mem[off(ca)+ci*16+5];
    rdata[48+:8]<=mem[off(ca)+ci*16+6];rdata[56+:8]<=mem[off(ca)+ci*16+7];
    rdata[64+:8]<=mem[off(ca)+ci*16+8];rdata[72+:8]<=mem[off(ca)+ci*16+9];
    rdata[80+:8]<=mem[off(ca)+ci*16+10];rdata[88+:8]<=mem[off(ca)+ci*16+11];
    rdata[96+:8]<=mem[off(ca)+ci*16+12];rdata[104+:8]<=mem[off(ca)+ci*16+13];
    rdata[112+:8]<=mem[off(ca)+ci*16+14];rdata[120+:8]<=mem[off(ca)+ci*16+15];
    rlast<=ci+1==cb;
    if(rready)begin
     read_beats<=read_beats+1;
     if(ci+1==cb)begin have<=0;sending<=0;end else ci<=ci+1;
    end
   end
   // combined queue count (push and pop can happen in the same cycle)
   qcnt<=qcnt+((arvalid&&arready)?1'b1:1'b0)-((!have&&qcnt!=0)?1'b1:1'b0);
   // writes
   if(awvalid&&awready)begin
    wa<=awaddr;wn<=awlen+1;wi<=0;awpend<=1;write_bursts<=write_bursts+1;
   end
   if(wvalid&&wready)begin
    for(k=0;k<16;k=k+1)if(wstrb[k])mem[off(wa)+wi*16+k]<=wdata[k*8+:8];
    write_beats<=write_beats+1;
    if(wi+1==wn)begin awpend<=0;bwait<={1'b0,lfsr[7:0]};end else wi<=wi+1;
   end
   if(!awpend&&!bvalid&&bwait!=0)begin
    if(bwait==1)begin bvalid<=1;bresp<=inject_write_error?2'b10:0;bwait<=0;end
    else bwait<=bwait-1;
   end
   if(bvalid&&bready)bvalid<=0;
  end
 end
endmodule
