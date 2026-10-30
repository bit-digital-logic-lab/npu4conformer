`timescale 1ns/1ps
// Direct ddr_vector_engine_pipe harness with an independent AXI-like BFM.
// Memory: A@0x04001000 B@0x04008000 C@0x04010000 D@0x04020000.
// Gold files (byte-wide hex) are produced by gold/gen_vector_vectors.py.
module tb_vector;
  parameter integer A_BASE = 32'h04001000;
  parameter integer B_BASE = 32'h04008000;
  parameter integer C_BASE = 32'h04010000;
  parameter integer D_BASE = 32'h04020000;
  parameter integer MAXCYC = 400000;

  reg clk = 0;
  always #5 clk = ~clk;
  reg rst_n = 0, start = 0, abort = 0;
  reg [511:0] descriptor = 0;
  reg [31:0] param_end = 32'h40000000;
  wire ready, busy, done, fault, aborted;
  wire [7:0] error_code, numeric_flags;
  wire [31:0] completed_elements, rejected_starts;
  wire [63:0] cycles, read_compute_overlap, write_compute_overlap;

  wire rd_request_valid;
  reg rd_request_ready = 1;
  wire [31:0] rd_address;
  wire [15:0] rd_beats;
  reg rd_valid = 0;
  wire rd_ready;
  reg [127:0] rd_data = 0;
  reg [15:0] rd_index = 0;
  reg rd_done = 0, rd_error = 0;

  wire wr_request_valid;
  reg wr_request_ready = 1;
  wire [31:0] wr_address;
  wire [15:0] wr_beats;
  wire wr_valid;
  reg wr_ready = 0;
  wire [127:0] wr_data;
  wire [15:0] wr_strobe;
  reg wr_done = 0, wr_error = 0;

  ddr_vector_engine_pipe #(.USE_APPROX_DIV_SQRT(0)) dut (
    .clk(clk), .rst_n(rst_n), .start(start), .descriptor(descriptor),
    .param_end(param_end), .ready(ready), .busy(busy), .done(done),
    .fault(fault), .aborted(aborted), .error_code(error_code),
    .numeric_flags(numeric_flags), .completed_elements(completed_elements),
    .rejected_starts(rejected_starts), .cycles(cycles),
    .read_compute_overlap(read_compute_overlap),
    .write_compute_overlap(write_compute_overlap),
    .rd_request_valid(rd_request_valid), .rd_request_ready(rd_request_ready),
    .rd_address(rd_address), .rd_beats(rd_beats), .rd_valid(rd_valid),
    .rd_ready(rd_ready), .rd_data(rd_data), .rd_index(rd_index),
    .rd_done(rd_done), .rd_error(rd_error),
    .wr_request_valid(wr_request_valid), .wr_request_ready(wr_request_ready),
    .wr_address(wr_address), .wr_beats(wr_beats), .wr_valid(wr_valid),
    .wr_ready(wr_ready), .wr_data(wr_data), .wr_strobe(wr_strobe),
    .wr_done(wr_done), .wr_error(wr_error)
  );

  reg [7:0] mem [0:262143];
  reg [7:0] expb [0:8191];

  integer op = 17, n = 1001, out16 = 0, mode = 0;
  integer errors = 0, cyc = 0, waited = 0;
  integer fd, rc, i, k;
  reg [1023:0] dir;
  integer b_delay = 0, last_b_cycle = -1, done_cycle = -1;
  integer b_count = 0, b_after_done = 0, aw_after_done = 0;
  reg done_seen = 0;

  // ---------------- read BFM ----------------
  reg rd_busy = 0, rd_hold = 0;
  reg [31:0] rd_addr = 0;
  reg [15:0] rd_left = 0, rd_idx = 0;
  reg rd_done_r = 0;
  function [127:0] word128;
    input [31:0] a;
    integer q;
    begin
      for (q = 0; q < 16; q = q + 1) word128[q*8 +: 8] = mem[(a + q) & 18'h3FFFF];
    end
  endfunction

  always @(posedge clk) begin
    if (!rst_n) begin
      rd_busy <= 0; rd_valid <= 0; rd_done <= 0; rd_hold <= 0;
    end else begin
      rd_done <= 0;
      if (!rd_busy) begin
        if (rd_request_valid && rd_request_ready) begin
          rd_busy <= 1; rd_addr <= rd_address & 32'h3FFFF;
          rd_left <= rd_beats; rd_idx <= 0; rd_index <= 0; rd_valid <= 1;
          rd_data <= word128(rd_address & 32'h3FFFF);
        end
      end else if (rd_valid && rd_ready) begin
        if (rd_left == 1) begin
          rd_valid <= 0; rd_busy <= 0; rd_done <= 1;
        end else begin
          rd_addr <= rd_addr + 16; rd_left <= rd_left - 1;
          rd_idx <= rd_idx + 1; rd_data <= word128(rd_addr + 16);
          rd_index <= rd_idx + 1;
        end
      end
    end
  end

  // ---------------- write BFM ----------------
  reg wr_busy = 0;
  reg [31:0] wr_addr = 0;
  reg [15:0] wr_left = 0;
  integer wb_wait = 0;
  always @(posedge clk) begin
    if (!rst_n) begin
      wr_busy <= 0; wr_ready <= 0; wr_done <= 0; wb_wait <= 0;
    end else begin
      wr_done <= 0;
      if (wb_wait > 0) begin
        wb_wait <= wb_wait - 1;
        if (wb_wait == 1) begin
          wr_done <= 1; last_b_cycle <= cyc; b_count <= b_count + 1;
        end
      end else if (wr_busy) begin
        wr_ready <= 1;
        if (wr_valid && wr_ready) begin
          for (k = 0; k < 16; k = k + 1)
            if (wr_strobe[k]) mem[(wr_addr + k) & 18'h3FFFF] <= wr_data[k*8 +: 8];
          if (wr_left == 1) begin
            wr_busy <= 0; wr_ready <= 0; wb_wait <= b_delay + 1;
          end else begin
            wr_addr <= wr_addr + 16; wr_left <= wr_left - 1;
          end
        end
      end else if (wr_request_valid && wr_request_ready) begin
        wr_busy <= 1; wr_addr <= wr_address & 32'h3FFFF;
        wr_left <= wr_beats; wr_ready <= 1;
      end
    end
  end

  always @(posedge clk) begin
    if (rst_n) begin
      cyc <= cyc + 1;
      if (done) begin done_seen <= 1; done_cycle <= cyc; end
      if (done && wr_done) b_after_done <= b_after_done + 1;
      if (done && wr_request_valid && wr_request_ready) aw_after_done <= aw_after_done + 1;
    end
  end

  initial begin
    #(10*MAXCYC);
    $display("WATCHDOG cyc=%0d err=%0d", cyc, errors);
    $fatal(1, "watchdog");
  end

  task load_bytes;
    input [1023:0] path;
    input integer base;
    input integer nbytes;
    begin
      for (i = 0; i < nbytes; i = i + 1) mem[base + i] = 8'h00;
      $readmemh(path, mem, base, base + nbytes - 1);
    end
  endtask

  task load_exp;
    input [1023:0] path;
    input integer nbytes;
    begin
      for (i = 0; i < nbytes; i = i + 1) expb[i] = 8'h00;
      $readmemh(path, expb, 0, nbytes - 1);
    end
  endtask

  initial begin
    if (!$value$plusargs("dir=%s", dir)) dir = "vectors/vec";
    if (!$value$plusargs("op=%d", op)) op = 17;
    if (!$value$plusargs("n=%d", n)) n = 1001;
    if (!$value$plusargs("out16=%d", out16)) out16 = 0;
    if (!$value$plusargs("mode=%d", mode)) mode = 0;
    if (!$value$plusargs("bdelay=%d", b_delay)) b_delay = 0;
    if (n > 2048) begin $display("n too large"); $fatal(1); end
    load_bytes({dir, "/a.hex"}, A_BASE & 32'h3FFFF, 4*n);
    load_bytes({dir, "/b.hex"}, B_BASE & 32'h3FFFF, 4*n);
    load_bytes({dir, "/c.hex"}, C_BASE & 32'h3FFFF, 4*n);
    if (out16) load_exp({dir, "/exp16.hex"}, 2*n);
    else       load_exp({dir, "/exp32.hex"}, 4*n);
    $display("VEC op=%0d n=%0d out16=%0d bdelay=%0d", op, n, out16, b_delay);

    descriptor = 0;
    descriptor[31:0] = 32'h22564543;
    descriptor[39:32] = op[7:0];
    descriptor[40] = 0;          // a16 in
    descriptor[41] = out16[0];   // out16
    descriptor[42] = 0;          // bscalar
    descriptor[43] = 0;          // ascalar
    descriptor[44] = 0;          // cscalar
    descriptor[45] = 0;          // a48
    descriptor[46] = 0;          // btiled
    descriptor[95:64] = A_BASE;
    descriptor[127:96] = B_BASE;
    descriptor[159:128] = C_BASE;
    descriptor[191:160] = D_BASE;
    descriptor[223:192] = n[31:0];
    descriptor[255:224] = 0;

    repeat (4) @(posedge clk);
    rst_n <= 1;
    @(posedge clk);
    // sentinel D
    for (i = 0; i < 4*n; i = i + 1) mem[(D_BASE + i) & 18'h3FFFF] = 8'hDE;
    @(posedge clk);
    while (!ready) @(posedge clk);
    start <= 1;
    @(posedge clk);
    start <= 0;
    while (!done && waited < MAXCYC) begin @(posedge clk); waited = waited + 1; end
    @(posedge clk);
    @(posedge clk);

    if (!done_seen) begin errors=errors+1; $display("FAIL no done"); end
    if (fault) begin errors=errors+1; $display("FAIL fault code=%02x", error_code); end
    if (completed_elements != n) begin errors=errors+1; $display("FAIL completed=%0d n=%0d", completed_elements, n); end
    if (aborted) begin errors=errors+1; $display("FAIL aborted"); end

    // independent output comparison
    if (out16) begin
      for (i = 0; i < n; i = i + 1) begin
        for (k = 0; k < 2; k = k + 1) begin
          if (mem[(D_BASE + 2*i + k) & 18'h3FFFF] !== expb[2*i + k]) begin
            errors = errors + 1;
            if (errors < 8) $display("FAIL d16 i=%0d byte=%0d got=%02x exp=%02x", i, k,
              mem[(D_BASE + 2*i + k) & 18'h3FFFF], expb[2*i + k]);
          end
        end
      end
    end else begin
      for (i = 0; i < n; i = i + 1) begin
        for (k = 0; k < 4; k = k + 1) begin
          if (mem[(D_BASE + 4*i + k) & 18'h3FFFF] !== expb[4*i + k]) begin
            errors = errors + 1;
            if (errors < 8) $display("FAIL d32 i=%0d byte=%0d got=%02x exp=%02x", i, k,
              mem[(D_BASE + 4*i + k) & 18'h3FFFF], expb[4*i + k]);
          end
        end
      end
    end
    if (b_after_done != 0) begin errors=errors+1; $display("FAIL b after done=%0d", b_after_done); end
    if (aw_after_done != 0) begin errors=errors+1; $display("FAIL aw after done=%0d", aw_after_done); end
    if (last_b_cycle >= done_cycle) begin errors=errors+1; $display("FAIL last_b=%0d done=%0d", last_b_cycle, done_cycle); end
    $display("RESULT op=%0d n=%0d out16=%0d cycles=%0d b=%0d last_b=%0d done=%0d errors=%0d",
             op, n, out16, cycles, b_count, last_b_cycle, done_cycle, errors);
    if (errors == 0 && !fault && done_seen) begin $display("PASS"); $finish; end
    else begin $display("FAIL"); $fatal(1, "mismatch"); end
  end
endmodule
