`timescale 1ns/1ps
// Candidate V1 block engine with A/W double-bank prefetch and C48 streaming.
//
// Numeric core is unchanged: array16_direct_v020 / pe_direct_v020 implement
// A16 * W7(S/J/M) with cfg_positions/cfg_clip, three product pipeline stages
// and INT48 accumulation.  This module only changes when operands and C
// results move:
//   * while RUN/COLLECT executes stage S, storage fills stage S^1 with the
//     next K tile (A and W transactions);
//   * on the final K tile the 4 C48 values produced per COLLECT beat are sent
//     to block_storage_stream_v1, which packs them into 128b posted writes;
//   * no whole-block C collect buffer and no eviction-before-write phase.
//
// K is always accumulated bk=0..nbk-1 in ascending order; C_READ/COLLECT still
// reads the same 4-value group and adds the same sums in the same lane order.
module block_engine_prefetch_v1 #(
 parameter integer SLOTS=2,
 parameter integer MAX_DIM=4096
)(
 input wire clk,reset,start,
 input wire [31:0] cfg_a_base,cfg_b_base,cfg_c_base,cfg_epoch,
 input wire [15:0] cfg_m,cfg_n,cfg_k,cfg_layer,cfg_a_id,cfg_b_id,cfg_c_id,
 input wire [15:0] cfg_target_high,cfg_allowed_ops,cfg_requested_op,
 input wire [15:0] cfg_positions,input wire cfg_clip,
 input wire cfg_c_valid,input wire [15:0] cfg_c_completed,
 output reg busy,done,fault,output reg [7:0] error_code,
 output reg [63:0] task_cycles,
 output reg [31:0] compute_cycles,read_blocks,write_blocks,cache_hits,cache_misses,
 output reg [31:0] prefetch_hits,prefetch_wait_cycles,
 output reg [31:0] overlap_compute_read_cycles,overlap_compute_write_cycles,
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
 output reg [1:0] stage_release,
 output reg rd_stage,output reg rd_row_half,rd_col_half,
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
 output reg cseg_valid,input wire cseg_ready,
 output reg [31:0] cseg_address,cseg_epoch,
 output reg [15:0] cseg_layer,cseg_matrix,cseg_row,cseg_col,cseg_beats,
 output reg cval_valid,input wire cval_ready,output reg [191:0] cval_data,output reg cval_last,
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
 localparam IDLE=0,LOOKUP=1,P0A=2,P0W=3,CREQ=4,CHDR=5,CDATA=6,WAITCUR=7,
  PREFA=8,PREFW=9,CLEAR=10,RUN=11,CREAD=12,COLLECT=13,NEXTK=14,WAITWR=15,
  RESULT=16,DONE=17,FAIL=18,WAITDRAIN=19;
 reg [4:0] state;
 reg [31:0] abase,bbase,cbase,epoch;
 reg [15:0] m,n,k,layer,aid,bid,cid,target_high,allowed,positions;
 reg clip;
 reg [15:0] br,bc,bk,nb_r,nb_c,nb_k;
 reg [15:0] c_completed;
 reg [6:0] run_cycle;
 reg [7:0] collect;
 reg [1:0] quadrant;
 reg [9:0] collect_ci;
 reg stage,rr;
 reg fresh_c,seg_issued,p0_issue_c;
 reg [31:0] slot;
 reg [31:0] caddr_cur;
 reg [8:0] ld_groups;
 reg [4:0] ld_bytes;
 reg [319:0] ld_buf;
 reg [191:0] collected_values;
 reg signed [48:0] c_add,c_old;
 reg c_overflow;
 reg [49151:0] result_payload;
 reg [15:0] av,wv;
 reg [8:0] ld_beat;
 reg cache_a_valid;
 reg [8:0] cache_a_group;
 reg [3:0] cache_a_mask;
 reg [191:0] cache_a_wdata;
 reg result_valid_r;
 // cache tags
 reg valid_cache[0:1],tag_done[0:1];
 reg [31:0] tag_epoch[0:1],tag_base[0:1];
 reg [15:0] tag_layer[0:1],tag_matrix[0:1],tag_r[0:1],tag_c[0:1];
 reg [15:0] tag_rows[0:1],tag_cols[0:1],tag_allowed[0:1],tag_completed[0:1];
 integer found,si;
 reg [63:0] tmp64;

 // addresses for current K and prefetched K+1
 wire [31:0] a_addr,b_addr,c_addr,an_addr,bn_addr;
 wire [15:0] arm,acm,brm,bcm,crm,ccm,anrm,ancm,bnrm,bncm;
 wire [39:0] aext,bext,cext,anext,bnext;
 wire amap,bmap,cmap,anmap,bnmap;
 block_address_v020 ma(cfg_a_base,cfg_m,cfg_k,br,bk,2'd0,a_addr,arm,acm,aext,amap);
 block_address_v020 mb(cfg_b_base,cfg_k,cfg_n,bk,bc,2'd1,b_addr,brm,bcm,bext,bmap);
 block_address_v020 mc(cfg_c_base,cfg_m,cfg_n,br,bc,2'd2,c_addr,crm,ccm,cext,cmap);
 block_address_v020 man(cfg_a_base,cfg_m,cfg_k,br,bk+16'd1,2'd0,an_addr,anrm,ancm,anext,anmap);
 block_address_v020 mbn(cfg_b_base,cfg_k,cfg_n,bk+16'd1,bc,2'd1,bn_addr,bnrm,bncm,bnext,bnmap);
 wire [15:0] next_bk=bk+16'd1;
 wire is_final_k=(next_bk>=nb_k);
 wire [9:0] seg_idx=(quadrant[1]*10'd16+collect[7:4])*10'd32+quadrant[0]*10'd16;
 wire [63:0] seg_off64={54'd0,seg_idx}*64'd6;
 wire [63:0] seg_addr64={32'd0,c_addr}+seg_off64;
 wire [31:0] seg_addr=seg_addr64[31:0];
 wire [12287:0] sums;
 wire [191:0] cache_a_rdata;
 wire [5:0] ld_total=ld_bytes+16;
 wire [319:0] ld_comb=ld_buf|({192'd0,c_ld_data}<<(ld_bytes*8));
 wire cache_hit_now;
 wire cur_stage_ok;
 wire commit;
 wire cache_rd_cycle=(state==CREAD);
 wire cache_wr_cycle=(state==COLLECT)&&commit;
 wire final_stream=is_final_k&&(state==COLLECT);

 // ---------------- cache ----------------
 c_cache_banked4 cache(.clk(clk),.rst_n(!reset),.a_valid(cache_a_valid),.a_ready(),.a_group(cache_a_group),
  .a_write_mask(cache_a_mask),.a_write_data(cache_a_wdata),.a_response_valid(),.a_response_ready(1'b1),
  .a_read_data(cache_a_rdata),.b_valid(1'b0),.b_ready(),.b_word(11'd0),.b_response_valid(),
  .b_response_ready(1'b1),.b_read_data());

 // ---------------- compute core (unchanged numerics) ----------------
 array16_direct_v020 array(.clk(clk),.reset(reset),.flush(state!=RUN),.clear_sum(state==CLEAR),
  .a_left(a_values),.w_top(w_values),.av(av),.wv(wv),.positions(positions),.clip(clip),.sums(sums));

 assign result_data=result_payload;

 // ---------------- collect index / C add ----------------
 always @*begin
  collect_ci=(quadrant[1]*16+collect[7:4])*32+quadrant[0]*16+collect[3:0];
  c_overflow=0;collected_values=0;c_add=0;c_old=0;
  for(integer lane=0;lane<4;lane=lane+1)begin
   c_old=(fresh_c&&bk==0)?49'sd0:$signed({cache_a_rdata[lane*48+47],cache_a_rdata[lane*48+:48]});
   c_add=c_old+$signed({sums[(collect+lane)*48+47],sums[(collect+lane)*48+:48]});
   collected_values[lane*48+:48]=c_add[47:0];
   c_overflow=c_overflow||(c_add[48]!=c_add[47]);
  end
 end

 // cache access mux
 always @*begin
  cache_a_valid=0;cache_a_group=0;cache_a_mask=4'h0;cache_a_wdata=0;
  if(state==CDATA&&c_ld_valid)begin
   cache_a_valid=(ld_total>=24);
   cache_a_group=slot[0]*256+ld_groups[7:0];
   cache_a_mask=4'hf;cache_a_wdata=ld_comb[191:0];
  end else if(state==CREAD)begin
   cache_a_valid=1;cache_a_group=slot[0]*256+(collect_ci>>2);
  end else if(state==COLLECT&&commit)begin
   cache_a_valid=1;cache_a_group=slot[0]*256+(collect_ci>>2);
   cache_a_mask=4'hf;cache_a_wdata=collected_values;
  end
 end

 // ---------------- bank read addresses / valid masks ----------------
 integer rr_i;
 always @*begin
  a_k=0;w_k=0;av=0;wv=0;
  rd_stage=stage;rd_row_half=quadrant[1];rd_col_half=quadrant[0];
  for(rr_i=0;rr_i<16;rr_i=rr_i+1)begin
   if(state==RUN)begin
    if(run_cycle>=rr_i&&(run_cycle-rr_i)<32)begin
     a_k[rr_i*5+:5]=run_cycle-rr_i;
     if((br*32+quadrant[1]*16+rr_i)<m&&(bk*32+run_cycle-rr_i)<k)
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

 // ---------------- cache hit search ----------------
 always @*begin
  found=-1;
  for(si=0;si<SLOTS;si=si+1)
   if(valid_cache[si]&&!tag_done[si]&&tag_epoch[si]==epoch&&tag_base[si]==cbase&&
      tag_layer[si]==layer&&tag_matrix[si]==cid&&tag_r[si]==br&&tag_c[si]==bc&&
      tag_rows[si]==m&&tag_cols[si]==n&&tag_allowed[si]==allowed)found=si;
 end
 assign cache_hit_now=(found>=0);
 assign cur_stage_ok=stage_a_ready[stage]&&stage_w_ready[stage];
 assign commit=(state==COLLECT)&&(!is_final_k||(seg_issued&&cval_valid&&cval_ready));

 // ---------------- result / task ----------------
 assign result_valid=result_valid_r;

 task fail(input [7:0] code);begin
  fault<=1;error_code<=code;abort_storage<=1;result_valid_r<=0;state<=WAITDRAIN;
 end endtask

 task install_tag(input integer sl);begin
  valid_cache[sl]<=1;tag_done[sl]<=0;
  tag_epoch[sl]<=epoch;tag_base[sl]<=cbase;tag_layer[sl]<=layer;tag_matrix[sl]<=cid;
  tag_r[sl]<=br;tag_c[sl]<=bc;tag_rows[sl]<=m;tag_cols[sl]<=n;
  tag_allowed[sl]<=allowed;tag_completed[sl]<=0;
 end endtask

 always @(posedge clk)begin
  if(reset)begin
   state<=IDLE;busy<=0;done<=0;fault<=0;error_code<=0;task_cycles<=0;compute_cycles<=0;
   read_blocks<=0;write_blocks<=0;cache_hits<=0;cache_misses<=0;
   prefetch_hits<=0;prefetch_wait_cycles<=0;overlap_compute_read_cycles<=0;overlap_compute_write_cycles<=0;
   ld_valid<=0;ld_kind<=0;ld_stage<=0;ld_address<=0;ld_epoch<=0;ld_layer<=0;ld_matrix<=0;
   ld_block_row<=0;ld_block_col<=0;ld_allowed_ops<=0;ld_completed_ops<=0;ld_encoding<=0;
   ld_block_valid<=0;ld_in_operation<=0;stage_release<=0;
   c_hdr_ready<=0;c_ld_ready<=0;cseg_valid<=0;cseg_address<=0;cseg_epoch<=0;
   cseg_layer<=0;cseg_matrix<=0;cseg_row<=0;cseg_col<=0;cseg_beats<=6;
   cval_valid<=0;cval_data<=0;cval_last<=0;abort_storage<=0;
   result_valid_r<=0;result_cache_address<=0;result_epoch<=0;result_target_low<=0;
   result_layer<=0;result_matrix<=0;result_block_row<=0;result_block_col<=0;result_op_tag<=0;
   result_block_valid<=0;result_in_operation<=0;result_allowed_ops<=0;result_completed_ops<=0;
   abase<=0;bbase<=0;cbase<=0;epoch<=0;m<=0;n<=0;k<=0;layer<=0;aid<=0;bid<=0;cid<=0;
   target_high<=0;allowed<=0;positions<=0;clip<=0;br<=0;bc<=0;bk<=0;nb_r<=0;nb_c<=0;nb_k<=0;
   run_cycle<=0;collect<=0;quadrant<=0;stage<=0;rr<=0;fresh_c<=0;seg_issued<=0;p0_issue_c<=0;
   slot<=0;ld_groups<=0;ld_bytes<=0;ld_buf<=0;ld_beat<=0;result_payload<=0;
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
   stage_release<=0;ld_valid<=0;c_hdr_ready<=0;c_ld_ready<=0;cseg_valid<=0;cval_valid<=0;
   cval_last<=0;

   case(state)
   IDLE:if(start)begin
    done<=0;fault<=0;error_code<=0;task_cycles<=0;compute_cycles<=0;read_blocks<=0;
    write_blocks<=0;cache_hits<=0;cache_misses<=0;prefetch_hits<=0;prefetch_wait_cycles<=0;
    overlap_compute_read_cycles<=0;overlap_compute_write_cycles<=0;result_valid_r<=0;
    abort_storage<=0;result_payload<=0;
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
     br<=0;bc<=0;bk<=0;nb_r<=(cfg_m+31)>>5;nb_c<=(cfg_n+31)>>5;nb_k<=(cfg_k+31)>>5;
     quadrant<=0;run_cycle<=0;collect<=0;rr<=0;stage<=0;
     busy<=1;state<=LOOKUP;
    end
   end
   LOOKUP:begin
    // operand extents and cache are checked once per block
    if(!amap||!bmap||!cmap||({8'd0,abase}+aext>40'h0100000000)||
       ({8'd0,bbase}+bext>40'h0100000000)||({8'd0,cbase}+cext>40'h0100000000)||
       !(({8'd0,abase}+aext<=bbase)||({8'd0,bbase}+bext<=abase))||
       !(({8'd0,abase}+aext<=cbase)||({8'd0,cbase}+cext<=abase))||
       !(({8'd0,bbase}+bext<=cbase)||({8'd0,cbase}+cext<=bbase)))fail(1);
    else begin
     bk<=0;quadrant<=0;run_cycle<=0;collect<=0;stage<=0;
     if(cache_hit_now)begin
      slot<=found;cache_hits<=cache_hits+1;fresh_c<=0;p0_issue_c<=0;seg_issued<=0;
      state<=P0A;
     end else begin
      slot<=rr;install_tag(rr);rr<=rr^1'b1;cache_misses<=cache_misses+1;
      fresh_c<=1;p0_issue_c<=cfg_c_valid;seg_issued<=0;state<=P0A;
     end
    end
   end
   P0A:begin
    ld_valid<=1;ld_kind<=0;ld_stage<=0;ld_address<=a_addr;ld_epoch<=epoch;
    ld_layer<=layer;ld_matrix<=aid;ld_block_row<=br;ld_block_col<=16'd0;
    ld_allowed_ops<=allowed;ld_completed_ops<=0;ld_encoding<=0;
    ld_block_valid<=1;ld_in_operation<=1;
    if(ld_ready)begin read_blocks<=read_blocks+1;state<=P0W;end
   end
   P0W:begin
    ld_valid<=1;ld_kind<=1;ld_stage<=0;ld_address<=b_addr;ld_epoch<=epoch;
    ld_layer<=layer;ld_matrix<=bid;ld_block_row<=16'd0;ld_block_col<=bc;
    ld_allowed_ops<=allowed;ld_completed_ops<=0;ld_encoding<=1;
    ld_block_valid<=1;ld_in_operation<=1;
    if(ld_ready)begin read_blocks<=read_blocks+1;state<=p0_issue_c?CREQ:WAITCUR;end
   end
   CREQ:begin
    ld_valid<=1;ld_kind<=2;ld_stage<=0;ld_address<=c_addr;ld_epoch<=epoch;
    ld_layer<=layer;ld_matrix<=cid;ld_block_row<=br;ld_block_col<=bc;
    ld_allowed_ops<=allowed;ld_completed_ops<=0;ld_encoding<=2;
    ld_block_valid<=1;ld_in_operation<=1;
    if(ld_ready)begin read_blocks<=read_blocks+1;ld_beat<=0;state<=CHDR;end
   end
   CHDR:begin
    c_hdr_ready<=1;
    if(c_hdr_valid)begin
     c_hdr_ready<=0;
     if(c_hdr_error||c_hdr_epoch[31:0]!=epoch||c_hdr_layer[15:0]!=layer||
        c_hdr_matrix[15:0]!=cid||c_hdr_row[15:0]!=br||c_hdr_col[15:0]!=bc||
        c_hdr_encoding[1:0]!=2||c_hdr_allowed[15:0]!=allowed||
        ((c_hdr_completed[15:0]&~allowed)!=0))fail(2);
     else if(c_hdr_exists&&!c_hdr_bvalid)fail(3);
     else if(c_hdr_exists&&c_hdr_completed[1])fail(3);
     else if(c_hdr_exists)begin
      fresh_c<=0;tag_completed[slot[0]]<=c_hdr_completed[15:0];
      ld_groups<=0;ld_bytes<=0;ld_buf<=0;state<=CDATA;
     end else begin
      fresh_c<=1;state<=WAITCUR;
     end
    end
   end
   CDATA:begin
    c_ld_ready<=1;
    if(c_ld_valid)begin
     if(c_ld_index!=ld_beat)begin
`ifdef ENGDBG
      $display("ENGDBG CIDX got=%0d exp=%0d",c_ld_index,ld_beat);
