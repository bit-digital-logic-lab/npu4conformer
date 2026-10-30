`timescale 1ns/1ps

module tb_flush_contract;
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

    // 1. Baseline array
    array16_direct_v020 u_base (
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

    // 2. Candidate CC array
    array16_pipeline_v023 #(.USE_CSA(0)) u_cc (
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

    // 3. Candidate CSA array
    array16_pipeline_v023 #(.USE_CSA(1)) u_csa (
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

    // Local storage for 16x32 and 32x16 matrix blocks
    reg [15:0] mat_a [0:15][0:31];
    reg [6:0]  mat_w [0:31][0:15];

    integer r, c, ki, run_cycle;
    integer fd_out;
    integer flush_at_cycle;

    task run_block_test(input integer flush_cycle_target, input integer test_mode);
        begin
            flush_at_cycle = flush_cycle_target;
            @(posedge clk);
            #1;
            clear_sum = 1;
            flush = 0;
            @(posedge clk);
            #1;
            clear_sum = 0;

            // Replicate block_engine_l1bank_v020 systolic feeding
            for (run_cycle = 0; run_cycle <= 68; run_cycle = run_cycle + 1) begin
                // Check flush assertion according to block_engine state contract
                // In block_engine, flush = (state != RUN).
                // If RUN finishes at run_cycle == flush_cycle_target,
                // state transitions to C_READ on the clock edge, so flush becomes 1 after that edge.
                if (run_cycle > flush_at_cycle) begin
                    flush = 1;
                end else begin
                    flush = 0;
                end

                a_left = 0;
                av = 0;
                w_top = 0;
                wv = 0;

                // Only drive inputs while RUN is active
                if (run_cycle <= flush_at_cycle) begin
                    for (r = 0; r < 16; r = r + 1) begin
                        ki = run_cycle - r;
                        if (ki >= 0 && ki < 32) begin
                            a_left[r*16 +: 16] = mat_a[r][ki];
                            av[r] = 1;
                        end
                    end

                    for (c = 0; c < 16; c = c + 1) begin
                        ki = run_cycle - c;
                        if (ki >= 0 && ki < 32) begin
                            w_top[c*7 +: 7] = mat_w[ki][c];
                            wv[c] = 1;
                        end
                    end
                end

                @(posedge clk);
                #1;
            end

            // Now dump PE(15,15) (index 255) and PE(0,0) (index 0) results
            $fdisplay(fd_out, "MODE %0d FLUSH_AT %0d PE00 %012h %012h %012h PE1515 %012h %012h %012h",
                test_mode,
                flush_at_cycle,
                sums_base[0 +: 48],
                sums_cc[0 +: 48],
                sums_csa[0 +: 48],
                sums_base[(15*16+15)*48 +: 48],
                sums_cc[(15*16+15)*48 +: 48],
                sums_csa[(15*16+15)*48 +: 48]
            );
        end
    endtask

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

        // Initialize pseudo-random matrices
        for (r = 0; r < 16; r = r + 1) begin
            for (ki = 0; ki < 32; ki = ki + 1) begin
                mat_a[r][ki] = ((r * 101 + ki * 37 + 19) & 16'h7FFF) - 16'd5000;
            end
        end
        for (ki = 0; ki < 32; ki = ki + 1) begin
            for (c = 0; c < 16; c = c + 1) begin
                mat_w[ki][c] = (c * 79 + ki * 17 + 11) & 7'h7F;
            end
        end

        fd_out = $fopen("logs/sim_flush_contract.txt", "w");

        // Test 1: Exact block_engine contract (flush asserted after cycle 65)
        run_block_test(65, 1);

        // Test 2: Premature flush (flush asserted after cycle 64 - 1 cycle too early)
        run_block_test(64, 2);

        // Test 3: Delayed flush (flush asserted after cycle 66 - 1 cycle slack)
        run_block_test(66, 3);

        // Test 4: Generous flush (flush asserted after cycle 70)
        run_block_test(70, 4);

        $fclose(fd_out);
        $display("tb_flush_contract completed!");
        $finish;
    end

endmodule
