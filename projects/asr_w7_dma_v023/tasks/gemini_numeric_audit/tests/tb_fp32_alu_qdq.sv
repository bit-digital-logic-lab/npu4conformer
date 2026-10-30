`timescale 1ns/1ps

module tb_fp32_alu_qdq;
    reg clk;
    reg rst_n;
    reg in_valid;
    wire in_ready;
    reg [7:0] op;
    reg [31:0] a;
    reg [31:0] b;
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

    always #5 clk = ~clk;

    integer fd_out;

    task do_op(input [7:0] req_op, input [31:0] req_a, input [31:0] req_b);
        begin
            @(posedge clk);
            #1;
            while (!in_ready) begin
                @(posedge clk);
                #1;
            end
            op = req_op;
            a = req_a;
            b = req_b;
            in_valid = 1;

            @(posedge clk);
            #1;
            in_valid = 0;

            while (!out_valid) begin
                @(posedge clk);
                #1;
            end

            $fdisplay(fd_out, "OP %0d A %08h B %08h RES %08h FLAGS %02h",
                req_op, req_a, req_b, result, flags);

            @(posedge clk);
            #1;
        end
    endtask

    initial begin
        clk = 0;
        rst_n = 0;
        in_valid = 0;
        op = 0;
        a = 0;
        b = 0;
        out_ready = 1;

        #20;
        rst_n = 1;
        #10;

        fd_out = $fopen("logs/sim_fp32_qdq.txt", "w");

        // Test I48_F32 (OP 14): {b[15:0], a[31:0]}
        // Case 1: 0
        do_op(14, 32'h0, 32'h0);
        // Case 2: +1
        do_op(14, 32'h1, 32'h0);
        // Case 3: -1 (48'hffffffffffff)
        do_op(14, 32'hffffffff, 32'hffff);
        // Case 4: Max positive 48-bit (48'h7fffffffffff)
        do_op(14, 32'hffffffff, 32'h7fff);
        // Case 5: Max negative 48-bit (48'h800000000000)
        do_op(14, 32'h00000000, 32'h8000);
        // Case 6: Precision truncation with sticky (e.g. 2^30 + 1)
        do_op(14, 32'h40000001, 32'h0000);

        // Test F32_I16 (OP 15):
        // Case 1: 0.0 (32'h00000000) -> 0
        do_op(15, 32'h00000000, 32'h0);
        // Case 2: +1.0 (32'h3f800000) -> 1
        do_op(15, 32'h3f800000, 32'h0);
        // Case 3: -1.0 (32'hbf800000) -> -1 (32'hffffffff or 32'hffff8000.. let's check sign-extension)
        do_op(15, 32'hbf800000, 32'h0);
        // Case 4: +32767.0 (32'h46fffe00) -> 32767 (0x00007fff)
        do_op(15, 32'h46fffe00, 32'h0);
        // Case 5: Saturation positive: +40000.0 (32'h471c4000) -> 32767 (0x00007fff)
        do_op(15, 32'h471c4000, 32'h0);
        // Case 6: Saturation negative: -50000.0 (32'hc7435000) -> -32768 (0xffff8000)
        do_op(15, 32'hc7435000, 32'h0);
        // Case 7: Banker's rounding: 1.5 (32'h3fc00000) -> 2
        do_op(15, 32'h3fc00000, 32'h0);
        // Case 8: Banker's rounding: 2.5 (32'h40200000) -> 2
        do_op(15, 32'h40200000, 32'h0);
        // Case 9: Banker's rounding: 3.5 (32'h40600000) -> 4
        do_op(15, 32'h40600000, 32'h0);

        // Test FTZ on Subnormal Input (e.g. in ADD op 0):
        // Small subnormal: 32'h00000001 (denormal)
        // Adding 0.0 to denormal -> should result in 0.0 and flag[3] (FTZ) set!
        do_op(0, 32'h00000001, 32'h00000000);
        // Negative subnormal: 32'h80000001
        do_op(0, 32'h80000001, 32'h00000000);

        $fclose(fd_out);
        $display("tb_fp32_alu_qdq completed!");
        $finish;
    end

endmodule
