`timescale 1ns/1ps

module tb_fp32_fma_pipe;

    reg clk;
    reg rst_n;
    reg flush;

    reg         in_valid;
    wire        in_ready;
    reg  [31:0] in_a;
    reg  [31:0] in_b;
    reg  [31:0] in_c;
    reg  [15:0] in_tag;
    reg         in_last;

    wire        out_valid;
    reg         out_ready;
    wire [31:0] out_result;
    wire [15:0] out_tag;
    wire        out_last;

    // Instantiate DUT
    fp32_fma_pipe #(
        .TAG_WIDTH(16)
    ) dut (
        .clk        (clk),
        .rst_n      (rst_n),
        .flush      (flush),
        .in_valid   (in_valid),
        .in_ready   (in_ready),
        .in_a       (in_a),
        .in_b       (in_b),
        .in_c       (in_c),
        .in_tag     (in_tag),
        .in_last    (in_last),
        .out_valid  (out_valid),
        .out_ready  (out_ready),
        .out_result (out_result),
        .out_tag    (out_tag),
        .out_last   (out_last)
    );

    // Clock generator: 100MHz (10ns period)
    always #5 clk = ~clk;

    // Watchdog timer: 100,000ns (100us)
    initial begin
        #100000;
        $display("[WATCHDOG] FATAL: Simulation timed out after 100us!");
        $finish(2);
    end

    integer err_count = 0;
    integer pass_count = 0;

    // Helper task to send one beat and wait for completion
    task send_and_check(
        input [31:0] a,
        input [31:0] b,
        input [31:0] c,
        input [31:0] exp_res,
        input [15:0] tag,
        input        last,
        input [127:0] test_name
    );
        reg done;
        integer wait_cycles;
        begin
            @(posedge clk);
            while (!in_ready) @(posedge clk);
            in_valid <= 1'b1;
            in_a     <= a;
            in_b     <= b;
            in_c     <= c;
            in_tag   <= tag;
            in_last  <= last;
            @(posedge clk);
            in_valid <= 1'b0;

            // Wait for out_valid
            done = 0;
            wait_cycles = 0;
            while (!done && wait_cycles < 20) begin
                if (out_valid && out_ready) begin
                    if (out_result !== exp_res) begin
                        $display("[FAIL] %0s: got 0x%08h, expected 0x%08h", test_name, out_result, exp_res);
                        err_count = err_count + 1;
                    end else if (out_tag !== tag || out_last !== last) begin
                        $display("[FAIL] %0s: metadata mismatch tag=%04h (exp %04h) last=%b (exp %b)",
                                 test_name, out_tag, tag, out_last, last);
                        err_count = err_count + 1;
                    end else begin
                        $display("[PASS] %0s: got 0x%08h == expected 0x%08h", test_name, out_result, exp_res);
                        pass_count = pass_count + 1;
                    end
                    done = 1;
                end
                @(posedge clk);
                wait_cycles = wait_cycles + 1;
            end
            if (!done) begin
                $display("[FAIL] %0s: Pipeline response timed out!", test_name);
                err_count = err_count + 1;
            end
        end
    endtask

    initial begin
        clk       = 0;
        rst_n     = 0;
        flush     = 0;
        in_valid  = 0;
        in_a      = 0;
        in_b      = 0;
        in_c      = 0;
        in_tag    = 0;
        in_last   = 0;
        out_ready = 1;

        #20;
        @(posedge clk);
        rst_n = 1;
        #20;
        @(posedge clk);

        $display("=== TEST START: fp32_fma_pipe Unit Verification ===");

        // 1. Primary Acceptance Probe Counterexample
        // 0x3f800001 * 0x3fc00000 + 0 = 0x3fc00002
        send_and_check(32'h3f800001, 32'h3fc00000, 32'h00000000, 32'h3fc00002, 16'h0001, 1'b0, "probe_mul_round");

        // 2. FMA Cancellation Test (from work/tests/fma_fixture)
        // (1 + 2^-23) * (1 - 2^-23) - 1 = -2^-46
        // 0x3f800001 * 0x3f7ffffe + 0xbf800000 = 0xa8800000
        send_and_check(32'h3f800001, 32'h3f7ffffe, 32'hbf800000, 32'ha8800000, 16'h0002, 1'b1, "cancellation_fma");

        // 3. Round-to-Nearest-Even Tie Breaking
        // Case A: Round down to even (LSB=0)
        // 1.0 * 1.0 + 2^-24 = 0x3f800000 (1.0)
        send_and_check(32'h3f800000, 32'h3f800000, 32'h33800000, 32'h3f800000, 16'h0003, 1'b0, "tie_round_to_even_down");

        // Case B: Round up to even (LSB=1 rounds up to LSB=0)
        // 0x3f800001 * 1.0 + 2^-24 = 0x3f800002
        send_and_check(32'h3f800001, 32'h3f800000, 32'h33800000, 32'h3f800002, 16'h0004, 1'b0, "tie_round_to_even_up");

        // 4. Non-trivial scale and bias
        // x = 2.5 (0x40200000), scale = 1.75 (0x3fe00000), bias = -0.375 (0xbec00000)
        // 2.5 * 1.75 = 4.375; 4.375 - 0.375 = 4.0 (0x40800000)
        send_and_check(32'h40200000, 32'h3fe00000, 32'hbec00000, 32'h40800000, 16'h0005, 1'b0, "scale_bias_exact_4_0");
        // Also test with bias = -0.1875 (0xbe400000) -> 4.1875 (0x40860000)
        send_and_check(32'h40200000, 32'h3fe00000, 32'hbe400000, 32'h40860000, 16'h0006, 1'b0, "scale_bias_exact_4_1875");

        // 5. Zero handling
        send_and_check(32'h00000000, 32'h40200000, 32'h40800000, 32'h40800000, 16'h0006, 1'b0, "zero_a_pass_c");
        send_and_check(32'h40200000, 32'h00000000, 32'h40800000, 32'h40800000, 16'h0007, 1'b0, "zero_b_pass_c");
        send_and_check(32'h40200000, 32'h40000000, 32'h00000000, 32'h40a00000, 16'h0008, 1'b1, "zero_c_mul_only");

        // 6. Inf / NaN handling
        send_and_check(32'h7f800000, 32'h40000000, 32'h00000000, 32'h7f800000, 16'h0009, 1'b0, "inf_mul");
        send_and_check(32'h7fc00000, 32'h40000000, 32'h00000000, 32'h7fc00000, 16'h000a, 1'b0, "nan_propagate");

        // 7. Flush / Abort test
        @(posedge clk);
        in_valid <= 1'b1;
        in_a <= 32'h40200000;
        in_b <= 32'h40000000;
        in_c <= 32'h00000000;
        @(posedge clk);
        flush <= 1'b1;
        in_valid <= 1'b0;
        @(posedge clk);
        flush <= 1'b0;
        // Verify out_valid does not assert
        repeat (10) @(posedge clk);
        if (out_valid) begin
            $display("[FAIL] flush_test: out_valid asserted after flush!");
            err_count = err_count + 1;
        end else begin
            $display("[PASS] flush_test: pipeline cleared properly");
            pass_count = pass_count + 1;
        end

        // 8. Backpressure test
        out_ready <= 1'b0; // backpressure downstream
        @(posedge clk);
        in_valid <= 1'b1;
        in_a <= 32'h40200000; in_b <= 32'h40000000; in_c <= 32'h00000000; // result 5.0 (0x40a00000)
        in_tag <= 16'hbeef; in_last <= 1'b1;
        @(posedge clk);
        in_valid <= 1'b0;
        repeat (10) @(posedge clk);
        if (!out_valid) begin
            $display("[FAIL] backpressure_test: out_valid not held while out_ready=0");
            err_count = err_count + 1;
        end else begin
            out_ready <= 1'b1;
            @(posedge clk);
            if (out_result === 32'h40a00000 && out_tag === 16'hbeef && out_last === 1'b1) begin
                $display("[PASS] backpressure_test: data received correctly after stall");
                pass_count = pass_count + 1;
            end else begin
                $display("[FAIL] backpressure_test: corrupted data after stall got 0x%08h", out_result);
                err_count = err_count + 1;
            end
        end

        $display("=== SUMMARY: passes=%0d, fails=%0d ===", pass_count, err_count);
        if (err_count == 0) begin
            $display("ALL TESTS PASSED SUCCESSFULLY");
            $finish(0);
        end else begin
            $display("TESTS FAILED WITH %0d ERRORS", err_count);
            $finish(1);
        end
    end

endmodule
