`timescale 1ns/1ps
// epilogue_fma_stage_v024.sv
// Same single-rounding FP32 FMA pipeline as V0.23, but scale/bias are per-beat
// inputs aligned with the data by epilogue_i48_to_f32_v024.  The tag payload
// still packs {mode,in_data,tag} through fp32_fma_pipe, so stalls cannot
// misalign an operand and its parameters.
module epilogue_fma_stage_v024 #(
    parameter TAG_WIDTH = 16
)(
    input  wire                  clk,
    input  wire                  rst_n,
    input  wire                  flush,
    input  wire [1:0]            mode,
    input  wire [31:0]           scale,
    input  wire [31:0]           bias,
    input  wire                  in_valid,
    output wire                  in_ready,
    input  wire [31:0]           in_data,
    input  wire [TAG_WIDTH-1:0]  in_tag,
    input  wire                  in_last,
    output wire                  out_valid,
    input  wire                  out_ready,
    output wire [31:0]           out_data,
    output wire [TAG_WIDTH-1:0]  out_tag,
    output wire                  out_last
);
    localparam [1:0] MODE_CONV_ONLY  = 2'd0;
    localparam [1:0] MODE_SCALE_BIAS = 2'd1;
    localparam [1:0] MODE_SCALE_ONLY = 2'd2;

    wire [31:0] op_a = in_data;
    wire [31:0] op_b = (mode == MODE_CONV_ONLY) ? 32'h3f800000 : scale;
    wire [31:0] op_c = (mode == MODE_SCALE_BIAS) ? bias : 32'h00000000;

    localparam EXT_TAG_WIDTH = TAG_WIDTH + 34;
    wire [EXT_TAG_WIDTH-1:0] fma_in_tag_ext = {mode, in_data, in_tag};
    wire [EXT_TAG_WIDTH-1:0] fma_out_tag_ext;
    wire fma_in_ready, fma_out_valid;
    wire [31:0] fma_out_result;
    wire fma_out_last;

    assign in_ready = fma_in_ready;

    fp32_fma_pipe #(.TAG_WIDTH(EXT_TAG_WIDTH)) u_fma_pipe (
        .clk        (clk),
        .rst_n      (rst_n),
        .flush      (flush),
        .in_valid   (in_valid),
        .in_ready   (fma_in_ready),
        .in_a       (op_a),
        .in_b       (op_b),
        .in_c       (op_c),
        .in_tag     (fma_in_tag_ext),
        .in_last    (in_last),
        .out_valid  (fma_out_valid),
        .out_ready  (out_ready),
        .out_result (fma_out_result),
        .out_tag    (fma_out_tag_ext),
        .out_last   (fma_out_last)
    );

    wire [1:0]           out_mode   = fma_out_tag_ext[EXT_TAG_WIDTH-1 : EXT_TAG_WIDTH-2];
    wire [31:0]          out_bp_data= fma_out_tag_ext[EXT_TAG_WIDTH-3 : TAG_WIDTH];
    wire [TAG_WIDTH-1:0] orig_out_tag = fma_out_tag_ext[TAG_WIDTH-1 : 0];

    assign out_valid = fma_out_valid;
    assign out_data  = (out_mode == MODE_CONV_ONLY) ? out_bp_data : fma_out_result;
    assign out_tag   = orig_out_tag;
    assign out_last  = fma_out_last;
endmodule
