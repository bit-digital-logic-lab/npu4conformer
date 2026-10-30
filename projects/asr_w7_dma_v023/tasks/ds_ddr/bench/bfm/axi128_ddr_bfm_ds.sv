`timescale 1ns/1ps
// 参数化 AXI4-128 共享 DDR 存储端 BFM（逻辑模型，不是板级 DDR 时序模型）。
// 建模内容：
//  - 每端口独立 AR/AW/W/R/B 握手；AR/AW 可多在途，R/B 按端口保序。
//  - 可配随机 AR/AW 接受阻塞、首拍读延迟、写响应延迟、R/W 背压。
//  - 全端口共享一条 128-bit 数据总线：每周期最多 1 拍（读或写），
//    读写换向有可配空拍；任何测量都不会超过共享总线可达界。
//  - 4KiB 边界、INCR/16B、WLAST、RLAST、写 strobe、错误响应检查。
//  - 错误只注入响应位；已接受事务仍必须被排空，BFM 不取消。
// 地址窗口（各 256KiB，互不重叠）：
//  0x0300_0000..0x0303_FFFF -> 0
//  0x0400_0000..0x0403_FFFF -> 256KiB
//  0x1000_0000..0x1003_FFFF -> 512KiB
module axi128_ddr_bfm #(
  parameter integer PORTS = 2,
  parameter integer MAX_OUT = 8,          // 每端口 AR 或 AW 队列深度
  parameter integer WFIFO = 512,          // 每端口待写拍缓冲
  parameter integer LAT_MIN = 8,
  parameter integer LAT_MAX = 40,
  parameter integer BLAT_MIN = 2,
  parameter integer BLAT_MAX = 12,
  parameter integer TURNAROUND = 2,
  parameter integer READY_STALL_PCT = 20,
  parameter integer R_STALL_PCT = 10,     // 由测试平台驱动 rready 使用；BFM 只统计
  parameter integer W_STALL_PCT = 10,     // 同上
  parameter integer SEED = 1
)(
  input wire clk, rst_n,
  input wire [PORTS*40-1:0] araddr, input wire [PORTS*8-1:0] arlen,
  input wire [PORTS*3-1:0] arsize, input wire [PORTS*2-1:0] arburst,
  input wire [PORTS-1:0] arvalid, output wire [PORTS-1:0] arready,
  output wire [PORTS*128-1:0] rdata, output wire [PORTS*2-1:0] rresp,
  output wire [PORTS-1:0] rlast, rvalid, input wire [PORTS-1:0] rready,
  input wire [PORTS*40-1:0] awaddr, input wire [PORTS*8-1:0] awlen,
  input wire [PORTS*3-1:0] awsize, input wire [PORTS*2-1:0] awburst,
  input wire [PORTS-1:0] awvalid, output wire [PORTS-1:0] awready,
  input wire [PORTS*128-1:0] wdata, input wire [PORTS*16-1:0] wstrb,
  input wire [PORTS-1:0] wlast, wvalid, output wire [PORTS-1:0] wready,
  output wire [PORTS*2-1:0] bresp, output wire [PORTS-1:0] bvalid, input wire [PORTS-1:0] bready,
  input wire [PORTS-1:0] inject_read_error, inject_write_error,
  output reg [63:0] cycles, bus_read_beats, bus_write_beats,
  output reg [63:0] bus_idle_cycles, bus_turnaround_cycles, bus_busy_cycles,
  output reg [63:0] read_bursts, write_bursts,
  output reg [31:0] max_rd_out, max_wr_out,
  output reg [63:0] ar_stall_cycles, aw_stall_cycles, r_stall_cycles, w_stall_cycles
);
  localparam integer MEM_BYTES = 3*262144;

  reg [7:0] memory [0:MEM_BYTES-1];
  integer mi;
  initial begin
    for (mi = 0; mi < MEM_BYTES; mi = mi + 1) memory[mi] = (mi * 8'h1d + 8'h13);
  end

  function automatic [19:0] mem_index(input [39:0] a);
    begin
      if (a >= 40'h0003000000 && a < 40'h0003040000) mem_index = a - 40'h0003000000;
      else if (a >= 40'h0004000000 && a < 40'h0004040000) mem_index = 20'd262144 + (a - 40'h0004000000);
      else if (a >= 40'h0010000000 && a < 40'h0010040000) mem_index = 20'd524288 + (a - 40'h0010000000);
      else mem_index = 20'hfffff;
    end
  endfunction
  function automatic valid_address(input [39:0] a);
    begin
      valid_address = (a >= 40'h0003000000 && a < 40'h0003040000) ||
                      (a >= 40'h0004000000 && a < 40'h0004040000) ||
                      (a >= 40'h0010000000 && a < 40'h0010040000);
    end
  endfunction
  function automatic [127:0] read_word(input [39:0] a, input [8:0] beat);
    integer lane;
    begin
      for (lane = 0; lane < 16; lane = lane + 1)
        read_word[lane*8+:8] = memory[mem_index(a) + beat*16 + lane];
    end
  endfunction

  // ---------------- 随机源 ----------------
  reg [31:0] lfsr;
  function automatic [31:0] rnd;
    begin
      rnd = lfsr;
      lfsr = {lfsr[30:0], lfsr[31]^lfsr[21]^lfsr[1]^lfsr[0]};
    end
  endfunction
  function automatic integer chance(input integer pct);
    begin
      chance = (pct > 0) && ((rnd() % 100) < pct);
    end
  endfunction

  // ---------------- 每端口 AR / AW 队列 ----------------
  reg [39:0] rd_addr [0:PORTS*MAX_OUT-1];
  reg [8:0]  rd_len  [0:PORTS*MAX_OUT-1];
  reg [15:0] rd_lat  [0:PORTS*MAX_OUT-1];
  reg        rd_err  [0:PORTS*MAX_OUT-1];
  reg        rd_v    [0:PORTS*MAX_OUT-1];
  integer rd_head [0:PORTS-1], rd_tail [0:PORTS-1], rd_cnt [0:PORTS-1];
  reg [8:0]  rd_beat [0:PORTS-1];
  reg        ar_block [0:PORTS-1];

  reg [39:0] aw_addr [0:PORTS*MAX_OUT-1];
  reg [8:0]  aw_len  [0:PORTS*MAX_OUT-1];
  reg [15:0] aw_lat  [0:PORTS*MAX_OUT-1];
  reg        aw_err  [0:PORTS*MAX_OUT-1];
  reg        aw_v    [0:PORTS*MAX_OUT-1];
  integer aw_head [0:PORTS-1], aw_tail [0:PORTS-1], aw_cnt [0:PORTS-1];
  reg [8:0]  aw_beat [0:PORTS-1];
  reg        aw_block [0:PORTS-1];
  reg        w_block  [0:PORTS-1];

  reg [127:0] wf_data [0:PORTS*WFIFO-1];
  reg [15:0]  wf_strb [0:PORTS*WFIFO-1];
  reg         wf_last [0:PORTS*WFIFO-1];
  integer wf_head [0:PORTS-1], wf_tail [0:PORTS-1], wf_cnt [0:PORTS-1];

  // 每端口 B 响应队列：允许多个 AW 在途时各自按序返回 B。
  reg [15:0] bq_lat [0:PORTS*MAX_OUT-1];
  reg        bq_err [0:PORTS*MAX_OUT-1];
  reg        bq_v   [0:PORTS*MAX_OUT-1];
  integer    bq_head [0:PORTS-1], bq_tail [0:PORTS-1], bq_cnt [0:PORTS-1];

  // ---------------- 共享总线仲裁 ----------------
  reg [1:0] last_dir;       // 0=无, 1=读, 2=写
  reg [31:0] rr;
  reg [7:0]  turn_cd;
  reg [PORTS-1:0] grant_r, grant_w;

  wire [PORTS-1:0] rd_servable, wr_servable;
  wire [PORTS-1:0] w_push = wvalid & wready;
  wire [PORTS-1:0] w_pop = grant_w;
  wire [PORTS-1:0] b_push;
  wire [PORTS-1:0] b_pop = bvalid & bready;
  wire [PORTS-1:0] r_pop;
  genvar p;
  generate
    for (p = 0; p < PORTS; p = p + 1) begin : g_bpush
      assign b_push[p] = grant_w[p] &&
             (aw_beat[p] + 1 == aw_len[p*MAX_OUT+aw_head[p]]);
      assign r_pop[p] = rvalid[p] && rready[p] &&
             (rd_beat[p] + 1 == rd_len[p*MAX_OUT+rd_head[p]]);
    end
  endgenerate
  generate
    for (p = 0; p < PORTS; p = p + 1) begin : g_port
      assign arready[p] = rst_n && (rd_cnt[p] < MAX_OUT) && !ar_block[p];
      assign awready[p] = rst_n && (aw_cnt[p] < MAX_OUT) && (bq_cnt[p] < MAX_OUT) && !aw_block[p];
      assign rd_servable[p] = rd_cnt[p] != 0 && rd_lat[p*MAX_OUT+rd_head[p]] == 0 && rready[p];
      assign wr_servable[p] = aw_cnt[p] != 0 && wf_cnt[p] != 0;
      assign rvalid[p] = rst_n && grant_r[p];
      assign rlast[p]  = rd_beat[p] + 1 == rd_len[p*MAX_OUT+rd_head[p]];
      assign rresp[p*2+:2] = rd_err[p*MAX_OUT+rd_head[p]] ? 2'b10 : 2'b00;
      assign rdata[p*128+:128] = read_word(rd_addr[p*MAX_OUT+rd_head[p]], rd_beat[p]);
      assign wready[p] = rst_n && (wf_cnt[p] < WFIFO) && !w_block[p];
      assign bvalid[p] = rst_n && (bq_cnt[p] != 0) &&
                         (bq_lat[p*MAX_OUT+bq_head[p]] == 0);
      assign bresp[p*2+:2] = bq_err[p*MAX_OUT+bq_head[p]] ? 2'b10 : 2'b00;
    end
  endgenerate

  // 组合仲裁：读写方向交替，端口轮转。单方向可服务时不会空转。
  integer q;
  reg found;
  reg dir_pref;
  always @* begin
    grant_r = 0; grant_w = 0; found = 0; dir_pref = 1'b1;
    if (turn_cd == 0) begin
      // 保持当前方向直到该方向无可服务拍，再换向并付 turnaround；
      // 不能每拍交替，否则会把共享总线人为限制在 50%。
      if (last_dir == 2) dir_pref = 1'b0;
      else dir_pref = 1'b1;
      if (dir_pref && (|rd_servable)) begin
        for (q = 0; q < PORTS; q = q + 1)
          if (!found && rd_servable[(rr+q)%PORTS]) begin grant_r[(rr+q)%PORTS] = 1'b1; found = 1; end
      end else if (!dir_pref && (|wr_servable)) begin
        for (q = 0; q < PORTS; q = q + 1)
          if (!found && wr_servable[(rr+q)%PORTS]) begin grant_w[(rr+q)%PORTS] = 1'b1; found = 1; end
      end
      if (!found && (|rd_servable)) begin
        for (q = 0; q < PORTS; q = q + 1)
          if (!found && rd_servable[(rr+q)%PORTS]) begin grant_r[(rr+q)%PORTS] = 1'b1; found = 1; end
      end else if (!found && (|wr_servable)) begin
        for (q = 0; q < PORTS; q = q + 1)
          if (!found && wr_servable[(rr+q)%PORTS]) begin grant_w[(rr+q)%PORTS] = 1'b1; found = 1; end
      end
    end
  end

  // ---------------- 主状态机 ----------------
  integer i, idx;
  always @(posedge clk) begin
    if (!rst_n) begin
      lfsr <= SEED;
      cycles <= 0; bus_read_beats <= 0; bus_write_beats <= 0;
      bus_idle_cycles <= 0; bus_turnaround_cycles <= 0; bus_busy_cycles <= 0;
      read_bursts <= 0; write_bursts <= 0; max_rd_out <= 0; max_wr_out <= 0;
      ar_stall_cycles <= 0; aw_stall_cycles <= 0; r_stall_cycles <= 0; w_stall_cycles <= 0;
      last_dir <= 0; rr <= 0; turn_cd <= 0;
      for (i = 0; i < PORTS; i = i + 1) begin
        rd_head[i] <= 0; rd_tail[i] <= 0; rd_cnt[i] <= 0; rd_beat[i] <= 0;
        aw_head[i] <= 0; aw_tail[i] <= 0; aw_cnt[i] <= 0; aw_beat[i] <= 0;
        wf_head[i] <= 0; wf_tail[i] <= 0; wf_cnt[i] <= 0;
        bq_head[i] <= 0; bq_tail[i] <= 0; bq_cnt[i] <= 0;
        ar_block[i] <= 0; aw_block[i] <= 0; w_block[i] <= 0;
      end
      for (i = 0; i < PORTS*MAX_OUT; i = i + 1) begin
        rd_v[i] <= 0; aw_v[i] <= 0; rd_lat[i] <= 0; aw_lat[i] <= 0;
        bq_v[i] <= 0; bq_lat[i] <= 0; bq_err[i] <= 0;
      end
    end else begin
      cycles <= cycles + 1;
      if (turn_cd != 0) turn_cd <= turn_cd - 1;
      for (i = 0; i < PORTS; i = i + 1) begin
        ar_block[i] <= chance(READY_STALL_PCT);
        aw_block[i] <= chance(READY_STALL_PCT);
        w_block[i]  <= chance(W_STALL_PCT);
      end

      // 已接受读突发的延迟并行倒计时（多在途可重叠）。
      for (i = 0; i < PORTS*MAX_OUT; i = i + 1)
        if (rd_v[i] && rd_lat[i] != 0) rd_lat[i] <= rd_lat[i] - 1;
      for (i = 0; i < PORTS*MAX_OUT; i = i + 1)
        if (bq_v[i] && bq_lat[i] != 0) bq_lat[i] <= bq_lat[i] - 1;

      for (i = 0; i < PORTS; i = i + 1) begin
        // AR 接受
        if (arvalid[i] && !arready[i]) ar_stall_cycles <= ar_stall_cycles + 1;
        if (arvalid[i] && arready[i]) begin
          if (!valid_address(araddr[i*40+:40])) $fatal(1, "AXI AR outside windows port=%0d addr=%h", i, araddr[i*40+:40]);
          if (araddr[i*40+:4] != 0 || arsize[i*3+:3] != 3'd4 || arburst[i*2+:2] != 2'd1 || arlen[i*8+:8] > 8'd255 ||
              ({1'b0, araddr[i*40+:12]} + (({1'b0, arlen[i*8+:8]} + 1) * 16)) > 4096)
            $fatal(1, "AXI AR framing port=%0d", i);
          rd_addr[i*MAX_OUT+rd_tail[i]] <= araddr[i*40+:40];
          rd_len [i*MAX_OUT+rd_tail[i]] <= arlen[i*8+:8] + 1;
          rd_lat [i*MAX_OUT+rd_tail[i]] <= LAT_MIN + (rnd() % (LAT_MAX - LAT_MIN + 1));
          rd_err [i*MAX_OUT+rd_tail[i]] <= inject_read_error[i];
          rd_v   [i*MAX_OUT+rd_tail[i]] <= 1;
          rd_tail[i] <= (rd_tail[i] + 1) % MAX_OUT;
          read_bursts <= read_bursts + 1;
          if (rd_cnt[i] + 1 > max_rd_out) max_rd_out <= rd_cnt[i] + 1;
        end
        // AW 接受
        if (awvalid[i] && !awready[i]) aw_stall_cycles <= aw_stall_cycles + 1;
        if (awvalid[i] && awready[i]) begin
          if (!valid_address(awaddr[i*40+:40])) $fatal(1, "AXI AW outside windows port=%0d addr=%h", i, awaddr[i*40+:40]);
          if (awaddr[i*40+:4] != 0 || awsize[i*3+:3] != 3'd4 || awburst[i*2+:2] != 2'd1 || awlen[i*8+:8] > 8'd255 ||
              ({1'b0, awaddr[i*40+:12]} + (({1'b0, awlen[i*8+:8]} + 1) * 16)) > 4096)
            $fatal(1, "AXI AW framing port=%0d", i);
          aw_addr[i*MAX_OUT+aw_tail[i]] <= awaddr[i*40+:40];
          aw_len [i*MAX_OUT+aw_tail[i]] <= awlen[i*8+:8] + 1;
          aw_lat [i*MAX_OUT+aw_tail[i]] <= BLAT_MIN + (rnd() % (BLAT_MAX - BLAT_MIN + 1));
          aw_err [i*MAX_OUT+aw_tail[i]] <= inject_write_error[i];
          aw_v   [i*MAX_OUT+aw_tail[i]] <= 1;
          aw_tail[i] <= (aw_tail[i] + 1) % MAX_OUT;
          write_bursts <= write_bursts + 1;
          if (aw_cnt[i] + 1 > max_wr_out) max_wr_out <= aw_cnt[i] + 1;
        end

        // W 拍进入缓冲
        if (wvalid[i] && wready[i]) begin
          wf_data[i*WFIFO+wf_tail[i]] <= wdata[i*128+:128];
          wf_strb[i*WFIFO+wf_tail[i]] <= wstrb[i*16+:16];
          wf_last[i*WFIFO+wf_tail[i]] <= wlast[i];
          wf_tail[i] <= (wf_tail[i] + 1) % WFIFO;
        end else if (wvalid[i] && !wready[i]) w_stall_cycles <= w_stall_cycles + 1;

        // R 拍返回
        if (rvalid[i] && !rready[i]) r_stall_cycles <= r_stall_cycles + 1;
        if (rvalid[i] && rready[i]) begin
          bus_read_beats <= bus_read_beats + 1;
          if (rd_beat[i] + 1 == rd_len[i*MAX_OUT+rd_head[i]]) begin
            rd_beat[i] <= 0;
            rd_v[i*MAX_OUT+rd_head[i]] <= 0;
            rd_head[i] <= (rd_head[i] + 1) % MAX_OUT;
          end else begin
            rd_beat[i] <= rd_beat[i] + 1;
          end
        end

        // W 拍写入共享存储
        if (grant_w[i]) begin
          if (aw_cnt[i] == 0) $fatal(1, "W beat without AW port=%0d", i);
          if (aw_beat[i] + 1 > aw_len[i*MAX_OUT+aw_head[i]]) $fatal(1, "Too many W beats port=%0d", i);
          if (wf_last[i*WFIFO+wf_head[i]] != (aw_beat[i] + 1 == aw_len[i*MAX_OUT+aw_head[i]]))
            $fatal(1, "AXI WLAST mismatch port=%0d", i);
          for (idx = 0; idx < 16; idx = idx + 1)
            if (wf_strb[i*WFIFO+wf_head[i]][idx])
              memory[mem_index(aw_addr[i*MAX_OUT+aw_head[i]]) + aw_beat[i]*16 + idx] <= wf_data[i*WFIFO+wf_head[i]][idx*8+:8];
          wf_head[i] <= (wf_head[i] + 1) % WFIFO;
          bus_write_beats <= bus_write_beats + 1;
          if (aw_beat[i] + 1 == aw_len[i*MAX_OUT+aw_head[i]]) begin
            aw_beat[i] <= 0;
            bq_lat[i*MAX_OUT+bq_tail[i]] <= aw_lat[i*MAX_OUT+aw_head[i]];
            bq_err[i*MAX_OUT+bq_tail[i]] <= aw_err[i*MAX_OUT+aw_head[i]];
            bq_v  [i*MAX_OUT+bq_tail[i]] <= 1;
            bq_tail[i] <= (bq_tail[i] + 1) % MAX_OUT;
            aw_v[i*MAX_OUT+aw_head[i]] <= 0;
            aw_head[i] <= (aw_head[i] + 1) % MAX_OUT;
          end else aw_beat[i] <= aw_beat[i] + 1;
        end

        if (bvalid[i] && bready[i]) begin
          bq_v[i*MAX_OUT+bq_head[i]] <= 0;
          bq_head[i] <= (bq_head[i] + 1) % MAX_OUT;
        end
        wf_cnt[i] <= wf_cnt[i] + (w_push[i] ? 1 : 0) - (w_pop[i] ? 1 : 0);
        bq_cnt[i] <= bq_cnt[i] + (b_push[i] ? 1 : 0) - (b_pop[i] ? 1 : 0);
        aw_cnt[i] <= aw_cnt[i] + ((awvalid[i] && awready[i]) ? 1 : 0) - (b_push[i] ? 1 : 0);
        rd_cnt[i] <= rd_cnt[i] + ((arvalid[i] && arready[i]) ? 1 : 0) - (r_pop[i] ? 1 : 0);
      end

      if (|grant_r || |grant_w) begin
        bus_busy_cycles <= bus_busy_cycles + 1;
        if (|grant_r && last_dir == 2 && TURNAROUND != 0) turn_cd <= TURNAROUND - 1;
        if (|grant_w && last_dir == 1 && TURNAROUND != 0) turn_cd <= TURNAROUND - 1;
        last_dir <= |grant_r ? 2'd1 : 2'd2;
        rr <= (rr + 1) % PORTS;
      end else begin
        bus_idle_cycles <= bus_idle_cycles + 1;
        if (turn_cd != 0) bus_turnaround_cycles <= bus_turnaround_cycles + 1;
      end
    end
  end
endmodule
