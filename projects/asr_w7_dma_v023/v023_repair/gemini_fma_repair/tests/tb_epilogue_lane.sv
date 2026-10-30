`timescale 1ns/1ps

module tb_epilogue_lane;

    reg clk;
    reg rst_n;
    reg flush;

    reg [1:0]  cfg_fma_mode;
    reg        cfg_relu_en;
    reg [31:0] cfg_scale;
    reg [31:0] cfg_bias;

    reg               in_valid;
    wire              in_ready;
    reg signed [47:0] in_c48;
    reg [15:0]        in_tag;
    reg               in_last;

    wire              out_valid;
    reg               out_ready;
    wire signed [15:0] out_a16;
    wire [15:0]       out_tag;
    wire              out_last;

    wire              fp32_valid;
    wire [31:0]       fp32_data;

    epilogue_lane #(
        .TAG_WIDTH(16)
    ) dut (
        .clk          (clk),
        .rst_n        (rst_n),
        .flush        (flush),
        .cfg_fma_mode (cfg_fma_mode),
        .cfg_relu_en  (cfg_relu_en),
        .cfg_scale    (cfg_scale),
        .cfg_bias     (cfg_bias),
        .in_valid     (in_valid),
        .in_ready     (in_ready),
        .in_c48       (in_c48),
        .in_tag       (in_tag),
        .in_last      (in_last),
        .out_valid    (out_valid),
        .out_ready    (out_ready),
        .out_a16      (out_a16),
        .out_tag      (out_tag),
        .out_last     (out_last),
        .fp32_valid   (fp32_valid),
        .fp32_data    (fp32_data)
    );

    always #5 clk = ~clk;

    // Watchdog: 200us
    initial begin
        #200000;
        $display("[WATCHDOG] FATAL: tb_epilogue_lane timed out!");
        $finish(2);
    end

    integer err_count = 0;
    integer pass_count = 0;

    task send_c48_check_a16(
        input signed [47:0] c48_val,
        input [15:0] tag,
        input last,
        input signed [15:0] exp_a16,
        input [127:0] name
    );
        reg done;
        integer timeout;
        begin
            @(posedge clk);
            while (!in_ready) @(posedge clk);
            in_valid <= 1'b1;
            in_c48   <= c48_val;
            in_tag   <= tag;
            in_last  <= last;
            @(posedge clk);
            in_valid <= 1'b0;

            done = 0;
            timeout = 0;
            while (!done && timeout < 50) begin
                if (out_valid && out_ready) begin
                    if (out_a16 !== exp_a16) begin
                        $display("[FAIL] %0s: got %0d (0x%04h), expected %0d (0x%04h)",
                                 name, out_a16, out_a16, exp_a16, exp_a16);
                        err_count = err_count + 1;
                    end else if (out_tag !== tag || out_last !== last) begin
                        $display("[FAIL] %0s: tag/last mismatch got tag=%h last=%b exp tag=%h last=%b",
                                 name, out_tag, out_last, tag, last);
                        err_count = err_count + 1;
                    end else begin
                        $display("[PASS] %0s: got %0d (tag=%04h, last=%b)", name, out_a16, out_tag, out_last);
                        pass_count = pass_count + 1;
                    end
                    done = 1;
                end
                @(posedge clk);
                timeout = timeout + 1;
            end
            if (!done) begin
                $display("[FAIL] %0s: response timed out!", name);
                err_count = err_count + 1;
            end
        end
    endtask

    initial begin
        clk = 0;
        rst_n = 0;
        flush = 0;
        cfg_fma_mode = 2'd0;
        cfg_relu_en = 1'b0;
        cfg_scale = 32'h3f800000;
        cfg_bias = 32'h00000000;
        in_valid = 0;
        in_c48 = 0;
        in_tag = 0;
        in_last = 0;
        out_ready = 1;

        #20;
        @(posedge clk);
        rst_n = 1;
        #20;
        @(posedge clk);

        $display("=== STARTING EPILOGUE LANE TESTS ===");

        // Test 1: MODE_CONV_ONLY (Bypass FMA, no ReLU)
        // c48 = 100 -> f32 = 100.0 -> fma bypass -> i16 = 100
        cfg_fma_mode = 2'd0;
        cfg_relu_en = 1'b0;
        send_c48_check_a16(48'sd100, 16'ha001, 1'b0, 16'sd100, "mode0_c100");
        send_c48_check_a16(-48'sd50, 16'ha002, 1'b1, -16'sd50, "mode0_neg50");

        // Test 2: MODE_SCALE_ONLY (mode=2, scale=0.5 (0x3f000000))
        // c48 = 100 -> f32 = 100.0 * 0.5 = 50.0 -> i16 = 50
        cfg_fma_mode = 2'd2;
        cfg_scale = 32'h3f000000; // 0.5
        send_c48_check_a16(48'sd100, 16'ha003, 1'b0, 16'sd50, "mode2_scale_half");
        send_c48_check_a16(-48'sd80, 16'ha004, 1'b1, -16'sd40, "mode2_scale_neg");

        // Test 3: MODE_SCALE_BIAS (mode=1, scale=0.25 (0x3e800000), bias=15.0 (0x41700000))
        // c48 = 100 -> f32 = 100 * 0.25 + 15 = 40.0 -> i16 = 40
        cfg_fma_mode = 2'd1;
        cfg_scale = 32'h3e800000; // 0.25
        cfg_bias  = 32'h41700000; // 15.0
        send_c48_check_a16(48'sd100, 16'ha005, 1'b0, 16'sd40, "mode1_scale_bias");

        // Test 4: ReLU activation (cfg_relu_en = 1)
        // With bias = -30.0 (0xc1f00000): 100 * 0.25 - 30 = -5.0 -> ReLU -> 0
        cfg_bias = 32'hc1f00000; // -30.0
        cfg_relu_en = 1'b1;
        send_c48_check_a16(48'sd100, 16'ha006, 1'b0, 16'sd0, "relu_clamped_zero");
        // c48 = 200: 200 * 0.25 - 30 = 20.0 -> ReLU -> 20
        send_c48_check_a16(48'sd200, 16'ha007, 1'b1, 16'sd20, "relu_positive_pass");

        // Test 5: Saturation clamp to [-32768, 32767]
        cfg_relu_en = 1'b0;
        cfg_fma_mode = 2'd0;
        // Large positive C48: 100,000 -> saturated to 32767
        send_c48_check_a16(48'sd100000, 16'ha008, 1'b0, 16'sd32767, "clamp_max_positive");
        // Large negative C48: -100,000 -> saturated to -32768
        send_c48_check_a16(-48'sd100000, 16'ha009, 1'b1, -16'sd32768, "clamp_min_negative");

        // Test 6: Flush / Abort in middle of burst
        @(posedge clk);
        in_valid <= 1'b1;
        in_c48 <= 48'sd999;
        in_tag <= 16'hdead;
        @(posedge clk);
        flush <= 1'b1;
        in_valid <= 1'b0;
        @(posedge clk);
        flush <= 1'b0;
        repeat (15) @(posedge clk);
        if (out_valid) begin
            $display("[FAIL] flush_test: out_valid asserted after flush!");
            err_count = err_count + 1;
        end else begin
            $display("[PASS] flush_test: pipeline successfully cleared");
            pass_count = pass_count + 1;
        end

        // Test 7: Backpressure stall recovery
        out_ready <= 1'b0;
        @(posedge clk);
        in_valid <= 1'b1;
        in_c48 <= 48'sd77;
        in_tag <= 16'hb001;
        in_last <= 1'b1;
        @(posedge clk);
        in_valid <= 1'b0;

        repeat (20) @(posedge clk);
        if (!out_valid) begin
            $display("[FAIL] backpressure_stall: out_valid did not assert!");
            err_count = err_count + 1;
        end else begin
            out_ready <= 1'b1;
            @(posedge clk);
            if (out_a16 === 16'sd77 && out_tag === 16'hb001 && out_last === 1'b1) begin
                $display("[PASS] backpressure_stall: received correctly after backpressure stall");
                pass_count = pass_count + 1;
            end else begin
                $display("[FAIL] backpressure_stall: incorrect data got %0d tag=%h last=%b",
                         out_a16, out_tag, out_last);
                err_count = err_count + 1;
            end
        end

        $display("=== LANE SUMMARY: %0d passed, %0d failed ===", pass_count, err_count);
        if (err_count == 0) begin
            $display("ALL EPILOGUE LANE TESTS PASSED");
            $finish(0);
        end else begin
            $display("EPILOGUE LANE TESTS FAILED!");
            $finish(1);
        end
    end

endmodule
