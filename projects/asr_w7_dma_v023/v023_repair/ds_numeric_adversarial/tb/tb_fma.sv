`timescale 1ns/1ps
// Independent file-driven testbench for epilogue_fma_stage.
// Input : "mode_hex scale_hex bias_hex data_hex tag_hex last"
// Output: "in_cycle out_cycle data_hex tag_hex last"
module tb_fma;
    reg clk, rst_n;
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

    integer fin, fout;
    integer rc;
    reg [1:0] vmode;
    reg [31:0] vs, vb, vd;
    reg [15:0] vt;
    reg vl;
    integer cycle, maxcycles;
    integer in_count, out_count;
    integer in_cycle [0:65535];
    integer bp_mode;
    reg [15:0] lfsr;
    string vec_file, out_file;

    integer stability_errors;
    reg stall_prev;
    reg [31:0] prev_data; reg [15:0] prev_tag; reg prev_last;

    always #4 clk = ~clk;

    epilogue_fma_stage dut (
        .clk(clk), .rst_n(rst_n), .flush(1'b0),
        .mode(mode), .scale(scale), .bias(bias),
        .in_valid(in_valid), .in_ready(in_ready), .in_data(in_data),
        .in_tag(in_tag), .in_last(in_last),
        .out_valid(out_valid), .out_ready(out_ready), .out_data(out_data),
        .out_tag(out_tag), .out_last(out_last)
    );

    always @(posedge clk) begin
        if (rst_n) begin
            cycle <= cycle + 1;
            if (cycle > maxcycles) begin
                $display("WATCHDOG: fma timeout cycle=%0d in=%0d out=%0d", cycle, in_count, out_count);
                $fclose(fout); $finish(2);
            end
        end
    end

    always @(negedge clk) begin
        if (rst_n) begin
            lfsr <= {lfsr[14:0], lfsr[15]^lfsr[13]^lfsr[12]^lfsr[10]};
            if (bp_mode == 1) out_ready <= lfsr[0];
            else if (bp_mode == 2) out_ready <= !(lfsr[2:0] == 3'd0);
            else out_ready <= 1'b1;
        end
    end

    always @(posedge clk) begin
        if (rst_n && out_valid && out_ready) begin
            $fwrite(fout, "%0d %0d %08x %04x %0d\n",
                    in_cycle[out_tag], cycle, out_data, out_tag, out_last);
            out_count <= out_count + 1;
        end
    end

    always @(posedge clk) begin
        if (rst_n) begin
            if (stall_prev) begin
                if (!out_valid || out_data !== prev_data || out_tag !== prev_tag || out_last !== prev_last)
                    stability_errors = stability_errors + 1;
            end
            stall_prev <= out_valid && !out_ready;
            prev_data <= out_data; prev_tag <= out_tag; prev_last <= out_last;
        end
    end

    initial begin
        clk = 0; rst_n = 0; in_valid = 0; in_data = 0; in_tag = 0; in_last = 0;
        mode = 0; scale = 32'h3f800000; bias = 0;
        out_ready = 1; cycle = 0; stability_errors = 0; stall_prev = 0; in_count = 0; out_count = 0; lfsr = 16'hBEEF;
        bp_mode = 0;
        if (!$value$plusargs("VEC_FILE=%s", vec_file)) begin $display("ERROR: no VEC_FILE"); $finish(1); end
        if (!$value$plusargs("OUT_FILE=%s", out_file)) begin $display("ERROR: no OUT_FILE"); $finish(1); end
        if (!$value$plusargs("MAX_CYCLES=%d", maxcycles)) maxcycles = 5000000;
        if (!$value$plusargs("BP=%d", bp_mode)) bp_mode = 0;
        fin = $fopen(vec_file, "r");
        fout = $fopen(out_file, "w");
        if (fin == 0 || fout == 0) begin $display("ERROR: file open failed"); $finish(1); end
        #20; rst_n = 1; @(negedge clk);

        rc = $fscanf(fin, "%h %h %h %h %h %d\n", vmode, vs, vb, vd, vt, vl);
        while (rc == 6) begin
            in_valid = 1; mode = vmode; scale = vs; bias = vb;
            in_data = vd; in_tag = vt; in_last = vl;
            @(posedge clk);
            while (!in_ready) @(posedge clk);
            in_cycle[vt] = cycle;
            in_count = in_count + 1;
            @(negedge clk);
            rc = $fscanf(fin, "%h %h %h %h %h %d\n", vmode, vs, vb, vd, vt, vl);
        end
        in_valid = 0;
        while (out_count < in_count && cycle <= maxcycles) @(posedge clk);
        if (out_count != in_count) begin
            $display("MISMATCH_COUNT in=%0d out=%0d", in_count, out_count);
            $fclose(fout); $finish(2);
        end
        $display("DONE fma in=%0d out=%0d cycles=%0d", in_count, out_count, cycle);
        $display("STABILITY_ERRORS=%0d", stability_errors);
        $fclose(fout);
        $finish(0);
    end
endmodule
