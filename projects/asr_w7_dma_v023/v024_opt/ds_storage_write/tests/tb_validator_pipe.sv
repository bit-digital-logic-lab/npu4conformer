`timescale 1ns/1ps
// Directed test for the registered ld address validator.
//  * 4 legal A/W commands are accepted on consecutive cycles (1 cmd/cycle)
//  * the wide row*ncols*bytes + base + compare cone is spread over V1..V4
//  * boundary/identity/alignment/wrap rejects set the stage fault
// The read engine is held at rd_req_ready=0 so only the validator/queue is
// exercised; no DMA data is needed.
module tb_validator_pipe;
 parameter [31:0] C_BASE=32'h03000000;
 reg clk=0,rst_n=0;always #5 clk=~clk;
 reg [31:0] cfg_a_base=32'h03000000,cfg_b_base=32'h03004000,cfg_c_base=C_BASE,cfg_epoch=32'd3;
 reg [15:0] cfg_m=32,cfg_n=32,cfg_k=32,cfg_layer=16'd5,cfg_a_id=16'd1,cfg_b_id=16'd2,cfg_c_id=16'd3;
 reg [15:0] cfg_allowed=16'd1,cfg_c_completed=16'd0;reg cfg_c_valid=0;
 reg ld_valid=0;wire ld_ready;reg [1:0] ld_kind=0;reg ld_stage=0;reg [31:0] ld_addr=0,ld_epoch=0;
 reg [15:0] ld_layer=0,ld_matrix=0,ld_row=0,ld_col=0,ld_ops=0,ld_comp=0;reg [1:0] ld_enc=0;
 reg ld_bvalid=0,ld_inop=0;
 wire [1:0] sa_r,sw_r,sa_f,sw_f,sa_bv,sw_bv,sa_io,sw_io;
 wire [63:0] sa_e,sw_e;wire [31:0] sa_l,sw_l,sa_m,sw_m,sa_row,sw_row,sa_col,sw_col,sa_a,sw_a,sa_c,sw_c;
 wire [3:0] sa_enc,sw_enc;reg [1:0] rel=0;
 reg rd_stage=0,rd_rh=0,rd_ch=0;reg [79:0] a_k=0,w_k=0;wire [255:0] a_values;wire [111:0] w_values;
 wire chv,chx,chbv,chio,cher;wire [7:0] chc;wire [63:0] che;wire [31:0] chl,chm,chr,chcol,cha,chcomp;
 wire [3:0] chenc;reg chready=1;
 wire clv,cll,cld,cldr;wire [127:0] cld_data;wire [15:0] cld_idx;wire [7:0] cldc;reg clready=1;
 reg cseg_valid=0;wire cseg_ready;reg [31:0] cseg_addr=0,cseg_epoch=0;
 reg [15:0] cseg_layer=0,cseg_matrix=0,cseg_row=0,cseg_col=0,cseg_beats=0;
 reg cval_valid=0;wire cval_ready;reg [191:0] cval_data=0;reg cval_last=0;
 wire [7:0] cwr_pending;wire cwr_idle,cwr_done,cwr_error;wire [7:0] cwr_code;
 wire rd_req_valid;reg rd_req_ready=0;wire [31:0] rd_req_addr;wire [15:0] rd_req_beats;
 wire rd_valid;wire rd_ready;wire [127:0] rd_data;wire [15:0] rd_index;wire rd_done,rd_error;
 wire wr_req_valid;wire wr_req_ready;wire [31:0] wr_req_addr;wire [15:0] wr_req_beats;
 wire wr_valid;wire wr_ready;wire [127:0] wr_data;wire [15:0] wr_strobe;wire wr_done,wr_error;
 wire idle,drain_done;wire [31:0] read_blocks,write_segs,read_bytes,write_bytes,error_count;
 wire [63:0] rd_wait,wr_wait;wire [31:0] ov_same,rdwractive;wire rd_active,wr_active;
 wire [1:0] dbg_rstate,dbg_wwait;
 wire [31:0] t_cseg,t_wrcmd,t_wrbeat,t_coal,t_gen,t_flush,t_cvalstall,t_csegstall;wire [7:0] t_maxb;

 block_storage_stream_v3 #(.ARENA_BASE(32'h03000000),.ARENA_END(32'h08000000),
   .LD_Q(8),.WR_OUT(8)) dut(
  .clk(clk),.rst_n(rst_n),.abort(1'b0),.param_end(32'h40000000),
  .cfg_a_base(cfg_a_base),.cfg_b_base(cfg_b_base),.cfg_c_base(cfg_c_base),.cfg_epoch(cfg_epoch),
  .cfg_m(cfg_m),.cfg_n(cfg_n),.cfg_k(cfg_k),.cfg_layer(cfg_layer),.cfg_a_id(cfg_a_id),
  .cfg_b_id(cfg_b_id),.cfg_c_id(cfg_c_id),.cfg_allowed(cfg_allowed),.cfg_c_valid(cfg_c_valid),
  .cfg_c_completed(cfg_c_completed),
  .ld_valid(ld_valid),.ld_ready(ld_ready),.ld_kind(ld_kind),.ld_stage(ld_stage),
  .ld_address(ld_addr),.ld_epoch(ld_epoch),.ld_layer(ld_layer),.ld_matrix(ld_matrix),
  .ld_block_row(ld_row),.ld_block_col(ld_col),.ld_allowed_ops(ld_ops),.ld_completed_ops(ld_comp),
  .ld_encoding(ld_enc),.ld_block_valid(ld_bvalid),.ld_in_operation(ld_inop),
  .stage_a_ready(sa_r),.stage_w_ready(sw_r),.stage_a_fault(sa_f),.stage_w_fault(sw_f),
  .stage_a_bvalid(sa_bv),.stage_w_bvalid(sw_bv),.stage_a_inop(sa_io),.stage_w_inop(sw_io),
  .stage_a_epoch(sa_e),.stage_w_epoch(sw_e),.stage_a_layer(sa_l),.stage_w_layer(sw_l),
  .stage_a_matrix(sa_m),.stage_w_matrix(sw_m),.stage_a_row(sa_row),.stage_w_row(sw_row),
  .stage_a_col(sa_col),.stage_w_col(sw_col),.stage_a_allowed(sa_a),.stage_w_allowed(sw_a),
  .stage_a_completed(sa_c),.stage_w_completed(sw_c),.stage_a_encoding(sa_enc),.stage_w_encoding(sw_enc),
  .stage_release(rel),.rd_stage(rd_stage),.rd_row_half(rd_rh),.rd_col_half(rd_ch),
  .a_k(a_k),.w_k(w_k),.a_values(a_values),.w_values(w_values),
  .c_hdr_valid(chv),.c_hdr_ready(chready),.c_hdr_exists(chx),.c_hdr_bvalid(chbv),
  .c_hdr_inop(chio),.c_hdr_error(cher),.c_hdr_code(chc),.c_hdr_epoch(che),.c_hdr_layer(chl),
  .c_hdr_matrix(chm),.c_hdr_row(chr),.c_hdr_col(chcol),.c_hdr_allowed(cha),
  .c_hdr_completed(chcomp),.c_hdr_encoding(chenc),
  .c_ld_valid(clv),.c_ld_ready(clready),.c_ld_data(cld_data),.c_ld_index(cld_idx),
  .c_ld_last(cll),.c_ld_done(cld),.c_ld_error(cldr),.c_ld_code(cldc),
  .cseg_valid(cseg_valid),.cseg_ready(cseg_ready),.cseg_address(cseg_addr),
  .cseg_epoch(cseg_epoch),.cseg_layer(cseg_layer),.cseg_matrix(cseg_matrix),
  .cseg_row(cseg_row),.cseg_col(cseg_col),.cseg_beats(cseg_beats),
  .cval_valid(cval_valid),.cval_ready(cval_ready),.cval_data(cval_data),.cval_last(cval_last),
  .cwr_pending(cwr_pending),.cwr_idle(cwr_idle),.cwr_done(cwr_done),.cwr_error(cwr_error),.cwr_code(cwr_code),
  .rd_req_valid(rd_req_valid),.rd_req_ready(rd_req_ready),.rd_req_address(rd_req_addr),
  .rd_req_beats(rd_req_beats),.rd_valid(rd_valid),.rd_ready(rd_ready),.rd_data(rd_data),
  .rd_index(rd_index),.rd_done(rd_done),.rd_error(rd_error),
  .wr_req_valid(wr_req_valid),.wr_req_ready(wr_req_ready),.wr_req_address(wr_req_addr),
  .wr_req_beats(wr_req_beats),.wr_valid(wr_valid),.wr_ready(wr_ready),.wr_data(wr_data),
  .wr_strobe(wr_strobe),.wr_done(wr_done),.wr_error(wr_error),
  .idle(idle),.drain_done(drain_done),.read_blocks(read_blocks),.write_segments(write_segs),
  .read_bytes(read_bytes),.write_bytes(write_bytes),.error_count(error_count),
  .read_wait_cycles(rd_wait),.write_wait_cycles(wr_wait),.ov_same_cycle(ov_same),
  .rd_active_wr_active_cycles(rdwractive),.rd_active(rd_active),.wr_active(wr_active),
  .dbg_rstate(dbg_rstate),.dbg_wwait(dbg_wwait),
  .cseg_cmds(t_cseg),.wr_cmds_posted(t_wrcmd),.wr_beats_sent(t_wrbeat),
  .coalesced_segs(t_coal),.generic_segs(t_gen),.flush_reqs(t_flush),
  .max_b_credit(t_maxb),.cval_stall_cycles(t_cvalstall),.cseg_stall_cycles(t_csegstall));

 integer errs=0,i,acc;
 task do_reset;begin
  rst_n=0;rel=0;repeat(4)@(negedge clk);rst_n=1;repeat(2)@(negedge clk);
 end endtask
 task send_ld(input [1:0] kind,input stage,input [31:0] addr,input [15:0] row,col,
              input [31:0] ep,input [15:0] ly,mat,input [1:0] enc);
  begin
   ld_kind=kind;ld_stage=stage;ld_addr=addr;ld_epoch=ep;ld_layer=ly;ld_matrix=mat;
   ld_row=row;ld_col=col;ld_ops=cfg_allowed;ld_comp=0;ld_enc=enc;ld_bvalid=1;ld_inop=1;
   ld_valid=1;
   while(!ld_ready)@(negedge clk);
   @(negedge clk);ld_valid=0;
  end
 endtask
 task drive_one(input [1:0] kind,input stage,input [31:0] addr,input [15:0] row,col,
              input [31:0] ep,input [15:0] ly,mat,input [1:0] enc);
  begin
   ld_kind=kind;ld_stage=stage;ld_addr=addr;ld_epoch=ep;ld_layer=ly;ld_matrix=mat;
   ld_row=row;ld_col=col;ld_ops=cfg_allowed;ld_comp=0;ld_enc=enc;ld_bvalid=1;ld_inop=1;
   ld_valid=1;
   #1;
   if(!ld_ready)begin $display("FAIL ld_ready low kind=%0d stage=%0d free=%b space=%b lq=%0d v0=%b h00=%b h01=%b h10=%b h11=%b cbusy=%b",kind,stage,dut.stage_free,dut.lq_accept_ok,dut.lq_cnt,dut.v0_valid,dut.stg_have[0][0],dut.stg_have[0][1],dut.stg_have[1][0],dut.stg_have[1][1],dut.c_cmd_busy);errs=errs+1;end
   @(negedge clk);
  end
 endtask
 initial begin
  errs=0;
  do_reset;
  // four legal commands on consecutive cycles (A0,W0,A1,W1)
  drive_one(0,0,32'h03000000,0,0,3,5,1,0);
  drive_one(1,0,32'h03004000,0,0,3,5,2,1);
  drive_one(0,1,32'h03000000,0,0,3,5,1,0);
  drive_one(1,1,32'h03004000,0,0,3,5,2,1);
  ld_valid=0;
  repeat(6)@(negedge clk);
  if(!(sa_bv[0]&&sa_bv[1]&&sw_bv[0]&&sw_bv[1]))begin
   $display("FAIL bvalid %b%b%b%b",sa_bv[0],sa_bv[1],sw_bv[0],sw_bv[1]);errs=errs+1;
  end
  if(|sa_f|||sw_f)begin $display("FAIL unexpected fault %b%b",sa_f,sw_f);errs=errs+1;end
  $display("INFO legal bvalid=%b%b%b%b lq=%0d",sa_bv[0],sa_bv[1],sw_bv[0],sw_bv[1],dut.lq_cnt);
  rel=2'b11;@(negedge clk);rel=0;repeat(2)@(negedge clk);

  // wrong address
  do_reset; send_ld(0,0,32'h03000100,0,0,3,5,1,0);repeat(6)@(negedge clk);
  if(!sa_f[0])begin $display("FAIL bad address not rejected");errs=errs+1;end
  // unaligned address (32 B)
  do_reset; send_ld(0,0,32'h03000020,0,0,3,5,1,0);repeat(6)@(negedge clk);
  if(!sa_f[0])begin $display("FAIL unaligned not rejected");errs=errs+1;end
  // row out of range
  do_reset; send_ld(0,0,32'h03000000,1,0,3,5,1,0);repeat(6)@(negedge clk);
  if(!sa_f[0])begin $display("FAIL row range not rejected");errs=errs+1;end
  // bad epoch
  do_reset; send_ld(0,0,32'h03000000,0,0,4,5,1,0);repeat(6)@(negedge clk);
  if(!sa_f[0])begin $display("FAIL epoch not rejected");errs=errs+1;end
  // bad encoding for A
  do_reset; send_ld(0,0,32'h03000000,0,0,3,5,1,1);repeat(6)@(negedge clk);
  if(!sa_f[0])begin $display("FAIL encoding not rejected");errs=errs+1;end
  // 64-bit end crossing: A base near the top
  do_reset; cfg_a_base=32'hFFFFFF00;
  send_ld(0,0,32'hFFFFFF00,0,0,3,5,1,0);repeat(6)@(negedge clk);
  if(!sa_f[0])begin $display("FAIL wrap/end not rejected");errs=errs+1;end
  cfg_a_base=32'h03000000;

  if(errs!=0)$fatal(1,"validator errs=%0d",errs);
  $display("PASS validator_pipe");
  $finish;
 end
 initial begin #2000000;$display("TIMEOUT validator");$fatal(1);end
endmodule
