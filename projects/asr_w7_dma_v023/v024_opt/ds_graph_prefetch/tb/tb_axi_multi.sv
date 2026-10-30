`timescale 1ns/1ps
// Shared-AXI single-port multi-outstanding stress test.
//
// 5 read masters and 3 write masters issue real concurrent AR/AW bursts.  The
// slave accepts many outstanding transactions, returns R in AR order, and
// returns B in AW order with random latency (b_pending > 1).  The test checks
// owner/tag routing of every beat, write data, WLAST/B ordering, peak pending
// counts, and the isolation gate.  One slave port only: not a multi-HP claim.
module tb_axi_multi;
 localparam integer NR = 5, NW = 3, NREAD = 8, NWRITE = 8, QDEPTH = 256;
 reg clk = 0;
 always #4 clk = ~clk;
 reg rst_n = 0;
 integer cyc = 0, timeout = 20000;

 reg [NR-1:0] arvalid;
 reg [NW-1:0] awvalid, wvalid;
 wire [NR-1:0] arready, rvalid, rlast;
 wire [NR*128-1:0] rdata;
 wire [NR*2-1:0] rresp;
 reg [NR-1:0] rready;
 wire [NW-1:0] awready, wready, bvalid;
 wire [NW*2-1:0] bresp;
 reg [NW-1:0] bready;
 reg [NR*40-1:0] araddr;
 reg [NR*8-1:0] arlen;
 reg [NR*3-1:0] arsize;
 reg [NR*2-1:0] arburst;
 reg [NW*40-1:0] awaddr;
 reg [NW*8-1:0] awlen;
 reg [NW*3-1:0] awsize;
 reg [NW*2-1:0] awburst;
 reg [NW*128-1:0] wdata;
 reg [NW*16-1:0] wstrb;
 reg [NW-1:0] wlast;

 wire [39:0] s_araddr; wire [7:0] s_arlen; wire [2:0] s_arsize;
 wire [1:0] s_arburst; wire s_arvalid; wire s_arready;
 wire [127:0] s_rdata; wire [1:0] s_rresp; wire s_rlast, s_rvalid, s_rready;
 wire [39:0] s_awaddr; wire [7:0] s_awlen; wire [2:0] s_awsize;
 wire [1:0] s_awburst; wire s_awvalid; wire s_awready;
 wire [127:0] s_wdata; wire [15:0] s_wstrb; wire s_wlast, s_wvalid, s_wready;
 wire [1:0] s_bresp; wire s_bvalid, s_bready;

 wire [31:0] rd_bursts, wr_bursts, r_beats, w_beats, rd_peak, wr_peak;
 wire [31:0] rd_stall, wr_stall, tag_errors;
 wire [31:0] rd_pending, wr_pending, b_pending;
 wire quiesced;
 wire [31:0] iso_blocked;
 reg isolate = 0;

 reg [31:0] bfm_rb, bfm_wb, bfm_rbeats, bfm_wbeats, bfm_bresp;
 reg [31:0] bfm_max_rd, bfm_max_aw, bfm_max_b, bfm_data_err, bfm_wlast_err;

 v023_axi_shared #(.NR(NR),.NW(NW),.CREDIT(8),.QDEPTH(32)) xbar (
  .clk(clk),.rst_n(rst_n),.isolate(isolate),
  .m_arvalid(arvalid),.m_arready(arready),.m_araddr(araddr),.m_arlen(arlen),
  .m_arsize(arsize),.m_arburst(arburst),.m_rdata(rdata),.m_rresp(rresp),
  .m_rlast(rlast),.m_rvalid(rvalid),.m_rready(rready),
  .s_araddr(s_araddr),.s_arlen(s_arlen),.s_arsize(s_arsize),.s_arburst(s_arburst),
  .s_arvalid(s_arvalid),.s_arready(s_arready),.s_rdata(s_rdata),.s_rresp(s_rresp),
  .s_rlast(s_rlast),.s_rvalid(s_rvalid),.s_rready(s_rready),
  .m_awvalid(awvalid),.m_awready(awready),.m_awaddr(awaddr),.m_awlen(awlen),
  .m_awsize(awsize),.m_awburst(awburst),.m_wdata(wdata),.m_wstrb(wstrb),
  .m_wlast(wlast),.m_wvalid(wvalid),.m_wready(wready),.m_bready(bready),
  .m_bresp(bresp),.m_bvalid(bvalid),
  .s_awaddr(s_awaddr),.s_awlen(s_awlen),.s_awsize(s_awsize),.s_awburst(s_awburst),
  .s_awvalid(s_awvalid),.s_awready(s_awready),.s_wdata(s_wdata),.s_wstrb(s_wstrb),
  .s_wlast(s_wlast),.s_wvalid(s_wvalid),.s_wready(s_wready),.s_bresp(s_bresp),
  .s_bvalid(s_bvalid),.s_bready(s_bready),
  .rd_bursts(rd_bursts),.wr_bursts(wr_bursts),.r_beats(r_beats),.w_beats(w_beats),
  .rd_peak(rd_peak),.wr_peak(wr_peak),.rd_stall_cycles(rd_stall),
  .wr_stall_cycles(wr_stall),.tag_errors(tag_errors),
  .rd_pending(rd_pending),.wr_pending(wr_pending),.b_pending(b_pending),
  .quiesced(quiesced),.iso_blocked(iso_blocked)
 );

 axi_multi_bfm #(.QDEPTH(QDEPTH)) bfm (
  .clk(clk),.rst_n(rst_n),
  .araddr(s_araddr),.arlen(s_arlen),.arsize(s_arsize),.arburst(s_arburst),
  .arvalid(s_arvalid),.arready(s_arready),.rdata(s_rdata),.rresp(s_rresp),
  .rlast(s_rlast),.rvalid(s_rvalid),.rready(s_rready),
  .awaddr(s_awaddr),.awlen(s_awlen),.awsize(s_awsize),.awburst(s_awburst),
  .awvalid(s_awvalid),.awready(s_awready),.wdata(s_wdata),.wstrb(s_wstrb),
  .wlast(s_wlast),.wvalid(s_wvalid),.wready(s_wready),.bresp(s_bresp),
  .bvalid(s_bvalid),.bready(s_bready),
  .read_bursts(bfm_rb),.write_bursts(bfm_wb),.r_beats(bfm_rbeats),.w_beats(bfm_wbeats),
  .b_responses(bfm_bresp),.max_rd_pending(bfm_max_rd),.max_aw_pending(bfm_max_aw),
  .max_b_pending(bfm_max_b),.data_errors(bfm_data_err),.wlast_errors(bfm_wlast_err)
 );

 reg [39:0] rq_addr[0:NR-1][0:15];
 reg [7:0]  rq_len[0:NR-1][0:15];
 integer rq_head[0:NR-1], rq_tail[0:NR-1];
 integer r_beat[0:NR-1], r_issued[0:NR-1], r_done[0:NR-1], ar_gap[0:NR-1];
 reg [39:0] wq_addr[0:NW-1][0:15];
 reg [7:0]  wq_len[0:NW-1][0:15];
 integer wq_head[0:NW-1], wq_tail[0:NW-1];
 integer w_beat[0:NW-1], w_issued[0:NW-1], w_done[0:NW-1], aw_gap[0:NW-1], b_done[0:NW-1];

 integer m, l, wm;
 integer data_err = 0, wlast_err = 0, unexpected_r = 0, unexpected_w = 0;
 integer max_rd_pending = 0, max_wr_pending = 0, max_b_pending = 0;
 integer iso_hs = 0, iso_cnt = 0;
 reg iso_done = 0;
 reg [31:0] iso_blocked_end = 0;

 always @* begin
  for (wm = 0; wm < NW; wm = wm + 1) begin
   wvalid[wm] = (wq_head[wm] < wq_tail[wm]);
   wstrb[wm*16 +: 16] = 16'hffff;
   wlast[wm] = (wq_head[wm] < wq_tail[wm]) && (w_beat[wm] == wq_len[wm][wq_head[wm]]);
   for (l = 0; l < 16; l = l + 1)
    wdata[wm*128 + l*8 +: 8] = (wq_addr[wm][wq_head[wm]] + w_beat[wm]*16 + l) & 8'hff;
  end
 end

 always @(posedge clk) begin
  if (!rst_n) begin
   arvalid <= 0; awvalid <= 0; rready <= {NR{1'b1}}; bready <= {NW{1'b1}};
   araddr <= 0; arlen <= 0; arsize <= 0; arburst <= 0;
   awaddr <= 0; awlen <= 0; awsize <= 0; awburst <= 0;
   for (m = 0; m < NR; m = m + 1) begin
    rq_head[m] = 0; rq_tail[m] = 0; r_beat[m] = 0; r_issued[m] = 0; r_done[m] = 0; ar_gap[m] = m;
   end
   for (m = 0; m < NW; m = m + 1) begin
    wq_head[m] = 0; wq_tail[m] = 0; w_beat[m] = 0; w_issued[m] = 0; w_done[m] = 0; aw_gap[m] = m; b_done[m] = 0;
   end
   data_err <= 0; wlast_err <= 0; unexpected_r <= 0; unexpected_w <= 0;
   max_rd_pending <= 0; max_wr_pending <= 0; max_b_pending <= 0;
   iso_hs <= 0; iso_cnt <= 0; iso_done <= 0; iso_blocked_end <= 0;
  end else begin
   for (m = 0; m < NR; m = m + 1) begin : rd_m
    reg push, pop, rq_empty;
    begin
     rq_empty = (rq_head[m] >= rq_tail[m]);
     push = arvalid[m] && arready[m];
     pop  = rvalid[m] && rready[m] && !rq_empty && (r_beat[m] == rq_len[m][rq_head[m]]);
     if (ar_gap[m] > 0) ar_gap[m] <= ar_gap[m] - 1;
     if (!arvalid[m] && (r_issued[m] < NREAD) && (ar_gap[m] == 0)) begin
      araddr[m*40 +: 40] <= 40'h04000000 + m*40'h00010000 + r_issued[m]*40'h00000200;
      arlen[m*8 +: 8] <= (m + r_issued[m]) % 8;
      arsize[m*3 +: 3] <= 3'd4;
      arburst[m*2 +: 2] <= 2'b01;
      arvalid[m] <= 1;
     end
     if (push) begin
      rq_addr[m][rq_tail[m]] <= araddr[m*40 +: 40];
      rq_len[m][rq_tail[m]] <= arlen[m*8 +: 8];
      rq_tail[m] <= rq_tail[m] + 1;
      r_issued[m] <= r_issued[m] + 1;
      arvalid[m] <= 0;
      ar_gap[m] <= (m + r_issued[m]) % 3;
     end
     if (rvalid[m] && rready[m]) begin
      if (rq_empty) unexpected_r <= unexpected_r + 1;
      else begin
       for (l = 0; l < 16; l = l + 1)
        if (rdata[m*128 + l*8 +: 8] != ((rq_addr[m][rq_head[m]] + r_beat[m]*16 + l) & 8'hff))
         data_err <= data_err + 1;
      end
      if (pop) begin
       rq_head[m] <= rq_head[m] + 1;
       r_beat[m] <= 0;
       r_done[m] <= r_done[m] + 1;
      end else r_beat[m] <= r_beat[m] + 1;
     end
    end
   end
   for (m = 0; m < NW; m = m + 1) begin : wr_m
    reg push, pop, wq_empty;
    begin
     wq_empty = (wq_head[m] >= wq_tail[m]);
     push = awvalid[m] && awready[m];
     pop  = wvalid[m] && wready[m] && !wq_empty && (w_beat[m] == wq_len[m][wq_head[m]]);
     if (aw_gap[m] > 0) aw_gap[m] <= aw_gap[m] - 1;
     if (!awvalid[m] && (w_issued[m] < NWRITE) && (aw_gap[m] == 0)) begin
      awaddr[m*40 +: 40] <= 40'h04020000 + m*40'h00010000 + w_issued[m]*40'h00000200;
      awlen[m*8 +: 8] <= (m + w_issued[m]) % 8;
      awsize[m*3 +: 3] <= 3'd4;
      awburst[m*2 +: 2] <= 2'b01;
      awvalid[m] <= 1;
     end
     if (push) begin
      wq_addr[m][wq_tail[m]] <= awaddr[m*40 +: 40];
      wq_len[m][wq_tail[m]] <= awlen[m*8 +: 8];
      wq_tail[m] <= wq_tail[m] + 1;
      w_issued[m] <= w_issued[m] + 1;
      awvalid[m] <= 0;
      aw_gap[m] <= (m + w_issued[m]) % 3;
     end
     if (wvalid[m] && wready[m]) begin
      if (wq_empty) unexpected_w <= unexpected_w + 1;
      else if (wlast[m] != (w_beat[m] == wq_len[m][wq_head[m]])) wlast_err <= wlast_err + 1;
      if (pop) begin
       wq_head[m] <= wq_head[m] + 1;
       w_beat[m] <= 0;
       w_done[m] <= w_done[m] + 1;
      end else w_beat[m] <= w_beat[m] + 1;
     end
     if (bvalid[m] && bready[m]) b_done[m] <= b_done[m] + 1;
    end
   end

   if (rd_pending > max_rd_pending) max_rd_pending <= rd_pending;
   if (wr_pending > max_wr_pending) max_wr_pending <= wr_pending;
   if (b_pending > max_b_pending) max_b_pending <= b_pending;

   if (!iso_done && (rd_pending >= 8)) begin isolate <= 1; iso_cnt <= 0; end
   if (isolate) begin
    if (s_arvalid || s_awvalid || s_wvalid) iso_hs <= iso_hs + 1;
    if (iso_cnt >= 8) begin isolate <= 0; iso_done <= 1; iso_blocked_end <= iso_blocked; end
    else iso_cnt <= iso_cnt + 1;
   end
  end
 end

 integer total_r, total_w, total_b;
 always @* begin
  total_r = 0; total_w = 0; total_b = 0;
  for (m = 0; m < NR; m = m + 1) total_r = total_r + r_done[m];
  for (m = 0; m < NW; m = m + 1) begin
   total_w = total_w + w_done[m];
   total_b = total_b + b_done[m];
  end
 end

 integer errors = 0;
 initial begin
  if (!$value$plusargs("watchdog=%d", timeout)) timeout = 20000;
  rst_n = 0;
  repeat (10) @(posedge clk);
  rst_n = 1;
  while ((total_r < NR*NREAD || total_w < NW*NWRITE || total_b < NW*NWRITE ||
          !quiesced || rd_pending != 0 || wr_pending != 0 || b_pending != 0) &&
         cyc < timeout) @(posedge clk);
  repeat (20) @(posedge clk);

  $display("AXI_STRESS rd_bursts=%0d wr_bursts=%0d r_beats=%0d w_beats=%0d b_resp=%0d",
    rd_bursts, wr_bursts, r_beats, w_beats, bfm_bresp);
  $display("AXI_STRESS done r=%0d/%0d w=%0d/%0d b=%0d/%0d", total_r, NR*NREAD,
    total_w, NW*NWRITE, total_b, NW*NWRITE);
  $display("AXI_STRESS peaks xbar_rd=%0d xbar_wr=%0d bfm_rd=%0d bfm_aw=%0d bfm_b=%0d sampled rd=%0d wr=%0d b=%0d",
    rd_peak, wr_peak, bfm_max_rd, bfm_max_aw, bfm_max_b,
    max_rd_pending, max_wr_pending, max_b_pending);
  $display("AXI_STRESS tag_err=%0d data_err=%0d bfm_data_err=%0d wlast_err=%0d bfm_wlast_err=%0d unexpected_r=%0d unexpected_w=%0d",
    tag_errors, data_err, bfm_data_err, wlast_err, bfm_wlast_err, unexpected_r, unexpected_w);
  $display("AXI_STRESS iso_done=%0d iso_hs=%0d iso_blocked=%0d quiesced=%0d rd_pending=%0d wr_pending=%0d b_pending=%0d",
    iso_done, iso_hs, iso_blocked, quiesced, rd_pending, wr_pending, b_pending);

  if (total_r != NR*NREAD) begin $display("FAIL r count"); errors = errors + 1; end
  if (total_w != NW*NWRITE) begin $display("FAIL w count"); errors = errors + 1; end
  if (total_b != NW*NWRITE) begin $display("FAIL b count"); errors = errors + 1; end
  if (!quiesced || rd_pending != 0 || wr_pending != 0 || b_pending != 0) begin
   $display("FAIL drain"); errors = errors + 1;
  end
  if (tag_errors != 0 || data_err != 0 || bfm_data_err != 0 ||
      wlast_err != 0 || bfm_wlast_err != 0 || unexpected_r != 0 || unexpected_w != 0) begin
   $display("FAIL data/tag"); errors = errors + 1;
  end
  if (max_rd_pending < 8 || max_wr_pending < 4 || max_b_pending < 2) begin
   $display("FAIL multi-outstanding peak"); errors = errors + 1;
  end
  if (!iso_done || iso_hs != 0 || iso_blocked_end == 0) begin
   $display("FAIL isolation gate"); errors = errors + 1;
  end
  if (cyc >= timeout) begin $display("FAIL timeout"); errors = errors + 1; end
  if (errors) begin $display("AXI_STRESS_RESULT FAIL errors=%0d", errors); $fatal(1); end
  else $display("AXI_STRESS_RESULT PASS");
  $finish;
 end

 always @(posedge clk) begin
  cyc <= cyc + 1;
  if (cyc > timeout + 2000) begin
   $display("AXI_STRESS_GLOBAL_TIMEOUT cyc=%0d", cyc);
   $fatal(1);
  end
 end
endmodule
