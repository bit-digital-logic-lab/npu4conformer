`timescale 1ns/1ps
// Candidate: drop-in block_storage_dma_wide4 with a registered, multi-stage
// descriptor validator.  External ports and externally visible ordering are
// unchanged; req -> header/write_ack latency increases by VSTAGES cycles.
//
// Timing intent (logic-only, no synthesis claim):
//   * block descriptor address formation used to be one 64-bit
//     (row*ncols+col)*block_bytes + base + bound-check cone sampled directly
//     by bad_reg.  It is now split into:
//       V1 metadata / geometry comparisons (no wide multiply)
//       V2 row*ncols                              (16x32 -> 64)
//       V3 + column                               (64-bit add)
//       V4 * block_bytes                          (64x32 -> 64; bytes is 2/4/6 KiB)
//       V5 base + offset, end = base+offset+bytes (64-bit add)
//       V6 address equality + arena/param range + row/col bound (64-bit cmp)
//       V7 fold metadata and address verdict, set v_done
//     No multiplier output and no 64-bit bound comparison share a register
//     stage.  The block engine side (request mux / block_address_v020) is out
//     of this module; this register boundary also isolates it from bad_reg.
//   * Writes still stream data immediately after acceptance (same as the
//     original).  Validation runs in parallel with the 1024-word pack, so the
//     write data path is not stalled.  A bad descriptor suppresses the DMA
//     write exactly as before, and WACK is the sole error exit.
//   * Reads wait for the validator before issuing the DMA request.  AXI read
//     errors are still drained before HEADER is presented.
module block_storage_dma_wide4 #(
 parameter [31:0] ARENA_BASE=32'h03000000,ARENA_END=32'h08000000,PARAM_BASE=32'h10000000,PARAM_END=32'h40000000
)(
 input wire clk,rst_n,abort_scalar,
 input wire [31:0] param_end,
 input wire [31:0] cfg_a_base,cfg_b_base,cfg_c_base,cfg_epoch,
 input wire [15:0] cfg_m,cfg_n,cfg_k,cfg_layer,cfg_a_id,cfg_b_id,cfg_c_id,cfg_allowed,
 input wire cfg_c_valid,input wire [15:0] cfg_c_completed,
 input wire req_valid,output wire req_ready,input wire req_write,
 input wire [31:0] req_address,req_epoch,
 input wire [15:0] req_layer,req_matrix,req_block_row,req_block_col,req_allowed_ops,req_completed_ops,
 input wire [1:0] req_encoding,input wire req_block_valid,req_in_operation,
 output wire header_valid,input wire header_ready,
 output wire header_exists,header_block_valid,header_in_operation,
 output wire [31:0] header_epoch,
 output wire [15:0] header_layer,header_matrix,header_block_row,header_block_col,header_allowed_ops,header_completed_ops,
 output wire [1:0] header_encoding,
 output wire data_valid,input wire data_ready,output reg [191:0] data_in,
 output wire [9:0] data_index,output wire data_last,
 input wire out_valid,output wire out_ready,input wire [47:0] out_data,
 input wire [9:0] out_index,input wire out_last,
 output wire write_ack,write_error,
 output wire dma_request_valid,input wire dma_request_ready,output wire dma_request_write,
 output wire [31:0] dma_address,output wire [15:0] dma_beats,
 input wire dma_read_valid,output wire dma_read_ready,input wire [127:0] dma_read_data,input wire [15:0] dma_read_index,
 output wire dma_write_valid,input wire dma_write_ready,output wire [127:0] dma_write_data,
 output wire [15:0] dma_write_strobe,input wire [15:0] dma_write_index,
 input wire dma_done,dma_error,
 output wire idle,output reg [31:0] transactions,read_blocks,write_blocks,error_transactions,
 output reg [63:0] read_wait_cycles,write_wait_cycles,scalar_cycles
);
 localparam IDLE=0,VWAIT=1,RREQ=2,RDMA=3,RCHECK=4,HEADER=5,RPRE=6,RSCALAR=7,
  WSCALAR=8,WVAL=9,WREQ=10,WDMA=11,WACK=12;
 localparam [2:0] VS_LAST=3'd7;
 reg [3:0] state;
 (* ram_style="block" *) reg [127:0] bank_even[0:191];
 (* ram_style="block" *) reg [127:0] bank_odd[0:191];
 reg [127:0] even_q,odd_q;
 reg write_loaded;
 reg [31:0] address,epoch;
 reg [15:0] layer,matrix,brow,bcol,allowed,completed,nbeats;
 reg [1:0] encoding;
 reg exists,bad;
 reg [10:0] word_index;
 reg [15:0] dma_received;
 reg [255:0] pack;
 reg [4:0] pack_bytes;
 reg [8:0] pack_index;
 wire [255:0] packed_next=pack|({208'd0,out_data}<<(pack_bytes*8));
 wire [5:0] packed_bytes={1'b0,pack_bytes}+6;
 wire [31:0] block_bytes=req_encoding==0?2048:req_encoding==1?1024:6144;
 wire [31:0] ncols=req_encoding==0?(({16'd0,cfg_k}+31)>>5):(({16'd0,cfg_n}+31)>>5);
 wire [31:0] nrows=req_encoding==1?(({16'd0,cfg_k}+31)>>5):(({16'd0,cfg_m}+31)>>5);
 wire [31:0] source_base=req_encoding==0?cfg_a_base:req_encoding==1?cfg_b_base:cfg_c_base;

 // ---- descriptor snapshot: all inputs frozen at acceptance -----------------
 reg [31:0] r_req_address,r_epoch,r_a_base,r_b_base,r_c_base,r_cfg_epoch,r_param_end;
 reg [15:0] r_row,r_col,r_layer,r_matrix,r_allowed_req,r_completed_req;
 reg [15:0] r_m,r_n,r_k,r_cfg_layer,r_a_id,r_b_id,r_c_id,r_cfg_allowed,r_c_completed;
 reg [1:0] r_encoding;
 reg r_write,r_block_valid,r_in_operation,r_c_valid;

 // ---- registered validator pipeline ----------------------------------------
 reg v_active;
 reg [2:0] v_stage;
 reg v_done,v_bad_final;
 reg v_meta;
 reg [31:0] v_ncols,v_nrows,v_bytes,v_base;
 reg [63:0] v_rowprod,v_rc,v_off,v_expected,v_expected_end;
 reg v_addr_bad;

 assign idle=state==IDLE;
 assign req_ready=idle&&rst_n;
 assign header_valid=state==HEADER;
 assign header_exists=exists;
 assign header_block_valid=exists;
 // A bad read must fault, including C; reporting absent C would silently zero it.
 assign header_in_operation=bad;
 assign header_epoch=epoch;assign header_layer=layer;assign header_matrix=matrix;
 assign header_block_row=brow;assign header_block_col=bcol;
 assign header_allowed_ops=allowed;assign header_completed_ops=completed;
 assign header_encoding=encoding;
 assign data_valid=state==RSCALAR;
 assign data_index=word_index[9:0];assign data_last=word_index==1020;
 assign out_ready=state==WSCALAR;
 assign write_ack=state==WACK;assign write_error=bad;
 assign dma_request_valid=state==RREQ||state==WREQ;
 assign dma_request_write=state==WREQ;
 assign dma_address=address;assign dma_beats=nbeats;
 assign dma_read_ready=state==RDMA;
 assign dma_write_valid=state==WDMA&&write_loaded;
 assign dma_write_data=dma_write_index[0]?odd_q:even_q;
 assign dma_write_strobe=16'hffff;
 wire [12:0] first_byte=encoding==0?(word_index<<1):encoding==1?word_index:word_index*6;
 wire next_scalar=state==RSCALAR&&data_ready&&word_index!=1020;
 wire [10:0] fetch_word=word_index+(next_scalar?11'd4:11'd0);
 wire [12:0] fetch_byte=encoding==0?(fetch_word<<1):encoding==1?fetch_word:fetch_word*6;
 wire next_write=state==WDMA&&write_loaded&&dma_write_ready;
 wire [8:0] fetch_write=dma_write_index[8:0]+(next_write?9'd1:9'd0);
 wire [8:0] first_beat=(state==RPRE||next_scalar)?fetch_byte[12:4]:fetch_write;
 wire [7:0] even_address=first_beat[8:1]+first_beat[0];
 wire [7:0] odd_address=first_beat[8:1];
 wire ram_read=state==RPRE||next_scalar||(state==WDMA&&(!write_loaded||next_write));
 wire read_store=state==RDMA&&dma_read_valid&&dma_read_index<384;
 wire pack_store=state==WSCALAR&&out_valid&&packed_bytes>=16;
 wire ram_write=read_store||pack_store;
 wire [8:0] store_beat=read_store?dma_read_index[8:0]:pack_index;
 wire [127:0] store_data=read_store?dma_read_data:packed_next[127:0];
 // No reset on the memory/read registers: infer physical synchronous BRAM.
 always @(posedge clk)begin
  if(ram_write&&!store_beat[0])bank_even[store_beat[8:1]]<=store_data;
  if(ram_read&&even_address<192)even_q<=bank_even[even_address];
 end
 always @(posedge clk)begin
  if(ram_write&&store_beat[0])bank_odd[store_beat[8:1]]<=store_data;
  if(ram_read&&odd_address<192)odd_q<=bank_odd[odd_address];
 end
 wire [255:0] ordered_pair=first_byte[4]?{even_q,odd_q}:{odd_q,even_q};
 wire [255:0] aligned_pair=ordered_pair>>(first_byte[3:0]*8);
 always @*begin
  data_in=0;
  for(integer lane=0;lane<4;lane=lane+1)case(encoding)
   0:data_in[lane*48+:48]={32'd0,aligned_pair[lane*16+:16]};
   1:data_in[lane*48+:48]={40'd0,aligned_pair[lane*8+:8]};
   2:data_in[lane*48+:48]=aligned_pair[lane*48+:48];
  endcase
 end
 always @(posedge clk)begin
  if(!rst_n)begin
   state<=IDLE;address<=0;epoch<=0;layer<=0;matrix<=0;brow<=0;bcol<=0;
   allowed<=0;completed<=0;nbeats<=0;encoding<=0;exists<=0;bad<=0;
   word_index<=0;dma_received<=0;write_loaded<=0;pack<=0;pack_bytes<=0;pack_index<=0;
   transactions<=0;read_blocks<=0;write_blocks<=0;error_transactions<=0;
   read_wait_cycles<=0;write_wait_cycles<=0;scalar_cycles<=0;
   r_req_address<=0;r_epoch<=0;r_a_base<=0;r_b_base<=0;r_c_base<=0;r_cfg_epoch<=0;r_param_end<=0;
   r_row<=0;r_col<=0;r_layer<=0;r_matrix<=0;r_allowed_req<=0;r_completed_req<=0;
   r_m<=0;r_n<=0;r_k<=0;r_cfg_layer<=0;r_a_id<=0;r_b_id<=0;r_c_id<=0;r_cfg_allowed<=0;r_c_completed<=0;
   r_encoding<=0;r_write<=0;r_block_valid<=0;r_in_operation<=0;r_c_valid<=0;
   v_active<=0;v_stage<=0;v_done<=0;v_bad_final<=0;v_meta<=0;v_addr_bad<=0;
   v_ncols<=0;v_nrows<=0;v_bytes<=0;v_base<=0;v_rowprod<=0;v_rc<=0;v_off<=0;
   v_expected<=0;v_expected_end<=0;
  end else begin
   // Preserve the original counter meaning: only DMA-wait states, not the
   // new descriptor-check states (VWAIT/WVAL).
   if(state==RREQ||state==RDMA)read_wait_cycles<=read_wait_cycles+1;
   if(state==WREQ||state==WDMA)write_wait_cycles<=write_wait_cycles+1;
   if(state==RSCALAR||state==WSCALAR)scalar_cycles<=scalar_cycles+1;
   case(state)
    IDLE:if(req_valid)begin
     transactions<=transactions+1;
     address<=req_address;epoch<=req_epoch;layer<=req_layer;matrix<=req_matrix;
     brow<=req_block_row;bcol<=req_block_col;allowed<=req_allowed_ops;encoding<=req_encoding;
     completed<=req_encoding==2&&cfg_c_valid?cfg_c_completed:0;
     nbeats<=block_bytes>>4;word_index<=0;bad<=0;dma_received<=0;
     exists<=req_encoding!=2||cfg_c_valid;
     pack<=0;pack_bytes<=0;pack_index<=0;
     // Freeze the validator inputs.  Geometry is derived in V1, not here.
     r_req_address<=req_address;r_epoch<=req_epoch;r_layer<=req_layer;r_matrix<=req_matrix;
     r_row<=req_block_row;r_col<=req_block_col;r_allowed_req<=req_allowed_ops;
     r_completed_req<=req_completed_ops;r_encoding<=req_encoding;r_write<=req_write;
     r_block_valid<=req_block_valid;r_in_operation<=req_in_operation;
     r_a_base<=cfg_a_base;r_b_base<=cfg_b_base;r_c_base<=cfg_c_base;r_cfg_epoch<=cfg_epoch;
     r_param_end<=param_end;r_m<=cfg_m;r_n<=cfg_n;r_k<=cfg_k;r_cfg_layer<=cfg_layer;
     r_a_id<=cfg_a_id;r_b_id<=cfg_b_id;r_c_id<=cfg_c_id;r_cfg_allowed<=cfg_allowed;
     r_c_valid<=cfg_c_valid;r_c_completed<=cfg_c_completed;
     v_active<=1;v_stage<=3'd1;v_done<=0;v_bad_final<=0;v_meta<=0;v_addr_bad<=0;
     if(req_write)begin write_blocks<=write_blocks+1;state<=WSCALAR;end
     else begin read_blocks<=read_blocks+1;state<=VWAIT;end
    end
    VWAIT:if(v_done)begin
     if(v_bad_final)begin bad<=1;state<=HEADER;end
     else if(!exists)state<=HEADER;
     else state<=RREQ;
    end
    RREQ:if(dma_request_ready)state<=RDMA;
    RDMA:begin
     if(dma_read_valid)begin
      if(dma_read_index!=dma_received||dma_read_index>=nbeats||dma_read_index>=384)bad<=1;
      dma_received<=dma_received+1;
     end
     if(dma_done)begin if(dma_error)bad<=1;state<=RCHECK;end
    end
    RCHECK:begin
     if(dma_received!=nbeats)bad<=1;
     state<=HEADER;
    end
    HEADER:if(header_ready)begin
     if(bad)begin error_transactions<=error_transactions+1;state<=IDLE;end
     else if(!exists)state<=IDLE;else begin word_index<=0;state<=RPRE;end
    end
    RPRE:state<=RSCALAR;
    RSCALAR:if(data_ready)begin
     if(word_index==1020)state<=IDLE;else word_index<=word_index+4;
    end
    WSCALAR:if(out_valid)begin
     if(out_index!=word_index[9:0]||out_last!=(word_index==1023))bad<=1;
     if(packed_bytes>=16)begin
      pack_index<=pack_index+1;
      pack<=packed_next>>128;pack_bytes<=packed_bytes-16;
     end else begin pack<=packed_next;pack_bytes<=packed_bytes;end
     if(word_index==1023)begin
      if(bad||out_index!=word_index[9:0]||!out_last||packed_bytes!=16)begin bad<=1;state<=WACK;end
      else state<=WVAL;
     end else word_index<=word_index+1;
    end
    WVAL:begin
     // The pack stream already ran in parallel with validation.  Only the
     // DMA launch waits for the descriptor verdict.
     if(bad)begin bad<=1;state<=WACK;end
     else if(v_done)begin
      if(v_bad_final)begin bad<=1;state<=WACK;end
      else begin state<=WREQ;write_loaded<=0;end
     end
    end
    WREQ:if(dma_request_ready)begin state<=WDMA;write_loaded<=0;end
    WDMA:begin
     if(!write_loaded)write_loaded<=1;
     if(dma_done)begin if(dma_error)bad<=1;state<=WACK;write_loaded<=0;end
    end
    WACK:begin
     if(bad)error_transactions<=error_transactions+1;
     state<=IDLE;
    end
   endcase
   // The engine can reject a W parity/data beat before the 1024th word. AXI
   // was already completely drained before HEADER/RSCALAR, so safely discard
   // the remaining local block instead of deadlocking task retirement.
   if(abort_scalar&&(state==RSCALAR||state==RPRE||state==HEADER))begin
    state<=IDLE;error_transactions<=error_transactions+1;
   end
   // ---------------- registered descriptor validator ----------------------
   if(v_active)begin
    case(v_stage)
    3'd1:begin
     v_bytes<=r_encoding==0?32'd2048:r_encoding==1?32'd1024:32'd6144;
     v_ncols<=r_encoding==0?(({16'd0,r_k}+31)>>5):(({16'd0,r_n}+31)>>5);
     v_nrows<=r_encoding==1?(({16'd0,r_k}+31)>>5):(({16'd0,r_m}+31)>>5);
     v_base<=r_encoding==0?r_a_base:r_encoding==1?r_b_base:r_c_base;
     v_meta<=(r_encoding==2'd3)||(r_epoch!=r_cfg_epoch)||(r_layer!=r_cfg_layer)||
       (r_matrix!=(r_encoding==0?r_a_id:r_encoding==1?r_b_id:r_c_id))||
       (r_allowed_req!=r_cfg_allowed)||(!r_block_valid)||(r_req_address[5:0]!=0)||
       (r_write?(r_encoding!=2'd2||r_in_operation||r_completed_req!=16'd1):
                (!r_in_operation||r_completed_req!=16'd0));
     v_stage<=3'd2;
    end
    3'd2:begin
     v_rowprod<={48'd0,r_row}*{32'd0,v_ncols};
     v_stage<=3'd3;
    end
    3'd3:begin
     v_rc<=v_rowprod+{48'd0,r_col};
     v_stage<=3'd4;
    end
    3'd4:begin
     v_off<=v_rc*{32'd0,v_bytes};
     v_stage<=3'd5;
    end
    3'd5:begin
     v_expected<={32'd0,v_base}+v_off;
     v_expected_end<={32'd0,v_base}+v_off+{32'd0,v_bytes};
     v_stage<=3'd6;
    end
    3'd6:begin
     v_addr_bad<=(v_expected!={32'd0,r_req_address})||
       !(((v_expected>={32'd0,ARENA_BASE})&&(v_expected_end<={32'd0,ARENA_END}))||
         (!r_write&&r_encoding==2'd1&&v_expected>={32'd0,PARAM_BASE}&&
          v_expected_end<={32'd0,r_param_end}&&r_param_end<=PARAM_END))||
       (r_row>=v_nrows)||(r_col>=v_ncols);
     v_stage<=3'd7;
    end
    VS_LAST:begin
     v_bad_final<=v_meta|v_addr_bad;
     v_done<=1;v_active<=0;v_stage<=3'd0;
    end
    default:begin v_active<=0;v_stage<=3'd0;end
    endcase
   end
  end
 end
endmodule
