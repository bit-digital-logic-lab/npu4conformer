`timescale 1ns/1ps
// Directed test of the II=1 C cache: synchronous read, separate write port,
// same-address bypass, and a cross-K style write(255)/read(0) sequence.
module tb_cache_pipe;
 reg clk=0,rst_n=0;always #5 clk=~clk;
 reg rd_valid=0,wr_valid=0;wire rd_ready,wr_ready;
 reg [8:0] rd_group=0,wr_group=0;reg [3:0] wr_mask=0;reg [191:0] wr_data=0;
 wire [191:0] rd_data;wire bypass;
 integer errs=0;
 c_cache_banked4_pipe dut(.clk(clk),.rst_n(rst_n),.rd_valid(rd_valid),.rd_ready(rd_ready),
  .rd_group(rd_group),.rd_data(rd_data),.wr_valid(wr_valid),.wr_ready(wr_ready),
  .wr_group(wr_group),.wr_mask(wr_mask),.wr_data(wr_data),.raw_bypass_pulse(bypass));
 function [191:0] pat(input [7:0] v);begin pat={4{48'h0+v}};end endfunction

 task write_group(input [8:0] g,input [7:0] v);begin
  @(negedge clk);wr_valid=1;wr_group=g;wr_mask=4'hf;wr_data=pat(v);
  @(posedge clk);@(negedge clk);wr_valid=0;
 end endtask

 task read_group(input [8:0] g,input [7:0] exp,input [255:0] what);begin
  @(negedge clk);rd_valid=1;rd_group=g;
  @(posedge clk);@(negedge clk);rd_valid=0;
  #1;
  if(rd_data!==pat(exp))begin $display("FAIL %0s g=%0d got=%h exp=%h",what,g,rd_data,pat(exp));errs=errs+1;end
 end endtask

 initial begin
  repeat(3)@(negedge clk);rst_n=1;repeat(2)@(negedge clk);
  // ordinary write -> next-cycle read
  write_group(9'd256,8'h11);
  read_group(9'd256,8'h11,"slot1 write/read");
  // same-address read/write in one cycle must bypass the write data
  @(negedge clk);rd_valid=1;rd_group=9'd256;wr_valid=1;wr_group=9'd256;wr_mask=4'hf;wr_data=pat(8'h22);
  @(posedge clk);@(negedge clk);rd_valid=0;wr_valid=0;#1;
  if(rd_data!==pat(8'h22))begin $display("FAIL same-address bypass got=%h exp=%h",rd_data,pat(8'h22));errs=errs+1;end
  if(!bypass)begin $display("FAIL bypass pulse not seen");errs=errs+1;end
  // cross-K: write last group 255 and read group 0 in the same cycle
  write_group(9'd255,8'h33);
  @(negedge clk);rd_valid=1;rd_group=9'd256;wr_valid=1;wr_group=9'd255;wr_mask=4'hf;wr_data=pat(8'h44);
  @(posedge clk);@(negedge clk);rd_valid=0;wr_valid=0;#1;
  if(rd_data!==pat(8'h22))begin $display("FAIL cross-group read got=%h exp=%h",rd_data,pat(8'h22));errs=errs+1;end
  // C48 max value must be stored/read without saturation
  write_group(9'd257,8'h00);
  @(negedge clk);wr_valid=1;wr_group=9'd257;wr_mask=4'hf;wr_data={4{48'hFFFFFFFFFFFF}};
  @(posedge clk);@(negedge clk);wr_valid=0;
  @(negedge clk);rd_valid=1;rd_group=9'd257;
  @(posedge clk);@(negedge clk);rd_valid=0;#1;
  if(rd_data!=={4{48'hFFFFFFFFFFFF}})begin $display("FAIL C48 max got=%h",rd_data);errs=errs+1;end
  if(errs!=0)$fatal(1,"cache pipe errs=%0d",errs);
  $display("PASS tb_cache_pipe");
  $finish;
 end
 initial begin #200000;$fatal(1,"timeout");end
endmodule
