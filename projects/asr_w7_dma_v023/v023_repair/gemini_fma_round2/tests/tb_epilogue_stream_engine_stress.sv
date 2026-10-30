`timescale 1ns/1ps

module tb_epilogue_stream_engine_stress;

    parameter TAG_WIDTH = 16;

    reg clk;
    reg rst_n;
    reg abort;

    // Configuration
    reg                   cfg_valid;
    wire                  cfg_ready;
    reg [1:0]             cfg_fma_mode;
    reg                   cfg_relu_en;
    reg                   cfg_spill_c48;
    reg                   cfg_spill_fp32;
    reg [31:0]            cfg_scale;
    reg [31:0]            cfg_bias;
    reg [TAG_WIDTH-1:0]   cfg_tag;

    // Parameter Preload DMA Port
    reg                   param_wr_valid;
    wire                  param_wr_ready;
    reg [7:0]             param_wr_addr;
    reg [31:0]            param_wr_data;

    // Upstream C48 Stream
    reg                   cval_valid;
    wire                  cval_ready;
    reg [191:0]           cval_data;
    reg [TAG_WIDTH-1:0]   cval_tag;
    reg                   cval_last;

    // Downstream A16 Stream
    wire                  a16_valid;
    reg                   a16_ready;
    wire [63:0]           a16_data;
    wire [127:0]          a16_packed;
    wire                  a16_packed_valid;
    reg                   a16_packed_ready;
    wire                  a16_packed_last;
    wire [TAG_WIDTH-1:0]  a16_tag;
    wire                  a16_last;

    // C48 Spill Stream
    wire                  spill_valid;
    reg                   spill_ready;
    wire [191:0]          spill_data;
    wire [TAG_WIDTH-1:0]  spill_tag;
    wire                  spill_last;

    // Statistics
    wire [31:0]           stat_c48_beats_in;
    wire [31:0]           stat_a16_beats_out;
    wire [31:0]           stat_spill_beats;
    wire [31:0]           stat_ddr_bytes_saved;

    // DUT
    epilogue_stream_engine_v023 #(
        .TAG_WIDTH(TAG_WIDTH)
    ) dut (
        .clk                  (clk),
        .rst_n                (rst_n),
        .abort                (abort),
        .cfg_valid            (cfg_valid),
        .cfg_ready            (cfg_ready),
        .cfg_fma_mode         (cfg_fma_mode),
        .cfg_relu_en          (cfg_relu_en),
        .cfg_spill_c48        (cfg_spill_c48),
        .cfg_spill_fp32       (cfg_spill_fp32),
        .cfg_scale            (cfg_scale),
        .cfg_bias             (cfg_bias),
        .cfg_tag              (cfg_tag),
        .param_wr_valid       (param_wr_valid),
        .param_wr_ready       (param_wr_ready),
        .param_wr_addr        (param_wr_addr),
        .param_wr_data        (param_wr_data),
        .cval_valid           (cval_valid),
        .cval_ready           (cval_ready),
        .cval_data            (cval_data),
        .cval_tag             (cval_tag),
        .cval_last            (cval_last),
        .a16_valid            (a16_valid),
        .a16_ready            (a16_ready),
        .a16_data             (a16_data),
        .a16_packed           (a16_packed),
        .a16_packed_valid     (a16_packed_valid),
        .a16_packed_ready     (a16_packed_ready),
        .a16_packed_last      (a16_packed_last),
        .a16_tag              (a16_tag),
        .a16_last             (a16_last),
        .spill_valid          (spill_valid),
        .spill_ready          (spill_ready),
        .spill_data           (spill_data),
        .spill_tag            (spill_tag),
        .spill_last           (spill_last),
        .stat_c48_beats_in    (stat_c48_beats_in),
        .stat_a16_beats_out   (stat_a16_beats_out),
        .stat_spill_beats     (stat_spill_beats),
        .stat_ddr_bytes_saved (stat_ddr_bytes_saved)
    );

    always #5 clk = ~clk;

    // Diagnosable Watchdog timer: 1,000,000ns (1ms)
    initial begin
        #1000000;
        $display("[WATCHDOG] FATAL: tb_epilogue_stream_engine_stress timed out at %0t ps!", $time);
        $finish(2);
    end

    // File I/O for stimulus and monitoring
    integer stim_fd, out_fd, packed_fd;
    string stim_path, out_path, packed_path;

    integer received_beats = 0;
    integer received_packed_beats = 0;

    // Output capture process for 64-bit a16_data
    always @(posedge clk) begin
        if (rst_n && !abort) begin
            if (a16_valid && a16_ready) begin
                $fdisplay(out_fd, "%04x %016x %b", a16_tag, a16_data, a16_last);
                received_beats = received_beats + 1;
            end
            if (a16_packed_valid && a16_packed_ready) begin
                $fdisplay(packed_fd, "%04x %032x %b", a16_tag, a16_packed, a16_packed_last);
                received_packed_beats = received_packed_beats + 1;
            end
        end
    end

    // Random backpressure generator
    reg [31:0] rand_seed = 32'hcafe1234;
    function automatic [31:0] next_rand(input [31:0] s);
        next_rand = s * 32'd1103515245 + 32'd12345;
    endfunction

    reg backpressure_en = 0;
    always @(posedge clk) begin
        if (backpressure_en) begin
            rand_seed <= next_rand(rand_seed);
            a16_ready <= (rand_seed[3:0] != 4'd0); // 93.75% ready, 6.25% stall
            a16_packed_ready <= (rand_seed[7:4] != 4'd0);
            spill_ready <= (rand_seed[11:8] != 4'd0);
        end else begin
            a16_ready <= 1'b1;
            a16_packed_ready <= 1'b1;
            spill_ready <= 1'b1;
        end
    end

    initial begin
        clk = 0;
        rst_n = 0;
        abort = 0;
        cfg_valid = 0;
        cfg_fma_mode = 0;
        cfg_relu_en = 0;
        cfg_spill_c48 = 0;
        cfg_spill_fp32 = 0;
        cfg_scale = 32'h3f800000;
        cfg_bias = 32'h00000000;
        cfg_tag = 16'h0000;
        param_wr_valid = 0;
        param_wr_addr = 0;
        param_wr_data = 0;
        cval_valid = 0;
        cval_data = 0;
        cval_tag = 0;
        cval_last = 0;
        a16_ready = 1;
        a16_packed_ready = 1;
        spill_ready = 1;

        if (!$value$plusargs("stim=%s", stim_path)) stim_path = "stimulus.txt";
        if (!$value$plusargs("out=%s", out_path)) out_path = "output.txt";
        if (!$value$plusargs("packed_out=%s", packed_path)) packed_path = "output_packed.txt";

        out_fd = $fopen(out_path, "w");
        packed_fd = $fopen(packed_path, "w");
        stim_fd = $fopen(stim_path, "r");

        if (stim_fd == 0) begin
            $display("[FATAL] Cannot open stimulus file: %s", stim_path);
            $finish(1);
        end

        #20;
        @(posedge clk);
        rst_n = 1'b1;
        #20;
        @(posedge clk);

        // Read command loop from stimulus file
        // Format of lines in stimulus.txt:
        // C <mode> <relu_en> <spill_c48> <scale_hex> <bias_hex> <tag_hex>
        // D <cval_hex192> <tag_hex> <last_bit>
        // B <backpressure_en_bit>
        // A (trigger abort)
        // W <cycles>
        // E (end)
        begin : stim_loop
            string cmd;
            reg [1:0] m;
            reg relu, spill;
            reg [31:0] sc, bi;
            reg [15:0] tg;
            reg [191:0] c_hex;
            reg last_b;
            reg bp_bit;
            integer wait_n;

            while (!$feof(stim_fd)) begin
                if ($fscanf(stim_fd, "%s", cmd) == 1) begin
                    if (cmd == "C") begin
                        $fscanf(stim_fd, "%d %d %d %x %x %x", m, relu, spill, sc, bi, tg);
                        @(posedge clk);
                        while (!cfg_ready) @(posedge clk);
                        cfg_valid <= 1'b1;
                        cfg_fma_mode <= m;
                        cfg_relu_en <= relu;
                        cfg_spill_c48 <= spill;
                        cfg_scale <= sc;
                        cfg_bias <= bi;
                        cfg_tag <= tg;
                        @(posedge clk);
                        cfg_valid <= 1'b0;
                    end else if (cmd == "D") begin
                        $fscanf(stim_fd, "%x %x %d", c_hex, tg, last_b);
                        @(posedge clk);
                        while (!cval_ready) @(posedge clk);
                        cval_valid <= 1'b1;
                        cval_data  <= c_hex;
                        cval_tag   <= tg;
                        cval_last  <= last_b;
                        @(posedge clk);
                        cval_valid <= 1'b0;
                    end else if (cmd == "B") begin
                        $fscanf(stim_fd, "%d", bp_bit);
                        backpressure_en <= bp_bit;
                    end else if (cmd == "A") begin
                        @(posedge clk);
                        abort <= 1'b1;
                        @(posedge clk);
                        abort <= 1'b0;
                    end else if (cmd == "W") begin
                        $fscanf(stim_fd, "%d", wait_n);
                        repeat (wait_n) @(posedge clk);
                    end else if (cmd == "E") begin
                        // Wait for pipeline to drain
                        repeat (40) @(posedge clk);
                        disable stim_loop;
                    end
                end
            end
        end

        // Wait extra cycles to ensure completion
        repeat (50) @(posedge clk);

        $fclose(stim_fd);
        $fclose(out_fd);
        $fclose(packed_fd);

        $display("=== SIMULATION REACHED END: received_beats=%0d, packed_beats=%0d ===",
                 received_beats, received_packed_beats);
        $display("C48 in=%0d, A16 out=%0d, Spill=%0d, Bytes saved=%0d",
                 stat_c48_beats_in, stat_a16_beats_out, stat_spill_beats, stat_ddr_bytes_saved);
        $finish(0);
    end

endmodule
