`timescale 1ns/1ps
// Layer-2 integration: candidate storage transaction ports connected to the
// original frozen axi_dma_v019 cores and a real AXI128 memory BFM.  This is
// not a new AXI burst engine; ds_ddr owns that layer.  It proves the storage
// contract drives the existing DMA RTL with independent read/write masters.
module tb_storage_axi;
 localparam [31:0] BASE=32'h03000000;
 localparam [31:0] A_BASE=32'h03000000,B_BASE=32'h03000800,C_BASE=32'h03000C00;
 localparam integer M=32,N=32,K=32;
 reg clk=0,rst_n=0;always #5 clk=~clk;
 reg [31:0] cfg_epoch=1;reg [15:0] cfg_m=M,cfg_n=N,cfg_k=K,cfg_layer=3,cfg_a_id=11,cfg_b_id=12,cfg_c_id=13,cfg_allowed=3;
 reg cfg_c_valid=0;reg [15:0] cfg_c_completed=0;reg abort=0;
 reg ld_valid=0;wire ld_ready;reg [1:0] ld_kind=0;reg ld_stage=0;reg [31:0] ld_address=0,ld_epoch=1;
 reg [15:0] ld_layer=3,ld_matrix=11,ld_brow=0,ld_bcol=0,ld_ops=3,ld_comp=0;reg [1:0] ld_enc=0;reg ld_bvalid=1,ld_inop=1;
 wire [1:0] sa_r,sw_r,sa_f,sw_f,sa_bv,sw_bv,sa_io,sw_io;reg [1:0] rel=0;wire [63:0] sa_e,sw_e;
 wire [31:0] sa_l,sw_l,sa_m,sw_m,sa_row,sw_row,sa_col,sw_col,sa_a,sw_a,sa_c,sw_c;wire [3:0] sa_enc,sw_enc;
 reg rd_stage=0,rd_rh=0,rd_ch=0;reg [79:0] a_k=0,w_k=0;wire [255:0] a_values;wire [111:0] w_values;
 wire chv,chx,chbv,chio,cher;wire [7:0] chc;wire [63:0] che;wire [31:0] chl,chm,chr,chcol,cha,chcomp;wire [3:0] chenc;
 reg chready=0;wire clv,cll,cld,cldr;wire [127:0] cld_data;wire [15:0] cld_idx;wire [7:0] cldc;reg clready=0;
 reg cseg_valid=0;wire cseg_ready;reg [31:0] cseg_addr=0,cseg_epoch=1;reg [15:0] cseg_layer=3,cseg_matrix=13,cseg_row=0,cseg_col=0,cseg_beats=6;
 reg cval_valid=0;wire cval_ready;reg [191:0] cval_data=0;reg cval_last=0;
 wire [7:0] cwr_pending;wire cwr_idle,cwr_done,cwr_error;wire [7:0] cwr_code;
 // storage DMA transaction ports
 wire rd_req_valid,rd_req_ready;wire [31:0] rd_req_addr;wire [15:0] rd_req_beats;
 wire rd_valid,rd_ready;wire [127:0] rd_data;wire [15:0] rd_index;wire rd_done,rd_error;
 wire wr_req_valid,wr_req_ready;wire [31:0] wr_req_addr;wire [15:0] wr_req_beats;
 wire wr_valid,wr_ready;wire [127:0] wr_data;wire [15:0] wr_strobe;wire wr_done,wr_error;
 // AXI read master
 wire [39:0] r_araddr;wire [7:0] r_arlen;wire [2:0] r_arsize;wire [1:0] r_arburst;
 wire [3:0] r_arcache;wire [2:0] r_arprot;wire r_arvalid,r_arready;
 wire [127:0] r_rdata;wire [1:0] r_rresp;wire r_rlast,r_rvalid,r_rready;
 wire [39:0] r_awaddr;wire [7:0] r_awlen;wire [2:0] r_awsize;wire [1:0] r_awburst;
 wire [3:0] r_awcache;wire [2:0] r_awprot;wire r_awvalid,r_awready;
 wire [127:0] r_wdata;wire [15:0] r_wstrb;wire r_wlast,r_wvalid,r_wready;wire [1:0] r_bresp;wire r_bvalid,r_bready;
 // AXI write master
 wire [39:0] w_araddr;wire [7:0] w_arlen;wire [2:0] w_arsize;wire [1:0] w_arburst;
 wire [3:0] w_arcache;wire [2:0] w_arprot;wire w_arvalid,w_arready;
 wire [127:0] w_rdata;wire [1:0] w_rresp;wire w_rlast,w_rvalid,w_rready;
 wire [39:0] w_awaddr;wire [7:0] w_awlen;wire [2:0] w_awsize;wire [1:0] w_awburst;
 wire [3:0] w_awcache;wire [2:0] w_awprot;wire w_awvalid,w_awready;
 wire [127:0] w_wdata;wire [15:0] w_wstrb;wire w_wlast,w_wvalid,w_wready;wire [1:0] w_bresp;wire w_bvalid,w_bready;
 wire [31:0] rd_bytes,wr_bytes,rd_bursts,wr_bursts;
 wire idle,drain_done,rd_active,wr_active;wire [31:0] rblk,wseg,rbytes,wbytes,errcnt,ovs,rdwr;
 wire [63:0] rdwait,wrwait;wire [1:0] drs,dws;
 reg [15:0] expA[0:1023];reg [47:0] expC[0:1023];
 integer i,r,c,h,g,v,errs=0,cyc=0;

 block_storage_stream_v2 #(.ARENA_BASE(32'h03000000),.ARENA_END(32'h08000000),.WR_OUT(4)) dut(
  .clk(clk),.rst_n(rst_n),.abort(abort),.param_end(32'h40000000),
  .cfg_a_base(A_BASE),.cfg_b_base(B_BASE),.cfg_c_base(C_BASE),.cfg_epoch(cfg_epoch),
  .cfg_m(cfg_m),.cfg_n(cfg_n),.cfg_k(cfg_k),.cfg_layer(cfg_layer),.cfg_a_id(cfg_a_id),.cfg_b_id(cfg_b_id),.cfg_c_id(cfg_c_id),
  .cfg_allowed(cfg_allowed),.cfg_c_valid(cfg_c_valid),.cfg_c_completed(cfg_c_completed),
  .ld_valid(ld_valid),.ld_ready(ld_ready),.ld_kind(ld_kind),.ld_stage(ld_stage),.ld_address(ld_address),.ld_epoch(ld_epoch),
  .ld_layer(ld_layer),.ld_matrix(ld_matrix),.ld_block_row(ld_brow),.ld_block_col(ld_bcol),.ld_allowed_ops(ld_ops),.ld_completed_ops(ld_comp),
  .ld_encoding(ld_enc),.ld_block_valid(ld_bvalid),.ld_in_operation(ld_inop),
  .stage_a_ready(sa_r),.stage_w_ready(sw_r),.stage_a_fault(sa_f),.stage_w_fault(sw_f),.stage_a_bvalid(sa_bv),.stage_w_bvalid(sw_bv),
  .stage_a_inop(sa_io),.stage_w_inop(sw_io),.stage_a_epoch(sa_e),.stage_w_epoch(sw_e),.stage_a_layer(sa_l),.stage_w_layer(sw_l),
  .stage_a_matrix(sa_m),.stage_w_matrix(sw_m),.stage_a_row(sa_row),.stage_w_row(sw_row),.stage_a_col(sa_col),.stage_w_col(sw_col),
  .stage_a_allowed(sa_a),.stage_w_allowed(sw_a),.stage_a_completed(sa_c),.stage_w_completed(sw_c),
  .stage_a_encoding(sa_enc),.stage_w_encoding(sw_enc),.stage_release(rel),
  .rd_stage(rd_stage),.rd_row_half(rd_rh),.rd_col_half(rd_ch),.a_k(a_k),.w_k(w_k),.a_values(a_values),.w_values(w_values),
  .c_hdr_valid(chv),.c_hdr_exists(chx),.c_hdr_bvalid(chbv),.c_hdr_inop(chio),.c_hdr_error(cher),.c_hdr_code(chc),
  .c_hdr_epoch(che),.c_hdr_layer(chl),.c_hdr_matrix(chm),.c_hdr_row(chr),.c_hdr_col(chcol),.c_hdr_allowed(cha),
  .c_hdr_completed(chcomp),.c_hdr_encoding(chenc),.c_hdr_ready(chready),
  .c_ld_valid(clv),.c_ld_last(cll),.c_ld_done(cld),.c_ld_error(cldr),.c_ld_data(cld_data),.c_ld_index(cld_idx),
  .c_ld_code(cldc),.c_ld_ready(clready),
  .cseg_valid(cseg_valid),.cseg_ready(cseg_ready),.cseg_address(cseg_addr),.cseg_epoch(cseg_epoch),.cseg_layer(cseg_layer),
  .cseg_matrix(cseg_matrix),.cseg_row(cseg_row),.cseg_col(cseg_col),.cseg_beats(cseg_beats),
  .cval_valid(cval_valid),.cval_ready(cval_ready),.cval_data(cval_data),.cval_last(cval_last),
  .cwr_pending(cwr_pending),.cwr_idle(cwr_idle),.cwr_done(cwr_done),.cwr_error(cwr_error),.cwr_code(cwr_code),
  .rd_req_valid(rd_req_valid),.rd_req_ready(rd_req_ready),.rd_req_address(rd_req_addr),.rd_req_beats(rd_req_beats),
  .rd_valid(rd_valid),.rd_ready(rd_ready),.rd_data(rd_data),.rd_index(rd_index),.rd_done(rd_done),.rd_error(rd_error),
  .wr_req_valid(wr_req_valid),.wr_req_ready(wr_req_ready),.wr_req_address(wr_req_addr),.wr_req_beats(wr_req_beats),
  .wr_valid(wr_valid),.wr_ready(wr_ready),.wr_data(wr_data),.wr_strobe(wr_strobe),.wr_done(wr_done),.wr_error(wr_error),
  .idle(idle),.drain_done(drain_done),.read_blocks(rblk),.write_segments(wseg),.read_bytes(rbytes),.write_bytes(wbytes),
  .error_count(errcnt),.read_wait_cycles(rdwait),.write_wait_cycles(wrwait),.ov_same_cycle(ovs),
  .rd_active_wr_active_cycles(rdwr),.rd_active(rd_active),.wr_active(wr_active),.dbg_rstate(drs),.dbg_wwait(dws));

 axi_dma_v019 rdma(.clk(clk),.rst_n(rst_n),.request_valid(rd_req_valid),.request_ready(rd_req_ready),.request_write(1'b0),
  .request_address(rd_req_addr),.request_beats(rd_req_beats),
  .read_valid(rd_valid),.read_ready(rd_ready),.read_data(rd_data),.read_index(rd_index),
  .write_valid(1'b0),.write_ready(),.write_data(128'd0),.write_strobe(16'd0),.write_index(),
  .done(rd_done),.error(rd_error),.read_bytes(rd_bytes),.write_bytes(),.read_bursts(rd_bursts),.write_bursts(),
  .m_axi_araddr(r_araddr),.m_axi_arlen(r_arlen),.m_axi_arsize(r_arsize),.m_axi_arburst(r_arburst),.m_axi_arcache(r_arcache),
  .m_axi_arprot(r_arprot),.m_axi_arvalid(r_arvalid),.m_axi_arready(r_arready),.m_axi_rdata(r_rdata),.m_axi_rresp(r_rresp),
  .m_axi_rlast(r_rlast),.m_axi_rvalid(r_rvalid),.m_axi_rready(r_rready),
  .m_axi_awaddr(r_awaddr),.m_axi_awlen(r_awlen),.m_axi_awsize(r_awsize),.m_axi_awburst(r_awburst),.m_axi_awcache(r_awcache),
  .m_axi_awprot(r_awprot),.m_axi_awvalid(r_awvalid),.m_axi_awready(r_awready),.m_axi_wdata(r_wdata),.m_axi_wstrb(r_wstrb),
  .m_axi_wlast(r_wlast),.m_axi_wvalid(r_wvalid),.m_axi_wready(r_wready),.m_axi_bresp(r_bresp),.m_axi_bvalid(r_bvalid),.m_axi_bready(r_bready));

 axi_dma_v019 wdma(.clk(clk),.rst_n(rst_n),.request_valid(wr_req_valid),.request_ready(wr_req_ready),.request_write(1'b1),
  .request_address(wr_req_addr),.request_beats(wr_req_beats),
  .read_valid(),.read_ready(1'b1),.read_data(),.read_index(),
  .write_valid(wr_valid),.write_ready(wr_ready),.write_data(wr_data),.write_strobe(wr_strobe),.write_index(),
  .done(wr_done),.error(wr_error),.read_bytes(),.write_bytes(wr_bytes),.read_bursts(),.write_bursts(wr_bursts),
  .m_axi_araddr(w_araddr),.m_axi_arlen(w_arlen),.m_axi_arsize(w_arsize),.m_axi_arburst(w_arburst),.m_axi_arcache(w_arcache),
  .m_axi_arprot(w_arprot),.m_axi_arvalid(w_arvalid),.m_axi_arready(w_arready),.m_axi_rdata(w_rdata),.m_axi_rresp(w_rresp),
  .m_axi_rlast(w_rlast),.m_axi_rvalid(w_rvalid),.m_axi_rready(w_rready),
  .m_axi_awaddr(w_awaddr),.m_axi_awlen(w_awlen),.m_axi_awsize(w_awsize),.m_axi_awburst(w_awburst),.m_axi_awcache(w_awcache),
  .m_axi_awprot(w_awprot),.m_axi_awvalid(w_awvalid),.m_axi_awready(w_awready),.m_axi_wdata(w_wdata),.m_axi_wstrb(w_wstrb),
  .m_axi_wlast(w_wlast),.m_axi_wvalid(w_wvalid),.m_axi_wready(w_wready),.m_axi_bresp(w_bresp),.m_axi_bvalid(w_bvalid),.m_axi_bready(w_bready));

 axi128_memory_bfm_v1 #(.PORTS(2)) mem(.clk(clk),.rst_n(rst_n),
  .araddr({w_araddr,r_araddr}),.arlen({w_arlen,r_arlen}),.arsize({w_arsize,r_arsize}),.arburst({w_arburst,r_arburst}),
  .arvalid({w_arvalid,r_arvalid}),.arready({w_arready,r_arready}),
  .rdata({w_rdata,r_rdata}),.rresp({w_rresp,r_rresp}),.rlast({w_rlast,r_rlast}),.rvalid({w_rvalid,r_rvalid}),.rready({w_rready,r_rready}),
  .awaddr({w_awaddr,r_awaddr}),.awlen({w_awlen,r_awlen}),.awsize({w_awsize,r_awsize}),.awburst({w_awburst,r_awburst}),
  .awvalid({w_awvalid,r_awvalid}),.awready({w_awready,r_awready}),
  .wdata({w_wdata,r_wdata}),.wstrb({w_wstrb,r_wstrb}),.wlast({w_wlast,r_wlast}),.wvalid({w_wvalid,r_wvalid}),.wready({w_wready,r_wready}),
  .bresp({w_bresp,r_bresp}),.bvalid({w_bvalid,r_bvalid}),.bready({w_bready,r_bready}),
  .inject_read_error(1'b0),.inject_write_error(1'b0),
  .read_bursts(),.write_bursts(),.read_beats(),.write_beats());

 task load_cmd(input [1:0] kind,input st,input [31:0] addr,input [15:0] row,input [15:0] col,input [1:0] enc,input [15:0] mat);
 begin
  @(negedge clk);ld_valid=1;ld_kind=kind;ld_stage=st;ld_address=addr;ld_brow=row;ld_bcol=col;ld_enc=enc;ld_matrix=mat;
  @(posedge clk);while(!ld_ready)@(posedge clk);
  @(negedge clk);ld_valid=0;
 end endtask

 initial begin
  errs=0;
  // A values: row-major 16-bit pattern
  for(i=0;i<1024;i=i+1)begin expA[i]=i*17+3;mem.memory[i*2]=expA[i][7:0];mem.memory[i*2+1]=expA[i][15:8];end
  for(i=0;i<1024;i=i+1)expC[i]={32'd0,i[15:0]};
  rst_n=0;repeat(6)@(negedge clk);rst_n=1;repeat(3)@(negedge clk);
  // A load (AXI read master) concurrent with C streamed write (AXI write master)
  fork
   load_cmd(0,0,A_BASE,0,0,0,11);
   begin
    for(r=0;r<32;r=r+1)for(h=0;h<2;h=h+1)begin
     cseg_addr=C_BASE+r*192+h*96;cseg_row=0;cseg_col=0;cseg_beats=6;
     @(negedge clk);cseg_valid=1;@(posedge clk);while(!cseg_ready)@(posedge clk);@(negedge clk);cseg_valid=0;
     for(g=0;g<4;g=g+1)begin
      cval_data=0;
      for(v=0;v<4;v=v+1)cval_data[v*48+:48]=expC[r*32+h*16+g*4+v];
      cval_last=(g==3);
      @(negedge clk);cval_valid=1;@(posedge clk);while(!cval_ready)@(posedge clk);@(negedge clk);cval_valid=0;
     end
    end
   end
  join
  wait(sa_r[0]);wait(cwr_idle);repeat(10)@(negedge clk);
  // A bank check
  for(h=0;h<2;h=h+1)for(r=0;r<32;r=r+1)begin
   // use one k at a time; a_k per row
   for(i=0;i<32;i=i+1)begin
    rd_stage=0;rd_rh=h;rd_ch=0;
    for(c=0;c<16;c=c+1)a_k[c*5+:5]=i;
    #1;
    for(c=0;c<16;c=c+1)if(a_values[c*16+:16]!==expA[(h*16+c)*32+i])begin
     if(errs<5)$display("FAIL A h=%0d r=%0d k=%0d got=%h exp=%h",h,c,i,a_values[c*16+:16],expA[(h*16+c)*32+i]);
     errs=errs+1;
    end
   end
  end
  // C memory check
  for(i=0;i<1024;i=i+1)for(v=0;v<6;v=v+1)
   if(mem.memory[(C_BASE-BASE)+i*6+v]!==expC[i][v*8+:8])begin
    if(errs<5)$display("FAIL C i=%0d v=%0d got=%h exp=%h",i,v,mem.memory[(C_BASE-BASE)+i*6+v],expC[i][v*8+:8]);
    errs=errs+1;
   end
  $display("INFO AXI rd_bursts=%0d wr_bursts=%0d rd_bytes=%0d wr_bytes=%0d errs=%0d",rd_bursts,wr_bursts,rd_bytes,wr_bytes,errs);
  if(errs!=0)$fatal(1,"tb_storage_axi errs");
  $display("PASS tb_storage_axi (original axi_dma_v019 + AXI128 BFM)");
  $finish;
 end
 initial begin #2000000;$fatal(1,"timeout");end
endmodule
