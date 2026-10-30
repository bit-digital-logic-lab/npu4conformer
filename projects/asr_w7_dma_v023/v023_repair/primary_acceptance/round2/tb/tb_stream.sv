`timescale 1ns/1ps
// Independent integration testbench for epilogue_stream_engine_v023.
// Sends a 4-lane C48 burst, checks A16 / packed / spill framing and abort.
// Plusargs: MODE RELU SPILL SCALE(hex) BIAS(hex) ABORT_AT BP
module tb_stream;
    reg clk, rst_n;
    reg abort;
    reg cfg_valid;
    wire cfg_ready;
    reg [1:0] cfg_fma_mode;
    reg cfg_relu_en, cfg_spill_c48, cfg_spill_fp32;
    reg [31:0] cfg_scale, cfg_bias;
    reg [15:0] cfg_tag;
    reg param_wr_valid;
    wire param_wr_ready;
    reg [7:0] param_wr_addr;
    reg [31:0] param_wr_data;
    reg cval_valid;
    wire cval_ready;
    reg [191:0] cval_data;
    reg [15:0] cval_tag;
    reg cval_last;
    wire a16_valid;
    reg a16_ready;
    wire [63:0] a16_data;
    wire [127:0] a16_packed;
    wire a16_packed_valid;
    reg a16_packed_ready;
    wire a16_packed_last;
    wire [15:0] a16_tag;
    wire a16_last;
    wire spill_valid;
    reg spill_ready;
    wire [191:0] spill_data;
    wire [15:0] spill_tag;
    wire spill_last;
    wire [31:0] stat_c48_beats_in, stat_a16_beats_out, stat_spill_beats, stat_ddr_bytes_saved;

    integer fin, fout;
    integer rc;
    reg [47:0] l0, l1, l2, l3;
    reg [15:0] vt;
    reg vl;
    integer cycle, maxcycles;
    integer in_count, out_count, pack_count, spill_count;
    integer abort_at, bp_mode, mode, relu, spill, param_en, param_addr, recfg_at;
    reg [31:0] recfg_scale, recfg_bias;
    reg [31:0] param_data;
    reg [31:0] scale, bias;
    reg [15:0] lfsr;
    string vec_file, out_file;
    integer abort_cycle;

    always #4 clk = ~clk;

    epilogue_stream_engine_v023 dut (
        .clk(clk), .rst_n(rst_n), .abort(abort),
        .cfg_valid(cfg_valid), .cfg_ready(cfg_ready),
        .cfg_fma_mode(cfg_fma_mode), .cfg_relu_en(cfg_relu_en),
        .cfg_spill_c48(cfg_spill_c48), .cfg_spill_fp32(cfg_spill_fp32),
        .cfg_scale(cfg_scale), .cfg_bias(cfg_bias), .cfg_tag(cfg_tag),
        .param_wr_valid(param_wr_valid), .param_wr_ready(param_wr_ready),
        .param_wr_addr(param_wr_addr), .param_wr_data(param_wr_data),
        .cval_valid(cval_valid), .cval_ready(cval_ready), .cval_data(cval_data),
        .cval_tag(cval_tag), .cval_last(cval_last),
        .a16_valid(a16_valid), .a16_ready(a16_ready), .a16_data(a16_data),
        .a16_packed(a16_packed), .a16_packed_valid(a16_packed_valid),
        .a16_packed_ready(a16_packed_ready), .a16_packed_last(a16_packed_last),
        .a16_tag(a16_tag), .a16_last(a16_last),
        .spill_valid(spill_valid), .spill_ready(spill_ready),
        .spill_data(spill_data), .spill_tag(spill_tag), .spill_last(spill_last),
        .stat_c48_beats_in(stat_c48_beats_in),
        .stat_a16_beats_out(stat_a16_beats_out),
        .stat_spill_beats(stat_spill_beats),
        .stat_ddr_bytes_saved(stat_ddr_bytes_saved)
    );

    always @(posedge clk) begin
        if (rst_n) begin
            cycle <= cycle + 1;
            if (cycle > maxcycles) begin
                $display("WATCHDOG: stream timeout cycle=%0d in=%0d out=%0d pack=%0d",
                         cycle, in_count, out_count, pack_count);
                $fclose(fout); $finish(2);
            end
        end
    end

    always @(negedge clk) begin
        if (rst_n) begin
            lfsr <= {lfsr[14:0], lfsr[15]^lfsr[13]^lfsr[12]^lfsr[10]};
            if (bp_mode == 1) begin
                a16_ready <= lfsr[0];
                a16_packed_ready <= lfsr[1];
                spill_ready <= lfsr[2];
            end else if (bp_mode == 2) begin
                a16_ready <= 1'b1;
                a16_packed_ready <= lfsr[0];
                spill_ready <= 1'b1;
            end else begin
                a16_ready <= 1'b1;
                a16_packed_ready <= 1'b1;
                spill_ready <= 1'b1;
            end
        end
    end

    always @(posedge clk) begin
        if (rst_n && a16_valid && a16_ready) begin
            $fwrite(fout, "A %0d %016x %04x %0d\n", cycle, a16_data, a16_tag, a16_last);
            out_count <= out_count + 1;
        end
        if (rst_n && a16_packed_valid && a16_packed_ready) begin
            $fwrite(fout, "P %0d %032x %04x %0d\n", cycle, a16_packed, a16_tag, a16_packed_last);
            pack_count <= pack_count + 1;
        end
        if (rst_n && spill_valid && spill_ready) begin
            $fwrite(fout, "S %0d %048x %04x %0d\n", cycle, spill_data, spill_tag, spill_last);
            spill_count <= spill_count + 1;
        end
    end

    initial begin
        clk = 0; rst_n = 0; abort = 0;
        cfg_valid = 0; cfg_fma_mode = 0; cfg_relu_en = 0; cfg_spill_c48 = 0;
        cfg_spill_fp32 = 0; cfg_scale = 32'h3f800000; cfg_bias = 0; cfg_tag = 0;
        param_wr_valid = 0; param_wr_addr = 0; param_wr_data = 0;
        cval_valid = 0; cval_data = 0; cval_tag = 0; cval_last = 0;
        a16_ready = 1; a16_packed_ready = 1; spill_ready = 1;
        cycle = 0; in_count = 0; out_count = 0; pack_count = 0; spill_count = 0;
        lfsr = 16'h5A5A; abort_cycle = -1; param_en = 0; param_addr = 0; param_data = 0;
        recfg_at = -1; recfg_scale = 32'h3f800000; recfg_bias = 0;
        if (!$value$plusargs("VEC_FILE=%s", vec_file)) begin $display("ERROR: no VEC_FILE"); $finish(1); end
        if (!$value$plusargs("OUT_FILE=%s", out_file)) begin $display("ERROR: no OUT_FILE"); $finish(1); end
        if (!$value$plusargs("MAX_CYCLES=%d", maxcycles)) maxcycles = 1000000;
        if (!$value$plusargs("MODE=%d", mode)) mode = 0;
        if (!$value$plusargs("RELU=%d", relu)) relu = 0;
        if (!$value$plusargs("SPILL=%d", spill)) spill = 0;
        if (!$value$plusargs("SCALE=%h", scale)) scale = 32'h3f800000;
        if (!$value$plusargs("BIAS=%h", bias)) bias = 0;
        if (!$value$plusargs("ABORT_AT=%d", abort_at)) abort_at = -1;
        if (!$value$plusargs("BP=%d", bp_mode)) bp_mode = 0;
        if (!$value$plusargs("PARAM_EN=%d", param_en)) param_en = 0;
        if (!$value$plusargs("PARAM_ADDR=%d", param_addr)) param_addr = 0;
        if (!$value$plusargs("PARAM_DATA=%h", param_data)) param_data = 0;
        if (!$value$plusargs("RECFG_AT=%d", recfg_at)) recfg_at = -1;
        if (!$value$plusargs("RECFG_SCALE=%h", recfg_scale)) recfg_scale = 32'h3f800000;
        if (!$value$plusargs("RECFG_BIAS=%h", recfg_bias)) recfg_bias = 0;
        fin = $fopen(vec_file, "r");
        fout = $fopen(out_file, "w");
        if (fin == 0 || fout == 0) begin $display("ERROR: file open failed"); $finish(1); end
        #20; rst_n = 1; @(negedge clk);

        // Optional parameter-preload write (interface claims this is supported)
        if (param_en) begin
            param_wr_valid = 1; param_wr_addr = param_addr[7:0]; param_wr_data = param_data;
            @(posedge clk);
            @(negedge clk);
            param_wr_valid = 0;
        end

        // Load descriptor
        cfg_valid = 1;
        cfg_fma_mode = mode[1:0]; cfg_relu_en = relu[0]; cfg_spill_c48 = spill[0];
        cfg_spill_fp32 = 0; cfg_scale = scale; cfg_bias = bias; cfg_tag = 16'hAAAA;
        @(posedge clk);
        while (!cfg_ready) @(posedge clk);
        @(negedge clk);
        cfg_valid = 0;

        rc = $fscanf(fin, "%h %h %h %h %h %d\n", l0, l1, l2, l3, vt, vl);
        while (rc == 6) begin
            cval_valid = 1;
            cval_data = {l3, l2, l1, l0};
            cval_tag = vt;
            cval_last = vl;
            @(posedge clk);
            while (!cval_ready) @(posedge clk);
            in_count = in_count + 1;
            @(negedge clk);
            if (vl) cval_valid = 0;
            if (recfg_at >= 0 && in_count == recfg_at) begin
                cfg_valid = 1;
                cfg_fma_mode = mode[1:0]; cfg_relu_en = relu[0];
                cfg_spill_c48 = spill[0]; cfg_spill_fp32 = 0;
                cfg_scale = recfg_scale; cfg_bias = recfg_bias; cfg_tag = 16'hBBBB;
                @(posedge clk);
                while (!cfg_ready) @(posedge clk);
                @(negedge clk);
                cfg_valid = 0;
            end
            if (abort_at >= 0 && in_count == abort_at) begin
                abort = 1; abort_cycle = cycle;
                @(negedge clk);
                abort = 0;
                cval_valid = 0;
                rc = 0; // stop sending
            end else begin
                rc = $fscanf(fin, "%h %h %h %h %h %d\n", l0, l1, l2, l3, vt, vl);
            end
        end
        cval_valid = 0;
        // Drain (bounded)
        repeat (200) @(posedge clk);
        $display("DONE stream mode=%0d relu=%0d spill=%0d abort_at=%0d abort_cycle=%0d",
                 mode, relu, spill, abort_at, abort_cycle);
        $display("STATS in=%0d a16=%0d pack=%0d spill=%0d c48stat=%0d a16stat=%0d spillstat=%0d saved=%0d",
                 in_count, out_count, pack_count, spill_count,
                 stat_c48_beats_in, stat_a16_beats_out, stat_spill_beats, stat_ddr_bytes_saved);
        $fclose(fout);
        $finish(0);
    end
endmodule
