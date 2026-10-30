`timescale 1ns/1ps
// Independent done-after-last-B check for fusion_a16_writer.
module tb_doneb;
  parameter integer MAXCYC = 20000;
  reg clk = 0;
  always #5 clk = ~clk;
  reg rst_n = 0, flush = 0, start = 0;
  reg [31:0] base_addr = 32'h03002000;
  reg [7:0] words = 2;
  reg [4:0] last_bytes = 16;
  reg buf_rd_valid = 0;
  wire buf_rd_ready;
  reg [127:0] buf_rd_data = 0;
  reg buf_rd_last = 0;
  wire dma_req_valid;
  reg dma_req_ready = 1;
  wire [31:0] dma_req_addr;
  wire [15:0] dma_req_beats;
  wire dma_wr_valid;
  reg dma_wr_ready = 1;
  wire [127:0] dma_wr_data;
  wire [15:0] dma_wr_strb;
  reg dma_done = 0, dma_error = 0;
  wire busy, done, fault;
  wire [7:0] error_code;
  wire [31:0] stat_beats, stat_bytes, stat_drain_cycles, cyc_last_w, cyc_dma_done;

  fusion_a16_writer #(.MAX_BURST(16)) dut (
    .clk(clk), .rst_n(rst_n), .flush(flush), .start(start),
    .base_addr(base_addr), .words(words), .last_bytes(last_bytes),
    .buf_rd_valid(buf_rd_valid), .buf_rd_ready(buf_rd_ready),
    .buf_rd_data(buf_rd_data), .buf_rd_last(buf_rd_last),
    .dma_req_valid(dma_req_valid), .dma_req_ready(dma_req_ready),
    .dma_req_addr(dma_req_addr), .dma_req_beats(dma_req_beats),
    .dma_wr_valid(dma_wr_valid), .dma_wr_ready(dma_wr_ready),
    .dma_wr_data(dma_wr_data), .dma_wr_strb(dma_wr_strb),
    .dma_done(dma_done), .dma_error(dma_error),
    .busy(busy), .done(done), .fault(fault), .error_code(error_code),
    .stat_beats(stat_beats), .stat_bytes(stat_bytes),
    .stat_drain_cycles(stat_drain_cycles),
    .cyc_last_w(cyc_last_w), .cyc_dma_done(cyc_dma_done)
  );

  integer bdelay = 0, cyc = 0, errors = 0;
  integer got_beats = 0, expect_beats = 0;
  integer lastw_cyc = -1, b_cyc = -1, done_cyc = -1, done_before_b = 0;
  integer got_strb_last = 0;
  reg [31:0] mem [0:63];
  reg b_pending = 0;
  integer b_wait = 0;
  reg done_seen = 0, b_seen = 0;
  reg [127:0] wbuf [0:1];

  always @(posedge clk) begin
    if (rst_n) cyc <= cyc + 1;
    if (rst_n && dma_done) begin
      b_seen <= 1;
      if (b_cyc < 0) b_cyc <= cyc;
    end
    if (rst_n && done) begin
      done_seen <= 1;
      if (done_cyc < 0) done_cyc <= cyc;
      if (b_cyc < 0) done_before_b <= done_before_b + 1;
    end
  end

  // DMA model: request -> W beats -> B after bdelay
  always @(posedge clk) begin
    dma_done <= 0;
    if (!rst_n) begin
      got_beats <= 0; b_pending <= 0; b_wait <= 0;
    end else if (dma_req_valid && dma_req_ready && !b_pending && got_beats == 0) begin
      expect_beats <= dma_req_beats;
    end else if (buf_rd_valid && buf_rd_ready) begin
      got_beats <= got_beats + 1;
      mem[got_beats] <= buf_rd_data;
      got_strb_last <= dma_wr_strb;
      if (dma_wr_valid && dma_wr_ready && (got_beats + 1 == expect_beats)) begin
        lastw_cyc <= cyc;
        b_wait <= bdelay + 1;
        b_pending <= 1;
      end
    end
    if (b_pending) begin
      if (b_wait > 0) begin
        b_wait <= b_wait - 1;
        if (b_wait == 1) begin dma_done <= 1; b_pending <= 0; end
      end
    end
  end

  initial begin
    if (!$value$plusargs("bdelay=%d", bdelay)) bdelay = 0;
    if (!$value$plusargs("words=%d", words)) words = 2;
    if (!$value$plusargs("lastb=%d", last_bytes)) last_bytes = 16;
    if (words > 2) begin $display("words max 2"); $fatal(1); end
    wbuf[0] = 128'h11111111111111111111111111111111;
    wbuf[1] = 128'h22222222222222222222222222222222;
    repeat (4) @(posedge clk); rst_n <= 1; @(posedge clk);
    start <= 1; @(posedge clk); start <= 0;
    buf_rd_valid <= 1; buf_rd_data <= wbuf[0]; buf_rd_last <= (words == 1);
    @(posedge clk);
    while (!buf_rd_ready) @(posedge clk);
    if (words > 1) begin
      buf_rd_data <= wbuf[1]; buf_rd_last <= 1;
      @(posedge clk);
      while (!buf_rd_ready) @(posedge clk);
    end
    buf_rd_valid <= 0; buf_rd_last <= 0;
    while (!done_seen && cyc < MAXCYC) @(posedge clk);
    repeat (5) @(posedge clk);
    if (!done_seen) begin errors=errors+1; $display("FAIL no done"); end
    if (fault) begin errors=errors+1; $display("FAIL fault=%02x", error_code); end
    if (done_before_b != 0) begin errors=errors+1; $display("FAIL done before B (%0d)", done_before_b); end
    if (b_cyc < 0) begin errors=errors+1; $display("FAIL no B"); end
    if (lastw_cyc >= b_cyc) begin errors=errors+1; $display("FAIL lastW=%0d >= B=%0d", lastw_cyc, b_cyc); end
    if (done_cyc <= b_cyc) begin errors=errors+1; $display("FAIL done=%0d <= B=%0d", done_cyc, b_cyc); end
    if (got_beats != words) begin errors=errors+1; $display("FAIL beats=%0d words=%0d", got_beats, words); end
    if (last_bytes < 16 && got_strb_last != ((1 << last_bytes) - 1)) begin
      errors=errors+1; $display("FAIL last strobe=%04x exp=%04x", got_strb_last, (1<<last_bytes)-1);
    end
    $display("RESULT bdelay=%0d words=%0d lastb=%0d lastW=%0d B=%0d done=%0d beats=%0d err=%0d",
             bdelay, words, last_bytes, lastw_cyc, b_cyc, done_cyc, got_beats, errors);
    if (errors == 0) begin $display("PASS"); $finish; end
    else begin $display("FAIL"); $fatal(1); end
  end
  initial begin #(10*MAXCYC); $display("WATCHDOG"); $fatal(1); end
endmodule
