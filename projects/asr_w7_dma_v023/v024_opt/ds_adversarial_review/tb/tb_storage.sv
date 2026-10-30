`timescale 1ns/1ps
// Independent storage coalescer monitor.
// Checks every posted write request for: 16 B alignment, beats<=16,
// no 4 KiB crossing, and reconstructs the 6144 B tile byte-exactly.
// Modes: +native (aligned block), +pagecross (block crosses 4 KiB),
//        +generic (96 B stride segments, one crosses 4 KiB).
module tb_storage;
  parameter [31:0] MEM_BASE = 32'h03000000;
  parameter integer MEM_WORDS = 4096;
  parameter integer MAXCYC = 300000;

  reg clk=0, rst_n=0, abort=0;
  always #5 clk=~clk;

  reg [31:0] cfg_epoch=32'd3, cfg_a_base=32'h03010000, cfg_b_base=32'h03018000, cfg_c_base;
  reg [15:0] cfg_m=32,cfg_n=32,cfg_k=32,cfg_layer=16'd5,cfg_a_id=16'd1,cfg_b_id=16'd2,cfg_c_id=16'd3;
  reg [15:0] cfg_allowed=16'd1,cfg_c_completed=16'd0;
  reg cfg_c_valid=0;
  reg ld_valid=0; wire ld_ready; reg [1:0] ld_kind=0; reg ld_stage=0; reg [31:0] ld_addr=0,ld_epoch=0;
  reg [15:0] ld_layer=0,ld_matrix=0,ld_row=0,ld_col=0,ld_ops=0,ld_comp=0; reg [1:0] ld_enc=0;
  reg ld_bvalid=0,ld_inop=0;
  wire [1:0] sa_r,sw_r,sa_f,sw_f,sa_bv,sw_bv,sa_io,sw_io;
  wire [63:0] sa_e,sw_e; wire [31:0] sa_l,sw_l,sa_m,sw_m,sa_row,sw_row,sa_col,sw_col,sa_a,sw_a,sa_c,sw_c;
  wire [3:0] sa_enc,sw_enc; reg [1:0] rel=0;
  reg rd_stage=0,rd_rh=0,rd_ch=0; reg [79:0] a_k=0,w_k=0; wire [255:0] a_values; wire [111:0] w_values;
  wire chv,chx,chbv,chio,cher; wire [7:0] chc; wire [63:0] che; wire [31:0] chl,chm,chr,chcol,cha,chcomp;
  wire [3:0] chenc; reg chready=1;
  wire clv,cll,cld,cldr; wire [127:0] cld_data; wire [15:0] cld_idx; wire [7:0] cldc; reg clready=1;
  reg cseg_valid=0; wire cseg_ready; reg [31:0] cseg_addr=0,cseg_epoch=0;
  reg [15:0] cseg_layer=0,cseg_matrix=0,cseg_row=0,cseg_col=0,cseg_beats=0;
  reg cval_valid=0; wire cval_ready; reg [191:0] cval_data=0; reg cval_last=0;
  wire [7:0] cwr_pending; wire cwr_idle,cwr_done,cwr_error; wire [7:0] cwr_code;
  wire rd_req_valid; wire rd_req_ready; wire [31:0] rd_req_addr; wire [15:0] rd_req_beats;
  wire rd_valid; wire rd_ready; wire [127:0] rd_data; wire [15:0] rd_index; wire rd_done,rd_error;
  wire wr_req_valid; wire wr_req_ready; wire [31:0] wr_req_addr; wire [15:0] wr_req_beats;
  wire wr_valid; wire wr_ready; wire [127:0] wr_data; wire [15:0] wr_strobe; wire wr_done,wr_error;
  wire idle,drain_done; wire [31:0] read_blocks,write_segs,read_bytes,write_bytes,error_count;
  wire [63:0] rd_wait,wr_wait; wire [31:0] ov_same,rdwractive; wire rd_active,wr_active;
  wire [1:0] dbg_rstate,dbg_wwait;
  wire [31:0] t_cseg,t_wrcmd,t_wrbeat,t_coal,t_gen,t_flush,t_cvalstall,t_csegstall; wire [7:0] t_maxb;
  wire [127:0] chk_data; wire [31:0] bfm_rdcmds,bfm_wrcmds,bfm_rdbeats,bfm_wrbeats,bfm_shared,max_b,rd_stall,wr_stall;
  reg init_valid=0; reg [31:0] init_addr=0; reg [127:0] init_data=0;

  block_storage_stream_v3 #(.ARENA_BASE(32'h03000000),.ARENA_END(32'h08000000),
    .LD_Q(8),.WR_OUT(8),.MAX_REQ_BEATS(16)) dut(
    .clk(clk),.rst_n(rst_n),.abort(abort),.param_end(32'h40000000),
    .cfg_a_base(cfg_a_base),.cfg_b_base(cfg_b_base),.cfg_c_base(cfg_c_base),.cfg_epoch(cfg_epoch),
    .cfg_m(cfg_m),.cfg_n(cfg_n),.cfg_k(cfg_k),.cfg_layer(cfg_layer),.cfg_a_id(cfg_a_id),
    .cfg_b_id(cfg_b_id),.cfg_c_id(cfg_c_id),.cfg_allowed(cfg_allowed),.cfg_c_valid(cfg_c_valid),
    .cfg_c_completed(cfg_c_completed),
    .ld_valid(ld_valid),.ld_ready(ld_ready),.ld_kind(ld_kind),.ld_stage(ld_stage),
    .ld_address(ld_addr),.ld_epoch(ld_epoch),.ld_layer(ld_layer),.ld_matrix(ld_matrix),
    .ld_block_row(ld_row),.ld_block_col(ld_col),.ld_allowed_ops(ld_ops),.ld_completed_ops(ld_comp),
    .ld_encoding(ld_enc),.ld_block_valid(ld_bvalid),.ld_in_operation(ld_inop),
    .stage_a_ready(sa_r),.stage_w_ready(sw_r),.stage_a_fault(sa_f),.stage_w_fault(sw_f),
    .stage_a_bvalid(sa_bv),.stage_w_bvalid(sw_bv),.stage_a_inop(sa_io),.stage_w_inop(sw_io),
    .stage_a_epoch(sa_e),.stage_w_epoch(sw_e),.stage_a_layer(sa_l),.stage_w_layer(sw_l),
    .stage_a_matrix(sa_m),.stage_w_matrix(sw_m),.stage_a_row(sa_row),.stage_w_row(sw_row),
    .stage_a_col(sa_col),.stage_w_col(sw_col),.stage_a_allowed(sa_a),.stage_w_allowed(sw_a),
    .stage_a_completed(sa_c),.stage_w_completed(sw_c),.stage_a_encoding(sa_enc),.stage_w_encoding(sw_enc),
    .stage_release(rel),.rd_stage(rd_stage),.rd_row_half(rd_rh),.rd_col_half(rd_ch),
    .a_k(a_k),.w_k(w_k),.a_values(a_values),.w_values(w_values),
    .c_hdr_valid(chv),.c_hdr_ready(chready),.c_hdr_exists(chx),.c_hdr_bvalid(chbv),
    .c_hdr_inop(chio),.c_hdr_error(cher),.c_hdr_code(chc),.c_hdr_epoch(che),.c_hdr_layer(chl),
    .c_hdr_matrix(chm),.c_hdr_row(chr),.c_hdr_col(chcol),.c_hdr_allowed(cha),
    .c_hdr_completed(chcomp),.c_hdr_encoding(chenc),
    .c_ld_valid(clv),.c_ld_ready(clready),.c_ld_data(cld_data),.c_ld_index(cld_idx),
    .c_ld_last(cll),.c_ld_done(cld),.c_ld_error(cldr),.c_ld_code(cldc),
    .cseg_valid(cseg_valid),.cseg_ready(cseg_ready),.cseg_address(cseg_addr),
    .cseg_epoch(cseg_epoch),.cseg_layer(cseg_layer),.cseg_matrix(cseg_matrix),
    .cseg_row(cseg_row),.cseg_col(cseg_col),.cseg_beats(cseg_beats),
    .cval_valid(cval_valid),.cval_ready(cval_ready),.cval_data(cval_data),.cval_last(cval_last),
    .cwr_pending(cwr_pending),.cwr_idle(cwr_idle),.cwr_done(cwr_done),.cwr_error(cwr_error),.cwr_code(cwr_code),
    .rd_req_valid(rd_req_valid),.rd_req_ready(rd_req_ready),.rd_req_address(rd_req_addr),
    .rd_req_beats(rd_req_beats),.rd_valid(rd_valid),.rd_ready(rd_ready),.rd_data(rd_data),
    .rd_index(rd_index),.rd_done(rd_done),.rd_error(rd_error),
    .wr_req_valid(wr_req_valid),.wr_req_ready(wr_req_ready),.wr_req_address(wr_req_addr),
    .wr_req_beats(wr_req_beats),.wr_valid(wr_valid),.wr_ready(wr_ready),.wr_data(wr_data),
    .wr_strobe(wr_strobe),.wr_done(wr_done),.wr_error(wr_error),
    .idle(idle),.drain_done(drain_done),.read_blocks(read_blocks),.write_segments(write_segs),
    .read_bytes(read_bytes),.write_bytes(write_bytes),.error_count(error_count),
    .read_wait_cycles(rd_wait),.write_wait_cycles(wr_wait),.ov_same_cycle(ov_same),
    .rd_active_wr_active_cycles(rdwractive),.rd_active(rd_active),.wr_active(wr_active),
    .dbg_rstate(dbg_rstate),.dbg_wwait(dbg_wwait),
    .cseg_cmds(t_cseg),.wr_cmds_posted(t_wrcmd),.wr_beats_sent(t_wrbeat),
    .coalesced_segs(t_coal),.generic_segs(t_gen),.flush_reqs(t_flush),
    .max_b_credit(t_maxb),.cval_stall_cycles(t_cvalstall),.cseg_stall_cycles(t_csegstall));

  txn_dma_bfm #(.BASE(MEM_BASE),.MEM_WORDS(MEM_WORDS),.SEED(11),.RD_LAT(0),.RD_GAP(0),
    .WR_GAP(0),.B_DELAY(0),.SHARED_BW(0),.MAX_B(8)) bfm(
    .clk(clk),.rst_n(rst_n),.inject_rd_error(1'b0),.inject_wr_error(1'b0),
    .rd_req_valid(rd_req_valid),.rd_req_ready(rd_req_ready),.rd_req_address(rd_req_addr),
    .rd_req_beats(rd_req_beats),.rd_valid(rd_valid),.rd_ready(rd_ready),.rd_data(rd_data),
    .rd_index(rd_index),.rd_done(rd_done),.rd_error(rd_error),
    .wr_req_valid(wr_req_valid),.wr_req_ready(wr_req_ready),.wr_req_address(wr_req_addr),
    .wr_req_beats(wr_req_beats),.wr_valid(wr_valid),.wr_ready(wr_ready),.wr_data(wr_data),
    .wr_strobe(wr_strobe),.wr_done(wr_done),.wr_error(wr_error),
    .init_valid(init_valid),.init_addr(init_addr),.init_data(init_data),
    .chk_addr(32'h0),.chk_data(chk_data),
    .rd_cmds(bfm_rdcmds),.wr_cmds(bfm_wrcmds),.rd_beats_c(bfm_rdbeats),.wr_beats_c(bfm_wrbeats),
    .shared_conflict(bfm_shared),.max_b_out(max_b),.rd_stall_cycles(rd_stall),.wr_stall_cycles(wr_stall));

  function [7:0] pat(input integer k); begin pat = 8'h5a ^ (k*7); end endfunction

  integer errs=0, i, j, mode=0, nreq=0, nbeats=0, maxbeats=0, page_split=0;
  integer wcnt [0:65535];
  integer idx, mj, cyc_dbg = 0, ngen = 4, paf;
  integer base_off, seg_base;
  reg [1023:0] cbase_arg;
  reg [31:0] C_BASE, cur_waddr=0, genoff=32'h00001110;
  reg [7:0] got [0:65535];

  // independent write monitor: request legality + byte-accurate reconstruct
  always @(posedge clk) begin
    if (rst_n && wr_req_valid && wr_req_ready) begin
      nreq = nreq + 1;
      if (wr_req_addr[3:0] != 0) begin errs=errs+1; $display("FAIL req unaligned %08x", wr_req_addr); end
      if (wr_req_beats == 0 || wr_req_beats > 16) begin errs=errs+1; $display("FAIL req beats %0d", wr_req_beats); end
      if ((wr_req_addr[11:0] + wr_req_beats*16) > 4096) begin errs=errs+1; $display("FAIL req crosses 4KiB addr=%08x beats=%0d", wr_req_addr, wr_req_beats); end
      if (wr_req_beats > maxbeats) maxbeats = wr_req_beats;
      if ((wr_req_addr[11:0] + wr_req_beats*16) == 4096) page_split = page_split + 1;
      cur_waddr = wr_req_addr;
      if ($test$plusargs("debug")) $display("WREQ addr=%08x beats=%0d gen=%0d", wr_req_addr, wr_req_beats, t_gen);
    end
    if (rst_n && wr_valid && wr_ready) begin
      nbeats = nbeats + 1;
      for (mj = 0; mj < 16; mj = mj + 1) begin
        if (wr_strobe[mj]) begin
          idx = cur_waddr + mj - C_BASE;
          got[idx] = wr_data[mj*8 +: 8];
          wcnt[idx] = wcnt[idx] + 1;
        end
      end
      cur_waddr = cur_waddr + 16;
    end
  end

  task send_group(input [31:0] addr_off, input integer grp, input integer last);
    integer q;
    begin
      for (q = 0; q < 24; q = q + 1) cval_data[q*8 +: 8] = pat(addr_off + grp*24 + q);
      cval_last = last; cval_valid = 1;
      while (!cval_ready) @(negedge clk);
      @(negedge clk);
      cval_valid = 0; cval_last = 0;
    end
  endtask

  task send_seg(input [31:0] addr, input integer off, input integer beats);
    integer g;
    begin
      cseg_addr = addr; cseg_epoch = cfg_epoch; cseg_layer = cfg_layer; cseg_matrix = cfg_c_id;
      cseg_row = 0; cseg_col = 0; cseg_beats = beats; cseg_valid = 1;
      while (!cseg_ready) @(negedge clk);
      @(negedge clk); cseg_valid = 0;
      for (g = 0; g < 4; g = g + 1) send_group(off, g, (g == 3));
    end
  endtask

  initial begin
    if (!$value$plusargs("cbase=%s", cbase_arg)) cbase_arg = "03000c00";
    C_BASE = 0;
    for (i = 0; i < 8; i = i + 1) begin
      // parse 8 hex chars
      C_BASE = (C_BASE << 4) | hexval(cbase_arg[8*8-1-i*8 -: 8]);
    end
    cfg_c_base = C_BASE;
    $display("STORAGE cbase=%08x", C_BASE);
    for (i = 0; i < 65536; i = i + 1) begin wcnt[i]=0; got[i]=8'h00; end
    rst_n = 0; repeat (6) @(negedge clk); rst_n = 1; repeat (4) @(negedge clk);
    if ($test$plusargs("native")) mode = 0;
    else if ($test$plusargs("pagecross")) mode = 1;
    else if ($test$plusargs("generic")) mode = 2;
    else mode = 0;
    paf = $value$plusargs("ngen=%d", ngen);
    if (!$value$plusargs("genoff=%s", cbase_arg)) cbase_arg = "00001110";
    genoff = 0;
    for (i = 0; i < 8; i = i + 1) genoff = (genoff << 4) | hexval(cbase_arg[8*8-1-i*8 -: 8]);

    if (mode == 0 || mode == 1) begin
      for (i = 0; i < 4; i = i + 1)
        for (j = 0; j < 16; j = j + 1) begin
          base_off = (i/2)*32*96 + ((i%2) + 2*j)*96;
          send_seg(C_BASE + base_off, base_off, 6);
        end
      wait (cwr_idle); repeat (6) @(negedge clk);
      for (i = 0; i < 6144; i = i + 1)
        if (got[i] !== pat(i) || wcnt[i] != 1) begin
          if (errs < 8) $display("FAIL byte %0d got=%02x exp=%02x cnt=%0d", i, got[i], pat(i), wcnt[i]);
          errs = errs + 1;
        end
      if (t_coal != 64) begin errs=errs+1; $display("FAIL coal=%0d", t_coal); end
      if (nreq > (mode==0 ? 24 : 32)) begin errs=errs+1; $display("FAIL nreq=%0d too high", nreq); end
      if (mode == 1 && page_split == 0) begin errs=errs+1; $display("FAIL page-cross block had no 4KiB split"); end
    end else begin
      // generic stride: 4 x 96 B segments, first starts 64 B before a 4 KiB page
      for (i = 0; i < ngen; i = i + 1) begin
        seg_base = (C_BASE & 32'hffffF000) + genoff + i*128;
        if (seg_base < C_BASE) seg_base = seg_base + 32'h1000;
        send_seg(seg_base, seg_base - C_BASE, 6);
      end
      wait (cwr_idle); repeat (6) @(negedge clk);
      for (i = 0; i < ngen; i = i + 1) begin
        seg_base = (C_BASE & 32'hffffF000) + genoff + i*128;
        if (seg_base < C_BASE) seg_base = seg_base + 32'h1000;
        for (j = 0; j < 96; j = j + 1)
          if (got[seg_base - C_BASE + j] !== pat(seg_base - C_BASE + j)) begin
            if (errs < 8) $display("FAIL gen i=%0d j=%0d got=%02x", i, j, got[seg_base-C_BASE+j]);
            errs = errs + 1;
          end
      end
      if (t_gen == 0) begin errs=errs+1; $display("FAIL no generic segs"); end
      if (nreq < ngen) begin errs=errs+1; $display("FAIL generic nreq=%0d", nreq); end
    end

    if (cwr_pending != 0) begin errs=errs+1; $display("FAIL pending=%0d", cwr_pending); end
    if (cwr_error) begin errs=errs+1; $display("FAIL cwr_error=%02x", cwr_code); end
    $display("RESULT mode=%0d cseg=%0d nreq=%0d nbeats=%0d maxbeats=%0d pagesplit=%0d wrbytes=%0d gen=%0d errs=%0d",
             mode, t_cseg, nreq, nbeats, maxbeats, page_split, write_bytes, t_gen, errs);
    if (errs == 0) begin $display("PASS"); $finish; end
    else begin $display("FAIL"); $fatal(1, "mismatch"); end
  end

  function [3:0] hexval(input [7:0] c);
    begin
      if (c >= "0" && c <= "9") hexval = c - "0";
      else if (c >= "a" && c <= "f") hexval = c - "a" + 10;
      else if (c >= "A" && c <= "F") hexval = c - "A" + 10;
      else hexval = 0;
    end
  endfunction

  always @(posedge clk) if (rst_n && (cyc_dbg % 2000 == 0)) begin
    cyc_dbg <= cyc_dbg + 1;
    if ($test$plusargs("debug")) $display("DBG t=%0d csegv=%b csegr=%b cvalv=%b cvalr=%b pend=%0d gen=%0d idle=%b", cyc_dbg, cseg_valid, cseg_ready, cval_valid, cval_ready, cwr_pending, t_gen, idle);
  end else cyc_dbg <= cyc_dbg + 1;
  initial begin #(10*MAXCYC); $display("WATCHDOG mode=%0d errs=%0d", mode, errs); $fatal(1); end
endmodule
