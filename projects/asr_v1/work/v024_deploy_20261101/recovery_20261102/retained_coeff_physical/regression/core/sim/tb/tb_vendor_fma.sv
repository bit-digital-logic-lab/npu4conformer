`timescale 1ns/1ps
module tb_vendor_fma;
 reg clk=0;always #4 clk=~clk;
 reg rst_n=0,in_valid=0;reg [31:0] a=0,b=0,c=0;
 wire out_valid;wire [31:0] result;
 reg [31:0] vec[0:191],gold[0:63];
 reg [1023:0] vecfile,goldfile;
 integer i,cycles=0,sent=0,seen=0,errors=0;
 integer issued[0:63];
 asr_fma_ip dut(.aclk(clk),.aresetn(rst_n),
  .s_axis_a_tvalid(in_valid),.s_axis_a_tdata(a),
  .s_axis_b_tvalid(in_valid),.s_axis_b_tdata(b),
  .s_axis_c_tvalid(in_valid),.s_axis_c_tdata(c),
  .m_axis_result_tvalid(out_valid),.m_axis_result_tdata(result));
 always @(posedge clk) begin
  cycles=cycles+1;
  if(rst_n) begin
   if(in_valid) begin issued[sent]=cycles;sent=sent+1;end
   if(out_valid) begin
    if(seen>=64) begin errors=errors+1;$display("FMA_EXTRA_RESULT");end
    else begin
     if(result!==gold[seen]) begin errors=errors+1;$display("FMA_MISMATCH index=%0d got=%h expected=%h",seen,result,gold[seen]);end
     if(cycles-issued[seen]!=12) begin errors=errors+1;$display("FMA_LATENCY_MISMATCH index=%0d observed=%0d expected=12",seen,cycles-issued[seen]);end
    end
    seen=seen+1;
   end
  end
 end
 initial begin
  if(!$value$plusargs("vecfile=%s",vecfile))$fatal(1,"missing vectors");
  if(!$value$plusargs("goldfile=%s",goldfile))$fatal(1,"missing gold");
  $readmemh(vecfile,vec);$readmemh(goldfile,gold);
  repeat(12) @(negedge clk);rst_n=1;
  repeat(3) @(negedge clk);
  for(i=0;i<64;i=i+1) begin
   @(negedge clk);in_valid=1;a=vec[3*i];b=vec[3*i+1];c=vec[3*i+2];
  end
  @(negedge clk);in_valid=0;
  repeat(20) @(negedge clk);
  if(sent!=64||seen!=64||errors!=0)$fatal(1,"VENDOR_FMA_FAIL sent=%0d seen=%0d errors=%0d",sent,seen,errors);
  $display("VENDOR_FMA_PASS sent=64 seen=64 mismatch=0 latency=12");
  $finish;
 end
endmodule
