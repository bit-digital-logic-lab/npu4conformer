`timescale 1ns/1ps
// Module-level storage ABI, NOT an AXI/DDR controller. Every transaction is one
// complete 32x32 block with identity, operation permissions and validity header.
// Autonomous M,N,K block iteration; four 16x16 physical sub-array runs per block.
module block_engine_banked_v020 #(parameter SLOTS=2,MAX_DIM=4096)(
 input wire clk,reset,start,
 input wire [31:0] cfg_a_base,cfg_b_base,cfg_c_base,cfg_epoch,
 input wire [15:0] cfg_m,cfg_n,cfg_k,cfg_layer,cfg_a_id,cfg_b_id,cfg_c_id,
 input wire [15:0] cfg_target_high,cfg_allowed_ops,cfg_requested_op,
 input wire [15:0] cfg_positions,input wire cfg_clip,
 output reg busy,done,fault,output reg [7:0] error_code,
 output reg [63:0] task_cycles,
 output reg [31:0] compute_cycles,read_blocks,write_blocks,cache_hits,cache_misses,
 output wire req_valid,input wire req_ready,output wire req_write,
 output wire [31:0] req_address,req_epoch,
 output wire [15:0] req_layer,req_matrix,req_block_row,req_block_col,req_allowed_ops,req_completed_ops,
 output wire [1:0] req_encoding,output wire req_block_valid,req_in_operation,
 // Read-response header. C absent/invalid means a new zero partial sum; an
 // existing valid C must be reloaded. A/B must exist and be valid.
 input wire header_valid,output wire header_ready,input wire header_exists,header_block_valid,header_in_operation,
 input wire [31:0] header_epoch,
 input wire [15:0] header_layer,header_matrix,header_block_row,header_block_col,header_allowed_ops,header_completed_ops,
 input wire [1:0] header_encoding,
 input wire data_valid,output wire data_ready,input wire [191:0] data_in,
 input wire [9:0] data_index,input wire data_last,
 output wire out_valid,input wire out_ready,output wire [47:0] out_data,
 output wire [9:0] out_index,output wire out_last,
 input wire write_ack,write_error,
 // Computation result carries the output block id, cache low address and tag.
 // full cache address is {target_high,target_low}; it is not the DDR address.
 output reg result_valid,input wire result_ready,
 output reg [31:0] result_cache_address,output wire [31:0] result_epoch,
 output reg [15:0] result_target_low,result_layer,result_matrix,result_block_row,result_block_col,result_op_tag,
 output wire [49151:0] result_data,
 output wire result_block_valid,result_in_operation,
 output wire [15:0] result_allowed_ops,result_completed_ops
);
 localparam IDLE=0,LOOKUP=1,EVICT_REQ=2,EVICT_DATA=3,EVICT_ACK=4,C_REQ=5,
  C_HEADER=6,C_DATA=7,A_REQ=8,A_HEADER=9,A_DATA=10,B_REQ=11,B_HEADER=12,
  B_DATA=13,CLEAR=14,RUN=15,COLLECT=16,ADVANCE=17,RESULT=18,
  FLUSH_FIND=19,FLUSH_REQ=20,FLUSH_DATA=21,FLUSH_ACK=22,FAIL=23,C_READ=24;
 reg [4:0] state;
 reg [10:0] beat;reg [6:0] run_cycle;reg [8:0] collect;
 reg [1:0] quadrant;reg [4:0] transfer_slot;
 wire [12287:0] sums;
 reg [31:0] abase,bbase,cbase,epoch;
 reg [15:0] m,n,k,layer,aid,bid,cid,target_high,allowed,positions;
 reg clip;reg [15:0] br,bc,bk;
 reg [15:0] nb_r,nb_c,nb_k;
 integer slot,rr,victim,flush_slot;
 reg valid_cache[0:SLOTS-1],dirty[0:SLOTS-1],in_operation[0:SLOTS-1];
 reg [31:0] tag_epoch[0:SLOTS-1],tag_base[0:SLOTS-1];
 reg [15:0] tag_layer[0:SLOTS-1],tag_matrix[0:SLOTS-1],tag_r[0:SLOTS-1],tag_c[0:SLOTS-1];
 reg [15:0] tag_rows[0:SLOTS-1],tag_cols[0:SLOTS-1],tag_allowed[0:SLOTS-1],tag_completed[0:SLOTS-1];
 reg fresh_c;
 reg [49151:0] result_payload;
 wire [191:0] c_values;reg [191:0] collected_values;
 reg c_overflow;reg signed [48:0] c_add,c_old;integer collect_ci;
 wire c_writeback=state==EVICT_DATA||state==FLUSH_DATA;
 wire c_bvalid;wire [47:0] c_bdata;
 wire c_loading=state==C_DATA&&data_valid&&data_index==beat[9:0]&&data_last==(beat==1020)&&beat[1:0]==0;
 wire c_reading=state==C_READ;
 wire c_collecting=state==COLLECT&&!c_overflow;
 wire c_avalid=c_loading||c_reading||c_collecting;
 wire [8:0] c_group=c_loading?(slot*256+(beat>>2)):(slot*256+(collect_ci>>2));
 wire [10:0] c_next_word=transfer_slot*1024+beat+(c_bvalid&&out_ready?1:0);
 wire c_brequest=c_writeback&&(!c_bvalid||(out_ready&&beat!=1023));
 c_cache_banked4 cache_ram(
  .clk(clk),.rst_n(!reset),.a_valid(c_avalid),.a_ready(),.a_group(c_group),
  .a_write_mask(c_loading||c_collecting?4'hf:4'h0),.a_write_data(c_loading?data_in:collected_values),
  .a_response_valid(),.a_response_ready(1'b1),.a_read_data(c_values),
  .b_valid(c_brequest),.b_ready(),.b_word(c_next_word),.b_response_valid(c_bvalid),
  .b_response_ready(c_writeback&&out_ready),.b_read_data(c_bdata));
 always @*begin
  collect_ci=(quadrant[1]*16+collect[7:4])*32+quadrant[0]*16+collect[3:0];
  c_overflow=0;collected_values=0;c_add=0;c_old=0;
  for(integer lane=0;lane<4;lane=lane+1)begin
   c_old=(fresh_c&&bk==0)?49'sd0:$signed({c_values[lane*48+47],c_values[lane*48+:48]});
   c_add=c_old+$signed({sums[(collect+lane)*48+47],sums[(collect+lane)*48+:48]});
   collected_values[lane*48+:48]=c_add[47:0];c_overflow=c_overflow||(c_add[48]!=c_add[47]);
  end
 end
 wire [255:0] bank_a;wire [111:0] bank_w;
 wire operand_beat_ok=data_valid&&data_index==beat[9:0]&&data_last==(beat==1020)&&beat[1:0]==0;
 wire operand_parity_ok=(^data_in[7:0])==0&&(^data_in[55:48])==0&&(^data_in[103:96])==0&&(^data_in[151:144])==0;
 operand_banks_v020 l1(.clk(clk),.a_write(!reset&&state==A_DATA&&operand_beat_ok),
  .b_write(!reset&&state==B_DATA&&operand_beat_ok&&operand_parity_ok),
  .write_index(beat[9:0]),.write_data(data_in),.run_cycle(run_cycle),.quadrant(quadrant),
  .a_values(bank_a),.w_values(bank_w));
 integer found,idx,ki,arow,bcol,ci;
 reg signed [48:0] updated_sum;
 reg [255:0] left_a;reg [111:0] top_w;reg [15:0] av,wv;
 wire [31:0] aaddr,baddr,caddr;wire [15:0] arm,acm,brm,bcm,crm,ccm;
 wire [39:0] aextent,bextent,cextent;wire amap,bmap,cmap;
 block_address_v020 ma(abase,m,k,br,bk,2'd0,aaddr,arm,acm,aextent,amap);
 block_address_v020 mb(bbase,k,n,bk,bc,2'd1,baddr,brm,bcm,bextent,bmap);
 block_address_v020 mc(cbase,m,n,br,bc,2'd2,caddr,crm,ccm,cextent,cmap);
 wire evict_state=state==EVICT_REQ||state==EVICT_DATA||state==EVICT_ACK;
 wire flush_state=state==FLUSH_REQ||state==FLUSH_DATA||state==FLUSH_ACK;
 wire sending=evict_state||flush_state;
 wire [15:0] tr=sending?tag_r[transfer_slot]:br;
 wire [15:0] tc=sending?tag_c[transfer_slot]:bc;
 wire [31:0] stored_addr=tag_base[transfer_slot]+(tag_r[transfer_slot]*(({16'd0,tag_cols[transfer_slot]}+31)>>5)+tag_c[transfer_slot])*6144;
 assign req_valid=state==EVICT_REQ||state==C_REQ||state==A_REQ||state==B_REQ||state==FLUSH_REQ;
 assign req_write=sending;
 assign req_address=sending?stored_addr:state==A_REQ?aaddr:state==B_REQ?baddr:caddr;
 assign req_epoch=sending?tag_epoch[transfer_slot]:epoch;
 assign req_layer=sending?tag_layer[transfer_slot]:layer;
 assign req_matrix=sending?tag_matrix[transfer_slot]:state==A_REQ?aid:state==B_REQ?bid:cid;
 assign req_block_row=state==B_REQ?bk:tr;
 assign req_block_col=state==A_REQ?bk:tc;
 assign req_encoding=state==A_REQ?0:state==B_REQ?1:2;
 assign req_allowed_ops=sending?tag_allowed[transfer_slot]:allowed;
 assign req_completed_ops=sending?tag_completed[transfer_slot]:0;
 assign req_block_valid=sending?valid_cache[transfer_slot]:1;
 assign req_in_operation=sending?in_operation[transfer_slot]:1;
 assign header_ready=state==C_HEADER||state==A_HEADER||state==B_HEADER;
 assign data_ready=state==C_DATA||state==A_DATA||state==B_DATA;
 assign out_valid=c_writeback&&c_bvalid;
 assign out_data=c_bdata;
 assign out_index=beat[9:0];assign out_last=beat==1023;
 assign result_block_valid=valid_cache[slot];
 assign result_epoch=epoch;
 assign result_in_operation=in_operation[slot];
 assign result_allowed_ops=tag_allowed[slot];assign result_completed_ops=tag_completed[slot];
 assign result_data=result_payload;
 array16_direct_v020 array(.clk(clk),.reset(reset),.flush(state!=RUN),.clear_sum(state==CLEAR),
  .a_left(left_a),.w_top(top_w),.av(av),.wv(wv),.positions(positions),.clip(clip),.sums(sums));
 always @* begin
  left_a=0;top_w=0;av=0;wv=0;
  for(integer r=0;r<16;r=r+1)begin
   ki=run_cycle-r;arow=quadrant[1]*16+r;
   if(state==RUN&&ki>=0&&ki<32&&(br*32+arow)<m&&(bk*32+ki)<k)begin
    left_a[r*16+:16]=bank_a[r*16+:16];av[r]=1;
   end
  end
  for(integer c=0;c<16;c=c+1)begin
   ki=run_cycle-c;bcol=quadrant[0]*16+c;
   if(state==RUN&&ki>=0&&ki<32&&(bc*32+bcol)<n&&(bk*32+ki)<k)begin
    top_w[c*7+:7]=bank_w[c*7+:7];wv[c]=1;
   end
  end
 end
 task fail(input [7:0] code);begin
  fault<=1;error_code<=code;busy<=0;done<=1;result_valid<=0;state<=FAIL;
  for(integer s=0;s<SLOTS;s=s+1)begin in_operation[s]<=0;valid_cache[s]<=0;dirty[s]<=0;end
 end endtask
 task install_current;begin
  valid_cache[slot]<=1;dirty[slot]<=0;in_operation[slot]<=1;
  tag_epoch[slot]<=epoch;tag_base[slot]<=cbase;tag_layer[slot]<=layer;
  tag_matrix[slot]<=cid;tag_r[slot]<=br;tag_c[slot]<=bc;
  tag_rows[slot]<=m;tag_cols[slot]<=n;tag_allowed[slot]<=allowed;tag_completed[slot]<=0;
 end endtask
 always @(posedge clk)begin
  if(reset)begin
   state<=IDLE;busy<=0;done<=0;fault<=0;error_code<=0;result_valid<=0;fresh_c<=0;
   task_cycles<=0;compute_cycles<=0;read_blocks<=0;write_blocks<=0;cache_hits<=0;cache_misses<=0;
   rr<=0;slot<=0;transfer_slot<=0;flush_slot<=0;beat<=0;run_cycle<=0;collect<=0;quadrant<=0;
   abase<=0;bbase<=0;cbase<=0;epoch<=0;m<=0;n<=0;k<=0;layer<=0;aid<=0;bid<=0;cid<=0;
   target_high<=0;allowed<=0;positions<=0;clip<=0;br<=0;bc<=0;bk<=0;nb_r<=0;nb_c<=0;nb_k<=0;
   result_cache_address<=0;result_target_low<=0;result_layer<=0;result_matrix<=0;result_block_row<=0;result_block_col<=0;result_op_tag<=0;
   for(integer s=0;s<SLOTS;s=s+1)begin
    valid_cache[s]<=0;dirty[s]<=0;in_operation[s]<=0;tag_epoch[s]<=0;tag_base[s]<=0;
    tag_layer[s]<=0;tag_matrix[s]<=0;tag_r[s]<=0;tag_c[s]<=0;tag_rows[s]<=0;tag_cols[s]<=0;tag_allowed[s]<=0;tag_completed[s]<=0;
   end
  end else begin
   if(busy)task_cycles<=task_cycles+1;
   if(state==RUN)compute_cycles<=compute_cycles+1;
   case(state)
   IDLE,FAIL: if(start)begin
    done<=0;fault<=0;error_code<=0;task_cycles<=0;compute_cycles<=0;read_blocks<=0;write_blocks<=0;cache_hits<=0;cache_misses<=0;
    if(cfg_m==0||cfg_n==0||cfg_k==0||cfg_m>MAX_DIM||cfg_n>MAX_DIM||cfg_k>MAX_DIM||MAX_DIM<1||MAX_DIM>4096||
       cfg_a_id==cfg_b_id||cfg_a_id==cfg_c_id||cfg_b_id==cfg_c_id||
       !(cfg_allowed_ops==1||cfg_allowed_ops==3)||cfg_requested_op!=1||
       cfg_positions[3:0]>12||cfg_positions[7:4]>12||cfg_positions[11:8]>12||cfg_positions[15:12]>12||
       cfg_a_base[5:0]!=0||cfg_b_base[5:0]!=0||cfg_c_base[5:0]!=0||SLOTS!=2)fail(1);
    else begin
     abase<=cfg_a_base;bbase<=cfg_b_base;cbase<=cfg_c_base;epoch<=cfg_epoch;
     m<=cfg_m;n<=cfg_n;k<=cfg_k;layer<=cfg_layer;aid<=cfg_a_id;bid<=cfg_b_id;cid<=cfg_c_id;
     target_high<=cfg_target_high;allowed<=cfg_allowed_ops;positions<=cfg_positions;clip<=cfg_clip;
     br<=0;bc<=0;bk<=0;nb_r<=(cfg_m+31)>>5;nb_c<=(cfg_n+31)>>5;nb_k<=(cfg_k+31)>>5;
     busy<=1;state<=LOOKUP;
    end
   end
   LOOKUP:begin
    if(!amap||!bmap||!cmap||{8'd0,abase}+aextent>40'h0100000000||
       {8'd0,bbase}+bextent>40'h0100000000||{8'd0,cbase}+cextent>40'h0100000000||
       !(({8'd0,abase}+aextent<=bbase)||({8'd0,bbase}+bextent<=abase))||
       !(({8'd0,abase}+aextent<=cbase)||({8'd0,cbase}+cextent<=abase))||
       !(({8'd0,bbase}+bextent<=cbase)||({8'd0,cbase}+cextent<=bbase)))fail(1);
    else begin
     found=-1;
     for(integer s=0;s<SLOTS;s=s+1)
      if(valid_cache[s]&&tag_epoch[s]==epoch&&tag_base[s]==cbase&&tag_layer[s]==layer&&tag_matrix[s]==cid&&
       tag_r[s]==br&&tag_c[s]==bc&&tag_rows[s]==m&&tag_cols[s]==n&&tag_allowed[s]==allowed)found=s;
     if(found>=0)begin if(bk==0)fresh_c<=0;slot<=found;in_operation[found]<=1;cache_hits<=cache_hits+1;state<=A_REQ;end
     else begin
      cache_misses<=cache_misses+1;slot<=rr;transfer_slot<=rr;rr<=rr==SLOTS-1?0:rr+1;
      if(valid_cache[rr]&&dirty[rr])state<=EVICT_REQ;else state<=C_REQ;
     end
    end
   end
   EVICT_REQ,FLUSH_REQ:if(req_ready)begin beat<=0;write_blocks<=write_blocks+1;state<=state==EVICT_REQ?EVICT_DATA:FLUSH_DATA;end
   EVICT_DATA,FLUSH_DATA:if(out_valid&&out_ready)begin if(beat==1023)state<=state==EVICT_DATA?EVICT_ACK:FLUSH_ACK;else beat<=beat+1;end
   EVICT_ACK,FLUSH_ACK:if(write_ack)begin
    if(write_error)fail(5);
    else begin dirty[transfer_slot]<=0;if(state==EVICT_ACK)begin valid_cache[transfer_slot]<=0;state<=C_REQ;end
     else begin flush_slot<=flush_slot+1;state<=FLUSH_FIND;end
    end
   end
   C_REQ,A_REQ,B_REQ:if(req_ready)begin read_blocks<=read_blocks+1;beat<=0;state<=state==C_REQ?C_HEADER:state==A_REQ?A_HEADER:B_HEADER;end
   C_HEADER,A_HEADER,B_HEADER:if(header_valid)begin
    if(header_epoch!=epoch||header_layer!=layer||header_matrix!=(state==A_HEADER?aid:state==B_HEADER?bid:cid)||
       header_block_row!=(state==B_HEADER?bk:br)||header_block_col!=(state==A_HEADER?bk:bc)||
       header_encoding!=(state==A_HEADER?0:state==B_HEADER?1:2)||header_allowed_ops!=allowed||
       (header_completed_ops&~header_allowed_ops)!=0||header_in_operation)fail(2);
    else if(state==C_HEADER)begin
     install_current;
     if(header_exists&&header_block_valid&&header_completed_ops[1])fail(3);
     else if(header_exists&&header_block_valid)begin fresh_c<=0;tag_completed[slot]<=header_completed_ops;state<=C_DATA;end
     else if(header_exists!=header_block_valid)fail(3);
     else begin fresh_c<=1;state<=A_REQ;end
    end else if(!header_exists||!header_block_valid)fail(3);
    else state<=state==A_HEADER?A_DATA:B_DATA;
   end
   C_DATA,A_DATA,B_DATA:if(data_valid)begin : receive_four
    reg parity_bad;
    parity_bad=0;
    for(integer lane=0;lane<4;lane=lane+1)parity_bad=parity_bad||((^data_in[lane*48+:8])!=0);
    if(data_index!=beat[9:0]||data_last!=(beat==1020)||beat[1:0]!=0)fail(4);
    else if(state==B_DATA&&parity_bad)fail(6);
    else begin
     for(integer lane=0;lane<4;lane=lane+1)begin
      // A writes are distributed across four K banks of the selected row.
      // B writes are distributed across physical column banks.
     end
     if(beat==1020)begin quadrant<=0;state<=state==C_DATA?A_REQ:state==A_DATA?B_REQ:CLEAR;end
     else beat<=beat+4;
    end
   end
   CLEAR:begin run_cycle<=0;state<=RUN;end
   RUN:if(run_cycle==65)begin collect<=0;state<=C_READ;end else run_cycle<=run_cycle+1;
   C_READ:state<=COLLECT;
   COLLECT:begin
    if(c_overflow)fail(8);
    else begin
     result_payload[collect_ci*48+:192]<=collected_values;
     if(collect==252)begin
      if(quadrant==3)begin dirty[slot]<=1;tag_completed[slot]<=tag_completed[slot]|1;state<=ADVANCE;end
      else begin quadrant<=quadrant+1;state<=CLEAR;end
     end else begin collect<=collect+4;state<=C_READ;end
    end
   end
   ADVANCE:begin
    if(bk+1<nb_k)begin bk<=bk+1;state<=LOOKUP;end
    else begin
     result_valid<=1;result_target_low<=slot*6144;result_cache_address<={target_high,16'd0}+slot*6144;
     result_layer<=layer;result_matrix<=cid;result_block_row<=br;result_block_col<=bc;result_op_tag<=1;
     in_operation[slot]<=0;state<=RESULT;
    end
   end
   RESULT:if(result_ready)begin
    result_valid<=0;bk<=0;
    if(bc+1<nb_c)begin bc<=bc+1;state<=LOOKUP;end
    else if(br+1<nb_r)begin bc<=0;br<=br+1;state<=LOOKUP;end
    else begin flush_slot<=0;state<=FLUSH_FIND;end
   end
   FLUSH_FIND:begin
    if(flush_slot==SLOTS)begin busy<=0;done<=1;state<=IDLE;end
    else if(valid_cache[flush_slot]&&dirty[flush_slot])begin transfer_slot<=flush_slot;state<=FLUSH_REQ;end
    else flush_slot<=flush_slot+1;
   end
   default:fail(7);
   endcase
  end
 end
endmodule
