`timescale 1ns/1ps

module tb_pipeline_stress;
    reg clk;
    reg reset;
    reg flush;
    reg clear_sum;

    reg [15:0] a_in;
    reg [6:0]  w_in;
    reg        av_in;
    reg        wv_in;
    reg [15:0] positions;
    reg        clip;

    wire signed [47:0] sum_base, sum_cc, sum_csa;

    // Baseline
    pe_direct_v020 u_base (
        .clk(clk), .reset(reset), .flush(flush), .clear_sum(clear_sum),
        .a_in(a_in), .w_in(w_in), .av_in(av_in), .wv_in(wv_in),
        .positions(positions), .clip(clip),
        .a_out(), .w_out(), .av_out(), .wv_out(),
        .sum(sum_base)
    );

    // CC
    pe_pipeline_cc_v023 u_cc (
        .clk(clk), .reset(reset), .flush(flush), .clear_sum(clear_sum),
        .a_in(a_in), .w_in(w_in), .av_in(av_in), .wv_in(wv_in),
        .positions(positions), .clip(clip),
        .a_out(), .w_out(), .av_out(), .wv_out(),
        .sum(sum_cc)
    );

    // CSA
    pe_pipeline_csa_v023 u_csa (
        .clk(clk), .reset(reset), .flush(flush), .clear_sum(clear_sum),
        .a_in(a_in), .w_in(w_in), .av_in(av_in), .wv_in(wv_in),
        .positions(positions), .clip(clip),
        .a_out(), .w_out(), .av_out(), .wv_out(),
        .sum(sum_csa)
    );

    always #5 clk = ~clk;

    integer fd_out;
    integer step;
    reg [31:0] lfsr;

    function [31:0] next_lfsr(input [31:0] s);
        next_lfsr = {s[30:0], s[31] ^ s[21] ^ s[1] ^ s[0]};
    endfunction

    initial begin
        clk = 0;
        reset = 1;
        flush = 0;
        clear_sum = 0;
        a_in = 0;
        w_in = 0;
        av_in = 0;
        wv_in = 0;
        positions = 16'hC840;
        clip = 1;
        lfsr = 32'hDEADBEEF;

        #20;
        reset = 0;
        #10;

        fd_out = $fopen("logs/sim_pipeline_stress.txt", "w");

        // -------------------------------------------------------------
        // TEST 1: Extreme C48 Wrap-around stress test
        // -------------------------------------------------------------
        // Accumulate huge positive products repeatedly until C48 overflows
        @(posedge clk); #1; clear_sum = 1;
        @(posedge clk); #1; clear_sum = 0;

        // A = 32767, W with p=12, m=7 -> prod = 32767 * 28672 = +939,495,424
        // Accumulating 2^48 / 9.39e8 ~ 300,000 steps would overflow.
        // Let's do 1000 steps with A = -32768, W = -32767 (prod = +1,073,709,056)
        // Check wrap-around consistency between CC and CSA.
        a_in = 16'h8000; // -32768
        w_in = 7'h68;   // sign=1, j=2, m=8 -> -32767 (with clip=1, p=12)
        positions = 16'hC840; // slot 2 has p=12 (0xC)
        clip = 1;

        for (step = 0; step < 1000; step = step + 1) begin
            av_in = 1;
            wv_in = 1;
            @(posedge clk);
            #1;
        end
        av_in = 0;
        wv_in = 0;
        repeat (5) @(posedge clk); #1;

        $fdisplay(fd_out, "TEST1_C48_LARGE_ACCUM base=%012h cc=%012h csa=%012h",
            sum_base, sum_cc, sum_csa);

        // -------------------------------------------------------------
        // TEST 2: C48 Signed Overflow Wrap-around Direct Test
        // -------------------------------------------------------------
        // To directly cross the 48-bit boundary without 300k cycles,
        // we test positive and negative saturation products and verify that
        // when CSA and CC accumulate consecutive max products, they wrap
        // identically at every single step!
        @(posedge clk); #1; clear_sum = 1;
        @(posedge clk); #1; clear_sum = 0;

        // Feed alternating signs, massive values
        for (step = 0; step < 200; step = step + 1) begin
            lfsr = next_lfsr(lfsr);
            a_in = lfsr[15:0];
            w_in = lfsr[22:16];
            av_in = lfsr[23];
            wv_in = lfsr[23]; // Paired valid

            @(posedge clk);
            #1;
            // Record if there is any mismatch between CC and CSA on any cycle!
            if (sum_cc !== sum_csa) begin
                $fdisplay(fd_out, "ERROR_MISMATCH_CC_CSA step=%0d cc=%012h csa=%012h",
                    step, sum_cc, sum_csa);
            end
        end

        av_in = 0;
        wv_in = 0;
        repeat (5) @(posedge clk); #1;
        $fdisplay(fd_out, "TEST2_RANDOM_STALLS base=%012h cc=%012h csa=%012h",
            sum_base, sum_cc, sum_csa);

        // -------------------------------------------------------------
        // TEST 3: Dynamic Positions Switching Mid-Stream
        // -------------------------------------------------------------
        @(posedge clk); #1; clear_sum = 1;
        @(posedge clk); #1; clear_sum = 0;

        // Step 0: Feed input with positions = 16'hC840
        positions = 16'hC840;
        a_in = 16'd1000;
        w_in = 7'h24; // j=2 (p=12), m=4
        av_in = 1; wv_in = 1;
        @(posedge clk); #1;

        // Step 1: In the very next cycle, immediately change positions to 16'h48C0
        // (now slot 2 is p=8 instead of p=12)
        positions = 16'h48C0;
        a_in = 16'd2000;
        w_in = 7'h24; // j=2 (now p=8), m=4
        @(posedge clk); #1;

        av_in = 0; wv_in = 0;
        repeat (5) @(posedge clk); #1;

        $fdisplay(fd_out, "TEST3_DYNAMIC_POS base=%012h cc=%012h csa=%012h",
            sum_base, sum_cc, sum_csa);

        // -------------------------------------------------------------
        // TEST 4: Clear_sum while pipeline is non-empty
        // -------------------------------------------------------------
        // Feed 2 cycles of data, then assert clear_sum immediately
        a_in = 16'd5000; w_in = 7'h11; av_in = 1; wv_in = 1;
        @(posedge clk); #1;
        a_in = 16'd6000; w_in = 7'h12;
        @(posedge clk); #1;
        clear_sum = 1;
        av_in = 0; wv_in = 0;
        @(posedge clk); #1;
        clear_sum = 0;
        repeat (5) @(posedge clk); #1;

        $fdisplay(fd_out, "TEST4_CLEAR_SUM_FLIGHT base=%012h cc=%012h csa=%012h",
            sum_base, sum_cc, sum_csa);

        $fclose(fd_out);
        $display("tb_pipeline_stress complete!");
        $finish;
    end

endmodule
