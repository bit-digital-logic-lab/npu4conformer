`timescale 1ns/1ps
// Shared-memory AXI128 BFM: independent ports, deterministic stalls, 4KiB checks.
// This is protocol evidence only; it is NOT a timing model of the board DDR.
module axi128_memory_bfm_v1 #(parameter PORTS=2)(
 input wire clk,rst_n,input wire [PORTS*40-1:0] araddr,input wire [PORTS*8-1:0] arlen,
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
 output reg [31:0] read_bursts,write_bursts,read_beats,write_beats);
 reg [7:0] memory[0:262143];integer cycle=0;
 function automatic integer offset(input [39:0] a);
  begin offset=a-40'h0003000000; end
 endfunction
 function automatic valid_address(input [39:0] a);
  begin valid_address=(^a!==1'bx)&&(a>=40'h0003000000)&&(a<40'h0003020000);end
 endfunction
 reg ra[0:PORTS-1],visible[0:PORTS-1],wa[0:PORTS-1],bp[0:PORTS-1];
 reg [39:0] rab[0:PORTS-1],wab[0:PORTS-1];
 reg [8:0] rn[0:PORTS-1],wn[0:PORTS-1],ri[0:PORTS-1],wi[0:PORTS-1];
 reg [2:0] bd[0:PORTS-1];
 generate for(genvar port=0;port<PORTS;port=port+1)begin:p
  assign arready[port]=rst_n&&!ra[port]&&cycle%7!=port;
  assign rvalid[port]=ra[port]&&visible[port];
  assign rlast[port]=ri[port]+1==rn[port];
  assign rresp[port*2+:2]=inject_read_error?2'b10:0;
  for(genvar lane=0;lane<16;lane=lane+1)assign rdata[port*128+lane*8+:8]=ra[port]?memory[offset(rab[port])+ri[port]*16+lane]:0;
  assign awready[port]=rst_n&&!wa[port]&&!bp[port]&&bd[port]==0&&cycle%9!=port;
  assign wready[port]=wa[port]&&cycle%5!=port;
  assign bvalid[port]=bp[port];assign bresp[port*2+:2]=inject_write_error?2'b10:0;
 end endgenerate
 always @(posedge clk)begin
  if(!rst_n)begin
   cycle<=0;read_bursts<=0;write_bursts<=0;read_beats<=0;write_beats<=0;
   for(integer port=0;port<PORTS;port=port+1)begin ra[port]<=0;visible[port]<=0;wa[port]<=0;bp[port]<=0;bd[port]<=0;ri[port]<=0;wi[port]<=0;rab[port]<=0;wab[port]<=0;rn[port]<=0;wn[port]<=0;end
  end else begin
   cycle<=cycle+1;
   for(integer port=0;port<PORTS;port=port+1)begin
    if(arvalid[port]&&arready[port])begin
     if(!valid_address(araddr[port*40+:40]))$fatal(1,"AXI AR outside private memory");
     if(araddr[port*40+:4]||arsize[port*3+:3]!=4||arburst[port*2+:2]!=1||arlen[port*8+:8]>15||
        ({1'b0,araddr[port*40+:12]}+((arlen[port*8+:8]+1)*16))>4096)$fatal(1,"AXI AR burst framing");
     rab[port]<=araddr[port*40+:40];rn[port]<=arlen[port*8+:8]+1;ri[port]<=0;ra[port]<=1;visible[port]<=0;
     read_bursts<=read_bursts+1;
    end
    if(ra[port]&&!visible[port]&&cycle%4!=port)visible[port]<=1;
    if(rvalid[port]&&rready[port])begin
     read_beats<=read_beats+1;visible[port]<=0;
     if(ri[port]+1==rn[port])ra[port]<=0;else ri[port]<=ri[port]+1;
    end
    if(awvalid[port]&&awready[port])begin
     if(!valid_address(awaddr[port*40+:40]))$fatal(1,"AXI AW outside private memory");
     if(awaddr[port*40+:4]||awsize[port*3+:3]!=4||awburst[port*2+:2]!=1||awlen[port*8+:8]>15||
        ({1'b0,awaddr[port*40+:12]}+((awlen[port*8+:8]+1)*16))>4096)$fatal(1,"AXI AW burst framing");
     wab[port]<=awaddr[port*40+:40];wn[port]<=awlen[port*8+:8]+1;wi[port]<=0;wa[port]<=1;write_bursts<=write_bursts+1;
    end
    if(wvalid[port]&&wready[port])begin
     if(wlast[port]!=(wi[port]+1==wn[port]))$fatal(1,"AXI WLAST");
     for(integer lane=0;lane<16;lane=lane+1)if(wstrb[port*16+lane])memory[offset(wab[port])+wi[port]*16+lane]<=wdata[port*128+lane*8+:8];
     write_beats<=write_beats+1;
     if(wi[port]+1==wn[port])begin wa[port]<=0;bd[port]<=3;end else wi[port]<=wi[port]+1;
    end
    if(bd[port]!=0)begin bd[port]<=bd[port]-1;if(bd[port]==1)bp[port]<=1;end
    if(bvalid[port]&&bready[port])bp[port]<=0;
   end
  end
 end
endmodule
