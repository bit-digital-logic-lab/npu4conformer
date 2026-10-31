`timescale 1ns/1ps
// V0.23 unified storage controller (V1 + PA-003/PA-004 corrections).
//
// Fixes the two serialization points in block_storage_dma_wide4:
//   1. A/W block transfers are loaded directly into one of two stage banks.
//      Compute may read stage 0 while the DMA fills stage 1, so the next K
//      tile is prefetched during RUN/COLLECT.  There is no whole-block
//      "RDMA done, then RSCALAR" barrier for A/W.
//   2. C48 output is accepted as 4 values/cycle, packed to 128b beats and
//      posted on an independent write transaction port as soon as 16 bytes
//      are available.  Write commands have their own outstanding credit; a
//      BRESP is not required before the next segment is posted.
//
// Block/header/ACL rules, address checks and the C tag fields are preserved
// from block_storage_dma_wide4.  This module is a transactional DMA terminal,
// not an AXI burst engine: the AXI master/DMA belongs to ds_ddr.
module block_storage_stream_v2 #(
 parameter [31:0] ARENA_BASE=32'h03000000,
 parameter [31:0] ARENA_END=32'h08000000,
 parameter [31:0] PARAM_BASE=32'h10000000,
 parameter [31:0] PARAM_END=32'h40000000,
 parameter integer LD_Q=8,
 parameter integer WR_Q=8,
 parameter integer WR_OUT=8
)(
 input wire clk,rst_n,abort,
 input wire [31:0] param_end,
 input wire [31:0] cfg_a_base,cfg_b_base,cfg_c_base,cfg_epoch,
 input wire [15:0] cfg_m,cfg_n,cfg_k,cfg_layer,cfg_a_id,cfg_b_id,cfg_c_id,cfg_allowed,
 input wire cfg_c_valid,input wire [15:0] cfg_c_completed,

 // ---------------- load (A/W prefetch or C stream) command ----------------
 input wire ld_valid,output wire ld_ready,
 input wire [1:0] ld_kind,                       // 0=A, 1=W, 2=C stream
 input wire ld_stage,                            // 0/1 for A/W
 input wire [31:0] ld_address,ld_epoch,
 input wire [15:0] ld_layer,ld_matrix,ld_block_row,ld_block_col,ld_allowed_ops,ld_completed_ops,
 input wire [1:0] ld_encoding,input wire ld_block_valid,ld_in_operation,

 // ---------------- A/W stage readiness + captured header ----------------
 output wire [1:0] stage_a_ready,stage_w_ready,stage_a_fault,stage_w_fault,
 output wire [1:0] stage_a_bvalid,stage_w_bvalid,stage_a_inop,stage_w_inop,
 output wire [63:0] stage_a_epoch,stage_w_epoch,
 output wire [31:0] stage_a_layer,stage_w_layer,stage_a_matrix,stage_w_matrix,
 output wire [31:0] stage_a_row,stage_w_row,stage_a_col,stage_w_col,
 output wire [31:0] stage_a_allowed,stage_w_allowed,stage_a_completed,stage_w_completed,
 output wire [3:0] stage_a_encoding,stage_w_encoding,
 input wire [1:0] stage_release,
 // compute-side bank read port
 input wire rd_stage,rd_row_half,rd_col_half,
 input wire [79:0] a_k,w_k,
 output wire [255:0] a_values,output wire [111:0] w_values,

 // ---------------- C stream load (partial C) ----------------
 output wire c_hdr_valid,c_hdr_exists,c_hdr_bvalid,c_hdr_inop,c_hdr_error,
 output wire [7:0] c_hdr_code,
 output wire [63:0] c_hdr_epoch,
 output wire [31:0] c_hdr_layer,c_hdr_matrix,c_hdr_row,c_hdr_col,c_hdr_allowed,c_hdr_completed,
 output wire [3:0] c_hdr_encoding,
 input wire c_hdr_ready,
 output wire c_ld_valid,c_ld_last,c_ld_done,c_ld_error,
 output wire [127:0] c_ld_data,output wire [15:0] c_ld_index,output wire [7:0] c_ld_code,
 input wire c_ld_ready,

 // ---------------- C48 value stream + segment commands ----------------
 input wire cseg_valid,output wire cseg_ready,
 input wire [31:0] cseg_address,cseg_epoch,
 input wire [15:0] cseg_layer,cseg_matrix,cseg_row,cseg_col,cseg_beats,
 input wire cval_valid,output wire cval_ready,input wire [191:0] cval_data,input wire cval_last,
 output wire [7:0] cwr_pending,output wire cwr_idle,cwr_done,cwr_error,output wire [7:0] cwr_code,

 // ---------------- independent transactional DMA ports ----------------
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
 output wire [1:0] dbg_rstate,dbg_wwait
);
 localparam RIDLE=0,RREQ=1,RRD=2,RCHDR=3;
 function automatic [4:0] pop16(input [15:0] bits);
  integer i;
  begin pop16=0; for(i=0;i<16;i=i+1) pop16=pop16+bits[i]; end
 endfunction

 // ------------------------- address / ACL checks -------------------------
 wire [31:0] a_ncols=({16'd0,cfg_k}+31)>>5;
 wire [31:0] a_nrows=({16'd0,cfg_m}+31)>>5;
 wire [31:0] b_ncols=({16'd0,cfg_n}+31)>>5;
 wire [31:0] b_nrows=({16'd0,cfg_k}+31)>>5;
 wire [31:0] c_ncols=({16'd0,cfg_n}+31)>>5;
 wire [31:0] c_nrows=({16'd0,cfg_m}+31)>>5;
 wire [31:0] block_bytes=(ld_kind==0)?32'd2048:(ld_kind==1)?32'd1024:32'd6144;
 wire [31:0] ld_ncols=(ld_kind==0)?a_ncols:(ld_kind==1)?b_ncols:c_ncols;
 wire [31:0] ld_nrows=(ld_kind==0)?a_nrows:(ld_kind==1)?b_nrows:c_nrows;
 wire [31:0] ld_base=(ld_kind==0)?cfg_a_base:(ld_kind==1)?cfg_b_base:cfg_c_base;
 wire [63:0] ld_expect={32'd0,ld_base}+(({48'd0,ld_block_row}*ld_ncols)+ld_block_col)*block_bytes;
 wire [63:0] ld_end=ld_expect+block_bytes;
 wire ld_in_arena=(ld_expect>={32'd0,ARENA_BASE})&&(ld_end<={32'd0,ARENA_END});
 wire ld_in_param=(ld_kind==1)&&(ld_expect>={32'd0,PARAM_BASE})&&
                   (ld_end<={32'd0,param_end})&&(param_end<=PARAM_END);
 wire ld_no_wrap=(ld_expect[63:32]==0)&&(ld_end[63:32]==0);
 wire ld_id_ok=(ld_epoch==cfg_epoch)&&(ld_layer==cfg_layer)&&
                (ld_matrix==((ld_kind==0)?cfg_a_id:(ld_kind==1)?cfg_b_id:cfg_c_id))&&
                (ld_allowed_ops==cfg_allowed)&&ld_block_valid&&
                (ld_block_row<ld_nrows)&&(ld_block_col<ld_ncols)&&
                (ld_expect=={32'd0,ld_address})&&(ld_address[5:0]==0)&&
                (ld_kind==0?ld_encoding==0:ld_kind==1?ld_encoding==1:ld_encoding==2);
 wire ld_flow_ok=ld_in_operation&&(ld_completed_ops==0);
 wire ld_bad=!ld_id_ok||!ld_flow_ok||!(ld_in_arena||ld_in_param)||!ld_no_wrap||(ld_kind>2);

 wire [63:0] c_extent=({32'd0,c_nrows}*c_ncols)*6144;
 wire [63:0] c_limit={32'd0,cfg_c_base}+c_extent;
 wire [63:0] c_block_base={32'd0,cfg_c_base}+(({48'd0,cseg_row}*c_ncols)+cseg_col)*6144;
 wire [63:0] cseg_end={32'd0,cseg_address}+({48'd0,cseg_beats}<<4);
 wire cseg_bad=(cseg_epoch!=cfg_epoch)||(cseg_layer!=cfg_layer)||(cseg_matrix!=cfg_c_id)||
               (cseg_row>=c_nrows)||(cseg_col>=c_ncols)||(cseg_address[3:0]!=0)||
               (cseg_beats==0)||(cseg_beats>384)||({32'd0,cseg_address}<c_block_base)||
               (cseg_end>(c_block_base+64'd6144))||(cseg_end>c_limit)||(cseg_end>={32'd0,ARENA_END})||
               (cseg_end[63:32]!=0)||(cseg_address>32'hFFFF_FFF0);

 // ---------------------------- load queue ----------------------------
 reg [1:0] lq_kind[0:LD_Q-1];
 reg lq_stage[0:LD_Q-1],lq_bad[0:LD_Q-1];
 reg [31:0] lq_addr[0:LD_Q-1];
 reg [15:0] lq_beats[0:LD_Q-1];
 reg [3:0] lq_wr,lq_rd,lq_cnt;
 wire [3:0] lq_free=LD_Q-lq_cnt;

 // per stage/kind captured header + ownership
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

 wire lq_have=(lq_cnt!=0);
 wire [1:0] h_kind=lq_kind[lq_rd[2:0]];
 wire h_stage=lq_stage[lq_rd[2:0]];
 wire h_bad=lq_bad[lq_rd[2:0]];
 wire [31:0] h_addr=lq_addr[lq_rd[2:0]];
 wire [15:0] h_beats=lq_beats[lq_rd[2:0]];

 assign ld_ready=rst_n&&!abort&&(lq_free!=0)&&
   ((ld_kind!=2)?!stg_have[ld_stage][ld_kind]:!c_cmd_busy);

 // stage header outputs (2 stages x 2 kinds)
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

 // ---------------------------- C header ----------------------------
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

 // ---------------------------- read engine ----------------------------
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

 operand_banks_dual_v1 banks(
  .clk(clk),.wr_en(bank_wr_en),.wr_stage(cur_stage),.wr_kind(cur_kind[0]),
  .wr_beat(recv[7:0]),.wr_data(rd_data),
  .rd_stage(rd_stage),.rd_row_half(rd_row_half),.rd_col_half(rd_col_half),
  .a_k(a_k),.w_k(w_k),.a_values(a_values),.w_values(w_values));

 // ---------------------------- write engine ----------------------------
 reg [31:0] wq_addr[0:WR_Q-1];
 reg [15:0] wq_beats[0:WR_Q-1];
 reg [3:0] wq_wr,wq_rd,wq_cnt;
 reg w_cur_valid;
 reg [31:0] w_cur_addr;
 reg [15:0] w_cur_beats,w_sent;
 reg [255:0] w_buf;
 reg [5:0] w_nbytes;
 reg w_last_seen,w_pad;
 reg [31:0] wr_segs,wr_bytes,wr_err_cnt;
 reg [63:0] wr_wait;
 reg wr_err_sticky,cwr_err_r,cwr_done_r;
 reg [7:0] wr_code_r;
 reg [7:0] b_out;
 reg [7:0] cwr_pend,pend_q;

 assign cseg_ready=rst_n&&!abort&&!wr_err_sticky&&(wq_cnt!=WR_Q);
 assign cval_ready=w_cur_valid&&!w_pad&&!wr_err_sticky&&!abort&&
                   !(w_nbytes>=16)&&!(w_last_seen&&w_nbytes>0)&&
                   (w_nbytes<=8)&&(w_sent<w_cur_beats);
 wire cval_hs=cval_valid&&cval_ready;
 wire [255:0] append_data=w_buf|({64'd0,cval_data}<<(w_nbytes*8));
 wire [5:0] append_bytes=w_nbytes+24;
 wire w_full_beat=(w_nbytes>=16);
 wire w_partial=w_last_seen&&(w_nbytes>0)&&(w_sent<w_cur_beats);
 assign wr_valid=w_cur_valid&&(w_pad||!wr_err_sticky)&&(w_full_beat||w_partial||w_pad)&&(w_sent<w_cur_beats);
 assign wr_data=w_pad?128'd0:w_buf[127:0];
 wire [15:0] used_strobe=w_full_beat?16'hffff:((16'h1<<w_nbytes)-16'h1);
 assign wr_strobe=w_pad?16'h0000:used_strobe;
 wire wr_hs=wr_valid&&wr_ready;
 wire wr_data_active=w_cur_valid;
 assign wr_req_valid=!w_cur_valid&&(wq_cnt!=0)&&!wr_err_sticky&&!abort&&(b_out<WR_OUT);
 assign wr_req_address=wq_addr[wq_rd[2:0]];
 assign wr_req_beats=wq_beats[wq_rd[2:0]];
 assign cwr_pending=cwr_pend;
 assign cwr_idle=(wq_cnt==0)&&!w_cur_valid&&(b_out==0);
 assign cwr_done=cwr_done_r;
 assign cwr_error=cwr_err_r;
 assign cwr_code=wr_code_r;
wire [5:0] nbytes_next=wr_hs?(w_full_beat?w_nbytes-6'd16:6'd0):w_nbytes;
wire [15:0] sent_next=w_sent+(wr_hs?1:0);

 // ---------------------------- shared sequencing ----------------------------
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
   wq_wr<=0;wq_rd<=0;wq_cnt<=0;w_cur_valid<=0;w_cur_addr<=0;w_cur_beats<=0;w_sent<=0;
   w_buf<=0;w_nbytes<=0;w_last_seen<=0;w_pad<=0;wr_segs<=0;wr_bytes<=0;wr_err_cnt<=0;wr_wait<=0;
   wr_err_sticky<=0;cwr_err_r<=0;cwr_done_r<=0;wr_code_r<=0;b_out<=0;cwr_pend<=0;pend_q<=0;
   for(i=0;i<2;i=i+1)begin
    stg_have[i][0]<=0;stg_have[i][1]<=0;stg_ready[i][0]<=0;stg_ready[i][1]<=0;
    stg_fault[i][0]<=0;stg_fault[i][1]<=0;
    stg_epoch[i][0]<=0;stg_epoch[i][1]<=0;stg_layer[i][0]<=0;stg_layer[i][1]<=0;
    stg_matrix[i][0]<=0;stg_matrix[i][1]<=0;stg_row[i][0]<=0;stg_row[i][1]<=0;
    stg_col[i][0]<=0;stg_col[i][1]<=0;stg_allowed[i][0]<=0;stg_allowed[i][1]<=0;
    stg_completed[i][0]<=0;stg_completed[i][1]<=0;stg_enc[i][0]<=0;stg_enc[i][1]<=0;
   end
  end else begin
   c_ld_done_r<=0;c_ld_error_r<=0;cwr_done_r<=0;
   if(rstate==RREQ)rd_wait<=rd_wait+1;
   if(rstate==RRD&&!r_hs)rd_wait<=rd_wait+1;
   if(r_hs&&wr_hs)ov_same<=ov_same+1;
   if(r_busy&&wr_data_active)rdwr_active<=rdwr_active+1;

   // ---------------- accept load command ----------------
   if(ld_valid&&ld_ready)begin
    lq_kind[lq_wr[2:0]]<=ld_kind;lq_stage[lq_wr[2:0]]<=ld_stage;lq_bad[lq_wr[2:0]]<=ld_bad;
    lq_addr[lq_wr[2:0]]<=ld_address;
    lq_beats[lq_wr[2:0]]<=ld_bad?16'd0:(ld_kind==0?16'd128:ld_kind==1?16'd64:16'd384);
    lq_wr<=lq_wr+1;lq_cnt<=lq_cnt+1;
    if(ld_kind!=2)begin
     stg_have[ld_stage][ld_kind]<=1;stg_ready[ld_stage][ld_kind]<=0;
     stg_fault[ld_stage][ld_kind]<=ld_bad;
     stg_epoch[ld_stage][ld_kind]<=ld_epoch;stg_layer[ld_stage][ld_kind]<=ld_layer;
     stg_matrix[ld_stage][ld_kind]<=ld_matrix;stg_row[ld_stage][ld_kind]<=ld_block_row;
     stg_col[ld_stage][ld_kind]<=ld_block_col;stg_allowed[ld_stage][ld_kind]<=ld_allowed_ops;
     stg_completed[ld_stage][ld_kind]<=ld_completed_ops;stg_enc[ld_stage][ld_kind]<=ld_encoding;
     if(ld_bad)rd_err_cnt<=rd_err_cnt+1;
    end else begin
     c_cmd_busy<=1;c_meta_bad<=ld_bad;c_meta_epoch<=ld_epoch;c_meta_layer<=ld_layer;
     c_meta_matrix<=ld_matrix;c_meta_row<=ld_block_row;c_meta_col<=ld_block_col;
     c_meta_allowed<=ld_allowed_ops;c_meta_completed<=cfg_c_completed;c_meta_enc<=ld_encoding;
     if(ld_bad)rd_err_cnt<=rd_err_cnt+1;
    end
   end

   // ---------------- read engine ----------------
   case(rstate)
    RIDLE:if(lq_have)begin
     cur_kind<=h_kind;cur_stage<=h_stage;cur_bad<=h_bad;cur_addr<=h_addr;cur_beats<=h_beats;
     recv<=0;c_hdr_done<=0;
     if(h_bad&&h_kind!=2)begin
      stg_fault[h_stage][h_kind]<=1;stg_ready[h_stage][h_kind]<=0;
      lq_rd<=lq_rd+1;lq_cnt<=lq_cnt-1;
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
      lq_rd<=lq_rd+1;lq_cnt<=lq_cnt-1;rstate<=RIDLE;
     end else if(rd_req_ready)rstate<=RRD;
    end
    RCHDR:if(c_hdr_ready)begin
     c_hdr_v<=0;c_hdr_done<=1;
     if(cur_bad||!c_hdr_v_exists)begin
      if(cur_bad)begin c_ld_error_r<=1;c_ld_code_r<=8'h21;rd_err_cnt<=rd_err_cnt+1;end
      else c_ld_done_r<=1;
      c_cmd_busy<=0;lq_rd<=lq_rd+1;lq_cnt<=lq_cnt-1;rstate<=RIDLE;
     end else begin
      rd_blocks_r<=rd_blocks_r+1;rstate<=RREQ;
     end
    end
    RRD:begin
     if(r_hs)begin
      rd_bytes_r<=rd_bytes_r+16;
      if(rd_index!=recv)begin cur_bad<=1;rd_err_cnt<=rd_err_cnt+1;end
      // B/W7 storage byte carries an even parity bit7. Preserve the V020
      // engine's B_DATA parity rule at the storage boundary.
      if(cur_kind==1)begin
       for(integer q=0;q<16;q=q+1)
        if(^rd_data[q*8+:8])begin cur_bad<=1;rd_err_cnt<=rd_err_cnt+1;end
      end
     end
     if(rd_done)begin
`ifdef BSDBG
      $display("BSDBG done kind=%0d recv_after=%0d beats=%0d rderr=%b bad=%b",cur_kind,recv_after,cur_beats,rd_error,cur_bad);
