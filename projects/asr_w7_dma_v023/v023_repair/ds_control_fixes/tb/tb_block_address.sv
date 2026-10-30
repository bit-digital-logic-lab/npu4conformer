`timescale 1ns/1ps
// block_address_v023 pipeline equivalence against the read-only v020.
// Random operands, boundary dimensions, encoding=3, out-of-range block ids and
// 32-bit offset/extent truncation cases; random output backpressure.
module tb_block_address;
 reg clk=0;always #4 clk=~clk;
 reg rst_n=0;
 reg [31:0] base=0;reg [15:0] rows=0,cols=0,br=0,bc=0;reg [1:0] enc=0;
 reg in_valid=0;wire in_ready;reg out_ready=1;
 wire [31:0] o_addr;wire [15:0] o_vr,o_vc;wire [39:0] o_ext;wire o_valid;
 wire [31:0] p_addr;wire [15:0] p_vr,p_vc;wire [39:0] p_ext;wire p_valid,p_valid_flag;
 block_address_v020 orig(.base(base),.rows(rows),.cols(cols),.block_row(br),.block_col(bc),
  .encoding(enc),.address(o_addr),.valid_rows(o_vr),.valid_cols(o_vc),.extent_bytes(o_ext),.valid(o_valid));
 block_address_v023 pipe(.clk(clk),.rst_n(rst_n),.in_valid(in_valid),.in_ready(in_ready),
  .base(base),.rows(rows),.cols(cols),.block_row(br),.block_col(bc),.encoding(enc),
  .out_valid(p_valid),.out_ready(out_ready),.address(p_addr),.valid_rows(p_vr),.valid_cols(p_vc),
  .extent_bytes(p_ext),.valid(p_valid_flag));
 // Expected queue (captured original output at input acceptance)
 reg [31:0] e_addr[0:4095];reg [15:0] e_vr[0:4095],e_vc[0:4095];
 reg [39:0] e_ext[0:4095];reg e_valid[0:4095];
 integer ewr=0,erd=0;
 integer errors=0;
 task chk(input [255:0] what,input cond);begin if(!cond)begin errors=errors+1;$display("FAIL %0s",what);$fflush();end end endtask
 integer seed=32'h55aa1234;
 integer i,stall;
 initial begin
  repeat(4)@(negedge clk);rst_n=1;repeat(2)@(negedge clk);
  // Drive exactly 3000 accepted vectors; hold inputs until in_ready.
  begin : gen
   integer acc,att;
   acc=0;att=0;
   while(acc<3000&&att<200000)begin
    @(negedge clk);att=att+1;
    out_ready=((att%7)!=0); // 6/7 chance ready
    if(in_ready)begin
     if(acc<8)begin
      case(acc)
       0:begin base=32'h03000000;rows=16'd32;cols=16'd32;br=0;bc=0;enc=0;end
       1:begin base=32'h03000000;rows=16'd1;cols=16'd1;br=0;bc=0;enc=1;end
       2:begin base=32'hFFFFFFFF;rows=16'd4096;cols=16'd4096;br=16'd127;bc=16'd127;enc=2;end
       3:begin base=32'h03000000;rows=0;cols=32;br=0;bc=0;enc=0;end
       4:begin base=32'h03000000;rows=32;cols=32;br=0;bc=0;enc=3;end
       5:begin base=32'h03000000;rows=32;cols=32;br=16'hffff;bc=16'hffff;enc=0;end
       6:begin base=32'h03000000;rows=16'hffff;cols=16'hffff;br=16'hffff;bc=16'hffff;enc=2;end
       7:begin base=32'hFFFFFFF0;rows=16'hffff;cols=16'hffff;br=16'd1;bc=16'd1;enc=2;end
      endcase
     end else begin
      base=$random(seed);rows=$random(seed);cols=$random(seed);br=$random(seed);bc=$random(seed);enc=$random(seed);
     end
     in_valid=1;
     @(posedge clk);
     if(in_valid&&in_ready)begin
      e_addr[ewr]=o_addr;e_vr[ewr]=o_vr;e_vc[ewr]=o_vc;e_ext[ewr]=o_ext;e_valid[ewr]=o_valid;ewr=ewr+1;acc=acc+1;
     end else begin
      chk("input handshake",0);
     end
     @(negedge clk);in_valid=0;
    end
   end
   $display("GENERATED accepted=%0d attempts=%0d",acc,att);
  end
  // Drain remaining expected records; keep the output moving.
  begin : drain_wait
   integer dcy;dcy=0;out_ready=1;
   while(erd<ewr&&dcy<20000)begin @(posedge clk);dcy=dcy+1;end
  end
  $display("BLOCK_ADDRESS_TEST_END accepted=%0d checked=%0d errors=%0d",ewr,erd,errors);$fflush();
  if(errors==0&&erd==3000)$display("BLOCK_ADDRESS_PASS");else $display("BLOCK_ADDRESS_FAIL");
  $finish;
 end
 // compare every output handshake
 always @(posedge clk)begin
  if(p_valid&&out_ready&&erd<ewr)begin
   if((p_addr!==e_addr[erd])||(p_vr!==e_vr[erd])||(p_vc!==e_vc[erd])||(p_ext!==e_ext[erd])||(p_valid_flag!==e_valid[erd]))begin
    if(errors<8)$display("MISMATCH idx=%0d exp a=%h vr=%0d vc=%0d ext=%h v=%0d got a=%h vr=%0d vc=%0d ext=%h v=%0d",
      erd,e_addr[erd],e_vr[erd],e_vc[erd],e_ext[erd],e_valid[erd],p_addr,p_vr,p_vc,p_ext,p_valid_flag);
   end
   chk("addr",p_addr===e_addr[erd]);chk("valid_rows",p_vr===e_vr[erd]);
   chk("valid_cols",p_vc===e_vc[erd]);chk("extent",p_ext===e_ext[erd]);
   chk("valid",p_valid_flag===e_valid[erd]);
   erd=erd+1;
  end
 end
 initial begin repeat(200000)@(posedge clk);$display("BLOCK_ADDRESS_TIMEOUT ewr=%0d erd=%0d",ewr,erd);$finish;end
endmodule
