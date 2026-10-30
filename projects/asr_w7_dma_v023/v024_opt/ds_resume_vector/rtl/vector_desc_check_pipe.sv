`timescale 1ns/1ps
// Pipelined descriptor validation for the v023 vector engine.
// Same predicate as the baseline combinational `invalid_descriptor`, split into
// V1 (format/flags), V2 (sizes + destination window) and V3 (source windows).
// No DMA side effect exists until V3 has produced a valid snapshot.
module vector_desc_check_pipe #(
 parameter [31:0] ARENA_BASE=32'h04000000,ARENA_END=32'h08000000,
 parameter [31:0] PARAM_BASE=32'h10000000,PARAM_END=32'h40000000
)(
 input wire clk,rst_n,
 input wire in_valid,
 input wire [511:0] descriptor,
 input wire [31:0] param_end,
 output wire in_ready,
 output reg out_valid,
 output reg out_invalid,
 output reg [511:0] out_cfg
);
 localparam [31:0] MAGIC=32'h22564543;
 assign in_ready=1'b1;

 function automatic readable(input [31:0] p,input [63:0] bytes);
  reg [63:0] e;
  begin
   e=({32'd0,p}&~64'd15)+((bytes+{60'd0,p[3:0]}+15)&~64'd15);
   readable=bytes!=0&&((p>=32'h03000000&&e<=ARENA_END)||
     (p>=PARAM_BASE&&e<=param_end&&param_end<=PARAM_END));
  end
 endfunction
 function automatic overlap(input [31:0] p,input [63:0] bytes,input [31:0] d,input [63:0] dn);
  begin overlap={32'd0,p}<({32'd0,d}+dn)&&{32'd0,d}<({32'd0,p}+bytes);end
 endfunction

 // format/flag predicate, evaluated on one descriptor snapshot
 function automatic bad_format(input [511:0] d);
  reg [7:0] op;reg [31:0] count,period;
  begin
   op=d[39:32];count=d[223:192];period=d[255:224];
   bad_format = d[31:0]!=MAGIC || d[63:47]!=0 || d[511:256]!=0 ||
    count==0 || count>16777216 || !(op<=15||op==17) ||
    (period!=0&&(d[42]||!(op<=3||op==9||op==10||op==11||op==14||op==17)||d[45]||period>4096||
     (!d[46]&&(period&(period-1))!=0))) ||
    (d[46]&&(period==0||count[9:0]!=0)) ||
    (d[40]&&d[45]) || (d[45]&&(op!=14||d[43]||d[42])) ||
    (d[41]&&op!=15) || (d[44]&&op!=17);
  end
 endfunction

 // sizes + destination window; one 64-bit multiply cone per stage
 function automatic bad_dest(input [511:0] d);
  reg [31:0] count,period,sd,sa;reg [63:0] an,dn;
  begin
   count=d[223:192];period=d[255:224];sd=d[191:160];sa=d[95:64];
   an=(d[43]?64'd1:{32'd0,count})*(d[45]?6:d[40]?2:4);
   dn={32'd0,count}*(d[41]?2:4);
   bad_dest = sd[3:0]!=0 || sd<ARENA_BASE ||
    {32'd0,sd}+((dn+15)&~64'd15)>ARENA_END ||
    ((sa&(d[40]||d[45]?1:3))!=0) ||
    !readable(sa,an) ||
    overlap(sa,an,sd,dn);
  end
 endfunction

 // source B/C windows
 function automatic bad_sources(input [511:0] d);
  reg [7:0] op;reg [31:0] count,period,sb,sc,sd;reg [63:0] bn,cn,dn;
  begin
   op=d[39:32];count=d[223:192];period=d[255:224];sb=d[127:96];sc=d[159:128];sd=d[191:160];
   bn=(d[42]?64'd1:d[46]?(({32'd0,period}+31)&~64'd31):
     period!=0?{32'd0,period}:{32'd0,count})*4;
   cn=(d[44]?64'd1:{32'd0,count})*4;
   dn={32'd0,count}*(d[41]?2:4);
   bad_sources =
    ((op<=3||op==9||op==10||op==11||op==14||op==17)&&!d[45]&&
     (sb[1:0]!=0||!readable(sb,bn)||overlap(sb,bn,sd,dn)))||
    (op==17&&(sc[1:0]!=0||!readable(sc,cn)||
     overlap(sc,cn,sd,dn)));
  end
 endfunction

 reg v1,v2,v3;
 reg [511:0] d1,d2,d3;
 reg q1,q2,q3;
 always @(posedge clk) begin
  if(!rst_n) begin
   v1<=0;v2<=0;v3<=0;d1<=0;d2<=0;d3<=0;q1<=0;q2<=0;q3<=0;
   out_valid<=0;out_invalid<=0;out_cfg<=0;
  end else begin
   v1<=in_valid;
   if(in_valid) begin d1<=descriptor;q1<=bad_format(descriptor);end
   v2<=v1;
   if(v1) begin d2<=d1;q2<=q1|bad_dest(d1);end
   v3<=v2;
   if(v2) begin d3<=d2;q3<=q2|bad_sources(d2);end
   out_valid<=v3;
   if(v3) begin out_cfg<=d3;out_invalid<=q3;end
  end
 end
endmodule
