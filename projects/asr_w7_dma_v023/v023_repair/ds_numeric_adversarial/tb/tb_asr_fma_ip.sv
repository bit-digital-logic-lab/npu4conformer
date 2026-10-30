`timescale 1ns/1ps
// File-driven audit of the asr_fma_ip-compatible wrapper (nonblocking AXIS).
// Input : "mode scale bias data tag last"  (mode 0 rows are bypassed as a=1)
// Output: "cycle result"
module tb_asr_fma_ip;
    reg aclk, aresetn;
    reg av, bv, cv;
    reg [31:0] ad, bd, cd;
    wire rv;
    wire [31:0] rd;
    integer fin, fout, rc, cycle, maxcycles, in_count, out_count;
    reg [1:0] vmode;
    reg [31:0] vs, vb, vd;
    reg [15:0] vt;
    reg vl;
    string vec_file, out_file;

    always #4 aclk = ~aclk;

    asr_fma_ip dut (
        .aclk(aclk), .aresetn(aresetn),
        .s_axis_a_tvalid(av), .s_axis_a_tdata(ad),
        .s_axis_b_tvalid(bv), .s_axis_b_tdata(bd),
        .s_axis_c_tvalid(cv), .s_axis_c_tdata(cd),
        .m_axis_result_tvalid(rv), .m_axis_result_tdata(rd));

    always @(posedge aclk) begin
        if (aresetn) begin
            cycle <= cycle + 1;
            if (cycle > maxcycles) begin
                $display("WATCHDOG: asr_fma_ip timeout cycle=%0d in=%0d out=%0d", cycle, in_count, out_count);
                $fclose(fout); $finish(2);
            end
        end
    end

    always @(posedge aclk) begin
        if (aresetn && rv) begin
            $fwrite(fout, "%0d %08x\n", cycle, rd);
            out_count <= out_count + 1;
        end
    end

    initial begin
        aclk = 0; aresetn = 0; av = 0; bv = 0; cv = 0; ad = 0; bd = 0; cd = 0;
        cycle = 0; in_count = 0; out_count = 0;
        if (!$value$plusargs("VEC_FILE=%s", vec_file)) begin $display("ERROR: no VEC_FILE"); $finish(1); end
        if (!$value$plusargs("OUT_FILE=%s", out_file)) begin $display("ERROR: no OUT_FILE"); $finish(1); end
        if (!$value$plusargs("MAX_CYCLES=%d", maxcycles)) maxcycles = 5000000;
        fin = $fopen(vec_file, "r"); fout = $fopen(out_file, "w");
        if (fin == 0 || fout == 0) begin $display("ERROR: file open failed"); $finish(1); end
        #20; aresetn = 1; @(negedge aclk);

        rc = $fscanf(fin, "%h %h %h %h %h %d\n", vmode, vs, vb, vd, vt, vl);
        while (rc == 6) begin
            if (vmode == 0) begin
                ad = vd; bd = 32'h3f800000; cd = 0;
            end else if (vmode == 2) begin
                ad = vd; bd = vs; cd = 0;
            end else begin
                ad = vd; bd = vs; cd = vb;
            end
            av = 1; bv = 1; cv = 1;
            @(posedge aclk);
            in_count = in_count + 1;
            @(negedge aclk);
            rc = $fscanf(fin, "%h %h %h %h %h %d\n", vmode, vs, vb, vd, vt, vl);
        end
        av = 0; bv = 0; cv = 0;
        while (out_count < in_count && cycle <= maxcycles) @(posedge aclk);
        $display("DONE asr_fma_ip in=%0d out=%0d cycles=%0d", in_count, out_count, cycle);
        $fclose(fout);
        $finish(out_count == in_count ? 0 : 2);
    end
endmodule
