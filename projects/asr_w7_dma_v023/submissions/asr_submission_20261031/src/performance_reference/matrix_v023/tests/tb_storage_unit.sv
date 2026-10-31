`timescale 1ns/1ps
module tb_storage_unit;
 localparam [31:0] A_BASE=32'h03000000,B_BASE=32'h03000800,C_BASE=32'h03000C00;
 localparam integer M=32,N=32,K=32;
 reg clk=0,rst_n=0;
 always #5 clk=~clk;

 // config
 reg [31:0] cfg_epoch=32'd1;
 reg [15:0] cfg_m=M,cfg_n=N,cfg_k=K,cfg_layer=16'd3,cfg_a_id=16'd11,cfg_b_id=16'd12,cfg_c_id=16'd13,cfg_allowed=16'd3;
 reg cfg_c_valid=0;reg [15:0] cfg_c_completed=0;reg [31:0] param_end=32'h40000000;
 reg abort=0;
 // load cmd
 reg ld_valid=0;wire ld_ready;reg [1:0] ld_kind=0;reg ld_stage=0;
 reg [31:0] ld_address=0,ld_epoch=1;reg [15:0] ld_layer=3,ld_matrix=11,ld_brow=0,ld_bcol=0,ld_ops=3,ld_comp=0;
 reg [1:0] ld_enc=0;reg ld_bvalid=1,ld_inop=1;
 wire [1:0] sa_r,sw_r,sa_f,sw_f,sa_bv,sw_bv,sa_io,sw_io;reg [1:0] rel=0;
 wire [63:0] sa_e,sw_e;wire [31:0] sa_l,sw_l,sa_m,sw_m,sa_row,sw_row,sa_col,sw_col,sa_a,sw_a,sa_c,sw_c;
 wire [3:0] sa_enc,sw_enc;
 reg rd_stage=0,rd_rh=0,rd_ch=0;reg [79:0] a_k=0,w_k=0;wire [255:0] a_values;wire [111:0] w_values;
 // C stream load
 wire chv,chx,chbv,chio,cher;wire [7:0] chc;wire [63:0] che;wire [31:0] chl,chm,chr,chcol,cha,chcomp;wire [3:0] chenc;
 reg chready=0;wire clv,cll,cld,cldr;wire [127:0] cld_data;wire [15:0] cld_idx;wire [7:0] cldc;reg clready=0;
 // C write
 reg cseg_valid=0;wire cseg_ready;reg [31:0] cseg_addr=0,cseg_epoch=1;reg [15:0] cseg_layer=3,cseg_matrix=13,cseg_row=0,cseg_col=0,cseg_beats=6;
 reg cval_valid=0;wire cval_ready;reg [191:0] cval_data=0;reg cval_last=0;
 wire [7:0] cwr_pending;wire cwr_idle,cwr_done,cwr_error;wire [7:0] cwr_code;
 // DMA
 wire rd_req_valid;wire rd_req_ready;wire [31:0] rd_req_addr;wire [15:0] rd_req_beats;
 wire rd_valid;wire rd_ready;wire [127:0] rd_data;wire [15:0] rd_index;wire rd_done,rd_error;
 wire wr_req_valid;wire wr_req_ready;wire [31:0] wr_req_addr;wire [15:0] wr_req_beats;
 wire wr_valid;wire wr_ready;wire [127:0] wr_data;wire [15:0] wr_strobe;wire wr_done,wr_error;
 reg init_valid=0;reg [31:0] init_addr=0;reg [127:0] init_data=0;
 wire [31:0] chk_addr=32'h03000000;wire [127:0] chk_data;
 wire [31:0] rd_cmds,wr_cmds,rd_beats,wr_beats,shared_conf,max_b,rd_stall,wr_stall;
 wire idle,drain_done,rd_active,wr_active;
 wire [31:0] rblocks,wsegs,rbytes,wbytes,errcnt,ovs,rdwr;
 wire [63:0] rdwait,wrwait;
 wire [1:0] drs,dws;

 block_storage_stream_v2 dut(
  .clk(clk),.rst_n(rst_n),.abort(abort),.param_end(param_end),
  .cfg_a_base(A_BASE),.cfg_b_base(B_BASE),.cfg_c_base(C_BASE),.cfg_epoch(cfg_epoch),
  .cfg_m(cfg_m),.cfg_n(cfg_n),.cfg_k(cfg_k),.cfg_layer(cfg_layer),.cfg_a_id(cfg_a_id),.cfg_b_id(cfg_b_id),.cfg_c_id(cfg_c_id),
  .cfg_allowed(cfg_allowed),.cfg_c_valid(cfg_c_valid),.cfg_c_completed(cfg_c_completed),
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
  .idle(idle),.drain_done(drain_done),.read_blocks(rblocks),.write_segments(wsegs),.read_bytes(rbytes),.write_bytes(wbytes),
  .error_count(errcnt),.read_wait_cycles(rdwait),.write_wait_cycles(wrwait),.ov_same_cycle(ovs),
  .rd_active_wr_active_cycles(rdwr),.rd_active(rd_active),.wr_active(wr_active),.dbg_rstate(drs),.dbg_wwait(dws));

 wire inj_rd=0,inj_wr=0;
 txn_dma_bfm #(.BASE(32'h03000000),.MEM_WORDS(16384),.SEED(7),.RD_LAT(5),.RD_GAP(10),.WR_GAP(15),.B_DELAY(7),.SHARED_BW(0)) bfm(
  .clk(clk),.rst_n(rst_n),.inject_rd_error(inj_rd),.inject_wr_error(inj_wr),
  .rd_req_valid(rd_req_valid),.rd_req_ready(rd_req_ready),.rd_req_address(rd_req_addr),.rd_req_beats(rd_req_beats),
  .rd_valid(rd_valid),.rd_ready(rd_ready),.rd_data(rd_data),.rd_index(rd_index),.rd_done(rd_done),.rd_error(rd_error),
  .wr_req_valid(wr_req_valid),.wr_req_ready(wr_req_ready),.wr_req_address(wr_req_addr),.wr_req_beats(wr_req_beats),
  .wr_valid(wr_valid),.wr_ready(wr_ready),.wr_data(wr_data),.wr_strobe(wr_strobe),.wr_done(wr_done),.wr_error(wr_error),
  .init_valid(init_valid),.init_addr(init_addr),.init_data(init_data),.chk_addr(chk_addr),.chk_data(chk_data),
  .rd_cmds(rd_cmds),.wr_cmds(wr_cmds),.rd_beats_c(rd_beats),.wr_beats_c(wr_beats),.shared_conflict(shared_conf),
  .max_b_out(max_b),.rd_stall_cycles(rd_stall),.wr_stall_cycles(wr_stall));

 // vectors
 reg [15:0] ea[0:1023];reg [7:0] eb[0:1023];reg [7:0] ecb[0:6143];
 integer i,j,p,errs;
 reg [31:0] lsr=32'h12345678;integer bfm_hs_cnt=0,dut_hs_cnt=0;
 function [31:0] rnd;begin lsr={lsr[30:0],lsr[31]^lsr[16]^lsr[5]^lsr[4]};rnd=lsr;end endfunction

 task init_word(input [31:0] a,input [127:0] d);begin
  @(negedge clk);init_valid=1;init_addr=a;init_data=d;
  @(negedge clk);init_valid=0;
 end endtask

 task load_cmd(input [1:0] kind,input st,input [31:0] addr,input [15:0] row,input [15:0] col,input [1:0] enc,input [15:0] mat);
 begin
  @(negedge clk);ld_valid=1;ld_kind=kind;ld_stage=st;ld_address=addr;ld_brow=row;ld_bcol=col;ld_enc=enc;ld_matrix=mat;
  @(posedge clk);while(!ld_ready)@(posedge clk);
  @(negedge clk);ld_valid=0;
 end endtask

 task check_a;integer h,k,r;begin
  for(h=0;h<2;h=h+1)for(k=0;k<32;k=k+1)begin
   rd_stage=0;rd_rh=h;rd_ch=0;
   for(r=0;r<16;r=r+1)a_k[r*5+:5]=k;
   #1;
   for(r=0;r<16;r=r+1)if(a_values[r*16+:16]!==ea[(h*16+r)*32+k])begin
    if(errs<10)$display("FAIL A h=%0d k=%0d r=%0d got=%h exp=%h",h,k,r,a_values[r*16+:16],ea[(h*16+r)*32+k]);
    errs=errs+1;
   end
  end
 end endtask

 task check_w;integer h,k,c;begin
  for(h=0;h<2;h=h+1)for(k=0;k<32;k=k+1)begin
   rd_stage=1;rd_rh=0;rd_ch=h;
   for(c=0;c<16;c=c+1)w_k[c*5+:5]=k;
   #1;
   for(c=0;c<16;c=c+1)if(w_values[c*7+:7]!==eb[k*32+h*16+c][6:0])begin
    if(errs<10)$display("FAIL W h=%0d k=%0d c=%0d got=%h exp=%h",h,k,c,w_values[c*7+:7],eb[k*32+h*16+c][6:0]);
    errs=errs+1;
   end
  end
 end endtask

 task write_c_block;integer s,row,half,g,v;begin
  for(s=0;s<64;s=s+1)begin
   row=s/2;half=s%2;
   cseg_addr=C_BASE+row*192+half*96;cseg_row=0;cseg_col=0;cseg_beats=6;
   @(negedge clk);cseg_valid=1;
   @(posedge clk);while(!cseg_ready)@(posedge clk);
   @(negedge clk);cseg_valid=0;
   for(g=0;g<4;g=g+1)begin
    cval_data=0;
    for(v=0;v<4;v=v+1)cval_data[v*48+:48]={ecb[((row*32+half*16)+(g*4+v))*6+5],ecb[((row*32+half*16)+(g*4+v))*6+4],ecb[((row*32+half*16)+(g*4+v))*6+3],ecb[((row*32+half*16)+(g*4+v))*6+2],ecb[((row*32+half*16)+(g*4+v))*6+1],ecb[((row*32+half*16)+(g*4+v))*6+0]};
    cval_last=(g==3);
    @(negedge clk);cval_valid=1;
    @(posedge clk);while(!cval_ready)@(posedge clk);
    @(negedge clk);cval_valid=0;
   end
  end
 end endtask

 initial begin
  errs=0;
  for(i=0;i<1024;i=i+1)ea[i]=$random;
  for(i=0;i<1024;i=i+1)begin eb[i]=$random&8'h7f;eb[i][7]=^eb[i][6:0];end
  for(i=0;i<6144;i=i+1)ecb[i]=$random;
  rst_n=0;repeat(5)@(negedge clk);rst_n=1;repeat(3)@(negedge clk);

  // init A/B/C memory
  for(i=0;i<128;i=i+1)begin
   init_data=0;
   for(j=0;j<8;j=j+1)init_data[j*16+:16]=ea[(i/4)*32+(i%4)*8+j];
   init_word(A_BASE+i*16,init_data);
  end
  for(i=0;i<64;i=i+1)begin
   init_data=0;
   for(j=0;j<16;j=j+1)init_data[j*8+:8]=eb[(i/2)*32+(i%2)*16+j];
   init_word(B_BASE+i*16,init_data);
  end
  for(i=0;i<384;i=i+1)begin
   init_data=0;
   for(j=0;j<16;j=j+1)init_data[j*8+:8]=ecb[i*16+j];
   init_word(C_BASE+i*16,init_data);
  end

  $display("INFO init done");
  // A stage0 and W stage1 concurrently with read side bank access
  fork
   load_cmd(0,0,A_BASE,0,0,0,11);
   begin wait(sa_r[0]);check_a;end
  join
  $display("A loaded");
  load_cmd(1,1,B_BASE,0,0,1,12);
  wait(sw_r[1]);
  $display("W loaded");
  check_w;
  $display("INFO A/W bank read done errs=%0d rd_cmds=%0d",errs,rd_cmds);
  if(errs!==0)$fatal(1,"A/W bank mismatch");
  @(negedge clk);rel=2'b11;@(negedge clk);rel=2'b00;

  $display("starting C write");
  // C48 streamed write while a new A prefetch is active
  cseg_valid=0;cval_valid=0;
  fork
   begin load_cmd(0,0,A_BASE,0,0,0,11);end
   begin wait(ld_ready);write_c_block;end
  join
  wait(cwr_idle);
  repeat(5)@(negedge clk);
  for(i=0;i<6144;i=i+1)if(bfm.mem[C_BASE-32'h03000000+i]!==ecb[i])begin
   if(errs<10)$display("FAIL C byte %0d got=%h exp=%h",i,bfm.mem[C_BASE-32'h03000000+i],ecb[i]);
   errs=errs+1;
  end
  $display("INFO C write errs=%0d wr_segs=%0d wr_bytes=%0d max_b=%0d ovsame=%0d rdwr=%0d",errs,wsegs,wbytes,max_b,ovs,rdwr);
  if(errs!==0)$fatal(1,"C stream mismatch");
  if(wsegs!=64)$fatal(1,"expected 64 segments");

  // bad ACL must fault without issuing a DMA command
  i=rd_cmds;
  load_cmd(0,1,A_BASE,0,0,0,99);
  wait(sa_f[1]);
  repeat(4)@(negedge clk);
  if(rd_cmds!==i)$fatal(1,"bad ACL issued DMA");
  if(errcnt==0)$fatal(1,"bad ACL did not count error");
  $display("PASS tb_storage_unit tests rd_cmds=%0d wr_cmds=%0d",rd_cmds,wr_cmds);
  $finish;
 end
 initial begin
  #200000;
  $display("TIMEOUT rstate=%0d lq=%0d sw_r=%b sw_f=%b sa_r=%b sa_f=%b rdcmds=%0d",dut.rstate,dut.lq_cnt,sw_r,sw_f,sa_r,sa_f,rd_cmds);
  $fatal(1,"timeout");
 end
endmodule
