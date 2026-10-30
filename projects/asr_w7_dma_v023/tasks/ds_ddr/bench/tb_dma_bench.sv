`timescale 1ns/1ps
// baseline(axi_dma_v019) 与 candidate(axi_dma_stream_v1) 同负载、同随机 DDR 条件对比。
// 两个 DUT 各自接一个参数完全相同的 AXI128 共享 DDR BFM（独立存储、同种子），
// 因此互不干扰，但随机延迟/背压/换向/4KiB 规则完全一致。
// 只验证搬运与协议，不包含矩阵数值；读数据与独立地址模式逐字节比对，
// 写数据在 BFM 存储中逐字节回读比对。
module tb_dma_bench #(
  parameter integer MODE = 0,          // 0=读 1=写 2=混合 3=短读 4=跨4KiB 5=长读
  parameter integer NBEATS = 4096,     // 单请求拍数
  parameter integer NREQ = 1,          // 请求数
  parameter integer BASE = 32'h04000000,
  parameter integer MAX_OUT = 4,
  parameter integer FIFO_BEATS = 64,
  parameter integer BURST_BEATS = 16,
  parameter integer LAT_MIN = 8,
  parameter integer LAT_MAX = 40,
  parameter integer BLAT_MIN = 2,
  parameter integer BLAT_MAX = 12,
  parameter integer TURNAROUND = 2,
  parameter integer READY_STALL_PCT = 20,
  parameter integer SEED = 1,
  parameter integer R_STALL_PCT = 10,
  parameter integer W_STALL_PCT = 10
);
  reg clk = 0;
  always #4 clk = ~clk; // 125MHz 逻辑时钟；频率目标另算，不声称物理时序
  reg rst_n = 0;

  // ---------------- baseline DUT ----------------
  reg  b_req_valid = 0, b_req_write = 0;
  wire b_req_ready;
  reg  [31:0] b_req_addr = BASE;
  reg  [15:0] b_req_beats = 0;
  wire b_rd_valid, b_wr_ready;
  reg  b_rd_ready = 0;
  wire [127:0] b_rd_data;
  wire [15:0] b_rd_index;
  reg  b_wr_valid = 0;
  reg  [127:0] b_wr_data = 0;
  reg  [15:0] b_wr_strb = 0;
  wire [15:0] b_wr_index;
  wire b_done, b_error;
  wire [31:0] b_rd_bytes, b_wr_bytes, b_rd_bursts, b_wr_bursts;

  wire [79:0] b_araddr, b_awaddr;
  wire [15:0] b_arlen, b_awlen;
  wire [5:0]  b_arsize, b_awsize;
  wire [3:0]  b_arburst, b_awburst;
  wire [1:0]  b_arvalid, b_awvalid;
  wire [1:0]  b_arready, b_awready;
  wire [255:0] b_rdata, b_wdata;
  wire [31:0] b_wstrb;
  wire [3:0]  b_rresp, b_bresp;
  wire [1:0]  b_rlast, b_rvalid, b_rready, b_wlast, b_wvalid, b_wready, b_bvalid, b_bready;

  axi_dma_v019 baseline(
    .clk(clk), .rst_n(rst_n),
    .request_valid(b_req_valid), .request_ready(b_req_ready), .request_write(b_req_write),
    .request_address(b_req_addr), .request_beats(b_req_beats),
    .read_valid(b_rd_valid), .read_ready(b_rd_ready), .read_data(b_rd_data), .read_index(b_rd_index),
    .write_valid(b_wr_valid), .write_ready(b_wr_ready), .write_data(b_wr_data),
    .write_strobe(b_wr_strb), .write_index(b_wr_index),
    .done(b_done), .error(b_error),
    .read_bytes(b_rd_bytes), .write_bytes(b_wr_bytes), .read_bursts(b_rd_bursts), .write_bursts(b_wr_bursts),
    .m_axi_araddr(b_araddr[39:0]), .m_axi_arlen(b_arlen[7:0]), .m_axi_arsize(b_arsize[2:0]),
    .m_axi_arburst(b_arburst[1:0]), .m_axi_arcache(), .m_axi_arprot(),
    .m_axi_arvalid(b_arvalid[0]), .m_axi_arready(b_arready[0]),
    .m_axi_rdata(b_rdata[127:0]), .m_axi_rresp(b_rresp[1:0]), .m_axi_rlast(b_rlast[0]),
    .m_axi_rvalid(b_rvalid[0]), .m_axi_rready(b_rready[0]),
    .m_axi_awaddr(b_awaddr[39:0]), .m_axi_awlen(b_awlen[7:0]), .m_axi_awsize(b_awsize[2:0]),
    .m_axi_awburst(b_awburst[1:0]), .m_axi_awcache(), .m_axi_awprot(),
    .m_axi_awvalid(b_awvalid[1]), .m_axi_awready(b_awready[1]),
    .m_axi_wdata(b_wdata[255:128]), .m_axi_wstrb(b_wstrb[31:16]),
    .m_axi_wlast(b_wlast[1]), .m_axi_wvalid(b_wvalid[1]), .m_axi_wready(b_wready[1]),
    .m_axi_bresp(b_bresp[3:2]), .m_axi_bvalid(b_bvalid[1]), .m_axi_bready(b_bready[1])
  );

  axi128_ddr_bfm #(.PORTS(2), .MAX_OUT(MAX_OUT), .WFIFO(512),
    .LAT_MIN(LAT_MIN), .LAT_MAX(LAT_MAX), .BLAT_MIN(BLAT_MIN), .BLAT_MAX(BLAT_MAX),
    .TURNAROUND(TURNAROUND), .READY_STALL_PCT(READY_STALL_PCT), .SEED(SEED),
    .R_STALL_PCT(R_STALL_PCT), .W_STALL_PCT(W_STALL_PCT)) ddr_b(
    .clk(clk), .rst_n(rst_n),
    .araddr({40'd0, b_araddr[39:0]}), .arlen({8'd0, b_arlen[7:0]}),
    .arsize({3'd0, b_arsize[2:0]}), .arburst({2'd0, b_arburst[1:0]}),
    .arvalid({1'b0, b_arvalid[0]}), .arready(b_arready),
    .rdata(b_rdata), .rresp(b_rresp),
    .rlast(b_rlast), .rvalid(b_rvalid), .rready({1'b0, b_rready[0]}),
    .awaddr({b_awaddr[39:0], 40'd0}), .awlen({b_awlen[7:0], 8'd0}),
    .awsize({b_awsize[2:0], 3'd0}), .awburst({b_awburst[1:0], 2'd0}),
    .awvalid({b_awvalid[1], 1'b0}), .awready(b_awready),
    .wdata({b_wdata[255:128], 128'd0}), .wstrb({b_wstrb[31:16], 16'd0}),
    .wlast({b_wlast[1], 1'b0}), .wvalid({b_wvalid[1], 1'b0}), .wready(b_wready),
    .bresp(b_bresp), .bvalid(b_bvalid), .bready({b_bready[1], 1'b0}),
    .inject_read_error(2'd0), .inject_write_error(2'd0),
    .cycles(), .bus_read_beats(), .bus_write_beats(), .bus_idle_cycles(),
    .bus_turnaround_cycles(), .bus_busy_cycles(), .read_bursts(), .write_bursts(),
    .max_rd_out(), .max_wr_out(), .ar_stall_cycles(), .aw_stall_cycles(),
    .r_stall_cycles(), .w_stall_cycles()
  );

  // ---------------- candidate DUT ----------------
  reg  c_req_valid = 0, c_req_write = 0;
  wire c_req_ready;
  reg  [31:0] c_req_addr = BASE;
  reg  [15:0] c_req_beats = 0;
  wire c_rd_valid, c_wr_ready;
  reg  c_rd_ready = 0;
  wire [127:0] c_rd_data;
  wire [15:0] c_rd_index;
  reg  c_wr_valid = 0;
  reg  [127:0] c_wr_data = 0;
  reg  [15:0] c_wr_strb = 0;
  wire [15:0] c_wr_index;
  wire c_done, c_error;
  wire [31:0] c_rd_bytes, c_wr_bytes, c_rd_bursts, c_wr_bursts;

  wire [79:0] c_araddr, c_awaddr;
  wire [15:0] c_arlen, c_awlen;
  wire [5:0]  c_arsize, c_awsize;
  wire [3:0]  c_arburst, c_awburst;
  wire [1:0]  c_arvalid, c_awvalid;
  wire [1:0]  c_arready, c_awready;
  wire [255:0] c_rdata, c_wdata;
  wire [31:0] c_wstrb;
  wire [3:0]  c_rresp, c_bresp;
  wire [1:0]  c_rlast, c_rvalid, c_rready, c_wlast, c_wvalid, c_wready, c_bvalid, c_bready;

  axi_dma_stream_v1 #(.MAX_RD_OUT(MAX_OUT), .MAX_WR_OUT(MAX_OUT),
    .FIFO_BEATS(FIFO_BEATS), .BURST_BEATS(BURST_BEATS)) candidate(
    .clk(clk), .rst_n(rst_n),
    .request_valid(c_req_valid), .request_ready(c_req_ready), .request_write(c_req_write),
    .request_address(c_req_addr), .request_beats(c_req_beats),
    .read_valid(c_rd_valid), .read_ready(c_rd_ready), .read_data(c_rd_data), .read_index(c_rd_index),
    .write_valid(c_wr_valid), .write_ready(c_wr_ready), .write_data(c_wr_data),
    .write_strobe(c_wr_strb), .write_index(c_wr_index),
    .done(c_done), .error(c_error),
    .read_bytes(c_rd_bytes), .write_bytes(c_wr_bytes), .read_bursts(c_rd_bursts), .write_bursts(c_wr_bursts),
    .m_axi_araddr(c_araddr[39:0]), .m_axi_arlen(c_arlen[7:0]), .m_axi_arsize(c_arsize[2:0]),
    .m_axi_arburst(c_arburst[1:0]), .m_axi_arcache(), .m_axi_arprot(),
    .m_axi_arvalid(c_arvalid[0]), .m_axi_arready(c_arready[0]),
    .m_axi_rdata(c_rdata[127:0]), .m_axi_rresp(c_rresp[1:0]), .m_axi_rlast(c_rlast[0]),
    .m_axi_rvalid(c_rvalid[0]), .m_axi_rready(c_rready[0]),
    .m_axi_awaddr(c_awaddr[39:0]), .m_axi_awlen(c_awlen[7:0]), .m_axi_awsize(c_awsize[2:0]),
    .m_axi_awburst(c_awburst[1:0]), .m_axi_awcache(), .m_axi_awprot(),
    .m_axi_awvalid(c_awvalid[1]), .m_axi_awready(c_awready[1]),
    .m_axi_wdata(c_wdata[255:128]), .m_axi_wstrb(c_wstrb[31:16]),
    .m_axi_wlast(c_wlast[1]), .m_axi_wvalid(c_wvalid[1]), .m_axi_wready(c_wready[1]),
    .m_axi_bresp(c_bresp[3:2]), .m_axi_bvalid(c_bvalid[1]), .m_axi_bready(c_bready[1])
  );

  wire [63:0] cb_cycles, cb_rbeats, cb_wbeats, cb_idle, cb_turn, cb_busy, cb_rburst, cb_wburst;
  wire [63:0] cb_arstall, cb_awstall, cb_rstall, cb_wstall;
  wire [31:0] cb_maxrd, cb_maxwr;

  axi128_ddr_bfm #(.PORTS(2), .MAX_OUT(MAX_OUT), .WFIFO(512),
    .LAT_MIN(LAT_MIN), .LAT_MAX(LAT_MAX), .BLAT_MIN(BLAT_MIN), .BLAT_MAX(BLAT_MAX),
    .TURNAROUND(TURNAROUND), .READY_STALL_PCT(READY_STALL_PCT), .SEED(SEED),
    .R_STALL_PCT(R_STALL_PCT), .W_STALL_PCT(W_STALL_PCT)) ddr_c(
    .clk(clk), .rst_n(rst_n),
    .araddr({40'd0, c_araddr[39:0]}), .arlen({8'd0, c_arlen[7:0]}),
    .arsize({3'd0, c_arsize[2:0]}), .arburst({2'd0, c_arburst[1:0]}),
    .arvalid({1'b0, c_arvalid[0]}), .arready(c_arready),
    .rdata(c_rdata), .rresp(c_rresp),
    .rlast(c_rlast), .rvalid(c_rvalid), .rready({1'b0, c_rready[0]}),
    .awaddr({c_awaddr[39:0], 40'd0}), .awlen({c_awlen[7:0], 8'd0}),
    .awsize({c_awsize[2:0], 3'd0}), .awburst({c_awburst[1:0], 2'd0}),
    .awvalid({c_awvalid[1], 1'b0}), .awready(c_awready),
    .wdata({c_wdata[255:128], 128'd0}), .wstrb({c_wstrb[31:16], 16'd0}),
    .wlast({c_wlast[1], 1'b0}), .wvalid({c_wvalid[1], 1'b0}), .wready(c_wready),
    .bresp(c_bresp), .bvalid(c_bvalid), .bready({c_bready[1], 1'b0}),
    .inject_read_error(2'd0), .inject_write_error(2'd0),
    .cycles(cb_cycles), .bus_read_beats(cb_rbeats), .bus_write_beats(cb_wbeats),
    .bus_idle_cycles(cb_idle), .bus_turnaround_cycles(cb_turn), .bus_busy_cycles(cb_busy),
    .read_bursts(cb_rburst), .write_bursts(cb_wburst), .max_rd_out(cb_maxrd), .max_wr_out(cb_maxwr),
    .ar_stall_cycles(cb_arstall), .aw_stall_cycles(cb_awstall),
    .r_stall_cycles(cb_rstall), .w_stall_cycles(cb_wstall)
  );

  // ---------------- 数据检查 ----------------
  function automatic [7:0] exp_byte(input [39:0] a, input integer off);
    integer mi;
    begin
      if (a >= 40'h0004000000) mi = 262144 + (a - 40'h0004000000);
      else if (a >= 40'h0010000000) mi = 524288 + (a - 40'h0010000000);
      else mi = a - 40'h0003000000;
      exp_byte = (mi + off) * 8'h1d + 8'h13;
    end
  endfunction
  function automatic [127:0] pat_beat_at(input [39:0] a, input [15:0] idx);
    integer lane;
    begin
      for (lane = 0; lane < 16; lane = lane + 1) pat_beat_at[lane*8+:8] = exp_byte(a, idx*16 + lane);
    end
  endfunction

  integer errors_b = 0, errors_c = 0;
  integer beats_b = 0, beats_c = 0;
  reg [31:0] b_base_cur, c_base_cur;

  // 读消费：ready 常 1，逐拍与独立地址模式比对。
  always @(posedge clk) if (rst_n) begin
    if (b_rd_valid && b_rd_ready) begin
      for (integer lane = 0; lane < 16; lane = lane + 1)
        if (b_rd_data[lane*8+:8] !== exp_byte(b_base_cur, b_rd_index*16 + lane)) errors_b = errors_b + 1;
      beats_b = beats_b + 1;
    end
    if (c_rd_valid && c_rd_ready) begin
      for (integer lane = 0; lane < 16; lane = lane + 1)
        if (c_rd_data[lane*8+:8] !== exp_byte(c_base_cur, c_rd_index*16 + lane)) errors_c = errors_c + 1;
      beats_c = beats_c + 1;
    end
  end

  // ---------------- 驱动 ----------------
  integer b_cycles = 0, c_cycles = 0;
  integer b_done_req = 0, c_done_req = 0;
  integer k;

  task automatic issue_b(input integer wr, input [31:0] a, input [15:0] n);
    begin
      @(negedge clk);
      b_req_valid = 1; b_req_write = wr; b_req_addr = a; b_req_beats = n;
      while (!b_req_ready) @(negedge clk);
      @(posedge clk); // 接受
      @(negedge clk); b_req_valid = 0;
    end
  endtask
  task automatic issue_c(input integer wr, input [31:0] a, input [15:0] n);
    begin
      @(negedge clk);
      c_req_valid = 1; c_req_write = wr; c_req_addr = a; c_req_beats = n;
      while (!c_req_ready) @(negedge clk);
      @(posedge clk);
      @(negedge clk); c_req_valid = 0;
    end
  endtask

  // 写数据源：组合生成，避免与任务在同一 negedge 竞争。
  always @* begin
    b_wr_data = pat_beat_at(b_base_cur, b_wr_index);
    b_wr_strb = b_wr_valid ? 16'hffff : 16'h0000;
    c_wr_data = pat_beat_at(c_base_cur, c_wr_index);
    c_wr_strb = c_wr_valid ? 16'hffff : 16'h0000;
  end

  // 写完成后的存储回读比对（由任务在 done 后调用）。
  task automatic check_write_b(input [31:0] a, input integer n, output integer errs);
    integer j;
    begin
      errs = 0;
      for (j = 0; j < n * 16; j = j + 1)
        if (ddr_b.memory[ddr_b.mem_index(a) + j] !== exp_byte(a, j)) errs = errs + 1;
    end
  endtask
  task automatic check_write_c(input [31:0] a, input integer n, output integer errs);
    integer j;
    begin
      errs = 0;
      for (j = 0; j < n * 16; j = j + 1)
        if (ddr_c.memory[ddr_c.mem_index(a) + j] !== exp_byte(a, j)) errs = errs + 1;
    end
  endtask

  task automatic run_b;
    integer req, we_b, mode_l;
    reg [31:0] a;
    reg [15:0] n;
    begin
      b_cycles = 0;
      for (req = 0; req < NREQ; req = req + 1) begin
        mode_l = MODE;
        if (mode_l == 3) begin a = BASE + req * 32'h100; n = 16; end
        else if (mode_l == 4) begin a = BASE + 32'h3e800; n = 256; end
        else if (mode_l == 5) begin a = BASE + req * 32'h1000; n = 4096; end
        else begin a = BASE + req * ((NBEATS * 16 + 4095) & ~4095); n = NBEATS; end
        b_base_cur = a;
        if (mode_l == 1) begin
          issue_b(1, a, n); b_wr_valid = 1;
          while (!b_done) begin @(posedge clk); b_cycles = b_cycles + 1; end
          @(negedge clk); b_wr_valid = 0;
          check_write_b(a, n, we_b); errors_b = errors_b + we_b;
        end else if (mode_l == 2) begin
          if (req % 2 == 0) begin
            a = BASE + 32'h10000; b_base_cur = a;
            issue_b(0, a, n); b_rd_ready = 1;
            while (!b_done) begin @(posedge clk); b_cycles = b_cycles + 1; end
            @(negedge clk); b_rd_ready = 0;
          end else begin
            a = BASE + 32'h20000; b_base_cur = a;
            issue_b(1, a, n); b_wr_valid = 1;
            while (!b_done) begin @(posedge clk); b_cycles = b_cycles + 1; end
            @(negedge clk); b_wr_valid = 0;
            check_write_b(a, n, we_b); errors_b = errors_b + we_b;
          end
        end else begin
          issue_b(0, a, n); b_rd_ready = 1;
          while (!b_done) begin @(posedge clk); b_cycles = b_cycles + 1; end
          @(negedge clk); b_rd_ready = 0;
        end
        b_done_req = b_done_req + 1;
      end
    end
  endtask

  task automatic run_c;
    integer req, we_c, mode_l;
    reg [31:0] a;
    reg [15:0] n;
    begin
      c_cycles = 0;
      for (req = 0; req < NREQ; req = req + 1) begin
        mode_l = MODE;
        if (mode_l == 3) begin a = BASE + req * 32'h100; n = 16; end
        else if (mode_l == 4) begin a = BASE + 32'h3e800; n = 256; end
        else if (mode_l == 5) begin a = BASE + req * 32'h1000; n = 4096; end
        else begin a = BASE + req * ((NBEATS * 16 + 4095) & ~4095); n = NBEATS; end
        c_base_cur = a;
        if (mode_l == 1) begin
          issue_c(1, a, n); c_wr_valid = 1;
          while (!c_done) begin @(posedge clk); c_cycles = c_cycles + 1; end
          @(negedge clk); c_wr_valid = 0;
          check_write_c(a, n, we_c); errors_c = errors_c + we_c;
        end else if (mode_l == 2) begin
          if (req % 2 == 0) begin
            a = BASE + 32'h10000; c_base_cur = a;
            issue_c(0, a, n); c_rd_ready = 1;
            while (!c_done) begin @(posedge clk); c_cycles = c_cycles + 1; end
            @(negedge clk); c_rd_ready = 0;
          end else begin
            a = BASE + 32'h20000; c_base_cur = a;
            issue_c(1, a, n); c_wr_valid = 1;
            while (!c_done) begin @(posedge clk); c_cycles = c_cycles + 1; end
            @(negedge clk); c_wr_valid = 0;
            check_write_c(a, n, we_c); errors_c = errors_c + we_c;
          end
        end else begin
          issue_c(0, a, n); c_rd_ready = 1;
          while (!c_done) begin @(posedge clk); c_cycles = c_cycles + 1; end
          @(negedge clk); c_rd_ready = 0;
        end
        c_done_req = c_done_req + 1;
      end
    end
  endtask

  integer total_cycles;
  initial begin
    b_rd_ready = 0; c_rd_ready = 0;
    repeat (8) @(posedge clk);
    rst_n = 1;
    repeat (2) @(posedge clk);
    fork
      run_b();
      run_c();
    join
    repeat (4) @(posedge clk);
    total_cycles = b_cycles > c_cycles ? b_cycles : c_cycles;
    $display("BENCH mode=%0d nbeats=%0d nreq=%0d maxout=%0d fifo=%0d burst=%0d lat=%0d..%0d turn=%0d stall=%0d seed=%0d",
             MODE, NBEATS, NREQ, MAX_OUT, FIFO_BEATS, BURST_BEATS, LAT_MIN, LAT_MAX, TURNAROUND, READY_STALL_PCT, SEED);
    $display("BASE cycles=%0d rd_beats=%0d wr_beats=%0d rd_bytes=%0d wr_bytes=%0d rd_bursts=%0d wr_bursts=%0d errs=%0d error=%0d bus_busy=%0d bus_idle=%0d bus_turn=%0d",
             b_cycles, beats_b, ddr_b.bus_write_beats, b_rd_bytes, b_wr_bytes, b_rd_bursts, b_wr_bursts,
             errors_b, b_error, ddr_b.bus_busy_cycles, ddr_b.bus_idle_cycles, ddr_b.bus_turnaround_cycles);
    $display("CAND cycles=%0d rd_beats=%0d wr_beats=%0d rd_bytes=%0d wr_bytes=%0d rd_bursts=%0d wr_bursts=%0d errs=%0d error=%0d bus_busy=%0d bus_idle=%0d bus_turn=%0d maxrd=%0d maxwr=%0d",
             c_cycles, beats_c, ddr_c.bus_write_beats, c_rd_bytes, c_wr_bytes, c_rd_bursts, c_wr_bursts,
             errors_c, c_error, ddr_c.bus_busy_cycles, ddr_c.bus_idle_cycles, ddr_c.bus_turnaround_cycles,
             cb_maxrd, cb_maxwr);
    if (errors_b != 0 || errors_c != 0) $fatal(1, "DATA MISMATCH baseline=%0d candidate=%0d", errors_b, errors_c);
    if (b_done_req != NREQ || c_done_req != NREQ) $fatal(1, "REQUEST COUNT");
    $display("BENCH_PASS");
    $finish;
  end
endmodule
