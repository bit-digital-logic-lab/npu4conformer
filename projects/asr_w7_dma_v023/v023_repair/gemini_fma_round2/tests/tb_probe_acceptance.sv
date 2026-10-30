`timescale 1ns/1ps

module tb_probe_acceptance;

    reg clk = 0;
    always #5 clk = ~clk;

    reg rst_n = 0;
    reg flush = 0;
    reg [1:0] mode = 2'd2; // scale-only
    reg [31:0] scale = 32'h3fc00000;
    reg [31:0] bias = 32'd0;
    reg in_valid = 0;
    reg [31:0] in_data = 32'h3f800001;
    reg [15:0] in_tag = 16'h1234;
    reg in_last = 1'b1;
    reg out_ready = 1'b1;

    wire in_ready;
    wire out_valid;
    wire [31:0] out_data;
    wire [15:0] out_tag;
    wire out_last;

    epilogue_fma_stage dut (
        .clk       (clk),
        .rst_n     (rst_n),
        .flush     (flush),
        .mode      (mode),
        .scale     (scale),
        .bias      (bias),
        .in_valid  (in_valid),
        .in_ready  (in_ready),
        .in_data   (in_data),
        .in_tag    (in_tag),
        .in_last   (in_last),
        .out_valid (out_valid),
        .out_ready (out_ready),
        .out_data  (out_data),
        .out_tag   (out_tag),
        .out_last  (out_last)
    );

    // Watchdog timer: 10,000ns
    initial begin
        #10000;
        $display("[WATCHDOG] FATAL: tb_probe_acceptance timed out!");
        $finish(2);
    end

    initial begin
        // Check 1: Static function call identical to primary_acceptance/tb_fma_probe.sv
        $display("STATIC FUNCTION: MUL got=%h expected=3fc00002", dut.fp32_mul(32'h3f800001, 32'h3fc00000));
        if (dut.fp32_mul(32'h3f800001, 32'h3fc00000) !== 32'h3fc00002) begin
            $display("[FAIL] STATIC FUNCTION: ROUNDING_FAIL");
            $finish(1);
        end else begin
            $display("[PASS] STATIC FUNCTION: ROUNDING_PASS");
        end

        // Check 2: Dynamic pipelined RTL stream
        #20;
        @(posedge clk);
        rst_n = 1'b1;
        #20;
        @(posedge clk);
        in_valid = 1'b1;
        @(posedge clk);
        in_valid = 1'b0;

        while (!out_valid) @(posedge clk);
        $display("PIPELINED STREAM: MUL got=%h expected=3fc00002 tag=%h last=%b", out_data, out_tag, out_last);
        if (out_data !== 32'h3fc00002) begin
            $display("[FAIL] PIPELINED STREAM: ROUNDING_FAIL");
            $finish(1);
        end else begin
            $display("[PASS] PIPELINED STREAM: ROUNDING_PASS");
        end

        $display("PRIMARY ACCEPTANCE PROBE RESOLVED 100%%");
        $finish(0);
    end

endmodule
