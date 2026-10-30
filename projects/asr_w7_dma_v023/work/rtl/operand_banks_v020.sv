`timescale 1ns/1ps
// L1 operands: complete logical 32x32 A16/W8 blocks, physical 16-row/col
// systolic injection. Small distributed RAM banks preserve asynchronous L1
// read timing but eliminate a centralized 1024-entry, 16-read-port mux.
module operand_banks_v020(
 input wire clk,a_write,b_write,input wire [9:0] write_index,
 input wire [191:0] write_data,input wire [6:0] run_cycle,
 input wire [1:0] quadrant,
 output wire [255:0] a_values,output wire [111:0] w_values
);
 genvar r,q,c;
 generate for(r=0;r<16;r=r+1)begin:arows
  wire [6:0] kpos=run_cycle-r;
  wire [63:0] four_values;
  for(q=0;q<4;q=q+1)begin:kmod4
   (* ram_style="distributed" *) reg [15:0] mem[0:15];
   always @(posedge clk)
    if(a_write&&write_index[8:5]==r)
     mem[{write_index[9],write_index[4:2]}]<=write_data[q*48+:16];
   assign four_values[q*16+:16]=mem[{quadrant[1],kpos[4:2]}];
  end
  assign a_values[r*16+:16]=four_values[kpos[1:0]*16+:16];
 end
 for(c=0;c<16;c=c+1)begin:bcols
  wire [6:0] kpos=run_cycle-c;
  (* ram_style="distributed" *) reg [7:0] mem[0:63];
  wire [7:0] value=mem[{quadrant[0],kpos[4:0]}];
  always @(posedge clk)
   if(b_write&&write_index[3:2]==(c/4))
    mem[{write_index[4],write_index[9:5]}]<=write_data[(c%4)*48+:8];
  assign w_values[c*7+:7]=value[6:0];
 end endgenerate
endmodule
