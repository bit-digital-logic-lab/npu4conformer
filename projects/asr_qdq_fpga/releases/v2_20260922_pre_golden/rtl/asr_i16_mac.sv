`timescale 1ns/1ps
// Signed W16A16 multiply/accumulate. The accumulator wraps on overflow; the
// sticky overflow output must be checked by the command controller.
// clear has priority over a product and does NOT produce an output beat.
// Every accepted product produces one output beat containing the new sum.
module asr_i16_mac (
    input  wire                 clk,
    input  wire                 rst_n,
    input  wire                 clear_valid,
    output wire                 clear_ready,
    input  wire signed [47:0]   clear_value,
    input  wire                 in_valid,
    output wire                 in_ready,
    input  wire signed [15:0]   in_a,
    input  wire signed [15:0]   in_b,
    output reg                  out_valid,
    input  wire                 out_ready,
    output reg signed [47:0]    out_sum,
    output reg                  overflow
);
    reg signed [47:0] accumulator;
    wire slot_available = !out_valid || out_ready;
    assign clear_ready = slot_available;
    assign in_ready = slot_available && !clear_valid;
    (* use_dsp = "yes" *) wire signed [31:0] product = in_a * in_b;
    wire signed [48:0] wide_sum = {accumulator[47], accumulator}
                                  + {{17{product[31]}}, product};
    wire sum_overflow = wide_sum[48] != wide_sum[47];
    always @(posedge clk) begin
        if (!rst_n) begin
            accumulator <= 48'sd0;
            out_sum <= 48'sd0;
            out_valid <= 1'b0;
            overflow <= 1'b0;
        end else begin
            if (out_valid && out_ready)
                out_valid <= 1'b0;
            if (clear_valid && clear_ready) begin
                accumulator <= clear_value;
                overflow <= 1'b0;
            end else if (in_valid && in_ready) begin
                accumulator <= wide_sum[47:0];
                out_sum <= wide_sum[47:0];
                overflow <= overflow || sum_overflow;
                out_valid <= 1'b1;
            end
        end
    end
endmodule
