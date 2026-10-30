`timescale 1ns/1ps
// tb_oddtail_writer.sv
// Directed odd-tail test for fusion_a16_writer + axi_dma_v020_multi_v2.
// The source presents `words` 16-byte words; the final word carries only
// `last_bytes` (1..16) valid bytes.  The AXI WSTRB must mask the tail, and the
// bytes outside the transfer must stay at the poison value.
module tb_oddtail_writer;
  parameter [31:0] BASE = 32'h03000000;
  parameter integer MEM_BYTES = 65536;
  parameter integer MAX_CYC = 20000;

  reg clk = 0;
  always #5 clk = ~clk;
  reg rst_n = 0;

  reg [7:0]  WORDS;
  reg [4:0]  LAST_BYTES;
  reg [31:0] ADDR;

  reg start = 0;
  reg [7:0] rd_idx = 0;
  wire buf_valid = (rd_idx < WORDS);
  wire [127:0] buf_data = {16{8'h10 + rd_idx}};
  wire buf_last = (rd_idx + 8'd1 == WORDS);
  wire buf_ready;

  wire dma_req_valid, dma_req_ready;
  wire [31:0] dma_req_addr;
  wire [15:0] dma_req_beats;
  wire dma_wr_valid, dma_wr_ready;
  wire [127:0] dma_wr_data;
  wire [15:0] dma_wr_strb;
  wire dma_done, dma_error;
  wire busy, done, fault;
  wire [7:0] error_code;
  wire [31:0] stat_beats, stat_bytes, stat_drain, last_w, dma_done_cyc;

  fusion_a16_writer u_writer (
    .clk(clk), .rst_n(rst_n), .flush(1'b0),
    .start(start), .base_addr(ADDR), .words(WORDS), .last_bytes(LAST_BYTES),
    .buf_rd_valid(buf_valid), .buf_rd_ready(buf_ready),
    .buf_rd_data(buf_data), .buf_rd_last(buf_last),
    .dma_req_valid(dma_req_valid), .dma_req_ready(dma_req_ready),
    .dma_req_addr(dma_req_addr), .dma_req_beats(dma_req_beats),
    .dma_wr_valid(dma_wr_valid), .dma_wr_ready(dma_wr_ready),
    .dma_wr_data(dma_wr_data), .dma_wr_strb(dma_wr_strb),
    .dma_done(dma_done), .dma_error(dma_error),
    .busy(busy), .done(done), .fault(fault), .error_code(error_code),
    .stat_beats(stat_beats), .stat_bytes(stat_bytes),
    .stat_drain_cycles(stat_drain),
    .cyc_last_w(last_w), .cyc_dma_done(dma_done_cyc)
  );

  reg [7:0] wr_beat;
  always @(posedge clk) if (rst_n && buf_ready && buf_valid && dma_wr_ready) rd_idx <= rd_idx + 1;

  wire [39:0] awaddr;
  wire [7:0]  awlen;
  wire [2:0]  awsize;
  wire [1:0]  awburst;
  wire        awvalid, awready;
  wire [127:0] wdata;
  wire [15:0]  wstrb;
  wire        wlast, wvalid, wready;
  wire [1:0]  bresp;
  wire        bvalid, bready;

  axi_dma_v020_multi_v2 #(.MAX_OUT(8), .FIFO_BEATS(128)) u_dma (
    .clk(clk), .rst_n(rst_n),
    .request_valid(dma_req_valid), .request_ready(dma_req_ready),
    .request_write(1'b1), .request_address(dma_req_addr),
    .request_beats(dma_req_beats),
    .read_valid(), .read_ready(1'b1), .read_data(), .read_index(),
    .write_valid(dma_wr_valid), .write_ready(dma_wr_ready),
    .write_data(dma_wr_data), .write_strobe(dma_wr_strb), .write_index(),
    .done(dma_done), .error(dma_error), .read_bytes(), .write_bytes(),
    .read_bursts(), .write_bursts(),
    .ar_outstanding_max(), .b_outstanding_max(),
    .read_bubble_cycles(), .write_bubble_cycles(), .read_fifo_high(),
    .m_axi_araddr(), .m_axi_arlen(), .m_axi_arsize(), .m_axi_arburst(),
    .m_axi_arcache(), .m_axi_arprot(), .m_axi_arvalid(), .m_axi_arready(1'b0),
    .m_axi_rdata(128'd0), .m_axi_rresp(2'd0), .m_axi_rlast(1'b0),
    .m_axi_rvalid(1'b0), .m_axi_rready(),
    .m_axi_awaddr(awaddr), .m_axi_awlen(awlen), .m_axi_awsize(awsize),
    .m_axi_awburst(awburst), .m_axi_awcache(), .m_axi_awprot(),
    .m_axi_awvalid(awvalid), .m_axi_awready(awready),
    .m_axi_wdata(wdata), .m_axi_wstrb(wstrb), .m_axi_wlast(wlast),
    .m_axi_wvalid(wvalid), .m_axi_wready(wready),
    .m_axi_bresp(bresp), .m_axi_bvalid(bvalid), .m_axi_bready(bready)
  );

  wire [0:0] arready_b, awready_b, wready_b, rvalid_b, bvalid_b;
  wire [0:0] arvalid_b, awvalid_b, wvalid_b, bready_b, rready_b;
  wire [39:0] araddr_b, awaddr_b;
  wire [7:0]  arlen_b, awlen_b;
  wire [2:0]  arsize_b, awsize_b;
  wire [1:0]  arburst_b, awburst_b;
  wire [127:0] rdata_b, wdata_b;
  wire [1:0]  rresp_b, bresp_b;
  wire [15:0] wstrb_b;
  wire        rlast_b, wlast_b;

  assign araddr_b  = 40'd0;
  assign arlen_b   = 8'd0;
  assign arsize_b  = 3'd0;
  assign arburst_b = 2'd0;
  assign arvalid_b = 1'b0;
  assign rready_b  = 1'b1;
  assign awaddr_b  = awaddr;
  assign awlen_b   = awlen;
  assign awsize_b  = awsize;
  assign awburst_b = awburst;
  assign awvalid_b = awvalid;
  assign wvalid_b  = wvalid;
  assign wdata_b   = wdata;
  assign wstrb_b   = wstrb;
  assign wlast_b   = wlast;
  assign bready_b  = bready;
  assign awready   = awready_b[0];
  assign wready    = wready_b[0];
  assign bvalid    = bvalid_b[0];
  assign bresp     = bresp_b;

  integer LAT_MIN, LAT_MAX, BP_PCT, SEED, LONG_MODE, LONG_PERIOD, LONG_LEN;
  axi128_ddr_bfm #(
    .PORTS(1), .BASE(BASE), .MEM_BYTES(MEM_BYTES),
    .MAX_RD_OUT(8), .MAX_WR_OUT(8), .DUPLEX(0), .QDEPTH(16)
  ) bfm (
    .clk(clk), .rst_n(rst_n),
    .cfg_lat_min(LAT_MIN), .cfg_lat_max(LAT_MAX), .cfg_bp_pct(BP_PCT),
    .cfg_seed(SEED), .cfg_long_mode(LONG_MODE), .cfg_long_period(LONG_PERIOD),
    .cfg_long_len(LONG_LEN),
    .araddr(araddr_b), .arlen(arlen_b), .arsize(arsize_b), .arburst(arburst_b),
    .arvalid(arvalid_b), .arready(arready_b),
    .rdata(rdata_b), .rresp(rresp_b), .rlast(rlast_b), .rvalid(rvalid_b), .rready(rready_b),
    .awaddr(awaddr_b), .awlen(awlen_b), .awsize(awsize_b), .awburst(awburst_b),
    .awvalid(awvalid_b), .awready(awready_b),
    .wdata(wdata_b), .wstrb(wstrb_b), .wlast(wlast_b), .wvalid(wvalid_b), .wready(wready_b),
    .bresp(bresp_b), .bvalid(bvalid_b), .bready(bready_b),
    .inject_read_error(1'b0), .inject_write_error(1'b0),
    .total_cycles(), .busy_cycles(), .read_busy_cycles(), .write_busy_cycles(),
    .read_beats(), .write_beats(), .read_bursts(), .write_bursts(),
    .read_wait_cycles(), .write_wait_cycles(),
    .ar_full_stalls(), .aw_full_stalls(), .cmd_stalls(),
    .max_rd_outstanding(), .max_wr_outstanding()
  );

  reg [15:0] last_strobe;
  integer cyc, errs, i, lo, hi;
  always @(posedge clk) begin
    if (rst_n) begin
      cyc <= cyc + 1;
      if (wvalid && wready && wlast) last_strobe <= wstrb;
    end
  end

  initial begin
    cyc = 0; errs = 0; last_strobe = 16'hxxxx;
    if (!$value$plusargs("words=%d", WORDS)) WORDS = 8'd5;
    if (!$value$plusargs("last_bytes=%d", LAST_BYTES)) LAST_BYTES = 4'd3;
    if (!$value$plusargs("addr=%h", ADDR)) ADDR = 32'h03000000;
    LAT_MIN = 0; LAT_MAX = 2; BP_PCT = 0; SEED = 3;
    LONG_MODE = 0; LONG_PERIOD = 100; LONG_LEN = 10;

    for (i = 0; i < MEM_BYTES/16; i = i + 1) bfm.mem[i] = {16{8'hee}};

    rst_n = 0;
    repeat (6) @(negedge clk);
    rst_n = 1;
    repeat (2) @(negedge clk);
    @(negedge clk); start = 1;
    @(negedge clk); start = 0;

    wait (done || fault);
    repeat (3) @(negedge clk);

    // check each byte
    for (i = 0; i < WORDS*16; i = i + 1) begin
      lo = i % 16;
      if (i < (WORDS-1)*16 + LAST_BYTES) begin
        if (bfm.mem[i/16][lo*8 +: 8] !== (8'h10 + (i/16))) begin
          if (errs < 8) $display("FAIL byte %0d got %02h exp %02h", i, bfm.mem[i/16][lo*8 +: 8], 8'h10 + (i/16));
          errs = errs + 1;
        end
      end else begin
        if (bfm.mem[i/16][lo*8 +: 8] !== 8'hee) begin
          if (errs < 8) $display("FAIL tail byte %0d changed to %02h", i, bfm.mem[i/16][lo*8 +: 8]);
          errs = errs + 1;
        end
      end
    end
    if (last_strobe !== ((16'h0001 << LAST_BYTES) - 16'h0001)) begin
      $display("FAIL last WSTRB=%04h exp=%04h", last_strobe, (16'h0001 << LAST_BYTES) - 16'h0001);
      errs = errs + 1;
    end
    if (stat_beats !== {8'd0, WORDS}) begin $display("FAIL beats %0d", stat_beats); errs=errs+1; end
    if (stat_bytes !== ((WORDS-1)*16 + LAST_BYTES)) begin $display("FAIL bytes %0d", stat_bytes); errs=errs+1; end
    if (last_w >= dma_done_cyc) begin $display("FAIL drain order last_w=%0d dma_done=%0d", last_w, dma_done_cyc); errs=errs+1; end

    $display("ODDTAIL words=%0d last_bytes=%0d beats=%0d bytes=%0d strobe=%04h drain=%0d errs=%0d",
             WORDS, LAST_BYTES, stat_beats, stat_bytes, last_strobe, stat_drain, errs);
    if (fault) begin $display("FAIL writer fault %02h", error_code); errs=errs+1; end
    if (errs == 0) $display("ODDTAIL_PASS"); else $display("ODDTAIL_FAIL");
    $finish;
  end

  initial begin
    #(MAX_CYC*10);
    $display("TIMEOUT oddtail watchdog");
    $fatal(1, "oddtail watchdog timeout");
  end
endmodule
