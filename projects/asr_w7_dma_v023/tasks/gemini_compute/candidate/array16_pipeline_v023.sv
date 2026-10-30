`timescale 1ns/1ps
// array16_pipeline_v023.sv
// 16x16 Systolic PE sub-array supporting both Carry-Chain and CSA pipeline candidates.
// Parameter USE_CSA: 0 = pe_pipeline_cc_v023 (Recommended), 1 = pe_pipeline_csa_v023.

module array16_pipeline_v023 #(
    parameter USE_CSA = 0
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
    output wire [12287:0] sums
);

    wire [15:0] aa [0:15][0:16];
    wire [6:0]  ww [0:16][0:15];
    wire        va [0:15][0:16];
    wire        vw [0:16][0:15];

    for (genvar r = 0; r < 16; r = r + 1) begin : rows
        assign aa[r][0] = a_left[r*16 +: 16];
        assign va[r][0] = av[r];

        for (genvar c = 0; c < 16; c = c + 1) begin : cols
            if (USE_CSA == 0) begin : gen_cc
                pe_pipeline_cc_v023 u_pe (
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
                    .sum(sums[(r*16+c)*48 +: 48])
                );
            end else begin : gen_csa
                pe_pipeline_csa_v023 u_pe (
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
                    .sum(sums[(r*16+c)*48 +: 48])
                );
            end
        end
    end

    for (genvar c = 0; c < 16; c = c + 1) begin : top
        assign ww[0][c] = w_top[c*7 +: 7];
        assign vw[0][c] = wv[c];
    end

endmodule
