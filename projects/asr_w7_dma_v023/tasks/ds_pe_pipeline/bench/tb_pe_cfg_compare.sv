`timescale 1ns/1ps
// tb_pe_cfg_compare.sv
// Drives identical vectors into the historical baseline and into
// pe_w7_c48_cfg with PIPE_STAGES=3/4/5/6 plus the CSA variant.
// Every vector line is one clock cycle.  Outputs are sampled after the
// following posedge, so the file is a cycle-by-cycle trace.
module tb_pe_cfg_compare;
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

    wire signed [47:0] sum_base;
    wire signed [47:0] sum_s3;
    wire signed [47:0] sum_s4;
    wire signed [47:0] sum_s5;
    wire signed [47:0] sum_s6;
    wire signed [47:0] sum_csa;

    pe_direct_v020 u_base (
        .clk(clk), .reset(reset), .flush(flush), .clear_sum(clear_sum),
        .a_in(a_in), .w_in(w_in), .av_in(av_in), .wv_in(wv_in),
        .positions(positions), .clip(clip),
        .a_out(), .w_out(), .av_out(), .wv_out(), .sum(sum_base)
    );

    pe_w7_c48_cfg #(.PIPE_STAGES(3), .ACCUM_MODE(0), .CPA_PIPE(1)) u_s3 (
        .clk(clk), .reset(reset), .flush(flush), .clear_sum(clear_sum),
        .a_in(a_in), .w_in(w_in), .av_in(av_in), .wv_in(wv_in),
        .positions(positions), .clip(clip),
        .a_out(), .w_out(), .av_out(), .wv_out(), .sum(sum_s3),
        .sum_valid(), .pipe_empty(), .latency_cycles(), .drain_cycles()
    );

    pe_w7_c48_cfg #(.PIPE_STAGES(4), .ACCUM_MODE(0), .CPA_PIPE(1)) u_s4 (
        .clk(clk), .reset(reset), .flush(flush), .clear_sum(clear_sum),
        .a_in(a_in), .w_in(w_in), .av_in(av_in), .wv_in(wv_in),
        .positions(positions), .clip(clip),
        .a_out(), .w_out(), .av_out(), .wv_out(), .sum(sum_s4),
        .sum_valid(), .pipe_empty(), .latency_cycles(), .drain_cycles()
    );

    pe_w7_c48_cfg #(.PIPE_STAGES(5), .ACCUM_MODE(0), .CPA_PIPE(1)) u_s5 (
        .clk(clk), .reset(reset), .flush(flush), .clear_sum(clear_sum),
        .a_in(a_in), .w_in(w_in), .av_in(av_in), .wv_in(wv_in),
        .positions(positions), .clip(clip),
        .a_out(), .w_out(), .av_out(), .wv_out(), .sum(sum_s5),
        .sum_valid(), .pipe_empty(), .latency_cycles(), .drain_cycles()
    );

    pe_w7_c48_cfg #(.PIPE_STAGES(6), .ACCUM_MODE(0), .CPA_PIPE(1)) u_s6 (
        .clk(clk), .reset(reset), .flush(flush), .clear_sum(clear_sum),
        .a_in(a_in), .w_in(w_in), .av_in(av_in), .wv_in(wv_in),
        .positions(positions), .clip(clip),
        .a_out(), .w_out(), .av_out(), .wv_out(), .sum(sum_s6),
        .sum_valid(), .pipe_empty(), .latency_cycles(), .drain_cycles()
    );

    pe_w7_c48_cfg #(.PIPE_STAGES(4), .ACCUM_MODE(1), .CPA_PIPE(1)) u_csa (
        .clk(clk), .reset(reset), .flush(flush), .clear_sum(clear_sum),
        .a_in(a_in), .w_in(w_in), .av_in(av_in), .wv_in(wv_in),
        .positions(positions), .clip(clip),
        .a_out(), .w_out(), .av_out(), .wv_out(), .sum(sum_csa),
        .sum_valid(), .pipe_empty(), .latency_cycles(), .drain_cycles()
    );

    always #5 clk = ~clk;

    integer fd_in, fd_out, r, cycles;
    reg [15:0] v_a;
    reg [6:0]  v_w;
    reg [15:0] v_pos;
    reg        v_clip, v_av, v_wv, v_reset, v_flush, v_clear;
    reg [1023:0] vec_file;
    reg [1023:0] out_file;

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
        cycles = 0;

        if (!$value$plusargs("VEC=%s", vec_file)) begin
            $display("ERROR: +VEC=<file> is required");
            $finish;
        end
        if (!$value$plusargs("OUT=%s", out_file)) begin
            $display("ERROR: +OUT=<file> is required");
            $finish;
        end
        fd_in = $fopen(vec_file, "r");
        fd_out = $fopen(out_file, "w");
        if (fd_in == 0) begin
            $display("ERROR: cannot open %0s", vec_file);
            $finish;
        end

        // Controller-facing constants; no hard-coded 65.
        $display("DRAIN base=4 s3=%0d s4=%0d s5=%0d s6=%0d csa=%0d",
                 u_s3.drain_cycles, u_s4.drain_cycles, u_s5.drain_cycles,
                 u_s6.drain_cycles, u_csa.drain_cycles);

        #20;
        reset = 0;
        #1;

        while (!$feof(fd_in)) begin
            r = $fscanf(fd_in, "%h %h %h %b %b %b %b %b %b\n",
                        v_a, v_w, v_pos, v_clip, v_av, v_wv,
                        v_reset, v_flush, v_clear);
            if (r == 9) begin
                @(negedge clk);
                a_in      = v_a;
                w_in      = v_w;
                positions = v_pos;
                clip      = v_clip;
                av_in     = v_av;
                wv_in     = v_wv;
                reset     = v_reset;
                flush     = v_flush;
                clear_sum = v_clear;
                @(posedge clk); #1;
                $fdisplay(fd_out, "%012h %012h %012h %012h %012h %012h",
                          sum_base[47:0], sum_s3[47:0], sum_s4[47:0],
                          sum_s5[47:0], sum_s6[47:0], sum_csa[47:0]);
                cycles = cycles + 1;
            end
        end

        // Fixed tail drain.  The largest supported drain is 8 cycles; 40 is
        // deliberately generous and is not used as a timing proof.
        repeat (40) begin
            @(negedge clk);
            a_in = 0; w_in = 0; av_in = 0; wv_in = 0;
            reset = 0; flush = 0; clear_sum = 0;
            @(posedge clk); #1;
            $fdisplay(fd_out, "%012h %012h %012h %012h %012h %012h",
                      sum_base[47:0], sum_s3[47:0], sum_s4[47:0],
                      sum_s5[47:0], sum_s6[47:0], sum_csa[47:0]);
            cycles = cycles + 1;
        end

        $fclose(fd_in);
        $fclose(fd_out);
        $display("PE_CFG_DONE cycles=%0d", cycles);
        $finish;
    end
endmodule
