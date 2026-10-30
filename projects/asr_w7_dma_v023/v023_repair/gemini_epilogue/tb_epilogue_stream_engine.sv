`timescale 1ns/1ps

module tb_epilogue_stream_engine;
    localparam TAG_WIDTH = 16;

    reg clk;
    reg rst_n;
    reg abort;

    // Config
    reg cfg_valid;
    wire cfg_ready;
    reg [1:0] cfg_fma_mode;
    reg cfg_relu_en;
    reg cfg_spill_c48;
    reg cfg_spill_fp32;
    reg [31:0] cfg_scale;
    reg [31:0] cfg_bias;
    reg [TAG_WIDTH-1:0] cfg_tag;

    // Param DMA
    reg param_wr_valid;
    wire param_wr_ready;
    reg [7:0] param_wr_addr;
    reg [31:0] param_wr_data;

    // Upstream C48 Stream
    reg cval_valid;
    wire cval_ready;
    reg [191:0] cval_data;
    reg [TAG_WIDTH-1:0] cval_tag;
    reg cval_last;

    // Downstream A16 Stream
    wire a16_valid;
    reg a16_ready;
    wire [63:0] a16_data;
    wire [127:0] a16_packed;
    wire a16_packed_valid;
    reg a16_packed_ready;
    wire a16_packed_last;
    wire [TAG_WIDTH-1:0] a16_tag;
    wire a16_last;

    // Spill Stream
    wire spill_valid;
    reg spill_ready;
    wire [191:0] spill_data;
    wire [TAG_WIDTH-1:0] spill_tag;
    wire spill_last;

    // Telemetry
    wire [31:0] stat_c48_beats_in;
    wire [31:0] stat_a16_beats_out;
    wire [31:0] stat_spill_beats;
    wire [31:0] stat_ddr_bytes_saved;

    // DUT Instantiation
    epilogue_stream_engine_v023 #(.TAG_WIDTH(TAG_WIDTH)) dut (
        .clk                 (clk),
        .rst_n               (rst_n),
        .abort               (abort),
        .cfg_valid           (cfg_valid),
        .cfg_ready           (cfg_ready),
        .cfg_fma_mode        (cfg_fma_mode),
        .cfg_relu_en         (cfg_relu_en),
        .cfg_spill_c48       (cfg_spill_c48),
        .cfg_spill_fp32      (cfg_spill_fp32),
        .cfg_scale           (cfg_scale),
        .cfg_bias            (cfg_bias),
        .cfg_tag             (cfg_tag),
        .param_wr_valid      (param_wr_valid),
        .param_wr_ready      (param_wr_ready),
        .param_wr_addr       (param_wr_addr),
        .param_wr_data       (param_wr_data),
        .cval_valid          (cval_valid),
        .cval_ready          (cval_ready),
        .cval_data           (cval_data),
        .cval_tag            (cval_tag),
        .cval_last           (cval_last),
        .a16_valid           (a16_valid),
        .a16_ready           (a16_ready),
        .a16_data            (a16_data),
        .a16_packed          (a16_packed),
        .a16_packed_valid    (a16_packed_valid),
        .a16_packed_ready    (a16_packed_ready),
        .a16_packed_last     (a16_packed_last),
        .a16_tag             (a16_tag),
        .a16_last            (a16_last),
        .spill_valid         (spill_valid),
        .spill_ready         (spill_ready),
        .spill_data          (spill_data),
        .spill_tag           (spill_tag),
        .spill_last          (spill_last),
        .stat_c48_beats_in   (stat_c48_beats_in),
        .stat_a16_beats_out  (stat_a16_beats_out),
        .stat_spill_beats    (stat_spill_beats),
        .stat_ddr_bytes_saved(stat_ddr_bytes_saved)
    );

    initial clk = 0;
    always #4 clk = ~clk; // 125 MHz clock (8ns period)

    integer pass_count = 0;
    integer fail_count = 0;

    task apply_config(
        input [1:0] fma_mode,
        input relu_en,
        input spill_c48,
        input [31:0] sc,
        input [31:0] bi,
        input [TAG_WIDTH-1:0] tag
    );
        begin
            @(posedge clk);
            while (!cfg_ready) @(posedge clk);
            cfg_valid <= 1'b1;
            cfg_fma_mode <= fma_mode;
            cfg_relu_en <= relu_en;
            cfg_spill_c48 <= spill_c48;
            cfg_spill_fp32 <= 1'b0;
            cfg_scale <= sc;
            cfg_bias <= bi;
            cfg_tag <= tag;
            @(posedge clk);
            cfg_valid <= 1'b0;
            @(posedge clk);
        end
    endtask

    task send_c48_beat(
        input [47:0] lane0,
        input [47:0] lane1,
        input [47:0] lane2,
        input [47:0] lane3,
        input [TAG_WIDTH-1:0] tag,
        input is_last
    );
        begin
            @(posedge clk);
            cval_valid <= 1'b1;
            cval_data  <= {lane3, lane2, lane1, lane0};
            cval_tag   <= tag;
            cval_last  <= is_last;
            while (!cval_ready) @(posedge clk);
            @(posedge clk);
            cval_valid <= 1'b0;
            cval_last  <= 1'b0;
        end
    endtask

    initial begin
        rst_n = 0;
        abort = 0;
        cfg_valid = 0;
        param_wr_valid = 0;
        cval_valid = 0;
        a16_ready = 1;
        a16_packed_ready = 1;
        spill_ready = 1;

        #20 rst_n = 1;
        #20;

        $display("=== STARTING EPILOGUE STREAM ENGINE VERIFICATION ===");

        // =====================================================================
        // Test Suite 1: Conversion-Only Mode (MODE_CONV_ONLY)
        // Tests I48_F32 -> F32_I16 with Banker's Rounding & Boundary Clamps
        // =====================================================================
        $display("--- Test Suite 1: Conversion-Only Mode ---");
        apply_config(2'd0, 1'b0, 1'b0, 32'h3f800000, 32'h00000000, 16'ha001);

        // Beat 1: Basic values 0, 1, -1, 32767
        fork
            send_c48_beat(48'sd0, 48'sd1, -48'sd1, 48'sd32767, 16'ha001, 1'b0);
            begin
                @(posedge clk);
                while (!a16_valid) @(posedge clk);
                if (a16_data[15:0] == 16'sd0 &&
                    a16_data[31:16] == 16'sd1 &&
                    $signed(a16_data[47:32]) == -16'sd1 &&
                    a16_data[63:48] == 16'sd32767) begin
                    $display("PASS Suite 1 Beat 1: Basic values match!");
                    pass_count = pass_count + 1;
                end else begin
                    $display("FAIL Suite 1 Beat 1: Got %h", a16_data);
                    fail_count = fail_count + 1;
                end
            end
        join

        // Beat 2: Clamping boundaries: -32768, 65536 (clamps to 32767), -100000 (clamps to -32768), max pos
        fork
            send_c48_beat(-48'sd32768, 48'sd65536, -48'sd100000, 48'h7fffffffffff, 16'ha001, 1'b1);
            begin
                @(posedge clk);
                while (!a16_valid) @(posedge clk);
                if ($signed(a16_data[15:0]) == -16'sd32768 &&
                    a16_data[31:16] == 16'sd32767 &&
                    $signed(a16_data[47:32]) == -16'sd32768 &&
                    a16_data[63:48] == 16'sd32767 &&
                    a16_last == 1'b1) begin
                    $display("PASS Suite 1 Beat 2: Saturation clamping and last flag match!");
                    pass_count = pass_count + 1;
                end else begin
                    $display("FAIL Suite 1 Beat 2: Got %h", a16_data);
                    fail_count = fail_count + 1;
                end
            end
        join

        // =====================================================================
        // Test Suite 2: ReLU Activation Mode
        // =====================================================================
        $display("--- Test Suite 2: ReLU Mode ---");
        apply_config(2'd0, 1'b1, 1'b0, 32'h3f800000, 32'h00000000, 16'ha002);

        // Inputs: -100 (should become 0), +50, -500 (should become 0), +300
        fork
            send_c48_beat(-48'sd100, 48'sd50, -48'sd500, 48'sd300, 16'ha002, 1'b1);
            begin
                @(posedge clk);
                while (!a16_valid) @(posedge clk);
                if (a16_data[15:0] == 16'sd0 &&
                    a16_data[31:16] == 16'sd50 &&
                    a16_data[47:32] == 16'sd0 &&
                    a16_data[63:48] == 16'sd300) begin
                    $display("PASS Suite 2 ReLU: Negative numbers zeroed out!");
                    pass_count = pass_count + 1;
                end else begin
                    $display("FAIL Suite 2 ReLU: Got %h", a16_data);
                    fail_count = fail_count + 1;
                end
            end
        join

        // =====================================================================
        // Test Suite 3: Scale and Bias FMA Mode
        // Scale = 2.0 (0x40000000), Bias = 10.0 (0x41200000)
        // result = x * 2.0 + 10.0
        // Inputs: 5 -> 20, 0 -> 10, -5 -> 0, 10 -> 30
        // =====================================================================
        $display("--- Test Suite 3: Scale & Bias FMA Mode ---");
        apply_config(2'd1, 1'b0, 1'b0, 32'h40000000, 32'h41200000, 16'ha003);

        fork
            send_c48_beat(48'sd5, 48'sd0, -48'sd5, 48'sd10, 16'ha003, 1'b1);
            begin
                @(posedge clk);
                while (!a16_valid) @(posedge clk);
                if (a16_data[15:0] == 16'sd20 &&
                    a16_data[31:16] == 16'sd10 &&
                    a16_data[47:32] == 16'sd0 &&
                    a16_data[63:48] == 16'sd30) begin
                    $display("PASS Suite 3 FMA: Scale (x2) and Bias (+10) computed correctly!");
                    pass_count = pass_count + 1;
                end else begin
                    $display("FAIL Suite 3 FMA: Got %h (expected 001e, 0000, 000a, 0014)", a16_data);
                    fail_count = fail_count + 1;
                end
            end
        join

        // =====================================================================
        // Test Suite 4: Multi-Consumer C48 Spill Stream
        // =====================================================================
        $display("--- Test Suite 4: Spill Channel Mode ---");
        apply_config(2'd0, 1'b0, 1'b1, 32'h3f800000, 32'h00000000, 16'ha004);

        fork
            send_c48_beat(48'h111111111111, 48'h222222222222, 48'h333333333333, 48'h444444444444, 16'ha004, 1'b1);
            begin
                @(posedge clk);
                while (!spill_valid) @(posedge clk);
                if (spill_data == {48'h444444444444, 48'h333333333333, 48'h222222222222, 48'h111111111111} &&
                    spill_tag == 16'ha004 && spill_last == 1'b1) begin
                    $display("PASS Suite 4 Spill: Raw C48 duplicated to spill port bit-exact!");
                    pass_count = pass_count + 1;
                end else begin
                    $display("FAIL Suite 4 Spill: Got spill_data=%h", spill_data);
                    fail_count = fail_count + 1;
                end
            end
            begin
                @(posedge clk);
                while (!a16_valid) @(posedge clk);
                $display("PASS Suite 4 Spill: A16 stream produced concurrently with spill!");
                pass_count = pass_count + 1;
            end
        join

        // =====================================================================
        // Test Suite 5: Backpressure Stress Test
        // =====================================================================
        $display("--- Test Suite 5: Backpressure Test ---");
        apply_config(2'd0, 1'b0, 1'b0, 32'h3f800000, 32'h00000000, 16'ha005);
        a16_ready <= 0; // Downstream stall

        fork
            send_c48_beat(48'sd7, 48'sd8, 48'sd9, 48'sd10, 16'ha005, 1'b1);
            begin
                #50;
                $display("Downstream released after stall");
                @(posedge clk);
                a16_ready <= 1;
                while (!a16_valid) @(posedge clk);
                if (a16_data[15:0] == 16'sd7 && a16_data[31:16] == 16'sd8 &&
                    a16_data[47:32] == 16'sd9 && a16_data[63:48] == 16'sd10) begin
                    $display("PASS Suite 5 Backpressure: Handled stall with zero data loss!");
                    pass_count = pass_count + 1;
                end else begin
                    $display("FAIL Suite 5 Backpressure: Got %h", a16_data);
                    fail_count = fail_count + 1;
                end
            end
        join

        // =====================================================================
        // Test Suite 6: 128-bit AXI Beat Packer Verification
        // =====================================================================
        $display("--- Test Suite 6: 128-bit Packer Test ---");
        apply_config(2'd0, 1'b0, 1'b0, 32'h3f800000, 32'h00000000, 16'ha006);

        // Send two consecutive beats (4 elements each = 8 elements total = 128 bits)
        fork
            begin
                send_c48_beat(48'sd1, 48'sd2, 48'sd3, 48'sd4, 16'ha006, 1'b0);
                send_c48_beat(48'sd5, 48'sd6, 48'sd7, 48'sd8, 16'ha006, 1'b1);
            end
            begin
                @(posedge clk);
                while (!a16_packed_valid) @(posedge clk);
                if (a16_packed == {16'sd8, 16'sd7, 16'sd6, 16'sd5, 16'sd4, 16'sd3, 16'sd2, 16'sd1} &&
                    a16_packed_last == 1'b1) begin
                    $display("PASS Suite 6 Packer: 128-bit beat packed 8 INT16 elements correctly!");
                    pass_count = pass_count + 1;
                end else begin
                    $display("FAIL Suite 6 Packer: Got %h", a16_packed);
                    fail_count = fail_count + 1;
                end
            end
        join

        // =====================================================================
        // Test Suite 7: Synchronous Error Drain / Abort
        // =====================================================================
        $display("--- Test Suite 7: Error Drain / Abort ---");
        // Start streaming and assert abort mid-pipeline
        @(posedge clk);
        cval_valid <= 1'b1;
        cval_data <= {48'd10, 48'd20, 48'd30, 48'd40};
        @(posedge clk);
        abort <= 1'b1;
        @(posedge clk);
        abort <= 1'b0;
        cval_valid <= 1'b0;
        #20;
        if (!a16_valid && !a16_packed_valid) begin
            $display("PASS Suite 7 Abort: Pipelines flushed cleanly with zero remaining valid!");
            pass_count = pass_count + 1;
        end else begin
            $display("FAIL Suite 7 Abort: Leak detected after flush!");
            fail_count = fail_count + 1;
        end

        // =====================================================================
        // Summary & Metrics
        // =====================================================================
        #50;
        $display("=====================================================");
        $display("EPILOGUE ENGINE VERIFICATION COMPLETE");
        $display("Total Suites Passed: %0d / %0d", pass_count, pass_count + fail_count);
        $display("C48 Beats In: %0d", stat_c48_beats_in);
        $display("A16 Beats Out: %0d", stat_a16_beats_out);
        $display("Spill Beats Out: %0d", stat_spill_beats);
        $display("DDR Bytes Saved (Telemetry): %0d Bytes", stat_ddr_bytes_saved);
        $display("=====================================================");

        if (fail_count == 0) begin
            $display("ALL EPILOGUE SUITES PASSED WITH 100%% SUCCESS!");
        end else begin
            $fatal(1, "TEST FAILED WITH %0d FAILURES", fail_count);
        end
        $finish;
    end

endmodule
