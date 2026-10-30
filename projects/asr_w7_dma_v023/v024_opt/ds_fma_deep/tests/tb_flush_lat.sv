`timescale 1ns/1ps
// Unit-level flush / error-drain audit for the epilogue leaf modules.
// out_ready is held low so a result parks in the output register; flush must
// clear it.  A post-flush transaction must still work.
module tb_flush;
    reg clk, rst_n, flush;
    integer errors;

    reg i48_in_valid; wire i48_in_ready; reg signed [47:0] i48_in_data;
    reg [15:0] i48_in_tag; reg i48_in_last; wire i48_out_valid;
    reg i48_out_ready; wire [31:0] i48_out_data; wire [15:0] i48_out_tag;
    wire i48_out_last;

    reg fma_in_valid; wire fma_in_ready; reg [31:0] fma_in_data;
    reg [15:0] fma_in_tag; reg fma_in_last; reg [1:0] fma_mode;
    reg [31:0] fma_scale, fma_bias; wire fma_out_valid; reg fma_out_ready;
    wire [31:0] fma_out_data; wire [15:0] fma_out_tag; wire fma_out_last;

    reg i16_in_valid; wire i16_in_ready; reg [31:0] i16_in_data;
    reg [15:0] i16_in_tag; reg i16_in_last; wire i16_out_valid;
    reg i16_out_ready; wire signed [15:0] i16_out_data;
    wire [15:0] i16_out_tag; wire i16_out_last;

    reg lane_in_valid; wire lane_in_ready; reg signed [47:0] lane_in_c48;
    reg [15:0] lane_in_tag; reg lane_in_last; reg [1:0] lane_mode;
    reg lane_relu; reg [31:0] lane_scale, lane_bias; wire lane_out_valid;
    reg lane_out_ready; wire signed [15:0] lane_out_a16; wire [15:0] lane_out_tag;
    wire lane_out_last;

    always #4 clk = ~clk;

    epilogue_i48_to_f32 u_i48 (
        .clk(clk), .rst_n(rst_n), .flush(flush),
        .in_valid(i48_in_valid), .in_ready(i48_in_ready), .in_data(i48_in_data),
        .in_tag(i48_in_tag), .in_last(i48_in_last),
        .out_valid(i48_out_valid), .out_ready(i48_out_ready),
        .out_data(i48_out_data), .out_tag(i48_out_tag), .out_last(i48_out_last));

    epilogue_fma_stage u_fma (
        .clk(clk), .rst_n(rst_n), .flush(flush), .mode(fma_mode),
        .scale(fma_scale), .bias(fma_bias),
        .in_valid(fma_in_valid), .in_ready(fma_in_ready), .in_data(fma_in_data),
        .in_tag(fma_in_tag), .in_last(fma_in_last),
        .out_valid(fma_out_valid), .out_ready(fma_out_ready),
        .out_data(fma_out_data), .out_tag(fma_out_tag), .out_last(fma_out_last));

    epilogue_f32_to_i16 u_i16 (
        .clk(clk), .rst_n(rst_n), .flush(flush),
        .in_valid(i16_in_valid), .in_ready(i16_in_ready), .in_data(i16_in_data),
        .in_tag(i16_in_tag), .in_last(i16_in_last),
        .out_valid(i16_out_valid), .out_ready(i16_out_ready),
        .out_data(i16_out_data), .out_tag(i16_out_tag), .out_last(i16_out_last));

    epilogue_lane u_lane (
        .clk(clk), .rst_n(rst_n), .flush(flush),
        .cfg_fma_mode(lane_mode), .cfg_relu_en(lane_relu),
        .cfg_scale(lane_scale), .cfg_bias(lane_bias),
        .in_valid(lane_in_valid), .in_ready(lane_in_ready), .in_c48(lane_in_c48),
        .in_tag(lane_in_tag), .in_last(lane_in_last),
        .out_valid(lane_out_valid), .out_ready(lane_out_ready),
        .out_a16(lane_out_a16), .out_tag(lane_out_tag), .out_last(lane_out_last),
        .fp32_valid(), .fp32_data());

    task check(input cond, input [255:0] msg);
        begin
            if (!cond) begin
                errors = errors + 1;
                $display("FLUSH_FAIL: %0s", msg);
            end
        end
    endtask

    initial begin
        clk = 0; rst_n = 0; flush = 0; errors = 0;
        i48_in_valid = 0; i48_in_data = 0; i48_in_tag = 0; i48_in_last = 0; i48_out_ready = 0;
        fma_in_valid = 0; fma_in_data = 0; fma_in_tag = 0; fma_in_last = 0; fma_out_ready = 0;
        fma_mode = 1; fma_scale = 32'h3fc00000; fma_bias = 0;
        i16_in_valid = 0; i16_in_data = 0; i16_in_tag = 0; i16_in_last = 0; i16_out_ready = 0;
        lane_in_valid = 0; lane_in_c48 = 0; lane_in_tag = 0; lane_in_last = 0; lane_out_ready = 0;
        lane_mode = 0; lane_relu = 0; lane_scale = 32'h3f800000; lane_bias = 0;
        #20; rst_n = 1; @(negedge clk);

        // ---------------- i48
        @(negedge clk); i48_in_valid = 1; i48_in_data = 48'd1; i48_in_tag = 16'h1111;
        @(posedge clk); @(negedge clk); i48_in_valid = 0;
        repeat (3) @(posedge clk);
        check(i48_out_valid && i48_out_data == 32'h3f800000, "i48 pre-flush result wrong");
        @(negedge clk); flush = 1;
        @(posedge clk); @(negedge clk); flush = 0;
        repeat (4) @(posedge clk);
        check(!i48_out_valid, "i48 out_valid survived flush");
        @(negedge clk); i48_in_valid = 1; i48_in_data = 48'd2; i48_in_tag = 16'h2222;
        @(posedge clk); @(negedge clk); i48_in_valid = 0;
        repeat (3) @(posedge clk);
        check(i48_out_valid && i48_out_data == 32'h40000000, "i48 post-flush result wrong");
        @(negedge clk); i48_out_ready = 1; @(posedge clk); @(negedge clk); i48_out_ready = 0;

        // ---------------- FMA
        @(negedge clk); fma_in_valid = 1; fma_in_data = 32'h3f800000; fma_in_tag = 16'h3333;
        @(posedge clk); @(negedge clk); fma_in_valid = 0;
        repeat (10) @(posedge clk);   // FMA latency adapted to 7 stages
        check(fma_out_valid && fma_out_data == 32'h3fc00000, "fma pre-flush result wrong");
        @(negedge clk); flush = 1;
        @(posedge clk); @(negedge clk); flush = 0;
        repeat (4) @(posedge clk);
        check(!fma_out_valid, "fma out_valid survived flush");
        @(negedge clk); fma_in_valid = 1; fma_in_data = 32'h40000000; fma_in_tag = 16'h4444;
        @(posedge clk); @(negedge clk); fma_in_valid = 0;
        repeat (10) @(posedge clk);   // FMA latency adapted to 7 stages
        check(fma_out_valid && fma_out_data == 32'h40400000, "fma post-flush result wrong");
        @(negedge clk); fma_out_ready = 1; @(posedge clk); @(negedge clk); fma_out_ready = 0;

        // ---------------- f32 -> i16
        @(negedge clk); i16_in_valid = 1; i16_in_data = 32'h3fc00000; i16_in_tag = 16'h5555;
        @(posedge clk); @(negedge clk); i16_in_valid = 0;
        repeat (2) @(posedge clk);
        check(i16_out_valid && i16_out_data == 16'sd2, "i16 pre-flush result wrong");
        @(negedge clk); flush = 1;
        @(posedge clk); @(negedge clk); flush = 0;
        repeat (4) @(posedge clk);
        check(!i16_out_valid, "i16 out_valid survived flush");
        @(negedge clk); i16_in_valid = 1; i16_in_data = 32'h40200000; i16_in_tag = 16'h6666;
        @(posedge clk); @(negedge clk); i16_in_valid = 0;
        repeat (2) @(posedge clk);
        check(i16_out_valid && i16_out_data == 16'sd2, "i16 post-flush result wrong");
        @(negedge clk); i16_out_ready = 1; @(posedge clk); @(negedge clk); i16_out_ready = 0;

        // ---------------- lane (conversion-only)
        @(negedge clk); lane_in_valid = 1; lane_in_c48 = 48'd1; lane_in_tag = 16'h7777;
        @(posedge clk); @(negedge clk); lane_in_valid = 0;
        repeat (16) @(posedge clk);   // lane latency now 2+7+1+2 = 12
        check(lane_out_valid && lane_out_a16 == 16'sd1, "lane pre-flush result wrong");
        @(negedge clk); flush = 1;
        @(posedge clk); @(negedge clk); flush = 0;
        repeat (4) @(posedge clk);
        check(!lane_out_valid, "lane out_valid survived flush");
        @(negedge clk); lane_in_valid = 1; lane_in_c48 = 48'd2; lane_in_tag = 16'h8888;
        @(posedge clk); @(negedge clk); lane_in_valid = 0;
        repeat (16) @(posedge clk);   // lane latency now 2+7+1+2 = 12
        check(lane_out_valid && lane_out_a16 == 16'sd2, "lane post-flush result wrong");

        $display("FLUSH_ERRORS=%0d", errors);
        $finish(errors == 0 ? 0 : 2);
    end
endmodule
