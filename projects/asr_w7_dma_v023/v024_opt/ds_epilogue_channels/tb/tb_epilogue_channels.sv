`timescale 1ns/1ps
// tb_epilogue_channels.sv
// Independent testbench for epilogue_stream_engine_v024.
//
// Drives one command file (CFG/BEAT/ABORT/WAIT/PARAMBARRIER/END) and one
// parameter-DMA file (PARAM).  The parameter writer is a separate process so
// inactive-bank preload can be exercised while C48 beats stream, and an
// active-bank write can be observed to wait.
//
// Outputs are logged as:
//   A <cycle> <data:016x> <tag:04x> <last>
//   P <cycle> <data:032x> <tag:04x> <last>
//   F <cycle> <data:032x> <tag:04x> <last>
//   S <cycle> <data:048x> <tag:04x> <last>
// plus STABILITY_ERRORS, PARAM_ERRORS, ABORT_CYCLE and DRAINED/DRAIN_FAIL.
//
// Cycle watchdog exits with code 2.  A normal run is expected to drain the
// last A16, packed, FP32 and spill beat; there is no AXI B channel in this
// module, so no B response is claimed here.

module tb_epilogue_channels;
    reg clk, rst_n;
    reg abort;
    reg cfg_valid;
    wire cfg_ready;
    reg [1:0] cfg_fma_mode;
    reg cfg_relu_en, cfg_spill_c48, cfg_spill_fp32, cfg_table_en, cfg_bank;
    reg [15:0] cfg_bc;
    reg [31:0] cfg_scale, cfg_bias;
    reg [15:0] cfg_tag;

    reg param_wr_valid;
    wire param_wr_ready;
    reg [7:0] param_wr_addr;
    reg [15:0] param_wr_bc;
    reg [31:0] param_wr_data;

    reg cval_valid;
    wire cval_ready;
    reg [191:0] cval_data;
    reg [15:0] cval_tag;
    reg [15:0] cval_bc;
    reg [4:0] cval_col;
    reg cval_last;

    wire a16_valid;
    reg a16_ready;
    wire [63:0] a16_data;
    wire [127:0] a16_packed;
    wire a16_packed_valid;
    reg a16_packed_ready;
    wire a16_packed_last;
    wire [15:0] a16_packed_tag;
    wire [15:0] a16_tag;
    wire a16_last;

    wire fp32x4_valid;
    reg fp32x4_ready;
    wire [127:0] fp32x4_data;
    wire [15:0] fp32x4_tag;
    wire fp32x4_last;

    wire spill_valid;
    reg spill_ready;
    wire [191:0] spill_data;
    wire [15:0] spill_tag;
    wire spill_last;

    wire [31:0] stat_c48_beats_in, stat_a16_beats_out, stat_spill_beats, stat_ddr_bytes_saved;
    wire [31:0] stat_fp32_beats_out, stat_table_hits, stat_table_misses;
    wire [31:0] stat_col_align_err, stat_param_rejects;

    epilogue_stream_engine_v024 dut (
        .clk(clk), .rst_n(rst_n), .abort(abort),
        .cfg_valid(cfg_valid), .cfg_ready(cfg_ready),
        .cfg_fma_mode(cfg_fma_mode), .cfg_relu_en(cfg_relu_en),
        .cfg_spill_c48(cfg_spill_c48), .cfg_spill_fp32(cfg_spill_fp32),
        .cfg_table_en(cfg_table_en), .cfg_bank(cfg_bank), .cfg_bc(cfg_bc),
        .cfg_scale(cfg_scale), .cfg_bias(cfg_bias), .cfg_tag(cfg_tag),
        .param_wr_valid(param_wr_valid), .param_wr_ready(param_wr_ready),
        .param_wr_addr(param_wr_addr), .param_wr_bc(param_wr_bc),
        .param_wr_data(param_wr_data),
        .cval_valid(cval_valid), .cval_ready(cval_ready),
        .cval_data(cval_data), .cval_tag(cval_tag), .cval_bc(cval_bc),
        .cval_col(cval_col), .cval_last(cval_last),
        .a16_valid(a16_valid), .a16_ready(a16_ready), .a16_data(a16_data),
        .a16_packed(a16_packed), .a16_packed_valid(a16_packed_valid),
        .a16_packed_ready(a16_packed_ready), .a16_packed_last(a16_packed_last),
        .a16_packed_tag(a16_packed_tag), .a16_tag(a16_tag), .a16_last(a16_last),
        .fp32x4_valid(fp32x4_valid), .fp32x4_ready(fp32x4_ready),
        .fp32x4_data(fp32x4_data), .fp32x4_tag(fp32x4_tag), .fp32x4_last(fp32x4_last),
        .spill_valid(spill_valid), .spill_ready(spill_ready),
        .spill_data(spill_data), .spill_tag(spill_tag), .spill_last(spill_last),
        .stat_c48_beats_in(stat_c48_beats_in),
        .stat_a16_beats_out(stat_a16_beats_out),
        .stat_spill_beats(stat_spill_beats),
        .stat_ddr_bytes_saved(stat_ddr_bytes_saved),
        .stat_fp32_beats_out(stat_fp32_beats_out),
        .stat_table_hits(stat_table_hits),
        .stat_table_misses(stat_table_misses),
        .stat_col_align_err(stat_col_align_err),
        .stat_param_rejects(stat_param_rejects)
    );

    integer cycle, maxcycles;
    integer in_count, out_count, pack_count, fp32_count, spill_count;
    integer stability_errors, param_errors;
    integer abort_cycle;
    integer bp_mode;
    integer fin_cmd, fin_par, fout;
    string cmd_file, par_file, out_file;
    reg [8*24-1:0] cmd;
    integer rc, rc2;
    reg [47:0] l0, l1, l2, l3;
    reg [15:0] vt, vbc;
    integer vcol, vlast;
    integer cmode, crelu, cspill48, cspillfp32, ctable, cbank;
    integer cbc;
    reg [31:0] cscale, cbias;
    reg [15:0] ctag;

    integer p_after, p_expect, p_maxc, p_cycles, p_accepted;
    integer barrier_need, wait_n;
    reg [7:0] p_addr;
    reg [15:0] p_bc;
    reg [31:0] p_data;
    integer param_done_count;
    reg param_active;
    reg drain_mode;
    reg files_ready;

    reg [15:0] lfsr;

    always #4 clk = ~clk;

    // ---------------- cycle counter / watchdog ----------------
    always @(posedge clk) begin
        if (rst_n) begin
            cycle <= cycle + 1;
            if (cycle > maxcycles) begin
                $display("WATCHDOG: timeout cycle=%0d in=%0d out=%0d pack=%0d fp32=%0d spill=%0d",
                         cycle, in_count, out_count, pack_count, fp32_count, spill_count);
                $fclose(fout); $finish(2);
            end
        end
    end

    // ---------------- backpressure drivers ----------------
    always @(negedge clk) begin
        if (rst_n) begin
            lfsr <= {lfsr[14:0], lfsr[15]^lfsr[13]^lfsr[12]^lfsr[10]};
            if (drain_mode) begin
                a16_ready <= 1'b1;
                a16_packed_ready <= 1'b1;
                fp32x4_ready <= 1'b1;
                spill_ready <= 1'b1;
            end else if (bp_mode == 1) begin
                a16_ready <= lfsr[0];
                a16_packed_ready <= lfsr[1];
                fp32x4_ready <= lfsr[2];
                spill_ready <= lfsr[3];
            end else if (bp_mode == 2) begin
                a16_ready <= lfsr[0];
                a16_packed_ready <= 1'b1;
                fp32x4_ready <= 1'b1;
                spill_ready <= 1'b1;
            end else if (bp_mode == 3) begin
                a16_ready <= 1'b1;
                a16_packed_ready <= lfsr[0];
                fp32x4_ready <= 1'b1;
                spill_ready <= 1'b1;
            end else if (bp_mode == 4) begin
                a16_ready <= 1'b1;
                a16_packed_ready <= 1'b1;
                fp32x4_ready <= lfsr[0];
                spill_ready <= 1'b1;
            end else if (bp_mode == 5) begin
                a16_ready <= (cycle % 32) >= 16;
                a16_packed_ready <= (cycle % 41) >= 20;
                fp32x4_ready <= (cycle % 53) >= 26;
                spill_ready <= (cycle % 29) >= 14;
            end else begin
                a16_ready <= 1'b1;
                a16_packed_ready <= 1'b1;
                fp32x4_ready <= 1'b1;
                spill_ready <= 1'b1;
            end
        end
    end

    // ---------------- output logging ----------------
    always @(posedge clk) begin
        if (rst_n) begin
            if (a16_valid && a16_ready) begin
                $fwrite(fout, "A %0d %016x %04x %0d\n", cycle, a16_data, a16_tag, a16_last);
                out_count <= out_count + 1;
            end
            if (a16_packed_valid && a16_packed_ready) begin
                $fwrite(fout, "P %0d %032x %04x %0d\n", cycle, a16_packed, a16_packed_tag, a16_packed_last);
                pack_count <= pack_count + 1;
            end
            if (fp32x4_valid && fp32x4_ready) begin
                $fwrite(fout, "F %0d %032x %04x %0d\n", cycle, fp32x4_data, fp32x4_tag, fp32x4_last);
                fp32_count <= fp32_count + 1;
            end
            if (spill_valid && spill_ready) begin
                $fwrite(fout, "S %0d %048x %04x %0d\n", cycle, spill_data, spill_tag, spill_last);
                spill_count <= spill_count + 1;
            end
        end
    end

    // ---------------- output stability assertions ----------------
    reg a_stalled, p_stalled, f_stalled, s_stalled;
    reg [80:0] a_saved;
    reg [144:0] p_saved;
    reg [144:0] f_saved;
    reg [209:0] s_saved;

    always @(posedge clk) begin
        if (!rst_n || abort) begin
            a_stalled <= 0; p_stalled <= 0; f_stalled <= 0; s_stalled <= 0;
        end else begin
            if (a_stalled && (!a16_valid || {a16_data,a16_tag,a16_last} !== a_saved))
                stability_errors <= stability_errors + 1;
            if (p_stalled && (!a16_packed_valid || {a16_packed,a16_packed_tag,a16_packed_last} !== p_saved))
                stability_errors <= stability_errors + 1;
            if (f_stalled && (!fp32x4_valid || {fp32x4_data,fp32x4_tag,fp32x4_last} !== f_saved))
                stability_errors <= stability_errors + 1;
            if (s_stalled && (!spill_valid || {spill_data,spill_tag,spill_last} !== s_saved))
                stability_errors <= stability_errors + 1;
            a_stalled <= a16_valid && !a16_ready;
            p_stalled <= a16_packed_valid && !a16_packed_ready;
            f_stalled <= fp32x4_valid && !fp32x4_ready;
            s_stalled <= spill_valid && !spill_ready;
            a_saved <= {a16_data,a16_tag,a16_last};
            p_saved <= {a16_packed,a16_packed_tag,a16_packed_last};
            f_saved <= {fp32x4_data,fp32x4_tag,fp32x4_last};
            s_saved <= {spill_data,spill_tag,spill_last};
        end
    end

    // ---------------- parameter DMA process ----------------
    initial begin
        param_wr_valid = 0; param_wr_addr = 0; param_wr_bc = 0; param_wr_data = 0;
        param_done_count = 0; param_errors = 0; param_active = 0;
        wait (files_ready);
        wait (rst_n);
        @(negedge clk);
        rc = $fscanf(fin_par, "%s", cmd);
        while (rc == 1) begin
            if (cmd == "PARAM") begin
                rc2 = $fscanf(fin_par, "%d %h %d %h %d %d\n",
                              p_after, p_addr, p_bc, p_data, p_expect, p_maxc);
                while (in_count < p_after) @(negedge clk);
                param_active = 1;
                param_wr_valid = 1;
                param_wr_addr = p_addr;
                param_wr_bc = p_bc;
                param_wr_data = p_data;
                p_accepted = 0;
                p_cycles = 0;
                // Hold the request until ready or the rejection window expires.
                while (p_cycles < p_maxc) begin
                    @(posedge clk);
                    if (param_wr_ready) begin
                        p_accepted = 1;
                        p_cycles = p_maxc;
                    end else begin
                        p_cycles = p_cycles + 1;
                    end
                end
                @(negedge clk);
                param_wr_valid = 0;
                param_active = 0;
                if (p_expect == 1 && !p_accepted) begin
                    $display("PARAM_ERROR: expected accept addr=%02x bc=%0d after=%0d",
                             p_addr, p_bc, p_after);
                    param_errors = param_errors + 1;
                end
                if (p_expect == 0 && p_accepted) begin
                    $display("PARAM_ERROR: unexpected accept addr=%02x bc=%0d after=%0d",
                             p_addr, p_bc, p_after);
                    param_errors = param_errors + 1;
                end
                param_done_count = param_done_count + 1;
            end
            rc = $fscanf(fin_par, "%s", cmd);
        end
    end

    // ---------------- main command driver ----------------
    initial begin
        clk = 0; rst_n = 0; abort = 0;
        cfg_valid = 0; cfg_fma_mode = 0; cfg_relu_en = 0; cfg_spill_c48 = 0;
        cfg_spill_fp32 = 0; cfg_table_en = 0; cfg_bank = 0; cfg_bc = 0;
        cfg_scale = 32'h3f800000; cfg_bias = 0; cfg_tag = 0;
        cval_valid = 0; cval_data = 0; cval_tag = 0; cval_bc = 0; cval_col = 0; cval_last = 0;
        a16_ready = 1; a16_packed_ready = 1; fp32x4_ready = 1; spill_ready = 1;
        cycle = 0; in_count = 0; out_count = 0; pack_count = 0; fp32_count = 0;
        spill_count = 0; stability_errors = 0; param_errors = 0;
        abort_cycle = -1; bp_mode = 0; lfsr = 16'h5A5A; drain_mode = 0;
        files_ready = 0;

        if (!$value$plusargs("CMD_FILE=%s", cmd_file)) begin $display("ERROR: no CMD_FILE"); $finish(1); end
        if (!$value$plusargs("PAR_FILE=%s", par_file)) begin $display("ERROR: no PAR_FILE"); $finish(1); end
        if (!$value$plusargs("OUT_FILE=%s", out_file)) begin $display("ERROR: no OUT_FILE"); $finish(1); end
        if (!$value$plusargs("MAX_CYCLES=%d", maxcycles)) maxcycles = 2000000;
        if (!$value$plusargs("BP=%d", bp_mode)) bp_mode = 0;
        fin_cmd = $fopen(cmd_file, "r");
        fin_par = $fopen(par_file, "r");
        fout = $fopen(out_file, "w");
        if (fin_cmd == 0 || fin_par == 0 || fout == 0) begin
            $display("ERROR: file open failed"); $finish(1);
        end
        files_ready = 1;
        #20; rst_n = 1; @(negedge clk);

        rc = $fscanf(fin_cmd, "%s", cmd);
        while (rc == 1) begin
            if (cmd == "CFG") begin
                rc2 = $fscanf(fin_cmd, "%d %d %d %d %d %d %d %h %h %h\n",
                              cmode, crelu, cspill48, cspillfp32, ctable, cbank,
                              cbc, cscale, cbias, ctag);
                cfg_fma_mode = cmode[1:0];
                cfg_relu_en = crelu[0];
                cfg_spill_c48 = cspill48[0];
                cfg_spill_fp32 = cspillfp32[0];
                cfg_table_en = ctable[0];
                cfg_bank = cbank[0];
                cfg_bc = cbc[15:0];
                cfg_scale = cscale;
                cfg_bias = cbias;
                cfg_tag = ctag;
                cfg_valid = 1;
                @(posedge clk);
                while (!cfg_ready) @(posedge clk);
                @(negedge clk);
                cfg_valid = 0;
            end else if (cmd == "CFGSTART") begin
                rc2 = $fscanf(fin_cmd, "%d %d %d %d %d %d %d %h %h %h\n",
                              cmode, crelu, cspill48, cspillfp32, ctable, cbank,
                              cbc, cscale, cbias, ctag);
                cfg_fma_mode = cmode[1:0];
                cfg_relu_en = crelu[0];
                cfg_spill_c48 = cspill48[0];
                cfg_spill_fp32 = cspillfp32[0];
                cfg_table_en = ctable[0];
                cfg_bank = cbank[0];
                cfg_bc = cbc[15:0];
                cfg_scale = cscale;
                cfg_bias = cbias;
                cfg_tag = ctag;
                cfg_valid = 1;
            end else if (cmd == "CFGWAIT") begin
                @(posedge clk);
                while (!cfg_ready) @(posedge clk);
                @(negedge clk);
                cfg_valid = 0;
            end else if (cmd == "BEAT") begin
                rc2 = $fscanf(fin_cmd, "%h %h %h %h %h %d %d %d\n",
                              l0, l1, l2, l3, vt, vbc, vcol, vlast);
                cval_data = {l3, l2, l1, l0};
                cval_tag = vt;
                cval_bc = vbc;
                cval_col = vcol[4:0];
                cval_last = vlast[0];
                cval_valid = 1;
                @(posedge clk);
                while (!cval_ready) @(posedge clk);
                in_count = in_count + 1;
                @(negedge clk);
                cval_valid = 0;
            end else if (cmd == "ABORT") begin
                abort = 1;
                @(posedge clk);
                abort_cycle = cycle;
                @(negedge clk);
                abort = 0;
            end else if (cmd == "WAIT") begin
                rc2 = $fscanf(fin_cmd, "%d\n", wait_n);
                repeat (wait_n) @(negedge clk);
            end else if (cmd == "PARAMBARRIER") begin
                rc2 = $fscanf(fin_cmd, "%d\n", barrier_need);
                while ((param_done_count < barrier_need) || param_active) @(negedge clk);
            end else if (cmd == "END") begin
                rc = 0;
            end else begin
                $display("ERROR: unknown command %0s", cmd);
                $finish(1);
            end
            if (rc != 0) rc = $fscanf(fin_cmd, "%s", cmd);
        end

        // Drain: force all consumers ready and require the last beats to leave.
        drain_mode = 1;
        cval_valid = 0;
        @(negedge clk);
        p_cycles = 0;
        while (p_cycles < 2000) begin
            @(posedge clk);
            if (!(a16_valid || a16_packed_valid || fp32x4_valid || spill_valid)) begin
                p_cycles = p_cycles + 1;
                if (p_cycles >= 20) p_cycles = 2000;
            end else begin
                p_cycles = 0;
            end
        end
        $display("ABORT_CYCLE=%0d", abort_cycle);
        $display("STATS in=%0d a16=%0d pack=%0d fp32=%0d spill=%0d c48stat=%0d a16stat=%0d fp32stat=%0d spillstat=%0d",
                 in_count, out_count, pack_count, fp32_count, spill_count,
                 stat_c48_beats_in, stat_a16_beats_out, stat_fp32_beats_out, stat_spill_beats);
        $display("TABLE hits=%0d misses=%0d align_err=%0d rejects=%0d saved=%0d",
                 stat_table_hits, stat_table_misses, stat_col_align_err,
                 stat_param_rejects, stat_ddr_bytes_saved);
        $display("STABILITY_ERRORS=%0d", stability_errors);
        $display("PARAM_ERRORS=%0d", param_errors);
        if (a16_valid || a16_packed_valid || fp32x4_valid || spill_valid) begin
            $display("DRAIN_FAIL cycle=%0d a16v=%0d pv=%0d fv=%0d sv=%0d",
                     cycle, a16_valid, a16_packed_valid, fp32x4_valid, spill_valid);
            $fclose(fout); $finish(2);
        end else begin
            $display("DRAINED cycle=%0d", cycle);
            $fclose(fout); $finish(0);
        end
    end
endmodule
