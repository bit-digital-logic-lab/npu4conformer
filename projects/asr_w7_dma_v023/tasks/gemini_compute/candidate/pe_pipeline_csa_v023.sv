`timescale 1ns/1ps
// pe_pipeline_csa_v023.sv
// Candidate B (Research / ASIC / Extreme Frequency): Dual-Rail CSA PE
// Replaces the 48-bit feedback carry chain with a 3:2 Carry-Save Accumulator.
// Accumulator state consists of sum_s[47:0] and sum_c[47:0].
// In each accumulation step:
//   sum_s <= sum_s ^ sum_c ^ p48
//   sum_c <= ((sum_s & sum_c) | (sum_s & p48) | (sum_c & p48)) << 1
// Accumulation loop has ZERO carry propagation delay (single LUT3 delay).
// Resolves final INT48 sum via Carry Propagate Adder (CPA) outside critical loop.

module pe_pipeline_csa_v023 (
    input  wire        clk,
    input  wire        reset,
    input  wire        flush,
    input  wire        clear_sum,
    input  wire [15:0] a_in,
    input  wire [6:0]  w_in,
    input  wire        av_in,
    input  wire        wv_in,
    input  wire [15:0] positions,
    input  wire        clip,
    output reg  [15:0] a_out,
    output reg  [6:0]  w_out,
    output reg         av_out,
    output reg         wv_out,
    output wire signed [47:0] sum
);

    // Combinational decode of position and saturation
    wire [3:0] p = positions[w_in[5:4]*4 +: 4];
    wire saturated = clip && (p == 4'd12) && (w_in[3:0] >= 4'd8);

    // Stage 0 registers
    reg [15:0] mag0;
    reg [3:0]  m0;
    reg [3:0]  p0;
    reg        neg0;
    reg        sat0;
    reg [3:0]  valid;

    // Stage 1 registers
    (* use_dsp="no" *) wire [19:0] raw_product = mag0 * m0;
    reg [19:0] raw1;
    reg [15:0] mag1;
    reg [3:0]  p1;
    reg        neg1;
    reg        sat1;

    // Stage 2A registers: Variable shifter and saturation subtraction
    wire [31:0] aligned = {12'd0, raw1} << p1;
    wire [31:0] magnitude = aligned - (sat1 ? {16'd0, mag1} : 32'd0);
    reg [31:0]  magnitude2a;
    reg         neg2a;

    // Stage 2B registers: 32-bit conditional negation
    reg signed [31:0] product2b;

    // Stage 3: Dual-Rail CSA Accumulator Registers
    reg [47:0] sum_s;
    reg [47:0] sum_c;

    wire [47:0] p48 = {{16{product2b[31]}}, product2b};

    // 3:2 Compressor Logic (Bitwise independent)
    wire [47:0] csa_sum   = sum_s ^ sum_c ^ p48;
    wire [47:0] csa_carry = ((sum_s & sum_c) | (sum_s & p48) | (sum_c & p48)) << 1;

    always @(posedge clk) begin
        if (reset || flush) begin
            a_out        <= 16'd0;
            w_out        <= 7'd0;
            av_out       <= 1'b0;
            wv_out       <= 1'b0;
            valid        <= 4'd0;
            mag0         <= 16'd0;
            m0           <= 4'd0;
            p0           <= 4'd0;
            neg0         <= 1'b0;
            sat0         <= 1'b0;
            raw1         <= 20'd0;
            mag1         <= 16'd0;
            p1           <= 4'd0;
            neg1         <= 1'b0;
            sat1         <= 1'b0;
            magnitude2a  <= 32'd0;
            neg2a        <= 1'b0;
            product2b    <= 32'd0;
        end else begin
            // Systolic forward registers
            a_out  <= a_in;
            w_out  <= w_in;
            av_out <= av_in;
            wv_out <= wv_in;

            // Valid pipeline: 4 stages
            valid <= {valid[2:0], (av_in && wv_in)};

            // Stage 0: Input abs and decode
            if (av_in && wv_in) begin
                mag0 <= a_in[15] ? (~a_in + 16'd1) : a_in;
                m0   <= saturated ? 4'd8 : w_in[3:0];
                p0   <= p;
                neg0 <= a_in[15] ^ w_in[6];
                sat0 <= saturated;
            end

            // Stage 1: 16x4 multiplier register
            if (valid[0]) begin
                raw1 <= raw_product;
                mag1 <= mag0;
                p1   <= p0;
                neg1 <= neg0;
                sat1 <= sat0;
            end

            // Stage 2A: Shift and Saturation subtract
            if (valid[1]) begin
                magnitude2a <= magnitude;
                neg2a       <= neg1;
            end

            // Stage 2B: Conditional negate
            if (valid[2]) begin
                product2b <= neg2a ? -$signed(magnitude2a) : $signed(magnitude2a);
            end
        end

        // CSA Dual-Rail Accumulation Stage
        if (reset || clear_sum) begin
            sum_s <= 48'd0;
            sum_c <= 48'd0;
        end else if (!flush && valid[3]) begin
            sum_s <= csa_sum;
            sum_c <= csa_carry;
        end
    end

    // CPA (Carry Propagate Adder) resolving sum_s + sum_c
    // Evaluated outside the accumulation feedback critical loop.
    assign sum = $signed(sum_s + sum_c);

endmodule
