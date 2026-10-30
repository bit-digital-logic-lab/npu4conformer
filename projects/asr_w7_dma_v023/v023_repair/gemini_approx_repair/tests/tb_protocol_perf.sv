`timescale 1ns/1ps

module tb_protocol_perf;
    reg clk;
    reg rst_n;
    reg flush;

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

    // Clock: 100 MHz (10.0 ns period)
    always #5 clk = ~clk;

    // DUT instantiation with strict parameters
    approx_div_sqrt #(
        .TIER(1),
        .LATENCY(5),
        .II(1)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .flush(flush),
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

    // Watchdog timer: 100,000 cycles max (1,000,000 ns)
    initial begin
        #1000000;
        $display("[WATCHDOG TIMEOUT] Simulation exceeded 1,000,000 ns! Terminating with error.");
        $finish(1);
    end

    integer measured_latency;
    integer issue_cycle;
    integer current_cycle;
    integer burst_issued;
    integer burst_received;
    integer i;

    always @(posedge clk) begin
        if (!rst_n) current_cycle <= 0;
        else current_cycle <= current_cycle + 1;
    end

    initial begin
        clk = 0;
        rst_n = 0;
        flush = 0;
        in_valid = 0;
        out_ready = 1;
        op = 0;
        a = 0;
        b = 0;
        tag = 0;
        current_cycle = 0;

        #20;
        rst_n = 1;
        @(posedge clk);

        $display("=== STARTING REAL RTL PROTOCOL & TIMING TESTS ===");

        // =====================================================================
        // Test 1: Exact Hardware Latency Measurement
        // =====================================================================
        $display("[TEST 1] Measuring exact hardware latency for DIV (a / b)...");
        @(posedge clk);
        in_valid <= 1'b1;
        op       <= 2'b00;
        a        <= 32'h41200000; // 10.0
        b        <= 32'h40000000; // 2.0
        tag      <= 16'h1001;
        issue_cycle = current_cycle + 1;
        @(posedge clk);
        in_valid <= 1'b0;

        while (!out_valid) begin
            @(posedge clk);
        end
        measured_latency = current_cycle - issue_cycle;
        $display("  DIV latency measured: %0d cycles (expected 5)", measured_latency);
        if (measured_latency !== 5) begin
            $display("FATAL ERROR: Measured DIV latency %0d != 5!", measured_latency);
            $finish(1);
        end
        if (tag_out !== 16'h1001) begin
            $display("FATAL ERROR: Echoed tag mismatch: %h != 1001", tag_out);
            $finish(1);
        end

        // Latency test for SQRT
        repeat (2) @(posedge clk);
        $display("[TEST 1b] Measuring exact hardware latency for SQRT (sqrt(a))...");
        in_valid <= 1'b1;
        op       <= 2'b01;
        a        <= 32'h40800000; // 4.0
        b        <= 32'h0;
        tag      <= 16'h1002;
        issue_cycle = current_cycle + 1;
        @(posedge clk);
        in_valid <= 1'b0;

        while (!out_valid) begin
            @(posedge clk);
        end
        measured_latency = current_cycle - issue_cycle;
        $display("  SQRT latency measured: %0d cycles (expected 5)", measured_latency);
        if (measured_latency !== 5) begin
            $display("FATAL ERROR: Measured SQRT latency %0d != 5!", measured_latency);
            $finish(1);
        end

        // Latency test for RSQRT
        repeat (2) @(posedge clk);
        $display("[TEST 1c] Measuring exact hardware latency for RSQRT (1 / sqrt(a))...");
        in_valid <= 1'b1;
        op       <= 2'b10;
        a        <= 32'h40800000; // 4.0
        b        <= 32'h0;
        tag      <= 16'h1003;
        issue_cycle = current_cycle + 1;
        @(posedge clk);
        in_valid <= 1'b0;

        while (!out_valid) begin
            @(posedge clk);
        end
        measured_latency = current_cycle - issue_cycle;
        $display("  RSQRT latency measured: %0d cycles (expected 5)", measured_latency);
        if (measured_latency !== 5) begin
            $display("FATAL ERROR: Measured RSQRT latency %0d != 5!", measured_latency);
            $finish(1);
        end

        repeat (5) @(posedge clk);

        // =====================================================================
        // Test 2: Initiation Interval (II = 1) Continuous Back-to-Back Throughput
        // =====================================================================
        $display("[TEST 2] Verifying Initiation Interval II = 1 with 32 back-to-back requests...");
        burst_issued = 0;
        burst_received = 0;
        fork
            begin : send_burst
                for (i = 0; i < 32; i = i + 1) begin
                    @(posedge clk);
                    in_valid <= 1'b1;
                    op       <= (i % 3);
                    a        <= 32'h40000000 + (i << 16);
                    b        <= 32'h3f800000 + (i << 12);
                    tag      <= 16'h2000 + i;
                    burst_issued = burst_issued + 1;
                end
                @(posedge clk);
                in_valid <= 1'b0;
            end
            begin : recv_burst
                integer last_recv_cycle;
                last_recv_cycle = 0;
                while (burst_received < 32) begin
                    @(posedge clk);
                    if (out_valid && out_ready) begin
                        if (burst_received > 0) begin
                            integer cycle_gap;
                            cycle_gap = current_cycle - last_recv_cycle;
                            if (cycle_gap !== 1) begin
                                $display("FATAL ERROR: Pipeline bubble detected! Gap = %0d between results (expected II=1)", cycle_gap);
                                $finish(1);
                            end
                        end
                        last_recv_cycle = current_cycle;
                        burst_received = burst_received + 1;
                    end
                end
            end
        join
        $display("  II=1 Verified: 32 items issued and 32 items received consecutively with 0 bubbles.");

        repeat (5) @(posedge clk);

        // =====================================================================
        // Test 3: Random Backpressure Resilience
        // =====================================================================
        $display("[TEST 3] Stressing pipeline under randomized backpressure (out_ready stalls)...");
        burst_issued = 0;
        burst_received = 0;
        fork
            begin : send_backpressure
                for (i = 0; i < 64; i = i + 1) begin
                    @(posedge clk);
                    while (!in_ready) @(posedge clk);
                    in_valid <= 1'b1;
                    op       <= (i % 3);
                    a        <= 32'h40800000 + i;
                    b        <= 32'h3f800000 + i;
                    tag      <= 16'h3000 + i;
                    burst_issued = burst_issued + 1;
                end
                @(posedge clk);
                while (!in_ready) @(posedge clk);
                in_valid <= 1'b0;
            end
            begin : rand_ready_gen
                while (burst_received < 64) begin
                    @(posedge clk);
                    out_ready <= (($random % 3) != 0); // 33% backpressure stall
                end
                out_ready <= 1'b1;
            end
            begin : verify_backpressure
                reg [15:0] exp_tag;
                exp_tag = 16'h3000;
                while (burst_received < 64) begin
                    @(posedge clk);
                    if (out_valid && out_ready) begin
                        if (tag_out !== exp_tag) begin
                            $display("FATAL ERROR: Tag out-of-order or corrupt under backpressure! Got %h, expected %h", tag_out, exp_tag);
                            $finish(1);
                        end
                        exp_tag = exp_tag + 1;
                        burst_received = burst_received + 1;
                    end
                end
            end
        join
        out_ready <= 1'b1;
        $display("  Random backpressure verified: 64 transactions completed in-order with 100%% tag integrity.");

        repeat (5) @(posedge clk);

        // =====================================================================
        // Test 4: Pipeline Flush Verification
        // =====================================================================
        $display("[TEST 4] Verifying pipeline flush functionality...");
        // Push 3 transactions into the pipeline
        for (i = 0; i < 3; i = i + 1) begin
            @(posedge clk);
            in_valid <= 1'b1;
            op       <= 2'b00;
            a        <= 32'h40000000;
            b        <= 32'h40000000;
            tag      <= 16'h4000 + i;
        end
        @(posedge clk);
        in_valid <= 1'b0;
        // Assert flush immediately
        flush <= 1'b1;
        @(posedge clk);
        flush <= 1'b0;

        // Monitor for 10 cycles: no flushed transaction should emerge
        for (i = 0; i < 10; i = i + 1) begin
            @(posedge clk);
            if (out_valid) begin
                $display("FATAL ERROR: Pipeline emitted data after flush asserted! tag_out = %h", tag_out);
                $finish(1);
            end
        end
        $display("  Pipeline flush verified: in-flight transactions cleanly discarded.");

        // Issue a clean new transaction after flush to confirm recovery
        @(posedge clk);
        in_valid <= 1'b1;
        op       <= 2'b00;
        a        <= 32'h41200000; // 10.0
        b        <= 32'h40000000; // 2.0
        tag      <= 16'h40ff;
        issue_cycle = current_cycle + 1;
        @(posedge clk);
        in_valid <= 1'b0;

        while (!out_valid) begin
            @(posedge clk);
        end
        if (tag_out !== 16'h40ff || (current_cycle - issue_cycle !== 5)) begin
            $display("FATAL ERROR: Post-flush transaction failed! tag=%h, latency=%0d", tag_out, current_cycle - issue_cycle);
            $finish(1);
        end
        $display("  Post-flush recovery verified: new transaction completed with exact 5-cycle latency.");

        repeat (5) @(posedge clk);
        $display("=== ALL PROTOCOL, LATENCY, II, BACKPRESSURE & FLUSH TESTS PASSED ===");
        $finish(0);
    end

endmodule
