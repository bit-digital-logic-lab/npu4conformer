`timescale 1ns/1ps
// Directed port/slot/RAW test for c_cache_banked4_pipe.
// Proves that the 9-bit group includes the slot bit: slot0 group g and slot1
// group g never alias, and the write-first bypass fires only for the same
// full 9-bit group.
module tb_cache_slots;
 reg clk=0,rst_n=0;always #5 clk=~clk;
 reg rd_valid=0,wr_valid=0;reg [8:0] rd_group=0,wr_group=0;
 reg [3:0] wr_mask=0;reg [191:0] wr_data=0;
 wire [191:0] rd_data;wire raw;
 integer errs=0;
 reg [191:0] exp7,exp6;
 c_cache_banked4_pipe dut(.clk(clk),.rst_n(rst_n),.rd_valid(rd_valid),.rd_ready(),
  .rd_group(rd_group),.rd_data(rd_data),.wr_valid(wr_valid),.wr_ready(),
  .wr_group(wr_group),.wr_mask(wr_mask),.wr_data(wr_data),.raw_bypass_pulse(raw));
 function [191:0] pat(input integer v);
  reg [191:0] r;integer i;
  begin for(i=0;i<4;i=i+1)r[i*48+:48]=v*4+i;pat=r;end
 endfunction
 task wr(input [8:0] g,input [191:0] d);begin
  @(negedge clk);wr_valid=1;wr_group=g;wr_mask=4'hf;wr_data=d;
  @(negedge clk);wr_valid=0;
 end endtask
 task rd(input [8:0] g);begin
  @(negedge clk);rd_valid=1;rd_group=g;
  @(posedge clk);#1;rd_valid=0;
  @(negedge clk);
 end endtask
 task chk(input [8:0] g,input [191:0] e,input [127:0] what);begin
  if(rd_data!==e)begin $display("FAIL %0s group=%h got=%h exp=%h",what,g,rd_data,e);errs=errs+1;end
 end endtask
 initial begin
  rst_n=0;repeat(4)@(negedge clk);rst_n=1;
  wr(9'h000,pat(1));wr(9'h100,pat(2));wr(9'h005,pat(3));wr(9'h105,pat(4));
  rd(9'h000);chk(9'h000,pat(1),"slot0 g0");
  rd(9'h100);chk(9'h100,pat(2),"slot1 g0");
  rd(9'h005);chk(9'h005,pat(3),"slot0 g5");
  rd(9'h105);chk(9'h105,pat(4),"slot1 g5");
  // same-cycle write group 0x101, read group 0x101 -> bypass
  @(negedge clk);wr_valid=1;wr_group=9'h101;wr_mask=4'hf;wr_data=pat(5);
  rd_valid=1;rd_group=9'h101;
  @(posedge clk);#1;
  if(!raw)begin $display("FAIL expected raw bypass pulse");errs=errs+1;end
  @(negedge clk);wr_valid=0;rd_valid=0;
  rd(9'h101);chk(9'h101,pat(5),"bypass written 0x101");
  // same-cycle write slot0 group 5, read slot1 group 5: must NOT alias/bypass
  @(negedge clk);wr_valid=1;wr_group=9'h005;wr_mask=4'hf;wr_data=pat(6);
  rd_valid=1;rd_group=9'h105;
  @(posedge clk);#1;
  if(raw)begin $display("FAIL cross-slot false bypass");errs=errs+1;end
  chk(9'h105,pat(4),"cross-slot read");
  @(negedge clk);wr_valid=0;rd_valid=0;
  rd(9'h005);chk(9'h005,pat(6),"slot0 updated");
  rd(9'h105);chk(9'h105,pat(4),"slot1 intact");
  // byte mask: write only bank 2 of group 0x1FF
  exp6=pat(6);wr(9'h1FF,exp6);
  exp7=pat(7);
  @(negedge clk);wr_valid=1;wr_group=9'h1FF;wr_mask=4'b0100;wr_data=exp7;
  @(negedge clk);wr_valid=0;
  rd(9'h1FF);
  if(rd_data[96+:48]!==exp7[96+:48])begin $display("FAIL masked bank2");errs=errs+1;end
  if(rd_data[0+:48]!==exp6[0+:48])begin $display("FAIL masked bank0 should stay old");errs=errs+1;end
  if(errs!=0)$fatal(1,"tb_cache_slots errs=%0d",errs);
  $display("PASS tb_cache_slots slot_alias=0 cross_slot_bypass=0 same_group_bypass=1 masked_write=1");
  $finish;
 end
 initial begin #200000;$display("TIMEOUT");$fatal(1);end
endmodule
