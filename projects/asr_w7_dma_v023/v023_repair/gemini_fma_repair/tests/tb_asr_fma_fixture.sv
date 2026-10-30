`timescale 1ns/1ps

module tb_asr_fma_fixture;

    reg clk = 0;
    always #5 clk = ~clk;

    reg rst_n = 0;

    reg        s_axis_a_tvalid = 0;
    reg [31:0] s_axis_a_tdata  = 0;
    reg        s_axis_b_tvalid = 0;
    reg [31:0] s_axis_b_tdata  = 0;
    reg        s_axis_c_tvalid = 0;
    reg [31:0] s_axis_c_tdata  = 0;

    wire        m_axis_result_tvalid;
    wire [31:0] m_axis_result_tdata;

    asr_fma_ip dut (
        .aclk                (clk),
        .aresetn             (rst_n),
        .s_axis_a_tvalid     (s_axis_a_tvalid),
        .s_axis_a_tdata      (s_axis_a_tdata),
        .s_axis_b_tvalid     (s_axis_b_tvalid),
        .s_axis_b_tdata      (s_axis_b_tdata),
        .s_axis_c_tvalid     (s_axis_c_tvalid),
        .s_axis_c_tdata      (s_axis_c_tdata),
        .m_axis_result_tvalid(m_axis_result_tvalid),
        .m_axis_result_tdata (m_axis_result_tdata)
    );

    // Watchdog timer: 1,000,000ns (1ms)
    initial begin
        #1000000;
        $display("[WATCHDOG] FATAL: tb_asr_fma_fixture timed out!");
        $finish(2);
    end

    reg [7:0] mem [0:(1<<18)-1];
    reg [7:0] gold_mem [0:4003];

    integer i;
    integer errors;
    integer pass_count;
    reg [31:0] wa, wb, wc, wgold;

    initial begin
        errors = 0;
        pass_count = 0;
        $readmemh("/home/yang/Desktop/项目/work/tests/fma_fixture/memory.hex", mem);
        $readmemh("/home/yang/Desktop/项目/work/tests/fma_fixture/gold.hex", gold_mem);

        #20;
        @(posedge clk);
        rst_n = 1;
        #20;
        @(posedge clk);

        $display("=== STARTING ASR_FMA_IP FIXTURE TEST (1001 VECTORS) ===");

        for (i = 0; i < 1001; i = i + 1) begin
            // Extract little-endian float words
            wa = {mem[i*4 + 3], mem[i*4 + 2], mem[i*4 + 1], mem[i*4 + 0]};
            wb = {mem[16'h1000 + i*4 + 3], mem[16'h1000 + i*4 + 2], mem[16'h1000 + i*4 + 1], mem[16'h1000 + i*4 + 0]};
            wc = {mem[16'h2000 + i*4 + 3], mem[16'h2000 + i*4 + 2], mem[16'h2000 + i*4 + 1], mem[16'h2000 + i*4 + 0]};
            wgold = {gold_mem[i*4 + 3], gold_mem[i*4 + 2], gold_mem[i*4 + 1], gold_mem[i*4 + 0]};

            s_axis_a_tvalid <= 1'b1;
            s_axis_a_tdata  <= wa;
            s_axis_b_tvalid <= 1'b1;
            s_axis_b_tdata  <= wb;
            s_axis_c_tvalid <= 1'b1;
            s_axis_c_tdata  <= wc;
            @(posedge clk);
            s_axis_a_tvalid <= 1'b0;
            s_axis_b_tvalid <= 1'b0;
            s_axis_c_tvalid <= 1'b0;

            while (!m_axis_result_tvalid) @(posedge clk);

            if (m_axis_result_tdata !== wgold) begin
                $display("[FAIL] idx %0d: a=%h b=%h c=%h got=%h exp=%h", i, wa, wb, wc, m_axis_result_tdata, wgold);
                errors = errors + 1;
            end else begin
                pass_count = pass_count + 1;
            end
        end

        $display("=== FIXTURE RESULTS: %0d matches, %0d errors ===", pass_count, errors);
        if (errors == 0 && pass_count == 1001) begin
            $display("V022_OFFICIAL_VENDOR_FMA_PASS: 1001/1001 EXACT MATCHES");
            $finish(0);
        end else begin
            $display("FIXTURE TEST FAILED!");
            $finish(1);
        end
    end

endmodule
