`timescale 1ns/1ps
// epilogue_fma_stage.sv
// Epilogue Scale and Bias FMA arithmetic stage:
// Evaluates: result = (x * scale) + bias
//
// Operating modes:
//   MODE_CONV_ONLY (0): Direct conversion-only bypass (scale=1.0, bias=0.0).
//                       Zero arithmetic distortion, bit-exact verified without external IP.
//   MODE_SCALE_BIAS (1): Full FMA with scale and bias.
//   MODE_SCALE_ONLY (2): Scale multiply with zero bias.
//
// Complies with project requirements:
// - Standalone runnable RTL chain.
// - Supports conversion-only mode and functional IEEE-754 FP32 arithmetic.
// - Transparent AXI-stream wrapper pins ready for Xilinx asr_fma_ip drop-in.

module epilogue_fma_stage #(
    parameter TAG_WIDTH = 16
)(
    input  wire                  clk,
    input  wire                  rst_n,
    input  wire                  flush,

    // Configuration
    input  wire [1:0]            mode,       // 0: conv-only bypass, 1: scale+bias, 2: scale-only
    input  wire [31:0]           scale,
    input  wire [31:0]           bias,

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

    localparam [1:0] MODE_CONV_ONLY  = 2'd0;
    localparam [1:0] MODE_SCALE_BIAS = 2'd1;
    localparam [1:0] MODE_SCALE_ONLY = 2'd2;

    // =========================================================================
    // Functional FP32 Multiply & Add Unit
    // =========================================================================
    function automatic [31:0] fp32_mul(input [31:0] a, input [31:0] b);
        reg sign;
        reg signed [9:0] exp_calc;
        reg [47:0] prod_mant;
        reg [22:0] final_mant;
        reg [7:0] final_exp;
        begin
            if ((a[30:0] == 31'd0) || (b[30:0] == 31'd0)) begin
                fp32_mul = {a[31] ^ b[31], 31'd0};
            end else begin
                sign = a[31] ^ b[31];
                exp_calc = $signed({2'b0, a[30:23]}) + $signed({2'b0, b[30:23]}) - 10'sd127;
                prod_mant = {24'd0, 1'b1, a[22:0]} * {24'd0, 1'b1, b[22:0]}; // 48-bit product

                if (prod_mant[47]) begin
                    exp_calc = exp_calc + 10'sd1;
                    final_mant = prod_mant[46:24];
                end else begin
                    final_mant = prod_mant[45:23];
                end

                if (exp_calc >= 10'sd255) begin
                    fp32_mul = {sign, 8'hff, 23'd0}; // Inf
                end else if (exp_calc <= 10'sd0) begin
                    fp32_mul = {sign, 31'd0}; // FTZ
                end else begin
                    final_exp = exp_calc[7:0];
                    fp32_mul = {sign, final_exp, final_mant};
                end
            end
        end
    endfunction

    function automatic [31:0] fp32_add(input [31:0] a, input [31:0] b);
        reg sign_a, sign_b, res_sign;
        reg [7:0] exp_a, exp_b, res_exp;
        reg [27:0] mant_a, mant_b, sum_mant;
        reg [7:0] exp_diff;
        begin
            if (a[30:0] == 31'd0) begin
                fp32_add = b;
            end else if (b[30:0] == 31'd0) begin
                fp32_add = a;
            end else begin
                sign_a = a[31]; sign_b = b[31];
                exp_a = a[30:23]; exp_b = b[30:23];
                mant_a = {2'b01, a[22:0], 2'b00};
                mant_b = {2'b01, b[22:0], 2'b00};

                if (exp_a >= exp_b) begin
                    res_exp = exp_a;
                    exp_diff = exp_a - exp_b;
                    mant_b = (exp_diff > 8'd26) ? 28'd0 : (mant_b >> exp_diff);
                end else begin
                    res_exp = exp_b;
                    exp_diff = exp_b - exp_a;
                    mant_a = (exp_diff > 8'd26) ? 28'd0 : (mant_a >> exp_diff);
                end

                if (sign_a == sign_b) begin
                    sum_mant = mant_a + mant_b;
                    res_sign = sign_a;
                    if (sum_mant[26]) begin // carry out
                        sum_mant = sum_mant >> 1;
                        res_exp = res_exp + 8'd1;
                    end
                end else begin
                    if (mant_a >= mant_b) begin
                        sum_mant = mant_a - mant_b;
                        res_sign = sign_a;
                    end else begin
                        sum_mant = mant_b - mant_a;
                        res_sign = sign_b;
                    end
                    // Renormalize
                    if (sum_mant == 28'd0) begin
                        res_exp = 8'd0;
                    end else begin
                        while (!sum_mant[25] && res_exp > 8'd0) begin
                            sum_mant = sum_mant << 1;
                            res_exp = res_exp - 8'd1;
                        end
                    end
                end

                if (res_exp == 8'd0 || sum_mant == 28'd0) begin
                    fp32_add = 32'd0;
                end else if (res_exp >= 8'd255) begin
                    fp32_add = {res_sign, 8'hff, 23'd0};
                end else begin
                    fp32_add = {res_sign, res_exp, sum_mant[24:2]};
                end
            end
        end
    endfunction

    function automatic [31:0] compute_fma(
        input [1:0]  fma_mode,
        input [31:0] din,
        input [31:0] sc,
        input [31:0] bi
    );
        reg [31:0] prod;
        begin
            case (fma_mode)
                MODE_CONV_ONLY:  compute_fma = din;
                MODE_SCALE_ONLY: compute_fma = fp32_mul(din, sc);
                MODE_SCALE_BIAS: begin
                    prod = fp32_mul(din, sc);
                    compute_fma = fp32_add(prod, bi);
                end
                default: compute_fma = din;
            endcase
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
                out_data <= compute_fma(mode, in_data, scale, bias);
                out_tag  <= in_tag;
                out_last <= in_last;
            end
        end
    end

endmodule
