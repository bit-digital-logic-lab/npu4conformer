`timescale 1ns/1ps
// -----------------------------------------------------------------------------
// array16_w7_c48_cfg.sv
// 16x16 physical systolic sub-array built from pe_w7_c48_cfg.
//
// The controller-facing timing contract is explicit and parameter-derived:
//   PE_DRAIN    = PIPE_STAGES + 1 + CSA_CPA_EXTRA
//   ARRAY_DRAIN = 15 + PE_DRAIN
// ARRAY_DRAIN is measured from the last external A/W input cycle.  After that
// many cycles (with no new input) all 256 accumulators are stable and
// drain_done/pipe_empty assert.  This replaces the hard-coded run_cycle==65.
// It is a logic contract only; it is not an STA result and says nothing about
// whether the candidate closes 300 MHz or 600 MHz.
// -----------------------------------------------------------------------------
module array16_w7_c48_cfg #(
    parameter integer PIPE_STAGES = 4,
    parameter integer ACCUM_MODE  = 0,
    parameter integer CPA_PIPE    = 1
) (
    input  wire         clk,
    input  wire         reset,
    input  wire         flush,
    input  wire         clear_sum,
    input  wire [255:0] a_left,
    input  wire [111:0] w_top,
    input  wire [15:0]  av,
    input  wire [15:0]  wv,
    input  wire [15:0]  positions,
    input  wire         clip,
    output wire [12287:0] sums,
    output wire         pipe_empty,
    output wire         drain_done,
    output wire [7:0]   pe_drain_cycles,
    output wire [7:0]   array_drain_cycles
);

    localparam integer CPA_EXTRA   = (ACCUM_MODE == 1 && CPA_PIPE == 1) ? 1 : 0;
    localparam integer PE_DRAIN    = PIPE_STAGES + 1 + CPA_EXTRA;
    localparam integer ARRAY_DRAIN = 15 + PE_DRAIN;

    wire [15:0] aa [0:15][0:16];
    wire [6:0]  ww [0:16][0:15];
    wire        va [0:15][0:16];
    wire        vw [0:16][0:15];
    wire signed [47:0] pe_sum [0:15][0:15];

    for (genvar r = 0; r < 16; r = r + 1) begin : rows
        assign aa[r][0] = a_left[r*16 +: 16];
        assign va[r][0] = av[r];

        for (genvar c = 0; c < 16; c = c + 1) begin : cols
            pe_w7_c48_cfg #(
                .PIPE_STAGES(PIPE_STAGES),
                .ACCUM_MODE(ACCUM_MODE),
                .CPA_PIPE(CPA_PIPE)
            ) u_pe (
                .clk(clk),
                .reset(reset),
                .flush(flush),
                .clear_sum(clear_sum),
                .a_in(aa[r][c]),
                .w_in(ww[r][c]),
                .av_in(va[r][c]),
                .wv_in(vw[r][c]),
                .positions(positions),
                .clip(clip),
                .a_out(aa[r][c+1]),
                .w_out(ww[r+1][c]),
                .av_out(va[r][c+1]),
                .wv_out(vw[r+1][c]),
                .sum(pe_sum[r][c]),
                .sum_valid(),
                .pipe_empty(),
                .latency_cycles(),
                .drain_cycles()
            );
            assign sums[(r*16+c)*48 +: 48] = pe_sum[r][c];
        end
    end

    for (genvar c = 0; c < 16; c = c + 1) begin : top
        assign ww[0][c] = w_top[c*7 +: 7];
        assign vw[0][c] = wv[c];
    end

    // Conservative array-level drain detector.  Any external input restarts
    // the quiet counter.  A 16x16 systolic array has at most 15 cycles of
    // row/column skew before the last product reaches PE(15,15).
    reg [7:0] quiet;
    wire any_input = (|av) | (|wv);
    always @(posedge clk) begin
        if (reset || flush) begin
            // pipeline is empty; hold the quiet counter at the full drain
            // depth so pipe_empty stays high until new input arrives.
            quiet <= ARRAY_DRAIN[7:0];
        end else if (any_input) begin
            quiet <= 8'd0;
        end else if (quiet < ARRAY_DRAIN[7:0]) begin
            quiet <= quiet + 8'd1;
        end
    end

    wire empty_now = (quiet >= ARRAY_DRAIN[7:0]);
    assign pipe_empty        = (reset || flush) ? 1'b1 : empty_now;
    assign drain_done        = pipe_empty;
    assign pe_drain_cycles   = PE_DRAIN[7:0];
    assign array_drain_cycles = ARRAY_DRAIN[7:0];

endmodule
