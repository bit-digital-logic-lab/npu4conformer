`timescale 1ns/1ps
// epilogue_lane.sv
// Single epilogue fusion lane executing:
//   C48 -> I48_F32 -> FMA (scale, bias) -> ReLU -> F32_I16 -> A16
// Supports descriptor-controlled spill taps and full backpressure / error flush.

module epilogue_lane #(
    parameter TAG_WIDTH = 16
)(
    input  wire                  clk,
    input  wire                  rst_n,
    input  wire                  flush,

    // Configuration
    input  wire [1:0]            cfg_fma_mode,
    input  wire                  cfg_relu_en,
    input  wire [31:0]           cfg_scale,
    input  wire [31:0]           cfg_bias,

    // Upstream Handshake (from Matrix collector)
    input  wire                  in_valid,
    output wire                  in_ready,
    input  wire signed [47:0]    in_c48,
    input  wire [TAG_WIDTH-1:0]  in_tag,
    input  wire                  in_last,

    // Downstream Handshake (to A16 packer / buffer)
    output wire                  out_valid,
    input  wire                  out_ready,
    output wire signed [15:0]    out_a16,
    output wire [TAG_WIDTH-1:0]  out_tag,
    output wire                  out_last,

    // Spill tap for FP32 intermediate (if needed by multi-consumer)
    output wire                  fp32_valid,
    output wire [31:0]           fp32_data
);

    // -------------------------------------------------------------------------
    // Stage 1: I48 to FP32
    // -------------------------------------------------------------------------
    wire                  i2f_valid;
    wire                  i2f_ready;
    wire [31:0]           i2f_data;
    wire [TAG_WIDTH-1:0]  i2f_tag;
    wire                  i2f_last;

    epilogue_i48_to_f32 #(.TAG_WIDTH(TAG_WIDTH)) u_i48_to_f32 (
        .clk       (clk),
        .rst_n     (rst_n),
        .flush     (flush),
        .in_valid  (in_valid),
        .in_ready  (in_ready),
        .in_data   (in_c48),
        .in_tag    (in_tag),
        .in_last   (in_last),
        .out_valid (i2f_valid),
        .out_ready (i2f_ready),
        .out_data  (i2f_data),
        .out_tag   (i2f_tag),
        .out_last  (i2f_last)
    );

    // -------------------------------------------------------------------------
    // Stage 2: Scale and Bias FMA
    // -------------------------------------------------------------------------
    wire                  fma_valid;
    wire                  fma_ready;
    wire [31:0]           fma_data;
    wire [TAG_WIDTH-1:0]  fma_tag;
    wire                  fma_last;

    epilogue_fma_stage #(.TAG_WIDTH(TAG_WIDTH)) u_fma_stage (
        .clk       (clk),
        .rst_n     (rst_n),
        .flush     (flush),
        .mode      (cfg_fma_mode),
        .scale     (cfg_scale),
        .bias      (cfg_bias),
        .in_valid  (i2f_valid),
        .in_ready  (i2f_ready),
        .in_data   (i2f_data),
        .in_tag    (i2f_tag),
        .in_last   (i2f_last),
        .out_valid (fma_valid),
        .out_ready (fma_ready),
        .out_data  (fma_data),
        .out_tag   (fma_tag),
        .out_last  (fma_last)
    );

    // -------------------------------------------------------------------------
    // Stage 3: ReLU Activation
    // -------------------------------------------------------------------------
    wire                  relu_valid;
    wire                  relu_ready;
    wire [31:0]           relu_data;
    wire [TAG_WIDTH-1:0]  relu_tag;
    wire                  relu_last;

    epilogue_relu #(.TAG_WIDTH(TAG_WIDTH)) u_relu (
        .clk       (clk),
        .rst_n     (rst_n),
        .flush     (flush),
        .relu_en   (cfg_relu_en),
        .in_valid  (fma_valid),
        .in_ready  (fma_ready),
        .in_data   (fma_data),
        .in_tag    (fma_tag),
        .in_last   (fma_last),
        .out_valid (relu_valid),
        .out_ready (relu_ready),
        .out_data  (relu_data),
        .out_tag   (relu_tag),
        .out_last  (relu_last)
    );

    assign fp32_valid = relu_valid;
    assign fp32_data  = relu_data;

    // -------------------------------------------------------------------------
    // Stage 4: FP32 to INT16 (A16)
    // -------------------------------------------------------------------------
    epilogue_f32_to_i16 #(.TAG_WIDTH(TAG_WIDTH)) u_f32_to_i16 (
        .clk       (clk),
        .rst_n     (rst_n),
        .flush     (flush),
        .in_valid  (relu_valid),
        .in_ready  (relu_ready),
        .in_data   (relu_data),
        .in_tag    (relu_tag),
        .in_last   (relu_last),
        .out_valid (out_valid),
        .out_ready (out_ready),
        .out_data  (out_a16),
        .out_tag   (out_tag),
        .out_last  (out_last)
    );

endmodule
