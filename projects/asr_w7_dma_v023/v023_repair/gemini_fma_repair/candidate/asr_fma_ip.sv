`timescale 1ns/1ps
// asr_fma_ip.sv
// Exact interface-compatible RTL implementation of official Xilinx asr_fma_ip.
// Computes: result = (a * b) + c using 4-stage pipelined IEEE-754 binary32 FMA.
// Supports single-rounding RNE, cancellation test, and acceptance probe fix.

module asr_fma_ip (
    input  wire        aclk,
    input  wire        aresetn,

    // AXIS Slave Port A
    input  wire        s_axis_a_tvalid,
    input  wire [31:0] s_axis_a_tdata,

    // AXIS Slave Port B
    input  wire        s_axis_b_tvalid,
    input  wire [31:0] s_axis_b_tdata,

    // AXIS Slave Port C
    input  wire        s_axis_c_tvalid,
    input  wire [31:0] s_axis_c_tdata,

    // AXIS Master Port Result
    output wire        m_axis_result_tvalid,
    output wire [31:0] m_axis_result_tdata
);

    wire in_valid = s_axis_a_tvalid & s_axis_b_tvalid & s_axis_c_tvalid;

    fp32_fma_pipe #(
        .TAG_WIDTH(1)
    ) u_fma_pipe (
        .clk        (aclk),
        .rst_n      (aresetn),
        .flush      (1'b0),
        .in_valid   (in_valid),
        .in_ready   (), // NonBlocking interface in asr_fma_ip contract
        .in_a       (s_axis_a_tdata),
        .in_b       (s_axis_b_tdata),
        .in_c       (s_axis_c_tdata),
        .in_tag     (1'b0),
        .in_last    (1'b0),
        .out_valid  (m_axis_result_tvalid),
        .out_ready  (1'b1),
        .out_result (m_axis_result_tdata),
        .out_tag    (),
        .out_last   ()
    );

endmodule
