`timescale 1ns/1ps
// epilogue_relu.sv
// FP32 ReLU activation: max(0.0, x)
// Configurable enable, supports FTZ and IEEE-754 semantics matching asr_fp32_alu.sv MAXIMUM.
// Pipelined with valid/ready handshake and backpressure.

module epilogue_relu #(
    parameter TAG_WIDTH = 16
)(
    input  wire                  clk,
    input  wire                  rst_n,
    input  wire                  flush,
    input  wire                  relu_en,

    // Upstream Handshake
    input  wire                  in_valid,
    output wire                  in_ready,
    input  wire [31:0]           in_data,
    input  wire [TAG_WIDTH-1:0]  in_tag,
    input  wire                  in_last,

    // Downstream Handshake
    output reg                   out_valid,
    input  wire                  out_ready,
    output reg  [31:0]           out_data,
    output reg  [TAG_WIDTH-1:0]  out_tag,
    output reg                   out_last
);

    wire is_nan  = (&in_data[30:23]) && (|in_data[22:0]);
    wire is_zero = (in_data[30:0] == 31'd0);
    wire is_neg  = in_data[31];

    function automatic [31:0] do_relu(input [31:0] din, input en);
        begin
            if (!en) begin
                do_relu = din;
            end else if (is_nan) begin
                do_relu = 32'h7fc00000;
            end else if (is_neg || is_zero) begin
                do_relu = 32'h00000000;
            end else begin
                do_relu = din;
            end
        end
    endfunction

    assign in_ready = !out_valid || out_ready;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            out_valid <= 1'b0;
            out_data  <= 32'd0;
            out_tag   <= {TAG_WIDTH{1'b0}};
            out_last  <= 1'b0;
        end else if (flush) begin
            out_valid <= 1'b0;
        end else if (in_ready) begin
            out_valid <= in_valid;
            if (in_valid) begin
                out_data <= do_relu(in_data, relu_en);
                out_tag  <= in_tag;
                out_last <= in_last;
            end
        end
    end

endmodule
