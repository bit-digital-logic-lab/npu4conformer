`timescale 1ns/1ps
module tb_asr_requant;
    reg clk = 0;
    always #5 clk = !clk;
    reg rst_n = 0, in_valid = 0, out_ready = 0;
    reg signed [47:0] in_acc = 0, in_bias = 0;
    reg signed [31:0] in_multiplier = 0;
    reg [6:0] in_shift = 0;
    wire in_ready, out_valid;
    wire signed [15:0] out_value;
    asr_requant dut(.*);
    integer tested = 0, i, j;
    reg [31:0] random_state = 32'h1234abcd;
    reg signed [47:0] random_acc, random_bias;
    reg signed [31:0] random_multiplier;
    reg [6:0] random_shift;
    function automatic signed [15:0] reference_value(
        input signed [47:0] acc,
        input signed [31:0] mult,
        input [6:0] shift,
        input signed [47:0] bias
    );
        reg signed [48:0] sum;
        reg signed [80:0] product;
        reg [80:0] magnitude, quotient, remainder, halfway;
        begin
            sum = {acc[47], acc} + {bias[47], bias};
            product = sum * mult;
            magnitude = product[80] ? -product : product;
            if (shift > 81) begin
                quotient = 0;
            end else if (shift == 0) begin
                quotient = magnitude;
            end else begin
                quotient = magnitude >> shift;
                remainder = magnitude - (quotient << shift);
                halfway = 81'd1 << (shift - 1);
                if (remainder > halfway || (remainder == halfway && quotient[0]))
                    quotient = quotient + 1'b1;
            end
            if (product[80]) begin
                reference_value = (quotient >= 32768) ? 16'sh8000 : -$signed(quotient[15:0]);
            end else begin
                reference_value = (quotient > 32767) ? 16'sh7fff : quotient[15:0];
            end
        end
    endfunction
    task run_case(
        input signed [47:0] acc,
        input signed [31:0] mult,
        input [6:0] shift,
        input signed [47:0] bias,
        input integer stall
    );
        reg signed [15:0] expected;
        integer cycles, k;
        begin
            expected = reference_value(acc, mult, shift, bias);
            @(negedge clk);
            while (!in_ready) @(negedge clk);
            in_acc = acc;
            in_multiplier = mult;
            in_shift = shift;
            in_bias = bias;
            in_valid = 1;
            out_ready = 0;
            @(negedge clk);
            in_valid = 0;
            in_acc = 48'sh12ab34567890;
            in_multiplier = -17;
            in_shift = 127;
            in_bias = -6;
            cycles = 0;
            while (!out_valid) begin
                @(negedge clk);
                cycles = cycles + 1;
                if (cycles > 120) $fatal(1, "requant latency exceeded bound");
                if (in_ready) $fatal(1, "requant accepts before result consumed");
            end
            if (out_value !== expected)
                $fatal(1, "requant acc=%0d m=%0d s=%0d bias=%0d got=%0d expected=%0d",
                       acc, mult, shift, bias, out_value, expected);
            if ($test$plusargs("DUMP_VECTORS"))
                $display("REQUANT_VECTOR %0d %0d %0d %0d %0d", acc, mult, shift, bias, out_value);
            for (k = 0; k < stall; k = k + 1) begin
                @(negedge clk);
                if (!out_valid || out_value !== expected || in_ready)
                    $fatal(1, "requant changed under output backpressure");
            end
            out_ready = 1;
            @(negedge clk);
            if (out_valid || !in_ready) $fatal(1, "requant handshake did not release output");
            tested = tested + 1;
        end
    endtask
    initial begin
        repeat (3) @(negedge clk);
        rst_n = 1;
        for (i = -17; i <= 17; i = i + 1) begin
            run_case(i, 1, 1, 0, i & 3);
            run_case(i, -1, 1, 0, 0);
        end
        run_case(32767, 1, 0, 0, 9);
        run_case(32768, 1, 0, 0, 0);
        run_case(-32768, 1, 0, 0, 0);
        run_case(-32769, 1, 0, 0, 0);
        run_case(1, 3, 1, 2, 5);
        run_case(48'sh7fffffffffff, 32'sh80000000, 0, 48'sh7fffffffffff, 0);
        run_case(48'sh800000000000, 32'sh80000000, 79, 48'sh800000000000, 0);
        for (i = 0; i < 128; i = i + 1) begin
            run_case(48'sh800000000000, 32'sh80000000, i, 48'sh800000000000, i % 3);
            run_case(48'sh7fffffffffff, 32'sh7fffffff, i, 48'sh7fffffffffff, 0);
        end
        for (i = 0; i < 200; i = i + 1) begin
            random_state = 1664525 * random_state + 1013904223;
            random_acc[47:16] = random_state;
            random_state = 1664525 * random_state + 1013904223;
            random_acc[15:0] = random_state[31:16];
            random_multiplier = random_state;
            random_state = 1664525 * random_state + 1013904223;
            random_bias = {{16{random_state[31]}}, random_state};
            random_shift = random_state[6:0];
            run_case(random_acc, random_multiplier, random_shift, random_bias, i % 7);
        end
        for (j = 0; j < 2; j = j + 1) begin
            @(negedge clk);
            in_valid = 1;
            in_acc = 123456;
            in_bias = 17;
            in_multiplier = -7654321;
            in_shift = 27;
            out_ready = 0;
            @(negedge clk);
            in_valid = 0;
            if (j == 0) repeat (8) @(negedge clk);
            else while (!out_valid) @(negedge clk);
            rst_n = 0;
            repeat (2) @(negedge clk);
            rst_n = 1;
            @(negedge clk);
            if (!in_ready || out_valid) $fatal(1, "requant reset failed");
            run_case(-5, 1, 1, 0, 2);
        end
        $display("PASS tb_asr_requant cases=%0d ties saturation shift0..127 extrema backpressure reset", tested);
        $finish;
    end
    initial begin #2000000; $fatal(1, "requant timeout"); end
endmodule
