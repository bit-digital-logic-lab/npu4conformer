`timescale 1ns/1ps
// Real-RTL testbench for block_engine_reuse_v1 + block_storage_stream_reuse_v1.
// Runtime M/N/K so one build covers M32/64/96, N32/64, K1/32/96/tail.
// The golden is scripts/gold_reuse.py (independent integer model).
module tb_reuse_engine;
 parameter [31:0] BASE=32'h03000000;
 parameter [31:0] A_BASE=32'h03000000,B_BASE=32'h03008000,C_BASE=32'h03020000;
 parameter integer MEM_WORDS=20'h5000;
 parameter integer PIPE=4;
 parameter integer MAX_NBLK=16;
 parameter integer RD_LAT=2,RD_GAP=1,WR_GAP=1,B_DELAY=4;
 parameter integer MAXB=8;
 reg clk=0,rst_n=0;
 always #5 clk=~clk;

 integer M=64,N=32,K=96,NBLK=2,NBR=2,NBC=1,NBK=3;
 reg [31:0] cfg_epoch=32'd3;
 reg [15:0] cfg_m=64,cfg_n=32,cfg_k=96,cfg_layer=16'd5,cfg_a_id=16'd1,cfg_b_id=16'd2,cfg_c_id=16'd3;
 reg [15:0] cfg_target_high=16'd0,cfg_allowed=16'd1,cfg_requested_op=16'd1;
 reg [15:0] cfg_positions=16'h3210,cfg_c_completed=16'd0;
 reg cfg_clip=1'b1,cfg_c_valid=0,cfg_w_reuse=0,start=0;
 reg inject_rd=0,inject_wr=0;
 wire busy,done,fault;wire [7:0] error_code;
 wire [63:0] task_cycles;wire [31:0] compute_cycles,read_blocks,write_blocks,cache_hits,cache_misses;
 wire [31:0] prefetch_hits,prefetch_wait,ov_rd,ov_wr;
 wire [31:0] c_groups,c_cycles,c_raw;
 wire [31:0] w_loads,a_loads,c_loads,pairs,w_saved;
 wire pair_mode;
 wire [7:0] pe_drain,array_drain;wire array_drain_done;
 // load
 wire ld_valid,ld_ready;wire [1:0] ld_kind;wire ld_stage;wire [31:0] ld_address,ld_epoch;
 wire [15:0] ld_layer,ld_matrix,ld_brow,ld_bcol,ld_ops,ld_comp;wire [1:0] ld_enc;wire ld_bvalid,ld_inop;
 wire [1:0] sa_r,sw_r,sa_f,sw_f,sa_bv,sw_bv,sa_io,sw_io;wire [63:0] sa_e,sw_e;
 wire [31:0] sa_l,sw_l,sa_m,sw_m,sa_row,sw_row,sa_col,sw_col,sa_a,sw_a,sa_c,sw_c;wire [3:0] sa_enc,sw_enc;
 wire [1:0] rel_a,rel_w;
 wire rd_a_stage,rd_w_stage,rd_rh,rd_ch;wire [79:0] a_k,w_k;wire [255:0] a_values;wire [111:0] w_values;
 // C load
 wire chv,chx,chbv,chio,cher;wire [7:0] chc;wire [63:0] che;wire [31:0] chl,chm,chr,chcol,cha,chcomp;wire [3:0] chenc;
 wire chready;wire clv,cll,cld,cldr;wire [127:0] cld_data;wire [15:0] cld_idx;wire [7:0] cldc;wire clready;
 // C write
 wire cseg_valid,cseg_ready;wire [31:0] cseg_addr,cseg_epoch;wire [15:0] cseg_layer,cseg_matrix,cseg_row,cseg_col,cseg_beats;
 wire cval_valid,cval_ready;wire [191:0] cval_data;wire cval_last;
 wire [7:0] cwr_pending;wire cwr_idle,cwr_done,cwr_error;wire [7:0] cwr_code;
 // result
 wire result_valid;reg result_ready=1;wire [31:0] result_cache_address,result_epoch;
 wire [15:0] result_target_low,result_layer,result_matrix,result_block_row,result_block_col,result_op_tag;
 wire [49151:0] result_data;wire result_block_valid,result_in_operation;
 wire [15:0] result_allowed_ops,result_completed_ops;
 wire abort_storage,storage_drain_done;
 // DMA
 wire rd_req_valid,rd_req_ready;wire [31:0] rd_req_addr;wire [15:0] rd_req_beats;
 wire rd_valid,rd_ready;wire [127:0] rd_data;wire [15:0] rd_index;wire rd_done,rd_error;
 wire wr_req_valid,wr_req_ready;wire [31:0] wr_req_addr;wire [15:0] wr_req_beats;
 wire wr_valid,wr_ready;wire [127:0] wr_data;wire [15:0] wr_strobe;wire wr_done,wr_error;
 reg init_valid=0;reg [31:0] init_addr=0;reg [127:0] init_data=0;
 wire [31:0] bfm_rdcmds,bfm_wrcmds,bfm_rdbeats,bfm_wrbeats,bfm_shared,max_b,rd_stall,wr_stall;
 wire [31:0] b_outstanding;wire w_busy;
 wire rd_active,wr_active;
 wire [31:0] st_read_blocks,st_write_segments,st_read_bytes,st_write_bytes,st_error_count;
 wire st_dbg_wr_en;wire [1:0] st_dbg_wr_kind;wire st_dbg_wr_stage;

 reg [127:0] initmem[0:MEM_WORDS-1];
 reg [47:0] expv[0:MAX_NBLK*1024-1];
 integer seen[0:MAX_NBLK-1];
 integer errs=0,i,j,blk,rv_count=0;
 integer cycle_count=0;
 reg [1023:0] initfile,expfile;
 integer haz_a=0,haz_w=0;
 integer dbg=0,run_entries=0,res_entries=0;
 reg [4:0] prev_state=0;
 integer expect_code=0;

 block_engine_reuse_v1 #(.SLOTS(2),.MAX_DIM(4096),.PIPE_STAGES(PIPE),.ACCUM_MODE(0),.CPA_PIPE(1)) dut(
  .clk(clk),.reset(!rst_n),.start(start),
  .cfg_a_base(A_BASE),.cfg_b_base(B_BASE),.cfg_c_base(C_BASE),.cfg_epoch(cfg_epoch),
  .cfg_m(cfg_m),.cfg_n(cfg_n),.cfg_k(cfg_k),.cfg_layer(cfg_layer),.cfg_a_id(cfg_a_id),
  .cfg_b_id(cfg_b_id),.cfg_c_id(cfg_c_id),.cfg_target_high(cfg_target_high),
  .cfg_allowed_ops(cfg_allowed),.cfg_requested_op(cfg_requested_op),.cfg_positions(cfg_positions),
  .cfg_clip(cfg_clip),.cfg_c_valid(cfg_c_valid),.cfg_c_completed(cfg_c_completed),
  .cfg_w_reuse(cfg_w_reuse),
  .busy(busy),.done(done),.fault(fault),.error_code(error_code),.task_cycles(task_cycles),
  .compute_cycles(compute_cycles),.read_blocks(read_blocks),.write_blocks(write_blocks),
  .cache_hits(cache_hits),.cache_misses(cache_misses),.prefetch_hits(prefetch_hits),
  .prefetch_wait_cycles(prefetch_wait),.overlap_compute_read_cycles(ov_rd),
  .overlap_compute_write_cycles(ov_wr),
  .c_collect_groups(c_groups),.c_collect_cycles(c_cycles),.c_raw_bypass_cycles(c_raw),
  .pe_drain_cycles(pe_drain),.array_drain_cycles(array_drain),.array_drain_done(array_drain_done),
  .w_load_blocks(w_loads),.a_load_blocks(a_loads),.c_load_blocks(c_loads),
  .pair_schedules(pairs),.w_reuse_saved(w_saved),.pair_mode(pair_mode),
  .ld_valid(ld_valid),.ld_ready(ld_ready),.ld_kind(ld_kind),.ld_stage(ld_stage),
  .ld_address(ld_address),.ld_epoch(ld_epoch),.ld_layer(ld_layer),.ld_matrix(ld_matrix),
  .ld_block_row(ld_brow),.ld_block_col(ld_bcol),.ld_allowed_ops(ld_ops),.ld_completed_ops(ld_comp),
  .ld_encoding(ld_enc),.ld_block_valid(ld_bvalid),.ld_in_operation(ld_inop),
  .stage_a_ready(sa_r),.stage_w_ready(sw_r),.stage_a_fault(sa_f),.stage_w_fault(sw_f),
  .stage_a_bvalid(sa_bv),.stage_w_bvalid(sw_bv),.stage_a_inop(sa_io),.stage_w_inop(sw_io),
  .stage_a_epoch(sa_e),.stage_w_epoch(sw_e),.stage_a_layer(sa_l),.stage_w_layer(sw_l),
  .stage_a_matrix(sa_m),.stage_w_matrix(sw_m),.stage_a_row(sa_row),.stage_w_row(sw_row),
  .stage_a_col(sa_col),.stage_w_col(sw_col),.stage_a_allowed(sa_a),.stage_w_allowed(sw_a),
  .stage_a_completed(sa_c),.stage_w_completed(sw_c),.stage_a_encoding(sa_enc),.stage_w_encoding(sw_enc),
  .stage_release_a(rel_a),.stage_release_w(rel_w),.rd_a_stage(rd_a_stage),.rd_w_stage(rd_w_stage),
  .rd_row_half(rd_rh),.rd_col_half(rd_ch),.a_k(a_k),.w_k(w_k),.a_values(a_values),.w_values(w_values),
  .c_hdr_valid(chv),.c_hdr_exists(chx),.c_hdr_bvalid(chbv),.c_hdr_inop(chio),.c_hdr_error(cher),
  .c_hdr_code(chc),.c_hdr_epoch(che),.c_hdr_layer(chl),.c_hdr_matrix(chm),.c_hdr_row(chr),
  .c_hdr_col(chcol),.c_hdr_allowed(cha),.c_hdr_completed(chcomp),.c_hdr_encoding(chenc),
  .c_hdr_ready(chready),
  .c_ld_valid(clv),.c_ld_last(cll),.c_ld_done(cld),.c_ld_error(cldr),.c_ld_data(cld_data),
  .c_ld_index(cld_idx),.c_ld_code(cldc),.c_ld_ready(clready),
  .cseg_valid(cseg_valid),.cseg_ready(cseg_ready),.cseg_address(cseg_addr),.cseg_epoch(cseg_epoch),
  .cseg_layer(cseg_layer),.cseg_matrix(cseg_matrix),.cseg_row(cseg_row),.cseg_col(cseg_col),.cseg_beats(cseg_beats),
  .cval_valid(cval_valid),.cval_ready(cval_ready),.cval_data(cval_data),.cval_last(cval_last),
  .cwr_pending(cwr_pending),.cwr_idle(cwr_idle),.cwr_done(cwr_done),.cwr_error(cwr_error),.cwr_code(cwr_code),
  .rd_active(rd_active),.wr_active(wr_active),.abort_storage(abort_storage),.storage_drain_done(storage_drain_done),
  .result_valid(result_valid),.result_ready(result_ready),.result_cache_address(result_cache_address),
  .result_epoch(result_epoch),.result_target_low(result_target_low),.result_layer(result_layer),
  .result_matrix(result_matrix),.result_block_row(result_block_row),.result_block_col(result_block_col),
  .result_op_tag(result_op_tag),.result_data(result_data),.result_block_valid(result_block_valid),
  .result_in_operation(result_in_operation),.result_allowed_ops(result_allowed_ops),
  .result_completed_ops(result_completed_ops));

 block_storage_stream_reuse_v1 #(.ARENA_BASE(32'h03000000),.ARENA_END(32'h08000000),.LD_Q(8),.WR_Q(8),.WR_OUT(8)) sto(
  .clk(clk),.rst_n(rst_n),.abort(abort_storage),.param_end(32'h40000000),
  .cfg_a_base(A_BASE),.cfg_b_base(B_BASE),.cfg_c_base(C_BASE),.cfg_epoch(cfg_epoch),
  .cfg_m(cfg_m),.cfg_n(cfg_n),.cfg_k(cfg_k),.cfg_layer(cfg_layer),.cfg_a_id(cfg_a_id),
  .cfg_b_id(cfg_b_id),.cfg_c_id(cfg_c_id),.cfg_allowed(cfg_allowed),.cfg_c_valid(cfg_c_valid),
  .cfg_c_completed(cfg_c_completed),
  .ld_valid(ld_valid),.ld_ready(ld_ready),.ld_kind(ld_kind),.ld_stage(ld_stage),
  .ld_address(ld_address),.ld_epoch(ld_epoch),.ld_layer(ld_layer),.ld_matrix(ld_matrix),
  .ld_block_row(ld_brow),.ld_block_col(ld_bcol),.ld_allowed_ops(ld_ops),.ld_completed_ops(ld_comp),
  .ld_encoding(ld_enc),.ld_block_valid(ld_bvalid),.ld_in_operation(ld_inop),
  .stage_a_ready(sa_r),.stage_w_ready(sw_r),.stage_a_fault(sa_f),.stage_w_fault(sw_f),
  .stage_a_bvalid(sa_bv),.stage_w_bvalid(sw_bv),.stage_a_inop(sa_io),.stage_w_inop(sw_io),
  .stage_a_epoch(sa_e),.stage_w_epoch(sw_e),.stage_a_layer(sa_l),.stage_w_layer(sw_l),
  .stage_a_matrix(sa_m),.stage_w_matrix(sw_m),.stage_a_row(sa_row),.stage_w_row(sw_row),
  .stage_a_col(sa_col),.stage_w_col(sw_col),.stage_a_allowed(sa_a),.stage_w_allowed(sw_a),
  .stage_a_completed(sa_c),.stage_w_completed(sw_c),.stage_a_encoding(sa_enc),.stage_w_encoding(sw_enc),
  .stage_release(2'b00),.stage_release_a(rel_a),.stage_release_w(rel_w),
  .rd_a_stage(rd_a_stage),.rd_w_stage(rd_w_stage),.rd_row_half(rd_rh),.rd_col_half(rd_ch),
  .a_k(a_k),.w_k(w_k),.a_values(a_values),.w_values(w_values),
  .c_hdr_valid(chv),.c_hdr_ready(chready),.c_hdr_exists(chx),.c_hdr_bvalid(chbv),.c_hdr_inop(chio),
  .c_hdr_error(cher),.c_hdr_code(chc),.c_hdr_epoch(che),.c_hdr_layer(chl),.c_hdr_matrix(chm),
  .c_hdr_row(chr),.c_hdr_col(chcol),.c_hdr_allowed(cha),.c_hdr_completed(chcomp),.c_hdr_encoding(chenc),
  .c_ld_valid(clv),.c_ld_ready(clready),.c_ld_data(cld_data),.c_ld_index(cld_idx),.c_ld_last(cll),
  .c_ld_done(cld),.c_ld_error(cldr),.c_ld_code(cldc),
  .cseg_valid(cseg_valid),.cseg_ready(cseg_ready),.cseg_address(cseg_addr),.cseg_epoch(cseg_epoch),
  .cseg_layer(cseg_layer),.cseg_matrix(cseg_matrix),.cseg_row(cseg_row),.cseg_col(cseg_col),.cseg_beats(cseg_beats),
  .cval_valid(cval_valid),.cval_ready(cval_ready),.cval_data(cval_data),.cval_last(cval_last),
  .cwr_pending(cwr_pending),.cwr_idle(cwr_idle),.cwr_done(cwr_done),.cwr_error(cwr_error),.cwr_code(cwr_code),
  .rd_req_valid(rd_req_valid),.rd_req_ready(rd_req_ready),.rd_req_address(rd_req_addr),.rd_req_beats(rd_req_beats),
  .rd_valid(rd_valid),.rd_ready(rd_ready),.rd_data(rd_data),.rd_index(rd_index),.rd_done(rd_done),.rd_error(rd_error),
  .wr_req_valid(wr_req_valid),.wr_req_ready(wr_req_ready),.wr_req_address(wr_req_addr),.wr_req_beats(wr_req_beats),
  .wr_valid(wr_valid),.wr_ready(wr_ready),.wr_data(wr_data),.wr_strobe(wr_strobe),.wr_done(wr_done),.wr_error(wr_error),
  .idle(),.drain_done(storage_drain_done),.read_blocks(st_read_blocks),.write_segments(st_write_segments),
  .read_bytes(st_read_bytes),.write_bytes(st_write_bytes),.error_count(st_error_count),
  .read_wait_cycles(),.write_wait_cycles(),.ov_same_cycle(),.rd_active_wr_active_cycles(),
  .rd_active(rd_active),.wr_active(wr_active),.dbg_rstate(),.dbg_wwait(),
  .dbg_wr_en(st_dbg_wr_en),.dbg_wr_kind(st_dbg_wr_kind),.dbg_wr_stage(st_dbg_wr_stage));

 txn_dma_bfm #(.BASE(BASE),.MEM_WORDS(MEM_WORDS),.SEED(11),.RD_LAT(RD_LAT),.RD_GAP(RD_GAP),
   .WR_GAP(WR_GAP),.B_DELAY(B_DELAY),.SHARED_BW(1),.MAX_B(MAXB)) bfm(
  .clk(clk),.rst_n(rst_n),.inject_rd_error(inject_rd),.inject_wr_error(inject_wr),
  .rd_req_valid(rd_req_valid),.rd_req_ready(rd_req_ready),.rd_req_address(rd_req_addr),.rd_req_beats(rd_req_beats),
  .rd_valid(rd_valid),.rd_ready(rd_ready),.rd_data(rd_data),.rd_index(rd_index),.rd_done(rd_done),.rd_error(rd_error),
  .wr_req_valid(wr_req_valid),.wr_req_ready(wr_req_ready),.wr_req_address(wr_req_addr),.wr_req_beats(wr_req_beats),
  .wr_valid(wr_valid),.wr_ready(wr_ready),.wr_data(wr_data),.wr_strobe(wr_strobe),.wr_done(wr_done),.wr_error(wr_error),
  .init_valid(init_valid),.init_addr(init_addr),.init_data(init_data),.chk_addr(32'h03020000),.chk_data(),
  .rd_cmds(bfm_rdcmds),.wr_cmds(bfm_wrcmds),.rd_beats_c(bfm_rdbeats),.wr_beats_c(bfm_wrbeats),
  .shared_conflict(bfm_shared),.max_b_out(max_b),.rd_stall_cycles(rd_stall),.wr_stall_cycles(wr_stall),
  .b_outstanding(b_outstanding),.w_busy(w_busy));

 task init_word(input [31:0] a,input [127:0] d);begin
  @(negedge clk);init_valid=1;init_addr=a;init_data=d;
  @(negedge clk);init_valid=0;
 end endtask

 // result payload / coordinate capture
 always @(posedge clk)if(rst_n&&result_valid&&result_ready)begin
  blk=result_block_row*((N+31)/32)+result_block_col;
  if(blk>=0&&blk<NBLK)begin
   if(result_block_valid!==1'b1)begin $display("FAIL result_block_valid=0 blk=%0d",blk);errs=errs+1;end
   for(i=0;i<1024;i=i+1)
    if(result_data[i*48+:48]!==expv[blk*1024+i])begin
     if(errs<10)$display("FAIL result blk=%0d i=%0d got=%012h exp=%012h",blk,i,result_data[i*48+:48],expv[blk*1024+i]);
     errs=errs+1;
    end
   rv_count=rv_count+1;seen[blk]=seen[blk]+1;
  end else begin
   $display("FAIL result blk out of range %0d",blk);errs=errs+1;
  end
 end

 // Port/staging hazard monitor: during RUN, a DMA write must never target the
 // A or W bank currently read by the array.
 always @(posedge clk)if(rst_n&&st_dbg_wr_en&&dut.state==18)begin
  if(st_dbg_wr_kind==2'd0&&st_dbg_wr_stage==rd_a_stage)begin
   $display("FAIL A bank read/write hazard cycle=%0d stage=%0d",cycle_count,rd_a_stage);haz_a=haz_a+1;end
  if(st_dbg_wr_kind==2'd1&&st_dbg_wr_stage==rd_w_stage)begin
   $display("FAIL W bank read/write hazard cycle=%0d stage=%0d",cycle_count,rd_w_stage);haz_w=haz_w+1;end
 end

 always @(posedge clk)if(rst_n)cycle_count<=cycle_count+1;
 always @(posedge clk)if(rst_n)begin
  if(dut.state==18&&prev_state!=18)begin run_entries<=run_entries+1; if(dbg)$display("DBG RUN cyc=%0d q=%0d bk=%0d br=%0d curs=%0d unit=%0d",cycle_count,dut.quadrant,dut.bk,dut.br_base,dut.curs,dut.unit); end
  prev_state<=dut.state;
  if(dbg&&dut.state==23)$display("DBG NEXT_TILE cyc=%0d br=%0d bc=%0d step=%0d res_row=%0d",cycle_count,dut.br_base,dut.bc,dut.res_step,dut.res_row);
  if(dbg&&dut.state==1)$display("DBG LOOKUP cyc=%0d br=%0d bc=%0d bk=%0d reuse=%b",cycle_count,dut.br_base,dut.bc,dut.bk,cfg_w_reuse);
  if(dbg&&dut.state==20&&prev_state!=20)$display("DBG COLLECT_ENTER cyc=%0d q=%0d bk=%0d br=%0d pg=%0d",cycle_count,dut.quadrant,dut.bk,dut.br_base,dut.pipe_grp);
 end
 always @(posedge clk)if(rst_n&&result_valid&&result_ready&&dbg)
  $display("DBG RESULT cyc=%0d row=%0d col=%0d slot=%0d br_base=%0d unit=%0d",cycle_count,result_block_row,result_block_col,dut.res_slot,dut.br_base,dut.unit);

 integer exp_a,exp_w,exp_c,exp_rd,exp_rbeats,exp_wr,exp_wbeats,exp_groups;
 initial begin
  if(!$value$plusargs("m=%d",M))M=64;
  if(!$value$plusargs("n=%d",N))N=32;
  if(!$value$plusargs("k=%d",K))K=96;
  if(!$value$plusargs("cvalid=%d",cfg_c_valid))cfg_c_valid=0;
  if(!$value$plusargs("reuse=%d",cfg_w_reuse))cfg_w_reuse=0;
  if(!$value$plusargs("pos=%h",cfg_positions))cfg_positions=16'h3210;
  if(!$value$plusargs("expect_code=%d",expect_code))expect_code=0;
  if(!$value$plusargs("dbg=%d",dbg))dbg=0;
  begin integer ti; ti=0;
   if($value$plusargs("inject_rd=%d",ti))inject_rd=ti[0];
   ti=0;
   if($value$plusargs("inject_wr=%d",ti))inject_wr=ti[0];
  end
  cfg_m=M;cfg_n=N;cfg_k=K;
  NBR=(M+31)/32;NBC=(N+31)/32;NBK=(K+31)/32;NBLK=NBR*NBC;
  if(NBLK>MAX_NBLK)begin $display("FAIL NBLK %0d > MAX_NBLK",NBLK);$fatal(1);end
  errs=0;rv_count=0;haz_a=0;haz_w=0;
  for(i=0;i<MAX_NBLK;i=i+1)seen[i]=0;
  if(!$value$plusargs("init=%s",initfile))initfile="fixtures/case/init.hex";
  if(!$value$plusargs("exp=%s",expfile))expfile="fixtures/case/exp_c.txt";
  $readmemh(initfile,initmem);$readmemh(expfile,expv);
  rst_n=0;repeat(6)@(negedge clk);rst_n=1;repeat(4)@(negedge clk);
  for(i=0;i<MEM_WORDS;i=i+1)init_word(BASE+i*16,initmem[i]);
  $display("INFO init done mem=%0d words",MEM_WORDS);
  $display("CFG m=%0d n=%0d k=%0d cvalid=%0d reuse=%0d pos=%h bases=%h/%h/%h",
    M,N,K,cfg_c_valid,cfg_w_reuse,cfg_positions,A_BASE,B_BASE,C_BASE);
  @(negedge clk);start=1;@(negedge clk);start=0;
  wait(done);
  repeat(8)@(negedge clk);
  $display("INFO done fault=%b code=%h cycles=%0d compute=%0d rdblk=%0d wrblk=%0d hits=%0d miss=%0d prehit=%0d prewait=%0d ov_rd=%0d ov_wr=%0d cgrp=%0d ccyc=%0d craw=%0d pdrain=%0d adrain=%0d",
    fault,error_code,task_cycles,compute_cycles,read_blocks,write_blocks,cache_hits,cache_misses,
    prefetch_hits,prefetch_wait,ov_rd,ov_wr,c_groups,c_cycles,c_raw,pe_drain,array_drain);
  $display("INFO reuse a=%0d w=%0d c=%0d pairs=%0d wsaved=%0d pairmode=%b wblk=%0d",
    a_loads,w_loads,c_loads,pairs,w_saved,pair_mode,write_blocks);
  $display("INFO bfm rdcmds=%0d wrcmds=%0d rdbeats=%0d wrbeats=%0d shared=%0d maxb=%0d rdstall=%0d wrstall=%0d bout=%0d wbusy=%b",
    bfm_rdcmds,bfm_wrcmds,bfm_rdbeats,bfm_wrbeats,bfm_shared,max_b,rd_stall,wr_stall,b_outstanding,w_busy);
  $display("INFO store rdblk=%0d wrseg=%0d rdbytes=%0d wrbytes=%0d errs=%0d drain=%b",
    st_read_blocks,st_write_segments,st_read_bytes,st_write_bytes,st_error_count,storage_drain_done);
  $display("INFO hazard haz_a=%0d haz_w=%0d",haz_a,haz_w);
  if(expect_code!=0)begin
   if(!fault||!done)begin $display("FAIL expected drained fault fault=%b done=%b code=%h",fault,done,error_code);$fatal(1,"no fault");end
   if(error_code!=expect_code)begin $display("FAIL code=%h expected=%h",error_code,expect_code);$fatal(1,"code");end
   if(cwr_pending!=0||b_outstanding!=0||w_busy)begin
    $display("FAIL fault drain cwr_pending=%0d bout=%0d wbusy=%b",cwr_pending,b_outstanding,w_busy);$fatal(1,"drain");end
   if(cycle_count==0)$display("WARN cycle_count");
   $display("PASS_FAULT code=%h cycles=%0d done=%b cwr_pending=%0d bout=%0d wbusy=%b",error_code,task_cycles,done,cwr_pending,b_outstanding,w_busy);
   $finish;
  end else begin
  if(fault)begin $display("FAIL fault code=%h",error_code);$fatal(1,"fault");end
  // expected traffic/counters for this workload
  exp_a=NBLK*NBK;
  exp_c=cfg_c_valid?NBLK:0;
  if(cfg_w_reuse)exp_w=((NBR+1)/2)*NBK*NBC; else exp_w=NBLK*NBK;
  exp_rd=exp_a+exp_w+exp_c;
  exp_rbeats=exp_a*128+exp_w*64+exp_c*384;
  exp_wr=NBLK*64;
  exp_wbeats=exp_wr*6;
  exp_groups=NBLK*NBK*256;
  // memory C comparison
  for(blk=0;blk<NBLK;blk=blk+1)
   for(i=0;i<1024;i=i+1)begin
    for(j=0;j<6;j=j+1)
     if(bfm.mem[C_BASE-BASE+blk*6144+i*6+j]!==expv[blk*1024+i][j*8+:8])begin
      if(errs<10)$display("FAIL mem blk=%0d i=%0d j=%0d got=%h exp=%h",blk,i,j,bfm.mem[C_BASE-BASE+blk*6144+i*6+j],expv[blk*1024+i][j*8+:8]);
      errs=errs+1;
     end
   end
  if(rv_count!=NBLK)begin $display("FAIL result count %0d != %0d",rv_count,NBLK);errs=errs+1;end
  for(blk=0;blk<NBLK;blk=blk+1)if(seen[blk]!=1)begin $display("FAIL seen blk=%0d count=%0d",blk,seen[blk]);errs=errs+1;end
  if(write_blocks!=exp_wr)begin $display("FAIL write_blocks %0d expected %0d",write_blocks,exp_wr);errs=errs+1;end
  if(st_write_segments!=exp_wr)begin $display("FAIL write_segments %0d expected %0d",st_write_segments,exp_wr);errs=errs+1;end
  if(st_write_bytes!=NBLK*6144)begin $display("FAIL write_bytes %0d expected %0d",st_write_bytes,NBLK*6144);errs=errs+1;end
  if(c_groups!=exp_groups)begin $display("FAIL c_groups %0d expected %0d",c_groups,exp_groups);errs=errs+1;end
  if(read_blocks!=exp_rd)begin $display("FAIL read_blocks %0d expected %0d (a=%0d w=%0d c=%0d)",read_blocks,exp_rd,exp_a,exp_w,exp_c);errs=errs+1;end
  if(a_loads!=exp_a)begin $display("FAIL a_loads %0d expected %0d",a_loads,exp_a);errs=errs+1;end
  if(w_loads!=exp_w)begin $display("FAIL w_loads %0d expected %0d",w_loads,exp_w);errs=errs+1;end
  if(c_loads!=exp_c)begin $display("FAIL c_loads %0d expected %0d",c_loads,exp_c);errs=errs+1;end
  if(cfg_w_reuse)begin
   if(w_saved!=((NBR/2)*NBK*NBC))begin $display("FAIL w_saved %0d expected %0d",w_saved,(NBR/2)*NBK*NBC);errs=errs+1;end
   if(pairs!=((NBR/2)*NBC))begin $display("FAIL pairs %0d expected %0d",pairs,(NBR/2)*NBC);errs=errs+1;end
  end else begin
   if(w_saved!=0||pairs!=0)begin $display("FAIL reuse counters nonzero with reuse=0");errs=errs+1;end
  end
  if(bfm_rdcmds!=exp_rd)begin $display("FAIL bfm rdcmds %0d expected %0d",bfm_rdcmds,exp_rd);errs=errs+1;end
  if(bfm_rdbeats!=exp_rbeats)begin $display("FAIL bfm rdbeats %0d expected %0d",bfm_rdbeats,exp_rbeats);errs=errs+1;end
  if(bfm_wrcmds!=exp_wr)begin $display("FAIL bfm wrcmds %0d expected %0d",bfm_wrcmds,exp_wr);errs=errs+1;end
  if(bfm_wrbeats!=exp_wbeats)begin $display("FAIL bfm wrbeats %0d expected %0d",bfm_wrbeats,exp_wbeats);errs=errs+1;end
  if(cwr_pending!=0)begin $display("FAIL cwr_pending %0d",cwr_pending);errs=errs+1;end
  if(!cwr_idle)begin $display("FAIL cwr_idle=0 after done");errs=errs+1;end
  if(b_outstanding!=0)begin $display("FAIL last B not drained bout=%0d",b_outstanding);errs=errs+1;end
  if(w_busy)begin $display("FAIL write engine still busy");errs=errs+1;end
  if(!storage_drain_done)begin $display("FAIL storage not drained");errs=errs+1;end
  if(haz_a!=0||haz_w!=0)begin $display("FAIL bank hazard a=%0d w=%0d",haz_a,haz_w);errs=errs+1;end
  if(NBK>1&&ov_rd==0)begin $display("FAIL no read/compute overlap");errs=errs+1;end
  if(ov_wr==0)begin $display("FAIL no write/compute overlap");errs=errs+1;end
  if(errs!=0)$fatal(1,"tb_reuse_engine errs=%0d",errs);
  $display("PASS tb_reuse_engine M=%0d N=%0d K=%0d CVALID=%0d REUSE=%0d PIPE=%0d cycles=%0d rdbytes=%0d wrbytes=%0d Wbytes=%0d",
    M,N,K,cfg_c_valid,cfg_w_reuse,PIPE,task_cycles,bfm_rdbeats*16,bfm_wrbeats*16,exp_w*1024);
  end
  $finish;
 end
 initial begin
  #20000000;
  $display("TIMEOUT done=%b fault=%b code=%h state=%0d bk=%0d cwr=%0d bfmtx=%0d bfmb=%0d bfmwact=%b",
    done,fault,error_code,dut.state,dut.bk,cwr_pending,bfm.wr_cmds,bfm.b_num,bfm.w_active);
  $fatal(1,"timeout");
 end
endmodule
