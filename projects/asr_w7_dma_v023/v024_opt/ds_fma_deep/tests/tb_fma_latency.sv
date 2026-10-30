`timescale 1ns/1ps
// Dedicated latency / II / bypass / flush / stall test for the 7-stage FMA.
// Fails with a nonzero exit code on any violation.
module tb_fma_latency;
    localparam integer LAT = 7;
    localparam integer N   = 40;

    reg clk, rst_n, flush;
    reg in_valid;
    wire in_ready;
    reg [31:0] in_data;
    reg [15:0] in_tag;
    reg in_last;
    reg [1:0] mode;
    reg [31:0] scale, bias;

    wire out_valid;
    reg out_ready;
    wire [31:0] out_data;
    wire [15:0] out_tag;
    wire out_last;

    integer cycle;
    integer errors;
    integer i;

    integer in_cyc  [0:4095];
    integer out_cyc [0:4095];
    reg [31:0] got_data [0:4095];
    reg        got_last [0:4095];
    reg        seen     [0:4095];

    epilogue_fma_stage dut (
        .clk(clk), .rst_n(rst_n), .flush(flush),
        .mode(mode), .scale(scale), .bias(bias),
        .in_valid(in_valid), .in_ready(in_ready), .in_data(in_data),
        .in_tag(in_tag), .in_last(in_last),
        .out_valid(out_valid), .out_ready(out_ready), .out_data(out_data),
        .out_tag(out_tag), .out_last(out_last)
    );

    always #5 clk = ~clk;

    always @(posedge clk) if (rst_n) cycle <= cycle + 1;

    // cycle watchdog
    initial begin
        #500000;
        $display("WATCHDOG: tb_fma_latency timeout");
        $finish(2);
    end

    // output capture
    always @(posedge clk) begin
        if (rst_n && out_valid && out_ready) begin
            out_cyc[out_tag[11:0]]  <= cycle;
            got_data[out_tag[11:0]] <= out_data;
            got_last[out_tag[11:0]] <= out_last;
            seen[out_tag[11:0]]     <= 1'b1;
        end
    end

    task fail(input [255:0] msg);
        begin
            errors = errors + 1;
            $display("[FAIL] %0s", msg);
        end
    endtask

    task reset_dut;
        begin
            rst_n = 0; flush = 0; in_valid = 0; in_data = 0; in_tag = 0;
            in_last = 0; mode = 0; scale = 32'h3f800000; bias = 0; out_ready = 1;
            repeat (3) @(negedge clk);
            rst_n = 1;
            repeat (2) @(negedge clk);
        end
    endtask

    initial begin
        clk = 1'b0;
        for (i = 0; i < 4096; i = i + 1) begin
            in_cyc[i] = -1; out_cyc[i] = -1; got_data[i] = 0;
            got_last[i] = 0; seen[i] = 0;
        end
        errors = 0; cycle = 0;

        // ------------------------------------------------------------------
        // 1) Back-to-back mode interleave: latency must be LAT, II must be 1.
        //    mode 0 is the pure bypass path; mode 1 computes 1.0*2.0+0 = 2.0.
        // ------------------------------------------------------------------
        reset_dut;
        for (i = 0; i < N; i = i + 1) begin
            @(negedge clk);
            in_valid = 1'b1;
            in_tag   = i[15:0];
            in_last  = (i == N - 1);
            mode     = i % 3;
            if (mode == 2'd0) begin
                in_data = 32'h3f000000 + i;   // asymmetric payload to prove bypass
                scale   = 32'h3f800000; bias = 32'h00000000;
            end else begin
                in_data = 32'h3f800000;       // 1.0
                scale   = 32'h40000000;       // 2.0
                bias    = 32'h00000000;
            end
            @(posedge clk);
            while (!in_ready) @(posedge clk);
            in_cyc[i] = cycle;
        end
        @(negedge clk);
        in_valid = 1'b0;
        // wait for all outputs
        for (i = 0; i < N * 4; i = i + 1) @(posedge clk);
        for (i = 0; i < N; i = i + 1) begin
            if (!seen[i]) begin
                $display("[FAIL] no output for tag %0d", i);
                errors = errors + 1;
            end else begin
                if (out_cyc[i] - in_cyc[i] != LAT) begin
                    $display("[FAIL] tag %0d latency %0d != %0d", i,
                             out_cyc[i] - in_cyc[i], LAT);
                    errors = errors + 1;
                end
                if (i % 3 == 0) begin
                    if (got_data[i] !== (32'h3f000000 + i)) begin
                        $display("[FAIL] mode0 bypass tag %0d got %08x", i, got_data[i]);
                        errors = errors + 1;
                    end
                end else begin
                    if (got_data[i] !== 32'h40000000) begin
                        $display("[FAIL] mode%0d arith tag %0d got %08x", i % 3, i, got_data[i]);
                        errors = errors + 1;
                    end
                end
                if (got_last[i] !== (i == N - 1)) begin
                    $display("[FAIL] tag %0d last mismatch", i);
                    errors = errors + 1;
                end
            end
        end
        // II=1: outputs occupy exactly N consecutive cycles
        if (out_cyc[N-1] - out_cyc[0] + 1 != N) begin
            $display("[FAIL] II!=1: span %0d for %0d beats",
                     out_cyc[N-1] - out_cyc[0] + 1, N);
            errors = errors + 1;
        end else begin
            $display("[PASS] latency=%0d, II=1 over %0d interleaved beats", LAT, N);
        end

        // ------------------------------------------------------------------
        // 2) In-flight flush: one beat launched then flush; nothing may emerge.
        // ------------------------------------------------------------------
        reset_dut;
        @(negedge clk);
        in_valid = 1'b1; in_tag = 16'h0abc; in_last = 1'b1;
        mode = 2'd1; in_data = 32'h3f800000; scale = 32'h40000000; bias = 0;
        @(posedge clk);
        while (!in_ready) @(posedge clk);
        @(negedge clk);
        in_valid = 1'b0;
        flush = 1'b1;
        @(posedge clk);
        @(negedge clk);
        flush = 1'b0;
        repeat (LAT + 6) @(posedge clk);
        if (out_valid) begin
            fail("out_valid survived in-flight flush");
        end else begin
            $display("[PASS] in-flight flush cleared the pipeline");
        end
        // post-flush transaction must work
        @(negedge clk);
        in_valid = 1'b1; in_tag = 16'h0abd; in_last = 1'b0;
        mode = 2'd1; in_data = 32'h3f800000; scale = 32'h40000000; bias = 0;
        @(posedge clk);
        while (!in_ready) @(posedge clk);
        in_cyc[12'h0bd] = cycle;
        @(negedge clk);
        in_valid = 1'b0;
        repeat (LAT + 4) @(posedge clk);
        if (!seen[12'habd] || got_data[12'habd] !== 32'h40000000) begin
            fail("post-flush transaction wrong");
        end else begin
            $display("[PASS] post-flush transaction correct");
        end

        // ------------------------------------------------------------------
        // 3) Stall freeze: hold out_ready=0 once a result is parked.
        // ------------------------------------------------------------------
        reset_dut;
        out_ready = 1'b0;
        @(negedge clk);
        in_valid = 1'b1; in_tag = 16'h0777; in_last = 1'b1;
        mode = 2'd1; in_data = 32'h3f800000; scale = 32'h40000000; bias = 0;
        @(posedge clk);
        while (!in_ready) @(posedge clk);
        @(negedge clk);
        in_valid = 1'b0;
        repeat (LAT + 2) @(posedge clk);
        if (!out_valid) begin
            fail("no parked result under backpressure");
        end else begin
            for (i = 0; i < 5; i = i + 1) begin
                @(posedge clk);
                if (!out_valid || out_data !== 32'h40000000 ||
                    out_tag !== 16'h0777 || out_last !== 1'b1)
                    fail("output not frozen under stall");
            end
            out_ready = 1'b1;
            @(posedge clk);
            @(negedge clk);
            $display("[PASS] output frozen under backpressure");
        end

        $display("LATENCY_TEST_ERRORS=%0d", errors);
        $finish(errors == 0 ? 0 : 1);
    end
endmodule
