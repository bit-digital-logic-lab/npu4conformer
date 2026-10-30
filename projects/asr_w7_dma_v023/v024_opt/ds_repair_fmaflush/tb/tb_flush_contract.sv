`timescale 1ns/1ps
// AR-001 contract test for fp32_fma_pipe.
// Checks: no input transfer during flush, out_valid cancelled on the flush
// cycle, parked output is discarded, reset is also a handshake barrier,
// post-flush/reset epoch has latency 7 and correct data/tag.
module tb_flush_contract;
    localparam integer LAT = 7;

    reg clk = 0;
    always #5 clk = ~clk;

    reg rst_n = 0, flush = 0, in_valid = 0;
    wire in_ready;
    reg [31:0] in_a = 0, in_b = 0, in_c = 0;
    reg [15:0] in_tag = 0;
    reg in_last = 0;
    wire out_valid;
    reg out_ready = 0;
    wire [31:0] out_result;
    wire [15:0] out_tag;
    wire out_last;

    fp32_fma_pipe #(.TAG_WIDTH(16)) dut (
        .clk(clk), .rst_n(rst_n), .flush(flush),
        .in_valid(in_valid), .in_ready(in_ready),
        .in_a(in_a), .in_b(in_b), .in_c(in_c), .in_tag(in_tag), .in_last(in_last),
        .out_valid(out_valid), .out_ready(out_ready),
        .out_result(out_result), .out_tag(out_tag), .out_last(out_last)
    );

    integer errors = 0;
    integer cyc = 0;
    integer accepts = 0, xfers = 0;
    integer i;
    integer in_cyc;
    reg [31:0] exp_val;
    reg [15:0] exp_tag;

    always @(posedge clk) if (rst_n) cyc <= cyc + 1;
    always @(posedge clk) if (rst_n && in_valid && in_ready) accepts <= accepts + 1;
    always @(posedge clk) if (rst_n && out_valid && out_ready) xfers <= xfers + 1;

    task fail(input [511:0] msg);
        begin
            errors = errors + 1;
            $display("[FAIL] %0s (cyc=%0d)", msg, cyc);
        end
    endtask

    task do_reset;
        begin
            rst_n = 0; flush = 0; in_valid = 0; out_ready = 0;
            in_a = 0; in_b = 0; in_c = 0; in_tag = 0; in_last = 0;
            repeat (3) @(negedge clk);
            rst_n = 1;
            repeat (2) @(negedge clk);
        end
    endtask

    // one transaction with out_ready=1, check exact latency/data/tag
    task send_check(input [31:0] a, input [31:0] b, input [31:0] c,
                    input [15:0] t, input [31:0] expct, input [511:0] name);
        integer t_out;
        begin
            @(negedge clk);
            in_valid = 1; in_a = a; in_b = b; in_c = c; in_tag = t; in_last = 1;
            out_ready = 1;
            @(posedge clk);
            while (!in_ready) @(posedge clk);
            in_cyc = cyc;
            @(negedge clk);
            in_valid = 0;
            t_out = 0;
            while (!(out_valid && out_ready) && t_out < 100) begin
                @(posedge clk); t_out = t_out + 1;
            end
            if (!(out_valid && out_ready)) begin
                fail(name);
            end else begin
                if (out_result !== expct) begin
                    $display("[FAIL] %0s data got=%08x exp=%08x", name, out_result, expct);
                    errors = errors + 1;
                end
                if (out_tag !== t) begin
                    $display("[FAIL] %0s tag got=%04x exp=%04x", name, out_tag, t);
                    errors = errors + 1;
                end
                if ((cyc - in_cyc) != LAT) begin
                    $display("[FAIL] %0s latency %0d != %0d", name, cyc - in_cyc, LAT);
                    errors = errors + 1;
                end else begin
                    $display("[PASS] %0s latency=%0d data=%08x tag=%04x", name, cyc - in_cyc, out_result, out_tag);
                end
            end
            @(negedge clk);
            out_ready = 0;
        end
    endtask

    initial begin
        // ---------------- A: flush barrier on an empty pipe ----------------
        do_reset;
        accepts = 0;
        flush = 1; in_valid = 1; in_a = 32'h3f800000; in_b = 32'h40000000;
        in_c = 32'h00000000; in_tag = 16'h1111; in_last = 0; out_ready = 1;
        for (i = 0; i < 4; i = i + 1) begin
            @(negedge clk);
            if (in_ready !== 1'b0) begin
                $display("[FAIL] in_ready=%b during flush (cycle %0d)", in_ready, i);
                errors = errors + 1;
            end
            if (out_valid !== 1'b0) begin
                $display("[FAIL] out_valid=%b during flush (cycle %0d)", out_valid, i);
                errors = errors + 1;
            end
            @(posedge clk);
        end
        if (accepts != 0) fail("accepted an input while flush was high");
        else $display("[PASS] flush held 4 cycles: accepts=0, in_ready=0, out_valid=0");
        @(negedge clk); flush = 0; in_valid = 0;

        // ---------------- B: flush cancels a parked output ----------------
        do_reset;
        @(negedge clk);
        in_valid = 1; in_a = 32'h3f800000; in_b = 32'h40000000; in_c = 0;
        in_tag = 16'h2222; in_last = 1; out_ready = 0;
        @(posedge clk);
        while (!in_ready) @(posedge clk);
        @(negedge clk); in_valid = 0;
        repeat (LAT + 2) @(posedge clk);
        if (!out_valid || out_result !== 32'h40000000 || out_tag !== 16'h2222)
            fail("parked output not present before flush");
        else $display("[PASS] parked output present before flush (tag=2222)");
        // assert flush and out_ready in the same cycle: no transfer may occur
        @(negedge clk); flush = 1; out_ready = 1; #1;
        if (out_valid !== 1'b0) begin
            $display("[FAIL] out_valid not cancelled combinationally on flush cycle");
            errors = errors + 1;
        end
        @(posedge clk);
        if (out_valid && out_ready) fail("flush cycle still transferred an output");
        @(negedge clk); flush = 0;
        repeat (3) @(posedge clk);
        if (out_valid) fail("old output survived flush");
        else $display("[PASS] flush cancelled parked output; flush cycle presented no transfer");
        send_check(32'h3f800000, 32'h40400000, 32'h00000000, 16'h2223, 32'h40400000,
                   "post-flush epoch");

        // ---------------- C: reset is a handshake barrier ----------------
        accepts = 0;
        rst_n = 0; flush = 0; in_valid = 1; in_a = 32'h3f800000;
        in_b = 32'h40000000; in_c = 0; in_tag = 16'h3333; out_ready = 1;
        for (i = 0; i < 3; i = i + 1) begin
            @(negedge clk);
            if (in_ready !== 1'b0) begin
                $display("[FAIL] in_ready=%b while rst_n=0 (cycle %0d)", in_ready, i);
                errors = errors + 1;
            end
            if (out_valid !== 1'b0) begin
                $display("[FAIL] out_valid=%b while rst_n=0 (cycle %0d)", out_valid, i);
                errors = errors + 1;
            end
            @(posedge clk);
        end
        if (accepts != 0) fail("accepted an input during reset");
        else $display("[PASS] reset barrier: accepts=0, in_ready=0, out_valid=0");
        @(negedge clk); rst_n = 1; in_valid = 0;
        repeat (2) @(negedge clk);
        send_check(32'h40000000, 32'h40400000, 32'h00000000, 16'h3334, 32'h40c00000,
                   "post-reset epoch");

        // ---------------- D: flush + valid + random ready stress ----------------
        do_reset;
        accepts = 0;
        flush = 1; in_valid = 1; in_a = 32'h3f800000; in_b = 32'h3f800000;
        in_c = 32'h3f800000; in_tag = 16'h4444; out_ready = 1;
        for (i = 0; i < 8; i = i + 1) begin
            @(negedge clk);
            out_ready = i[0];
            if (in_ready !== 1'b0 || out_valid !== 1'b0) begin
                $display("[FAIL] barrier violated at flush cycle %0d", i);
                errors = errors + 1;
            end
            @(posedge clk);
        end
        @(negedge clk); flush = 0; in_valid = 0; out_ready = 1;
        if (accepts != 0) fail("flush stress accepted input");
        else $display("[PASS] 8-cycle flush stress: accepts=0");
        send_check(32'h3f800000, 32'h3f800000, 32'h00000000, 16'h4445, 32'h3f800000,
                   "post-stress epoch");

        $display("CONTRACT_ERRORS=%0d", errors);
        if (errors == 0) $finish;
        else $fatal(1, "contract test failed");
    end

    initial begin
        #200000;
        $display("WATCHDOG: tb_flush_contract timeout");
        $fatal(1, "watchdog");
    end
endmodule
