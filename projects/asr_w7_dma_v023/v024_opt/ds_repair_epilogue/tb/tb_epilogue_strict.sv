`timescale 1ns/1ps
// Independent strict epilogue gate (repair tree).
//
// Differences from ds_adversarial_review/tb/tb_epilogue.sv:
//   * every consumer ready is driven continuously by a local clocked driver,
//     including during config/param/drain waits (the review TB froze ready
//     after the last send beat, which is not a legal AXI-Stream stimulus);
//   * independent random / long-window / bounded-full-stall profiles on
//     a16, a16_packed, fp32x4 and spill;
//   * valid/payload stability checks on all four output channels;
//   * packed data/tag/last checked against an independently built pair queue;
//   * spill data/tag/last checked against the accepted input beat;
//   * exact expected A16/packed/FP32/spill beat counts and tag completeness;
//   * multi-phase bank0 -> bank1 -> scalar, abort/recover, spill, and
//     1..32-beat boundary scenarios.
//
// Exit status: 0 only on PASS. Any mismatch, stability error, missing/extra
// beat, timeout or count error calls $fatal(1).
module tb_epilogue_strict;
  parameter integer MAXCYC = 400000;
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
  reg [47:0] q_c [0:8191];
  reg [4:0]  q_col [0:2047];
  reg [15:0] q_bc [0:2047], q_tag [0:2047];
  reg [63:0] exp_a16 [0:8191];
  reg [127:0] exp_fp [0:8191];
  reg exp_seen_a [0:8191];
  reg exp_seen_f [0:8191];
  reg exp_need [0:8191];
  reg exp_last_a [0:8191];
  reg exp_last_f [0:8191];
  reg [127:0] pq_data [0:2047];
  reg [15:0]  pq_tag  [0:2047];
  reg         pq_last [0:2047];
  integer qn = 0, pq_n = 0, pc = 0;
  integer p0s,p0e,p1s,p1e,pss,pse;

  integer mode = 0, errors = 0, cyc = 0, waited = 0;
  integer fd, rc, i, k, lane;
  integer cfg_fires = 0, cfg_sent = 0;
  integer pw_fires = 0, pw_sent = 0;
  integer cval_fires = 0, cval_sent = 0;
  integer a16_count = 0, fp_count = 0, pack_count = 0, spill_count = 0;
  integer exp_a16_n = 0, exp_fp_n = 0, exp_pack_n = 0, exp_spill_n = 0;
  integer exp_a16_c = 0, exp_fp_c = 0, exp_pack_c = 0, exp_spill_c = 0;
  integer extra_a = 0, extra_f = 0;
  integer abort_seen = 0, abort_out_after = 0, abort_cycle = -1;
  integer bp_profile = 1, seed = 1, freeze_left = 0, freeze_at = -1;
  integer spill_hold = 0;
  integer n0 = 32, n1 = 32, ns = 8;
  integer colerr_expected = 0;
  integer cfg_ready_while_busy = 0, active_write_ready_seen = 0;
  reg [1023:0] dir, vpath;

  always @(posedge clk) if (rst_n) cyc <= cyc + 1;
  always @(posedge clk) begin
    if (cfg_valid && cfg_ready) cfg_fires <= cfg_fires + 1;
    if (param_wr_valid && param_wr_ready) pw_fires <= pw_fires + 1;
    if (cval_valid && cval_ready) cval_fires <= cval_fires + 1;
  end

  // ---------------- continuous independent ready driver ----------------
  // Never frozen: even during config/param/drain waits this keeps toggling.
  always @(negedge clk) begin
    if (!rst_n) begin
      a16_ready <= 1; a16_packed_ready <= 1; fp32x4_ready <= 1; spill_ready <= 1;
      freeze_left <= 0;
    end else if (freeze_left > 0) begin
      a16_ready <= 0; a16_packed_ready <= 0; fp32x4_ready <= 0; spill_ready <= 0;
      freeze_left <= freeze_left - 1;
    end else if (bp_profile == 0) begin
      a16_ready <= 1; a16_packed_ready <= 1; fp32x4_ready <= 1; spill_ready <= 1;
    end else if (bp_profile == 2) begin
      // coprime long windows: create every combination of one/two channels low
      a16_ready        <= ((cyc % 97) >= 61);
      a16_packed_ready <= ((cyc % 89) >= 53);
      fp32x4_ready     <= ((cyc % 83) >= 47);
      spill_ready      <= ((cyc % 79) >= 43);
    end else if (bp_profile == 3) begin
      // AR-006 shape: A16 and FP32 independent random, packed/spill ready
      a16_ready        <= (($random(seed) & 32'h7fffffff) % 100) < 65;
      fp32x4_ready     <= (($random(seed) & 32'h7fffffff) % 100) < 55;
      a16_packed_ready <= 1; spill_ready <= 1;
    end else if (bp_profile == 4) begin
      // packed-heavy long stall
      a16_ready        <= 1;
      a16_packed_ready <= ((cyc % 71) >= 39);
      fp32x4_ready     <= 1;
      spill_ready      <= 1;
    end else begin
      // profile 1: all four independent random
      a16_ready        <= (($random(seed) & 32'h7fffffff) % 100) < 70;
      a16_packed_ready <= (($random(seed) & 32'h7fffffff) % 100) < 60;
      fp32x4_ready     <= (($random(seed) & 32'h7fffffff) % 100) < 65;
      spill_ready      <= (($random(seed) & 32'h7fffffff) % 100) < 75;
    end
    if (spill_hold) spill_ready <= 1'b0;
  end

  // ---------------- output checkers ----------------
  function [31:0] lane32;
    input [127:0] w; input integer l;
    begin lane32 = w[l*32 +: 32]; end
  endfunction

  // stability saves
  reg        p_a_v=0,p_p_v=0,p_f_v=0,p_s_v=0;
  reg        p_a_r=0,p_p_r=0,p_f_r=0,p_s_r=0;
  reg [63:0] p_a_d=0;  reg [15:0] p_a_t=0; reg p_a_l=0;
  reg [127:0]p_p_d=0;  reg [15:0] p_p_t=0; reg p_p_l=0;
  reg [127:0]p_f_d=0;  reg [15:0] p_f_t=0; reg p_f_l=0;
  reg [191:0]p_s_d=0;  reg [15:0] p_s_t=0; reg p_s_l=0;

  always @(posedge clk) begin
    if (rst_n && !abort) begin
      // ---- valid stability while !ready ----
      if (p_a_v && !p_a_r)
        if (!a16_valid || a16_data!==p_a_d || a16_tag!==p_a_t || a16_last!==p_a_l) begin
          errors=errors+1; $display("FAIL STABLE a16 tag=%0d", p_a_t); end
      if (p_p_v && !p_p_r)
        if (!a16_packed_valid || a16_packed!==p_p_d || a16_packed_tag!==p_p_t || a16_packed_last!==p_p_l) begin
          errors=errors+1; $display("FAIL STABLE packed tag=%0d", p_p_t); end
      if (p_f_v && !p_f_r)
        if (!fp32x4_valid || fp32x4_data!==p_f_d || fp32x4_tag!==p_f_t || fp32x4_last!==p_f_l) begin
          errors=errors+1; $display("FAIL STABLE fp32 tag=%0d", p_f_t); end
      if (p_s_v && !p_s_r)
        if (!spill_valid || spill_data!==p_s_d || spill_tag!==p_s_t || spill_last!==p_s_l) begin
          errors=errors+1; $display("FAIL STABLE spill tag=%0d", p_s_t); end

      // ---- A16 ----
      if (a16_valid && a16_ready) begin
        if (abort_seen) abort_out_after=abort_out_after+1;
        if (a16_tag > 8191) begin errors=errors+1; $display("FAIL a16 tag range %0d",a16_tag); end
        else if (exp_seen_a[a16_tag]) extra_a=extra_a+1;
        else begin
          exp_seen_a[a16_tag] <= 1;
          for (lane=0; lane<4; lane=lane+1)
            if (a16_data[lane*16 +: 16] !== exp_a16[a16_tag][lane*16 +: 16]) begin
              errors=errors+1; $display("FAIL a16 tag=%0d lane=%0d got=%04x exp=%04x",
                a16_tag,lane,a16_data[lane*16 +: 16],exp_a16[a16_tag][lane*16 +: 16]); end
        end
        if (exp_need[a16_tag] && a16_last !== exp_last_a[a16_tag]) begin
          errors=errors+1; $display("FAIL a16 last tag=%0d got=%0d exp=%0d",a16_tag,a16_last,exp_last_a[a16_tag]); end
        a16_count=a16_count+1;
      end
      // ---- FP32 ----
      if (fp32x4_valid && fp32x4_ready) begin
        if (abort_seen) abort_out_after=abort_out_after+1;
        if (fp32x4_tag > 8191) begin errors=errors+1; $display("FAIL fp tag range %0d",fp32x4_tag); end
        else if (exp_seen_f[fp32x4_tag]) extra_f=extra_f+1;
        else begin
          exp_seen_f[fp32x4_tag] <= 1;
          for (lane=0; lane<4; lane=lane+1)
            if (lane32(fp32x4_data,lane) !== lane32(exp_fp[fp32x4_tag],lane)) begin
              errors=errors+1; $display("FAIL fp tag=%0d lane=%0d got=%08x exp=%08x",
                fp32x4_tag,lane,lane32(fp32x4_data,lane),lane32(exp_fp[fp32x4_tag],lane)); end
        end
        if (exp_need[fp32x4_tag] && fp32x4_last !== exp_last_f[fp32x4_tag]) begin
          errors=errors+1; $display("FAIL fp last tag=%0d got=%0d exp=%0d",fp32x4_tag,fp32x4_last,exp_last_f[fp32x4_tag]); end
        fp_count=fp_count+1;
      end
      // ---- packed (order queue) ----
      if (a16_packed_valid && a16_packed_ready) begin
        if (pc >= pq_n) begin errors=errors+1; $display("FAIL packed extra beat"); end
        else begin
          if (a16_packed !== pq_data[pc] || a16_packed_tag !== pq_tag[pc] || a16_packed_last !== pq_last[pc]) begin
            errors=errors+1;
            $display("FAIL packed[%0d] got tag=%0d last=%0d exp tag=%0d last=%0d",
                     pc,a16_packed_tag,a16_packed_last,pq_tag[pc],pq_last[pc]);
          end
          pc=pc+1;
        end
        pack_count=pack_count+1;
      end
      // ---- spill (tee of accepted input) ----
      if (spill_valid && spill_ready) begin
        if (!(cval_valid && cval_ready)) begin
          errors=errors+1; $display("FAIL spill fired without input handshake");
        end else if (spill_data!==cval_data || spill_tag!==cval_tag || spill_last!==cval_last) begin
          errors=errors+1; $display("FAIL spill payload tag=%0d",cval_tag);
        end
        spill_count=spill_count+1;
      end
    end
    // save
    p_a_v<=a16_valid; p_a_r<=a16_ready; p_a_d<=a16_data; p_a_t<=a16_tag; p_a_l<=a16_last;
    p_p_v<=a16_packed_valid; p_p_r<=a16_packed_ready; p_p_d<=a16_packed; p_p_t<=a16_packed_tag; p_p_l<=a16_packed_last;
    p_f_v<=fp32x4_valid; p_f_r<=fp32x4_ready; p_f_d<=fp32x4_data; p_f_t<=fp32x4_tag; p_f_l<=fp32x4_last;
    p_s_v<=spill_valid; p_s_r<=spill_ready; p_s_d<=spill_data; p_s_t<=spill_tag; p_s_l<=spill_last;
  end

  initial begin
    #(10*MAXCYC);
    $display("WATCHDOG cyc=%0d err=%0d a16=%0d pack=%0d fp=%0d spill=%0d pc=%0d/%0d",
             cyc,errors,a16_count,pack_count,fp_count,spill_count,pc,pq_n);
    $fatal(1,"watchdog");
  end

  // ---------------- vector loaders ----------------
  task load_table;
    input [1023:0] path; input integer bank;
    integer c; reg [31:0] ts, tb;
    begin
      fd=$fopen(path,"r"); if (fd==0) begin $display("cannot open %0s",path); $fatal(1); end
      for (c=0;c<32;c=c+1) begin
        rc=$fscanf(fd,"%h %h\n",ts,tb);
        tscale[bank*32+c]=ts; tbias[bank*32+c]=tb;
      end
      $fclose(fd);
    end
  endtask

  task load_beats;
    input [1023:0] path; output integer s0, s1;
    reg [63:0] c0,c1,c2,c3; reg [31:0] f0,f1,f2,f3;
    reg [15:0] a0,a1,a2,a3;
    integer col,bc,tag;
    begin
      s0=qn;
      fd=$fopen(path,"r"); if (fd==0) begin $display("cannot open %0s",path); $fatal(1); end
      rc=$fscanf(fd,"%h %h %h %h %h %h %h",c0,c1,c2,c3,col,bc,tag);
      while (rc==7) begin
        rc=$fscanf(fd,"%h %h %h %h %h %h %h %h\n",a0,a1,a2,a3,f0,f1,f2,f3);
        if (rc!=8) begin $display("bad expected line"); $fatal(1); end
        q_c[qn*4+0]=c0[47:0]; q_c[qn*4+1]=c1[47:0]; q_c[qn*4+2]=c2[47:0]; q_c[qn*4+3]=c3[47:0];
        q_col[qn]=col; q_bc[qn]=bc; q_tag[qn]=tag;
        exp_a16[tag][15:0]=a0;  exp_a16[tag][31:16]=a1;
        exp_a16[tag][47:32]=a2; exp_a16[tag][63:48]=a3;
        exp_fp[tag][31:0]=f0;   exp_fp[tag][63:32]=f1;
        exp_fp[tag][95:64]=f2;  exp_fp[tag][127:96]=f3;
        exp_seen_a[tag]=0; exp_seen_f[tag]=0; exp_need[tag]=1;
        qn=qn+1;
        rc=$fscanf(fd,"%h %h %h %h %h %h %h",c0,c1,c2,c3,col,bc,tag);
      end
      $fclose(fd);
      s1=qn;
    end
  endtask

  // expected last flags + packed pair queue for one phase
  task mark_phase;
    input integer s0,s1;
    begin
      for (i=s0;i<s1;i=i+1) begin
        exp_need[q_tag[i]]=1; exp_last_a[q_tag[i]]=0; exp_last_f[q_tag[i]]=0;
      end
      exp_last_a[q_tag[s1-1]]=1; exp_last_f[q_tag[s1-1]]=1;
      exp_a16_n=exp_a16_n+(s1-s0);
      exp_fp_n =exp_fp_n +(s1-s0);
      i=s0;
      while (i<s1) begin
        exp_pack_n=exp_pack_n+1;
        if (i+1<s1) begin
          pq_data[pq_n]={exp_a16[q_tag[i+1]],exp_a16[q_tag[i]]};
          pq_tag[pq_n]=q_tag[i];
          pq_last[pq_n]=(i+1==s1-1);
          i=i+2;
        end else begin
          pq_data[pq_n]={64'd0,exp_a16[q_tag[i]]};
          pq_tag[pq_n]=q_tag[i];
          pq_last[pq_n]=1;
          i=i+1;
        end
        pq_n=pq_n+1;
      end
    end
  endtask

  // ---------------- BFMs ----------------
  task do_cfg;
    input [1:0] fma_mode; input relu_en, table_en, spill_fp32, spill48;
    input bank; input [15:0] bc; input [31:0] scale, bias;
    begin
      cfg_valid<=1; cfg_fma_mode<=fma_mode; cfg_relu_en<=relu_en;
      cfg_table_en<=table_en; cfg_spill_fp32<=spill_fp32; cfg_spill_c48<=spill48;
      cfg_bank<=bank; cfg_bc<=bc; cfg_scale<=scale; cfg_bias<=bias;
      @(posedge clk); @(negedge clk);
      while (cfg_fires < cfg_sent+1) begin @(posedge clk); @(negedge clk); end
      cfg_sent=cfg_sent+1;
      cfg_valid<=0;
    end
  endtask

  task do_pw;
    input [7:0] addr; input [15:0] bc; input [31:0] data;
    begin
      param_wr_valid<=1; param_wr_addr<=addr; param_wr_bc<=bc; param_wr_data<=data;
      @(posedge clk); @(negedge clk);
      while (pw_fires < pw_sent+1) begin @(posedge clk); @(negedge clk); end
      pw_sent=pw_sent+1;
      param_wr_valid<=0;
    end
  endtask

  task preload;
    input integer bank; input [15:0] bc; input integer col0, ncol;
    integer c;
    begin
      for (c=col0;c<col0+ncol;c=c+1) begin
        do_pw(8'h80|((bank&1)<<6)|c[4:0], bc, tscale[bank*32+c]);
        do_pw(8'h80|((bank&1)<<6)|8'h20|c[4:0], bc, tbias[bank*32+c]);
      end
    end
  endtask

  task send_beat;
    input integer idx; input last;
    begin
      cval_valid<=1;
      cval_data[47:0]<=q_c[idx*4+0]; cval_data[95:48]<=q_c[idx*4+1];
      cval_data[143:96]<=q_c[idx*4+2]; cval_data[191:144]<=q_c[idx*4+3];
      cval_tag<=q_tag[idx]; cval_bc<=q_bc[idx]; cval_col<=q_col[idx];
      cval_last<=last;
      @(posedge clk); @(negedge clk);
      while (cval_fires < cval_sent+1) begin @(posedge clk); @(negedge clk); end
      cval_sent=cval_sent+1;
      cval_valid<=0;
    end
  endtask

  task stream;
    input integer s0,s1; input freeze_pos;
    integer x;
    begin
      for (x=s0;x<s1;x=x+1) begin
        if (freeze_pos >= 0 && x == freeze_pos) freeze_left = 64;
        send_beat(x, x==s1-1);
      end
    end
  endtask

  task wait_drain;
    begin
      waited=0;
      while ((a16_count<exp_a16_c || fp_count<exp_fp_c ||
              pack_count<exp_pack_c || spill_count<exp_spill_c) && waited<MAXCYC) begin
        @(posedge clk); waited=waited+1;
      end
      repeat (30) @(posedge clk);
    end
  endtask

  integer s0,s1, total_phases;
  initial begin
    if (!$value$plusargs("dir=%s",dir)) dir="vectors";
    if (!$value$plusargs("mode=%d",mode)) mode=0;
    if (!$value$plusargs("bp=%d",bp_profile)) bp_profile=1;
    if (!$value$plusargs("seed=%d",seed)) seed=1;
    if ((seed&1)==0) seed=seed+1;
    if (!$value$plusargs("n0=%d",n0)) n0=32;
    if (!$value$plusargs("n1=%d",n1)) n1=32;
    if (!$value$plusargs("ns=%d",ns)) ns=8;
    $display("STRICT mode=%0d dir=%0s bp=%0d seed=%0d n0=%0d n1=%0d ns=%0d",
             mode,dir,bp_profile,seed,n0,n1,ns); $fflush;

    $sformat(vpath,"%0s/table_bank0.txt",dir); load_table(vpath,0);
    $sformat(vpath,"%0s/table_bank1.txt",dir); load_table(vpath,1);
    $sformat(vpath,"%0s/beats_bank0.txt",dir); load_beats(vpath,p0s,p0e);
    $sformat(vpath,"%0s/beats_bank1.txt",dir); load_beats(vpath,p1s,p1e);
    $sformat(vpath,"%0s/beats_scalar.txt",dir); load_beats(vpath,pss,pse);
    $display("beats: bank0=%0d..%0d bank1=%0d..%0d scalar=%0d..%0d",
             p0s,p0e-1,p1s,p1e-1,pss,pse-1); $fflush;

    for (i=0;i<8192;i=i+1) begin
      exp_need[i]=0; exp_seen_a[i]=0; exp_seen_f[i]=0;
      exp_last_a[i]=0; exp_last_f[i]=0;
    end
    repeat (4) @(posedge clk);
    rst_n<=1;
    @(posedge clk);

    if (mode==3) begin
      // boundary: one bank0 phase of n0 beats
      if (n0<1) n0=1; if (n0>512) n0=512;
      preload(0,5,0,32);
      mark_phase(p0s,p0s+n0);
      do_cfg(1,1,1,1,0,0,5,32'h3f800000,32'h00000000);
      exp_a16_c=exp_a16_n; exp_fp_c=exp_fp_n;
      exp_pack_c=exp_pack_n; exp_spill_c=0;
      stream(p0s,p0s+n0,-1);
      wait_drain;
    end else if (mode==1) begin
      // abort / recover
      preload(0,5,0,32);
      do_cfg(1,1,1,1,0,0,5,32'h3f800000,32'h00000000);
      for (i=p0s;i<p0s+6;i=i+1) send_beat(i,0);
      @(posedge clk);
      abort<=1; @(posedge clk); abort<=0; abort_seen=1; abort_cycle=cyc;
      repeat (20) @(posedge clk);
      abort_seen=0;
      // new epoch: scalar; pre-abort partial outputs are not scored again
      a16_count=0; fp_count=0; pack_count=0; spill_count=0; pc=0;
      for (i=0;i<8192;i=i+1) begin exp_need[i]=0; exp_seen_a[i]=0; exp_seen_f[i]=0; end
      // new epoch: scalar
      do_pw(8'h00,0,32'h3f400000);   // legacy scale 0.75
      do_pw(8'h01,0,32'hbf000000);   // legacy bias -0.5
      mark_phase(pss,pss+ns);
      do_cfg(1,1,0,1,0,0,0,32'h3f400000,32'hbf000000);
      exp_a16_c=ns; exp_fp_c=ns; exp_pack_c=exp_pack_n; exp_spill_c=0;
      stream(pss,pss+ns,-1);
      wait_drain;
      if (abort_out_after!=0) begin errors=errors+1; $display("FAIL outputs after abort=%0d",abort_out_after); end
      if (a16_count!=ns) begin errors=errors+1; $display("FAIL abort a16 count=%0d exp=%0d",a16_count,ns); end
    end else if (mode==2) begin
      // spill + fp32 + independent backpressure, bank0 phase
      preload(0,5,0,32);
      mark_phase(p0s,p0s+n0);
      exp_a16_c=exp_a16_n; exp_fp_c=exp_fp_n;
      exp_pack_c=exp_pack_n; exp_spill_c=n0;
      do_cfg(1,1,1,1,1,0,5,32'h3f800000,32'h00000000);
      stream(p0s,p0s+n0, p0s + n0/2);
      wait_drain;
    end else if (mode==4) begin
      // config/param drain while an input beat is presented but not accepted.
      // Contract: config may be asserted early but must not hand-shake over a
      // pending beat (that would re-parameterize it and withdraw spill_valid).
      preload(0,5,0,32);
      mark_phase(p0s,p0s+1);
      do_cfg(1,1,1,1,1,0,5,32'h3f800000,32'h00000000); // spill48 on
      spill_hold=1;
      repeat (4) @(posedge clk); // let the ready driver settle with hold=1
      if (spill_ready!==1'b0) begin errors=errors+1; $display("FAIL spill hold not applied"); end
      cval_valid<=1;
      cval_data[47:0]<=q_c[p0s*4+0]; cval_data[95:48]<=q_c[p0s*4+1];
      cval_data[143:96]<=q_c[p0s*4+2]; cval_data[191:144]<=q_c[p0s*4+3];
      cval_tag<=q_tag[p0s]; cval_bc<=q_bc[p0s]; cval_col<=q_col[p0s];
      cval_last<=1;
      @(posedge clk); @(negedge clk);
      // assert an early config request while this beat is still pending
      cfg_valid<=1; cfg_fma_mode<=1; cfg_relu_en<=1; cfg_table_en<=0;
      cfg_spill_c48<=0; cfg_spill_fp32<=1; cfg_bank<=0; cfg_bc<=0;
      cfg_scale<=32'h3f400000; cfg_bias<=32'hbf000000;
      repeat (20) begin
        @(posedge clk);
        if (cfg_ready) begin errors=errors+1; $display("FAIL cfg_ready with pending input beat"); end
        if (spill_valid!==1'b1) begin errors=errors+1; $display("FAIL spill valid withdrawn without handshake"); end
      end
      spill_hold=0; // release the spill consumer; the beat is accepted now
      while (cval_fires < cval_sent+1) begin @(posedge clk); @(negedge clk); end
      cval_sent=cval_sent+1;
      cval_valid<=0;
      while (cfg_fires < cfg_sent+1) begin @(posedge clk); @(negedge clk); end
      cfg_sent=cfg_sent+1;
      cfg_valid<=0;
      @(posedge clk);
      // scalar epoch
      do_pw(8'h00,0,32'h3f400000);
      do_pw(8'h01,0,32'hbf000000);
      mark_phase(pss,pss+ns);
      do_cfg(1,1,0,1,0,0,0,32'h3f400000,32'hbf000000);
      exp_a16_c=exp_a16_n; exp_fp_c=exp_fp_n;
      exp_pack_c=exp_pack_n; exp_spill_c=1;
      stream(pss,pss+ns,-1);
      wait_drain;
    end else begin
      // mode 0: bank0 -> bank1 -> scalar multi-phase
      if (n0<1) n0=1; if (n0>512) n0=512;
      if (n1<1) n1=1; if (n1>512) n1=512;
      if (ns<1) ns=1; if (ns>64) ns=64;
      preload(0,5,0,32);
      mark_phase(p0s,p0s+n0);
      do_cfg(1,1,1,1,0,0,5,32'h3f800000,32'h00000000);
      // stream bank0, preload inactive bank1 halfway, probe active-bank write
      for (i=p0s;i<p0s+n0;i=i+1) begin
        if (i==p0s+n0/2) begin
          preload(1,6,0,32);
          param_wr_valid<=1; param_wr_addr<=8'h80; param_wr_bc<=5; param_wr_data<=32'h11111111;
          repeat (4) begin @(posedge clk); if (param_wr_ready) active_write_ready_seen=active_write_ready_seen+1; end
          param_wr_valid<=0; @(posedge clk);
        end
        if (i==p0s+n0/2 && n0>3) freeze_left=64;
        send_beat(i, i==p0s+n0-1);
      end
      // config to bank1, may be asserted while last beats drain
      mark_phase(p1s,p1s+n1);
      do_cfg(1,1,1,1,0,1,6,32'h3f800000,32'h00000000);
      stream(p1s,p1s+n1,-1);
      // scalar fallback
      do_pw(8'h00,0,32'h3f400000);
      do_pw(8'h01,0,32'hbf000000);
      mark_phase(pss,pss+ns);
      do_cfg(1,1,0,1,0,0,0,32'h3f400000,32'hbf000000);
      stream(pss,pss+ns,-1);
      exp_a16_c=exp_a16_n; exp_fp_c=exp_fp_n;
      exp_pack_c=exp_pack_n; exp_spill_c=0;
      wait_drain;
      if (active_write_ready_seen!=0)
        $display("NOTE active-bank write ready %0d samples (may be idle)",active_write_ready_seen);
    end

    // ---- completeness / extras ----
    for (i=0;i<8192;i=i+1) if (exp_need[i]) begin
      if (!exp_seen_a[i]) begin errors=errors+1; $display("FAIL a16 missing tag=%0d",i); end
      if (!exp_seen_f[i]) begin errors=errors+1; $display("FAIL fp32 missing tag=%0d",i); end
    end
    if (extra_a!=0) begin errors=errors+1; $display("FAIL extra a16=%0d",extra_a); end
    if (extra_f!=0) begin errors=errors+1; $display("FAIL extra fp32=%0d",extra_f); end
    if (pc!=pq_n) begin errors=errors+1; $display("FAIL packed count pc=%0d exp=%0d",pc,pq_n); end
    if (a16_count!=exp_a16_c) begin errors=errors+1; $display("FAIL a16 count=%0d exp=%0d",a16_count,exp_a16_c); end
    if (fp_count!=exp_fp_c) begin errors=errors+1; $display("FAIL fp32 count=%0d exp=%0d",fp_count,exp_fp_c); end
    if (pack_count!=exp_pack_c) begin errors=errors+1; $display("FAIL packed count=%0d exp=%0d",pack_count,exp_pack_c); end
    if (spill_count!=exp_spill_c) begin errors=errors+1; $display("FAIL spill count=%0d exp=%0d",spill_count,exp_spill_c); end
    if (stat_col_align_err!=0) begin errors=errors+1; $display("FAIL col_align_err=%0d",stat_col_align_err); end

    $display("RESULT mode=%0d a16=%0d/%0d pack=%0d/%0d fp=%0d/%0d spill=%0d/%0d err=%0d hits=%0d misses=%0d rej=%0d cyc=%0d",
             mode,a16_count,exp_a16_c,pack_count,exp_pack_c,fp_count,exp_fp_c,
             spill_count,exp_spill_c,errors,stat_table_hits,stat_table_misses,
             stat_param_rejects,cyc);
    if (errors==0) begin $display("PASS"); $finish; end
    else begin $display("FAIL"); $fatal(1,"mismatch"); end
  end
endmodule
