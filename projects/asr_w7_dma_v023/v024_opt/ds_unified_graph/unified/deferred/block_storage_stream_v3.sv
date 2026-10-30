`timescale 1ns/1ps
`default_nettype none
// V0.24 matrix storage: registered address validator + legal C48 write
// coalescer.  Derived from v023 ds_matrix/block_storage_stream_v2.sv.
//
//   * ld_expected is split into registered V1(row*ncols) -> V2(*bytes) ->
//     V3(+base/+end) -> V4(compare/push) stages.  ld_ready never waits on the
//     wide multiply or the 64-bit compare.
//   * cseg is accepted into a metadata FIFO; cseg and the first cval of the
//     same 16-value segment may be accepted in one cycle.
//   * the native C48 layout (block_base + unit*96, unit<64, 6 beats) is staged
//     in 6144 B and flushed as <=16-beat, non-4KiB-crossing requests.  Other
//     strides use a generic per-segment path (<=128 B).
//   * write_bytes counts the real WSTRB.  Abort/error pads the accepted burst
//     with zero-strobe beats and drops unposted commands.
//
// Logic simulation only.  No synthesis/STA/CDC/board claim.
module block_storage_stream_v3 #(
 parameter [31:0] ARENA_BASE=32'h03000000,
 parameter [31:0] ARENA_END=32'h08000000,
 parameter [31:0] PARAM_BASE=32'h10000000,
 parameter [31:0] PARAM_END=32'h40000000,
 parameter integer LD_Q=8,
 parameter integer META_Q=4,
 parameter integer CQ_Q=8,
 parameter integer STAGE_BYTES=6144,
 parameter integer MAX_REQ_BEATS=16,
 parameter integer COALESCE_EN=1,
 parameter integer WR_OUT=8
)(
 input wire clk,rst_n,abort,
 input wire [31:0] param_end,
 input wire [31:0] cfg_a_base,cfg_b_base,cfg_c_base,cfg_epoch,
 input wire [15:0] cfg_m,cfg_n,cfg_k,cfg_layer,cfg_a_id,cfg_b_id,cfg_c_id,cfg_allowed,
 input wire cfg_c_valid,input wire [15:0] cfg_c_completed,

 input wire ld_valid,output wire ld_ready,
 input wire [1:0] ld_kind,
 input wire ld_stage,
 input wire [31:0] ld_address,ld_epoch,
 input wire [15:0] ld_layer,ld_matrix,ld_block_row,ld_block_col,ld_allowed_ops,ld_completed_ops,
 input wire [1:0] ld_encoding,input wire ld_block_valid,ld_in_operation,

 output wire [1:0] stage_a_ready,stage_w_ready,stage_a_fault,stage_w_fault,
 output wire [1:0] stage_a_bvalid,stage_w_bvalid,stage_a_inop,stage_w_inop,
 output wire [63:0] stage_a_epoch,stage_w_epoch,
 output wire [31:0] stage_a_layer,stage_w_layer,stage_a_matrix,stage_w_matrix,
 output wire [31:0] stage_a_row,stage_w_row,stage_a_col,stage_w_col,
 output wire [31:0] stage_a_allowed,stage_w_allowed,stage_a_completed,stage_w_completed,
 output wire [3:0] stage_a_encoding,stage_w_encoding,
 input wire [1:0] stage_release,
 input wire rd_stage,rd_row_half,rd_col_half,
 input wire [79:0] a_k,w_k,
 output wire [255:0] a_values,output wire [111:0] w_values,

 output wire c_hdr_valid,c_hdr_exists,c_hdr_bvalid,c_hdr_inop,c_hdr_error,
 output wire [7:0] c_hdr_code,
 output wire [63:0] c_hdr_epoch,
 output wire [31:0] c_hdr_layer,c_hdr_matrix,c_hdr_row,c_hdr_col,c_hdr_allowed,c_hdr_completed,
 output wire [3:0] c_hdr_encoding,
 input wire c_hdr_ready,
 output wire c_ld_valid,c_ld_last,c_ld_done,c_ld_error,
 output wire [127:0] c_ld_data,output wire [15:0] c_ld_index,output wire [7:0] c_ld_code,
 input wire c_ld_ready,

 input wire cseg_valid,output wire cseg_ready,
 input wire [31:0] cseg_address,cseg_epoch,
 input wire [15:0] cseg_layer,cseg_matrix,cseg_row,cseg_col,cseg_beats,
 input wire cval_valid,output wire cval_ready,input wire [191:0] cval_data,input wire cval_last,
 output wire [7:0] cwr_pending,output wire cwr_idle,cwr_done,cwr_error,output wire [7:0] cwr_code,

 output wire rd_req_valid,input wire rd_req_ready,
 output wire [31:0] rd_req_address,output wire [15:0] rd_req_beats,
 input wire rd_valid,output wire rd_ready,input wire [127:0] rd_data,input wire [15:0] rd_index,
 input wire rd_done,rd_error,
 output wire wr_req_valid,input wire wr_req_ready,
 output wire [31:0] wr_req_address,output wire [15:0] wr_req_beats,
 output wire wr_valid,input wire wr_ready,output wire [127:0] wr_data,output wire [15:0] wr_strobe,
 input wire wr_done,wr_error,

 output wire idle,drain_done,
 output wire [31:0] read_blocks,write_segments,read_bytes,write_bytes,error_count,
 output wire [63:0] read_wait_cycles,write_wait_cycles,
 output wire [31:0] ov_same_cycle,rd_active_wr_active_cycles,
 output wire rd_active,wr_active,
 output wire [1:0] dbg_rstate,dbg_wwait,

 output wire [31:0] cseg_cmds,wr_cmds_posted,wr_beats_sent,
 output wire [31:0] coalesced_segs,generic_segs,flush_reqs,
 output wire [7:0] max_b_credit,
 output wire [31:0] cval_stall_cycles,cseg_stall_cycles
);
 localparam RIDLE=0,RREQ=1,RRD=2,RCHDR=3;
 function automatic [4:0] pop16(input [15:0] bits);
  integer i;
  begin pop16=0; for(i=0;i<16;i=i+1) pop16=pop16+bits[i]; end
 endfunction

 // ---------------------------------------------------------------------
 // cfg-derived geometry
 // ---------------------------------------------------------------------
 wire [31:0] a_ncols=({16'd0,cfg_k}+31)>>5;
 wire [31:0] a_nrows=({16'd0,cfg_m}+31)>>5;
 wire [31:0] b_ncols=({16'd0,cfg_n}+31)>>5;
 wire [31:0] b_nrows=({16'd0,cfg_k}+31)>>5;
 wire [31:0] c_ncols=({16'd0,cfg_n}+31)>>5;
 wire [31:0] c_nrows=({16'd0,cfg_m}+31)>>5;

 function automatic [31:0] ncols_of(input [1:0] k);
  begin ncols_of=(k==0)?a_ncols:(k==1)?b_ncols:c_ncols; end
 endfunction
 function automatic [31:0] nrows_of(input [1:0] k);
  begin nrows_of=(k==0)?a_nrows:(k==1)?b_nrows:c_nrows; end
 endfunction
 function automatic [31:0] bytes_of(input [1:0] k);
  begin bytes_of=(k==0)?32'd2048:(k==1)?32'd1024:32'd6144; end
 endfunction
 function automatic [31:0] base_of(input [1:0] k);
  begin base_of=(k==0)?cfg_a_base:(k==1)?cfg_b_base:cfg_c_base; end
 endfunction

 // ---------------------------------------------------------------------
 // storage state (declared before the validator uses it)
 // ---------------------------------------------------------------------
 reg [1:0] lq_kind[0:LD_Q-1];
 reg lq_stage[0:LD_Q-1],lq_bad[0:LD_Q-1];
 reg [31:0] lq_addr[0:LD_Q-1];
 reg [15:0] lq_beats[0:LD_Q-1];
 reg [3:0] lq_wr,lq_rd,lq_cnt;
 wire [3:0] lq_free=LD_Q-lq_cnt;
 wire lq_have=(lq_cnt!=0);

 reg stg_have[0:1][0:1],stg_ready[0:1][0:1],stg_fault[0:1][0:1];
 reg [31:0] stg_epoch[0:1][0:1];
 reg [15:0] stg_layer[0:1][0:1],stg_matrix[0:1][0:1],stg_row[0:1][0:1],stg_col[0:1][0:1];
 reg [15:0] stg_allowed[0:1][0:1],stg_completed[0:1][0:1];
 reg [1:0] stg_enc[0:1][0:1];
 reg c_meta_bad;
 reg [31:0] c_meta_epoch;
 reg [15:0] c_meta_layer,c_meta_matrix,c_meta_row,c_meta_col,c_meta_allowed,c_meta_completed;
 reg [1:0] c_meta_enc;
 reg c_cmd_busy;

 // =====================================================================
 // Registered ld validator: V0 -> V1(mul) -> V2(mul) -> V3(add) -> V4(cmp)
 // =====================================================================
 reg v0_valid,v1_valid,v2_valid,v3_valid;
 reg [1:0] v0_kind,v1_kind,v2_kind,v3_kind;
 reg v0_stage,v1_stage,v2_stage,v3_stage;
 reg [31:0] v0_addr,v1_addr,v2_addr,v3_addr;
 reg [31:0] v0_epoch,v1_epoch,v2_epoch,v3_epoch;
 reg [15:0] v0_layer,v1_layer,v2_layer,v3_layer;
 reg [15:0] v0_matrix,v1_matrix,v2_matrix,v3_matrix;
 reg [15:0] v0_brow,v1_brow,v2_brow,v3_brow;
 reg [15:0] v0_bcol,v1_bcol,v2_bcol,v3_bcol;
 reg [15:0] v0_allowed,v1_allowed,v2_allowed,v3_allowed;
 reg [15:0] v0_comp,v1_comp,v2_comp,v3_comp;
 reg [1:0] v0_enc,v1_enc,v2_enc,v3_enc;
 reg v0_bvalid,v1_bvalid,v2_bvalid,v3_bvalid;
 reg v0_inop,v1_inop,v2_inop,v3_inop;
 reg [31:0] v1_idx;
 reg [63:0] v2_off;
 reg [63:0] v3_expect,v3_end;
 wire [31:0] v_inflight={28'd0,v0_valid}+{28'd0,v1_valid}+{28'd0,v2_valid}+{28'd0,v3_valid};

 wire stage_free=(ld_kind!=2)?!stg_have[ld_stage][ld_kind]:!c_cmd_busy;
 wire lq_accept_ok=({28'd0,lq_cnt}+v_inflight+32'd1<=LD_Q);
 assign ld_ready=rst_n&&!abort&&stage_free&&lq_accept_ok;

 wire v4_bad=!((v3_epoch==cfg_epoch)&&(v3_layer==cfg_layer)&&
   (v3_matrix==((v3_kind==0)?cfg_a_id:(v3_kind==1)?cfg_b_id:cfg_c_id))&&
   (v3_allowed==cfg_allowed)&&v3_bvalid&&
   (v3_brow<nrows_of(v3_kind))&&(v3_bcol<ncols_of(v3_kind))&&
   (v3_expect=={32'd0,v3_addr})&&(v3_addr[5:0]==0)&&
   (v3_kind==0?v3_enc==2'd0:v3_kind==1?v3_enc==2'd1:v3_enc==2'd2)&&
   v3_inop&&(v3_comp==0)&&
   (((v3_expect>={32'd0,ARENA_BASE})&&(v3_end<={32'd0,ARENA_END}))||
    ((v3_kind==1)&&(v3_expect>={32'd0,PARAM_BASE})&&(v3_end<={32'd0,param_end})&&
     (param_end<=PARAM_END)))&&
   (v3_expect[63:32]==0)&&(v3_end[63:32]==0)&&(v3_kind<=2));

 always @(posedge clk)begin
  if(!rst_n)begin
   v0_valid<=0;v1_valid<=0;v2_valid<=0;v3_valid<=0;
   v0_kind<=0;v1_kind<=0;v2_kind<=0;v3_kind<=0;
   v0_stage<=0;v1_stage<=0;v2_stage<=0;v3_stage<=0;
   v0_addr<=0;v1_addr<=0;v2_addr<=0;v3_addr<=0;
   v0_epoch<=0;v1_epoch<=0;v2_epoch<=0;v3_epoch<=0;
   v0_layer<=0;v1_layer<=0;v2_layer<=0;v3_layer<=0;
   v0_matrix<=0;v1_matrix<=0;v2_matrix<=0;v3_matrix<=0;
   v0_brow<=0;v1_brow<=0;v2_brow<=0;v3_brow<=0;
   v0_bcol<=0;v1_bcol<=0;v2_bcol<=0;v3_bcol<=0;
   v0_allowed<=0;v1_allowed<=0;v2_allowed<=0;v3_allowed<=0;
   v0_comp<=0;v1_comp<=0;v2_comp<=0;v3_comp<=0;
   v0_enc<=0;v1_enc<=0;v2_enc<=0;v3_enc<=0;
   v0_bvalid<=0;v1_bvalid<=0;v2_bvalid<=0;v3_bvalid<=0;
   v0_inop<=0;v1_inop<=0;v2_inop<=0;v3_inop<=0;
   v1_idx<=0;v2_off<=0;v3_expect<=0;v3_end<=0;
  end else begin
   v1_valid<=v0_valid;v2_valid<=v1_valid;v3_valid<=v2_valid;
   v1_kind<=v0_kind;v2_kind<=v1_kind;v3_kind<=v2_kind;
   v1_stage<=v0_stage;v2_stage<=v1_stage;v3_stage<=v2_stage;
   v1_addr<=v0_addr;v2_addr<=v1_addr;v3_addr<=v2_addr;
   v1_epoch<=v0_epoch;v2_epoch<=v1_epoch;v3_epoch<=v2_epoch;
   v1_layer<=v0_layer;v2_layer<=v1_layer;v3_layer<=v2_layer;
   v1_matrix<=v0_matrix;v2_matrix<=v1_matrix;v3_matrix<=v2_matrix;
   v1_brow<=v0_brow;v2_brow<=v1_brow;v3_brow<=v2_brow;
   v1_bcol<=v0_bcol;v2_bcol<=v1_bcol;v3_bcol<=v2_bcol;
   v1_allowed<=v0_allowed;v2_allowed<=v1_allowed;v3_allowed<=v2_allowed;
   v1_comp<=v0_comp;v2_comp<=v1_comp;v3_comp<=v2_comp;
   v1_enc<=v0_enc;v2_enc<=v1_enc;v3_enc<=v2_enc;
   v1_bvalid<=v0_bvalid;v2_bvalid<=v1_bvalid;v3_bvalid<=v2_bvalid;
   v1_inop<=v0_inop;v2_inop<=v1_inop;v3_inop<=v2_inop;

   v0_valid<=0;
   if(ld_valid&&ld_ready)begin
    v0_valid<=1;v0_kind<=ld_kind;v0_stage<=ld_stage;v0_addr<=ld_address;
    v0_epoch<=ld_epoch;v0_layer<=ld_layer;v0_matrix<=ld_matrix;v0_brow<=ld_block_row;
    v0_bcol<=ld_block_col;v0_allowed<=ld_allowed_ops;v0_comp<=ld_completed_ops;
    v0_enc<=ld_encoding;v0_bvalid<=ld_block_valid;v0_inop<=ld_in_operation;
   end

   if(v0_valid)v1_idx<=({16'd0,v0_brow}*ncols_of(v0_kind))+{16'd0,v0_bcol};
   if(v1_valid)v2_off<={32'd0,v1_idx}*{32'd0,bytes_of(v1_kind)};
   if(v2_valid)begin
    v3_expect<={32'd0,base_of(v2_kind)}+v2_off;
    v3_end<={32'd0,base_of(v2_kind)}+v2_off+{32'd0,bytes_of(v2_kind)};
   end
  end
 end

 // ---------------------------------------------------------------------
 // stage header outputs
 // ---------------------------------------------------------------------
 genvar s;
 generate
  for(s=0;s<2;s=s+1)begin:stageout
   assign stage_a_ready[s]=stg_ready[s][0];
   assign stage_w_ready[s]=stg_ready[s][1];
   assign stage_a_fault[s]=stg_fault[s][0];
   assign stage_w_fault[s]=stg_fault[s][1];
   assign stage_a_bvalid[s]=stg_have[s][0];
   assign stage_w_bvalid[s]=stg_have[s][1];
   assign stage_a_inop[s]=1'b0;
   assign stage_w_inop[s]=1'b0;
   assign stage_a_epoch[s*32+:32]=stg_epoch[s][0];
   assign stage_w_epoch[s*32+:32]=stg_epoch[s][1];
   assign stage_a_layer[s*16+:16]=stg_layer[s][0];
   assign stage_w_layer[s*16+:16]=stg_layer[s][1];
   assign stage_a_matrix[s*16+:16]=stg_matrix[s][0];
   assign stage_w_matrix[s*16+:16]=stg_matrix[s][1];
   assign stage_a_row[s*16+:16]=stg_row[s][0];
   assign stage_w_row[s*16+:16]=stg_row[s][1];
   assign stage_a_col[s*16+:16]=stg_col[s][0];
   assign stage_w_col[s*16+:16]=stg_col[s][1];
   assign stage_a_allowed[s*16+:16]=stg_allowed[s][0];
   assign stage_w_allowed[s*16+:16]=stg_allowed[s][1];
   assign stage_a_completed[s*16+:16]=stg_completed[s][0];
   assign stage_w_completed[s*16+:16]=stg_completed[s][1];
   assign stage_a_encoding[s*2+:2]=stg_enc[s][0];
   assign stage_w_encoding[s*2+:2]=stg_enc[s][1];
  end
 endgenerate

 // ---------------------------------------------------------------------
 // C header
 // ---------------------------------------------------------------------
 reg c_hdr_v;
 reg c_hdr_v_exists,c_hdr_v_err;
 reg [7:0] c_hdr_v_code;
 assign c_hdr_valid=c_hdr_v;
 assign c_hdr_exists=c_hdr_v_exists&&!c_meta_bad;
 assign c_hdr_bvalid=c_hdr_v_exists&&!c_meta_bad;
 assign c_hdr_inop=1'b0;
 assign c_hdr_error=c_hdr_v_err;
 assign c_hdr_code=c_hdr_v_code;
 assign c_hdr_epoch={32'd0,c_meta_epoch};
 assign c_hdr_layer={16'd0,c_meta_layer};
 assign c_hdr_matrix={16'd0,c_meta_matrix};
 assign c_hdr_row={16'd0,c_meta_row};
 assign c_hdr_col={16'd0,c_meta_col};
 assign c_hdr_allowed={16'd0,c_meta_allowed};
 assign c_hdr_completed={16'd0,c_meta_completed};
 assign c_hdr_encoding={2'd0,c_meta_enc};

 // ---------------------------------------------------------------------
 // read engine
 // ---------------------------------------------------------------------
 reg [1:0] rstate;
 reg [1:0] cur_kind;
 reg cur_stage,cur_bad;
 reg [31:0] cur_addr;
 reg [15:0] cur_beats;
 reg [15:0] recv;
 reg c_hdr_done;
 reg c_ld_done_r,c_ld_error_r;
 reg [7:0] c_ld_code_r;
 reg [31:0] rd_blocks_r,rd_bytes_r,rd_err_cnt;
 reg [63:0] rd_wait;
 reg [31:0] ov_same,rdwr_active;

 wire r_busy=(rstate!=RIDLE);
 assign rd_req_valid=(rstate==RREQ);
 assign rd_req_address=cur_addr;
 assign rd_req_beats=cur_beats;
 assign rd_ready=(rstate==RRD)&&(cur_kind!=2||(c_hdr_done&&c_ld_ready));
 wire r_hs=(rstate==RRD)&&rd_valid&&rd_ready;
 wire [15:0] recv_after=recv+(r_hs?1:0);
 wire bank_wr_en=r_hs&&(cur_kind!=2);
 assign c_ld_valid=(rstate==RRD)&&(cur_kind==2)&&rd_valid;
 assign c_ld_data=rd_data;
 assign c_ld_index=rd_index;
 assign c_ld_last=(rd_index+1==cur_beats);
 assign c_ld_done=c_ld_done_r;
 assign c_ld_error=c_ld_error_r;
 assign c_ld_code=c_ld_code_r;

 wire [1:0] h_kind=lq_kind[lq_rd[2:0]];
 wire h_stage=lq_stage[lq_rd[2:0]];
 wire h_bad=lq_bad[lq_rd[2:0]];
 wire [31:0] h_addr=lq_addr[lq_rd[2:0]];
 wire [15:0] h_beats=lq_beats[lq_rd[2:0]];
 wire lq_pop=(rstate==RIDLE&&lq_have&&(h_bad&&h_kind!=2))||
   (rstate==RREQ&&abort)||
   (rstate==RCHDR&&c_hdr_ready&&(cur_bad||!c_hdr_v_exists))||
   (rstate==RRD&&rd_done)||
   (abort&&lq_have&&rstate==RIDLE);

 operand_banks_dual_v1 banks(
  .clk(clk),.wr_en(bank_wr_en),.wr_stage(cur_stage),.wr_kind(cur_kind[0]),
  .wr_beat(recv[7:0]),.wr_data(rd_data),
  .rd_stage(rd_stage),.rd_row_half(rd_row_half),.rd_col_half(rd_col_half),
  .a_k(a_k),.w_k(w_k),.a_values(a_values),.w_values(w_values));

 // ---------------------------------------------------------------------
 // C48 write path
 // ---------------------------------------------------------------------
 // metadata FIFO
 reg [31:0] mq_addr[0:META_Q-1];
 reg [15:0] mq_beats[0:META_Q-1],mq_row[0:META_Q-1],mq_col[0:META_Q-1];
 reg [1:0] mq_wr,mq_rd;
 reg [2:0] mq_cnt;

 // current segment
 reg cur_seg_valid;
 reg [31:0] cur_seg_addr;
 reg [15:0] cur_seg_beats;
 reg [1:0] grp_idx;
 reg cur_native;
 reg [31:0] cur_rel,cur_blk;
 reg [5:0] cur_unit;

 // staging buffer / completion bitmap
 reg [7:0] stage_mem[0:STAGE_BYTES-1];
 reg [63:0] unit_done;
 reg [1:0] half_ready;
 reg [6:0] done0,done1;
 reg [31:0] blk_base;
 reg blk_valid;

 // generic stride path: two 128 B buffers
 reg [7:0] gen_mem[0:1][0:127];
 reg [1:0] gen_sel,gen_busy;
 reg [7:0] gen_bytes;

 // write command queue
 reg [31:0] cq_addr[0:CQ_Q-1];
 reg [15:0] cq_beats[0:CQ_Q-1];
 reg [12:0] cq_bytes[0:CQ_Q-1];
 reg [12:0] cq_off[0:CQ_Q-1];
 reg cq_src[0:CQ_Q-1];
 reg [3:0] cq_wr,cq_rd,cq_cnt;

 // flush engine
 reg fl_active;
 reg fl_half;
 reg [12:0] fl_off;
 reg [31:0] fl_reqs;

 // write request / beat engine
 reg w_cur_valid;
 reg [31:0] w_addr;
 reg [15:0] w_beats,w_sent;
 reg [12:0] w_bytes;
 reg [12:0] w_off;
 reg w_src,w_pad;
 reg beat_valid,rd_pending;
 reg [127:0] beat_data;
 reg [12:0] rd_addr;
 reg rd_src,rd_buf;
 reg [31:0] wr_segs,wr_cmds,wr_beats,wr_bytes,wr_err_cnt;
 reg [63:0] wr_wait;
 reg wr_err_sticky,cwr_err_r,cwr_done_r;
 reg [7:0] wr_code_r;
 reg [7:0] b_out,b_out_max;
 reg [7:0] cwr_pend;
 reg [31:0] cseg_cmds_r,coalesced_r,generic_r,cval_stall_r,cseg_stall_r;

 // ---------------------------------------------------------------------
 // segment start / legality
 // ---------------------------------------------------------------------
 wire cseg_hs=cseg_valid&&cseg_ready;
 wire cval_hs=cval_valid&&cval_ready;
 wire start_bypass=cseg_hs&&!cur_seg_valid;
 wire start_pop=cval_hs&&cval_last&&((mq_cnt!=0)||(cseg_hs&&cur_seg_valid));

 wire [31:0] st_addr=start_bypass?cseg_address:mq_addr[mq_rd[1:0]];
 wire [15:0] st_beats=start_bypass?cseg_beats:mq_beats[mq_rd[1:0]];
 wire [15:0] st_row=start_bypass?cseg_row:mq_row[mq_rd[1:0]];
 wire [15:0] st_col=start_bypass?cseg_col:mq_col[mq_rd[1:0]];
 wire [63:0] st_blk64={32'd0,cfg_c_base}+(({48'd0,st_row}*c_ncols)+st_col)*64'd6144;
 wire [31:0] st_blk=st_blk64[31:0];
 wire [31:0] st_rel=st_addr-st_blk;
 wire [7:0] st_q=st_rel[12:5];
 wire st_native=COALESCE_EN&&(st_blk64[63:32]==0)&&(st_blk[3:0]==0)&&
   (st_addr>=st_blk)&&(st_addr<st_blk+32'd6144)&&(st_rel[4:0]==0)&&(st_rel[31:13]==0)&&
   ((st_q%3)==0)&&((st_q/3)<64)&&(st_beats==16'd6);
 wire [5:0] st_unit=st_q/3;

 wire [63:0] c_extent=({32'd0,c_nrows}*c_ncols)*64'd6144;
 wire [63:0] c_limit={32'd0,cfg_c_base}+c_extent;
 wire [63:0] st_end64={32'd0,st_addr}+({48'd0,st_beats}<<4);
 wire seg_bad=(st_addr[3:0]!=0)||(st_beats==0)||(st_beats>16'd384)||
   (st_row>=c_nrows)||(st_col>=c_ncols)||(st_addr<st_blk)||
   (st_end64>(st_blk+64'd6144))||(st_end64>c_limit)||(st_end64>{32'd0,ARENA_END})||
   (st_end64[63:32]!=0)||(st_addr>32'hFFFF_FFF0)||
   (start_bypass?((cseg_epoch!=cfg_epoch)||(cseg_layer!=cfg_layer)||(cseg_matrix!=cfg_c_id)):1'b0);

 // popped metadata fields (for the segment after a cval_last)
 wire [63:0] pop_blk64={32'd0,cfg_c_base}+(({48'd0,mq_row[mq_rd[1:0]]}*c_ncols)+mq_col[mq_rd[1:0]])*64'd6144;
 wire [31:0] pop_blk=pop_blk64[31:0];
 wire [31:0] pop_rel=mq_addr[mq_rd[1:0]]-pop_blk;
 wire [7:0] pop_q=pop_rel[12:5];
 wire pop_native=COALESCE_EN&&(pop_blk64[63:32]==0)&&(pop_blk[3:0]==0)&&
   (mq_addr[mq_rd[1:0]]>=pop_blk)&&(mq_addr[mq_rd[1:0]]<pop_blk+32'd6144)&&
   (pop_rel[4:0]==0)&&(pop_rel[31:13]==0)&&((pop_q%3)==0)&&((pop_q/3)<64)&&
   (mq_beats[mq_rd[1:0]]==16'd6);
 wire [5:0] pop_unit=pop_q/3;

 // cseg legality at the accept point (covers both bypass and FIFO push)
 wire [63:0] cs_blk64={32'd0,cfg_c_base}+(({48'd0,cseg_row}*c_ncols)+cseg_col)*64'd6144;
 wire [31:0] cs_blk=cs_blk64[31:0];
 wire [31:0] cs_rel=cseg_address-cs_blk;
 wire [7:0] cs_q=cs_rel[12:5];
 wire cs_native=COALESCE_EN&&(cs_blk64[63:32]==0)&&(cs_blk[3:0]==0)&&
   (cseg_address>=cs_blk)&&(cseg_address<cs_blk+32'd6144)&&
   (cs_rel[4:0]==0)&&(cs_rel[31:13]==0)&&((cs_q%3)==0)&&((cs_q/3)<64)&&
   (cseg_beats==16'd6);
 wire [63:0] cs_end64={32'd0,cseg_address}+({48'd0,cseg_beats}<<4);
 wire cs_bad=(cseg_address[3:0]!=0)||(cseg_beats==0)||(cseg_beats>16'd384)||
   (cseg_row>=c_nrows)||(cseg_col>=c_ncols)||(cseg_address<cs_blk)||
   (cs_end64>(cs_blk+64'd6144))||(cs_end64>c_limit)||(cs_end64>{32'd0,ARENA_END})||
   (cs_end64[63:32]!=0)||(cseg_address>32'hFFFF_FFF0)||
   (cseg_epoch!=cfg_epoch)||(cseg_layer!=cfg_layer)||(cseg_matrix!=cfg_c_id);

 // acceptance
 assign cseg_ready=rst_n&&!abort&&!wr_err_sticky&&(mq_cnt<META_Q);
 wire eff_native=start_bypass?st_native:(cur_seg_valid?cur_native:1'b0);
 wire generic_ok=!gen_busy[gen_sel]&&(gen_bytes+8'd24<=8'd128)&&(cq_cnt<CQ_Q);
 wire have_seg=start_bypass||cur_seg_valid;
 assign cval_ready=rst_n&&!abort&&!wr_err_sticky&&have_seg&&
   (eff_native||generic_ok)&&!((start_bypass&&cs_bad));

 wire use_start=start_bypass;
 wire [31:0] eff_rel=use_start?st_rel:cur_rel;
 wire [5:0] eff_unit=use_start?st_unit:cur_unit;
 wire [1:0] eff_grp=use_start?2'd0:grp_idx;
 wire [7:0] eff_grp_off=grp_idx*8'd24;
 wire [12:0] stage_wr_off=eff_rel[12:0]+{5'd0,eff_grp_off};

 // staging / generic write (24 B per cval)
 integer b;
 always @(posedge clk)begin
  if(cval_hs)begin
   if(eff_native)begin
    for(b=0;b<24;b=b+1)stage_mem[stage_wr_off+b]<=cval_data[b*8+:8];
   end else begin
    for(b=0;b<24;b=b+1)gen_mem[gen_sel][gen_bytes+b]<=cval_data[b*8+:8];
   end
  end
 end
 wire [8:0] gen_next_bytes=gen_bytes+8'd24;
 wire [15:0] gen_beats=(gen_next_bytes+8'd15)>>4;

 // write data read (synchronous, one beat/cycle)
 wire [12:0] sent_bytes={6'd0,w_sent[7:0]}*13'd16;
 wire [127:0] rd_data_mux;
 generate
  for(genvar bb=0;bb<16;bb=bb+1)begin:beatmux
   assign rd_data_mux[bb*8+:8]=rd_src?gen_mem[rd_buf][rd_addr[6:0]+bb[6:0]]:
     stage_mem[rd_addr+bb[12:0]];
  end
 endgenerate

 wire [12:0] w_left=(w_bytes>sent_bytes)?(w_bytes-sent_bytes):13'd0;
 wire [15:0] w_strobe=(w_pad||!w_cur_valid)?16'h0:
   (w_left>=13'd16 ? 16'hffff : ((16'h1<<w_left[3:0])-16'h1));

 assign wr_req_valid=!w_cur_valid&&(cq_cnt!=0)&&!wr_err_sticky&&!abort&&(b_out<WR_OUT);
 assign wr_req_address=cq_addr[cq_rd[2:0]];
 assign wr_req_beats=cq_beats[cq_rd[2:0]];
 assign wr_valid=w_cur_valid&&beat_valid&&(w_sent<w_beats)&&(w_pad||!wr_err_sticky);
 assign wr_data=beat_data;
 assign wr_strobe=w_strobe;
 wire wr_hs=wr_valid&&wr_ready;

 // command queue push / pop
 wire cq_space=(cq_cnt<CQ_Q);
 wire gen_complete=cval_hs&&cval_last&&!eff_native;
 wire gen_push=gen_complete&&cq_space;
 wire [31:0] eff_seg_addr=use_start?st_addr:cur_seg_addr;
 wire mq_push=cseg_hs&&cur_seg_valid&&!cs_bad;
 wire mq_pop=start_pop;
 wire pop_from_push=start_pop&&cseg_hs&&(mq_cnt==0);
 wire cq_space_flush=!gen_push&&(cq_cnt<CQ_Q);

 // flush burst computation
 wire [31:0] fl_base=blk_base+(fl_half?32'd3072:32'd0);
 wire [12:0] fl_rem=13'd3072-fl_off;
 wire [12:0] fl_addr_sum={1'b0,fl_base[11:0]}+fl_off;
 wire [11:0] fl_addr_low=fl_addr_sum[11:0];
 wire [12:0] fl_page_left=13'd4096-{1'b0,fl_addr_low};
 wire [8:0] fl_page_beats=fl_page_left[12:4];
 wire [8:0] fl_cap=fl_rem>>4;
 wire [8:0] fl_cap_max=(fl_cap>MAX_REQ_BEATS)?MAX_REQ_BEATS[8:0]:fl_cap;
 wire [8:0] fl_beats9=(fl_page_beats>fl_cap_max)?fl_cap_max:fl_page_beats;
 wire start_half=half_ready[0]?1'b0:1'b1;
 wire [31:0] start_fl_addr=blk_base+(start_half?32'd3072:32'd0);
 wire [12:0] start_page_left=13'd4096-{1'b0,start_fl_addr[11:0]};
 wire [8:0] start_page_beats=start_page_left[12:4];
 wire [8:0] start_cap=(start_page_beats>9'd192)?9'd192:start_page_beats;
 wire [8:0] start_beats9=(start_cap>MAX_REQ_BEATS[8:0])?MAX_REQ_BEATS[8:0]:start_cap;
 wire fl_can_start=!fl_active&&(half_ready!=0)&&cq_space_flush&&(start_beats9!=0);
 wire fl_can_next=fl_active&&cq_space_flush&&(fl_beats9!=0);
 wire fl_push=fl_can_start||fl_can_next;
 wire [1:0] cq_push={1'b0,gen_push}+{1'b0,fl_push};
 wire cq_pop=wr_req_valid&&wr_req_ready;

 // segment class counters (bypass + pop can coincide in the one-cycle
 // early-cseg case, hence the 2-bit increments)
 wire bypass_coal=cseg_hs&&!cur_seg_valid&&!cs_bad&&st_native;
 wire bypass_gen =cseg_hs&&!cur_seg_valid&&!cs_bad&&!st_native;
 wire new_native=pop_from_push?st_native:pop_native;
 wire pop_coal=start_pop&&new_native;
 wire pop_gen =start_pop&&!new_native;
 wire [1:0] coal_inc={1'b0,bypass_coal}+{1'b0,pop_coal};
 wire [1:0] gen_inc ={1'b0,bypass_gen }+{1'b0,pop_gen };

 // status
 assign cseg_cmds=cseg_cmds_r;
 assign wr_cmds_posted=wr_cmds;
 assign wr_beats_sent=wr_beats;
 assign coalesced_segs=coalesced_r;
 assign generic_segs=generic_r;
 assign flush_reqs=fl_reqs;
 assign max_b_credit=b_out_max;
 assign cval_stall_cycles=cval_stall_r;
 assign cseg_stall_cycles=cseg_stall_r;
 assign cwr_pending=cwr_pend;
 assign cwr_done=cwr_done_r;
 assign cwr_error=cwr_err_r;
 assign cwr_code=wr_code_r;

 wire gen_busy_any=(gen_busy!=0);
 wire write_idle=(cq_cnt==0)&&!w_cur_valid&&(b_out==0)&&(mq_cnt==0)&&
   !cur_seg_valid&&!fl_active&&(half_ready==0)&&!gen_busy_any;
 assign cwr_idle=write_idle;

 wire [7:0] b_out_next=b_out+(wr_req_valid&&wr_req_ready?1:0)-(wr_done?1:0);
 wire [7:0] pend_sum=cq_cnt+{6'd0,w_cur_valid}+b_out+{6'd0,fl_active}+
   {6'd0,half_ready}+mq_cnt+{7'd0,cur_seg_valid}+{6'd0,gen_busy_any};

 integer i;
 always @(posedge clk)begin
  if(!rst_n)begin
   rstate<=RIDLE;lq_wr<=0;lq_rd<=0;lq_cnt<=0;
   cur_kind<=0;cur_stage<=0;cur_bad<=0;cur_addr<=0;cur_beats<=0;recv<=0;
   c_hdr_done<=0;c_hdr_v<=0;c_hdr_v_exists<=0;c_hdr_v_err<=0;c_hdr_v_code<=0;
   c_ld_done_r<=0;c_ld_error_r<=0;c_ld_code_r<=0;c_cmd_busy<=0;c_meta_bad<=0;
   c_meta_epoch<=0;c_meta_layer<=0;c_meta_matrix<=0;c_meta_row<=0;c_meta_col<=0;
   c_meta_allowed<=0;c_meta_completed<=0;c_meta_enc<=0;
   rd_blocks_r<=0;rd_bytes_r<=0;rd_err_cnt<=0;rd_wait<=0;ov_same<=0;rdwr_active<=0;
   mq_wr<=0;mq_rd<=0;mq_cnt<=0;
   cur_seg_valid<=0;cur_seg_addr<=0;cur_seg_beats<=0;grp_idx<=0;cur_native<=0;
   cur_rel<=0;cur_blk<=0;cur_unit<=0;
   unit_done<=0;half_ready<=0;done0<=0;done1<=0;blk_base<=0;blk_valid<=0;
   gen_sel<=0;gen_busy<=0;gen_bytes<=0;
   cq_wr<=0;cq_rd<=0;cq_cnt<=0;
   fl_active<=0;fl_half<=0;fl_off<=0;fl_reqs<=0;
   w_cur_valid<=0;w_addr<=0;w_beats<=0;w_sent<=0;w_bytes<=0;w_off<=0;w_src<=0;w_pad<=0;
   beat_valid<=0;rd_pending<=0;beat_data<=0;rd_addr<=0;rd_src<=0;rd_buf<=0;
   wr_segs<=0;wr_cmds<=0;wr_beats<=0;wr_bytes<=0;wr_err_cnt<=0;wr_wait<=0;
   wr_err_sticky<=0;cwr_err_r<=0;cwr_done_r<=0;wr_code_r<=0;b_out<=0;b_out_max<=0;cwr_pend<=0;
   cseg_cmds_r<=0;coalesced_r<=0;generic_r<=0;cval_stall_r<=0;cseg_stall_r<=0;
   v0_valid<=0;v1_valid<=0;v2_valid<=0;v3_valid<=0;
   v0_kind<=0;v1_kind<=0;v2_kind<=0;v3_kind<=0;
   v0_stage<=0;v1_stage<=0;v2_stage<=0;v3_stage<=0;
   v0_addr<=0;v1_addr<=0;v2_addr<=0;v3_addr<=0;
   v0_epoch<=0;v1_epoch<=0;v2_epoch<=0;v3_epoch<=0;
   v0_layer<=0;v1_layer<=0;v2_layer<=0;v3_layer<=0;
   v0_matrix<=0;v1_matrix<=0;v2_matrix<=0;v3_matrix<=0;
   v0_brow<=0;v1_brow<=0;v2_brow<=0;v3_brow<=0;
   v0_bcol<=0;v1_bcol<=0;v2_bcol<=0;v3_bcol<=0;
   v0_allowed<=0;v1_allowed<=0;v2_allowed<=0;v3_allowed<=0;
   v0_comp<=0;v1_comp<=0;v2_comp<=0;v3_comp<=0;
   v0_enc<=0;v1_enc<=0;v2_enc<=0;v3_enc<=0;
   v0_bvalid<=0;v1_bvalid<=0;v2_bvalid<=0;v3_bvalid<=0;
   v0_inop<=0;v1_inop<=0;v2_inop<=0;v3_inop<=0;
   v1_idx<=0;v2_off<=0;v3_expect<=0;v3_end<=0;
   for(i=0;i<2;i=i+1)begin
    stg_have[i][0]<=0;stg_have[i][1]<=0;stg_ready[i][0]<=0;stg_ready[i][1]<=0;
    stg_fault[i][0]<=0;stg_fault[i][1]<=0;
    stg_epoch[i][0]<=0;stg_epoch[i][1]<=0;stg_layer[i][0]<=0;stg_layer[i][1]<=0;
    stg_matrix[i][0]<=0;stg_matrix[i][1]<=0;stg_row[i][0]<=0;stg_row[i][1]<=0;
    stg_col[i][0]<=0;stg_col[i][1]<=0;stg_allowed[i][0]<=0;stg_allowed[i][1]<=0;
    stg_completed[i][0]<=0;stg_completed[i][1]<=0;stg_enc[i][0]<=0;stg_enc[i][1]<=0;
   end
   for(i=0;i<STAGE_BYTES;i=i+1)stage_mem[i]<=0;
   for(i=0;i<128;i=i+1)begin gen_mem[0][i]<=0;gen_mem[1][i]<=0;end
  end else begin
   c_ld_done_r<=0;c_ld_error_r<=0;cwr_done_r<=0;
   if(rstate==RREQ)rd_wait<=rd_wait+1;
   if(rstate==RRD&&!r_hs)rd_wait<=rd_wait+1;
   if(r_hs&&wr_hs)ov_same<=ov_same+1;
   if(r_busy&&w_cur_valid)rdwr_active<=rdwr_active+1;
   if(cval_valid&&!cval_ready)cval_stall_r<=cval_stall_r+1;
   if(cseg_valid&&!cseg_ready)cseg_stall_r<=cseg_stall_r+1;

   // ---------------- ld accept reservation ----------------
   if(ld_valid&&ld_ready)begin
    if(ld_kind!=2)begin
     stg_have[ld_stage][ld_kind]<=1;stg_ready[ld_stage][ld_kind]<=0;
     stg_fault[ld_stage][ld_kind]<=0;
     stg_epoch[ld_stage][ld_kind]<=ld_epoch;stg_layer[ld_stage][ld_kind]<=ld_layer;
     stg_matrix[ld_stage][ld_kind]<=ld_matrix;stg_row[ld_stage][ld_kind]<=ld_block_row;
     stg_col[ld_stage][ld_kind]<=ld_block_col;stg_allowed[ld_stage][ld_kind]<=ld_allowed_ops;
     stg_completed[ld_stage][ld_kind]<=ld_completed_ops;stg_enc[ld_stage][ld_kind]<=ld_encoding;
    end else begin
     c_cmd_busy<=1;
     c_meta_epoch<=ld_epoch;c_meta_layer<=ld_layer;c_meta_matrix<=ld_matrix;
     c_meta_row<=ld_block_row;c_meta_col<=ld_block_col;c_meta_allowed<=ld_allowed_ops;
     c_meta_completed<=cfg_c_completed;c_meta_enc<=ld_encoding;c_meta_bad<=0;
    end
   end
   // ---------------- validated ld push ----------------
   if(v3_valid)begin
    lq_kind[lq_wr[2:0]]<=v3_kind;lq_stage[lq_wr[2:0]]<=v3_stage;
    lq_bad[lq_wr[2:0]]<=v4_bad;lq_addr[lq_wr[2:0]]<=v3_addr;
    lq_beats[lq_wr[2:0]]<=v4_bad?16'd0:(v3_kind==0?16'd128:v3_kind==1?16'd64:16'd384);
    lq_wr<=lq_wr+1;
    if(v3_kind!=2)begin
     if(v4_bad)begin stg_fault[v3_stage][v3_kind]<=1;stg_ready[v3_stage][v3_kind]<=0;
      rd_err_cnt<=rd_err_cnt+1;end
    end else begin
     c_meta_bad<=v4_bad;
     if(v4_bad)rd_err_cnt<=rd_err_cnt+1;
    end
   end

   lq_cnt<=lq_cnt+(v3_valid?4'd1:4'd0)-(lq_pop?4'd1:4'd0);

   // ---------------- read engine ----------------
   case(rstate)
    RIDLE:if(lq_have)begin
     cur_kind<=h_kind;cur_stage<=h_stage;cur_bad<=h_bad;cur_addr<=h_addr;cur_beats<=h_beats;
     recv<=0;c_hdr_done<=0;
     if(h_bad&&h_kind!=2)begin
      stg_fault[h_stage][h_kind]<=1;stg_ready[h_stage][h_kind]<=0;
      lq_rd<=lq_rd+1;
     end else if(h_kind==2)begin
      c_hdr_v<=1;c_hdr_v_exists<=cfg_c_valid;
      c_hdr_v_err<=h_bad;c_hdr_v_code<=h_bad?8'h21:8'h00;
      rstate<=RCHDR;
     end else begin
      rd_blocks_r<=rd_blocks_r+1;rstate<=RREQ;
     end
    end
    RREQ:begin
     if(abort)begin
      if(cur_kind!=2)begin stg_fault[cur_stage][cur_kind]<=1;stg_ready[cur_stage][cur_kind]<=0;end
      lq_rd<=lq_rd+1;rstate<=RIDLE;
     end else if(rd_req_ready)rstate<=RRD;
    end
    RCHDR:if(c_hdr_ready)begin
     c_hdr_v<=0;c_hdr_done<=1;
     if(cur_bad||!c_hdr_v_exists)begin
      if(cur_bad)begin c_ld_error_r<=1;c_ld_code_r<=8'h21;rd_err_cnt<=rd_err_cnt+1;end
      else c_ld_done_r<=1;
      c_cmd_busy<=0;lq_rd<=lq_rd+1;rstate<=RIDLE;
     end else begin
      rd_blocks_r<=rd_blocks_r+1;rstate<=RREQ;
     end
    end
    RRD:begin
     if(r_hs)begin
      rd_bytes_r<=rd_bytes_r+16;
      if(rd_index!=recv)begin cur_bad<=1;rd_err_cnt<=rd_err_cnt+1;end
      if(cur_kind==1)begin
       for(integer q=0;q<16;q=q+1)
        if(^rd_data[q*8+:8])begin cur_bad<=1;rd_err_cnt<=rd_err_cnt+1;end
      end
     end
     if(rd_done)begin
      if(cur_kind==2)begin
       if(rd_error||cur_bad||recv_after!=cur_beats)begin
        c_ld_error_r<=1;c_ld_code_r<=rd_error?8'h22:8'h23;rd_err_cnt<=rd_err_cnt+1;
       end else c_ld_done_r<=1;
       c_cmd_busy<=0;c_hdr_done<=0;
      end else begin
       if(rd_error||cur_bad||recv_after!=cur_beats)begin
        stg_fault[cur_stage][cur_kind]<=1;stg_ready[cur_stage][cur_kind]<=0;rd_err_cnt<=rd_err_cnt+1;
       end else stg_ready[cur_stage][cur_kind]<=1;
      end
      lq_rd<=lq_rd+1;rstate<=RIDLE;recv<=0;
     end else if(r_hs)recv<=recv+1;
    end
    default:rstate<=RIDLE;
   endcase

   if(abort&&lq_have&&rstate==RIDLE)begin
    if(h_kind!=2)begin stg_fault[h_stage][h_kind]<=1;stg_ready[h_stage][h_kind]<=0;end
    else c_cmd_busy<=0;
    lq_rd<=lq_rd+1;
   end

   for(i=0;i<2;i=i+1)if(stage_release[i])begin
    stg_have[i][0]<=0;stg_have[i][1]<=0;stg_ready[i][0]<=0;stg_ready[i][1]<=0;
    stg_fault[i][0]<=0;stg_fault[i][1]<=0;
   end

   // ---------------- cseg / cval / flush / write ----------------
   if(cseg_hs)begin
    cseg_cmds_r<=cseg_cmds_r+1;wr_segs<=wr_segs+1;
    if(cs_bad)begin
     wr_err_sticky<=1;wr_code_r<=8'h31;wr_err_cnt<=wr_err_cnt+1;cur_seg_valid<=0;
    end else if(!cur_seg_valid)begin
     cur_seg_valid<=1;cur_seg_addr<=st_addr;cur_seg_beats<=st_beats;
     cur_native<=st_native;cur_rel<=st_rel;cur_blk<=st_blk;cur_unit<=st_unit;grp_idx<=0;
     if(st_native&&(!blk_valid||(st_blk!=blk_base)))begin
      blk_base<=st_blk;blk_valid<=1;unit_done<=0;done0<=0;done1<=0;half_ready<=0;
     end
    end else begin
     mq_addr[mq_wr[1:0]]<=cseg_address;mq_beats[mq_wr[1:0]]<=cseg_beats;
     mq_row[mq_wr[1:0]]<=cseg_row;mq_col[mq_wr[1:0]]<=cseg_col;
     mq_wr<=mq_wr+1;
    end
   end

   if(cval_hs)begin
    if(eff_native)begin
     if(cval_last&&!unit_done[eff_unit])begin
      unit_done[eff_unit]<=1;
      if(eff_unit<32)begin done0<=done0+1;if(done0==31)half_ready[0]<=1;end
      else begin done1<=done1+1;if(done1==31)half_ready[1]<=1;end
     end
    end else if(cval_last)begin
     if(cq_space)begin
      cq_addr[cq_wr[2:0]]<=eff_seg_addr;cq_beats[cq_wr[2:0]]<=gen_beats;
      cq_bytes[cq_wr[2:0]]<=gen_next_bytes;cq_off[cq_wr[2:0]]<={gen_sel,7'd0};
      cq_src[cq_wr[2:0]]<=1;cq_wr<=cq_wr+1;
      gen_busy[gen_sel]<=1;gen_sel<=~gen_sel;gen_bytes<=0;
     end
    end else gen_bytes<=gen_next_bytes;

    if(cval_last)begin
     if(start_pop)begin
      if(pop_from_push)begin
       cur_seg_valid<=1;cur_seg_addr<=st_addr;cur_seg_beats<=st_beats;
       cur_native<=st_native;cur_rel<=st_rel;cur_blk<=st_blk;cur_unit<=st_unit;
      end else begin
       cur_seg_valid<=1;cur_seg_addr<=mq_addr[mq_rd[1:0]];cur_seg_beats<=mq_beats[mq_rd[1:0]];
       cur_native<=pop_native;cur_rel<=pop_rel;cur_blk<=pop_blk;cur_unit<=pop_unit;
      end
      mq_rd<=mq_rd+1;
      if((pop_from_push?st_native:pop_native)&&
         ((pop_from_push?st_blk:pop_blk)!=blk_base))begin
       blk_base<=(pop_from_push?st_blk:pop_blk);blk_valid<=1;
       unit_done<=0;done0<=0;done1<=0;half_ready<=0;
      end
     end else if(start_bypass)begin
      cur_seg_valid<=0;
     end else if(mq_cnt!=0)begin
      cur_seg_valid<=1;cur_seg_addr<=mq_addr[mq_rd[1:0]];cur_seg_beats<=mq_beats[mq_rd[1:0]];
      cur_native<=pop_native;cur_rel<=pop_rel;cur_blk<=pop_blk;cur_unit<=pop_unit;
      mq_rd<=mq_rd+1;
     end else cur_seg_valid<=0;
     grp_idx<=0;
    end else grp_idx<=grp_idx+1;
   end

   // flush requests (one per cycle; generic push has priority for the last slot)
   if(fl_can_start)begin
    fl_active<=(start_beats9<<4<13'd3072);fl_half<=start_half;fl_off<=(start_beats9<<4);
    cq_addr[cq_wr[2:0]]<=start_fl_addr;
    cq_beats[cq_wr[2:0]]<={7'd0,start_beats9};
    cq_bytes[cq_wr[2:0]]<=(start_beats9<<4);
    cq_off[cq_wr[2:0]]<=(start_half?13'd3072:13'd0);cq_src[cq_wr[2:0]]<=0;
    cq_wr<=cq_wr+1;fl_reqs<=fl_reqs+1;
    if((start_beats9<<4)>=3072)begin
     if(start_half)half_ready[1]<=0;else half_ready[0]<=0;
    end
   end else if(fl_can_next)begin
    cq_addr[cq_wr[2:0]]<=fl_base+{19'd0,fl_off};
    cq_beats[cq_wr[2:0]]<={7'd0,fl_beats9};
    cq_bytes[cq_wr[2:0]]<=(fl_beats9<<4);
    cq_off[cq_wr[2:0]]<=(fl_half?13'd3072:13'd0)+fl_off;
    cq_src[cq_wr[2:0]]<=0;
    cq_wr<=cq_wr+1;fl_reqs<=fl_reqs+1;
    if((fl_off+(fl_beats9<<4))>=3072)begin
     fl_active<=0;
     if(fl_half)half_ready[1]<=0;else half_ready[0]<=0;
    end else fl_off<=fl_off+(fl_beats9<<4);
   end

   // write request accept
   if(cq_pop)begin
    w_cur_valid<=1;w_addr<=wr_req_address;w_beats<=wr_req_beats;
    w_bytes<=cq_bytes[cq_rd[2:0]];w_off<=cq_off[cq_rd[2:0]];w_src<=cq_src[cq_rd[2:0]];
    w_sent<=0;w_pad<=0;beat_valid<=0;rd_pending<=1;rd_addr<=cq_off[cq_rd[2:0]];
    rd_src<=cq_src[cq_rd[2:0]];rd_buf<=cq_off[cq_rd[2:0]][7];
    cq_rd<=cq_rd+1;wr_cmds<=wr_cmds+1;
   end
   if(wr_req_valid&&!wr_req_ready)wr_wait<=wr_wait+1;
   if(wr_valid&&!wr_ready)wr_wait<=wr_wait+1;

   // write beats
   if(rd_pending)begin
    beat_data<=rd_data_mux;beat_valid<=1;rd_pending<=0;
   end
   if(wr_hs)begin
    wr_beats<=wr_beats+1;wr_bytes<=wr_bytes+pop16(wr_strobe);
    beat_valid<=0;w_sent<=w_sent+1;
    if(w_sent+1<w_beats)begin
     rd_pending<=1;rd_addr<=w_off+sent_bytes+13'd16;
     rd_src<=w_src;rd_buf<=rd_buf;
    end else begin
     w_cur_valid<=0;
     if(w_src&&!w_pad)gen_busy[rd_buf]<=0;
    end
   end
   if((abort||wr_err_sticky)&&w_cur_valid)w_pad<=1;

   // central counters (single driver)
   mq_cnt<=mq_cnt+(mq_push?3'd1:3'd0)-(mq_pop?3'd1:3'd0);
   if(wr_err_sticky||abort)begin
    cq_cnt<=0;cq_rd<=cq_wr;half_ready<=0;fl_active<=0;unit_done<=0;
    cur_seg_valid<=0;mq_cnt<=0;gen_busy<=0;gen_bytes<=0;blk_valid<=0;
   end else begin
    cq_cnt<=cq_cnt+{2'd0,cq_push}-{3'd0,cq_pop};
   end
   coalesced_r<=coalesced_r+{30'd0,coal_inc};
   generic_r<=generic_r+{30'd0,gen_inc};

   // posted-write credit accounting
   b_out<=b_out_next;
   if(b_out_next>b_out_max)b_out_max<=b_out_next;
   if(wr_error)begin wr_err_sticky<=1;wr_code_r<=8'h33;wr_err_cnt<=wr_err_cnt+1;end

   cwr_pend<=pend_sum;
   if(write_idle&&(cwr_pend!=0)&&!wr_err_sticky)cwr_done_r<=1;
   if((wr_err_sticky||abort)&&write_idle&&!cwr_err_r)begin
    cwr_err_r<=1;rd_err_cnt<=rd_err_cnt+1;
   end
  end
 end

 // ---------------------------------------------------------------------
 // counters / status
 // ---------------------------------------------------------------------
 assign read_blocks=rd_blocks_r;
 assign write_segments=wr_segs;
 assign read_bytes=rd_bytes_r;
 assign write_bytes=wr_bytes;
 assign error_count=rd_err_cnt+wr_err_cnt;
 assign read_wait_cycles=rd_wait;
 assign write_wait_cycles=wr_wait;
 assign ov_same_cycle=ov_same;
 assign rd_active_wr_active_cycles=rdwr_active;
 assign idle=(rstate==RIDLE)&&(lq_cnt==0)&&!c_hdr_v&&write_idle;
 assign drain_done=idle;
 assign rd_active=(rstate!=RIDLE);
 assign wr_active=w_cur_valid||(cq_cnt!=0)||(b_out!=0)||fl_active||(half_ready!=0)||(mq_cnt!=0);
 assign dbg_rstate=rstate;
 assign dbg_wwait={7'd0,w_cur_valid};
endmodule
`default_nettype wire
