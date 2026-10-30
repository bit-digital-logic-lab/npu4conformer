`timescale 1ns/1ps
// -----------------------------------------------------------------------------
// pe_delay_stub.sv
// Parameterized latency PE for pipeline verification across arbitrary LATENCY.
// Preserves exact arithmetic of W7p8/A16/C48 contract while allowing LATENCY
// to be swept (3, 4, 5, 6, 8, etc.).
// -----------------------------------------------------------------------------
module pe_delay_stub #(
    parameter integer LATENCY = 3
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
    output reg  signed [47:0] sum,
    output wire        pipe_empty
);

    // Arithmetic decode
    wire [3:0] p = positions[w_in[5:4]*4 +: 4];
    wire saturated = clip && (p == 4'd12) && (w_in[3:0] >= 4'd8);
    wire [15:0] mag = a_in[15] ? (~a_in + 16'd1) : a_in;
    wire [3:0]  m   = saturated ? 4'd8 : w_in[3:0];
    wire [19:0] raw_product = mag * m;
    wire [31:0] aligned = {12'd0, raw_product} << p;
    wire [31:0] magnitude = aligned - (saturated ? {16'd0, mag} : 32'd0);
    wire signed [31:0] product = (a_in[15] ^ w_in[6]) ? -$signed(magnitude) : $signed(magnitude);

    // Pipeline registers of depth LATENCY
    reg [LATENCY-1:0] valid_pipe;
    reg signed [31:0] product_pipe [0:LATENCY-1];

    integer i;
    always @(posedge clk) begin
        if (reset || flush) begin
            a_out      <= 16'd0;
            w_out      <= 7'd0;
            av_out     <= 1'b0;
            wv_out     <= 1'b0;
            valid_pipe <= {LATENCY{1'b0}};
            for (i = 0; i < LATENCY; i = i + 1) begin
                product_pipe[i] <= 32'sd0;
            end
        end else begin
            // Systolic wavefront pass-through (1 cycle skew per coordinate)
            a_out  <= a_in;
            w_out  <= w_in;
            av_out <= av_in;
            wv_out <= wv_in;

            // Pipeline stage 0
            valid_pipe[0]   <= av_in && wv_in;
            product_pipe[0] <= product;

            // Shift downstream stages
            for (i = 1; i < LATENCY; i = i + 1) begin
                valid_pipe[i]   <= valid_pipe[i-1];
                product_pipe[i] <= product_pipe[i-1];
            end
        end

        // Accumulator
        if (reset || clear_sum) begin
            sum <= 48'sd0;
        end else if (!flush && valid_pipe[LATENCY-1]) begin
            sum <= sum + $signed({{16{product_pipe[LATENCY-1][31]}}, product_pipe[LATENCY-1]});
        end
    end

    assign pipe_empty = (valid_pipe == {LATENCY{1'b0}});

endmodule

// -----------------------------------------------------------------------------
// array16_delay_stub.sv
// 16x16 array of pe_delay_stub modules with parameterizable LATENCY.
// -----------------------------------------------------------------------------
module array16_delay_stub #(
    parameter integer LATENCY = 3
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

    localparam integer ARRAY_DRAIN = 15 + LATENCY + 1;

    wire [15:0] aa [0:15][0:16];
    wire [6:0]  ww [0:16][0:15];
    wire        va [0:15][0:16];
    wire        vw [0:16][0:15];
    wire signed [47:0] pe_sum [0:15][0:15];
    wire        pe_empty [0:15][0:15];

    for (genvar r = 0; r < 16; r = r + 1) begin : rows
        assign aa[r][0] = a_left[r*16 +: 16];
        assign va[r][0] = av[r];

        for (genvar c = 0; c < 16; c = c + 1) begin : cols
            pe_delay_stub #(.LATENCY(LATENCY)) pe (
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
                .pipe_empty(pe_empty[r][c])
            );
            assign sums[(r*16+c)*48 +: 48] = pe_sum[r][c];
        end
    end

    for (genvar c = 0; c < 16; c = c + 1) begin : top
        assign ww[0][c] = w_top[c*7 +: 7];
        assign vw[0][c] = wv[c];
    end

    // Array drain tracking
    reg [7:0] quiet;
    wire any_input = (|av) | (|wv);
    always @(posedge clk) begin
        if (reset || flush) begin
            quiet <= 8'd0;
        end else if (any_input) begin
            quiet <= 8'd0;
        end else if (quiet < ARRAY_DRAIN[7:0]) begin
            quiet <= quiet + 8'd1;
        end
    end

    wire empty_now = (quiet >= (ARRAY_DRAIN[7:0] - 8'd1));
    assign pipe_empty         = (reset || flush) ? 1'b1 : empty_now;
    assign drain_done         = pipe_empty;
    assign pe_drain_cycles    = (LATENCY[7:0] + 8'd1);
    assign array_drain_cycles = ARRAY_DRAIN[7:0];

endmodule
