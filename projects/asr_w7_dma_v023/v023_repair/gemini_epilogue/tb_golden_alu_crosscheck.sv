`timescale 1ns/1ps
module tb_golden_alu_crosscheck;
    reg clk;
    reg rst_n;
    reg in_valid;
    wire in_ready;
    reg [7:0] op;
    reg [31:0] a, b;
    wire out_valid;
    reg out_ready;
    wire [31:0] result;
    wire [7:0] flags;

    asr_fp32_alu u_alu (
        .clk(clk),
        .rst_n(rst_n),
        .in_valid(in_valid),
        .in_ready(in_ready),
        .op(op),
        .a(a),
        .b(b),
        .out_valid(out_valid),
        .out_ready(out_ready),
        .result(result),
        .flags(flags)
    );

    initial clk = 0;
    always #5 clk = ~clk;

    task test_i48_f32(input [47:0] val, input [31:0] exp_f32);
        begin
            @(posedge clk);
            while (!in_ready) @(posedge clk);
            in_valid <= 1;
            op <= 8'd14; // I48_F32
            a <= val[31:0];
            b <= {16'd0, val[47:32]};
            @(posedge clk);
            in_valid <= 0;
            out_ready <= 1;
            while (!out_valid) @(posedge clk);
            if (result !== exp_f32) begin
                $display("ERROR I48_F32 mismatch! val=%h, got=%h, exp=%h", val, result, exp_f32);
                $fatal(1);
            end else begin
                $display("PASS I48_F32 val=%h -> %h", val, result);
            end
        end
    endtask

    task test_f32_i16(input [31:0] f32_val, input [15:0] exp_i16);
        begin
            @(posedge clk);
            while (!in_ready) @(posedge clk);
            in_valid <= 1;
            op <= 8'd15; // F32_I16
            a <= f32_val;
            b <= 32'd0;
            @(posedge clk);
            in_valid <= 0;
            out_ready <= 1;
            while (!out_valid) @(posedge clk);
            if (result[15:0] !== exp_i16) begin
                $display("ERROR F32_I16 mismatch! f32=%h, got=%h, exp=%h", f32_val, result[15:0], exp_i16);
                $fatal(1);
            end else begin
                $display("PASS F32_I16 f32=%h -> %h", f32_val, result[15:0]);
            end
        end
    endtask

    initial begin
        rst_n = 0;
        in_valid = 0;
        out_ready = 1;
        #20 rst_n = 1;
        #20;

        // Cross-check test cases from python golden model
        test_i48_f32(48'h000000000000, 32'h00000000);
        test_i48_f32(48'h000000000001, 32'h3f800000);
        test_i48_f32(48'hffffffffffff, 32'hbf800000); // -1
        test_i48_f32(48'h000000007fff, 32'h46fffe00); // 32767
        test_i48_f32(48'hffffffff8000, 32'hc7000000); // -32768
        test_i48_f32(48'h000000010000, 32'h47800000); // 65536
        test_i48_f32(48'hfffffffe0000, 32'hc8000000); // -131072
        test_i48_f32(48'h7fffffffffff, 32'h57000000); // max pos
        test_i48_f32(48'h800000000000, 32'hd7000000); // min neg (-2^47)
        test_i48_f32(48'h0000075bcd15, 32'h4ceb79a3); // +123456789
        test_i48_f32(48'hfffc521974ef, 32'hd06b79a3); // -15802469137

        // F32_I16 tests
        test_f32_i16(32'h00000000, 16'h0000); // 0
        test_f32_i16(32'h3f800000, 16'h0001); // 1.0 -> 1
        test_f32_i16(32'hbf800000, 16'hffff); // -1.0 -> -1
        test_f32_i16(32'h46fffe00, 16'h7fff); // 32767.0 -> 32767
        test_f32_i16(32'hc7000000, 16'h8000); // -32768.0 -> -32768
        test_f32_i16(32'h47800000, 16'h7fff); // 65536.0 -> 32767 (clamped)
        test_f32_i16(32'hc8000000, 16'h8000); // -131072.0 -> -32768 (clamped)
        // Banker's rounding halfway cases:
        // 1.5 (0x3fc00000) -> 2 (even)
        test_f32_i16(32'h3fc00000, 16'h0002);
        // 2.5 (0x40200000) -> 2 (even)
        test_f32_i16(32'h40200000, 16'h0002);
        // 3.5 (0x40600000) -> 4 (even)
        test_f32_i16(32'h40600000, 16'h0004);

        $display("ALL 19 CROSSCHECK TEST CASES PASSED WITH 100%% BIT-EXACT MATCH!");
        $finish;
    end
endmodule
