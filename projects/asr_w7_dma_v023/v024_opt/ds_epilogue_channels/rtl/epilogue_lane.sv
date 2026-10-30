`timescale 1ns/1ps
// epilogue_lane.sv (v024)
// Single epilogue fusion lane executing:
//   C48 -> I48_F32 -> FMA (scale, bias) -> ReLU -> F32_I16 -> A16
// plus an independent post-ReLU 4xFP32 fork tap.
//
// v024 changes versus primary_stream_fix:
//   * cfg_scale/cfg_bias are per-lane values (the engine selects them from the
//     per-column table or the scalar fallback for this lane's column).
//   * fp32_out_* is a real independent ready/valid channel.  When fp32_en=1 the
//     lane keeps one elastic FP32 beat and does not advance ReLU until both the
//     A16 converter and the FP32 beat can accept.  When fp32_en=0 the channel is
//     idle and costs no throughput.
//
// Numeric chain is unchanged; scale/bias are captured into the FMA input
// registers, so a later table/config change cannot alter an in-flight beat.

module epilogue_lane #(
    parameter TAG_WIDTH = 16
)(
    input  wire                  clk,
    input  wire                  rst_n,
    input  wire                  flush,

    // Configuration
    input  wire [1:0]            cfg_fma_mode,
    input  wire                  cfg_relu_en,
    input  wire [31:0]           cfg_scale,   // per-lane (per-column) value
    input  wire [31:0]           cfg_bias,    // per-lane (per-column) value
    input  wire                  fp32_en,

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

    // Independent post-ReLU 4xFP32 tap
    output wire                  fp32_out_valid,
    input  wire                  fp32_out_ready,
    output wire [31:0]           fp32_out_data,
    output wire [TAG_WIDTH-1:0]  fp32_out_tag,
    output wire                  fp32_out_last
);

    // -------------------------------------------------------------------------
    // Stage 1: I48 to FP32
    // -------------------------------------------------------------------------
    wire                  i2f_valid;
    wire                  i2f_ready;
    wire [31:0]           i2f_data;
    wire [31:0]           i2f_scale;
    wire [31:0]           i2f_bias;
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
        .in_scale  (cfg_scale),
        .in_bias   (cfg_bias),
        .out_scale (i2f_scale),
        .out_bias  (i2f_bias),
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
        .scale     (i2f_scale),
        .bias      (i2f_bias),
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

    // -------------------------------------------------------------------------
    // Stage 4: FP32 to INT16 (A16) + optional independent FP32 fork
    // -------------------------------------------------------------------------
    wire                  f32_in_ready;

    reg                  fp32_pending;
    reg [31:0]           fp32_data_reg;
    reg [TAG_WIDTH-1:0]  fp32_tag_reg;
    reg                  fp32_last_reg;

    wire fp32_sink_ok = !fp32_en || !fp32_pending || fp32_out_ready;
    assign relu_ready = f32_in_ready && fp32_sink_ok;

    // When the optional FP32 beat cannot be accepted, do not let the A16
    // converter consume the ReLU output behind the ReLU's back.  Both fork
    // consumers must accept the same beat.
    wire a16_in_valid = relu_valid && fp32_sink_ok;

    epilogue_f32_to_i16 #(.TAG_WIDTH(TAG_WIDTH)) u_f32_to_i16 (
        .clk       (clk),
        .rst_n     (rst_n),
        .flush     (flush),
        .in_valid  (a16_in_valid),
        .in_ready  (f32_in_ready),
        .in_data   (relu_data),
        .in_tag    (relu_tag),
        .in_last   (relu_last),
        .out_valid (out_valid),
        .out_ready (out_ready),
        .out_data  (out_a16),
        .out_tag   (out_tag),
        .out_last  (out_last)
    );

    assign fp32_out_valid = fp32_pending && fp32_en && !flush;
    assign fp32_out_data  = fp32_data_reg;
    assign fp32_out_tag   = fp32_tag_reg;
    assign fp32_out_last  = fp32_last_reg;

    wire relu_fire = relu_valid && relu_ready;
    wire fp32_fire = fp32_out_valid && fp32_out_ready;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            fp32_pending  <= 1'b0;
            fp32_data_reg <= 32'd0;
            fp32_tag_reg  <= {TAG_WIDTH{1'b0}};
            fp32_last_reg <= 1'b0;
        end else if (flush) begin
            fp32_pending  <= 1'b0;
            fp32_data_reg <= 32'd0;
            fp32_tag_reg  <= {TAG_WIDTH{1'b0}};
            fp32_last_reg <= 1'b0;
        end else begin
            if (relu_fire && fp32_en) begin
                fp32_pending  <= 1'b1;
                fp32_data_reg <= relu_data;
                fp32_tag_reg  <= relu_tag;
                fp32_last_reg <= relu_last;
            end else if (fp32_fire) begin
                fp32_pending  <= 1'b0;
            end
        end
    end

endmodule
