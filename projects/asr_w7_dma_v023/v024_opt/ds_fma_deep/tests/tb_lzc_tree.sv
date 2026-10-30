`timescale 1ns/1ps
// Exhaustive + random check of the grouped/tree 129-bit leading-one detector
// inside the real fp32_fma_pipe instance (hierarchical combinational probe).
module tb_lzc_tree;
    reg clk = 0, rst_n = 1, flush = 0, in_valid = 0, in_last = 0, out_ready = 1;
    reg [31:0] in_a = 0, in_b = 0, in_c = 0;
    reg [15:0] in_tag = 0;
    wire in_ready, out_valid, out_last;
    wire [31:0] out_result;
    wire [15:0] out_tag;

    fp32_fma_pipe #(.TAG_WIDTH(16)) dut (
        .clk(clk), .rst_n(rst_n), .flush(flush),
        .in_valid(in_valid), .in_ready(in_ready),
        .in_a(in_a), .in_b(in_b), .in_c(in_c),
        .in_tag(in_tag), .in_last(in_last),
        .out_valid(out_valid), .out_ready(out_ready),
        .out_result(out_result), .out_tag(out_tag), .out_last(out_last)
    );

    integer g, w, r, k, errors;
    reg [128:0] v;
    reg [127:0] rnd;

    function [7:0] lin_msb(input [128:0] x);
        integer j;
        begin
            lin_msb = 8'd0;
            for (j = 0; j <= 128; j = j + 1)
                if (x[j]) lin_msb = j[7:0];
        end
    endfunction

    initial begin
        errors = 0;
        #20000000;
        $display("WATCHDOG: tb_lzc_tree timeout");
        $finish(2);
    end

    initial begin
        #1;
        // all-zero
        force dut.s4_sum_acc = 129'd0;
        #1;
        if (dut.comb_msb !== 8'd0) begin
            errors = errors + 1;
            $display("[FAIL] all-zero msb=%0d", dut.comb_msb);
        end

        // one populated 16-bit group at a time, exhaustive word value
        for (g = 0; g < 8; g = g + 1) begin
            for (w = 1; w < 65536; w = w + 1) begin
                force dut.s4_sum_acc = ({113'd0, w[15:0]} << (g * 16));
                #1;
                if (dut.comb_msb !== lin_msb(({113'd0, w[15:0]} << (g * 16)))) begin
                    errors = errors + 1;
                    if (errors < 8)
                        $display("[FAIL] group=%0d w=%04x got=%0d exp=%0d",
                                 g, w, dut.comb_msb, lin_msb(({113'd0, w[15:0]} << (g * 16))));
                end
            end
        end
        // group 8 contains only bit 128
        force dut.s4_sum_acc = (129'd1 << 128);
        #1;
        if (dut.comb_msb !== 8'd128) begin
            errors = errors + 1;
            $display("[FAIL] bit128 got=%0d", dut.comb_msb);
        end

        // random multi-group patterns
        for (r = 0; r < 20000; r = r + 1) begin
            v = {$random, $random, $random, $random, $random};
            force dut.s4_sum_acc = v;
            #1;
            if (dut.comb_msb !== lin_msb(v)) begin
                errors = errors + 1;
                if (errors < 8)
                    $display("[FAIL] random v=%0h got=%0d exp=%0d", v, dut.comb_msb, lin_msb(v));
            end
        end

        // dense patterns: all ones, alternating, two high groups
        force dut.s4_sum_acc = {(129){1'b1}}; #1;
        if (dut.comb_msb !== 8'd128) begin errors = errors + 1; $display("[FAIL] all-ones"); end
        v = {128'h5555_5555_5555_5555_5555_5555_5555_5555, 1'b1};
        force dut.s4_sum_acc = v; #1;
        if (dut.comb_msb !== lin_msb(v)) begin
            errors = errors + 1; $display("[FAIL] alternating");
        end
        force dut.s4_sum_acc = (129'd1 << 127) | (129'd1 << 16); #1;
        if (dut.comb_msb !== 8'd127) begin errors = errors + 1; $display("[FAIL] two-group"); end

        $display("LZC_ERRORS=%0d", errors);
        $finish(errors == 0 ? 0 : 1);
    end
endmodule
