`timescale 1ns/1ps
module tb_v024_iterhash_genfault;
 tb_v024_iterhash base();
 integer inject_state;
 reg injected=0;
 initial begin
  if(!$value$plusargs("inject_state=%d",inject_state))$fatal(1,"missing inject_state");
  if(inject_state!=10 && inject_state!=11)$fatal(1,"invalid inject_state");
  wait(base.body.rst_n);
  while(!(base.body.dut.graph.ctrl.state==inject_state && base.body.dut.graph.ctrl.hash_word==4))@(negedge base.body.clk);
  force base.body.dut.graph.ctrl.generation=32'd1;
  injected=1;
  $display("ITERHASH_GENERATION_INJECT state=%0d hash_word=4",inject_state);
 end
 always @(posedge base.body.clk) if(injected)begin
  if(base.body.dut.graph.ctrl.fetch_req_valid)$fatal(1,"GENERATION_INVALIDATION_ISSUED_FETCH");
  if(base.body.dut.graph.ctrl.mat_valid || base.body.dut.graph.ctrl.vec_valid || base.body.dut.graph.ctrl.lay_valid || base.body.dut.graph.ctrl.seq_valid)$fatal(1,"GENERATION_INVALIDATION_DISPATCHED");
 end
endmodule
