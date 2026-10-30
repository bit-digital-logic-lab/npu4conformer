`timescale 1ns/1ps
// V0.24 optional 2x1 super-tile matrix engine with W reuse.
//
// Numeric contract is the v023 block_engine_prefetch_v2 contract:
//   A16 signed * W7 {S,J[1:0],M[3:0]}, cfg_positions nibble, clip saturation,
//   INT48 two's-complement wrap, C48 old-C add with overflow fault 8,
//   K accumulated in ascending bk order, four C48 lanes per group.
//
// What is new:
//   * cfg_w_reuse=1 and at least two row blocks: a pair (br,br+1) keeps both
//     32x32 C tiles in cache slot 0/1 for the whole K loop and loads
//     W(bk,bc) once per bk.  br0 reads A stage 0 and br1 reads A stage 1;
//     the W bank is pinned and W(next) is double-buffered in the other W bank.
//   * A and W read stages are independent (rd_a_stage/rd_w_stage), and stage
//     release is per kind, so refilling A does not free the pinned W.
//   * cfg_w_reuse=0, a single row block, or an odd tail use the v023
//     single-tile schedule (one C slot, W per tile per bk).
//
// The two C slots are two accumulators, not two simultaneous result payloads.
// Results are emitted one tile at a time; result0 waits cwr_idle before the
// br1 final-K write stream starts, so v1 never interleaves the two tiles'
// cseg streams.  See INTERFACE.md / REVIEW.md.
module block_engine_reuse_v1 #(
 parameter integer SLOTS=2,
 parameter integer MAX_DIM=4096,
 parameter integer PIPE_STAGES=4,
 parameter integer ACCUM_MODE=0,
 parameter integer CPA_PIPE=1
)(
 input wire clk,reset,start,
 input wire [31:0] cfg_a_base,cfg_b_base,cfg_c_base,cfg_epoch,
 input wire [15:0] cfg_m,cfg_n,cfg_k,cfg_layer,cfg_a_id,cfg_b_id,cfg_c_id,
 input wire [15:0] cfg_target_high,cfg_allowed_ops,cfg_requested_op,
 input wire [15:0] cfg_positions,input wire cfg_clip,
 input wire cfg_c_valid,input wire [15:0] cfg_c_completed,
 input wire cfg_w_reuse,
 output reg busy,done,fault,output reg [7:0] error_code,
 output reg [63:0] task_cycles,
 output reg [31:0] compute_cycles,read_blocks,write_blocks,cache_hits,cache_misses,
 output reg [31:0] prefetch_hits,prefetch_wait_cycles,
 output reg [31:0] overlap_compute_read_cycles,overlap_compute_write_cycles,
 output reg [31:0] c_collect_groups,c_collect_cycles,c_raw_bypass_cycles,
 output wire [7:0] pe_drain_cycles,array_drain_cycles,
 output wire array_drain_done,
 output reg [31:0] w_load_blocks,a_load_blocks,c_load_blocks,pair_schedules,w_reuse_saved,
 output wire pair_mode,
 // load command / stage response
 output reg ld_valid,input wire ld_ready,
 output reg [1:0] ld_kind,output reg ld_stage,
 output reg [31:0] ld_address,ld_epoch,
 output reg [15:0] ld_layer,ld_matrix,ld_block_row,ld_block_col,ld_allowed_ops,ld_completed_ops,
 output reg [1:0] ld_encoding,output reg ld_block_valid,ld_in_operation,
 input wire [1:0] stage_a_ready,stage_w_ready,stage_a_fault,stage_w_fault,
 input wire [1:0] stage_a_bvalid,stage_w_bvalid,stage_a_inop,stage_w_inop,
 input wire [63:0] stage_a_epoch,stage_w_epoch,
 input wire [31:0] stage_a_layer,stage_w_layer,stage_a_matrix,stage_w_matrix,
 input wire [31:0] stage_a_row,stage_w_row,stage_a_col,stage_w_col,
 input wire [31:0] stage_a_allowed,stage_w_allowed,stage_a_completed,stage_w_completed,
 input wire [3:0] stage_a_encoding,stage_w_encoding,
 output reg [1:0] stage_release_a,stage_release_w,
 output wire rd_a_stage,rd_w_stage,
 output reg rd_row_half,rd_col_half,
 output reg [79:0] a_k,w_k,
 input wire [255:0] a_values,input wire [111:0] w_values,
 // C stream load
 input wire c_hdr_valid,output reg c_hdr_ready,
 input wire c_hdr_exists,c_hdr_bvalid,c_hdr_inop,c_hdr_error,input wire [7:0] c_hdr_code,
 input wire [63:0] c_hdr_epoch,
 input wire [31:0] c_hdr_layer,c_hdr_matrix,c_hdr_row,c_hdr_col,c_hdr_allowed,c_hdr_completed,
 input wire [3:0] c_hdr_encoding,
 input wire c_ld_valid,output reg c_ld_ready,input wire [127:0] c_ld_data,
 input wire [15:0] c_ld_index,input wire c_ld_last,
 input wire c_ld_done,c_ld_error,input wire [7:0] c_ld_code,
 // C write
 output wire cseg_valid,input wire cseg_ready,
 output wire [31:0] cseg_address,cseg_epoch,
 output wire [15:0] cseg_layer,cseg_matrix,cseg_row,cseg_col,cseg_beats,
 output wire cval_valid,input wire cval_ready,output wire [191:0] cval_data,output wire cval_last,
 input wire [7:0] cwr_pending,input wire cwr_idle,cwr_done,cwr_error,input wire [7:0] cwr_code,
 input wire rd_active,wr_active,
 // error drain
 output reg abort_storage,input wire storage_drain_done,
 // result
 output reg result_valid,input wire result_ready,
 output reg [31:0] result_cache_address,
 output reg [31:0] result_epoch,
 output reg [15:0] result_target_low,result_layer,result_matrix,result_block_row,result_block_col,result_op_tag,
 output wire [49151:0] result_data,
 output reg result_block_valid,result_in_operation,
 output reg [15:0] result_allowed_ops,result_completed_ops
);
 localparam IDLE=0,LOOKUP=1,CL_REQ=2,CL_HDR=3,CL_DATA=4,
  S_P0A=5,S_P0W=6,S_WAITCUR=7,S_PREFA=8,S_PREFW=9,
  P_INIT_A=10,P_INIT_W=11,P_AW_WAIT=12,P_PRE=13,P_ISS_A1=14,P_ISS_AN=15,P_ISS_WN=16,
  CLEAR=17,RUN=18,CREAD=19,COLLECT=20,WAIT_A1=21,RESULT=22,NEXT_TILE=23,
  DONE=24,FAIL=25,WAITDRAIN=26;
 reg [4:0] state;
 reg [31:0] abase,bbase,cbase,epoch;
 reg [15:0] m,n,k,layer,aid,bid,cid,target_high,allowed,positions;
 reg clip;
 reg [15:0] br_base,bc,bk,nb_r,nb_c,nb_k;
 reg [15:0] c_completed;
 reg [6:0] run_cycle;
 reg [7:0] grp;
 reg [1:0] quadrant;
 reg unit,use_pair,wst,curs;
 reg cload_u;
 reg res_slot;
 reg [15:0] res_row;
 reg [1:0] res_step;
 reg [4:0] res_next;
 reg res_issued;
 reg fresh_c [0:1];
 reg tag_done [0:1];
 reg valid_cache [0:1];
 reg [31:0] tag_epoch[0:1],tag_base[0:1];
 reg [15:0] tag_layer[0:1],tag_matrix[0:1],tag_r[0:1],tag_c[0:1];
 reg [15:0] tag_rows[0:1],tag_cols[0:1],tag_allowed[0:1],tag_completed[0:1];
 reg [8:0] ld_groups;
 reg [4:0] ld_bytes;
 reg [319:0] ld_buf;
 reg [191:0] collected_values;
 reg signed [48:0] c_add,c_old;
 reg c_overflow;
 reg [49151:0] result_payload;
 reg [15:0] av,wv;
 reg [8:0] ld_beat;
 reg result_valid_r;
 reg pipe_valid;
 reg seg_issued;
 reg [7:0] pipe_grp;
 reg [9:0] pipe_ci;
 reg [191:0] pipe_sums;
 wire [191:0] cache_rd_data;
 wire cache_raw_bypass;
 integer si;
 integer rr_i;
 reg [63:0] tmp64;

 // ---------------- addresses ----------------
 wire [15:0] br_second=br_base+16'd1;
 wire [15:0] br_cur=br_base+{15'd0,unit};
 wire [15:0] next_bk=bk+16'd1;
 wire is_final_k=(next_bk>=nb_k);
 wire [31:0] a0_addr,a1_addr,a0n_addr,a1n_addr,b_addr,bn_addr,c_addr,cl_addr,aze,bze,cze;
 wire [39:0] azext,bzext,czext;
 wire azmap,bzmap,czmap;
 block_address_v020 ma0(.base(cfg_a_base),.rows(cfg_m),.cols(cfg_k),.block_row(br_base),.block_col(bk),.encoding(2'd0),.address(a0_addr),.valid_rows(),.valid_cols(),.extent_bytes(),.valid());
 block_address_v020 ma1(.base(cfg_a_base),.rows(cfg_m),.cols(cfg_k),.block_row(br_second),.block_col(bk),.encoding(2'd0),.address(a1_addr),.valid_rows(),.valid_cols(),.extent_bytes(),.valid());
 block_address_v020 ma0n(.base(cfg_a_base),.rows(cfg_m),.cols(cfg_k),.block_row(br_base),.block_col(next_bk),.encoding(2'd0),.address(a0n_addr),.valid_rows(),.valid_cols(),.extent_bytes(),.valid());
 block_address_v020 ma1n(.base(cfg_a_base),.rows(cfg_m),.cols(cfg_k),.block_row(br_second),.block_col(next_bk),.encoding(2'd0),.address(a1n_addr),.valid_rows(),.valid_cols(),.extent_bytes(),.valid());
 block_address_v020 mb(.base(cfg_b_base),.rows(cfg_k),.cols(cfg_n),.block_row(bk),.block_col(bc),.encoding(2'd1),.address(b_addr),.valid_rows(),.valid_cols(),.extent_bytes(),.valid());
 block_address_v020 mbn(.base(cfg_b_base),.rows(cfg_k),.cols(cfg_n),.block_row(next_bk),.block_col(bc),.encoding(2'd1),.address(bn_addr),.valid_rows(),.valid_cols(),.extent_bytes(),.valid());
 block_address_v020 mc(.base(cfg_c_base),.rows(cfg_m),.cols(cfg_n),.block_row(br_cur),.block_col(bc),.encoding(2'd2),.address(c_addr),.valid_rows(),.valid_cols(),.extent_bytes(),.valid());
 // zero-based helpers used only for the extent/overlap check at LOOKUP
 block_address_v020 mae(.base(cfg_a_base),.rows(cfg_m),.cols(cfg_k),.block_row(16'd0),.block_col(16'd0),.encoding(2'd0),.address(aze),.valid_rows(),.valid_cols(),.extent_bytes(azext),.valid(azmap));
 block_address_v020 mbe(.base(cfg_b_base),.rows(cfg_k),.cols(cfg_n),.block_row(16'd0),.block_col(16'd0),.encoding(2'd1),.address(bze),.valid_rows(),.valid_cols(),.extent_bytes(bzext),.valid(bzmap));
 block_address_v020 mce(.base(cfg_c_base),.rows(cfg_m),.cols(cfg_n),.block_row(16'd0),.block_col(16'd0),.encoding(2'd2),.address(cze),.valid_rows(),.valid_cols(),.extent_bytes(czext),.valid(czmap));
 // C load address for slot cload_u
 block_address_v020 mcl(.base(cfg_c_base),.rows(cfg_m),.cols(cfg_n),.block_row(br_base+{15'd0,cload_u}),.block_col(bc),.encoding(2'd2),.address(cl_addr),.valid_rows(),.valid_cols(),.extent_bytes(),.valid());

 wire [12287:0] sums;
 wire [5:0] ld_total=ld_bytes+16;
 wire [319:0] ld_comb=ld_buf|({192'd0,c_ld_data}<<(ld_bytes*8));

 // K-local last external input (same contract as v023).
 wire [15:0] k_left=(k>bk*16'd32)?(k-bk*16'd32):16'd0;
 wire [15:0] k_local=(k_left>16'd32)?16'd32:k_left;
 wire [7:0] last_input_cycle=k_local[7:0]+8'd14;
 wire run_finished=(state==RUN)&&(run_cycle>=last_input_cycle)&&array_drain_done;

 assign pair_mode=use_pair;
 assign rd_a_stage=use_pair?unit:curs;
 assign rd_w_stage=use_pair?wst:curs;

 // Current compute-stage header selection.
 wire a_st_sel=use_pair?unit:curs;
 wire w_st_sel=use_pair?wst:curs;
 wire a_fault_now=stage_a_fault[a_st_sel];
 wire w_fault_now=stage_w_fault[w_st_sel];
 wire a_hdr_ok=stage_a_bvalid[a_st_sel]&&!stage_a_inop[a_st_sel]&&
   stage_a_epoch[a_st_sel*32+:32]==epoch&&stage_a_layer[a_st_sel*16+:16]==layer&&
   stage_a_matrix[a_st_sel*16+:16]==aid&&stage_a_row[a_st_sel*16+:16]==br_cur&&
   stage_a_col[a_st_sel*16+:16]==bk&&stage_a_allowed[a_st_sel*16+:16]==allowed&&
   stage_a_completed[a_st_sel*16+:16]==16'd0&&stage_a_encoding[a_st_sel*2+:2]==2'd0;
 wire w_hdr_ok=stage_w_bvalid[w_st_sel]&&!stage_w_inop[w_st_sel]&&
   stage_w_epoch[w_st_sel*32+:32]==epoch&&stage_w_layer[w_st_sel*16+:16]==layer&&
   stage_w_matrix[w_st_sel*16+:16]==bid&&stage_w_row[w_st_sel*16+:16]==bk&&
   stage_w_col[w_st_sel*16+:16]==bc&&stage_w_allowed[w_st_sel*16+:16]==allowed&&
   stage_w_completed[w_st_sel*16+:16]==16'd0&&stage_w_encoding[w_st_sel*2+:2]==2'd1;
 wire cur_stage_ok=stage_a_ready[a_st_sel]&&stage_w_ready[w_st_sel]&&a_hdr_ok&&w_hdr_ok;
 wire a1_hdr_ok=stage_a_bvalid[1]&&!stage_a_inop[1]&&
   stage_a_epoch[32+:32]==epoch&&stage_a_layer[16+:16]==layer&&
   stage_a_matrix[16+:16]==aid&&stage_a_row[16+:16]==br_second&&
   stage_a_col[16+:16]==bk&&stage_a_allowed[16+:16]==allowed&&
   stage_a_completed[16+:16]==16'd0&&stage_a_encoding[2+:2]==2'd0;

 // ---------------- C group mapping (unchanged) ----------------
 function [9:0] ci_of(input [7:0] g,input [1:0] q);
  reg [7:0] c;
  begin
   c={g,2'b00};
   ci_of=(q[1]*16+c[7:4])*32+q[0]*16+c[3:0];
  end
 endfunction
 wire [7:0] issue_collect=(grp<8'd64)?{grp,2'b00}:8'd0;
 wire [9:0] issue_ci=ci_of(grp,quadrant);
 reg [191:0] issue_sums;
 always @* begin
  issue_sums=0;
  for(integer lane=0;lane<4;lane=lane+1)
   issue_sums[lane*48+:48]=sums[(issue_collect+lane)*48+:48];
 end
 wire [9:0] segment=(quadrant[1]*16+(pipe_grp>>2))*32+quadrant[0]*16;
 wire [63:0] seg_off64={54'd0,segment}*64'd6;
 wire [63:0] seg_addr64={32'd0,c_addr}+seg_off64;
 wire [31:0] seg_addr=seg_addr64[31:0];

 // ---------------- cache ----------------
 wire cache_wr_load=(state==CL_DATA)&&c_ld_valid&&(ld_total>=24);
 wire seg_needed=is_final_k&&(pipe_grp[1:0]==0)&&!seg_issued;
 wire cval_needed=is_final_k&&!seg_needed;
 wire commit_now=pipe_valid&&!seg_needed&&(!cval_needed||cval_ready);
 wire cache_wr_collect=commit_now;
 wire cache_rd_issue=(state==CREAD)||((state==COLLECT)&&commit_now&&(pipe_grp!=8'd63));
 wire [8:0] cache_wr_group=cache_wr_load?{cload_u,ld_groups[7:0]}:
   (cache_wr_collect?({unit,8'd0}+{1'b0,(pipe_ci>>2)}):9'd0);
 wire [3:0] cache_wr_mask=cache_wr_load?4'hf:(cache_wr_collect?4'hf:4'h0);
 wire [191:0] cache_wr_data=cache_wr_load?ld_comb[191:0]:
   (cache_wr_collect?collected_values:192'd0);
 wire [8:0] cache_rd_group={unit,8'd0}+{1'b0,(issue_ci>>2)};
 c_cache_banked4_pipe cache(.clk(clk),.rst_n(!reset),
  .rd_valid(cache_rd_issue),.rd_ready(),.rd_group(cache_rd_group),.rd_data(cache_rd_data),
  .wr_valid(cache_wr_load||cache_wr_collect),.wr_ready(),.wr_group(cache_wr_group),
  .wr_mask(cache_wr_mask),.wr_data(cache_wr_data),.raw_bypass_pulse(cache_raw_bypass));

 // ---------------- array ----------------
 wire array_flush=reset||(state==FAIL);
 array16_w7_c48_cfg #(.PIPE_STAGES(PIPE_STAGES),.ACCUM_MODE(ACCUM_MODE),.CPA_PIPE(CPA_PIPE)) array(
  .clk(clk),.reset(reset),.flush(array_flush),.clear_sum(state==CLEAR),
  .a_left(a_values),.w_top(w_values),.av(av),.wv(wv),.positions(positions),.clip(clip),
  .sums(sums),.pipe_empty(),.drain_done(array_drain_done),
  .pe_drain_cycles(pe_drain_cycles),.array_drain_cycles(array_drain_cycles));

 assign result_data=result_payload;

 // ---------------- C add / final result ----------------
 always @*begin
  c_overflow=0;collected_values=0;c_add=0;c_old=0;
  for(integer lane=0;lane<4;lane=lane+1)begin
   c_old=(fresh_c[unit]&&bk==0)?49'sd0:$signed({cache_rd_data[lane*48+47],cache_rd_data[lane*48+:48]});
   c_add=c_old+$signed({pipe_sums[lane*48+47],pipe_sums[lane*48+:48]});
   collected_values[lane*48+:48]=c_add[47:0];
   c_overflow=c_overflow||(c_add[48]!=c_add[47]);
  end
 end

 assign cseg_valid=(state==COLLECT)&&pipe_valid&&seg_needed;
 assign cseg_address=seg_addr;assign cseg_epoch=epoch;
 assign cseg_layer=layer;assign cseg_matrix=cid;assign cseg_row=br_cur;assign cseg_col=bc;
 assign cseg_beats=16'd6;
 assign cval_valid=(state==COLLECT)&&pipe_valid&&is_final_k&&!seg_needed;
 assign cval_data=collected_values;
 assign cval_last=(pipe_grp[1:0]==2'd3);

 // ---------------- bank read addresses ----------------
 always @*begin
  a_k=0;w_k=0;av=0;wv=0;
  rd_row_half=quadrant[1];rd_col_half=quadrant[0];
  for(rr_i=0;rr_i<16;rr_i=rr_i+1)begin
   if(state==RUN)begin
    if(run_cycle>=rr_i&&(run_cycle-rr_i)<32)begin
     a_k[rr_i*5+:5]=run_cycle-rr_i;
     if((br_cur*32+quadrant[1]*16+rr_i)<m&&(bk*32+run_cycle-rr_i)<k)
      av[rr_i]=1;
    end
    if(run_cycle>=rr_i&&(run_cycle-rr_i)<32)begin
     w_k[rr_i*5+:5]=run_cycle-rr_i;
     if((bc*32+quadrant[0]*16+rr_i)<n&&(bk*32+run_cycle-rr_i)<k)
      wv[rr_i]=1;
    end
   end
  end
 end

 // ---------------- result / task ----------------
 assign result_valid=result_valid_r;

 task fail(input [7:0] code);begin
  fault<=1;error_code<=code;abort_storage<=1;result_valid_r<=0;state<=WAITDRAIN;
 end endtask

 task install_tag(input integer sl);begin
  valid_cache[sl]<=1;tag_done[sl]<=0;
  tag_epoch[sl]<=epoch;tag_base[sl]<=cbase;tag_layer[sl]<=layer;tag_matrix[sl]<=cid;
  tag_r[sl]<=br_base+sl;tag_c[sl]<=bc;tag_rows[sl]<=m;tag_cols[sl]<=n;
  tag_allowed[sl]<=allowed;tag_completed[sl]<=0;
 end endtask

 always @(posedge clk)begin
  if(reset)begin
   state<=IDLE;busy<=0;done<=0;fault<=0;error_code<=0;task_cycles<=0;compute_cycles<=0;
   read_blocks<=0;write_blocks<=0;cache_hits<=0;cache_misses<=0;
   prefetch_hits<=0;prefetch_wait_cycles<=0;overlap_compute_read_cycles<=0;overlap_compute_write_cycles<=0;
   w_load_blocks<=0;a_load_blocks<=0;c_load_blocks<=0;pair_schedules<=0;w_reuse_saved<=0;
   ld_valid<=0;ld_kind<=0;ld_stage<=0;ld_address<=0;ld_epoch<=0;ld_layer<=0;ld_matrix<=0;
   ld_block_row<=0;ld_block_col<=0;ld_allowed_ops<=0;ld_completed_ops<=0;ld_encoding<=0;
   ld_block_valid<=0;ld_in_operation<=0;stage_release_a<=0;stage_release_w<=0;
   c_hdr_ready<=0;c_ld_ready<=0;abort_storage<=0;
   result_valid_r<=0;result_cache_address<=0;result_epoch<=0;result_target_low<=0;
   result_layer<=0;result_matrix<=0;result_block_row<=0;result_block_col<=0;result_op_tag<=0;
   result_block_valid<=0;result_in_operation<=0;result_allowed_ops<=0;result_completed_ops<=0;
   abase<=0;bbase<=0;cbase<=0;epoch<=0;m<=0;n<=0;k<=0;layer<=0;aid<=0;bid<=0;cid<=0;
   target_high<=0;allowed<=0;positions<=0;clip<=0;br_base<=0;bc<=0;bk<=0;nb_r<=0;nb_c<=0;nb_k<=0;
   run_cycle<=0;grp<=0;quadrant<=0;unit<=0;use_pair<=0;wst<=0;curs<=0;cload_u<=0;
   res_slot<=0;res_row<=0;res_step<=1;res_next<=NEXT_TILE;res_issued<=0;
   pipe_valid<=0;pipe_grp<=0;pipe_ci<=0;pipe_sums<=0;
   c_collect_groups<=0;c_collect_cycles<=0;c_raw_bypass_cycles<=0;
   ld_groups<=0;ld_bytes<=0;ld_buf<=0;ld_beat<=0;result_payload<=0;
   fresh_c[0]<=0;fresh_c[1]<=0;
   for(si=0;si<SLOTS;si=si+1)begin
    valid_cache[si]<=0;tag_done[si]<=0;tag_epoch[si]<=0;tag_base[si]<=0;tag_layer[si]<=0;
    tag_matrix[si]<=0;tag_r[si]<=0;tag_c[si]<=0;tag_rows[si]<=0;tag_cols[si]<=0;
    tag_allowed[si]<=0;tag_completed[si]<=0;
   end
  end else begin
   if(busy)task_cycles<=task_cycles+1;
   if(state==RUN)compute_cycles<=compute_cycles+1;
   if((state==RUN||state==COLLECT)&&rd_active)overlap_compute_read_cycles<=overlap_compute_read_cycles+1;
   if((state==RUN||state==COLLECT)&&wr_active)overlap_compute_write_cycles<=overlap_compute_write_cycles+1;
   stage_release_a<=0;stage_release_w<=0;ld_valid<=0;c_hdr_ready<=0;c_ld_ready<=0;
   if(cache_raw_bypass)c_raw_bypass_cycles<=c_raw_bypass_cycles+1;

   case(state)
   IDLE:if(start)begin
    done<=0;fault<=0;error_code<=0;task_cycles<=0;compute_cycles<=0;read_blocks<=0;
    write_blocks<=0;cache_hits<=0;cache_misses<=0;prefetch_hits<=0;prefetch_wait_cycles<=0;
    overlap_compute_read_cycles<=0;overlap_compute_write_cycles<=0;result_valid_r<=0;
    abort_storage<=0;result_payload<=0;w_load_blocks<=0;a_load_blocks<=0;c_load_blocks<=0;
    pair_schedules<=0;w_reuse_saved<=0;
    if(cfg_m==0||cfg_n==0||cfg_k==0||cfg_m>MAX_DIM||cfg_n>MAX_DIM||cfg_k>MAX_DIM||MAX_DIM<1||MAX_DIM>4096||
       cfg_a_id==cfg_b_id||cfg_a_id==cfg_c_id||cfg_b_id==cfg_c_id||
       !(cfg_allowed_ops==1||cfg_allowed_ops==3)||cfg_requested_op!=1||
       cfg_positions[3:0]>12||cfg_positions[7:4]>12||cfg_positions[11:8]>12||cfg_positions[15:12]>12||
       cfg_a_base[5:0]!=0||cfg_b_base[5:0]!=0||cfg_c_base[5:0]!=0||SLOTS!=2)begin
     fail(1);
    end else begin
     abase<=cfg_a_base;bbase<=cfg_b_base;cbase<=cfg_c_base;epoch<=cfg_epoch;
     m<=cfg_m;n<=cfg_n;k<=cfg_k;layer<=cfg_layer;aid<=cfg_a_id;bid<=cfg_b_id;cid<=cfg_c_id;
     target_high<=cfg_target_high;allowed<=cfg_allowed_ops;positions<=cfg_positions;clip<=cfg_clip;
     c_completed<=cfg_c_completed;
     br_base<=0;bc<=0;bk<=0;nb_r<=(cfg_m+31)>>5;nb_c<=(cfg_n+31)>>5;nb_k<=(cfg_k+31)>>5;
     quadrant<=0;run_cycle<=0;grp<=0;unit<=0;use_pair<=0;wst<=0;curs<=0;
     pipe_valid<=0;pipe_sums<=0;seg_issued<=0;res_issued<=0;
     busy<=1;state<=LOOKUP;
    end
   end
   LOOKUP:begin
    if(!azmap||!bzmap||!czmap||({8'd0,abase}+azext>40'h0100000000)||
       ({8'd0,bbase}+bzext>40'h0100000000)||({8'd0,cbase}+czext>40'h0100000000)||
       !(({8'd0,abase}+azext<=bbase)||({8'd0,bbase}+bzext<=abase))||
       !(({8'd0,abase}+azext<=cbase)||({8'd0,cbase}+czext<=abase))||
       !(({8'd0,bbase}+bzext<=cbase)||({8'd0,cbase}+czext<=bbase)))fail(1);
    else begin
     bk<=0;quadrant<=0;run_cycle<=0;grp<=0;pipe_valid<=0;unit<=0;wst<=0;curs<=0;res_issued<=0;
     if(cfg_w_reuse&&(nb_r-br_base)>=2)begin
      use_pair<=1;pair_schedules<=pair_schedules+1;
      install_tag(0);install_tag(1);cache_misses<=cache_misses+2;
      cload_u<=0;
      if(cfg_c_valid)state<=CL_REQ;
      else begin fresh_c[0]<=1;fresh_c[1]<=1;state<=P_INIT_A;end
     end else begin
      use_pair<=0;install_tag(0);cache_misses<=cache_misses+1;
      cload_u<=0;
      if(cfg_c_valid)state<=CL_REQ;
      else begin fresh_c[0]<=1;state<=S_P0A;end
     end
    end
   end
   // ---------------- C load (one or two tiles) ----------------
   CL_REQ:begin
    ld_valid<=1;ld_kind<=2;ld_stage<=0;ld_address<=cl_addr;ld_epoch<=epoch;
    ld_layer<=layer;ld_matrix<=cid;ld_block_row<=br_base+{15'd0,cload_u};ld_block_col<=bc;
    ld_allowed_ops<=allowed;ld_completed_ops<=0;ld_encoding<=2;
    ld_block_valid<=1;ld_in_operation<=1;
    if(ld_ready)begin read_blocks<=read_blocks+1;c_load_blocks<=c_load_blocks+1;ld_beat<=0;state<=CL_HDR;end
   end
   CL_HDR:begin
    c_hdr_ready<=1;
    if(c_hdr_valid)begin
     c_hdr_ready<=0;
     if(c_hdr_error||c_hdr_epoch[31:0]!=epoch||c_hdr_layer[15:0]!=layer||
        c_hdr_matrix[15:0]!=cid||c_hdr_row[15:0]!=(br_base+{15'd0,cload_u})||
        c_hdr_col[15:0]!=bc||c_hdr_encoding[1:0]!=2||c_hdr_allowed[15:0]!=allowed||
        ((c_hdr_completed[15:0]&~allowed)!=0))fail(2);
     else if(c_hdr_exists&&!c_hdr_bvalid)fail(3);
     else if(c_hdr_exists&&c_hdr_completed[1])fail(3);
     else if(c_hdr_exists)begin
      fresh_c[cload_u]<=0;tag_completed[cload_u]<=c_hdr_completed[15:0];
      ld_groups<=0;ld_bytes<=0;ld_buf<=0;state<=CL_DATA;
     end else begin
      fresh_c[cload_u]<=1;
      if(use_pair&&cload_u==0)begin cload_u<=1;state<=CL_REQ;end
      else state<=use_pair?P_INIT_A:S_P0A;
     end
    end
   end
   CL_DATA:begin
    c_ld_ready<=1;
    if(c_ld_valid)begin
     if(c_ld_index!=ld_beat)begin
      error_code<=8'h24;fail(5);
     end else begin
      ld_beat<=ld_beat+1;
      if(ld_total>=24)begin
       ld_buf<=ld_comb>>192;ld_bytes<=ld_total-24;ld_groups<=ld_groups+1;
      end else begin
       ld_buf<=ld_comb;ld_bytes<=ld_total;
      end
     end
    end
    if(c_ld_error)begin error_code<=c_ld_code;fail(4);end
    if(c_ld_done)begin
     if((ld_groups+(c_ld_valid&&ld_total>=24?1:0))!=256||
        (c_ld_valid?(ld_total>=24?(ld_total-24):ld_total):ld_bytes)!=0)fail(5);
     else if(use_pair&&cload_u==0)begin cload_u<=1;state<=CL_REQ;end
     else state<=use_pair?P_INIT_A:S_P0A;
    end
   end
   // ---------------- single-tile schedule (v023 semantics) ----------------
   S_P0A:begin
    ld_valid<=1;ld_kind<=0;ld_stage<=curs;ld_address<=a0_addr;ld_epoch<=epoch;
    ld_layer<=layer;ld_matrix<=aid;ld_block_row<=br_base;ld_block_col<=bk;
    ld_allowed_ops<=allowed;ld_completed_ops<=0;ld_encoding<=0;
    ld_block_valid<=1;ld_in_operation<=1;
    if(ld_ready)begin read_blocks<=read_blocks+1;a_load_blocks<=a_load_blocks+1;state<=S_P0W;end
   end
   S_P0W:begin
    ld_valid<=1;ld_kind<=1;ld_stage<=curs;ld_address<=b_addr;ld_epoch<=epoch;
    ld_layer<=layer;ld_matrix<=bid;ld_block_row<=bk;ld_block_col<=bc;
    ld_allowed_ops<=allowed;ld_completed_ops<=0;ld_encoding<=1;
    ld_block_valid<=1;ld_in_operation<=1;
    if(ld_ready)begin read_blocks<=read_blocks+1;w_load_blocks<=w_load_blocks+1;state<=S_WAITCUR;end
   end
   S_WAITCUR:begin
    if(!cur_stage_ok)prefetch_wait_cycles<=prefetch_wait_cycles+1;
    if(a_fault_now||w_fault_now)fail(9);
    else if(cur_stage_ok)state<=S_PREFA;
   end
   S_PREFA:begin
    if(next_bk>=nb_k)state<=CLEAR;
    else begin
     ld_valid<=1;ld_kind<=0;ld_stage<=curs^1'b1;ld_address<=a0n_addr;ld_epoch<=epoch;
     ld_layer<=layer;ld_matrix<=aid;ld_block_row<=br_base;ld_block_col<=next_bk;
     ld_allowed_ops<=allowed;ld_completed_ops<=0;ld_encoding<=0;
     ld_block_valid<=1;ld_in_operation<=1;
     if(ld_ready)begin read_blocks<=read_blocks+1;a_load_blocks<=a_load_blocks+1;state<=S_PREFW;end
    end
   end
   S_PREFW:begin
    ld_valid<=1;ld_kind<=1;ld_stage<=curs^1'b1;ld_address<=bn_addr;ld_epoch<=epoch;
    ld_layer<=layer;ld_matrix<=bid;ld_block_row<=next_bk;ld_block_col<=bc;
    ld_allowed_ops<=allowed;ld_completed_ops<=0;ld_encoding<=1;
    ld_block_valid<=1;ld_in_operation<=1;
    if(ld_ready)begin read_blocks<=read_blocks+1;w_load_blocks<=w_load_blocks+1;state<=CLEAR;end
   end
   // ---------------- pair schedule (W reuse) ----------------
   P_INIT_A:begin
    ld_valid<=1;ld_kind<=0;ld_stage<=1'b0;ld_address<=a0_addr;ld_epoch<=epoch;
    ld_layer<=layer;ld_matrix<=aid;ld_block_row<=br_base;ld_block_col<=bk;
    ld_allowed_ops<=allowed;ld_completed_ops<=0;ld_encoding<=0;
    ld_block_valid<=1;ld_in_operation<=1;
    if(ld_ready)begin read_blocks<=read_blocks+1;a_load_blocks<=a_load_blocks+1;state<=P_INIT_W;end
   end
   P_INIT_W:begin
    ld_valid<=1;ld_kind<=1;ld_stage<=wst;ld_address<=b_addr;ld_epoch<=epoch;
    ld_layer<=layer;ld_matrix<=bid;ld_block_row<=bk;ld_block_col<=bc;
    ld_allowed_ops<=allowed;ld_completed_ops<=0;ld_encoding<=1;
    ld_block_valid<=1;ld_in_operation<=1;
    if(ld_ready)begin read_blocks<=read_blocks+1;w_load_blocks<=w_load_blocks+1;state<=P_AW_WAIT;end
   end
   P_AW_WAIT:begin
    if(!cur_stage_ok)prefetch_wait_cycles<=prefetch_wait_cycles+1;
    if(a_fault_now||w_fault_now)fail(9);
    else if(cur_stage_ok)begin unit<=0;quadrant<=0;state<=P_PRE;end
   end
   P_PRE:begin
    if(unit==0)state<=P_ISS_A1;                 // A1 fills while br0 runs
    else begin
     w_reuse_saved<=w_reuse_saved+1;            // this bk's second row tile
     if(!is_final_k)state<=P_ISS_AN;            // A0(next)+W(next) while br1 runs
     else state<=CLEAR;
    end
   end
   P_ISS_A1:begin
    ld_valid<=1;ld_kind<=0;ld_stage<=1'b1;ld_address<=a1_addr;ld_epoch<=epoch;
    ld_layer<=layer;ld_matrix<=aid;ld_block_row<=br_second;ld_block_col<=bk;
    ld_allowed_ops<=allowed;ld_completed_ops<=0;ld_encoding<=0;
    ld_block_valid<=1;ld_in_operation<=1;
    if(ld_ready)begin read_blocks<=read_blocks+1;a_load_blocks<=a_load_blocks+1;state<=CLEAR;end
   end
   P_ISS_AN:begin
    ld_valid<=1;ld_kind<=0;ld_stage<=1'b0;ld_address<=a0n_addr;ld_epoch<=epoch;
    ld_layer<=layer;ld_matrix<=aid;ld_block_row<=br_base;ld_block_col<=next_bk;
    ld_allowed_ops<=allowed;ld_completed_ops<=0;ld_encoding<=0;
    ld_block_valid<=1;ld_in_operation<=1;
    if(ld_ready)begin read_blocks<=read_blocks+1;a_load_blocks<=a_load_blocks+1;state<=P_ISS_WN;end
   end
   P_ISS_WN:begin
    ld_valid<=1;ld_kind<=1;ld_stage<=wst^1'b1;ld_address<=bn_addr;ld_epoch<=epoch;
    ld_layer<=layer;ld_matrix<=bid;ld_block_row<=next_bk;ld_block_col<=bc;
    ld_allowed_ops<=allowed;ld_completed_ops<=0;ld_encoding<=1;
    ld_block_valid<=1;ld_in_operation<=1;
    if(ld_ready)begin
     read_blocks<=read_blocks+1;w_load_blocks<=w_load_blocks+1;
     state<=CLEAR;
    end
   end
   WAIT_A1:begin
    if(stage_a_fault[1]||stage_w_fault[wst])fail(9);
    else if(stage_a_ready[1]&&a1_hdr_ok)begin unit<=1;quadrant<=0;state<=P_PRE;end
    else prefetch_wait_cycles<=prefetch_wait_cycles+1;
   end
   // ---------------- compute ----------------
   CLEAR:begin
    run_cycle<=0;grp<=0;pipe_valid<=0;seg_issued<=0;state<=RUN;
   end
   RUN:begin
    if(run_finished)begin
     grp<=0;pipe_valid<=0;seg_issued<=0;state<=CREAD;
    end else run_cycle<=run_cycle+1;
   end
   CREAD:begin
    grp<=8'd1;
    pipe_valid<=1;pipe_grp<=8'd0;pipe_ci<=issue_ci;pipe_sums<=issue_sums;
    c_collect_cycles<=c_collect_cycles+1;
    state<=COLLECT;
   end
   COLLECT:begin
    if(cwr_error)fail(10);
    else if(c_overflow)begin
     fail(8);
    end else if(seg_needed)begin
     if(cseg_ready)begin
      seg_issued<=1;write_blocks<=write_blocks+1;
     end
     c_collect_cycles<=c_collect_cycles+1;
    end else if(commit_now)begin
     result_payload[pipe_ci*48+:192]<=collected_values;
     c_collect_groups<=c_collect_groups+1;
     c_collect_cycles<=c_collect_cycles+1;
     if(is_final_k&&(pipe_grp[1:0]==2'd3))seg_issued<=0;
     if(pipe_grp==8'd63)begin
      pipe_valid<=0;
      if(quadrant==3)begin
       tag_completed[unit]<=tag_completed[unit]|16'h0001;
       if(use_pair)begin
        if(unit==0)begin
         stage_release_a<=2'b01;
         if(is_final_k)begin
          res_slot<=0;res_row<=br_base;res_step<=2;res_next<=WAIT_A1;state<=RESULT;
         end else state<=WAIT_A1;
        end else begin
         stage_release_a<=2'b10;stage_release_w<=wst?2'b10:2'b01;
         if(is_final_k)begin
          res_slot<=1;res_row<=br_second;res_step<=2;res_next<=NEXT_TILE;state<=RESULT;
         end else begin
          bk<=next_bk;wst<=wst^1'b1;unit<=1'b0;
          if(stage_a_ready[0]&&stage_w_ready[wst^1'b1])prefetch_hits<=prefetch_hits+1;
          state<=P_AW_WAIT;
         end
        end
       end else begin
        stage_release_a<=curs?2'b10:2'b01;stage_release_w<=curs?2'b10:2'b01;
        if(is_final_k)begin
         res_slot<=0;res_row<=br_base;res_step<=1;res_next<=NEXT_TILE;state<=RESULT;
        end else begin
         bk<=next_bk;curs<=curs^1'b1;quadrant<=2'd0;
         if(stage_a_ready[curs^1'b1]&&stage_w_ready[curs^1'b1])prefetch_hits<=prefetch_hits+1;
         state<=S_WAITCUR;
        end
       end
      end else begin
       quadrant<=quadrant+1'b1;state<=CLEAR;
      end
     end else begin
      pipe_grp<=grp;pipe_ci<=issue_ci;pipe_sums<=issue_sums;
      grp<=grp+8'd1;pipe_valid<=1;
     end
    end else begin
     c_collect_cycles<=c_collect_cycles+1;
    end
   end
   RESULT:begin
    if(cwr_error)fail(10);
    else if(!res_issued)begin
     if(cwr_idle)begin
      result_cache_address<={target_high,16'd0}+(res_slot?32'd6144:32'd0);
      result_target_low<=res_slot?16'd6144:16'd0;
      result_epoch<=epoch;result_layer<=layer;result_matrix<=cid;
      result_block_row<=res_row;result_block_col<=bc;result_op_tag<=1;
      result_block_valid<=1;result_in_operation<=0;
      result_allowed_ops<=allowed;result_completed_ops<=tag_completed[res_slot]|16'h0001;
      result_valid_r<=1;res_issued<=1;
     end
    end else if(result_ready)begin
     result_valid_r<=0;tag_done[res_slot]<=1;res_issued<=0;state<=res_next;
    end
   end
   NEXT_TILE:begin
    if(({1'b0,br_base}+{14'd0,res_step})>=nb_r)begin
     br_base<=0;use_pair<=0;
     if(({1'b0,bc}+16'd1)>=nb_c)begin busy<=0;done<=1;state<=DONE;end
     else begin bc<=bc+16'd1;state<=LOOKUP;end
    end else begin
     br_base<=br_base+{14'd0,res_step};state<=LOOKUP;
    end
   end
   DONE:state<=IDLE;
   FAIL:state<=WAITDRAIN;
   WAITDRAIN:begin
    abort_storage<=1;
    if(storage_drain_done)begin busy<=0;fault<=1;done<=1;state<=IDLE;end
   end
   default:fail(7);
   endcase
  end
 end
endmodule
