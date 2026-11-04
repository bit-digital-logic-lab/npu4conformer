`timescale 1ns/1ps
module tb_parallel_fault;
 tb_v024_acl_body body();
 reg saw_mat=0,saw_acl=0,saw_fault=0,saw_done=0;
 always @(posedge body.clk) if(body.rst_n) begin
  if(body.dut.graph.ctrl.mat_valid && body.dut.graph.ctrl.mat_ready) begin saw_mat<=1;$display("REAL_MATRIX_DISPATCH cyc=%0d",body.cyc);end
  if(body.dut.graph.ctrl.fault_latched && !saw_fault)begin
   saw_fault<=1;$display("REAL_ACL_FAULT cyc=%0d error=%h active=%h rd=%0d wr=%0d b=%0d",body.cyc,body.dut.graph.ctrl.error_code,body.dut.graph.ctrl.e_active,body.rd_pending,body.wr_pending,body.b_pending);
   if(!saw_mat||!body.dut.graph.ctrl.e_active[1])$fatal(1,"not real concurrent fault");
  end
  if(saw_fault && (body.dut.graph.ctrl.mat_valid||body.dut.graph.ctrl.vec_valid||body.dut.graph.ctrl.lay_valid||body.dut.graph.ctrl.seq_valid||body.dut.graph.ctrl.fetch_req_valid))$fatal(1,"postfault new dispatch or fetch");
  if(body.dut.graph.ctrl.done&&!saw_done) begin
   saw_done<=1;
   if(!saw_mat||!saw_fault)$fatal(1,"incomplete reachable sequence");
   $display("REAL_ACL_DONE cyc=%0d active=%h rd=%0d wr=%0d b=%0d quiesced=%0d",body.cyc,body.dut.graph.ctrl.e_active,body.rd_pending,body.wr_pending,body.b_pending,body.port_quiesced);
  end
 end
endmodule
