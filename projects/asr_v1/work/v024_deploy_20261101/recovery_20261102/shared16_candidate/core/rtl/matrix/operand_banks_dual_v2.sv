`timescale 1ns/1ps
// Same combinational read / synchronous write contract as the original.
// Each generated row/column owns one one-dimensional RAM and one write port.
module operand_banks_dual_v1(
 input wire clk,
 input wire wr_en,input wire wr_stage,input wire wr_kind,
 input wire [7:0] wr_beat,input wire [127:0] wr_data,
 input wire rd_stage,input wire rd_row_half,rd_col_half,
 input wire [79:0] a_k,input wire [79:0] w_k,
 output wire [255:0] a_values,output wire [111:0] w_values
);
 wire [3:0] aw_rowbank=wr_beat[5:2];
 wire [2:0] aw_entry={wr_beat[6],wr_beat[1:0]};
 // Preserve the original truncation/alias behavior for wr_beat[7:6].
 wire [4:0] ww_k=wr_beat[6:1];
 wire ww_half=wr_beat[0];
 genvar s,r,c;
 wire [255:0] a_stage_val[0:1];
 wire [111:0] w_stage_val[0:1];
 generate
  for(s=0;s<2;s=s+1)begin:astage
   for(r=0;r<16;r=r+1)begin:arow
    (* ram_style="distributed" *) reg [127:0] mem[0:7];
    always @(posedge clk)
     if(wr_en&&wr_kind==1'b0&&wr_stage==s&&aw_rowbank==r)
      mem[aw_entry]<=wr_data;
    wire [4:0] kk=a_k[r*5+:5];
    wire [127:0] chunk=mem[{rd_row_half,kk[4:3]}];
    wire [15:0] value=chunk[kk[2:0]*16+:16];
    assign a_stage_val[s][r*16+:16]=value;
   end
  end
  for(s=0;s<2;s=s+1)begin:wstage
   for(c=0;c<16;c=c+1)begin:wcol
    (* ram_style="distributed" *) reg [7:0] mem[0:63];
    always @(posedge clk)
     if(wr_en&&wr_kind==1'b1&&wr_stage==s)
      mem[{ww_half,ww_k}]<=wr_data[c*8+:8];
    wire [4:0] kk=w_k[c*5+:5];
    wire [7:0] value=mem[{rd_col_half,kk}];
    assign w_stage_val[s][c*7+:7]=value[6:0];
   end
  end
 endgenerate
 assign a_values=rd_stage?a_stage_val[1]:a_stage_val[0];
 assign w_values=rd_stage?w_stage_val[1]:w_stage_val[0];
endmodule
