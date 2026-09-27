`timescale 1ns/1ps
module tb_asr_i16_mac;
    reg clk = 0;
    always #5 clk = !clk;
    reg rst_n = 0, clear_valid = 0, in_valid = 0, out_ready = 0;
    reg signed [47:0] clear_value = 0;
    reg signed [15:0] in_a = 0, in_b = 0;
    wire clear_ready, in_ready, out_valid, overflow;
    wire signed [47:0] out_sum;
    asr_i16_mac dut(.*);
    reg signed [47:0] expected_sum [0:20000];
    reg expected_overflow [0:20000];
    reg signed [47:0] reference_acc = 0;
    reg reference_overflow = 0;
    reg signed [31:0] reference_product;
    reg signed [48:0] reference_wide;
    integer written = 0, read_count = 0, total_checked = 0;
    reg was_stalled = 0;
    reg signed [47:0] stalled_sum;
    reg stalled_overflow;
    reg [31:0] random_state = 32'h8a537b19;
    integer i;
    always @(posedge clk) begin
        if (!rst_n) begin
            written = 0;
            read_count = 0;
            reference_acc = 0;
            reference_overflow = 0;
            was_stalled = 0;
        end else begin
            if (was_stalled && (!out_valid || out_sum !== stalled_sum || overflow !== stalled_overflow))
                $fatal(1, "MAC output changed under backpressure");
            if (out_valid && out_ready) begin
                if (read_count >= written) $fatal(1, "MAC unexpected output");
                if (out_sum !== expected_sum[read_count] || overflow !== expected_overflow[read_count])
                    $fatal(1, "MAC mismatch at %0d got=%0d overflow=%0b expected=%0d overflow=%0b",
                           read_count, out_sum, overflow, expected_sum[read_count], expected_overflow[read_count]);
                read_count = read_count + 1;
                total_checked = total_checked + 1;
            end
            was_stalled = out_valid && !out_ready;
            stalled_sum = out_sum;
            stalled_overflow = overflow;
            if (clear_valid && clear_ready) begin
                reference_acc = clear_value;
                reference_overflow = 0;
                if (in_ready) $fatal(1, "MAC product ready during priority clear");
            end else if (in_valid && in_ready) begin
                reference_product = in_a * in_b;
                reference_wide = {reference_acc[47], reference_acc} + {{17{reference_product[31]}}, reference_product};
                reference_acc = reference_wide[47:0];
                reference_overflow = reference_overflow || (reference_wide[48] != reference_wide[47]);
                expected_sum[written] = reference_acc;
                expected_overflow[written] = reference_overflow;
                written = written + 1;
            end
        end
    end
    task clear_to(input signed [47:0] value);
        begin
            @(negedge clk);
            clear_value = value;
            clear_valid = 1;
            in_valid = 0;
            out_ready = 1;
            @(posedge clk);
            while (!clear_ready) @(posedge clk);
            @(negedge clk);
            clear_valid = 0;
        end
    endtask
    task product_once(input signed [15:0] a, input signed [15:0] b);
        begin
            @(negedge clk);
            in_a = a;
            in_b = b;
            in_valid = 1;
            @(posedge clk);
            while (!in_ready) @(posedge clk);
            @(negedge clk);
            in_valid = 0;
        end
    endtask
    initial begin
        repeat (3) @(negedge clk);
        rst_n = 1;
        out_ready = 1;
        clear_to(0);
        @(negedge clk);
        in_valid = 1;
        in_a = -16'sd32768;
        in_b = -16'sd32768;
        repeat (9728) @(negedge clk);
        in_valid = 0;
        repeat (2) @(negedge clk);
        if (out_sum !== 48'd10445360463872) $fatal(1, "K=9728 endpoint incorrect");
        clear_to(48'sh7fffffffffff);
        product_once(1, 1);
        product_once(0, 0);
        clear_to(48'sh800000000000);
        product_once(-1, 1);
        clear_to(-48'sd23);
        @(negedge clk);
        out_ready = 0;
        in_valid = 1;
        in_a = -17;
        in_b = 31;
        repeat (5) @(negedge clk);
        clear_valid = 1;
        clear_value = 9;
        repeat (5) @(negedge clk);
        out_ready = 1;
        @(negedge clk);
        clear_valid = 0;
        in_valid = 0;
        product_once(-32768, 32767);
        for (i = 0; i < 1024; i = i + 1) begin
            @(negedge clk);
            random_state = 1664525 * random_state + 1013904223;
            in_valid = random_state[0] || random_state[3];
            out_ready = random_state[5];
            in_a = random_state[31:16];
            in_b = random_state[15:0];
        end
        @(negedge clk);
        in_valid = 0;
        out_ready = 1;
        repeat (3) @(negedge clk);
        if (read_count != written) $fatal(1, "MAC lost output");
        out_ready = 0;
        product_once(123, -456);
        repeat (3) @(negedge clk);
        rst_n = 0;
        repeat (2) @(negedge clk);
        rst_n = 1;
        out_ready = 1;
        product_once(-7, 11);
        repeat (3) @(negedge clk);
        if (out_sum !== -48'sd77 || read_count != written) $fatal(1, "MAC reset failed");
        $display("PASS tb_asr_i16_mac checked=%0d K=9728 limits stalls clear reset", total_checked);
        $finish;
    end
    initial begin #500000; $fatal(1, "MAC timeout"); end
endmodule
