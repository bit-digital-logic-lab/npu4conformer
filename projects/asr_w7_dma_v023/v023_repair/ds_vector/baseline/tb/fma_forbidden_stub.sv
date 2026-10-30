// Interface-only stub for Icarus tests that NEVER invoke FMA. Fail if used.
// Production and vendor simulation must link the original asr_fma_ip, not this.
module asr_fma_ip(input wire aclk,aresetn,s_axis_a_tvalid,s_axis_b_tvalid,s_axis_c_tvalid,
 input wire [31:0] s_axis_a_tdata,s_axis_b_tdata,s_axis_c_tdata,
 output wire m_axis_result_tvalid,output wire [31:0] m_axis_result_tdata);
 assign m_axis_result_tvalid=0;assign m_axis_result_tdata=0;
 always @(posedge aclk)if(aresetn&&(s_axis_a_tvalid||s_axis_b_tvalid||s_axis_c_tvalid))$fatal(1,"FMA not covered by forbidden-stub tests");
endmodule
