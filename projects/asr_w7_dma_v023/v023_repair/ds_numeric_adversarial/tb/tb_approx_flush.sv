`timescale 1ns/1ps
// Flush / latency audit for the repaired approx_div_sqrt (TIER=1, LATENCY=5).
module tb_approx_flush;
    reg clk, rst_n, flush;
    reg in_valid;
    wire in_ready;
    reg [1:0] op;
    reg [31:0] a, b;
    reg [15:0] tag;
    wire out_valid;
    reg out_ready;
    wire [31:0] result;
    wire [7:0] flags;
    wire [15:0] tag_out;
    integer errors;
    integer i;

    always #4 clk = ~clk;

    approx_div_sqrt #(.TIER(1), .LATENCY(5), .II(1)) dut (
        .clk(clk), .rst_n(rst_n), .flush(flush),
        .in_valid(in_valid), .in_ready(in_ready), .op(op), .a(a), .b(b),
        .tag(tag),
        .out_valid(out_valid), .out_ready(out_ready), .result(result),
        .flags(flags), .tag_out(tag_out));

    task check(input cond, input [255:0] msg);
        begin
            if (!cond) begin
                errors = errors + 1;
                $display("APPROX_FLUSH_FAIL: %0s", msg);
            end
        end
    endtask

    initial begin
        clk = 0; rst_n = 0; flush = 0; in_valid = 0; op = 0; a = 0; b = 0;
        tag = 0; out_ready = 0; errors = 0;
        #20; rst_n = 1; @(negedge clk);

        // Fill 3 entries, then flush them all.
        @(negedge clk);
        in_valid = 1;
        op = 0; a = 32'h41200000; b = 32'h40400000; tag = 16'h1001;
        @(posedge clk);
        op = 0; a = 32'h40000000; b = 32'h40400000; tag = 16'h1002;
        @(posedge clk);
        op = 1; a = 32'h40800000; b = 0; tag = 16'h1003;
        @(posedge clk);
        @(negedge clk); in_valid = 0;
        @(negedge clk); flush = 1;
        @(posedge clk); @(negedge clk); flush = 0;
        repeat (6) @(posedge clk);
        check(!out_valid, "out_valid survived flush");

        // Post-flush request: check exact 5-cycle latency and tag/result.
        @(negedge clk);
        in_valid = 1; op = 0; a = 32'h41200000; b = 32'h40400000; tag = 16'h2001;
        @(posedge clk);
        @(negedge clk); in_valid = 0;
        for (i = 0; i < 4; i = i + 1) begin
            @(posedge clk);
            check(!out_valid, "out_valid asserted before 5-cycle latency");
        end
        @(posedge clk);
        check(out_valid, "out_valid missing at 5-cycle latency");
        check(tag_out == 16'h2001, "post-flush tag mismatch");
        // 10/3 ~= 3.33333325; only require a plausible finite result.
        check(result[30:23] != 8'hff && result[30:23] != 8'h00, "post-flush result not finite normal");

        $display("APPROX_FLUSH_ERRORS=%0d", errors);
        $finish(errors == 0 ? 0 : 2);
    end
endmodule
