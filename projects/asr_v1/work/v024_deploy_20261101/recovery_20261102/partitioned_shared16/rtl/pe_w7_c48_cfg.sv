`timescale 1ns/1ps
// -----------------------------------------------------------------------------
// pe_w7_c48_cfg.sv
// Strictly configurable W7p8/A16/C48 processing element.
//
// Numeric contract (unchanged from work/rtl/pe_direct_v020.sv):
//   A16 signed two's complement, including -32768.
//   W7 = {S, J[1:0], M[3:0]}; p = positions[J]; sat = clip && p==12 && M>=8.
//   raw = |A| * (sat ? 8 : M); magnitude = (raw << p) - (sat ? |A| : 0);
//   product32 = (S ^ A_sign) ? -magnitude : magnitude.
//   sum48 = (sum48 + sign_extend(product32)) mod 2^48.
//
// PIPE_STAGES is a real elaboration-time parameter, 3..6:
//   3: ABS/DECODE -> MUL -> SHIFT+SUB+NEG   (the historical baseline shape)
//   4: ABS/DECODE -> MUL -> SHIFT+SUB -> NEG
//   5: ABS/DECODE -> MUL -> SHIFT -> SUB -> NEG
//   6: ABS/DECODE -> MUL -> SHIFT -> SUB -> NEG -> SEXT48
// The last stage is followed by accumulator feedback.  For ACCUM_MODE=1 (CSA)
// an optional final CPA register adds one cycle; the CSA feedback loop itself
// never contains a full-width carry propagation.
//
// DRAIN_CYCLES is the controller-facing constant:
//   number of clocks from the cycle in which an input is accepted until the
//   accumulator update edge for that input (sum visible in the following cycle).
// For ACCUM_MODE=0: DRAIN_CYCLES = PIPE_STAGES + 1.
// For ACCUM_MODE=1, CPA_PIPE=1: DRAIN_CYCLES = PIPE_STAGES + 2.
// No controller may hard-code 65; use DRAIN_CYCLES (see INTERFACE.md).
// -----------------------------------------------------------------------------
module pe_w7_c48_cfg #(
    parameter integer PIPE_STAGES = 4,
    parameter integer ACCUM_MODE  = 0, // 0 = native carry-chain, 1 = dual-rail CSA
    parameter integer CPA_PIPE    = 1  // 1 = register the CSA final CPA
) (
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
    output wire signed [47:0] sum,
    output wire        sum_valid,
    output wire        pipe_empty,
    output wire [7:0]  latency_cycles,
    output wire [7:0]  drain_cycles
);

    localparam integer CPA_EXTRA  = (ACCUM_MODE == 1 && CPA_PIPE == 1) ? 1 : 0;
    localparam integer DRAIN      = PIPE_STAGES + 1 + CPA_EXTRA;
    localparam integer NS         = PIPE_STAGES;

    // Stage operation codes.  Stage 0 (capture) is handled separately.
    localparam integer OP_MUL            = 0;
    localparam integer OP_SHIFT          = 1;
    localparam integer OP_SUB            = 2;
    localparam integer OP_NEG            = 3;
    localparam integer OP_SHIFT_SUB      = 4;
    localparam integer OP_SHIFT_SUB_NEG  = 5;
    localparam integer OP_SEXT48         = 6;
    localparam integer OP_NONE           = 7;

    function automatic integer op_for(input integer s);
        begin
            op_for = OP_NONE;
            if (s == 1) begin
                op_for = OP_MUL;
            end else if (PIPE_STAGES == 3) begin
                if (s == 2) op_for = OP_SHIFT_SUB_NEG;
            end else if (PIPE_STAGES == 4) begin
                if (s == 2) op_for = OP_SHIFT_SUB;
                else if (s == 3) op_for = OP_NEG;
            end else if (PIPE_STAGES == 5) begin
                if (s == 2) op_for = OP_SHIFT;
                else if (s == 3) op_for = OP_SUB;
                else if (s == 4) op_for = OP_NEG;
            end else if (PIPE_STAGES == 6) begin
                if (s == 2) op_for = OP_SHIFT;
                else if (s == 3) op_for = OP_SUB;
                else if (s == 4) op_for = OP_NEG;
                else if (s == 5) op_for = OP_SEXT48;
            end
        end
    endfunction

    // ------------------------------------------------------------------
    // Valid chain.  One always block owns every valid bit, so unused bits
    // are deterministically zero and no bit has multiple drivers.
    // ------------------------------------------------------------------
    reg [5:0] valid;
    integer vi;
    always @(posedge clk) begin
        if (reset || flush) begin
            valid <= 6'd0;
        end else begin
            valid[0] <= av_in && wv_in;
            for (vi = 1; vi < 6; vi = vi + 1) begin
                if (vi < PIPE_STAGES) valid[vi] <= valid[vi-1];
                else                  valid[vi] <= 1'b0;
            end
        end
    end

    // ------------------------------------------------------------------
    // Stage 0: input capture, |A|, W7 decode, clip saturation.
    // ------------------------------------------------------------------
    wire [3:0]  p_dec       = positions[w_in[5:4]*4 +: 4];
    wire        sat_dec     = clip && (p_dec == 4'd12) && (w_in[3:0] >= 4'd8);
    wire [15:0] mag_in      = a_in[15] ? (~a_in + 16'd1) : a_in;
    wire        neg_in      = a_in[15] ^ w_in[6];

    reg [15:0] mag       [0:5];
    reg [3:0]  m         [0:5];
    reg [3:0]  p         [0:5];
    reg        neg       [0:5];
    reg        sat       [0:5];
    reg [19:0] raw       [0:5];
    reg [31:0] aligned   [0:5];
    reg [31:0] magnitude [0:5];
    reg signed [31:0] product   [0:5];
    reg signed [47:0] product48 [0:5];

    always @(posedge clk) begin
        if (reset || flush) begin
            a_out <= 16'd0;
            w_out <= 7'd0;
            av_out <= 1'b0;
            wv_out <= 1'b0;
            mag[0] <= 16'd0;
            m[0]   <= 4'd0;
            p[0]   <= 4'd0;
            neg[0] <= 1'b0;
            sat[0] <= 1'b0;
        end else begin
            a_out  <= a_in;
            w_out  <= w_in;
            av_out <= av_in;
            wv_out <= wv_in;
            if (av_in && wv_in) begin
                mag[0] <= mag_in;
                m[0]   <= sat_dec ? 4'd8 : w_in[3:0];
                p[0]   <= p_dec;
                neg[0] <= neg_in;
                sat[0] <= sat_dec;
            end
        end
    end

    // ------------------------------------------------------------------
    // Stages 1..PIPE_STAGES-1.  Each generate instance owns exactly one
    // stage's data registers.  Multiply, shift, subtract, negation and
    // 48-bit sign extension are never all stacked in one stage for 4..6.
    // ------------------------------------------------------------------
    genvar s;
    generate
        for (s = 1; s < PIPE_STAGES; s = s + 1) begin : g_stage
            localparam integer OP = op_for(s);

            wire [19:0] mul_raw = mag[s-1] * m[s-1]; // 16x4 unsigned
            wire [31:0] shifted = {12'd0, raw[s-1]} << p[s-1];
            wire [31:0] magnitude_expr =
                shifted - (sat[s-1] ? {16'd0, mag[s-1]} : 32'd0);
            wire [31:0] magnitude_from_aligned =
                aligned[s-1] - (sat[s-1] ? {16'd0, mag[s-1]} : 32'd0);

            // Only the fields consumed by a later stage are registered here.
            // This keeps the reference payload lean instead of carrying an
            // unused 190-bit superset through every stage.
            always @(posedge clk) begin
                if (reset || flush) begin
                    if (OP == OP_MUL) begin
                        raw[s] <= 20'd0; mag[s] <= 16'd0; p[s] <= 4'd0;
                        neg[s] <= 1'b0; sat[s] <= 1'b0;
                    end else if (OP == OP_SHIFT_SUB_NEG) begin
                        product[s] <= 32'sd0;
                    end else if (OP == OP_SHIFT_SUB) begin
                        magnitude[s] <= 32'd0; neg[s] <= 1'b0;
                    end else if (OP == OP_SHIFT) begin
                        aligned[s] <= 32'd0; mag[s] <= 16'd0;
                        sat[s] <= 1'b0; neg[s] <= 1'b0;
                    end else if (OP == OP_SUB) begin
                        magnitude[s] <= 32'd0; neg[s] <= 1'b0;
                    end else if (OP == OP_NEG) begin
                        product[s] <= 32'sd0;
                    end else if (OP == OP_SEXT48) begin
                        product48[s] <= 48'sd0;
                    end
                end else if (valid[s-1]) begin
                    if (OP == OP_MUL) begin
                        raw[s] <= mul_raw;
                        mag[s] <= mag[s-1];
                        p[s]   <= p[s-1];
                        neg[s] <= neg[s-1];
                        sat[s] <= sat[s-1];
                    end else if (OP == OP_SHIFT) begin
                        aligned[s] <= shifted;
                        mag[s]     <= mag[s-1];
                        sat[s]     <= sat[s-1];
                        neg[s]     <= neg[s-1];
                    end else if (OP == OP_SUB) begin
                        magnitude[s] <= magnitude_from_aligned;
                        neg[s]       <= neg[s-1];
                    end else if (OP == OP_NEG) begin
                        product[s] <= neg[s-1] ? -$signed(magnitude[s-1])
                                               :  $signed(magnitude[s-1]);
                    end else if (OP == OP_SHIFT_SUB) begin
                        magnitude[s] <= magnitude_expr;
                        neg[s]       <= neg[s-1];
                    end else if (OP == OP_SHIFT_SUB_NEG) begin
                        product[s] <= neg[s-1] ? -$signed(magnitude_expr)
                                               :  $signed(magnitude_expr);
                    end else if (OP == OP_SEXT48) begin
                        product48[s] <= {{16{product[s-1][31]}}, product[s-1]};
                    end
                end
            end
        end
    endgenerate

    // Final 48-bit product presented to the accumulator.  For 3..5 stages the
    // sign extension is combinational; the optional 6th stage registers it.
    wire signed [47:0] final_product;
    generate
        if (PIPE_STAGES == 6) begin : g_prod48
            assign final_product = product48[5];
        end else begin : g_prod32
            assign final_product =
                $signed({{16{product[PIPE_STAGES-1][31]}}, product[PIPE_STAGES-1]});
        end
    endgenerate

    wire acc_fire = !reset && !flush && !clear_sum && valid[PIPE_STAGES-1];

    // ------------------------------------------------------------------
    // Accumulator.  Mode 0 is the FPGA-native CARRY8-friendly feedback.  Mode 1
    // is a 3:2 CSA feedback loop; its optional final CPA register is the only
    // place where a 48-bit carry chain appears.
    // ------------------------------------------------------------------
    reg sum_valid_q;
    reg sum_valid_qq;
    always @(posedge clk) begin
        if (reset) begin
            sum_valid_q  <= 1'b0;
            sum_valid_qq <= 1'b0;
        end else begin
            sum_valid_q  <= acc_fire;
            sum_valid_qq <= sum_valid_q;
        end
    end

    generate
        if (ACCUM_MODE == 0) begin : g_accum_carry
            reg signed [47:0] sum_acc;
            always @(posedge clk) begin
                if (reset) begin
                    sum_acc <= 48'sd0;
                end else if (clear_sum) begin
                    sum_acc <= 48'sd0;
                end else if (acc_fire) begin
                    sum_acc <= sum_acc + final_product;
                end
            end
            assign sum         = sum_acc;
            assign sum_valid   = sum_valid_q;
            assign pipe_empty  = ~|valid;
        end else begin : g_accum_csa
            reg [47:0] sum_s;
            reg [47:0] sum_c;
            wire [47:0] csa_sum   = sum_s ^ sum_c ^ final_product;
            wire [47:0] csa_carry =
                ((sum_s & sum_c) | (sum_s & final_product) | (sum_c & final_product)) << 1;

            always @(posedge clk) begin
                if (reset || clear_sum) begin
                    sum_s <= 48'd0;
                    sum_c <= 48'd0;
                end else if (acc_fire) begin
                    sum_s <= csa_sum;
                    sum_c <= csa_carry;
                end
            end

            if (CPA_PIPE == 1) begin : g_cpa_pipe
                reg signed [47:0] sum_q;
                always @(posedge clk) begin
                    if (reset) begin
                        sum_q <= 48'sd0;
                    end else if (clear_sum) begin
                        sum_q <= 48'sd0;
                    end else begin
                        sum_q <= $signed(sum_s + sum_c);
                    end
                end
                assign sum        = sum_q;
                assign sum_valid  = sum_valid_qq;
                assign pipe_empty = (~|valid) && !sum_valid_q && !sum_valid_qq;
            end else begin : g_cpa_comb
                assign sum        = $signed(sum_s + sum_c);
                assign sum_valid  = sum_valid_q;
                // Combinational CPA is still a full-width carry propagation and
                // must not be mistaken for a pipelined result by a controller.
                assign pipe_empty = (~|valid) && !sum_valid_q;
            end
        end
    endgenerate

    assign latency_cycles = DRAIN[7:0];
    assign drain_cycles   = DRAIN[7:0];

endmodule
