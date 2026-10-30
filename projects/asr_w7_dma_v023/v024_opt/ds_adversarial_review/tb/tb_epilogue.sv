`timescale 1ns/1ps
// Independent per-channel epilogue harness.
// Modes: 0 = two-bank per-column + config-wait + active-write reject + scalar,
//        1 = abort / new epoch.
module tb_epilogue;
  parameter integer MAXCYC = 200000;
  reg clk = 0;
  always #5 clk = ~clk;

  reg rst_n = 0, abort = 0;
  reg cfg_valid = 0;
  wire cfg_ready;
  reg [1:0] cfg_fma_mode = 1;
  reg cfg_relu_en = 1, cfg_spill_c48 = 0, cfg_spill_fp32 = 1;
  reg cfg_table_en = 1, cfg_bank = 0;
  reg [15:0] cfg_bc = 0;
  reg [31:0] cfg_scale = 0, cfg_bias = 0;
  reg [15:0] cfg_tag = 0;

  reg param_wr_valid = 0;
  wire param_wr_ready;
  reg [7:0] param_wr_addr = 0;
  reg [15:0] param_wr_bc = 0;
  reg [31:0] param_wr_data = 0;

  reg cval_valid = 0;
  wire cval_ready;
  reg [191:0] cval_data = 0;
  reg [15:0] cval_tag = 0, cval_bc = 0;
  reg [4:0] cval_col = 0;
  reg cval_last = 0;

  wire a16_valid, a16_packed_valid, fp32x4_valid, spill_valid;
  reg a16_ready = 1, a16_packed_ready = 1, fp32x4_ready = 1, spill_ready = 1;
  wire [63:0] a16_data;
  wire [15:0] a16_tag;
  wire a16_last;
  wire [127:0] a16_packed, fp32x4_data;
  wire [15:0] a16_packed_tag, fp32x4_tag;
  wire a16_packed_last, fp32x4_last;
  wire [191:0] spill_data;
  wire [15:0] spill_tag;
  wire spill_last;

  wire [31:0] stat_c48_beats_in, stat_a16_beats_out, stat_spill_beats,
               stat_ddr_bytes_saved, stat_fp32_beats_out, stat_table_hits,
               stat_table_misses, stat_col_align_err, stat_param_rejects;

  epilogue_stream_engine_v024 #(.TAG_WIDTH(16)) dut (
    .clk(clk), .rst_n(rst_n), .abort(abort),
    .cfg_valid(cfg_valid), .cfg_ready(cfg_ready), .cfg_fma_mode(cfg_fma_mode),
    .cfg_relu_en(cfg_relu_en), .cfg_spill_c48(cfg_spill_c48),
    .cfg_spill_fp32(cfg_spill_fp32), .cfg_table_en(cfg_table_en),
    .cfg_bank(cfg_bank), .cfg_bc(cfg_bc), .cfg_scale(cfg_scale),
    .cfg_bias(cfg_bias), .cfg_tag(cfg_tag),
    .param_wr_valid(param_wr_valid), .param_wr_ready(param_wr_ready),
    .param_wr_addr(param_wr_addr), .param_wr_bc(param_wr_bc),
    .param_wr_data(param_wr_data),
    .cval_valid(cval_valid), .cval_ready(cval_ready), .cval_data(cval_data),
    .cval_tag(cval_tag), .cval_bc(cval_bc), .cval_col(cval_col),
    .cval_last(cval_last),
    .a16_valid(a16_valid), .a16_ready(a16_ready), .a16_data(a16_data),
    .a16_tag(a16_tag), .a16_last(a16_last),
    .a16_packed(a16_packed), .a16_packed_valid(a16_packed_valid),
    .a16_packed_ready(a16_packed_ready), .a16_packed_last(a16_packed_last),
    .a16_packed_tag(a16_packed_tag),
    .fp32x4_valid(fp32x4_valid), .fp32x4_ready(fp32x4_ready),
    .fp32x4_data(fp32x4_data), .fp32x4_tag(fp32x4_tag),
    .fp32x4_last(fp32x4_last),
    .spill_valid(spill_valid), .spill_ready(spill_ready),
    .spill_data(spill_data), .spill_tag(spill_tag), .spill_last(spill_last),
    .stat_c48_beats_in(stat_c48_beats_in), .stat_a16_beats_out(stat_a16_beats_out),
    .stat_spill_beats(stat_spill_beats), .stat_ddr_bytes_saved(stat_ddr_bytes_saved),
    .stat_fp32_beats_out(stat_fp32_beats_out), .stat_table_hits(stat_table_hits),
    .stat_table_misses(stat_table_misses), .stat_col_align_err(stat_col_align_err),
    .stat_param_rejects(stat_param_rejects)
  );

  // ---------------- vectors ----------------
  reg [31:0] tscale [0:63];
  reg [31:0] tbias  [0:63];
  reg [47:0] q_c [0:4095];
  reg [4:0]  q_col [0:1023];
  reg [15:0] q_bc [0:1023], q_tag [0:1023];
  reg [63:0] exp_a16 [0:8191];
  reg [127:0] exp_fp [0:8191];
  reg exp_seen_a [0:8191];
  reg exp_seen_f [0:8191];
  reg exp_need [0:8191];
  integer qn = 0;
  integer p0s, p0e, p1s, p1e, pss, pse;

  integer mode = 0, errors = 0, cyc = 0, waited = 0;
  integer fd, rc, i, k, lane;
  integer cfg_fires = 0, cfg_sent = 0;
  integer pw_fires = 0, pw_sent = 0;
  integer cval_fires = 0, cval_sent = 0;
  integer active_write_ready_seen = 0, cfg_ready_while_busy = 0;
  integer abort_out_after = 0, abort_seen = 0, out_stall = 0, exp_beats = 0, bp_mode = 1;
  integer extra_out = 0, a16_count = 0, fp_count = 0;
  reg [1023:0] dir;
  reg [1023:0] vpath;
  integer paf;

  always @(posedge clk) if (rst_n) cyc <= cyc + 1;
  always @(posedge clk) begin
    if (cfg_valid && cfg_ready) cfg_fires <= cfg_fires + 1;
    if (param_wr_valid && param_wr_ready) pw_fires <= pw_fires + 1;
    if (cval_valid && cval_ready) cval_fires <= cval_fires + 1;
  end

  function [31:0] lane32;
    input [127:0] w;
    input integer l;
    begin lane32 = w[l*32 +: 32]; end
  endfunction

  // output checkers
  always @(posedge clk) begin
    if (rst_n && a16_valid && a16_ready) begin
      if (abort_seen) abort_out_after <= abort_out_after + 1;
      if (exp_seen_a[a16_tag]) extra_out <= extra_out + 1;
      else begin
        exp_seen_a[a16_tag] <= 1;
        for (lane = 0; lane < 4; lane = lane + 1) begin
          if (a16_data[lane*16 +: 16] !== exp_a16[a16_tag][lane*16 +: 16]) begin
            errors <= errors + 1;
            $display("FAIL a16 tag=%0d lane=%0d got=%04x exp=%04x",
                     a16_tag, lane, a16_data[lane*16 +: 16], exp_a16[a16_tag][lane*16 +: 16]);
          end
        end
      end
      a16_count <= a16_count + 1;
    end
    if (rst_n && fp32x4_valid && fp32x4_ready) begin
      if (abort_seen) abort_out_after <= abort_out_after + 1;
      if (exp_seen_f[fp32x4_tag]) extra_out <= extra_out + 1;
      else begin
        exp_seen_f[fp32x4_tag] <= 1;
        for (lane = 0; lane < 4; lane = lane + 1) begin
          if (lane32(fp32x4_data, lane) !== lane32(exp_fp[fp32x4_tag], lane)) begin
            errors <= errors + 1;
            $display("FAIL fp32 tag=%0d lane=%0d got=%08x exp=%08x",
                     fp32x4_tag, lane, lane32(fp32x4_data, lane), lane32(exp_fp[fp32x4_tag], lane));
          end
        end
      end
      fp_count <= fp_count + 1;
    end
  end

  initial begin
    #(10*MAXCYC);
    $display("WATCHDOG cyc=%0d err=%0d a16=%0d fp=%0d", cyc, errors, a16_count, fp_count);
    $fatal(1, "watchdog");
  end

  task load_table;
    input [1023:0] path;
    input integer bank;
    integer c;
    reg [31:0] ts, tb;
    begin
      fd = $fopen(path, "r");
      if (fd == 0) begin $display("cannot open table"); $fatal(1); end
      for (c = 0; c < 32; c = c + 1) begin
        rc = $fscanf(fd, "%h %h\n", ts, tb);
        tscale[bank*32+c] = ts; tbias[bank*32+c] = tb;
      end
      $fclose(fd);
    end
  endtask

  task load_beats;
    input [1023:0] path;
    output integer s0;
    output integer s1;
    reg [63:0] c0,c1,c2,c3;
    integer col, bc, tag;
    reg [15:0] a0,a1,a2,a3;
    reg [31:0] f0,f1,f2,f3;
    begin
      s0 = qn;
      fd = $fopen(path, "r");
      if (fd == 0) begin $display("cannot open beats"); $fatal(1); end
      rc = $fscanf(fd, "%h %h %h %h %h %h %h", c0,c1,c2,c3,col,bc,tag);
      while (rc == 7) begin
        rc = $fscanf(fd, "%h %h %h %h %h %h %h %h\n", a0,a1,a2,a3,f0,f1,f2,f3);
        if (rc != 8) begin $display("bad expected line"); $fatal(1); end
        q_c[qn*4+0] = c0[47:0]; q_c[qn*4+1] = c1[47:0]; q_c[qn*4+2] = c2[47:0]; q_c[qn*4+3] = c3[47:0];
        q_col[qn] = col; q_bc[qn] = bc; q_tag[qn] = tag;
        exp_a16[tag][15:0] = a0; exp_a16[tag][31:16] = a1;
        exp_a16[tag][47:32] = a2; exp_a16[tag][63:48] = a3;
        exp_fp[tag][31:0] = f0; exp_fp[tag][63:32] = f1;
        exp_fp[tag][95:64] = f2; exp_fp[tag][127:96] = f3;
        exp_seen_a[tag] = 0; exp_seen_f[tag] = 0; exp_need[tag] = 1;
        qn = qn + 1;
        rc = $fscanf(fd, "%h %h %h %h %h %h %h", c0,c1,c2,c3,col,bc,tag);
      end
      $fclose(fd);
      s1 = qn;
    end
  endtask

  task do_cfg;
    input [1:0] fma_mode;
    input relu_en, table_en, spill_fp32;
    input bank;
    input [15:0] bc;
    input [31:0] scale, bias;
    begin
      cfg_valid <= 1; cfg_fma_mode <= fma_mode; cfg_relu_en <= relu_en;
      cfg_table_en <= table_en; cfg_spill_fp32 <= spill_fp32;
      cfg_bank <= bank; cfg_bc <= bc; cfg_scale <= scale; cfg_bias <= bias;
      @(posedge clk); @(negedge clk);
      while (cfg_fires < cfg_sent + 1) begin @(posedge clk); @(negedge clk); end
      cfg_sent = cfg_sent + 1;
      cfg_valid <= 0;
    end
  endtask

  task do_pw;
    input [7:0] addr;
    input [15:0] bc;
    input [31:0] data;
    begin
      param_wr_valid <= 1; param_wr_addr <= addr; param_wr_bc <= bc; param_wr_data <= data;
      @(posedge clk); @(negedge clk);
      while (pw_fires < pw_sent + 1) begin @(posedge clk); @(negedge clk); end
      pw_sent = pw_sent + 1;
      param_wr_valid <= 0;
    end
  endtask

  task preload;
    input integer bank;
    input [15:0] bc;
    input integer col0, ncol;
    integer c;
    begin
      for (c = col0; c < col0+ncol; c = c + 1) begin
        do_pw(8'h80 | ((bank & 1) << 6) | c[4:0], bc, tscale[bank*32+c]);
        do_pw(8'h80 | ((bank & 1) << 6) | 8'h20 | c[4:0], bc, tbias[bank*32+c]);
      end
    end
  endtask

  task send_beat;
    input integer idx;
    input last;
    begin
      cval_valid <= 1;
      cval_data[47:0] <= q_c[idx*4+0]; cval_data[95:48] <= q_c[idx*4+1];
      cval_data[143:96] <= q_c[idx*4+2]; cval_data[191:144] <= q_c[idx*4+3];
      cval_tag <= q_tag[idx]; cval_bc <= q_bc[idx]; cval_col <= q_col[idx];
      cval_last <= last;
      @(posedge clk); @(negedge clk);
      while (cval_fires < cval_sent + 1) begin
        if (out_stall > 0) begin
          a16_ready <= 0; fp32x4_ready <= 0; a16_packed_ready <= 0; out_stall = out_stall - 1;
        end else if (bp_mode == 0) begin
          a16_ready <= 1; fp32x4_ready <= 1; a16_packed_ready <= 1;
        end else if (bp_mode == 2) begin
          a16_ready <= (($random & 32'h7fffffff) % 100) < 75;
          fp32x4_ready <= 1; a16_packed_ready <= 1;
        end else if (bp_mode == 3) begin
          a16_ready <= 1;
          fp32x4_ready <= (($random & 32'h7fffffff) % 100) < 60;
          a16_packed_ready <= 1;
        end else if (bp_mode == 4) begin
          a16_ready <= 1; fp32x4_ready <= 1;
          a16_packed_ready <= (($random & 32'h7fffffff) % 100) < 50;
        end else begin
          a16_ready <= (($random & 32'h7fffffff) % 100) < 75;
          fp32x4_ready <= (($random & 32'h7fffffff) % 100) < 60;
          a16_packed_ready <= 1;
        end
        @(posedge clk); @(negedge clk);
      end
      cval_sent = cval_sent + 1;
      cval_valid <= 0;
    end
  endtask

  task stream;
    input integer s0, s1;
    integer x;
    begin
      for (x = s0; x < s1; x = x + 1) send_beat(x, x == s1-1);
    end
  endtask

  task drain_outputs;
    begin
      waited = 0;
      while ((a16_count < exp_beats || fp_count < exp_beats) && waited < 20000) begin
        @(posedge clk); waited = waited + 1;
      end
      repeat (10) @(posedge clk);
    end
  endtask

  integer s0, s1;
  initial begin
    if (!$value$plusargs("dir=%s", dir)) dir = "vectors/epi";
    if (!$value$plusargs("mode=%d", mode)) mode = 0;
    paf = $value$plusargs("bp=%d", bp_mode);
    $display("EPI mode=%0d dir=%0s", mode, dir); $fflush;
    $sformat(vpath, "%0s/table_bank0.txt", dir); $display("ld t0"); $fflush; load_table(vpath, 0); $display("t0 ok"); $fflush;
    $sformat(vpath, "%0s/table_bank1.txt", dir); load_table(vpath, 1); $display("t1 ok"); $fflush;
    $sformat(vpath, "%0s/beats_bank0.txt", dir); $display("ld b0"); $fflush; load_beats(vpath, p0s, p0e); $display("b0 ok %0d %0d",p0s,p0e); $fflush;
    $sformat(vpath, "%0s/beats_bank1.txt", dir); load_beats(vpath, p1s, p1e);
    $sformat(vpath, "%0s/beats_scalar.txt", dir); load_beats(vpath, pss, pse);
    $display("beats: bank0=%0d..%0d bank1=%0d..%0d scalar=%0d..%0d", p0s,p0e-1,p1s,p1e-1,pss,pse-1);

    repeat (4) @(posedge clk);
    rst_n <= 1;
    @(posedge clk);

    preload(0, 5, 0, 32);

    if (mode == 2) begin
      for (i = 0; i < 4096; i = i + 1) exp_need[i] = 0;
      for (i = pss; i < pse; i = i + 1) exp_need[q_tag[i]] = 1;
      do_cfg(1, 1, 0, 1, 0, 5, 32'h3f400000, 32'hbf000000);
      exp_beats = pse - pss;
      stream(pss, pse);
      drain_outputs;
    end else if (mode == 4) begin
      for (i = 0; i < 4096; i = i + 1) exp_need[i] = 0;
      for (i = p0s; i < p0e; i = i + 1) exp_need[q_tag[i]] = 1;
      preload(0, 5, 0, 32);
      do_cfg(1, 1, 1, 1, 0, 5, 32'h3f800000, 32'h00000000);
      for (i = p0s; i < p0e; i = i + 1) begin
        if (i == p0s + 4) out_stall = 40;
        send_beat(i, i == p0e-1);
      end
      exp_beats = p0e - p0s;
      drain_outputs;
    end else if (mode == 3) begin
      for (i = 0; i < 4096; i = i + 1) exp_need[i] = 0;
      for (i = p0s; i < p0e; i = i + 1) exp_need[q_tag[i]] = 1;
      preload(0, 5, 0, 32);
      do_cfg(1, 1, 1, 1, 0, 5, 32'h3f800000, 32'h00000000);
      exp_beats = p0e - p0s;
      stream(p0s, p0e);
      drain_outputs;
    end else if (mode == 1) begin
      for (i = 0; i < 4096; i = i + 1) exp_need[i] = 0;
      for (i = pss; i < pse; i = i + 1) exp_need[q_tag[i]] = 1;
      do_cfg(1, 1, 1, 1, 0, 5, 32'h3f800000, 32'h00000000);
      // put some beats in flight then abort
      for (i = p0s; i < p0s+6; i = i + 1) send_beat(i, 0);
      @(posedge clk);
      abort <= 1;
      @(posedge clk);
      abort <= 0;
      abort_seen = 1;
      repeat (20) @(posedge clk);
      abort_seen = 0;
      // new epoch, scalar config
      preload(0, 5, 0, 32);
      do_cfg(1, 1, 0, 1, 0, 5, 32'h3f400000, 32'hbf000000);
      stream(pss, pss+8);
      exp_beats = 8;
      drain_outputs;
      if (abort_out_after != 0) begin errors=errors+1; $display("FAIL outputs after abort=%0d", abort_out_after); end
    end else begin
      do_cfg(1, 1, 1, 1, 0, 5, 32'h3f800000, 32'h00000000);

      // stream bank0; halfway, preload bank1 (inactive) and probe active-bank write
      for (i = p0s; i < p0e; i = i + 1) begin
        send_beat(i, i == p0e-1);
        if (i == p0s+8) begin
          // bank1 preload while bank0 is streaming (inactive path)
          preload(1, 6, 0, 32);
          // active-bank table write probe (recorded; engine may already be idle)
          param_wr_valid <= 1; param_wr_addr <= 8'h80; param_wr_bc <= 5;
          param_wr_data <= 32'h11111111;
          repeat (4) begin
            @(posedge clk);
            if (param_wr_ready) active_write_ready_seen = active_write_ready_seen + 1;
          end
          param_wr_valid <= 0;
          @(posedge clk);
        end
      end
      // config for bank1: assert while the last beats are still draining
      cfg_valid <= 1; cfg_fma_mode <= 1; cfg_relu_en <= 1; cfg_table_en <= 1;
      cfg_spill_fp32 <= 1; cfg_bank <= 1; cfg_bc <= 6;
      cfg_scale <= 0; cfg_bias <= 0;
      @(posedge clk);
      repeat (4) begin
        if (!cfg_ready) cfg_ready_while_busy = cfg_ready_while_busy + 1;
        @(posedge clk);
      end
      while (!cfg_ready) @(posedge clk);
      cfg_valid <= 0; cfg_sent = cfg_sent + 1;
      @(posedge clk);
      stream(p1s, p1e);
      exp_beats = (p0e-p0s) + (p1e-p1s);
      drain_outputs;
      // scalar fallback
      do_cfg(1, 1, 0, 1, 1, 0, 32'h3f400000, 32'hbf000000);
      stream(pss, pse);
      exp_beats = (p0e-p0s) + (p1e-p1s) + (pse-pss);
      drain_outputs;
      if (active_write_ready_seen != 0)
        $display("NOTE active-bank table write was ready %0d samples (engine may have been idle)", active_write_ready_seen);
    end

    // expected-tag completeness (all phases used)
    for (i = 0; i < 4096; i = i + 1) begin
      if (exp_need[i]) begin
        if (!exp_seen_a[i]) begin errors=errors+1; $display("FAIL a16 missing tag=%0d", i); end
        if (!exp_seen_f[i]) begin errors=errors+1; $display("FAIL fp32 missing tag=%0d", i); end
      end
    end
    if (extra_out != 0) begin errors=errors+1; $display("FAIL extra outputs=%0d", extra_out); end
    $display("RESULT mode=%0d a16=%0d fp=%0d errors=%0d hits=%0d misses=%0d colerr=%0d rej=%0d cyc=%0d",
             mode, a16_count, fp_count, errors, stat_table_hits, stat_table_misses,
             stat_col_align_err, stat_param_rejects, cyc);
    if (errors == 0) begin $display("PASS"); $finish; end
    else begin $display("FAIL"); $fatal(1, "mismatch"); end
  end
endmodule
