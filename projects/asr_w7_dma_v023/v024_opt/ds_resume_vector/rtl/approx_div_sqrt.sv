`timescale 1ns/1ps
// Synthesizable approximate DIV / SQRT / RSQRT execution core
// Conforms to ds_vector/INTERFACE.md section 3.
// Supported operations:
//   op == 2'b00: DIV   (a / b)
//   op == 2'b01: SQRT  (sqrt(a))
//   op == 2'b10: RSQRT (1 / sqrt(a))
//
// Pipeline Architecture:
//   Single production-ready tier: LUT Seed + 1-step Newton-Raphson.
//   Hardware Latency: exactly 5 clock cycles (Stage 0 to Output register).
//   Initiation Interval (II): 1 cycle (fully pipelined back-to-back throughput).
//   Composite multipliers are cleanly split across register boundaries:
//     - Stage 1: Seed squaring / first product
//     - Stage 2: RSQRT inner product + 58-bit subtract; DIV refined seed
//     - Stage 3: RSQRT refined seed multiplication
//     - Stage 4: Numerator multiplication, normalization & output pack
//   Unsupported parameter configurations trigger compile & simulation assertions.

module approx_div_sqrt #(
    parameter integer TIER    = 1,
    parameter integer LATENCY = 5,
    parameter integer II      = 1
)(
    input  wire        clk,
    input  wire        rst_n,
    input              flush = 1'b0,

    // Request interface
    input  wire        in_valid,
    output wire        in_ready,
    input  wire [1:0]  op,
    input  wire [31:0] a,
    input  wire [31:0] b,
    input  wire [15:0] tag,

    // Completion interface
    output reg         out_valid,
    input  wire        out_ready,
    output reg  [31:0] result,
    output reg  [7:0]  flags,
    output reg  [15:0] tag_out
);

    // -------------------------------------------------------------------------
    // Parameter Validation & Strict Assertion
    // -------------------------------------------------------------------------
    generate
        if (TIER != 1) begin : gen_assert_tier
            illegal_tier_parameter_only_tier_1_supported _assert();
        end
        if (LATENCY != 5) begin : gen_assert_latency
            illegal_latency_parameter_must_be_5 _assert();
        end
        if (II != 1) begin : gen_assert_ii
            illegal_ii_parameter_must_be_1 _assert();
        end
    endgenerate

    initial begin
        if (TIER != 1) begin
            $fatal(1, "approx_div_sqrt: Unsupported TIER=%0d. Only TIER=1 (single high-throughput pipeline) is supported.", TIER);
        end
        if (LATENCY != 5) begin
            $fatal(1, "approx_div_sqrt: Configured LATENCY=%0d does not match hardware latency 5.", LATENCY);
        end
        if (II != 1) begin
            $fatal(1, "approx_div_sqrt: Configured II=%0d does not match hardware initiation interval 1.", II);
        end
    end

    // -------------------------------------------------------------------------
    // IEEE-754 Special Constants & Status Flags
    // -------------------------------------------------------------------------
    localparam [31:0] FP32_QNAN    = 32'h7fc00000;
    localparam [31:0] FP32_POS_INF = 32'h7f800000;
    localparam [31:0] FP32_NEG_INF = 32'hff800000;
    localparam [31:0] FP32_POS_ZERO= 32'h00000000;
    localparam [31:0] FP32_NEG_ZERO= 32'h80000000;

    localparam [7:0] FLAG_INVALID   = 8'h01; // [0] NaN, negative sqrt, 0/0, inf/inf
    localparam [7:0] FLAG_DIV_BY_0  = 8'h02; // [1] b == 0 in DIV, or RSQRT(+0)
    localparam [7:0] FLAG_OVERFLOW  = 8'h04; // [2] Exponent overflow
    localparam [7:0] FLAG_UNDERFLOW = 8'h08; // [3] Subnormal / FTZ
    localparam [7:0] FLAG_APPROX    = 8'h10; // [4] Approximate result marker

    function automatic is_nan(input [31:0] x);
        is_nan = (&x[30:23]) && (|x[22:0]);
    endfunction

    function automatic is_inf(input [31:0] x);
        is_inf = (&x[30:23]) && (~|x[22:0]);
    endfunction

    function automatic is_zero(input [31:0] x);
        is_zero = (~|x[30:0]);
    endfunction

    function automatic is_sub(input [31:0] x);
        is_sub = (~|x[30:23]) && (|x[22:0]);
    endfunction

    function automatic [31:0] ftz(input [31:0] x);
        ftz = (~|x[30:23]) ? {x[31], 31'b0} : x;
    endfunction

    // Pipeline stall control
    wire pipeline_enable = out_ready || !out_valid;
    assign in_ready = pipeline_enable;

    // -------------------------------------------------------------------------
    // Stage 0: Decode, Classification, FTZ, and LUT Lookups
    // -------------------------------------------------------------------------
    wire [31:0] a_ftz = ftz(a);
    wire [31:0] b_ftz = ftz(b);
    wire a_was_sub = is_sub(a);
    wire b_was_sub = is_sub(b);

    wire a_sign = a_ftz[31];
    wire b_sign = b_ftz[31];
    wire [7:0] a_exp = a_ftz[30:23];
    wire [7:0] b_exp = b_ftz[30:23];
    wire [22:0] a_mant = a_ftz[22:0];
    wire [22:0] b_mant = b_ftz[22:0];

    // ROM instances
    wire [15:0] recip_seed;
    approx_recip_lut u_recip_lut (
        .addr(b_mant[22:16]),
        .data(recip_seed)
    );

    wire signed [10:0] a_unbiased_exp = $signed({3'b0, a_exp}) - 11'sd127;
    wire a_exp_is_odd = a_unbiased_exp[0];
    wire [15:0] rsqrt_seed;
    approx_rsqrt_lut u_rsqrt_lut (
        .addr({a_exp_is_odd, a_mant[22:16]}),
        .data(rsqrt_seed)
    );

    // Edge case evaluation
    reg is_special_s0;
    reg [31:0] special_val_s0;
    reg [7:0] special_flags_s0;

    always @* begin
        is_special_s0 = 1'b0;
        special_val_s0 = 32'b0;
        special_flags_s0 = 8'b0;

        if (a_was_sub || ((op == 2'b00) && b_was_sub))
            special_flags_s0 = special_flags_s0 | FLAG_UNDERFLOW;

        if (op == 2'b00) begin // DIV (a / b)
            if (is_nan(a_ftz) || is_nan(b_ftz) || (is_zero(a_ftz) && is_zero(b_ftz)) || (is_inf(a_ftz) && is_inf(b_ftz))) begin
                is_special_s0 = 1'b1;
                special_val_s0 = FP32_QNAN;
                special_flags_s0 = special_flags_s0 | FLAG_INVALID;
            end else if (is_zero(b_ftz)) begin
                is_special_s0 = 1'b1;
                special_val_s0 = (a_sign ^ b_sign) ? FP32_NEG_INF : FP32_POS_INF;
                special_flags_s0 = special_flags_s0 | (is_inf(a_ftz) ? 8'h00 : FLAG_DIV_BY_0);
            end else if (is_inf(a_ftz)) begin
                is_special_s0 = 1'b1;
                special_val_s0 = (a_sign ^ b_sign) ? FP32_NEG_INF : FP32_POS_INF;
            end else if (is_zero(a_ftz) || is_inf(b_ftz)) begin
                is_special_s0 = 1'b1;
                special_val_s0 = (a_sign ^ b_sign) ? FP32_NEG_ZERO : FP32_POS_ZERO;
            end
        end else if (op == 2'b01 || op == 2'b10) begin // SQRT / RSQRT
            if (is_nan(a_ftz) || (a_sign && !is_zero(a_ftz))) begin
                is_special_s0 = 1'b1;
                special_val_s0 = FP32_QNAN;
                special_flags_s0 = special_flags_s0 | FLAG_INVALID;
            end else if (is_zero(a_ftz)) begin
                is_special_s0 = 1'b1;
                if (op == 2'b01) special_val_s0 = a_ftz; // sqrt(+/-0) = +/-0
                else begin
                    special_val_s0 = a_sign ? FP32_NEG_INF : FP32_POS_INF;
                    special_flags_s0 = special_flags_s0 | FLAG_DIV_BY_0;
                end
            end else if (is_inf(a_ftz)) begin
                is_special_s0 = 1'b1;
                special_val_s0 = (op == 2'b01) ? FP32_POS_INF : FP32_POS_ZERO;
            end
        end
    end

    // Stage 0 Pipeline Registers (R0)
    reg        val_r0;
    reg [1:0]  op_r0;
    reg [15:0] tag_r0;
    reg        spec_r0;
    reg [31:0] sval_r0;
    reg [7:0]  sflg_r0;
    reg        sign_r0;
    reg signed [11:0] exp_r0;
    reg signed [10:0] k_r0;
    reg        b_r0;
    reg [24:0] xa_r0;
    reg [23:0] xb_r0;
    reg [15:0] seed_r0;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            val_r0   <= 1'b0;
            op_r0    <= 2'b0;
            tag_r0   <= 16'b0;
            spec_r0  <= 1'b0;
            sval_r0  <= 32'b0;
            sflg_r0  <= 8'b0;
            sign_r0  <= 1'b0;
            exp_r0   <= 12'b0;
            k_r0     <= 11'b0;
            b_r0     <= 1'b0;
            xa_r0    <= 25'b0;
            xb_r0    <= 24'b0;
            seed_r0  <= 16'b0;
        end else if (flush) begin
            val_r0   <= 1'b0;
        end else if (pipeline_enable) begin
            val_r0   <= in_valid;
            op_r0    <= op;
            tag_r0   <= tag;
            spec_r0  <= is_special_s0;
            sval_r0  <= special_val_s0;
            sflg_r0  <= special_flags_s0;

            if (op == 2'b00) begin // DIV
                sign_r0 <= a_sign ^ b_sign;
                exp_r0  <= $signed({4'b0, a_exp}) - $signed({4'b0, b_exp}) + 12'sd127;
                k_r0    <= 11'sd0;
                b_r0    <= 1'b0;
                xa_r0   <= {1'b0, 1'b1, a_mant};
                xb_r0   <= {1'b1, b_mant};
                seed_r0 <= recip_seed;
            end else begin // SQRT / RSQRT
                sign_r0 <= 1'b0;
                k_r0    <= a_unbiased_exp >>> 1;
                b_r0    <= a_exp_is_odd;
                exp_r0  <= 12'sd0;
                xa_r0   <= a_exp_is_odd ? {1'b1, a_mant, 1'b0} : {2'b01, a_mant};
                xb_r0   <= {1'b1, a_mant}; // original A mantissa (Q23)
                seed_r0 <= rsqrt_seed;
            end
        end
    end

    // -------------------------------------------------------------------------
    // Stage 1: Newton-Raphson Step 1 (Inner Residual / Seed Squaring)
    // -------------------------------------------------------------------------
    // For DIV: xb * seed (24-bit x 16-bit = 40-bit Q39)
    wire [39:0] div_p1 = xb_r0 * seed_r0;
    // 2.0 in Q39 is 41'h100_0000_0000
    wire signed [41:0] div_d1 = 42'sh100_0000_0000 - $signed({2'b0, div_p1});

    // For RSQRT: seed * seed (16-bit x 16-bit = 32-bit Q32)
    wire [31:0] rsqrt_y0_sq = seed_r0 * seed_r0;

    // Stage 1 Pipeline Registers (R1)
    reg        val_r1;
    reg [1:0]  op_r1;
    reg [15:0] tag_r1;
    reg        spec_r1;
    reg [31:0] sval_r1;
    reg [7:0]  sflg_r1;
    reg        sign_r1;
    reg signed [11:0] exp_r1;
    reg signed [10:0] k_r1;
    reg        b_r1;
    reg [24:0] xa_r1;
    reg [23:0] xb_r1;
    reg [15:0] seed_r1;
    reg [24:0] res_div_r1;
    reg [31:0] rsqrt_sq_r1;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            val_r1      <= 1'b0;
            op_r1       <= 2'b0;
            tag_r1      <= 16'b0;
            spec_r1     <= 1'b0;
            sval_r1     <= 32'b0;
            sflg_r1     <= 8'b0;
            sign_r1     <= 1'b0;
            exp_r1      <= 12'b0;
            k_r1        <= 11'b0;
            b_r1        <= 1'b0;
            xa_r1       <= 25'b0;
            xb_r1       <= 24'b0;
            seed_r1     <= 16'b0;
            res_div_r1  <= 25'b0;
            rsqrt_sq_r1 <= 32'b0;
        end else if (flush) begin
            val_r1      <= 1'b0;
        end else if (pipeline_enable) begin
            val_r1      <= val_r0;
            op_r1       <= op_r0;
            tag_r1      <= tag_r0;
            spec_r1     <= spec_r0;
            sval_r1     <= sval_r0;
            sflg_r1     <= sflg_r0;
            sign_r1     <= sign_r0;
            exp_r1      <= exp_r0;
            k_r1        <= k_r0;
            b_r1        <= b_r0;
            xa_r1       <= xa_r0;
            xb_r1       <= xb_r0;
            seed_r1     <= seed_r0;
            // d1 has 39 fractional bits; d1 >> 15 leaves 24 fractional bits (Q24)
            res_div_r1  <= div_d1[39:15];
            rsqrt_sq_r1 <= rsqrt_y0_sq;
        end
    end

    // -------------------------------------------------------------------------
    // Stage 2: RSQRT Step 2A (Isolated xa * y0_sq and Subtraction) & DIV Refinement
    // -------------------------------------------------------------------------
    // For DIV: seed * d1 -> refined y1
    wire [40:0] div_y1_wide = seed_r1 * res_div_r1; // 16 x 25 = 41 bits (Q40)
    wire [23:0] div_y1 = div_y1_wide[40:17]; // Q23

    // For RSQRT: xa * y0_sq (25-bit Q23 x 32-bit Q32 = 57-bit Q55)
    wire [56:0] rsqrt_p1 = xa_r1 * rsqrt_sq_r1;
    // 3.0 in Q55 is 3 * 2^55 = 58'sh180_0000_0000_0000.
    wire signed [57:0] rsqrt_d1 = 58'sh180_0000_0000_0000 - $signed({1'b0, rsqrt_p1});

    // Stage 2 Pipeline Registers (R2)
    reg        val_r2;
    reg [1:0]  op_r2;
    reg [15:0] tag_r2;
    reg        spec_r2;
    reg [31:0] sval_r2;
    reg [7:0]  sflg_r2;
    reg        sign_r2;
    reg signed [11:0] exp_r2;
    reg signed [10:0] k_r2;
    reg        b_r2;
    reg [23:0] xa_orig_r2;
    reg [15:0] seed_r2;
    reg [23:0] div_y1_r2;
    reg signed [57:0] rsqrt_d1_r2;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            val_r2       <= 1'b0;
            op_r2        <= 2'b0;
            tag_r2       <= 16'b0;
            spec_r2      <= 1'b0;
            sval_r2      <= 32'b0;
            sflg_r2      <= 8'b0;
            sign_r2      <= 1'b0;
            exp_r2       <= 12'b0;
            k_r2         <= 11'b0;
            b_r2         <= 1'b0;
            xa_orig_r2   <= 24'b0;
            seed_r2      <= 16'b0;
            div_y1_r2    <= 24'b0;
            rsqrt_d1_r2  <= 58'sh0;
        end else if (flush) begin
            val_r2       <= 1'b0;
        end else if (pipeline_enable) begin
            val_r2       <= val_r1;
            op_r2        <= op_r1;
            tag_r2       <= tag_r1;
            spec_r2      <= spec_r1;
            sval_r2      <= sval_r1;
            sflg_r2      <= sflg_r1;
            sign_r2      <= sign_r1;
            exp_r2       <= exp_r1;
            k_r2         <= k_r1;
            b_r2         <= b_r1;
            xa_orig_r2   <= (op_r1 == 2'b00) ? xa_r1[23:0] : xb_r1;
            seed_r2      <= seed_r1;
            div_y1_r2    <= div_y1;
            rsqrt_d1_r2  <= rsqrt_d1;
        end
    end

    // -------------------------------------------------------------------------
    // Stage 3: RSQRT Step 2B (Isolated seed * rsqrt_d1 multiplication)
    // -------------------------------------------------------------------------
    // y1 = 0.5 * seed * d1
    // seed (16-bit Q16) x d1 (58-bit signed Q55) -> 74 bits Q71.
    // 0.5 * wide -> Q72. We want Q23, so shift right by 72 - 23 = 49 bits.
    wire signed [73:0] rsqrt_y1_wide = $signed({1'b0, seed_r2}) * rsqrt_d1_r2;
    wire [23:0] rsqrt_y1 = rsqrt_y1_wide[72:49]; // Q23

    wire [23:0] refined_y_s3 = (op_r2 == 2'b00) ? div_y1_r2 : rsqrt_y1;

    // Stage 3 Pipeline Registers (R3)
    reg        val_r3;
    reg [1:0]  op_r3;
    reg [15:0] tag_r3;
    reg        spec_r3;
    reg [31:0] sval_r3;
    reg [7:0]  sflg_r3;
    reg        sign_r3;
    reg signed [11:0] exp_r3;
    reg signed [10:0] k_r3;
    reg        b_r3;
    reg [23:0] xa_orig_r3;
    reg [23:0] refined_y_r3;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            val_r3       <= 1'b0;
            op_r3        <= 2'b0;
            tag_r3       <= 16'b0;
            spec_r3      <= 1'b0;
            sval_r3      <= 32'b0;
            sflg_r3      <= 8'b0;
            sign_r3      <= 1'b0;
            exp_r3       <= 12'b0;
            k_r3         <= 11'b0;
            b_r3         <= 1'b0;
            xa_orig_r3   <= 24'b0;
            refined_y_r3 <= 24'b0;
        end else if (flush) begin
            val_r3       <= 1'b0;
        end else if (pipeline_enable) begin
            val_r3       <= val_r2;
            op_r3        <= op_r2;
            tag_r3       <= tag_r2;
            spec_r3      <= spec_r2;
            sval_r3      <= sval_r2;
            sflg_r3      <= sflg_r2;
            sign_r3      <= sign_r2;
            exp_r3       <= exp_r2;
            k_r3         <= k_r2;
            b_r3         <= b_r2;
            xa_orig_r3   <= xa_orig_r2;
            refined_y_r3 <= refined_y_s3;
        end
    end

    // -------------------------------------------------------------------------
    // Stage 4: Numerator Multiplication, Normalization and Pack into Output
    // -------------------------------------------------------------------------
    // For DIV: xa * refined_y (Q23 x Q23 = Q46)
    wire [47:0] div_num_prod = xa_orig_r3 * refined_y_r3;

    // For SQRT: A * (1/sqrt(A))
    // y_norm in Q23 = refined_y << 1.
    wire [23:0] rsqrt_y_norm = refined_y_r3 << 1;
    wire [47:0] sqrt_num_prod = xa_orig_r3 * rsqrt_y_norm; // Q23 x Q23 = Q46

    // Normalization & Exponent calculation
    reg [22:0] final_mant_s4;
    reg signed [11:0] final_exp_s4;

    always @* begin
        if (op_r3 == 2'b00) begin // DIV
            if (div_num_prod[46]) begin // >= 1.0
                final_mant_s4 = div_num_prod[45:23];
                final_exp_s4  = exp_r3;
            end else if (div_num_prod[45]) begin // in [0.5, 1.0)
                final_mant_s4 = div_num_prod[44:22];
                final_exp_s4  = exp_r3 - 12'sd1;
            end else begin // in [0.25, 0.5) due to NR approximation dip below 0.5
                final_mant_s4 = div_num_prod[43:21];
                final_exp_s4  = exp_r3 - 12'sd2;
            end
        end else if (op_r3 == 2'b10) begin // RSQRT
            if (rsqrt_y_norm[23]) begin // >= 1.0
                final_mant_s4 = rsqrt_y_norm[22:0];
                final_exp_s4  = 12'sd126 - $signed({{1{k_r3[10]}}, k_r3});
            end else begin // < 1.0 due to NR approximation dip below 1.0
                final_mant_s4 = {rsqrt_y_norm[21:0], 1'b0};
                final_exp_s4  = 12'sd125 - $signed({{1{k_r3[10]}}, k_r3});
            end
        end else begin // SQRT
            if (sqrt_num_prod[47]) begin // >= 2.0
                final_mant_s4 = sqrt_num_prod[46:24];
                final_exp_s4  = 12'sd127 + $signed({{1{k_r3[10]}}, k_r3}) + $signed({11'b0, b_r3});
            end else begin // < 2.0
                final_mant_s4 = sqrt_num_prod[45:23];
                final_exp_s4  = 12'sd126 + $signed({{1{k_r3[10]}}, k_r3}) + $signed({11'b0, b_r3});
            end
        end
    end

    // Pack IEEE-754 FP32
    reg [31:0] normal_fp32_s4;
    reg [7:0]  normal_flags_s4;

    always @* begin
        normal_flags_s4 = FLAG_APPROX;
        if (final_exp_s4 >= 12'sd255) begin
            normal_fp32_s4 = sign_r3 ? FP32_NEG_INF : FP32_POS_INF;
            normal_flags_s4 = normal_flags_s4 | FLAG_OVERFLOW;
        end else if (final_exp_s4 <= 12'sd0) begin
            normal_fp32_s4 = sign_r3 ? FP32_NEG_ZERO : FP32_POS_ZERO;
            normal_flags_s4 = normal_flags_s4 | FLAG_UNDERFLOW;
        end else begin
            normal_fp32_s4 = {sign_r3, final_exp_s4[7:0], final_mant_s4};
        end
    end

    // Output Registers (R4 -> Output Interface, total 5 cycles latency)
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            out_valid <= 1'b0;
            result    <= 32'b0;
            flags     <= 8'b0;
            tag_out   <= 16'b0;
        end else if (flush) begin
            out_valid <= 1'b0;
            result    <= 32'b0;
            flags     <= 8'b0;
            tag_out   <= 16'b0;
        end else if (pipeline_enable) begin
            out_valid <= val_r3;
            tag_out   <= tag_r3;
            if (spec_r3) begin
                result <= sval_r3;
                flags  <= sflg_r3;
            end else begin
                result <= normal_fp32_s4;
                flags  <= normal_flags_s4;
            end
        end
    end

endmodule
