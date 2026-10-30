`timescale 1ns/1ps
// Independent FMA DUT harness. Drives only clk/rst_n/flush/ready-valid.
// Vectors: <a> <b> <c> <expected> hex, expected from gold/fma_gold.py.
// Modes: 0 stream+random backpressure, 1 flush (old epoch must vanish),
//        2 reset, 3 II=1, 4 strict flush-handshake probe.
module tb_fma;
  parameter integer MAXN = 40000;
  parameter integer MAXCYC = 400000;

  reg clk = 0;
  always #5 clk = ~clk;

  reg rst_n = 0, flush = 0;
  reg in_valid = 0;
  wire in_ready;
  reg [31:0] in_a = 0, in_b = 0, in_c = 0;
  reg [15:0] in_tag = 0;
  reg in_last = 0;
  wire out_valid;
  reg out_ready = 1;
  wire [31:0] out_result;
  wire [15:0] out_tag;
  wire out_last;

  fp32_fma_pipe #(.TAG_WIDTH(16)) dut (
    .clk(clk), .rst_n(rst_n), .flush(flush),
    .in_valid(in_valid), .in_ready(in_ready),
    .in_a(in_a), .in_b(in_b), .in_c(in_c), .in_tag(in_tag), .in_last(in_last),
    .out_valid(out_valid), .out_ready(out_ready),
    .out_result(out_result), .out_tag(out_tag), .out_last(out_last)
  );

  reg [31:0] va [0:MAXN-1];
  reg [31:0] vb [0:MAXN-1];
  reg [31:0] vc [0:MAXN-1];
  reg [31:0] ve [0:MAXN-1];

  integer n = 0, mode = 0, errors = 0, out_count = 0, sent = 0;
  integer fd, rc, i, waited = 0, seen_new = 0, extra_out = 0;
  integer old_out_after_flush = 0, flush_handshakes = 0;
  reg [1023:0] vfile;
  integer cyc = 0;
  integer stall_left = 0, force_stall = 0;
  reg bp_mode = 0;
  reg [31:0] bp_lfsr = 32'h0badf00d;
  reg [15:0] tag_base = 16'd1000;
  reg flush_seen = 0;
  integer acc_count = 0, first_accept = -1, last_accept = -1, max_gap = 0;
  integer dbg = 0;

  function integer pct_lt;
    input integer pct;
    integer r;
    begin
      r = $random;
      if (r < 0) r = -r;
      pct_lt = ((r % 100) < pct);
    end
  endfunction

  // backpressure / output-ready generator (single driver)
  always @(posedge clk) begin
    bp_lfsr <= {bp_lfsr[30:0], bp_lfsr[31]^bp_lfsr[21]^bp_lfsr[1]^bp_lfsr[0]};
    if (force_stall > 0) begin
      out_ready <= 0;
      force_stall <= force_stall - 1;
    end else if (bp_mode) begin
      if (stall_left > 0) begin
        out_ready <= 0;
        stall_left <= stall_left - 1;
      end else begin
        out_ready <= bp_lfsr[0] | bp_lfsr[3];
        if (bp_lfsr[7:0] == 0) stall_left <= 20;
      end
    end else begin
      out_ready <= 1;
    end
  end

  // accept / II monitor
  always @(posedge clk) begin
    if (rst_n) begin
      cyc <= cyc + 1;
      if (in_valid && in_ready) begin
        acc_count <= acc_count + 1;
        if (dbg) $display("ACC tag=%0d cyc=%0d sent=%0d", in_tag, cyc, sent);
        if (first_accept < 0) first_accept <= cyc;
        if (last_accept >= 0 && (cyc - last_accept) > max_gap) max_gap <= cyc - last_accept;
        last_accept <= cyc;
      end
    end
  end

  // ---------------- output checker ----------------
  always @(posedge clk) begin
    if (rst_n && out_valid && out_ready) begin
      if (mode == 1) begin
        if (out_tag < tag_base) begin
          if (flush_seen) begin
            old_out_after_flush <= old_out_after_flush + 1;
            $display("FAIL old-epoch output after flush: tag=%0d result=%08x cyc=%0d",
                     out_tag, out_result, cyc);
          end
        end else if (seen_new < n) begin
          if (out_result !== ve[out_tag - tag_base]) begin
            errors <= errors + 1;
            $display("FAIL new result tag=%0d got=%08x exp=%08x cyc=%0d",
                     out_tag, out_result, ve[out_tag - tag_base], cyc);
          end
          seen_new <= seen_new + 1;
        end else begin
          extra_out <= extra_out + 1;
          $display("EXTRA tag=%0d result=%08x cyc=%0d seen=%0d", out_tag, out_result, cyc, seen_new);
        end
      end else begin
        if (out_count >= n) begin
          extra_out <= extra_out + 1;
        end else if (out_tag >= n) begin
          extra_out <= extra_out + 1;
          out_count <= out_count + 1;
        end else begin
          if (out_result !== ve[out_tag]) begin
            errors <= errors + 1;
            $display("FAIL tag=%0d got=%08x exp=%08x cyc=%0d",
                     out_tag, out_result, ve[out_tag], cyc);
          end
          if (out_last !== (out_tag == n - 1)) begin
            errors <= errors + 1;
            $display("FAIL out_last tag=%0d last=%b exp=%b", out_tag, out_last, (out_tag == n-1));
          end
          out_count <= out_count + 1;
        end
      end
    end
  end

  initial begin
    #(10 * MAXCYC);
    $display("WATCHDOG timeout cyc=%0d mode=%0d out=%0d err=%0d", cyc, mode, out_count, errors);
    $fatal(1, "watchdog");
  end

  task load_vectors;
    output integer cnt;
    begin
      cnt = 0;
      rc = $fscanf(fd, "%h %h %h %h\n", va[cnt], vb[cnt], vc[cnt], ve[cnt]);
      while (rc == 4 && cnt < MAXN - 1) begin
        cnt = cnt + 1;
        rc = $fscanf(fd, "%h %h %h %h\n", va[cnt], vb[cnt], vc[cnt], ve[cnt]);
      end
    end
  endtask

  // drive one item and wait until the accept counter proves the handshake
  task send_one;
    input integer idx;
    input [15:0] tag;
    begin
      in_valid <= 1; in_a <= va[idx]; in_b <= vb[idx]; in_c <= vc[idx];
      in_tag <= tag; in_last <= (tag == n - 1);
      @(posedge clk);
      @(negedge clk);
      while (acc_count < sent + 1) begin
        if (bp_mode && pct_lt(40)) in_valid <= 0; else in_valid <= 1;
        @(posedge clk);
        @(negedge clk);
      end
      in_valid <= 0;
      sent = sent + 1;
    end
  endtask

  initial begin
    if (!$value$plusargs("vec=%s", vfile)) begin $display("need +vec"); $fatal(1); end
    if (!$value$plusargs("mode=%d", mode)) mode = 0;
    if ($test$plusargs("dbg")) dbg = 1;
    fd = $fopen(vfile, "r");
    if (fd == 0) begin $display("cannot open %0s", vfile); $fatal(1); end
    load_vectors(n);
    $fclose(fd);
    $display("MODE=%0d N=%0d", mode, n);
    if (n < 1) begin $display("FAIL empty vectors"); $fatal(1); end

    repeat (4) @(posedge clk);
    rst_n <= 1;
    @(posedge clk);

    if (mode == 1) begin
      // put exactly a pipeline-full of OLD items in flight, then flush
      force_stall <= 40;
      for (i = 0; i < 4 && i < n; i = i + 1) send_one(i, i[15:0]);
      in_valid <= 0;
      force_stall <= 0;
      @(posedge clk);
      flush <= 1;
      @(posedge clk);
      flush <= 0;
      flush_seen = 1;
      bp_mode <= 1;
      force_stall <= 40;
      repeat (5) @(posedge clk);
      for (i = 0; i < n; i = i + 1) send_one(i, tag_base + i[15:0]);
      in_valid <= 0;
      while (seen_new < n && waited < MAXCYC) begin @(posedge clk); waited = waited + 1; end
      repeat (10) @(posedge clk);
      if (seen_new != n) begin errors = errors + 1; $display("FAIL flush: new outputs %0d/%0d", seen_new, n); end
      if (old_out_after_flush != 0) errors = errors + 1;
      if (extra_out != 0) begin errors = errors + 1; $display("FAIL flush extra %0d", extra_out); end
    end else if (mode == 2) begin
      force_stall <= 40;
      for (i = 0; i < n && i < 50; i = i + 1) send_one(i, i[15:0]);
      in_valid <= 0;
      repeat (3) @(posedge clk);
      rst_n <= 0;
      repeat (3) @(posedge clk);
      rst_n <= 1;
      @(posedge clk);
      out_count <= 0;
      bp_mode <= 1;
      force_stall <= 10;
      for (i = 0; i < n; i = i + 1) send_one(i, i[15:0]);
      in_valid <= 0;
      while (out_count < n && waited < MAXCYC) begin @(posedge clk); waited = waited + 1; end
      repeat (10) @(posedge clk);
      if (out_count != n) begin errors = errors + 1; $display("FAIL reset outputs %0d/%0d", out_count, n); end
    end else if (mode == 3) begin
      bp_mode <= 0;
      in_valid <= 1;
      @(negedge clk);
      for (i = 0; i < n; i = i + 1) begin
        in_a <= va[i]; in_b <= vb[i]; in_c <= vc[i];
        in_tag <= i[15:0]; in_last <= (i == n-1);
        @(posedge clk);
        @(negedge clk);
        while (acc_count < sent + 1) begin @(posedge clk); @(negedge clk); end
        sent = sent + 1;
      end
      in_valid <= 0;
      while (out_count < n && waited < MAXCYC) begin @(posedge clk); waited = waited + 1; end
      $display("II_ACCEPT span=%0d n=%0d max_gap=%0d accepted=%0d",
               last_accept - first_accept + 1, n, max_gap, acc_count);
      if (max_gap > 1) begin errors = errors + 1; $display("FAIL II gap %0d", max_gap); end
      if (out_count != n) begin errors = errors + 1; $display("FAIL II outputs %0d/%0d", out_count, n); end
    end else if (mode == 4) begin
      bp_mode <= 0;
      in_valid <= 1; in_a <= 32'hdeadbeef; in_b <= 32'hdeadbeef;
      in_c <= 32'hdeadbeef; in_tag <= 16'hffff; in_last <= 0;
      flush <= 1;
      repeat (4) begin
        @(posedge clk);
        if (in_ready && in_valid) flush_handshakes = flush_handshakes + 1;
      end
      flush <= 0; in_valid <= 0;
      $display("FLUSH_HANDSHAKES=%0d", flush_handshakes);
      if (flush_handshakes != 0) begin
        errors = errors + 1;
        $display("FAIL in_ready accepted traffic while flush was asserted");
      end
    end else begin
      bp_mode <= 1;
      for (i = 0; i < n; i = i + 1) send_one(i, i[15:0]);
      in_valid <= 0;
      while (out_count < n && waited < MAXCYC) begin @(posedge clk); waited = waited + 1; end
      repeat (20) @(posedge clk);
      if (out_count != n) begin errors = errors + 1; $display("FAIL stream outputs %0d/%0d", out_count, n); end
    end

    if (extra_out != 0) $display("FAIL extra outputs %0d", extra_out);
    $display("RESULT mode=%0d n=%0d out=%0d errors=%0d cycles=%0d", mode, n, out_count, errors, cyc);
    if (errors == 0 && extra_out == 0 && old_out_after_flush == 0) begin
      $display("PASS");
      $finish;
    end else begin
      $display("FAIL");
      $fatal(1, "mismatch");
    end
  end
endmodule
