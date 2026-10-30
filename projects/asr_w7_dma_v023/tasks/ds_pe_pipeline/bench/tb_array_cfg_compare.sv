`timescale 1ns/1ps
// tb_array_cfg_compare.sv
// Identical 16x16 wavefront vectors into the historical array and into
// array16_w7_c48_cfg for PIPE_STAGES=3/4/5/6 plus CSA.
// A vector line is one clock cycle.  When the dump bit is 1 after a posedge,
// all 256 sums of every array are written as: array_id pe_index sum_hex.
module tb_array_cfg_compare;
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
    wire [12287:0] sums_s3;
    wire [12287:0] sums_s4;
    wire [12287:0] sums_s5;
    wire [12287:0] sums_s6;
    wire [12287:0] sums_csa;

    wire empty_s3, empty_s4, empty_s5, empty_s6, empty_csa;
    wire done_s3, done_s4, done_s5, done_s6, done_csa;
    wire [7:0] ped_s3, ped_s4, ped_s5, ped_s6, ped_csa;
    wire [7:0] ard_s3, ard_s4, ard_s5, ard_s6, ard_csa;

    array16_direct_v020 u_base (
        .clk(clk), .reset(reset), .flush(flush), .clear_sum(clear_sum),
        .a_left(a_left), .w_top(w_top), .av(av), .wv(wv),
        .positions(positions), .clip(clip), .sums(sums_base)
    );

    array16_w7_c48_cfg #(.PIPE_STAGES(3), .ACCUM_MODE(0), .CPA_PIPE(1)) u_s3 (
        .clk(clk), .reset(reset), .flush(flush), .clear_sum(clear_sum),
        .a_left(a_left), .w_top(w_top), .av(av), .wv(wv),
        .positions(positions), .clip(clip), .sums(sums_s3),
        .pipe_empty(empty_s3), .drain_done(done_s3),
        .pe_drain_cycles(ped_s3), .array_drain_cycles(ard_s3)
    );

    array16_w7_c48_cfg #(.PIPE_STAGES(4), .ACCUM_MODE(0), .CPA_PIPE(1)) u_s4 (
        .clk(clk), .reset(reset), .flush(flush), .clear_sum(clear_sum),
        .a_left(a_left), .w_top(w_top), .av(av), .wv(wv),
        .positions(positions), .clip(clip), .sums(sums_s4),
        .pipe_empty(empty_s4), .drain_done(done_s4),
        .pe_drain_cycles(ped_s4), .array_drain_cycles(ard_s4)
    );

    array16_w7_c48_cfg #(.PIPE_STAGES(5), .ACCUM_MODE(0), .CPA_PIPE(1)) u_s5 (
        .clk(clk), .reset(reset), .flush(flush), .clear_sum(clear_sum),
        .a_left(a_left), .w_top(w_top), .av(av), .wv(wv),
        .positions(positions), .clip(clip), .sums(sums_s5),
        .pipe_empty(empty_s5), .drain_done(done_s5),
        .pe_drain_cycles(ped_s5), .array_drain_cycles(ard_s5)
    );

    array16_w7_c48_cfg #(.PIPE_STAGES(6), .ACCUM_MODE(0), .CPA_PIPE(1)) u_s6 (
        .clk(clk), .reset(reset), .flush(flush), .clear_sum(clear_sum),
        .a_left(a_left), .w_top(w_top), .av(av), .wv(wv),
        .positions(positions), .clip(clip), .sums(sums_s6),
        .pipe_empty(empty_s6), .drain_done(done_s6),
        .pe_drain_cycles(ped_s6), .array_drain_cycles(ard_s6)
    );

    array16_w7_c48_cfg #(.PIPE_STAGES(4), .ACCUM_MODE(1), .CPA_PIPE(1)) u_csa (
        .clk(clk), .reset(reset), .flush(flush), .clear_sum(clear_sum),
        .a_left(a_left), .w_top(w_top), .av(av), .wv(wv),
        .positions(positions), .clip(clip), .sums(sums_csa),
        .pipe_empty(empty_csa), .drain_done(done_csa),
        .pe_drain_cycles(ped_csa), .array_drain_cycles(ard_csa)
    );

    always #5 clk = ~clk;

    integer fd_in, fd_out, r, cycles, i;
    reg [255:0] v_a;
    reg [111:0] v_w;
    reg [15:0]  v_av, v_wv, v_pos;
    reg         v_clip, v_reset, v_flush, v_clear, v_dump;
    reg [1023:0] vec_file;
    reg [1023:0] out_file;

    task dump_all;
        begin
            for (i = 0; i < 256; i = i + 1) begin
                $fdisplay(fd_out, "0 %0d %012h", i, sums_base[i*48 +: 48]);
                $fdisplay(fd_out, "1 %0d %012h", i, sums_s3[i*48 +: 48]);
                $fdisplay(fd_out, "2 %0d %012h", i, sums_s4[i*48 +: 48]);
                $fdisplay(fd_out, "3 %0d %012h", i, sums_s5[i*48 +: 48]);
                $fdisplay(fd_out, "4 %0d %012h", i, sums_s6[i*48 +: 48]);
                $fdisplay(fd_out, "5 %0d %012h", i, sums_csa[i*48 +: 48]);
            end
            $fdisplay(fd_out, "#E 1 %b %b %0d %0d", empty_s3, done_s3, ped_s3, ard_s3);
            $fdisplay(fd_out, "#E 2 %b %b %0d %0d", empty_s4, done_s4, ped_s4, ard_s4);
            $fdisplay(fd_out, "#E 3 %b %b %0d %0d", empty_s5, done_s5, ped_s5, ard_s5);
            $fdisplay(fd_out, "#E 4 %b %b %0d %0d", empty_s6, done_s6, ped_s6, ard_s6);
            $fdisplay(fd_out, "#E 5 %b %b %0d %0d", empty_csa, done_csa, ped_csa, ard_csa);
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

        $display("ARRAY_DRAIN s3=%0d s4=%0d s5=%0d s6=%0d csa=%0d",
                 u_s3.array_drain_cycles, u_s4.array_drain_cycles,
                 u_s5.array_drain_cycles, u_s6.array_drain_cycles,
                 u_csa.array_drain_cycles);

        #20;
        reset = 0;
        #1;

        while (!$feof(fd_in)) begin
            r = $fscanf(fd_in, "%h %h %h %h %h %b %b %b %b %b\n",
                        v_a, v_w, v_av, v_wv, v_pos, v_clip,
                        v_reset, v_flush, v_clear, v_dump);
            if (r == 10) begin
                @(negedge clk);
                a_left    = v_a;
                w_top     = v_w;
                av        = v_av;
                wv        = v_wv;
                positions = v_pos;
                clip      = v_clip;
                reset     = v_reset;
                flush     = v_flush;
                clear_sum = v_clear;
                @(posedge clk); #1;
                cycles = cycles + 1;
                $fdisplay(fd_out, "#S %0d %b %b %b %b %b %b %b %b %b %b",
                          cycles - 1,
                          empty_s3, done_s3, empty_s4, done_s4,
                          empty_s5, done_s5, empty_s6, done_s6,
                          empty_csa, done_csa);
                if (v_dump) dump_all;
            end
        end

        $fclose(fd_in);
        $fclose(fd_out);
        $display("ARRAY_CFG_DONE cycles=%0d", cycles);
        $finish;
    end
endmodule
