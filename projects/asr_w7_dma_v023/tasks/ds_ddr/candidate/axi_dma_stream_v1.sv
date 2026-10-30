`timescale 1ns/1ps
// 候选 DDR 搬运引擎：axi_dma_v019 的可参数化替代（接口保持兼容）。
// 关键改动（只动搬运，不动数值协议）：
//  1. 读路径：AR 多在途 + 拍级 FIFO/信用。AR 不再等 RLAST 才发下一笔，
//     首拍延迟被后续突发覆盖；R 与消费端解耦，允许有限缓冲吸收背压。
//  2. 写路径：W 拍先入 FIFO，AW 可多在途，B 响应按信用回收（posted write），
//     不再等 BRESP 才发下一笔 AW。
//  3. 4KiB 边界仍逐笔拆分；RLAST/WLAST/BRESP/RRESP 全检查。
//  4. 出错后不再发新读 AR，但已接受事务全部排空；FIFO 满时丢弃新 R 拍，
//     保证不因下游停读而死锁。写错误保持 sticky，已接受 W/B 全部排空。
// 说明：这是逻辑 RTL，不包含 DDR PHY/MIG 时序；频率目标与物理实现无关。
module axi_dma_stream_v1 #(
  parameter integer MAX_RD_OUT = 4,
  parameter integer MAX_WR_OUT = 4,
  parameter integer FIFO_BEATS = 64,
  parameter integer BURST_BEATS = 16
)(
  input wire clk, rst_n,
  input wire request_valid, output wire request_ready, input wire request_write,
  input wire [31:0] request_address, input wire [15:0] request_beats,
  output wire read_valid, input wire read_ready, output wire [127:0] read_data,
  output reg [15:0] read_index,
  input wire write_valid, output wire write_ready, input wire [127:0] write_data,
  input wire [15:0] write_strobe, output reg [15:0] write_index,
  output reg done, error,
  output reg [31:0] read_bytes, write_bytes, read_bursts, write_bursts,
  output wire [39:0] m_axi_araddr, output wire [7:0] m_axi_arlen,
  output wire [2:0] m_axi_arsize, output wire [1:0] m_axi_arburst,
  output wire [3:0] m_axi_arcache, output wire [2:0] m_axi_arprot,
  output wire m_axi_arvalid, input wire m_axi_arready,
  input wire [127:0] m_axi_rdata, input wire [1:0] m_axi_rresp,
  input wire m_axi_rlast, m_axi_rvalid, output wire m_axi_rready,
  output wire [39:0] m_axi_awaddr, output wire [7:0] m_axi_awlen,
  output wire [2:0] m_axi_awsize, output wire [1:0] m_axi_awburst,
  output wire [3:0] m_axi_awcache, output wire [2:0] m_axi_awprot,
  output wire m_axi_awvalid, input wire m_axi_awready,
  output wire [127:0] m_axi_wdata, output wire [15:0] m_axi_wstrb,
  output wire m_axi_wlast, m_axi_wvalid, input wire m_axi_wready,
  input wire [1:0] m_axi_bresp, input wire m_axi_bvalid, output wire m_axi_bready
);
  localparam integer AW = (MAX_RD_OUT > 1) ? $clog2(MAX_RD_OUT) : 1;
  localparam integer WW = (MAX_WR_OUT > 1) ? $clog2(MAX_WR_OUT) : 1;
  localparam integer FW = (FIFO_BEATS > 1) ? $clog2(FIFO_BEATS) : 1;
  localparam [2:0] IDLE = 0, RD = 1, WR = 2, FIN = 3;

  reg [2:0] state;
  reg [31:0] addr;
  reg [15:0] total_beats;
  reg [15:0] beats_left;

  // ---------------- 读路径 ----------------
  reg [127:0] rf_data [0:FIFO_BEATS-1];
  reg [FW-1:0] rf_head, rf_tail;
  reg [FW:0]   rf_cnt;
  reg [AW:0]   ar_out;
  reg [FW:0]   ar_resv;
  reg [31:0]   rd_addr;
  reg [15:0]   rcv_beats;
  reg          rd_err;
  reg [15:0]   arq_len [0:MAX_RD_OUT-1];
  reg [AW-1:0] arq_head, arq_tail;
  reg [AW:0]   arq_cnt;
  reg [15:0]   rb_beat;
  reg          ar_blocked;

  wire [12:0] rd_page = (13'd4096 - {1'b0, rd_addr[11:0]}) >> 4;
  wire [15:0] rd_limit = BURST_BEATS[15:0];
  wire [15:0] rd_burst = (beats_left > rd_limit) ? rd_limit : beats_left;
  wire [15:0] rd_burst_pg = (rd_burst > {3'd0, rd_page}) ? {3'd0, rd_page} : rd_burst;
  wire [FW:0] rd_room = FIFO_BEATS[FW:0] - rf_cnt - ar_resv;
  wire        rd_issue_ok = (state == RD) && (beats_left != 0) && !rd_err &&
                             (ar_out < MAX_RD_OUT) && (rd_room >= {1'b0, rd_burst_pg});
  wire        rf_full = (rf_cnt == FIFO_BEATS[FW:0]);
  wire        rf_empty = (rf_cnt == 0);
  wire [15:0] ar_cur_len = arq_len[arq_head];

  // ---------------- 写路径 ----------------
  reg [127:0] wf_data [0:FIFO_BEATS-1];
  reg [15:0]  wf_strb [0:FIFO_BEATS-1];
  reg [FW-1:0] wf_head, wf_tail;
  reg [FW:0]   wf_cnt;
  reg [15:0]   wf_total;
  reg [15:0]   wf_seen;
  reg [WW:0]   aw_out;
  reg [WW:0]   aw_iss;
  reg [31:0]   wr_addr;
  reg [15:0]   wr_left;
  reg [15:0]   wb_beat;
  reg [15:0]   awq_len [0:MAX_WR_OUT-1];
  reg [WW-1:0] awq_head, awq_tail;
  reg [WW:0]   awq_cnt;
  reg          wr_err;
  reg          aw_blocked;

  wire [12:0] wr_page = (13'd4096 - {1'b0, wr_addr[11:0]}) >> 4;
  wire [15:0] wr_limit = BURST_BEATS[15:0];
  wire [15:0] wr_burst = (wr_left > wr_limit) ? wr_limit : wr_left;
  wire [15:0] wr_burst_pg = (wr_burst > {3'd0, wr_page}) ? {3'd0, wr_page} : wr_burst;
  wire        wr_issue_ok = (state == WR) && (wr_left != 0) && (aw_out < MAX_WR_OUT) &&
                             (wf_cnt != 0);
  wire        wf_full = (wf_cnt == FIFO_BEATS[FW:0]);
  wire        wf_empty = (wf_cnt == 0);
  wire [15:0] aw_cur_len = awq_len[awq_head];
  wire        w_last = (wb_beat + 1 == aw_cur_len);

  // ---------------- 握手事件 ----------------
  assign request_ready = (state == IDLE) && rst_n;
  assign read_valid = (state == RD) && !rf_empty;
  assign read_data = rf_data[rf_head];
  assign m_axi_rready = (state == RD) && (!rf_full || rd_err);
  assign m_axi_arvalid = rd_issue_ok && !ar_blocked;
  assign m_axi_araddr = {8'd0, rd_addr};
  assign m_axi_arlen = rd_burst_pg - 1;
  assign m_axi_arsize = 3'd4;
  assign m_axi_arburst = 2'd1;
  assign m_axi_arcache = 4'd0;
  assign m_axi_arprot = 3'd0;

  assign write_ready = (state == WR) && !wf_full;
  assign m_axi_awvalid = wr_issue_ok && !aw_blocked;
  assign m_axi_awaddr = {8'd0, wr_addr};
  assign m_axi_awlen = wr_burst_pg - 1;
  assign m_axi_awsize = 3'd4;
  assign m_axi_awburst = 2'd1;
  assign m_axi_awcache = 4'd0;
  assign m_axi_awprot = 3'd0;
  assign m_axi_wvalid = (state == WR) && (aw_iss != 0) && !wf_empty;
  assign m_axi_wdata = wf_data[wf_head];
  assign m_axi_wstrb = wf_strb[wf_head];
  assign m_axi_wlast = w_last;
  assign m_axi_bready = (state == WR) && (aw_out != 0);

  wire ar_fire = m_axi_arvalid && m_axi_arready;
  wire r_fire  = m_axi_rvalid && m_axi_rready;
  wire r_last  = r_fire && m_axi_rlast;
  wire rd_pop  = read_valid && read_ready;
  wire rd_push = r_fire && !rf_full;
  wire aw_fire = m_axi_awvalid && m_axi_awready;
  wire w_fire  = m_axi_wvalid && m_axi_wready;
  wire w_last_fire = w_fire && w_last;
  wire w_push = write_valid && write_ready;
  wire b_fire = m_axi_bvalid && m_axi_bready;

  wire [FW:0] rf_cnt_n = rf_cnt + (rd_push ? 1'b1 : 1'b0) - (rd_pop ? 1'b1 : 1'b0);
  wire [AW:0] ar_out_n = ar_out + (ar_fire ? 1'b1 : 1'b0) - (r_last ? 1'b1 : 1'b0);
  wire [15:0] beats_left_n = beats_left - (ar_fire ? rd_burst_pg : 16'd0);
  wire [FW:0] wf_cnt_n = wf_cnt + (w_push ? 1'b1 : 1'b0) - (w_fire ? 1'b1 : 1'b0);
  wire [WW:0] aw_out_n = aw_out + (aw_fire ? 1'b1 : 0) - (b_fire ? 1'b1 : 0);
  wire [WW:0] aw_iss_n = aw_iss + (aw_fire ? 1'b1 : 0) - (w_last_fire ? 1'b1 : 0);
  wire [15:0] wr_left_n = wr_left - (aw_fire ? wr_burst_pg : 16'd0);
  wire [15:0] wf_seen_n = wf_seen + (w_push ? 16'd1 : 16'd0);
  wire rd_err_n = rd_err || (r_fire && (m_axi_rresp != 0 ||
                  (m_axi_rlast != (rb_beat + 1 == ar_cur_len))));
  wire wr_err_n = wr_err || (b_fire && m_axi_bresp != 0);

  function automatic [4:0] pop16(input [15:0] bits);
    integer k;
    begin
      pop16 = 0;
      for (k = 0; k < 16; k = k + 1) pop16 = pop16 + bits[k];
    end
  endfunction

  always @(posedge clk) begin
    if (!rst_n) begin
      state <= IDLE; addr <= 0; total_beats <= 0; beats_left <= 0;
      rf_head <= 0; rf_tail <= 0; rf_cnt <= 0; ar_out <= 0; ar_resv <= 0;
      rd_addr <= 0; rcv_beats <= 0; rd_err <= 0;
      arq_head <= 0; arq_tail <= 0; arq_cnt <= 0; rb_beat <= 0; ar_blocked <= 0;
      wf_head <= 0; wf_tail <= 0; wf_cnt <= 0; wf_total <= 0; wf_seen <= 0;
      aw_out <= 0; aw_iss <= 0; wr_addr <= 0; wr_left <= 0; wb_beat <= 0;
      awq_head <= 0; awq_tail <= 0; awq_cnt <= 0; wr_err <= 0; aw_blocked <= 0;
      done <= 0; error <= 0; read_index <= 0; write_index <= 0;
      read_bytes <= 0; write_bytes <= 0; read_bursts <= 0; write_bursts <= 0;
    end else begin
      done <= 0;
      ar_blocked <= 0;
      aw_blocked <= 0;

      if (state == IDLE && request_valid && request_ready) begin
        error <= 0; rd_err <= 0; wr_err <= 0;
        addr <= request_address; total_beats <= request_beats; beats_left <= request_beats;
        rd_addr <= request_address; wr_addr <= request_address; wr_left <= request_beats;
        rcv_beats <= 0; read_index <= 0; write_index <= 0;
        rf_head <= 0; rf_tail <= 0; rf_cnt <= 0; ar_out <= 0; ar_resv <= 0;
        arq_head <= 0; arq_tail <= 0; arq_cnt <= 0; rb_beat <= 0;
        wf_head <= 0; wf_tail <= 0; wf_cnt <= 0; wf_total <= request_beats; wf_seen <= 0;
        aw_out <= 0; aw_iss <= 0; wb_beat <= 0; awq_head <= 0; awq_tail <= 0; awq_cnt <= 0;
        if (request_address[3:0] != 0 || request_beats == 0) begin
          rd_err <= 1; state <= FIN;
        end else state <= request_write ? WR : RD;
      end

      // ---------- 读路径 ----------
      if (state == RD) begin
        if (ar_fire) begin
          arq_len[arq_tail] <= rd_burst_pg;
          arq_tail <= arq_tail + 1;
          arq_cnt <= arq_cnt + 1;
          rd_addr <= rd_addr + ({16'd0, rd_burst_pg} << 4);
          read_bursts <= read_bursts + 1;
        end
        if (r_fire) begin
          rcv_beats <= rcv_beats + 1;
          if (rd_push) begin
            rf_data[rf_tail] <= m_axi_rdata;
            rf_tail <= rf_tail + 1;
            if (!rd_err) read_bytes <= read_bytes + 16;
          end
          if (m_axi_rlast) begin
            arq_head <= arq_head + 1;
            arq_cnt <= arq_cnt - 1;
            rb_beat <= 0;
          end else rb_beat <= rb_beat + 1;
        end
        if (rd_pop) begin
          rf_head <= rf_head + 1;
          read_index <= read_index + 1;
        end
        ar_out <= ar_out_n;
        ar_resv <= ar_resv + (ar_fire ? rd_burst_pg : 16'd0) - (r_fire ? 16'd1 : 16'd0);
        rf_cnt <= rf_cnt_n;
        beats_left <= beats_left_n;
        if (rd_err_n) begin rd_err <= 1; error <= 1; end

        if (rd_err_n && ar_out_n == 0) begin
          rf_cnt <= 0; rf_head <= 0; rf_tail <= 0;
          state <= FIN;
        end else if (beats_left_n == 0 && ar_out_n == 0 && rf_cnt_n == 0) begin
          state <= FIN;
        end
      end

      // ---------- 写路径 ----------
      if (state == WR) begin
        if (w_push) begin
          wf_data[wf_tail] <= write_data;
          wf_strb[wf_tail] <= write_strobe;
          wf_tail <= wf_tail + 1;
          wf_seen <= wf_seen + 1;
          write_index <= write_index + 1;
          write_bytes <= write_bytes + pop16(write_strobe);
        end
        if (aw_fire) begin
          awq_len[awq_tail] <= wr_burst_pg;
          awq_tail <= awq_tail + 1;
          awq_cnt <= awq_cnt + 1;
          wr_addr <= wr_addr + ({16'd0, wr_burst_pg} << 4);
          write_bursts <= write_bursts + 1;
        end
        if (w_fire) begin
          wf_head <= wf_head + 1;
          if (w_last) begin
            wb_beat <= 0;
            awq_head <= awq_head + 1;
            awq_cnt <= awq_cnt - 1;
          end else wb_beat <= wb_beat + 1;
        end
        if (b_fire && m_axi_bresp != 0) begin wr_err <= 1; error <= 1; end
        wf_cnt <= wf_cnt_n;
        aw_out <= aw_out_n;
        aw_iss <= aw_iss_n;
        wr_left <= wr_left_n;

        if (wf_seen_n == wf_total && wf_cnt_n == 0 && wr_left_n == 0 &&
            aw_iss_n == 0 && aw_out_n == 0) state <= FIN;
      end

      // ---------- 单完成出口 ----------
      if (state == FIN) begin
        done <= 1;
        error <= rd_err_n || wr_err_n;
        state <= IDLE;
      end
    end
  end
endmodule
