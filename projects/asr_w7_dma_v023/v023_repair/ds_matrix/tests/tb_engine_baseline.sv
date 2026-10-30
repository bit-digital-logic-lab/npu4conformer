`timescale 1ns/1ps
// Baseline serial RTL: original block_engine_banked_v020 + original
// block_storage_dma_wide4.  Same BFM, same init.hex, same stalls as the
// candidate test.  The original engine source is used read-only from work/rtl.
module tb_engine_baseline;
 parameter [31:0] BASE=32'h03000000;
 parameter [31:0] A_BASE=32'h03000000,B_BASE=32'h03002000,C_BASE=32'h03003000;
 parameter integer M=32,N=32,K=32;
 parameter integer MEM_WORDS=1536;
 parameter integer RD_LAT=5,RD_GAP=12,WR_GAP=12,B_DELAY=8;
 parameter integer CVALID=0;
 parameter integer NBLK=(M/32)*(N/32);

 reg clk=0,rst_n=0;
 always #5 clk=~clk;
 reg [31:0] cfg_epoch=32'd3;
 reg [15:0] cfg_m=M,cfg_n=N,cfg_k=K,cfg_layer=16'd5,cfg_a_id=16'd1,cfg_b_id=16'd2,cfg_c_id=16'd3;
 reg [15:0] cfg_target_high=16'd0,cfg_allowed=16'd1,cfg_requested=16'd1;
 reg [15:0] cfg_positions=16'h3210,cfg_clip=1'b1,cfg_c_completed=16'd0;
 reg cfg_c_valid=0,start=0;
 wire busy,done,fault;wire [7:0] error_code;wire [63:0] task_cycles;
 wire [31:0] compute_cycles,read_blocks,write_blocks,cache_hits,cache_misses;
 wire [31:0] o_req_valid;wire o_req_ready,o_req_write;wire [31:0] o_req_address,o_req_epoch;
 wire [15:0] o_req_layer,o_req_matrix,o_req_row,o_req_col,o_req_allowed,o_req_completed;
 wire [1:0] o_req_enc;wire o_req_bvalid,o_req_inop;
 wire o_hdr_valid,o_hdr_ready,o_hdr_exists,o_hdr_bvalid,o_hdr_inop;
 wire [31:0] o_hdr_epoch;wire [15:0] o_hdr_layer,o_hdr_matrix,o_hdr_row,o_hdr_col,o_hdr_allowed,o_hdr_completed;
 wire [1:0] o_hdr_enc;
 wire o_data_valid,o_data_ready;wire [191:0] o_data_in;wire [9:0] o_data_index;wire o_data_last;
 wire o_out_valid,o_out_ready;wire [47:0] o_out_data;wire [9:0] o_out_index;wire o_out_last;
 wire o_write_ack,o_write_error;
 wire result_valid;reg result_ready=1;wire [31:0] result_cache_address,result_epoch;
 wire [15:0] result_target_low,result_layer,result_matrix,result_block_row,result_block_col,result_op_tag;
 wire [49151:0] result_data;wire result_block_valid,result_in_operation;
 wire [15:0] result_allowed_ops,result_completed_ops;
 wire [31:0] st_rblk,st_wblk,st_err;wire [63:0] st_rdwait,st_wrwait,st_scalar;
 // DMA
 wire rd_req_valid,rd_req_ready;wire [31:0] rd_req_addr;wire [15:0] rd_req_beats;
 wire rd_valid,rd_ready;wire [127:0] rd_data;wire [15:0] rd_index;wire rd_done,rd_error;
 wire wr_req_valid,wr_req_ready;wire [31:0] wr_req_addr;wire [15:0] wr_req_beats;
 wire wr_valid,wr_ready;wire [127:0] wr_data;wire [15:0] wr_strobe;wire wr_done,wr_error;
 reg init_valid=0;reg [31:0] init_addr=0;reg [127:0] init_data=0;
 wire [31:0] chk_addr=32'h03003000;wire [127:0] chk_data;
 wire [31:0] bfm_rdcmds,bfm_wrcmds,bfm_rdbeats,bfm_wrbeats,bfm_shared,max_b,rd_stall,wr_stall;
 reg [127:0] initmem[0:MEM_WORDS-1];reg [47:0] expv[0:NBLK*1024-1];
 integer errs=0,i,j,blk,rv_count=0;reg [1023:0] initfile,expfile;

 block_engine_banked_v020 #(.SLOTS(2)) eng(
  .clk(clk),.reset(!rst_n),.start(start),
  .cfg_a_base(A_BASE),.cfg_b_base(B_BASE),.cfg_c_base(C_BASE),.cfg_epoch(cfg_epoch),
  .cfg_m(cfg_m),.cfg_n(cfg_n),.cfg_k(cfg_k),.cfg_layer(cfg_layer),.cfg_a_id(cfg_a_id),
  .cfg_b_id(cfg_b_id),.cfg_c_id(cfg_c_id),.cfg_target_high(cfg_target_high),
  .cfg_allowed_ops(cfg_allowed),.cfg_requested_op(cfg_requested),.cfg_positions(cfg_positions),
  .cfg_clip(cfg_clip),.busy(busy),.done(done),.fault(fault),.error_code(error_code),
  .task_cycles(task_cycles),.compute_cycles(compute_cycles),.read_blocks(read_blocks),
  .write_blocks(write_blocks),.cache_hits(cache_hits),.cache_misses(cache_misses),
  .req_valid(o_req_valid),.req_ready(o_req_ready),.req_write(o_req_write),.req_address(o_req_address),
  .req_epoch(o_req_epoch),.req_layer(o_req_layer),.req_matrix(o_req_matrix),.req_block_row(o_req_row),
  .req_block_col(o_req_col),.req_allowed_ops(o_req_allowed),.req_completed_ops(o_req_completed),
  .req_encoding(o_req_enc),.req_block_valid(o_req_bvalid),.req_in_operation(o_req_inop),
  .header_valid(o_hdr_valid),.header_ready(o_hdr_ready),.header_exists(o_hdr_exists),
  .header_block_valid(o_hdr_bvalid),.header_in_operation(o_hdr_inop),.header_epoch(o_hdr_epoch),
  .header_layer(o_hdr_layer),.header_matrix(o_hdr_matrix),.header_block_row(o_hdr_row),
  .header_block_col(o_hdr_col),.header_allowed_ops(o_hdr_allowed),.header_completed_ops(o_hdr_completed),
  .header_encoding(o_hdr_enc),.data_valid(o_data_valid),.data_ready(o_data_ready),.data_in(o_data_in),
  .data_index(o_data_index),.data_last(o_data_last),.out_valid(o_out_valid),.out_ready(o_out_ready),
  .out_data(o_out_data),.out_index(o_out_index),.out_last(o_out_last),.write_ack(o_write_ack),
  .write_error(o_write_error),.result_valid(result_valid),.result_ready(result_ready),
  .result_cache_address(result_cache_address),.result_epoch(result_epoch),.result_target_low(result_target_low),
  .result_layer(result_layer),.result_matrix(result_matrix),.result_block_row(result_block_row),
  .result_block_col(result_block_col),.result_op_tag(result_op_tag),.result_data(result_data),
  .result_block_valid(result_block_valid),.result_in_operation(result_in_operation),
  .result_allowed_ops(result_allowed_ops),.result_completed_ops(result_completed_ops));

 block_storage_dma_wide4 #(.ARENA_BASE(32'h03000000),.ARENA_END(32'h08000000)) sto(
  .clk(clk),.rst_n(rst_n),.abort_scalar(fault),.param_end(32'h40000000),
  .cfg_a_base(A_BASE),.cfg_b_base(B_BASE),.cfg_c_base(C_BASE),.cfg_epoch(cfg_epoch),
  .cfg_m(cfg_m),.cfg_n(cfg_n),.cfg_k(cfg_k),.cfg_layer(cfg_layer),.cfg_a_id(cfg_a_id),
  .cfg_b_id(cfg_b_id),.cfg_c_id(cfg_c_id),.cfg_allowed(cfg_allowed),.cfg_c_valid(cfg_c_valid),
  .cfg_c_completed(cfg_c_completed),
  .req_valid(o_req_valid),.req_ready(o_req_ready),.req_write(o_req_write),.req_address(o_req_address),
  .req_epoch(o_req_epoch),.req_layer(o_req_layer),.req_matrix(o_req_matrix),.req_block_row(o_req_row),
  .req_block_col(o_req_col),.req_allowed_ops(o_req_allowed),.req_completed_ops(o_req_completed),
  .req_encoding(o_req_enc),.req_block_valid(o_req_bvalid),.req_in_operation(o_req_inop),
  .header_valid(o_hdr_valid),.header_ready(o_hdr_ready),.header_exists(o_hdr_exists),
  .header_block_valid(o_hdr_bvalid),.header_in_operation(o_hdr_inop),.header_epoch(o_hdr_epoch),
  .header_layer(o_hdr_layer),.header_matrix(o_hdr_matrix),.header_block_row(o_hdr_row),
  .header_block_col(o_hdr_col),.header_allowed_ops(o_hdr_allowed),.header_completed_ops(o_hdr_completed),
  .header_encoding(o_hdr_enc),.data_valid(o_data_valid),.data_ready(o_data_ready),.data_in(o_data_in),
  .data_index(o_data_index),.data_last(o_data_last),.out_valid(o_out_valid),.out_ready(o_out_ready),
  .out_data(o_out_data),.out_index(o_out_index),.out_last(o_out_last),.write_ack(o_write_ack),
  .write_error(o_write_error),
  .dma_request_valid(dma_request_valid),.dma_request_ready(dma_request_ready),.dma_request_write(dma_request_write),
  .dma_address(dma_address),.dma_beats(dma_beats),
  .dma_read_valid(rd_valid),.dma_read_ready(rd_ready),.dma_read_data(rd_data),.dma_read_index(rd_index),
  .dma_write_valid(wr_valid),.dma_write_ready(wr_ready),.dma_write_data(wr_data),.dma_write_strobe(wr_strobe),
  .dma_write_index(wr_index),.dma_done(dma_done),.dma_error(dma_error),.idle(),.transactions(),
  .read_blocks(st_rblk),.write_blocks(st_wblk),.error_transactions(st_err),
  .read_wait_cycles(st_rdwait),.write_wait_cycles(st_wrwait),.scalar_cycles(st_scalar));
 wire dma_request_valid,dma_request_ready,dma_request_write;wire [31:0] dma_address;wire [15:0] dma_beats,wr_index;
 wire dma_done,dma_error;
 assign rd_req_valid=dma_request_valid&&!dma_request_write;
 assign wr_req_valid=dma_request_valid&&dma_request_write;
 assign rd_req_addr=dma_address;assign rd_req_beats=dma_beats;
 assign wr_req_addr=dma_address;assign wr_req_beats=dma_beats;
 assign dma_request_ready=dma_request_write?wr_req_ready:rd_req_ready;
 reg dma_dir=0;
 always @(posedge clk)if(rst_n&&dma_request_valid&&dma_request_ready)dma_dir<=dma_request_write;
 assign dma_done=dma_dir?wr_done:rd_done;
 assign dma_error=dma_dir?wr_error:rd_error;

 wire inj_rd=0,inj_wr=0;
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

 always @(posedge clk)if(rst_n&&result_valid&&result_ready)begin
  blk=result_block_row*(N/32)+result_block_col;
  for(i=0;i<1024;i=i+1)
   if(result_data[i*48+:48]!==expv[blk*1024+i])begin
    if(errs<6)$display("FAIL base result blk=%0d i=%0d got=%012h exp=%012h",blk,i,result_data[i*48+:48],expv[blk*1024+i]);
    errs=errs+1;
   end
  rv_count=rv_count+1;
 end

 initial begin
  errs=0;rv_count=0;cfg_c_valid=CVALID;
  if(!$value$plusargs("init=%s",initfile))initfile="fixtures/eng_k1/init.hex";
  if(!$value$plusargs("exp=%s",expfile))expfile="fixtures/eng_k1/exp_c.txt";
  $readmemh(initfile,initmem);$readmemh(expfile,expv);
  rst_n=0;repeat(6)@(negedge clk);rst_n=1;repeat(4)@(negedge clk);
  for(i=0;i<MEM_WORDS;i=i+1)init_word(BASE+i*16,initmem[i]);
  @(negedge clk);start=1;@(negedge clk);start=0;
  wait(done);
  repeat(5)@(negedge clk);
  $display("BASE done fault=%b code=%h cycles=%0d compute=%0d rdblk=%0d wrblk=%0d hits=%0d miss=%0d res=%0d st_rdwait=%0d st_wrwait=%0d st_scalar=%0d",
    fault,error_code,task_cycles,compute_cycles,read_blocks,write_blocks,cache_hits,cache_misses,rv_count,
    st_rdwait,st_wrwait,st_scalar);
  if(fault)begin $display("BASE fault code=%h",error_code);$fatal(1,"fault");end
  if(rv_count!=NBLK)begin $display("FAIL result count %0d",rv_count);errs=errs+1;end
  if(errs!=0)$fatal(1,"baseline errs=%0d",errs);
  $display("PASS tb_engine_baseline cycles=%0d compute=%0d",task_cycles,compute_cycles);
  $finish;
 end
 initial begin #5000000;$fatal(1,"timeout");end
endmodule
