`timescale 1ns/1ps
// Sparse AXI4 128-bit memory BFM for the WCPG v2 tests.  It is a logic model,
// not a DDR timing model.  Windows:
//   0x03000000..0x0303ffff -> 0x00000..0x3ffff  scratch
//   0x04000000..0x0403ffff -> 0x40000..0x7ffff  intermediate
//   0x08000000..0x0803ffff -> 0x80000..0xbffff  external boundary I/O
//   0x10000000..0x1003ffff -> 0xc0000..0xfffff  parameter/plan (read-only)
module wc_graph_bfm #(parameter PORTS=1,parameter PROTECT_PARAM=1,parameter PORT_OFFSET=0)(
 input wire clk,rst_n,
 input wire [PORTS*40-1:0] araddr,input wire [PORTS*8-1:0] arlen,
 input wire [PORTS*3-1:0] arsize,input wire [PORTS*2-1:0] arburst,
 input wire [PORTS-1:0] arvalid,output wire [PORTS-1:0] arready,
 output wire [PORTS*128-1:0] rdata,output wire [PORTS*2-1:0] rresp,
 output wire [PORTS-1:0] rlast,rvalid,input wire [PORTS-1:0] rready,
 input wire [PORTS*40-1:0] awaddr,input wire [PORTS*8-1:0] awlen,
 input wire [PORTS*3-1:0] awsize,input wire [PORTS*2-1:0] awburst,
 input wire [PORTS-1:0] awvalid,output wire [PORTS-1:0] awready,
 input wire [PORTS*128-1:0] wdata,input wire [PORTS*16-1:0] wstrb,
 input wire [PORTS-1:0] wlast,wvalid,output wire [PORTS-1:0] wready,
 output wire [PORTS*2-1:0] bresp,output wire [PORTS-1:0] bvalid,input wire [PORTS-1:0] bready,
 input wire inject_read_error,inject_write_error,
 output reg [31:0] read_bursts,write_bursts,read_beats,write_beats
);
 reg [31:0] memw[0:262143]; // 1 MiB
 integer cycle=0;
 reg [1023:0] memfile;
 reg [31:0] lfsr;
 integer seed;
 initial begin if(!$value$plusargs("seed=%d",seed))seed=1;lfsr=seed|1;end
 always @(posedge clk)lfsr<={lfsr[30:0],lfsr[31]^lfsr[21]^lfsr[1]^lfsr[0]};
 initial if($value$plusargs("memfile=%s",memfile))$readmemh(memfile,memw);
 function automatic integer win_offset(input [39:0] a);
  begin
   if(a>=40'h0003000000&&a<40'h0003040000)win_offset=a-40'h0003000000;
   else if(a>=40'h0004000000&&a<40'h0004040000)win_offset=32'h00040000+(a-40'h0004000000);
   else if(a>=40'h0008000000&&a<40'h0008040000)win_offset=32'h00080000+(a-40'h0008000000);
   else if(a>=40'h0010000000&&a<40'h0010040000)win_offset=32'h000c0000+(a-40'h0010000000);
   else win_offset=-1;
  end
 endfunction
 function automatic in_param(input [39:0] a);
  begin in_param=(a>=40'h0010000000&&a<40'h0010040000);end
 endfunction
 function automatic valid_address(input [39:0] a);
  begin valid_address=(^a!==1'bx)&&win_offset(a)>=0;end
 endfunction
 reg ra[0:PORTS-1],vis[0:PORTS-1],wa[0:PORTS-1],bp[0:PORTS-1];
 reg [39:0] rab[0:PORTS-1],wab[0:PORTS-1];
 reg [8:0] rn[0:PORTS-1],wn[0:PORTS-1],ri[0:PORTS-1],wi[0:PORTS-1];
 reg [2:0] bd[0:PORTS-1];
 generate for(genvar port=0;port<PORTS;port=port+1)begin:p
  assign arready[port]=rst_n&&!ra[port]&&((cycle+port+PORT_OFFSET)%7!=0)&&(lfsr[2:0]!=3'd0);
  assign rvalid[port]=ra[port]&&vis[port];
  assign rlast[port]=ri[port]+1==rn[port];
  assign rresp[port*2+:2]=inject_read_error?2'b10:0;
  for(genvar lane=0;lane<16;lane=lane+1)begin:rd
   wire [31:0] off=(win_offset(rab[port])+ri[port]*16+lane)>>2;
   wire [7:0] by=(win_offset(rab[port])+ri[port]*16+lane)&3;
   assign rdata[port*128+lane*8+:8]=ra[port]?memw[off][by*8+:8]:8'h00;
  end
  assign awready[port]=rst_n&&!wa[port]&&!bp[port]&&bd[port]==0&&((cycle+2*(port+PORT_OFFSET))%9!=0);
  assign wready[port]=wa[port]&&((cycle+port+PORT_OFFSET)%5!=0)&&(lfsr[5:3]!=3'd0);
  assign bvalid[port]=bp[port];assign bresp[port*2+:2]=inject_write_error?2'b10:0;
 end endgenerate
 always @(posedge clk)begin
  if(!rst_n)begin
   cycle<=0;read_bursts<=0;write_bursts<=0;read_beats<=0;write_beats<=0;
   for(integer port=0;port<PORTS;port=port+1)begin
    ra[port]<=0;vis[port]<=0;wa[port]<=0;bp[port]<=0;bd[port]<=0;
    ri[port]<=0;wi[port]<=0;rab[port]<=0;wab[port]<=0;rn[port]<=0;wn[port]<=0;
   end
  end else begin
   cycle<=cycle+1;
   for(integer port=0;port<PORTS;port=port+1)begin
    if(arvalid[port]&&arready[port])begin
     $display("DBGAR cyc=%0d p=%0d a=%h len=%0d",cycle,port,araddr[port*40+:40],arlen[port*8+:8]);
     if(!valid_address(araddr[port*40+:40]))$fatal(1,"AR outside model windows %h",araddr[port*40+:40]);
     if(araddr[port*40+:4]!=0||arsize[port*3+:3]!=4||arburst[port*2+:2]!=1||arlen[port*8+:8]>15||
        ({1'b0,araddr[port*40+:12]}+((arlen[port*8+:8]+1)*16))>4096)$fatal(1,"AR burst framing");
     rab[port]<=araddr[port*40+:40];rn[port]<=arlen[port*8+:8]+1;ri[port]<=0;ra[port]<=1;vis[port]<=0;
     read_bursts<=read_bursts+1;
    end
    if(ra[port]&&!vis[port]&&((cycle+port+PORT_OFFSET)%4!=0))vis[port]<=1;
    if(rvalid[port]&&rready[port])begin
     read_beats<=read_beats+1;vis[port]<=0;
     if(ri[port]+1==rn[port])ra[port]<=0;else ri[port]<=ri[port]+1;
    end
    if(awvalid[port]&&awready[port])begin
     $display("DBGAW cyc=%0d p=%0d a=%h len=%0d",cycle,port,awaddr[port*40+:40],awlen[port*8+:8]);
     if(!valid_address(awaddr[port*40+:40]))$fatal(1,"AW outside model windows %h",awaddr[port*40+:40]);
     if(PROTECT_PARAM&&in_param(awaddr[port*40+:40]))$fatal(1,"WRITE TO READ-ONLY PARAMETER %h",awaddr[port*40+:40]);
     if(awaddr[port*40+:4]!=0||awsize[port*3+:3]!=4||awburst[port*2+:2]!=1||awlen[port*8+:8]>15||
        ({1'b0,awaddr[port*40+:12]}+((awlen[port*8+:8]+1)*16))>4096)$fatal(1,"AW burst framing");
     wab[port]<=awaddr[port*40+:40];wn[port]<=awlen[port*8+:8]+1;wi[port]<=0;wa[port]<=1;
     write_bursts<=write_bursts+1;
    end
    if(wvalid[port]&&wready[port])begin
     if(wlast[port]!=(wi[port]+1==wn[port]))$fatal(1,"WLAST mismatch");
     for(integer lane=0;lane<16;lane=lane+1)begin
      if(wstrb[port*16+lane])
       memw[(win_offset(wab[port])+wi[port]*16+lane)>>2]
           [((win_offset(wab[port])+wi[port]*16+lane)&3)*8+:8]<=wdata[port*128+lane*8+:8];
     end
     write_beats<=write_beats+1;
     if(wi[port]+1==wn[port])begin wa[port]<=0;bd[port]<=3;end else wi[port]<=wi[port]+1;
    end
    if(bd[port]!=0)begin bd[port]<=bd[port]-1;if(bd[port]==1)bp[port]<=1;end
    if(bvalid[port]&&bready[port])bp[port]<=0;
   end
  end
 end
 // Testbench-only helpers.  Offsets are window offsets (not absolute).
 task poke(input integer off,input [7:0] v);begin memw[off>>2][(off&3)*8+:8]=v;end endtask
 task poke32(input integer off,input [31:0] v);begin memw[off>>2]=v;end endtask
 function [31:0] peek32(input integer off);begin peek32=memw[off>>2];end endfunction
endmodule