`endif
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
`ifdef ENGDBG
     $display("ENGDBG CDONE groups=%0d add=%0d bytes=%0d total=%0d ldbeat=%0d valid=%b",ld_groups,(c_ld_valid&&ld_total>=24?1:0),ld_bytes,ld_total,ld_beat,c_ld_valid);
`endif
     if((ld_groups+(c_ld_valid&&ld_total>=24?1:0))!=256||
        (c_ld_valid?(ld_total>=24?(ld_total-24):ld_total):ld_bytes)!=0)fail(5);
     else state<=WAITCUR;
    end
   end
   WAITCUR:begin
    if(!cur_stage_ok)prefetch_wait_cycles<=prefetch_wait_cycles+1;
    if(stage_a_fault[stage]||stage_w_fault[stage])fail(9);
    else if(cur_stage_ok)begin
     if(!stage_a_bvalid[stage]||!stage_w_bvalid[stage]||stage_a_inop[stage]||stage_w_inop[stage]||
        stage_a_epoch[stage*32+:32]!=epoch||stage_w_epoch[stage*32+:32]!=epoch||
        stage_a_layer[stage*16+:16]!=layer||stage_w_layer[stage*16+:16]!=layer||
        stage_a_matrix[stage*16+:16]!=aid||stage_w_matrix[stage*16+:16]!=bid||
        stage_a_row[stage*16+:16]!=br||stage_w_row[stage*16+:16]!=bk||
        stage_a_col[stage*16+:16]!=bk||stage_w_col[stage*16+:16]!=bc||
        stage_a_allowed[stage*16+:16]!=allowed||stage_w_allowed[stage*16+:16]!=allowed||
        stage_a_completed[stage*16+:16]!=0||stage_w_completed[stage*16+:16]!=0||
        stage_a_encoding[stage*2+:2]!=0||stage_w_encoding[stage*2+:2]!=1)fail(2);
     else state<=PREFA;
    end
   end
   PREFA:begin
    if(next_bk>=nb_k)begin state<=CLEAR;end
    else begin
     ld_valid<=1;ld_kind<=0;ld_stage<=stage^1'b1;ld_address<=an_addr;ld_epoch<=epoch;
     ld_layer<=layer;ld_matrix<=aid;ld_block_row<=br;ld_block_col<=next_bk;
     ld_allowed_ops<=allowed;ld_completed_ops<=0;ld_encoding<=0;
     ld_block_valid<=1;ld_in_operation<=1;
     if(ld_ready)begin read_blocks<=read_blocks+1;state<=PREFW;end
    end
   end
   PREFW:begin
    ld_valid<=1;ld_kind<=1;ld_stage<=stage^1'b1;ld_address<=bn_addr;ld_epoch<=epoch;
    ld_layer<=layer;ld_matrix<=bid;ld_block_row<=next_bk;ld_block_col<=bc;
    ld_allowed_ops<=allowed;ld_completed_ops<=0;ld_encoding<=1;
    ld_block_valid<=1;ld_in_operation<=1;
    if(ld_ready)begin read_blocks<=read_blocks+1;state<=CLEAR;end
   end
   CLEAR:begin run_cycle<=0;state<=RUN;end
   RUN:begin
    if(run_cycle==65)begin collect<=0;state<=CREAD;end
    else run_cycle<=run_cycle+1;
   end
   CREAD:state<=COLLECT;
   COLLECT:begin
    if(cwr_error)fail(10);
    else if(c_overflow)begin
`ifdef ENGDBG
     $display("ENGDBG OVF bk=%0d q=%0d coll=%0d ci=%0d old=%012h sum=%012h add=%013h",bk,quadrant,collect,collect_ci,cache_a_rdata[47:0],sums[collect*48+:48],c_add);
