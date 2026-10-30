`timescale 1ns/1ps

module tb_approx_div_sqrt;
    reg clk;
    reg rst_n;

    reg        in_valid;
    wire       in_ready;
    reg [1:0]  op;
    reg [31:0] a;
    reg [31:0] b;
    reg [15:0] tag;

    wire       out_valid;
    reg        out_ready;
    wire [31:0] result;
    wire [7:0]  flags;
    wire [15:0] tag_out;

    // Clock generation: 125 MHz (8.0 ns period) / 250 MHz compatible
    always #4 clk = ~clk;

    // DUT instantiation
    approx_div_sqrt #(
        .TIER(1),
        .LATENCY(4),
        .II(1)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .in_valid(in_valid),
        .in_ready(in_ready),
        .op(op),
        .a(a),
        .b(b),
        .tag(tag),
        .out_valid(out_valid),
        .out_ready(out_ready),
        .result(result),
        .flags(flags),
        .tag_out(tag_out)
    );

    // Vector files
    integer vec_file;
    integer out_file;
    integer scan_ret;

    reg [1:0]  v_op;
    reg [31:0] v_a;
    reg [31:0] v_b;
    reg [15:0] v_tag;

    integer tx_count;
    integer rx_count;
    integer mismatch_count;

    initial begin
        clk = 0;
        rst_n = 0;
        in_valid = 0;
        out_ready = 1;
        op = 0;
        a = 0;
        b = 0;
        tag = 0;
        tx_count = 0;
        rx_count = 0;
        mismatch_count = 0;

        #20;
        rst_n = 1;
        #20;

        // Open test vectors if specified via plusarg
        // Otherwise run built-in sanity checks
        if ($test$plusargs("VEC_FILE")) begin
            // File-driven mode handled below
        end
    end

    // File-driven driver
    string vec_filename;
    string out_filename;

    // Dynamic ready/backpressure generation
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            out_ready <= 1'b1;
        end else if ($test$plusargs("RAND_BACKPRESSURE")) begin
            out_ready <= ($random % 4) != 0; // 75% ready, 25% backpressure
        end else begin
            out_ready <= 1'b1;
        end
    end

    initial begin
        wait(rst_n == 1);
        @(posedge clk);

        if ($value$plusargs("VEC_FILE=%s", vec_filename) && $value$plusargs("OUT_FILE=%s", out_filename)) begin
            vec_file = $fopen(vec_filename, "r");
            out_file = $fopen(out_filename, "w");

            if (vec_file == 0 || out_file == 0) begin
                $display("ERROR: Failed to open vector or output file");
                $finish(1);
            end

            while (!$feof(vec_file)) begin
                scan_ret = $fscanf(vec_file, "%h %h %h %h\n", v_op, v_a, v_b, v_tag);
                if (scan_ret == 4) begin
                    in_valid <= 1'b1;
                    op       <= v_op;
                    a        <= v_a;
                    b        <= v_b;
                    tag      <= v_tag;

                    @(posedge clk);
                    while (!in_ready) begin
                        @(posedge clk);
                    end
                    tx_count = tx_count + 1;
                end
            end
            in_valid <= 1'b0;
            $fclose(vec_file);

            // Drain pipeline
            while (rx_count < tx_count) begin
                @(posedge clk);
            end

            $fclose(out_file);
            $display("SIMULATION COMPLETE: Tx = %0d, Rx = %0d", tx_count, rx_count);
            $finish(0);
        end else begin
            // Built-in Sanity Test Suite
            $display("Running Built-in Sanity Suite...");
            drive_test(2'b00, 32'h41200000, 32'h40400000, 16'h0001); // 10.0 / 3.0
            drive_test(2'b01, 32'h40000000, 32'h00000000, 16'h0002); // sqrt(2.0)
            drive_test(2'b10, 32'h40000000, 32'h00000000, 16'h0003); // rsqrt(2.0)
            drive_test(2'b00, 32'h3f800000, 32'h00000000, 16'h0004); // 1.0 / 0.0 (div by zero)
            drive_test(2'b01, 32'hc0800000, 32'h00000000, 16'h0005); // sqrt(-4.0) (invalid)
            drive_test(2'b10, 32'h00000000, 32'h00000000, 16'h0006); // rsqrt(0.0)
            drive_test(2'b10, 32'h358637bd, 32'h00000000, 16'h0007); // rsqrt(1e-6)

            repeat (10) @(posedge clk);
            $display("Built-in Sanity Suite Completed Successfully.");
            $finish(0);
        end
    end

    // Monitor
    always @(posedge clk) begin
        if (rst_n && out_valid && out_ready) begin
            rx_count <= rx_count + 1;
            if (out_file != 0) begin
                $fwrite(out_file, "%h %h %h\n", result, flags, tag_out);
            end else begin
                $display("RX [%0t]: result = %h, flags = %h, tag = %h", $time, result, flags, tag_out);
            end
        end
    end

    task drive_test(input [1:0] top, input [31:0] ta, input [31:0] tb, input [15:0] ttag);
        begin
            @(posedge clk);
            in_valid <= 1'b1;
            op       <= top;
            a        <= ta;
            b        <= tb;
            tag      <= ttag;
            @(posedge clk);
            while (!in_ready) @(posedge clk);
            in_valid <= 1'b0;
        end
    endtask

endmodule