`endif
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
      lq_rd<=lq_rd+1;lq_cnt<=lq_cnt-1;rstate<=RIDLE;recv<=0;
     end else if(r_hs)recv<=recv+1;
    end
    default:rstate<=RIDLE;
   endcase

   // abort discards commands that have not reached the DMA
   if(abort&&lq_have&&rstate==RIDLE)begin
    if(h_kind!=2)begin stg_fault[h_stage][h_kind]<=1;stg_ready[h_stage][h_kind]<=0;end
    else c_cmd_busy<=0;
    lq_rd<=lq_rd+1;lq_cnt<=lq_cnt-1;
   end

   // stage release wins over a same-cycle completion
   for(i=0;i<2;i=i+1)if(stage_release[i])begin
    stg_have[i][0]<=0;stg_have[i][1]<=0;stg_ready[i][0]<=0;stg_ready[i][1]<=0;
    stg_fault[i][0]<=0;stg_fault[i][1]<=0;
   end

   // ---------------- write engine ----------------
   if(cseg_valid&&cseg_ready)begin
    if(cseg_bad)begin
     wr_err_sticky<=1;wr_code_r<=8'h31;wr_err_cnt<=wr_err_cnt+1;
    end else begin
     wq_addr[wq_wr[2:0]]<=cseg_address;wq_beats[wq_wr[2:0]]<=cseg_beats;
     wq_wr<=wq_wr+1;wq_cnt<=wq_cnt+1;wr_segs<=wr_segs+1;
    end
   end
   if(wr_req_valid&&wr_req_ready)begin
    w_cur_valid<=1;w_cur_addr<=wr_req_address;w_cur_beats<=wr_req_beats;
    w_sent<=0;w_buf<=0;w_nbytes<=0;w_last_seen<=0;w_pad<=0;
    wq_rd<=wq_rd+1;wq_cnt<=wq_cnt-1;
   end
   if(wr_req_valid&&!wr_req_ready)wr_wait<=wr_wait+1;
   if(wr_valid&&!wr_ready)wr_wait<=wr_wait+1;

   if(cval_hs)begin
    w_buf<=append_data;w_nbytes<=append_bytes;
    if(cval_last)w_last_seen<=1;
   end
   if(wr_hs)begin
    // PA-004: byte telemetry follows the actual WSTRB, including zero-strobe
    // padding on an aborted posted write.
    wr_bytes<=wr_bytes+pop16(wr_strobe);
    if(w_full_beat)begin w_buf<=w_buf>>128;w_nbytes<=w_nbytes-16;end
    else begin w_buf<=0;w_nbytes<=0;end
    w_sent<=w_sent+1;
   end
   if((abort||wr_err_sticky)&&w_cur_valid)w_pad<=1;
   // on DMA error/abort, drop segment commands that were never posted and
   // pad the accepted command with zero-strobe beats so the DMA beat count
   // is still satisfied before the error exit.
   if(wr_err_sticky&&wq_cnt!=0)begin wq_cnt<=0;wq_rd<=wq_wr;end

   if(w_cur_valid&&(sent_next==w_cur_beats)&&((nbytes_next==0)||w_pad))begin
    if(!w_last_seen&&!w_pad&&!wr_err_sticky)begin
     wr_err_sticky<=1;wr_code_r<=8'h32;wr_err_cnt<=wr_err_cnt+1;
    end
    w_cur_valid<=0;
   end
   if(w_cur_valid&&w_last_seen&&!w_pad&&(w_nbytes==0)&&(w_sent<w_cur_beats)&&!wr_err_sticky)begin
    wr_err_sticky<=1;wr_code_r<=8'h32;wr_err_cnt<=wr_err_cnt+1;
   end

   // posted-write credit accounting
   b_out<=b_out+(wr_req_valid&&wr_req_ready?1:0)-(wr_done?1:0);
   if(wr_error)begin wr_err_sticky<=1;wr_code_r<=8'h33;wr_err_cnt<=wr_err_cnt+1;end

   pend_q<=wq_cnt+w_cur_valid+b_out;
   cwr_pend<=wq_cnt+w_cur_valid+b_out+(wr_req_valid&&wr_req_ready?1:0)-(wr_done?1:0);
   if(cwr_idle&&(pend_q!=0)&&!wr_err_sticky)cwr_done_r<=1;
   if((wr_err_sticky||abort)&&cwr_idle&&!cwr_err_r)begin
    cwr_err_r<=1;rd_err_cnt<=rd_err_cnt+1;
   end
  end
 end

 // ---------------------------- counters / status ----------------------------
 assign read_blocks=rd_blocks_r;
 assign write_segments=wr_segs;
 assign read_bytes=rd_bytes_r;
 assign write_bytes=wr_bytes;
 assign error_count=rd_err_cnt+wr_err_cnt;
 assign read_wait_cycles=rd_wait;
 assign write_wait_cycles=wr_wait;
 assign ov_same_cycle=ov_same;
 assign rd_active_wr_active_cycles=rdwr_active;
 assign idle=(rstate==RIDLE)&&(lq_cnt==0)&&!c_hdr_v&&cwr_idle;
 assign drain_done=idle;
 assign rd_active=(rstate!=RIDLE);
 assign wr_active=w_cur_valid||(wq_cnt!=0)||(b_out!=0)||(wr_req_valid);
 assign dbg_rstate=rstate;
 assign dbg_wwait={7'd0,w_cur_valid};
endmodule
