`timescale 1ns/1ps
// sat_int16(round_nearest_even(((acc + bias) * multiplier) / 2**shift)).
// bias is in ACCUMULATOR units and is added BEFORE multiplication. It is not
// an ONNX bias conversion: model extraction must explicitly derive its scale.
// Signed 49-bit pre-add and 81-bit product prevent intermediate overflow.
// Iterative multiplication and one-bit shifting bound combinational cost.
module asr_requant (
    input  wire                 clk,
    input  wire                 rst_n,
    input  wire                 in_valid,
    output wire                 in_ready,
    input  wire signed [47:0]   in_acc,
    input  wire signed [31:0]   in_multiplier,
    input  wire [6:0]           in_shift,
    input  wire signed [47:0]   in_bias,
    output wire                 out_valid,
    input  wire                 out_ready,
    output reg signed [15:0]    out_value
);
    localparam [2:0] IDLE = 3'd0, MULTIPLY = 3'd1, SHIFT = 3'd2,
                     ROUND = 3'd3, HOLD = 3'd4;
    reg [2:0] state;
    reg [80:0] multiplicand;
    reg [31:0] multiplier;
    reg [80:0] magnitude;
    reg [5:0] multiply_left;
    reg [6:0] shift_left;
    reg negative, guard_bit, sticky_bit;
    wire signed [48:0] pre_add = {in_acc[47], in_acc}
                                  + {in_bias[47], in_bias};
    wire [48:0] pre_magnitude = pre_add[48] ? (~pre_add + 49'd1) : pre_add;
    wire [31:0] multiplier_magnitude = in_multiplier[31]
                                      ? (~in_multiplier + 32'd1) : in_multiplier;
    wire [80:0] multiply_next = magnitude
                                  + (multiplier[0] ? multiplicand : 81'd0);
    wire round_up = guard_bit && (sticky_bit || magnitude[0]);
    wire [80:0] rounded = magnitude + {{80{1'b0}}, round_up};
    assign in_ready = (state == IDLE);
    assign out_valid = (state == HOLD);
    always @(posedge clk) begin
        if (!rst_n) begin
            state <= IDLE;
            multiplicand <= 81'd0;
            multiplier <= 32'd0;
            magnitude <= 81'd0;
            multiply_left <= 6'd0;
            shift_left <= 7'd0;
            negative <= 1'b0;
            guard_bit <= 1'b0;
            sticky_bit <= 1'b0;
            out_value <= 16'sd0;
        end else begin
            case (state)
                IDLE: if (in_valid) begin
                    multiplicand <= {32'd0, pre_magnitude};
                    multiplier <= multiplier_magnitude;
                    magnitude <= 81'd0;
                    multiply_left <= 6'd32;
                    shift_left <= in_shift;
                    negative <= pre_add[48] ^ in_multiplier[31];
                    guard_bit <= 1'b0;
                    sticky_bit <= 1'b0;
                    state <= MULTIPLY;
                end
                MULTIPLY: begin
                    magnitude <= multiply_next;
                    multiplicand <= multiplicand << 1;
                    multiplier <= multiplier >> 1;
                    multiply_left <= multiply_left - 1'b1;
                    if (multiply_left == 6'd1) begin
                        if (shift_left > 7'd81) begin
                            magnitude <= 81'd0;
                            shift_left <= 7'd0;
                            state <= ROUND;
                        end else if (shift_left == 7'd0) begin
                            state <= ROUND;
                        end else begin
                            state <= SHIFT;
                        end
                    end
                end
                SHIFT: begin
                    // guard becomes the highest discarded bit; sticky includes
                    // only lower discarded bits, for symmetric signed RNE.
                    sticky_bit <= sticky_bit || guard_bit;
                    guard_bit <= magnitude[0];
                    magnitude <= magnitude >> 1;
                    shift_left <= shift_left - 1'b1;
                    if (shift_left == 7'd1)
                        state <= ROUND;
                end
                ROUND: begin
                    if (negative) begin
                        if (rounded >= 81'd32768)
                            out_value <= 16'sh8000;
                        else
                            out_value <= -$signed(rounded[15:0]);
                    end else begin
                        if (rounded > 81'd32767)
                            out_value <= 16'sh7fff;
                        else
                            out_value <= rounded[15:0];
                    end
                    state <= HOLD;
                end
                HOLD: if (out_ready)
                    state <= IDLE;
                default: state <= IDLE;
            endcase
        end
    end
endmodule
