`timescale 1ns/1ps
// epilogue_f32_to_i16.sv
// Converts IEEE-754 binary32 FP32 to signed 16-bit integer (INT16).
// Fully bit-exact with asr_fp32_alu.sv float_int32 clamped to 16-bit.
// Implements Banker's Rounding (Round to Nearest Even) and [-32768, 32767] saturation clamp.
// 2-stage pipelined with valid/ready handshake and backpressure.

module epilogue_f32_to_i16 #(
    parameter TAG_WIDTH = 16
)(
    input  wire                  clk,
    input  wire                  rst_n,
    input  wire                  flush,

    // Upstream Handshake
    input  wire                  in_valid,
    output wire                  in_ready,
    input  wire [31:0]           in_data,
    input  wire [TAG_WIDTH-1:0]  in_tag,
    input  wire                  in_last,

    // Downstream Handshake
    output wire                  out_valid,
    input  wire                  out_ready,
    output wire signed [15:0]    out_data,
    output wire [TAG_WIDTH-1:0]  out_tag,
    output wire                  out_last
);

    wire is_nan = (&in_data[30:23]) && (|in_data[22:0]);
    wire signed [10:0] exp_unbiased = $signed({3'b0, in_data[30:23]}) - 11'sd127;
    wire [23:0] mant_full = {1'b1, in_data[22:0]};

    // =========================================================================
    // Stage 1: Exponent classification, shifting, discard/halfway extraction
    // =========================================================================
    reg                  s1_valid;
    wire                 s1_ready;
    reg                  s1_sign;
    reg                  s1_nan_or_zero;
    reg                  s1_overflow;
    reg [31:0]           s1_mag;
    reg [31:0]           s1_discard;
    reg [31:0]           s1_halfway;
    reg                  s1_need_round;
    reg [TAG_WIDTH-1:0]  s1_tag;
    reg                  s1_last;

    assign in_ready = !s1_valid || s1_ready;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s1_valid       <= 1'b0;
            s1_sign        <= 1'b0;
            s1_nan_or_zero <= 1'b0;
            s1_overflow    <= 1'b0;
            s1_mag         <= 32'd0;
            s1_discard     <= 32'd0;
            s1_halfway     <= 32'd0;
            s1_need_round  <= 1'b0;
            s1_tag         <= {TAG_WIDTH{1'b0}};
            s1_last        <= 1'b0;
        end else if (flush) begin
            s1_valid <= 1'b0;
        end else if (in_ready) begin
            s1_valid <= in_valid;
            if (in_valid) begin
                s1_sign <= in_data[31];
                s1_tag  <= in_tag;
                s1_last <= in_last;

                if (is_nan || (exp_unbiased < -11'sd1) || (in_data[30:23] == 8'd0)) begin
                    s1_nan_or_zero <= 1'b1;
                    s1_overflow    <= 1'b0;
                    s1_mag         <= 32'd0;
                    s1_need_round  <= 1'b0;
                end else if (exp_unbiased >= 11'sd31) begin
                    s1_nan_or_zero <= 1'b0;
                    s1_overflow    <= 1'b1;
                    s1_mag         <= 32'd0;
                    s1_need_round  <= 1'b0;
                end else begin
                    s1_nan_or_zero <= 1'b0;
                    s1_overflow    <= 1'b0;
                    if (exp_unbiased >= 11'sd23) begin
                        s1_mag        <= {8'b0, mant_full} << (exp_unbiased - 11'sd23);
                        s1_discard    <= 32'd0;
                        s1_halfway    <= 32'd0;
                        s1_need_round <= 1'b0;
                    end else begin
                        begin : shift_calc
                            reg [5:0] shift;
                            reg [31:0] mag_tmp;
                            reg [31:0] discard_tmp;
                            reg [31:0] halfway_tmp;
                            shift = 6'd23 - exp_unbiased[5:0];
                            mag_tmp = {8'b0, mant_full} >> shift;
                            discard_tmp = {8'b0, mant_full} - (mag_tmp << shift);
                            halfway_tmp = 32'd1 << (shift - 6'd1);
                            s1_mag        <= mag_tmp;
                            s1_discard    <= discard_tmp;
                            s1_halfway    <= halfway_tmp;
                            s1_need_round <= 1'b1;
                        end
                    end
                end
            end
        end
    end

    // =========================================================================
    // Stage 2: Banker's Rounding, 2's Complement Sign, and Clamp to [-32768, 32767]
    // =========================================================================
    reg                  s2_valid;
    reg signed [15:0]    s2_data;
    reg [TAG_WIDTH-1:0]  s2_tag;
    reg                  s2_last;

    assign s1_ready  = !s2_valid || out_ready;
    assign out_valid = s2_valid;
    assign out_data  = s2_data;
    assign out_tag   = s2_tag;
    assign out_last  = s2_last;

    function automatic signed [15:0] clamp_round(
        input sign,
        input nan_or_zero,
        input overflow,
        input [31:0] mag,
        input [31:0] discard,
        input [31:0] halfway,
        input need_round
    );
        reg [31:0] rounded_mag;
        reg signed [31:0] signed_val;
        begin
            if (nan_or_zero) begin
                clamp_round = 16'd0;
            end else if (overflow) begin
                clamp_round = sign ? -16'sd32768 : 16'sd32767;
            end else begin
                rounded_mag = mag;
                if (need_round) begin
                    if ((discard > halfway) || ((discard == halfway) && rounded_mag[0])) begin
                        rounded_mag = rounded_mag + 32'd1;
                    end
                end

                signed_val = sign ? (~rounded_mag + 32'd1) : rounded_mag;

                if (signed_val > 32'sd32767) begin
                    clamp_round = 16'sd32767;
                end else if (signed_val < -32'sd32768) begin
                    clamp_round = -16'sd32768;
                end else begin
                    clamp_round = signed_val[15:0];
                end
            end
        end
    endfunction

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s2_valid <= 1'b0;
            s2_data  <= 16'd0;
            s2_tag   <= {TAG_WIDTH{1'b0}};
            s2_last  <= 1'b0;
        end else if (flush) begin
            s2_valid <= 1'b0;
        end else if (s1_ready) begin
            s2_valid <= s1_valid;
            if (s1_valid) begin
                s2_data <= clamp_round(s1_sign, s1_nan_or_zero, s1_overflow,
                                       s1_mag, s1_discard, s1_halfway, s1_need_round);
                s2_tag  <= s1_tag;
                s2_last <= s1_last;
            end
        end
    end

endmodule
