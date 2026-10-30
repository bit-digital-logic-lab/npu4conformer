`timescale 1ns/1ps

module tb_pe_compare;
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

    // Outputs from baseline
    wire [15:0] a_out_base;
    wire [6:0]  w_out_base;
    wire        av_out_base, wv_out_base;
    wire signed [47:0] sum_base;

    // Outputs from CC candidate
    wire [15:0] a_out_cc;
    wire [6:0]  w_out_cc;
    wire        av_out_cc, wv_out_cc;
    wire signed [47:0] sum_cc;

    // Outputs from CSA candidate
    wire [15:0] a_out_csa;
    wire [6:0]  w_out_csa;
    wire        av_out_csa, wv_out_csa;
    wire signed [47:0] sum_csa;

    // 1. Baseline DUT
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

    // 2. Candidate A: Pipelined Carry-Chain
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

    // 3. Candidate B: Dual-Rail CSA
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
    integer r;
    reg [15:0] v_a;
    reg [6:0]  v_w;
    reg [15:0] v_pos;
    reg        v_clip;
    reg        v_av, v_wv, v_clr, v_flush;
    integer sample_count;

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
        sample_count = 0;

        #20;
        reset = 0;
        #10;

        fd_in = $fopen("bench/test_vectors_pe.txt", "r");
        if (fd_in == 0) begin
            $display("ERROR: could not open test_vectors_pe.txt");
            $finish;
        end
        fd_out = $fopen("bench/sim_output_pe_compare.txt", "w");

        while (!$feof(fd_in)) begin
            r = $fscanf(fd_in, "%h %h %h %b %b %b %b %b\n", v_a, v_w, v_pos, v_clip, v_av, v_wv, v_clr, v_flush);
            if (r == 8) begin
                @(posedge clk);
                #1;
                a_in = v_a;
                w_in = v_w;
                positions = v_pos;
                clip = v_clip;
                av_in = v_av;
                wv_in = v_wv;
                clear_sum = v_clr;
                flush = v_flush;

                #3;
                $fdisplay(fd_out, "%012h %012h %012h", sum_base[47:0], sum_cc[47:0], sum_csa[47:0]);
                sample_count = sample_count + 1;
            end
        end

        // Drain pipeline
        repeat (15) begin
            @(posedge clk);
            #1;
            a_in = 0; w_in = 0; av_in = 0; wv_in = 0; clear_sum = 0; flush = 0;
            #3;
            $fdisplay(fd_out, "%012h %012h %012h", sum_base[47:0], sum_cc[47:0], sum_csa[47:0]);
        end

        $fclose(fd_in);
        $fclose(fd_out);
        $display("PE Compare Simulation complete. Samples: %0d", sample_count);
        $finish;
    end

endmodule