`endif
     fail(8);
    end
    else if(!is_final_k||(seg_issued&&cval_valid&&cval_ready))begin
     // commit one 4-value group
     result_payload[collect_ci*48+:192]<=collected_values;
     if(is_final_k&&collect[3:0]==12)seg_issued<=0;
     if(collect==252)begin
      if(quadrant==3)begin
       tag_completed[slot[0]]<=tag_completed[slot[0]]|16'h0001;
       if(next_bk<nb_k)state<=NEXTK;
       else begin stage_release<=1<<stage;state<=WAITWR;end
      end else begin quadrant<=quadrant+1;state<=CLEAR;end
     end else begin
      collect<=collect+4;state<=CREAD;
     end
    end else if(is_final_k&&!seg_issued)begin
     // wait for the segment command to be accepted
     cseg_valid<=1;
     cseg_address<=seg_addr;cseg_epoch<=epoch;cseg_layer<=layer;cseg_matrix<=cid;
     cseg_row<=br;cseg_col<=bc;cseg_beats<=6;
     if(cseg_ready)begin seg_issued<=1;write_blocks<=write_blocks+1;end
    end else begin
     // wait for the C packer credit; keep sums/cache value stable
     cval_valid<=1;cval_data<=collected_values;cval_last<=(collect[3:0]==12);
    end
   end
   NEXTK:begin
    stage_release<=1<<stage;
    bk<=next_bk;stage<=stage^1'b1;quadrant<=0;run_cycle<=0;collect<=0;
    // the new stage was prefetched while the old one computed
    if(stage_a_ready[stage^1'b1]&&stage_w_ready[stage^1'b1])prefetch_hits<=prefetch_hits+1;
    state<=WAITCUR;
   end
   WAITWR:begin
    if(cwr_error)begin error_code<=cwr_code;fail(10);end
    else if(cwr_idle)begin
     result_cache_address<={target_high,16'd0}+slot[0]*6144;
     result_target_low<=slot[0]*6144;result_epoch<=epoch;result_layer<=layer;
     result_matrix<=cid;result_block_row<=br;result_block_col<=bc;result_op_tag<=1;
     result_block_valid<=valid_cache[slot[0]];result_in_operation<=0;
     result_allowed_ops<=allowed;result_completed_ops<=tag_completed[slot[0]]|16'h0001;
     result_valid_r<=1;state<=RESULT;
    end
   end
   RESULT:if(result_ready)begin
    result_valid_r<=0;tag_done[slot[0]]<=1;
    if(bc+1<nb_c)begin bc<=bc+1;state<=LOOKUP;end
    else if(br+1<nb_r)begin bc<=0;br<=br+1;state<=LOOKUP;end
    else begin busy<=0;done<=1;state<=DONE;end
   end
   DONE:state<=IDLE;
   FAIL:state<=WAITDRAIN;
   WAITDRAIN:begin
    // all accepted DMA reads/writes must drain before the error is reported
    abort_storage<=1;
    if(storage_drain_done)begin busy<=0;fault<=1;done<=1;state<=IDLE;end
   end
   default:fail(7);
   endcase
  end
 end
endmodule
