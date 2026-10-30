`timescale 1ns/1ps

module tb_array16_compare;
    reg clk;
    reg reset;
    reg flush;
    reg clear_sum;

    reg [255:0] a_left;
    reg [111:0] w_top;
    reg [15:0]  av;
    reg [15:0]  wv;
    reg [15:0]  positions;
    reg         clip;

    wire [12287:0] sums_base;
    wire [12287:0] sums_cc;
    wire [12287:0] sums_csa;

    // 1. Baseline 16x16 array
    array16_direct_v020 u_base_array (
        .clk(clk),
        .reset(reset),
        .flush(flush),
        .clear_sum(clear_sum),
        .a_left(a_left),
        .w_top(w_top),
        .av(av),
        .wv(wv),
        .positions(positions),
        .clip(clip),
        .sums(sums_base)
    );

    // 2. Candidate A: Pipelined Carry-Chain Array
    array16_pipeline_v023 #(.USE_CSA(0)) u_cc_array (
        .clk(clk),
        .reset(reset),
        .flush(flush),
        .clear_sum(clear_sum),
        .a_left(a_left),
        .w_top(w_top),
        .av(av),
        .wv(wv),
        .positions(positions),
        .clip(clip),
        .sums(sums_cc)
    );

    // 3. Candidate B: Dual-Rail CSA Array
    array16_pipeline_v023 #(.USE_CSA(1)) u_csa_array (
        .clk(clk),
        .reset(reset),
        .flush(flush),
        .clear_sum(clear_sum),
        .a_left(a_left),
        .w_top(w_top),
        .av(av),
        .wv(wv),
        .positions(positions),
        .clip(clip),
        .sums(sums_csa)
    );

    always #5 clk = ~clk;

    integer fd_out;
    integer step;
    integer r, c, ki;

    // Local matrix storage for feeding systolic wavefront
    // A matrix: 16 rows x 32 K
    // W matrix: 32 K x 16 cols
    reg [15:0] mat_a [0:15][0:31];
    reg [6:0]  mat_w [0:31][0:15];

    initial begin
        clk = 0;
        reset = 1;
        flush = 0;
        clear_sum = 0;
        a_left = 0;
        w_top = 0;
        av = 0;
        wv = 0;
        positions = 16'hC840;
        clip = 1;

        #20;
        reset = 0;
        #10;

        // Clear accumulators
        @(posedge clk);
        #1;
        clear_sum = 1;
        @(posedge clk);
        #1;
        clear_sum = 0;

        // Load pseudo-random test matrix data
        for (r = 0; r < 16; r = r + 1) begin
            for (ki = 0; ki < 32; ki = ki + 1) begin
                mat_a[r][ki] = ((r * 37 + ki * 13 + 5) & 16'h7FFF) - 16'd4000;
            end
        end
        for (ki = 0; ki < 32; ki = ki + 1) begin
            for (c = 0; c < 16; c = c + 1) begin
                mat_w[ki][c] = (c * 23 + ki * 7 + 3) & 7'h7F;
            end
        end

        // Run systolic feed: exactly 67 cycles to feed and drain through all 16x16 PEs
        // ki = step - r for row r
        // ki = step - c for col c
        for (step = 0; step < 70; step = step + 1) begin
            @(posedge clk);
            #1;
            a_left = 0;
            av = 0;
            w_top = 0;
            wv = 0;

            for (r = 0; r < 16; r = r + 1) begin
                ki = step - r;
                if (ki >= 0 && ki < 32) begin
                    a_left[r*16 +: 16] = mat_a[r][ki];
                    av[r] = 1;
                end
            end

            for (c = 0; c < 16; c = c + 1) begin
                ki = step - c;
                if (ki >= 0 && ki < 32) begin
                    w_top[c*7 +: 7] = mat_w[ki][c];
                    wv[c] = 1;
                end
            end
        end

        // Wait extra 5 cycles to guarantee full settling
        repeat (5) @(posedge clk);

        // Dump final results to file
        fd_out = $fopen("bench/sim_output_array16.txt", "w");
        for (r = 0; r < 16; r = r + 1) begin
            for (c = 0; c < 16; c = c + 1) begin
                $fdisplay(fd_out, "%0d %0d %012h %012h %012h",
                    r, c,
                    sums_base[(r*16+c)*48 +: 48],
                    sums_cc[(r*16+c)*48 +: 48],
                    sums_csa[(r*16+c)*48 +: 48]
                );
            end
        end
        $fclose(fd_out);

        $display("16x16 Array Simulation Complete!");
        $finish;
    end

endmodule
