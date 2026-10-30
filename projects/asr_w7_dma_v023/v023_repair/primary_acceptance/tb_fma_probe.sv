module tb;
reg clk=0; always #5 clk=~clk;
epilogue_fma_stage dut(.clk(clk),.rst_n(1'b0),.flush(1'b0),.mode(2'd2),.scale(32'h3fc00000),.bias(32'd0),.in_valid(1'b0),.in_data(32'd0),.in_tag(16'd0),.in_last(1'b0),.out_ready(1'b1));
initial begin
$display("MUL got=%h expected=3fc00002",dut.fp32_mul(32'h3f800001,32'h3fc00000));
if(dut.fp32_mul(32'h3f800001,32'h3fc00000)!==32'h3fc00002) $display("ROUNDING_FAIL");
$finish;
end
endmodule
