`timescale 1ns/1ps
module tb_v024_iterhash;
 tb_v024_unified body();
 reg [511:0] h_snapshot;
 reg [1535:0] n_snapshot;
 integer h_steps=0,n_steps=0;
 always @(posedge body.clk) if(body.rst_n) begin
  if(body.dut.graph.ctrl.state==10) begin
   if(body.dut.graph.ctrl.hash_word==0)h_snapshot=body.dut.graph.ctrl.header;
   else if(body.dut.graph.ctrl.header!==h_snapshot)$fatal(1,"HASH_HEADER_BUFFER_MOVED");
   h_steps=h_steps+1;
  end
  if(body.dut.graph.ctrl.state==11) begin
   if(body.dut.graph.ctrl.hash_word==0)n_snapshot=body.dut.graph.ctrl.node_buf;
   else if(body.dut.graph.ctrl.node_buf!==n_snapshot)$fatal(1,"HASH_NODE_BUFFER_MOVED");
   n_steps=n_steps+1;
   if(body.dut.graph.ctrl.hash_word==47 && body.dut.graph.ctrl.nfetch_index+1==body.dut.graph.ctrl.header[95:64])
    $display("ITERHASH_FINAL computed=%08x expected=%08x header_steps=%0d node_steps=%0d",body.dut.graph.ctrl.hash_next,body.dut.graph.ctrl.header[255:224],h_steps,n_steps);
  end
  if(body.dut.graph.ctrl.state==10 || body.dut.graph.ctrl.state==11)begin
   if(body.dut.graph.ctrl.fetch_req_valid || body.dut.graph.ctrl.fetch_read_ready)$fatal(1,"HASH_FETCH_OVERLAP");
   if(body.dut.graph.ctrl.mat_valid || body.dut.graph.ctrl.vec_valid || body.dut.graph.ctrl.lay_valid || body.dut.graph.ctrl.seq_valid)$fatal(1,"HASH_DISPATCH_BEFORE_VERIFICATION");
  end
 end
endmodule
