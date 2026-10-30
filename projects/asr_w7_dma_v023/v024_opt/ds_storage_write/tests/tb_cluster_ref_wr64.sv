`timescale 1ns/1ps
// AXI-level integration test for matrix_p2_cluster_v2.
// Same integer fixtures as tb_engine_p2.  The BFM is a logic AXI slave with
// multiple outstanding AR/AW, not a DDR timing model.  A per-cycle CSV and
// transfer-event log are written for the project traffic-ledger and
// module-activity-waveform skills.
module tb_cluster_ref_wr64;
 parameter [31:0] BASE=32'h03000000;
 parameter [31:0] A_BASE=32'h03000000,B_BASE=32'h03002000,C_BASE=32'h03003000;
 parameter integer M=32,N=32,K=32;
 parameter integer MEM_WORDS=1536;
 parameter integer PIPE=4;
 parameter integer LAT_MIN=8,LAT_MAX=32,BP_PCT=10,SEED=7;
 parameter integer DUPLEX=0;
 parameter integer NBLK=((M+31)/32)*((N+31)/32);
 reg clk=0,rst_n=0;always #5 clk=~clk;
 reg [31:0] cfg_epoch=32'd3;
 reg [15:0] cfg_m=M,cfg_n=N,cfg_k=K,cfg_layer=16'd5,cfg_a_id=16'd1,cfg_b_id=16'd2,cfg_c_id=16'd3;
 reg [15:0] cfg_target_high=16'd0,cfg_allowed=16'd1,cfg_requested_op=16'd1;
 reg [15:0] cfg_positions=16'h3210,cfg_c_completed=16'd0;
 reg cfg_clip=1'b1,cfg_c_valid=0,start=0;
 wire busy,done,fault;wire [7:0] error_code;
 wire [63:0] task_cycles;wire [31:0] compute_cycles,read_blocks,write_blocks,cache_hits,cache_misses;
 wire [31:0] prehit,prewait,ov_rd,ov_wr,cgrp,ccyc,craw;
 wire [7:0] pe_drain,array_drain;
 wire result_valid;reg result_ready=1;wire [31:0] result_cache_address,result_epoch;
 wire [15:0] result_target_low,result_layer,result_matrix,result_block_row,result_block_col,result_op_tag;
 wire [49151:0] result_data;wire result_block_valid,result_in_operation;
 wire [15:0] result_allowed_ops,result_completed_ops;
 // AXI read port (BFM port 0)
 wire [39:0] r_araddr;wire [7:0] r_arlen;wire [2:0] r_arsize;wire [1:0] r_arburst;
 wire r_arvalid,r_arready;wire [127:0] r_rdata;wire [1:0] r_rresp;wire r_rlast,r_rvalid,r_rready;
 // AXI write port (BFM port 1)
 wire [39:0] w_awaddr;wire [7:0] w_awlen;wire [2:0] w_awsize;wire [1:0] w_awburst;
 wire w_awvalid,w_awready;wire [127:0] w_wdata;wire [15:0] w_wstrb;wire w_wlast,w_wvalid,w_wready;
 wire [1:0] w_bresp;wire w_bvalid,w_bready;
 wire [31:0] rd_armax,rd_bytes,rd_bursts,wr_bmax,wr_bytes,wr_bursts;wire [63:0] rd_fifo_high;
 // BFM bus
 wire [1:0] arready_b,awready_b,wready_b,rvalid_b,bvalid_b,arvalid_b,awvalid_b,wvalid_b,bready_b,rready_b;
 wire [79:0] araddr_b,awaddr_b;wire [15:0] arlen_b,awlen_b;wire [5:0] arsize_b,awsize_b;
 wire [3:0] arburst_b,awburst_b;wire [255:0] rdata_b,wdata_b;wire [3:0] rresp_b,bresp_b;
 wire [31:0] wstrb_b;wire [1:0] rlast_b,wlast_b;
 assign araddr_b={40'd0,r_araddr};assign arlen_b={8'd0,r_arlen};assign arsize_b={3'd0,r_arsize};
 assign arburst_b={2'd0,r_arburst};assign arvalid_b={1'b0,r_arvalid};assign rready_b={1'b1,r_rready};
 assign awaddr_b={w_awaddr,40'd0};assign awlen_b={w_awlen,8'd0};assign awsize_b={w_awsize,3'd0};
 assign awburst_b={w_awburst,2'd0};assign awvalid_b={w_awvalid,1'b0};assign wvalid_b={w_wvalid,1'b0};
 assign wdata_b={w_wdata,128'd0};assign wstrb_b={w_wstrb,16'd0};assign wlast_b={w_wlast,1'b0};
 assign bready_b={w_bready,1'b1};
 assign r_arready=arready_b[0];assign r_rvalid=rvalid_b[0];assign r_rdata=rdata_b[127:0];
 assign r_rresp=rresp_b[1:0];assign r_rlast=rlast_b[0];
 assign w_awready=awready_b[1];assign w_wready=wready_b[1];assign w_bvalid=bvalid_b[1];
 assign w_bresp=bresp_b[3:2];
 wire [63:0] total_cycles,busy_cycles,read_busy,write_busy,read_beats,write_beats,read_bursts_bfm,write_bursts_bfm;
 wire [63:0] read_wait,write_wait,ar_stalls,aw_stalls,cmd_stalls;
 wire [31:0] max_rd,max_wr;

 matrix_p2_cluster_v2 #(.PIPE_STAGES(PIPE),.MAX_OUT(8),.FIFO_BEATS(128),.WR_OUT(64)) dut(
  .clk(clk),.reset(!rst_n),.start(start),
  .cfg_a_base(A_BASE),.cfg_b_base(B_BASE),.cfg_c_base(C_BASE),.cfg_epoch(cfg_epoch),
  .cfg_m(cfg_m),.cfg_n(cfg_n),.cfg_k(cfg_k),.cfg_layer(cfg_layer),.cfg_a_id(cfg_a_id),
  .cfg_b_id(cfg_b_id),.cfg_c_id(cfg_c_id),.cfg_target_high(cfg_target_high),
  .cfg_allowed_ops(cfg_allowed),.cfg_requested_op(cfg_requested_op),.cfg_positions(cfg_positions),
  .cfg_clip(cfg_clip),.cfg_c_valid(cfg_c_valid),.cfg_c_completed(cfg_c_completed),
  .param_end(32'h40000000),.busy(busy),.done(done),.fault(fault),.error_code(error_code),
  .task_cycles(task_cycles),.compute_cycles(compute_cycles),.read_blocks(read_blocks),
  .write_blocks(write_blocks),.cache_hits(cache_hits),.cache_misses(cache_misses),
  .prefetch_hits(prehit),.prefetch_wait_cycles(prewait),
  .overlap_compute_read_cycles(ov_rd),.overlap_compute_write_cycles(ov_wr),
  .c_collect_groups(cgrp),.c_collect_cycles(ccyc),.c_raw_bypass_cycles(craw),
  .pe_drain_cycles(pe_drain),.array_drain_cycles(array_drain),
  .result_valid(result_valid),.result_ready(result_ready),
  .result_cache_address(result_cache_address),.result_epoch(result_epoch),
  .result_target_low(result_target_low),.result_layer(result_layer),.result_matrix(result_matrix),
  .result_block_row(result_block_row),.result_block_col(result_block_col),.result_op_tag(result_op_tag),
  .result_data(result_data),.result_block_valid(result_block_valid),
  .result_in_operation(result_in_operation),.result_allowed_ops(result_allowed_ops),
  .result_completed_ops(result_completed_ops),
  .rd_m_axi_araddr(r_araddr),.rd_m_axi_arlen(r_arlen),.rd_m_axi_arsize(r_arsize),
  .rd_m_axi_arburst(r_arburst),.rd_m_axi_arvalid(r_arvalid),.rd_m_axi_arready(r_arready),
  .rd_m_axi_rdata(r_rdata),.rd_m_axi_rresp(r_rresp),.rd_m_axi_rlast(r_rlast),
  .rd_m_axi_rvalid(r_rvalid),.rd_m_axi_rready(r_rready),
  .wr_m_axi_awaddr(w_awaddr),.wr_m_axi_awlen(w_awlen),.wr_m_axi_awsize(w_awsize),
  .wr_m_axi_awburst(w_awburst),.wr_m_axi_awvalid(w_awvalid),.wr_m_axi_awready(w_awready),
  .wr_m_axi_wdata(w_wdata),.wr_m_axi_wstrb(w_wstrb),.wr_m_axi_wlast(w_wlast),
  .wr_m_axi_wvalid(w_wvalid),.wr_m_axi_wready(w_wready),
  .wr_m_axi_bresp(w_bresp),.wr_m_axi_bvalid(w_bvalid),.wr_m_axi_bready(w_bready),
  .rd_ar_outstanding_max(rd_armax),.rd_read_bytes(rd_bytes),.rd_read_bursts(rd_bursts),
  .wr_b_outstanding_max(wr_bmax),.wr_write_bytes(wr_bytes),.wr_write_bursts(wr_bursts),
  .rd_read_fifo_high(rd_fifo_high));

 axi128_ddr_bfm #(.PORTS(2),.BASE(BASE),.MEM_BYTES(1048576),.LAT_MIN(LAT_MIN),.LAT_MAX(LAT_MAX),
   .BP_PCT(BP_PCT),.SEED(SEED),.MAX_RD_OUT(8),.MAX_WR_OUT(8),.DUPLEX(DUPLEX)) bfm(
  .clk(clk),.rst_n(rst_n),
  .araddr(araddr_b),.arlen(arlen_b),.arsize(arsize_b),.arburst(arburst_b),
  .arvalid(arvalid_b),.arready(arready_b),
  .rdata(rdata_b),.rresp(rresp_b),.rlast(rlast_b),.rvalid(rvalid_b),.rready(rready_b),
  .awaddr(awaddr_b),.awlen(awlen_b),.awsize(awsize_b),.awburst(awburst_b),
  .awvalid(awvalid_b),.awready(awready_b),
  .wdata(wdata_b),.wstrb(wstrb_b),.wlast(wlast_b),.wvalid(wvalid_b),.wready(wready_b),
  .bresp(bresp_b),.bvalid(bvalid_b),.bready(bready_b),
  .inject_read_error(1'b0),.inject_write_error(1'b0),
  .total_cycles(total_cycles),.busy_cycles(busy_cycles),.read_busy_cycles(read_busy),
  .write_busy_cycles(write_busy),.read_beats(read_beats),.write_beats(write_beats),
  .read_bursts(read_bursts_bfm),.write_bursts(write_bursts_bfm),
  .read_wait_cycles(read_wait),.write_wait_cycles(write_wait),
  .ar_full_stalls(ar_stalls),.aw_full_stalls(aw_stalls),.cmd_stalls(cmd_stalls),
  .max_rd_outstanding(max_rd),.max_wr_outstanding(max_wr));

 reg [127:0] initmem[0:MEM_WORDS-1];
 reg [47:0] expv[0:NBLK*1024-1];
 reg seen[0:NBLK-1];integer errs=0,i,j,blk,rv=0,cyc=0;
 reg [1023:0] initfile,expfile,tracefile;integer tf=-1;reg tracing=0;
 integer start_cycle=0,done_cycle=0;
 function [7:0] bfm_byte(input integer off);
  integer wd,ln;begin wd=off/16;ln=off%16;bfm_byte=bfm.mem[wd][ln*8+:8];end
 endfunction

 always @(posedge clk)if(rst_n&&result_valid&&result_ready)begin
  blk=result_block_row*((N+31)/32)+result_block_col;
  if(blk>=0&&blk<NBLK)begin
   for(i=0;i<1024;i=i+1)
    if(result_data[i*48+:48]!==expv[blk*1024+i])begin
     if(errs<8)$display("FAIL result blk=%0d i=%0d got=%012h exp=%012h",blk,i,result_data[i*48+:48],expv[blk*1024+i]);
     errs=errs+1;
    end
   rv=rv+1;
  end
 end

 // per-cycle trace for the two project skills
 always @(posedge clk)if(rst_n&&tracing)begin
  cyc=cyc+1;
  $fwrite(tf,"C %0d %0d %0d %0d %0d %0d %0d %0d %0d %0d %0d %0d %0d %0d %0d %0d %0d %0d %0d %0d %0d %0d\n",
   cyc,
   (r_arvalid&&r_arready),(r_rvalid&&r_rready),(r_rvalid&&!r_rready),
   (dut.rd_req_valid&&dut.rd_req_ready),
   (w_awvalid&&w_awready),(w_wvalid&&w_wready),(w_wvalid&&!w_wready),
   (dut.wr_req_valid&&dut.wr_req_ready),(w_bvalid&&w_bready),
   dut.eng.state,dut.sto.rstate,(dut.sto.w_cur_valid||dut.sto.wq_cnt!=0||dut.sto.b_out!=0),
   (dut.eng.cache_rd_issue),(dut.eng.cache_wr_load||dut.eng.cache_wr_collect),
   (dut.cseg_valid&&dut.cseg_ready),(dut.cval_valid&&dut.cval_ready),
   (dut.cval_valid&&!dut.cval_ready),dut.sto.wq_cnt,dut.sto.b_out,
   (dut.rd_active),(dut.wr_active));
  if(dut.rd_req_valid&&dut.rd_req_ready)$fwrite(tf,"E rdcmd %0d %0d %0d\n",cyc,dut.rd_req_addr,dut.rd_req_beats);
  if(dut.rd_valid&&dut.rd_ready)$fwrite(tf,"E rdbeat %0d 16\n",cyc);
  if(dut.rd_done)$fwrite(tf,"E rddone %0d\n",cyc);
  if(dut.ld_valid&&dut.ld_ready)$fwrite(tf,"E ld %0d %0d %0d %0d %0d\n",cyc,dut.ld_kind,dut.ld_block_row,dut.ld_block_col,dut.ld_address);
  if(dut.cseg_valid&&dut.cseg_ready)$fwrite(tf,"E cseg %0d %0d %0d %0d\n",cyc,dut.cseg_address,dut.cseg_beats,dut.cseg_row*16+dut.cseg_col);
  if(dut.wr_req_valid&&dut.wr_req_ready)$fwrite(tf,"E wrcmd %0d %0d %0d\n",cyc,dut.wr_req_addr,dut.wr_req_beats);
  if(dut.wr_valid&&dut.wr_ready)$fwrite(tf,"E wrbeat %0d %0d\n",cyc,$countones(dut.wr_strobe));
  if(dut.wr_done)$fwrite(tf,"E wrdone %0d\n",cyc);
 end

 initial begin
  if(!$value$plusargs("init=%s",initfile))initfile="fixtures/eng_k1/init.hex";
  if(!$value$plusargs("exp=%s",expfile))expfile="fixtures/eng_k1/exp_c.txt";
  if($value$plusargs("trace=%s",tracefile))begin tf=$fopen(tracefile,"w");end
  if(!$value$plusargs("cvalid=%d",cfg_c_valid))cfg_c_valid=0;
  $readmemh(initfile,initmem);$readmemh(expfile,expv);
  for(i=0;i<NBLK;i=i+1)seen[i]=0;
  for(i=0;i<MEM_WORDS;i=i+1)bfm.mem[i]=initmem[i];
  for(i=MEM_WORDS;i<1048576/16;i=i+1)bfm.mem[i]=0;
  rst_n=0;repeat(6)@(negedge clk);rst_n=1;repeat(4)@(negedge clk);
  @(negedge clk);start=1;@(negedge clk);start=0;
  start_cycle=cyc;tracing=1;
  $fwrite(tf,"S %0d\n",start_cycle);
  wait(done);repeat(5)@(negedge clk);tracing=0;done_cycle=cyc;
  $fwrite(tf,"D %0d\n",done_cycle);$fclose(tf);
  $display("INFO cluster done fault=%b code=%h cycles=%0d compute=%0d rdblk=%0d wrblk=%0d cgrp=%0d ccyc=%0d craw=%0d",
   fault,error_code,task_cycles,compute_cycles,read_blocks,write_blocks,cgrp,ccyc,craw);
  $display("INFO dma rd_bursts=%0d rd_bytes=%0d armax=%0d fifohi=%0d wr_bursts=%0d wr_bytes=%0d bmax=%0d bfm_rbeats=%0d bfm_wbeats=%0d maxrd=%0d maxwr=%0d",
   rd_bursts,rd_bytes,rd_armax,rd_fifo_high,wr_bursts,wr_bytes,wr_bmax,read_beats,write_beats,max_rd,max_wr);
  if(fault)begin $display("FAIL cluster fault");$fatal(1);end
  for(blk=0;blk<NBLK;blk=blk+1)begin
   for(i=0;i<1024;i=i+1)for(j=0;j<6;j=j+1)
    if(bfm_byte((C_BASE-BASE)+blk*6144+i*6+j)!==expv[blk*1024+i][j*8+:8])begin
     if(errs<8)$display("FAIL C mem blk=%0d i=%0d j=%0d got=%h exp=%h",blk,i,j,bfm_byte((C_BASE-BASE)+blk*6144+i*6+j),expv[blk*1024+i][j*8+:8]);
     errs=errs+1;
    end
  end
  if(errs!=0)$fatal(1,"cluster errs=%0d",errs);
  if(rv!=NBLK)begin $display("FAIL result count %0d != %0d",rv,NBLK);$fatal(1);end
  if(wr_bytes!=NBLK*6144)begin $display("FAIL write_bytes %0d expected %0d",wr_bytes,NBLK*6144);$fatal(1);end
  $display("PASS tb_p2_cluster_axi M=%0d N=%0d K=%0d PIPE=%0d cycles=%0d rv=%0d wr_bytes=%0d",
   M,N,K,PIPE,task_cycles,rv,wr_bytes);
  $finish;
 end
 initial begin #20000000;$display("TIMEOUT done=%b fault=%b state=%0d",done,fault,dut.eng.state);$fatal(1);end
endmodule
