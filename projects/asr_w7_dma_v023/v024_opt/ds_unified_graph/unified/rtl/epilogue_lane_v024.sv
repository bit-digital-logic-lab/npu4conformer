`timescale 1ns/1ps
// epilogue_lane_v024.sv
// One lane of C48 -> I48/F32 -> single-rounding FMA(scale,bias) -> ReLU ->
// F32/I16.  V0.24 adds per-beat scale/bias inputs used by the per-channel
// epilogue engine; the arithmetic blocks are the frozen V0.23 candidates.
module epilogue_lane_v024 #(
    parameter TAG_WIDTH = 16
)(
    input  wire                  clk,
    input  wire                  rst_n,
    input  wire                  flush,

    input  wire [1:0]            cfg_fma_mode,
    input  wire                  cfg_relu_en,
    input  wire [31:0]           in_scale,
    input  wire [31:0]           in_bias,

    input  wire                  in_valid,
    output wire                  in_ready,
    input  wire signed [47:0]    in_c48,
    input  wire [TAG_WIDTH-1:0]  in_tag,
    input  wire                  in_last,

    output wire                  out_valid,
    input  wire                  out_ready,
    output wire signed [15:0]    out_a16,
    output wire [TAG_WIDTH-1:0]  out_tag,
    output wire                  out_last,

    output wire                  fp32_valid,
    output wire [31:0]           fp32_data
);
    wire                  i2f_valid, i2f_ready;
    wire [31:0]           i2f_data;
    wire [TAG_WIDTH-1:0]  i2f_tag;
    wire                  i2f_last;
    wire [31:0]           i2f_scale, i2f_bias;

    epilogue_i48_to_f32_v024 #(.TAG_WIDTH(TAG_WIDTH)) u_i48_to_f32 (
        .clk(clk), .rst_n(rst_n), .flush(flush),
        .in_valid(in_valid), .in_ready(in_ready),
        .in_data(in_c48), .in_tag(in_tag), .in_last(in_last),
        .in_scale(in_scale), .in_bias(in_bias),
        .out_valid(i2f_valid), .out_ready(i2f_ready),
        .out_data(i2f_data), .out_tag(i2f_tag), .out_last(i2f_last),
        .out_scale(i2f_scale), .out_bias(i2f_bias)
    );

    wire                  fma_valid, fma_ready;
    wire [31:0]           fma_data;
    wire [TAG_WIDTH-1:0]  fma_tag;
    wire                  fma_last;

    epilogue_fma_stage_v024 #(.TAG_WIDTH(TAG_WIDTH)) u_fma_stage (
        .clk(clk), .rst_n(rst_n), .flush(flush),
        .mode(cfg_fma_mode),
        .scale(i2f_scale), .bias(i2f_bias),
        .in_valid(i2f_valid), .in_ready(i2f_ready),
        .in_data(i2f_data), .in_tag(i2f_tag), .in_last(i2f_last),
        .out_valid(fma_valid), .out_ready(fma_ready),
        .out_data(fma_data), .out_tag(fma_tag), .out_last(fma_last)
    );

    wire                  relu_valid, relu_ready;
    wire [31:0]           relu_data;
    wire [TAG_WIDTH-1:0]  relu_tag;
    wire                  relu_last;

    epilogue_relu #(.TAG_WIDTH(TAG_WIDTH)) u_relu (
        .clk(clk), .rst_n(rst_n), .flush(flush),
        .relu_en(cfg_relu_en),
        .in_valid(fma_valid), .in_ready(fma_ready),
        .in_data(fma_data), .in_tag(fma_tag), .in_last(fma_last),
        .out_valid(relu_valid), .out_ready(relu_ready),
        .out_data(relu_data), .out_tag(relu_tag), .out_last(relu_last)
    );

    assign fp32_valid = relu_valid;
    assign fp32_data  = relu_data;

    epilogue_f32_to_i16 #(.TAG_WIDTH(TAG_WIDTH)) u_f32_to_i16 (
        .clk(clk), .rst_n(rst_n), .flush(flush),
        .in_valid(relu_valid), .in_ready(relu_ready),
        .in_data(relu_data), .in_tag(relu_tag), .in_last(relu_last),
        .out_valid(out_valid), .out_ready(out_ready),
        .out_data(out_a16), .out_tag(out_tag), .out_last(out_last)
    );
endmodule
