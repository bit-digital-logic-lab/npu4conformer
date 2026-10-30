`timescale 1ns/1ps
// Exact sealed-RTL baseline chain (host-sequenced, not PL-autonomous).
// Same fixture, same BFM, same shared AXI port as the integrated candidate.
// It runs the same 7 descriptors: LAY(A), LAY(W), VEC(I48->F32), VEC(MUL),
// VEC(ADD), VEC(F32->I16), LAY(final copy).  This provides the same-load
// exact baseline for output/cycles/traffic; the integrated candidate is the
// PL-autonomous superplan path.
module tb_v023_baseline_chain;
 localparam integer MAX_CYCLES = 200000;
 reg clk=0; always #4 clk=~clk;
 reg rst_n=0;
 integer cyc=0, i, k;
 reg [1023:0] memfile, outfile;
 integer errors=0;

 // Shared AXI
 wire [39:0] s_araddr; wire [7:0] s_arlen; wire [2:0] s_arsize; wire [1:0] s_arburst;
 wire s_arvalid, s_arready; wire [127:0] s_rdata; wire [1:0] s_rresp; wire s_rlast,s_rvalid,s_rready;
 wire [39:0] s_awaddr; wire [7:0] s_awlen; wire [2:0] s_awsize; wire [1:0] s_awburst;
 wire s_awvalid, s_awready; wire [127:0] s_wdata; wire [15:0] s_wstrb; wire s_wlast,s_wvalid,s_wready;
 wire [1:0] s_bresp; wire s_bvalid,s_bready;

 wire [1:0] xr_arvalid, xr_arready; wire [1*40:0] dummy0;
 wire [2*40-1:0] xr_araddr; wire [2*8-1:0] xr_arlen; wire [2*3-1:0] xr_arsize; wire [2*2-1:0] xr_arburst;
 wire [2*128-1:0] xr_rdata; wire [2*2-1:0] xr_rresp; wire [1:0] xr_rlast,xr_rvalid,xr_rready;
 wire [1:0] xw_awvalid,xw_awready; wire [2*40-1:0] xw_awaddr; wire [2*8-1:0] xw_awlen;
 wire [2*3-1:0] xw_awsize; wire [2*2-1:0] xw_awburst; wire [2*128-1:0] xw_wdata;
 wire [2*16-1:0] xw_wstrb; wire [1:0] xw_wlast,xw_wvalid,xw_wready,xw_bready;
 wire [2*2-1:0] xw_bresp; wire [1:0] xw_bvalid;
 wire [31:0] xrdb,xwrb,xrb,xwb,xrp,xwp,xrds,xwrs,xte;

 // Vector AXI
 wire [39:0] v_araddr; wire [7:0] v_arlen; wire [2:0] v_arsize; wire [1:0] v_arburst;
 wire v_arvalid,v_arready,v_rlast,v_rvalid,v_rready; wire [127:0] v_rdata; wire [1:0] v_rresp;
 wire [39:0] v_awaddr; wire [7:0] v_awlen; wire [2:0] v_awsize; wire [1:0] v_awburst;
 wire v_awvalid,v_awready,v_wlast,v_wvalid,v_wready; wire [127:0] v_wdata; wire [15:0] v_wstrb;
 wire [1:0] v_bresp; wire v_bvalid,v_bready;
 // Layout AXI
 wire [39:0] l_araddr; wire [7:0] l_arlen; wire [2:0] l_arsize; wire [1:0] l_arburst;
 wire l_arvalid,l_arready,l_rlast,l_rvalid,l_rready; wire [127:0] l_rdata; wire [1:0] l_rresp;
 wire [39:0] l_awaddr; wire [7:0] l_awlen; wire [2:0] l_awsize; wire [1:0] l_awburst;
 wire l_awvalid,l_awready,l_wlast,l_wvalid,l_wready; wire [127:0] l_wdata; wire [15:0] l_wstrb;
 wire [1:0] l_bresp; wire l_bvalid,l_bready;

 reg v_start=0,l_start=0;
 reg [511:0] v_desc=0; reg [1023:0] l_desc=0;
 wire v_ready,v_busy,v_done,v_fault; wire [7:0] v_error,v_flags;
 wire [31:0] v_elems,v_rej; wire [63:0] v_cycles,v_ro,v_wo;
 wire [31:0] v_rb,v_wb,v_rburst,v_wburst;
 wire l_ready,l_busy,l_done,l_fault; wire [7:0] l_error;
 wire [31:0] l_elems,l_rej,l_hits,l_misses; wire [63:0] l_cycles;
 wire [31:0] l_rb,l_wb,l_rburst,l_wburst;

 integer vcyc[0:3]; integer lcyc[0:2];

 // BFM
 wire [31:0] brb,bwb,rbe,wbe;
 wc_graph_bfm #(.PORTS(1),.PROTECT_PARAM(1)) bfm(
  .clk(clk),.rst_n(rst_n),
  .araddr(s_araddr),.arlen(s_arlen),.arsize(s_arsize),.arburst(s_arburst),
  .arvalid(s_arvalid),.arready(s_arready),.rdata(s_rdata),.rresp(s_rresp),
  .rlast(s_rlast),.rvalid(s_rvalid),.rready(s_rready),
  .awaddr(s_awaddr),.awlen(s_awlen),.awsize(s_awsize),.awburst(s_awburst),
  .awvalid(s_awvalid),.awready(s_awready),.wdata(s_wdata),.wstrb(s_wstrb),
  .wlast(s_wlast),.wvalid(s_wvalid),.wready(s_wready),.bresp(s_bresp),
  .bvalid(s_bvalid),.bready(s_bready),.inject_read_error(1'b0),.inject_write_error(1'b0),
  .read_bursts(brb),.write_bursts(bwb),.read_beats(rbe),.write_beats(wbe));

 v023_axi_shared #(.NR(2),.NW(2)) xbar(
  .clk(clk),.rst_n(rst_n),
  .m_arvalid(xr_arvalid),.m_arready(xr_arready),.m_araddr(xr_araddr),.m_arlen(xr_arlen),
  .m_arsize(xr_arsize),.m_arburst(xr_arburst),.m_rdata(xr_rdata),.m_rresp(xr_rresp),
  .m_rlast(xr_rlast),.m_rvalid(xr_rvalid),.m_rready(xr_rready),
  .s_araddr(s_araddr),.s_arlen(s_arlen),.s_arsize(s_arsize),.s_arburst(s_arburst),
  .s_arvalid(s_arvalid),.s_arready(s_arready),.s_rdata(s_rdata),.s_rresp(s_rresp),
  .s_rlast(s_rlast),.s_rvalid(s_rvalid),.s_rready(s_rready),
  .m_awvalid(xw_awvalid),.m_awready(xw_awready),.m_awaddr(xw_awaddr),.m_awlen(xw_awlen),
  .m_awsize(xw_awsize),.m_awburst(xw_awburst),.m_wdata(xw_wdata),.m_wstrb(xw_wstrb),
  .m_wlast(xw_wlast),.m_wvalid(xw_wvalid),.m_wready(xw_wready),.m_bready(xw_bready),
  .m_bresp(xw_bresp),.m_bvalid(xw_bvalid),
  .s_awaddr(s_awaddr),.s_awlen(s_awlen),.s_awsize(s_awsize),.s_awburst(s_awburst),
  .s_awvalid(s_awvalid),.s_awready(s_awready),.s_wdata(s_wdata),.s_wstrb(s_wstrb),
  .s_wlast(s_wlast),.s_wvalid(s_wvalid),.s_wready(s_wready),.s_bresp(s_bresp),
  .s_bvalid(s_bvalid),.s_bready(s_bready),
  .rd_bursts(xrdb),.wr_bursts(xwrb),.r_beats(xrb),.w_beats(xwb),.rd_peak(xrp),.wr_peak(xwp),
  .rd_stall_cycles(xrds),.wr_stall_cycles(xwrs),.tag_errors(xte));

 // vector master 0, layout master 1
 assign xr_arvalid[0]=v_arvalid; assign xr_araddr[0*40+:40]=v_araddr; assign xr_arlen[0*8+:8]=v_arlen;
 assign xr_arsize[0*3+:3]=v_arsize; assign xr_arburst[0*2+:2]=v_arburst; assign v_arready=xr_arready[0];
 assign v_rdata=xr_rdata[0*128+:128]; assign v_rresp=xr_rresp[0*2+:2]; assign v_rlast=xr_rlast[0];
 assign v_rvalid=xr_rvalid[0]; assign xr_rready[0]=v_rready;
 assign xr_arvalid[1]=l_arvalid; assign xr_araddr[1*40+:40]=l_araddr; assign xr_arlen[1*8+:8]=l_arlen;
 assign xr_arsize[1*3+:3]=l_arsize; assign xr_arburst[1*2+:2]=l_arburst; assign l_arready=xr_arready[1];
 assign l_rdata=xr_rdata[1*128+:128]; assign l_rresp=xr_rresp[1*2+:2]; assign l_rlast=xr_rlast[1];
 assign l_rvalid=xr_rvalid[1]; assign xr_rready[1]=l_rready;
 assign xw_awvalid[0]=v_awvalid; assign xw_awaddr[0*40+:40]=v_awaddr; assign xw_awlen[0*8+:8]=v_awlen;
 assign xw_awsize[0*3+:3]=v_awsize; assign xw_awburst[0*2+:2]=v_awburst; assign v_awready=xw_awready[0];
 assign xw_wdata[0*128+:128]=v_wdata; assign xw_wstrb[0*16+:16]=v_wstrb; assign xw_wlast[0]=v_wlast;
 assign xw_wvalid[0]=v_wvalid; assign v_wready=xw_wready[0]; assign v_bvalid=xw_bvalid[0];
 assign v_bresp=xw_bresp[0*2+:2]; assign xw_bready[0]=v_bready;
 assign xw_awvalid[1]=l_awvalid; assign xw_awaddr[1*40+:40]=l_awaddr; assign xw_awlen[1*8+:8]=l_awlen;
 assign xw_awsize[1*3+:3]=l_awsize; assign xw_awburst[1*2+:2]=l_awburst; assign l_awready=xw_awready[1];
 assign xw_wdata[1*128+:128]=l_wdata; assign xw_wstrb[1*16+:16]=l_wstrb; assign xw_wlast[1]=l_wlast;
 assign xw_wvalid[1]=l_wvalid; assign l_wready=xw_wready[1]; assign l_bvalid=xw_bvalid[1];
 assign l_bresp=xw_bresp[1*2+:2]; assign xw_bready[1]=l_bready;

 ddr_vector_axi vec(
  .clk(clk),.rst_n(rst_n),.start(v_start),.descriptor(v_desc),.param_end(32'h10040000),
  .ready(v_ready),.busy(v_busy),.done(v_done),.fault(v_fault),.error_code(v_error),
  .numeric_flags(v_flags),.completed_elements(v_elems),.rejected_starts(v_rej),
  .cycles(v_cycles),.read_compute_overlap(v_ro),.write_compute_overlap(v_wo),
  .read_bytes(v_rb),.write_bytes(v_wb),.read_bursts(v_rburst),.write_bursts(v_wburst),
  .read_m_axi_araddr(v_araddr),.read_m_axi_arlen(v_arlen),.read_m_axi_arsize(v_arsize),
  .read_m_axi_arburst(v_arburst),.read_m_axi_arcache(),.read_m_axi_arprot(),
  .read_m_axi_arvalid(v_arvalid),.read_m_axi_arready(v_arready),
  .read_m_axi_rdata(v_rdata),.read_m_axi_rresp(v_rresp),.read_m_axi_rlast(v_rlast),
  .read_m_axi_rvalid(v_rvalid),.read_m_axi_rready(v_rready),
  .read_m_axi_awaddr(),.read_m_axi_awlen(),.read_m_axi_awsize(),.read_m_axi_awburst(),
  .read_m_axi_awcache(),.read_m_axi_awprot(),.read_m_axi_awvalid(),.read_m_axi_awready(1'b1),
  .read_m_axi_wdata(),.read_m_axi_wstrb(),.read_m_axi_wlast(),.read_m_axi_wvalid(),
  .read_m_axi_wready(1'b1),.read_m_axi_bresp(2'd0),.read_m_axi_bvalid(1'b0),.read_m_axi_bready(),
  .write_m_axi_araddr(),.write_m_axi_arlen(),.write_m_axi_arsize(),.write_m_axi_arburst(),
  .write_m_axi_arcache(),.write_m_axi_arprot(),.write_m_axi_arvalid(),.write_m_axi_arready(1'b1),
  .write_m_axi_rdata(128'd0),.write_m_axi_rresp(2'd0),.write_m_axi_rlast(1'b0),
  .write_m_axi_rvalid(1'b0),.write_m_axi_rready(),
  .write_m_axi_awaddr(v_awaddr),.write_m_axi_awlen(v_awlen),.write_m_axi_awsize(v_awsize),
  .write_m_axi_awburst(v_awburst),.write_m_axi_awcache(),.write_m_axi_awprot(),
  .write_m_axi_awvalid(v_awvalid),.write_m_axi_awready(v_awready),
  .write_m_axi_wdata(v_wdata),.write_m_axi_wstrb(v_wstrb),.write_m_axi_wlast(v_wlast),
  .write_m_axi_wvalid(v_wvalid),.write_m_axi_wready(v_wready),
  .write_m_axi_bresp(v_bresp),.write_m_axi_bvalid(v_bvalid),.write_m_axi_bready(v_bready));

 ddr_layout_axi lay(
  .clk(clk),.rst_n(rst_n),.start(l_start),.descriptor(l_desc),.param_end(32'h10040000),
  .ready(l_ready),.busy(l_busy),.done(l_done),.fault(l_fault),.error_code(l_error),
  .processed_elements(l_elems),.rejected_starts(l_rej),.cache_hits(l_hits),.cache_misses(l_misses),
  .cycles(l_cycles),.read_bytes(l_rb),.write_bytes(l_wb),.read_bursts(l_rburst),.write_bursts(l_wburst),
  .read_m_axi_araddr(l_araddr),.read_m_axi_arlen(l_arlen),.read_m_axi_arsize(l_arsize),
  .read_m_axi_arburst(l_arburst),.read_m_axi_arcache(),.read_m_axi_arprot(),
  .read_m_axi_arvalid(l_arvalid),.read_m_axi_arready(l_arready),
  .read_m_axi_rdata(l_rdata),.read_m_axi_rresp(l_rresp),.read_m_axi_rlast(l_rlast),
  .read_m_axi_rvalid(l_rvalid),.read_m_axi_rready(l_rready),
  .read_m_axi_awaddr(),.read_m_axi_awlen(),.read_m_axi_awsize(),.read_m_axi_awburst(),
  .read_m_axi_awcache(),.read_m_axi_awprot(),.read_m_axi_awvalid(),.read_m_axi_awready(1'b1),
  .read_m_axi_wdata(),.read_m_axi_wstrb(),.read_m_axi_wlast(),.read_m_axi_wvalid(),
  .read_m_axi_wready(1'b1),.read_m_axi_bresp(2'd0),.read_m_axi_bvalid(1'b0),.read_m_axi_bready(),
  .write_m_axi_araddr(),.write_m_axi_arlen(),.write_m_axi_arsize(),.write_m_axi_arburst(),
  .write_m_axi_arcache(),.write_m_axi_arprot(),.write_m_axi_arvalid(),.write_m_axi_arready(1'b1),
  .write_m_axi_rdata(128'd0),.write_m_axi_rresp(2'd0),.write_m_axi_rlast(1'b0),
  .write_m_axi_rvalid(1'b0),.write_m_axi_rready(),
  .write_m_axi_awaddr(l_awaddr),.write_m_axi_awlen(l_awlen),.write_m_axi_awsize(l_awsize),
  .write_m_axi_awburst(l_awburst),.write_m_axi_awcache(),.write_m_axi_awprot(),
  .write_m_axi_awvalid(l_awvalid),.write_m_axi_awready(l_awready),
  .write_m_axi_wdata(l_wdata),.write_m_axi_wstrb(l_wstrb),.write_m_axi_wlast(l_wlast),
  .write_m_axi_wvalid(l_wvalid),.write_m_axi_wready(l_wready),
  .write_m_axi_bresp(l_bresp),.write_m_axi_bvalid(l_bvalid),.write_m_axi_bready(l_bready));

 task run_vec(input [511:0] d, output integer cyc_o);
 begin
  v_desc=d; @(negedge clk); while(!v_ready)@(negedge clk);
  v_start=1; @(negedge clk); v_start=0;
  while(!v_done)@(posedge clk);
  cyc_o=v_cycles; if(v_fault)begin $display("BASE_VEC_FAULT %02x",v_error);errors=errors+1;end
  @(posedge clk);
 end endtask

 task run_lay(input [1023:0] d, output integer cyc_o);
 begin
  l_desc=d; @(negedge clk); while(!l_ready)@(negedge clk);
  l_start=1; @(negedge clk); l_start=0;
  while(!l_done)@(posedge clk);
  cyc_o=l_cycles; if(l_fault)begin $display("BASE_LAY_FAULT %02x",l_error);errors=errors+1;end
  @(posedge clk);
 end endtask

 function [511:0] vd(input [15:0] wa, input [31:0] a,b,c,d, input [31:0] n);
 begin
  vd=512'd0; vd[31:0]=32'h22564543; vd[47:32]=wa;
  vd[95:64]=a; vd[127:96]=b; vd[159:128]=c; vd[191:160]=d; vd[223:192]=n;
 end endfunction

 function [1023:0] ld(input [31:0] mode,src,dst,total,nb);
 begin
  ld=1024'd0; ld[31:0]=32'h224c4159; ld[63:32]=mode; ld[95:64]=src; ld[127:96]=dst;
  ld[159:128]=total; ld[191:160]=nb;
 end endfunction

 initial begin
  if (!$value$plusargs("memfile=%s", memfile)) memfile="fixtures/mem_integrated.hex";
  if (!$value$plusargs("outfile=%s", outfile)) outfile="logs/baseline_out.hex";
  repeat(10)@(posedge clk); rst_n=1; repeat(4)@(posedge clk);
  run_lay(ld(0,32'h10001000,32'h04000000,1024,2), lcyc[0]);
  run_lay(ld(0,32'h10002000,32'h04001000,512,2), lcyc[1]);
  run_vec(vd(16'h200e,32'h04002000,32'h04003000,0,32'h04004000,1024), vcyc[0]);
  run_vec(vd(16'h0402,32'h04004000,32'h10000004,0,32'h04005000,1024), vcyc[1]);
  run_vec(vd(16'h0400,32'h04005000,32'h10000008,0,32'h04006000,1024), vcyc[2]);
  run_vec(vd(16'h020f,32'h04006000,0,0,32'h04007000,1024), vcyc[3]);
  run_lay(ld(0,32'h04007000,32'h04008000,1024,2), lcyc[2]);
  repeat(20)@(posedge clk);
  begin : dump
   integer fd;
   fd=$fopen(outfile,"w");
   for(i=0;i<512;i=i+1)$fwrite(fd,"%08x\n",bfm.memw[32'h12000+i]);
   $fclose(fd);
   fd=$fopen("logs/baseline_stage_i16.hex","w");
   for(i=0;i<512;i=i+1)$fwrite(fd,"%08x\n",bfm.memw[32'h11c00+i]);
   $fclose(fd);
   fd=$fopen("logs/baseline_stage_d2.hex","w");
   for(i=0;i<256;i=i+1)$fwrite(fd,"%08x\n",bfm.memw[32'h11800+i]);
   $fclose(fd);
  end
  $display("BASE_CHAIN lcyc=%0d/%0d/%0d vcyc=%0d/%0d/%0d/%0d axi rb=%0d wb=%0d rburst=%0d wburst=%0d errors=%0d",
   lcyc[0],lcyc[1],lcyc[2],vcyc[0],vcyc[1],vcyc[2],vcyc[3],rbe,wbe,xrdb,xwrb,errors);
  if(errors)$display("BASE_CHAIN_RESULT FAIL"); else $display("BASE_CHAIN_RESULT PASS");
  $finish;
 end
 always @(posedge clk) begin cyc<=cyc+1; if(cyc>MAX_CYCLES)begin $display("BASE_TIMEOUT");$finish;end end
endmodule
