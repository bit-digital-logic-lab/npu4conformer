`timescale 1ns/1ps
// Preserved-latency check: asr_fma_ip wrapper = 7 cycles (II=1) and
// epilogue_lane conversion-only bypass = 12 cycles (2+7+1+2, II=1).
module tb_wrap_lane_lat;
    localparam integer N = 24;

    reg clk = 0;
    always #5 clk = ~clk;
    reg rst_n = 0;
    integer cyc = 0, errors = 0;
    always @(posedge clk) if (rst_n) cyc <= cyc + 1;

    // ---------------- asr_fma_ip wrapper ----------------
    reg av = 0, bv = 0, cv = 0;
    reg [31:0] ad = 0, bd = 0, cd = 0;
    wire rv;
    wire [31:0] rd;
    integer w_in = -1, w_first = -1, w_last = -1, w_count = 0;

    asr_fma_ip u_wrap (
        .aclk(clk), .aresetn(rst_n),
        .s_axis_a_tvalid(av), .s_axis_a_tdata(ad),
        .s_axis_b_tvalid(bv), .s_axis_b_tdata(bd),
        .s_axis_c_tvalid(cv), .s_axis_c_tdata(cd),
        .m_axis_result_tvalid(rv), .m_axis_result_tdata(rd)
    );

    always @(posedge clk) begin
        if (rst_n && rv) begin
            if (rd !== 32'h40000000) begin
                $display("[FAIL] wrapper data got=%08x exp=40000000", rd);
                errors = errors + 1;
            end
            if (w_first < 0) w_first = cyc;
            w_last = cyc;
            w_count = w_count + 1;
        end
    end

    // ---------------- epilogue_lane bypass ----------------
    reg lv = 0;
    wire lr;
    reg signed [47:0] lc48 = 0;
    reg [15:0] ltag = 0;
    reg llast = 0;
    reg [1:0] lmode = 0;
    reg lrelu = 0;
    reg [31:0] lscale = 32'h3f800000, lbias = 0;
    wire lov;
    reg lo_ready = 1;
    wire signed [15:0] la16;
    wire [15:0] lotag;
    wire lolast;

    epilogue_lane u_lane (
        .clk(clk), .rst_n(rst_n), .flush(1'b0),
        .cfg_fma_mode(lmode), .cfg_relu_en(lrelu),
        .cfg_scale(lscale), .cfg_bias(lbias),
        .in_valid(lv), .in_ready(lr), .in_c48(lc48),
        .in_tag(ltag), .in_last(llast),
        .out_valid(lov), .out_ready(lo_ready), .out_a16(la16),
        .out_tag(lotag), .out_last(lolast),
        .fp32_valid(), .fp32_data()
    );

    integer l_in_cyc [0:255];
    integer l_out_cyc [0:255];
    integer l_seen [0:255];
    integer l_count = 0;
    integer i;

    always @(posedge clk) begin
        if (rst_n && lov && lo_ready) begin
            if (la16 !== 16'sd1) begin
                $display("[FAIL] lane data tag=%0d got=%0d exp=1", lotag, la16);
                errors = errors + 1;
            end
            if (lotag < N) begin
                l_out_cyc[lotag] = cyc;
                l_seen[lotag] = 1;
            end
            l_count = l_count + 1;
        end
    end

    task do_reset;
        begin
            rst_n = 0; av = 0; bv = 0; cv = 0; lv = 0;
            repeat (3) @(negedge clk);
            rst_n = 1;
            repeat (2) @(negedge clk);
        end
    endtask

    initial begin
        for (i = 0; i < 256; i = i + 1) begin
            l_in_cyc[i] = -1; l_out_cyc[i] = -1; l_seen[i] = 0;
        end
        do_reset;

        // ---- wrapper: continuous 1.0*2.0+0 = 2.0, latency 7 ----
        for (i = 0; i < N; i = i + 1) begin
            @(negedge clk);
            av = 1; bv = 1; cv = 1;
            ad = 32'h3f800000; bd = 32'h40000000; cd = 32'h00000000;
            @(posedge clk);
            if (i == 0) w_in = cyc;
        end
        @(negedge clk); av = 0; bv = 0; cv = 0;
        wait (w_count == N);
        @(posedge clk);
        if (w_in < 0 || w_first < 0) begin
            $display("[FAIL] wrapper produced no output");
            errors = errors + 1;
        end else begin
            if ((w_first - w_in) != 7) begin
                $display("[FAIL] wrapper latency %0d != 7", w_first - w_in);
                errors = errors + 1;
            end
            if ((w_last - w_first + 1) != N) begin
                $display("[FAIL] wrapper II span %0d != %0d", w_last - w_first + 1, N);
                errors = errors + 1;
            end else begin
                $display("[PASS] wrapper latency=7 II=1 n=%0d", N);
            end
        end

        // ---- lane mode 0 bypass: 1 -> 1, latency 12, II=1 ----
        lmode = 2'd0; lrelu = 0; lscale = 32'h3f800000; lbias = 0;
        for (i = 0; i < N; i = i + 1) begin
            @(negedge clk);
            if (lr !== 1'b1) begin
                $display("[FAIL] lane in_ready low at beat %0d", i);
                errors = errors + 1;
            end
            lv = 1; lc48 = 48'sd1; ltag = i[15:0]; llast = (i == N - 1);
            @(posedge clk);
            l_in_cyc[i] = cyc;
        end
        @(negedge clk); lv = 0; llast = 0;
        wait (l_count == N);
        @(posedge clk);
        for (i = 0; i < N; i = i + 1) begin
            if (!l_seen[i]) begin
                $display("[FAIL] lane missing tag %0d", i);
                errors = errors + 1;
            end else if ((l_out_cyc[i] - l_in_cyc[i]) != 12) begin
                $display("[FAIL] lane latency tag %0d = %0d != 12", i,
                         l_out_cyc[i] - l_in_cyc[i]);
                errors = errors + 1;
            end
        end
        if (l_count == N && (l_out_cyc[N-1] - l_out_cyc[0] + 1) != N) begin
            $display("[FAIL] lane II span %0d != %0d",
                     l_out_cyc[N-1] - l_out_cyc[0] + 1, N);
            errors = errors + 1;
        end else if (l_count == N) begin
            $display("[PASS] lane mode0 bypass latency=12 II=1 n=%0d", N);
        end

        $display("WRAP_LANE_ERRORS=%0d", errors);
        if (errors == 0) $finish;
        else $fatal(1, "wrapper/lane latency test failed");
    end

    initial begin
        #200000;
        $display("WATCHDOG: tb_wrap_lane_lat timeout");
        $fatal(1, "watchdog");
    end
endmodule
