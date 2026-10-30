`timescale 1ns/1ps
// V0.20 storage ABI to whole-block DMA. A request is validated against its
// matrix record, then transferred independently of the CPU. Read failures are
// presented only after DMA drain; write ACK follows the AXI write response.
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
 localparam IDLE=0,RREQ=1,RDMA=2,RCHECK=3,HEADER=4,RSCALAR=5,WSCALAR=6,WREQ=7,WDMA=8,WACK=9,RPRE=10;
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
 wire [63:0] expected_address={32'd0,source_base}+
        (({48'd0,req_block_row}*ncols)+req_block_col)*block_bytes;
 wire [63:0] expected_end=expected_address+block_bytes;
 wire request_bad=req_encoding==3||req_epoch!=cfg_epoch||req_layer!=cfg_layer||
      req_matrix!=(req_encoding==0?cfg_a_id:req_encoding==1?cfg_b_id:cfg_c_id)||
      req_allowed_ops!=cfg_allowed||!req_block_valid||
      req_block_row>=nrows||req_block_col>=ncols||expected_address!={32'd0,req_address}||
      !((expected_address>={32'd0,ARENA_BASE}&&expected_end<={32'd0,ARENA_END})||
       (!req_write&&req_encoding==1&&expected_address>={32'd0,PARAM_BASE}&&expected_end<={32'd0,param_end}&&param_end<=PARAM_END))||req_address[5:0]!=0||
      (req_write?(req_encoding!=2||req_in_operation||req_completed_ops!=1):(!req_in_operation||req_completed_ops!=0));
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
  end else begin
   if(state==RREQ||state==RDMA)read_wait_cycles<=read_wait_cycles+1;
   if(state==WREQ||state==WDMA)write_wait_cycles<=write_wait_cycles+1;
   if(state==RSCALAR||state==WSCALAR)scalar_cycles<=scalar_cycles+1;
   case(state)
    IDLE:if(req_valid)begin
     transactions<=transactions+1;
     address<=req_address;epoch<=req_epoch;layer<=req_layer;matrix<=req_matrix;
     brow<=req_block_row;bcol<=req_block_col;allowed<=req_allowed_ops;encoding<=req_encoding;
     completed<=req_encoding==2&&cfg_c_valid?cfg_c_completed:0;
     nbeats<=block_bytes>>4;word_index<=0;bad<=request_bad;dma_received<=0;
     exists<=req_encoding!=2||cfg_c_valid;
     pack<=0;pack_bytes<=0;pack_index<=0;
     if(req_write)begin write_blocks<=write_blocks+1;state<=WSCALAR;end
     else begin
      read_blocks<=read_blocks+1;
      if(request_bad||(req_encoding==2&&!cfg_c_valid))state<=HEADER;else state<=RREQ;
     end
    end
    RREQ:if(dma_request_ready)state<=RDMA;
    RDMA:begin
     if(dma_read_valid)begin
      if(dma_read_index!=dma_received||dma_read_index>=nbeats||dma_read_index>=384)bad<=1;
      // RAM write is on the independent synchronous bank port.
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
      else state<=WREQ;
     end else word_index<=word_index+1;
    end
    WREQ:if(dma_request_ready)begin state<=WDMA;write_loaded<=0;end
    WDMA:begin
     if(!write_loaded)write_loaded<=1;
     // Accepted beat simultaneously prefetches its successor; hold on stall.
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
  end
 end
endmodule
