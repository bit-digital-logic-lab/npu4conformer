`timescale 1ns/1ps

module tb_pe_exhaustive;
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

    wire [15:0] a_out_base, a_out_cc, a_out_csa;
    wire [6:0]  w_out_base, w_out_cc, w_out_csa;
    wire        av_out_base, av_out_cc, av_out_csa;
    wire        wv_out_base, wv_out_cc, wv_out_csa;
    wire signed [47:0] sum_base, sum_cc, sum_csa;

    // 1. Baseline PE (latency 3)
    pe_direct_v020 u_base (
        .clk(clk),
        .reset(reset),
        .flush(flush),
        .clear_sum(clear_sum),
        .a_in(a_in),
        .w_in(w_in),
        .av_in(av_in),
        .wv_in(wv_in),
        .positions(positions),
        .clip(clip),
        .a_out(a_out_base),
        .w_out(w_out_base),
        .av_out(av_out_base),
        .wv_out(wv_out_base),
        .sum(sum_base)
    );

    // 2. Candidate A: Pipelined Carry-Chain PE (latency 4)
    pe_pipeline_cc_v023 u_cc (
        .clk(clk),
        .reset(reset),
        .flush(flush),
        .clear_sum(clear_sum),
        .a_in(a_in),
        .w_in(w_in),
        .av_in(av_in),
        .wv_in(wv_in),
        .positions(positions),
        .clip(clip),
        .a_out(a_out_cc),
        .w_out(w_out_cc),
        .av_out(av_out_cc),
        .wv_out(wv_out_cc),
        .sum(sum_cc)
    );

    // 3. Candidate B: Dual-Rail CSA PE (latency 4)
    pe_pipeline_csa_v023 u_csa (
        .clk(clk),
        .reset(reset),
        .flush(flush),
        .clear_sum(clear_sum),
        .a_in(a_in),
        .w_in(w_in),
        .av_in(av_in),
        .wv_in(wv_in),
        .positions(positions),
        .clip(clip),
        .a_out(a_out_csa),
        .w_out(w_out_csa),
        .av_out(av_out_csa),
        .wv_out(wv_out_csa),
        .sum(sum_csa)
    );

    always #5 clk = ~clk;

    integer fd_in, fd_out;
    integer scan_res;
    reg [15:0] in_a;
    reg [6:0]  in_w;
    reg [15:0] in_pos;
    reg        in_clip;
    integer test_id;

    initial begin
        clk = 0;
        reset = 1;
        flush = 0;
        clear_sum = 0;
        a_in = 0;
        w_in = 0;
        av_in = 0;
        wv_in = 0;
        positions = 0;
        clip = 0;

        #20;
        reset = 0;
        #10;

        fd_in = $fopen("tests/vectors_pe_exhaustive.txt", "r");
        if (fd_in == 0) begin
            $display("ERROR: Cannot open tests/vectors_pe_exhaustive.txt");
            $finish;
        end

        fd_out = $fopen("logs/sim_pe_exhaustive.txt", "w");

        test_id = 0;
        while (!$feof(fd_in)) begin
            scan_res = $fscanf(fd_in, "%h %h %h %h\n", in_a, in_w, in_pos, in_clip);
            if (scan_res == 4) begin
                // Clear sum before each single-pulse test
                @(posedge clk);
                #1;
                clear_sum = 1;
                @(posedge clk);
                #1;
                clear_sum = 0;

                // Present 1 valid input pulse
                a_in = in_a;
                w_in = in_w;
                positions = in_pos;
                clip = in_clip;
                av_in = 1;
                wv_in = 1;

                @(posedge clk);
                #1;
                av_in = 0;
                wv_in = 0;

                // Wait 3 cycles (total latency for baseline is 3 cycles)
                repeat (2) @(posedge clk);
                #1;
                // At cycle T+3, baseline has settled
                // Sample baseline sum
                // Wait 1 more cycle (cycle T+4, CC and CSA have settled)
                @(posedge clk);
                #1;
                // Wait another cycle to ensure all three have stable outputs
                @(posedge clk);
                #1;

                $fdisplay(fd_out, "%0d %04h %02h %04h %0d %012h %012h %012h",
                    test_id, in_a, in_w, in_pos, in_clip,
                    sum_base, sum_cc, sum_csa
                );
                test_id = test_id + 1;
            end
        end

        $fclose(fd_in);
        $fclose(fd_out);
        $display("tb_pe_exhaustive completed. Total tests: %0d", test_id);
        $finish;
    end

endmodule
