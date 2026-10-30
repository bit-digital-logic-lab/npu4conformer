`timescale 1ns/1ps
// Real RTL engine + storage + transactional DMA BFM.
// Same workload can be run with the baseline serial RTL (see tb_engine_baseline)
// and with different BFM stalls to check output backpressure.
module tb_engine_overlap;
 parameter [31:0] BASE=32'h03000000;
 parameter [31:0] A_BASE=32'h03000000,B_BASE=32'h03004000,C_BASE=32'h03005000;
 parameter integer M=64,N=32,K=96;
 parameter integer MEM_WORDS=2048;
 parameter integer RD_LAT=5,RD_GAP=12,WR_GAP=12,B_DELAY=8;
 parameter integer EXPECT_FAULT=0;
 parameter integer NBLK=(M/32)*(N/32);
 parameter integer NBK=(K+31)/32;
 reg clk=0,rst_n=0;
 always #5 clk=~clk;

 reg [31:0] cfg_epoch=32'd3;
 reg [15:0] cfg_m=M,cfg_n=N,cfg_k=K,cfg_layer=16'd5,cfg_a_id=16'd1,cfg_b_id=16'd2,cfg_c_id=16'd3;
 reg [15:0] cfg_target_high=16'd0,cfg_allowed=16'd1,cfg_requested_op=16'd1;
 reg [15:0] cfg_positions=16'h3210,cfg_c_completed=16'd0;
 reg cfg_clip=1'b1;
 reg cfg_c_valid=0;
 reg start=0;
 wire busy,done,fault;wire [7:0] error_code;
 wire [63:0] task_cycles;wire [31:0] compute_cycles,read_blocks,write_blocks,cache_hits,cache_misses;
 wire [31:0] prefetch_hits,prefetch_wait,ov_rd,ov_wr;
 // load
 wire ld_valid,ld_ready;wire [1:0] ld_kind;wire ld_stage;wire [31:0] ld_address,ld_epoch;
 wire [15:0] ld_layer,ld_matrix,ld_brow,ld_bcol,ld_ops,ld_comp;wire [1:0] ld_enc;wire ld_bvalid,ld_inop;
 wire [1:0] sa_r,sw_r,sa_f,sw_f,sa_bv,sw_bv,sa_io,sw_io;wire [63:0] sa_e,sw_e;
 wire [31:0] sa_l,sw_l,sa_m,sw_m,sa_row,sw_row,sa_col,sw_col,sa_a,sw_a,sa_c,sw_c;wire [3:0] sa_enc,sw_enc;
 wire [1:0] rel;
 wire rd_stage,rd_rh,rd_ch;wire [79:0] a_k,w_k;wire [255:0] a_values;wire [111:0] w_values;
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
 wire [31:0] chk_addr=32'h03005000;wire [127:0] chk_data;
 wire [31:0] bfm_rdcmds,bfm_wrcmds,bfm_rdbeats,bfm_wrbeats,bfm_shared,max_b,rd_stall,wr_stall;
 wire rd_active,wr_active;

 reg [127:0] initmem[0:MEM_WORDS-1];
 reg [47:0] expv[0:NBLK*1024-1];
 reg [49151:0] rescap[0:NBLK-1];
 reg seen_result[0:NBLK-1];
 integer errs=0,i,j,blk,rv_count=0;
 reg [1023:0] initfile,expfile;
 integer cycle_count=0;
 reg [1023:0] tracefile;integer tf=-1,trace_en=0;

 block_engine_prefetch_v1 #(.SLOTS(2),.MAX_DIM(4096)) eng(
  .clk(clk),.reset(!rst_n),.start(start),
  .cfg_a_base(A_BASE),.cfg_b_base(B_BASE),.cfg_c_base(C_BASE),.cfg_epoch(cfg_epoch),
  .cfg_m(cfg_m),.cfg_n(cfg_n),.cfg_k(cfg_k),.cfg_layer(cfg_layer),.cfg_a_id(cfg_a_id),
  .cfg_b_id(cfg_b_id),.cfg_c_id(cfg_c_id),.cfg_target_high(cfg_target_high),
  .cfg_allowed_ops(cfg_allowed),.cfg_requested_op(cfg_requested_op),.cfg_positions(cfg_positions),
  .cfg_clip(cfg_clip),.cfg_c_valid(cfg_c_valid),.cfg_c_completed(cfg_c_completed),
  .busy(busy),.done(done),.fault(fault),.error_code(error_code),.task_cycles(task_cycles),
  .compute_cycles(compute_cycles),.read_blocks(read_blocks),.write_blocks(write_blocks),
  .cache_hits(cache_hits),.cache_misses(cache_misses),.prefetch_hits(prefetch_hits),
  .prefetch_wait_cycles(prefetch_wait),.overlap_compute_read_cycles(ov_rd),
  .overlap_compute_write_cycles(ov_wr),
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
  .stage_release(rel),.rd_stage(rd_stage),.rd_row_half(rd_rh),.rd_col_half(rd_ch),
  .a_k(a_k),.w_k(w_k),.a_values(a_values),.w_values(w_values),
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

 block_storage_stream_v1 #(.ARENA_BASE(32'h03000000),.ARENA_END(32'h08000000),.LD_Q(8),.WR_Q(8),.WR_OUT(8)) sto(
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
  .stage_release(rel),.rd_stage(rd_stage),.rd_row_half(rd_rh),.rd_col_half(rd_ch),
  .a_k(a_k),.w_k(w_k),.a_values(a_values),.w_values(w_values),
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
  .rd_req_valid(rd_req_valid),.rd_req_ready(rd_req_ready),.rd_req_address(rd_req_addr),.rd_req_beats(rd_req_beats),
  .rd_valid(rd_valid),.rd_ready(rd_ready),.rd_data(rd_data),.rd_index(rd_index),.rd_done(rd_done),.rd_error(rd_error),
  .wr_req_valid(wr_req_valid),.wr_req_ready(wr_req_ready),.wr_req_address(wr_req_addr),.wr_req_beats(wr_req_beats),
  .wr_valid(wr_valid),.wr_ready(wr_ready),.wr_data(wr_data),.wr_strobe(wr_strobe),.wr_done(wr_done),.wr_error(wr_error),
  .idle(),.drain_done(storage_drain_done),.read_blocks(),.write_segments(),.read_bytes(),.write_bytes(),
  .error_count(),.read_wait_cycles(),.write_wait_cycles(),.ov_same_cycle(),.rd_active_wr_active_cycles(),
  .rd_active(rd_active),.wr_active(wr_active),.dbg_rstate(),.dbg_wwait());

 reg inj_rd=0,inj_wr=0;
 txn_dma_bfm #(.BASE(BASE),.MEM_WORDS(MEM_WORDS),.SEED(11),.RD_LAT(RD_LAT),.RD_GAP(RD_GAP),
   .WR_GAP(WR_GAP),.B_DELAY(B_DELAY),.SHARED_BW(1)) bfm(
  .clk(clk),.rst_n(rst_n),.inject_rd_error(inj_rd),.inject_wr_error(inj_wr),
  .rd_req_valid(rd_req_valid),.rd_req_ready(rd_req_ready),.rd_req_address(rd_req_addr),.rd_req_beats(rd_req_beats),
  .rd_valid(rd_valid),.rd_ready(rd_ready),.rd_data(rd_data),.rd_index(rd_index),.rd_done(rd_done),.rd_error(rd_error),
  .wr_req_valid(wr_req_valid),.wr_req_ready(wr_req_ready),.wr_req_address(wr_req_addr),.wr_req_beats(wr_req_beats),
  .wr_valid(wr_valid),.wr_ready(wr_ready),.wr_data(wr_data),.wr_strobe(wr_strobe),.wr_done(wr_done),.wr_error(wr_error),
  .init_valid(init_valid),.init_addr(init_addr),.init_data(init_data),.chk_addr(chk_addr),.chk_data(chk_data),
  .rd_cmds(bfm_rdcmds),.wr_cmds(bfm_wrcmds),.rd_beats_c(bfm_rdbeats),.wr_beats_c(bfm_wrbeats),
  .shared_conflict(bfm_shared),.max_b_out(max_b),.rd_stall_cycles(rd_stall),.wr_stall_cycles(wr_stall));

 task init_word(input [31:0] a,input [127:0] d);begin
  @(negedge clk);init_valid=1;init_addr=a;init_data=d;
  @(negedge clk);init_valid=0;
 end endtask

 // capture result payload and block coordinates
 always @(posedge clk)if(rst_n&&result_valid&&result_ready)begin
  blk=result_block_row*(N/32)+result_block_col;
  if(blk>=0&&blk<NBLK)begin
   rescap[blk]<=result_data;seen_result[blk]<=1;
   for(i=0;i<1024;i=i+1)
    if(result_data[i*48+:48]!==expv[blk*1024+i])begin
     if(errs<10)$display("FAIL result blk=%0d i=%0d got=%012h exp=%012h",blk,i,result_data[i*48+:48],expv[blk*1024+i]);
     errs=errs+1;
    end
   rv_count=rv_count+1;
  end
 end

 initial begin
  errs=0;rv_count=0;
  for(i=0;i<NBLK;i=i+1)seen_result[i]=0;
  if(!$value$plusargs("cvalid=%d",cfg_c_valid))cfg_c_valid=0;
  if(EXPECT_FAULT==1)inj_rd=1;
  if(EXPECT_FAULT==2)inj_wr=1;
  if($value$plusargs("trace=%s",tracefile))begin
   tf=$fopen(tracefile,"w");trace_en=1;
   $fwrite(tf,"cycle rd_payload rd_cmd rd_wait rd_idle wr_payload wr_cmd wr_wait wr_bp wr_idle comp_run comp_collect comp_wait comp_other busy\n");
  end
  if(!$value$plusargs("init=%s",initfile))initfile="fixtures/eng_c0/init.hex";
  if(!$value$plusargs("exp=%s",expfile))expfile="fixtures/eng_c0/exp_c.txt";
  $readmemh(initfile,initmem);
  $readmemh(expfile,expv);
  rst_n=0;repeat(6)@(negedge clk);rst_n=1;repeat(4)@(negedge clk);
  for(i=0;i<MEM_WORDS;i=i+1)init_word(BASE+i*16,initmem[i]);
  $display("INFO init done mem=%0d words",MEM_WORDS);
  $display("CFG m=%0d n=%0d k=%0d ids=%0d/%0d/%0d allowed=%0d req=%0d pos=%h bases=%h/%h/%h slots=2",cfg_m,cfg_n,cfg_k,cfg_a_id,cfg_b_id,cfg_c_id,cfg_allowed,cfg_requested_op,cfg_positions,A_BASE,B_BASE,C_BASE);
  @(negedge clk);start=1;@(negedge clk);start=0;
  wait(done);
  repeat(5)@(negedge clk);
  $display("INFO done fault=%b code=%h cycles=%0d compute=%0d rdblk=%0d wrblk=%0d hits=%0d miss=%0d prehit=%0d prewait=%0d ov_rd=%0d ov_wr=%0d",
    fault,error_code,task_cycles,compute_cycles,read_blocks,write_blocks,cache_hits,cache_misses,
    prefetch_hits,prefetch_wait,ov_rd,ov_wr);
  $display("INFO bfm rdcmds=%0d wrcmds=%0d rdbeats=%0d wrbeats=%0d shared=%0d maxb=%0d rdstall=%0d wrstall=%0d",
    bfm_rdcmds,bfm_wrcmds,bfm_rdbeats,bfm_wrbeats,bfm_shared,max_b,rd_stall,wr_stall);
  if(EXPECT_FAULT!=0)begin
   if(!fault||!done)begin $display("FAIL expected drained fault fault=%b done=%b code=%h",fault,done,error_code);$fatal(1,"no fault");end
   $display("PASS_FAULT code=%h cycles=%0d done=%b cwr_pending=%0d",error_code,task_cycles,done,cwr_pending);
   $finish;
  end
  if(EXPECT_FAULT==0)begin
  if(fault)begin $display("FAIL fault code=%h",error_code);$fatal(1,"fault");end
  if(cycle_count==0)$display("WARN cycle_count");
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
  if(write_blocks!=NBLK*64)begin $display("FAIL write_blocks %0d",write_blocks);errs=errs+1;end
  if(prefetch_hits<(NBK-1)*NBLK)begin $display("FAIL prefetch_hits %0d",prefetch_hits);errs=errs+1;end
  if(NBK>1&&ov_rd==0)begin $display("FAIL no read/compute overlap");errs=errs+1;end
  if(ov_wr==0)begin $display("FAIL no write/compute overlap");errs=errs+1;end
  if(cwr_pending!=0)begin $display("FAIL cwr_pending %0d",cwr_pending);errs=errs+1;end
  if(errs!=0)$fatal(1,"tb_engine_overlap errs=%0d",errs);
  end
  if(trace_en)$fclose(tf);
  $display("PASS tb_engine_overlap M=%0d N=%0d K=%0d C_VALID=%0d cycles=%0d compute=%0d ov_rd=%0d ov_wr=%0d prehit=%0d prewait=%0d",
    M,N,K,cfg_c_valid,task_cycles,compute_cycles,ov_rd,ov_wr,prefetch_hits,prefetch_wait);
  $finish;
 end
 always @(posedge clk)if(rst_n)cycle_count<=cycle_count+1;
 always @(posedge clk)if(rst_n&&trace_en)begin
  $fwrite(tf,"%0d %0d %0d %0d %0d %0d %0d %0d %0d %0d %0d %0d %0d %0d %0d\n",
   cycle_count,
   (rd_valid&&rd_ready),
   (rd_req_valid&&rd_req_ready),
   (rd_active&&!(rd_valid&&rd_ready)),
   (!rd_active&&!(rd_valid&&rd_ready)),
   (wr_valid&&wr_ready),
   (wr_req_valid&&wr_req_ready),
   (wr_active&&!((wr_valid&&wr_ready)||(wr_req_valid&&wr_req_ready)||((cval_valid&&!cval_ready)||(wr_valid&&!wr_ready)))),
   ((cval_valid&&!cval_ready)||(wr_valid&&!wr_ready)),
   (!wr_active&&!((wr_valid&&wr_ready)||(cval_valid&&!cval_ready)||(wr_valid&&!wr_ready))),
   (eng.state==11),
   ((eng.state==12)||(eng.state==13)),
   ((eng.state==7)||(eng.state==8)||(eng.state==9)),
   (!((eng.state==11)||(eng.state==12)||(eng.state==13)||(eng.state==7)||(eng.state==8)||(eng.state==9))),
   busy);
 end
 reg prev_fault=0;
 always @(posedge clk)if(rst_n)begin
  if(fault&&!prev_fault)$display("FAULT code=%h cyc=%0d engstate=%0d bk=%0d q=%0d col=%0d cwr=%0d csegr=%b cvalr=%b",error_code,cycle_count,eng.state,eng.bk,eng.quadrant,eng.collect,cwr_pending,cseg_ready,cval_ready);
  prev_fault<=fault;
 end
 initial begin
  #5000000;
  $display("TIMEOUT done=%b fault=%b code=%h engstate=%0d bk=%0d cwr=%0d bfmtx=%0d bfmb=%0d bfmwact=%b bfmwidx=%0d bfmwbeats=%0d wcur=%b wsent=%0d/%0d wnb=%0d wq=%0d bout=%0d wreq=%b/%b wp=%b err=%b wseg=%0d wrblk=%0d",
    done,fault,error_code,eng.state,eng.bk,cwr_pending,bfm.wr_cmds,bfm.b_num,bfm.w_active,bfm.w_idx,bfm.w_beats,
    sto.w_cur_valid,sto.w_sent,sto.w_cur_beats,sto.w_nbytes,sto.wq_cnt,sto.b_out,sto.wr_req_valid,sto.wr_req_ready,sto.w_pad,sto.wr_err_sticky,sto.wr_segs,write_blocks);
  $fatal(1,"timeout");
 end
endmodule
