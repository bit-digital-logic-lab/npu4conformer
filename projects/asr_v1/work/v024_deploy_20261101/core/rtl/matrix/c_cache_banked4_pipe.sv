`timescale 1ns/1ps
// Two logical 32x32 INT48 blocks in four 512x48 true-dual-port BRAM banks.
// V0.23 C-collect variant: one synchronous read port and one synchronous write
// port so a read-modify-write group can sustain II=1.  The original
// c_cache_banked4 uses the same port for read and write, which forces the
// controller to spend one cycle on C_READ and one on COLLECT (2 cycles per
// four-value group).  Here the read of group g+1 and the write of group g
// happen in the same cycle.
//
// Read data is registered (synchronous BRAM read).  If the read address equals
// the write address in the same cycle, the read output bypasses with the write
// data (write-first), so a cross-K / last-group RAW cannot return stale data.
// No RAM reset or whole-block clear: ownership/epoch remains external.
module c_cache_banked4_pipe(
 input wire clk,rst_n,
 // read port: synchronous, one-cycle latency
 input wire rd_valid,output wire rd_ready,input wire [8:0] rd_group,
 output reg [191:0] rd_data,
 // write port: synchronous, one-cycle write
 input wire wr_valid,output wire wr_ready,input wire [8:0] wr_group,
 input wire [3:0] wr_mask,input wire [191:0] wr_data,
 // diagnostics
 output reg raw_bypass_pulse
);
 assign rd_ready=rst_n;
 assign wr_ready=rst_n;
 wire wr_fire=wr_valid&&wr_ready;
 wire rd_fire=rd_valid&&rd_ready;
 wire same_group=wr_fire&&rd_fire&&(wr_group==rd_group);
 generate
  for(genvar b=0;b<4;b=b+1)begin:banks
   (* ram_style="block" *) reg [47:0] mem[0:511];
   always @(posedge clk)begin
    if(wr_fire&&wr_mask[b])mem[wr_group]<=wr_data[b*48+:48];
    if(rd_fire)begin
     if(wr_fire&&wr_mask[b]&&(wr_group==rd_group))
      rd_data[b*48+:48]<=wr_data[b*48+:48];
     else
      rd_data[b*48+:48]<=mem[rd_group];
    end
   end
  end
 endgenerate
 always @(posedge clk)begin
  if(!rst_n)raw_bypass_pulse<=0;
  else raw_bypass_pulse<=same_group;
 end
endmodule
