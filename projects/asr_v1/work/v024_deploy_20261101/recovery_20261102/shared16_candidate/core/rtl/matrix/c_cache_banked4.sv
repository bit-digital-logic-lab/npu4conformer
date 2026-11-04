`timescale 1ns/1ps
// Two logical 32x32 INT48 blocks in four 512x48 true-dual-port BRAM banks.
// New building block; not yet connected to the V020 block controller.
// Port A: four adjacent C values for accumulation, synchronous READ_FIRST.
// Port B: one C value for writeback, synchronous and held under backpressure.
// No RAM reset/whole-block clear. A controller must use valid/epoch metadata.
module c_cache_banked4(
 input wire clk,rst_n,
 input wire a_valid,output wire a_ready,input wire [8:0] a_group,
 input wire [3:0] a_write_mask,input wire [191:0] a_write_data,
 output reg a_response_valid,input wire a_response_ready,output wire [191:0] a_read_data,
 input wire b_valid,output wire b_ready,input wire [10:0] b_word,
 output reg b_response_valid,input wire b_response_ready,output wire [47:0] b_read_data
);
 wire a_fire=a_valid&&a_ready;
 wire conflict=a_fire&&a_group==b_word[10:2]&&a_write_mask[b_word[1:0]];
 wire b_fire=b_valid&&b_ready;
 assign a_ready=rst_n&&(!a_response_valid||a_response_ready);
 assign b_ready=rst_n&&(!b_response_valid||b_response_ready)&&!conflict;
 wire [191:0] b_values;reg [1:0] b_bank;
 assign b_read_data=b_values[b_bank*48+:48];
 for(genvar bank=0;bank<4;bank=bank+1)begin:banks
  (* ram_style="block" *) reg [47:0] mem[0:511];
  reg [47:0] aq,bq;
  assign a_read_data[bank*48+:48]=aq;
  assign b_values[bank*48+:48]=bq;
  always @(posedge clk)begin
   if(a_fire)begin
    aq<=mem[a_group];
    if(a_write_mask[bank])mem[a_group]<=a_write_data[bank*48+:48];
   end
   if(b_fire)bq<=mem[b_word[10:2]];
  end
 end
 always @(posedge clk)begin
  if(!rst_n)begin a_response_valid<=0;b_response_valid<=0;b_bank<=0;end
  else begin
   if(a_ready)a_response_valid<=a_valid;
   if(b_ready)b_response_valid<=b_valid;
   else if(b_response_valid&&b_response_ready)b_response_valid<=0;
   if(b_fire)b_bank<=b_word[1:0];
  end
 end
endmodule
