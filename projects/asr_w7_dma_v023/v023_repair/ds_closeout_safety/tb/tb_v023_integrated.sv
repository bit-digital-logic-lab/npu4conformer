`timescale 1ns/1ps
// Integrated V0.23 superplan testbench.
// The host performs CSR writes only (plan base + one START).  After START all
// node fetches and data DMA are issued by the PL graph/matrix/vector/layout
// blocks through the shared AXI port.  The BFM is preloaded once.
module tb_v023_integrated;
 localparam integer MAX_CYCLES = 400000;
 reg clk = 0;
 always #4 clk = ~clk;
 reg rst_n = 0;

 // CSR
 reg [23:0] awaddr = 0; reg awvalid = 0; wire awready;
 reg [31:0] wdata = 0; reg [3:0] wstrb = 0; reg wvalid = 0; wire wready;
 wire [1:0] bresp; wire bvalid; reg bready = 1;
 reg [23:0] araddr = 0; reg arvalid = 0; wire arready;
 wire [31:0] rdata; wire [1:0] rresp; wire rvalid; reg rready = 1;

 // data AXI
 wire [39:0] m_araddr; wire [7:0] m_arlen; wire [2:0] m_arsize;
 wire [1:0] m_arburst; wire m_arvalid; wire m_arready;
 wire [127:0] m_rdata; wire [1:0] m_rresp; wire m_rlast, m_rvalid; wire m_rready;
 wire [39:0] m_awaddr; wire [7:0] m_awlen; wire [2:0] m_awsize;
 wire [1:0] m_awburst; wire m_awvalid; wire m_awready;
 wire [127:0] m_wdata; wire [15:0] m_wstrb; wire m_wlast, m_wvalid; wire m_wready;
 wire [1:0] m_bresp; wire m_bvalid; wire m_bready;

 // status
 wire busy, done, fault, irq, drain_timeout;
 wire [7:0] error_code;
 wire [31:0] completed, last_node;
 wire [63:0] cycles;
 wire seq_active, vector_busy, layout_busy, matrix_busy;
 wire [7:0] matrix_error;
 wire [63:0] matrix_cycles;
 wire [31:0] matrix_compute_cycles;
 wire [63:0] vector_cycles, layout_cycles;
 wire [31:0] vector_read_bytes, vector_write_bytes, layout_read_bytes, layout_write_bytes;
 wire [31:0] rd_bursts, wr_bursts, r_beats, w_beats;
 wire [31:0] rd_peak, wr_peak, rd_stall_cycles, wr_stall_cycles, axi_tag_errors;

 integer cyc = 0;
 integer timeout = 200000;
 integer trace_fd = 0;
 reg [1023:0] memfile, outfile, tracefile;
 integer i, j;
 reg [31:0] plan_base;
 reg [31:0] val;
 integer errors = 0;
 integer trace_en = 0;
 integer allow_fault = 0;
 integer expect_error = -1;
 wire done_latch = dut.csr.done_latched;

 // BFM: one shared AXI128 slave port, sparse model windows.
 wire [31:0] bfm_rb, bfm_wb, bfm_rbeats, bfm_wbeats;
 wc_graph_bfm #(.PORTS(1),.PROTECT_PARAM(1)) bfm (
  .clk(clk),.rst_n(rst_n),
  .araddr(m_araddr),.arlen(m_arlen),.arsize(m_arsize),.arburst(m_arburst),
  .arvalid(m_arvalid),.arready(m_arready),
  .rdata(m_rdata),.rresp(m_rresp),.rlast(m_rlast),.rvalid(m_rvalid),.rready(m_rready),
  .awaddr(m_awaddr),.awlen(m_awlen),.awsize(m_awsize),.awburst(m_awburst),
  .awvalid(m_awvalid),.awready(m_awready),
  .wdata(m_wdata),.wstrb(m_wstrb),.wlast(m_wlast),.wvalid(m_wvalid),.wready(m_wready),
  .bresp(m_bresp),.bvalid(m_bvalid),.bready(m_bready),
  .inject_read_error(1'b0),.inject_write_error(1'b0),
  .read_bursts(bfm_rb),.write_bursts(bfm_wb),.read_beats(bfm_rbeats),.write_beats(bfm_wbeats)
 );

 v023_integrated_top #(
  .PIPE_STAGES(4),.MAX_PREFETCH(16),.USE_APPROX_DIV_SQRT(0),
  .MATRIX_WATCHDOG(200000),.VEC_WATCHDOG(200000),.LAY_WATCHDOG(200000)
 ) dut (
  .clk(clk),.rst_n(rst_n),
  .s_axi_awaddr(awaddr),.s_axi_awvalid(awvalid),.s_axi_awready(awready),
  .s_axi_wdata(wdata),.s_axi_wstrb(wstrb),.s_axi_wvalid(wvalid),.s_axi_wready(wready),
  .s_axi_bresp(bresp),.s_axi_bvalid(bvalid),.s_axi_bready(bready),
  .s_axi_araddr(araddr),.s_axi_arvalid(arvalid),.s_axi_arready(arready),
  .s_axi_rdata(rdata),.s_axi_rresp(rresp),.s_axi_rvalid(rvalid),.s_axi_rready(rready),
  .m_araddr(m_araddr),.m_arlen(m_arlen),.m_arsize(m_arsize),.m_arburst(m_arburst),
  .m_arvalid(m_arvalid),.m_arready(m_arready),
  .m_rdata(m_rdata),.m_rresp(m_rresp),.m_rlast(m_rlast),.m_rvalid(m_rvalid),.m_rready(m_rready),
  .m_awaddr(m_awaddr),.m_awlen(m_awlen),.m_awsize(m_awsize),.m_awburst(m_awburst),
  .m_awvalid(m_awvalid),.m_awready(m_awready),
  .m_wdata(m_wdata),.m_wstrb(m_wstrb),.m_wlast(m_wlast),.m_wvalid(m_wvalid),.m_wready(m_wready),
  .m_bresp(m_bresp),.m_bvalid(m_bvalid),.m_bready(m_bready),
  .busy(busy),.done(done),.fault(fault),.irq(irq),.drain_timeout(drain_timeout),
  .error_code(error_code),.completed(completed),.last_node(last_node),.cycles(cycles),
  .seq_active(seq_active),.vector_busy(vector_busy),.layout_busy(layout_busy),
  .matrix_busy(matrix_busy),.matrix_error(matrix_error),.matrix_cycles(matrix_cycles),
  .matrix_compute_cycles(matrix_compute_cycles),
  .vector_cycles(vector_cycles),.layout_cycles(layout_cycles),
  .vector_read_bytes(vector_read_bytes),.vector_write_bytes(vector_write_bytes),
  .layout_read_bytes(layout_read_bytes),.layout_write_bytes(layout_write_bytes),
  .rd_bursts(rd_bursts),.wr_bursts(wr_bursts),.r_beats(r_beats),.w_beats(w_beats),
  .rd_peak(rd_peak),.wr_peak(wr_peak),.rd_stall_cycles(rd_stall_cycles),
  .wr_stall_cycles(wr_stall_cycles),.axi_tag_errors(axi_tag_errors)
 );

 task csr_write(input [23:0] a, input [31:0] d);
 begin
  @(posedge clk); awaddr <= a; wdata <= d; wstrb <= 4'hf; awvalid <= 1; wvalid <= 1;
  while (!(awready && wready)) @(posedge clk);
  @(posedge clk); awvalid <= 0; wvalid <= 0;
  while (!bvalid) @(posedge clk);
  @(posedge clk);
 end
 endtask

 task csr_read(input [23:0] a, output [31:0] d);
 begin
  @(posedge clk); araddr <= a; arvalid <= 1;
  while (!arready) @(posedge clk);
  @(posedge clk); arvalid <= 0;
  while (!rvalid) @(posedge clk);
  d = rdata;
  @(posedge clk);
 end
 endtask

 // per-cycle trace (real handshakes, no estimated activity)
 always @(posedge clk) begin
  if (rst_n && trace_fd != 0 && trace_en != 0) begin
   $fwrite(trace_fd, "%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d\n",
    cyc,
    m_arvalid,m_arready,m_rvalid,m_rready,m_rlast,m_awvalid,m_awready,m_wvalid,m_wready,m_wlast,m_bvalid,m_bready,
    dut.xbar.ar_count,dut.xbar.aw_count,dut.xbar.b_count,
    dut.xbar.rd_grant,dut.xbar.ar_owner,dut.xbar.ar_left_now,dut.xbar.wr_grant,dut.xbar.aw_owner,dut.xbar.aw_left_now,dut.xbar.b_owner,
    dut.xbar.rd_bursts,dut.xbar.wr_bursts,dut.xbar.r_beats,dut.xbar.w_beats,
    busy,done,fault,matrix_busy,vector_busy,layout_busy,dut.matrix.st,
    m_wstrb,dut.graph.sf_req_valid,dut.matrix.qreq,dut.graph.vr_arvalid,dut.graph.lr_arvalid,dut.graph.vw_awvalid
   );
   if (m_arvalid && m_arready)
    $fwrite(trace_fd, "AR,%0d,%0d,%h,%0d\n", cyc, dut.xbar.rd_grant-1, m_araddr, m_arlen);
   if (m_awvalid && m_awready)
    $fwrite(trace_fd, "AW,%0d,%0d,%h,%0d\n", cyc, dut.xbar.wr_grant-1, m_awaddr, m_awlen);
   if (cyc % 200 == 0) $fflush(trace_fd);
  end
 end

 initial begin
  if (!$value$plusargs("memfile=%s", memfile)) memfile = "fixtures/mem_integrated.hex";
  if (!$value$plusargs("outfile=%s", outfile)) outfile = "logs/integrated_out.hex";
  if (!$value$plusargs("trace=%s", tracefile)) tracefile = "traces/integrated_trace.csv";
  if (!$value$plusargs("trace_enable=%d", trace_en)) trace_en = 0;
  if (!$value$plusargs("allow_fault=%d", allow_fault)) allow_fault = 0;
  if (!$value$plusargs("expect_error=%d", expect_error)) expect_error = -1;
  if (!$value$plusargs("plan=%d", plan_base)) plan_base = 32'h10008000;
  if (!$value$plusargs("watchdog=%d", timeout)) timeout = timeout;
  trace_fd = $fopen(tracefile, "w");
  $fwrite(trace_fd, "cycle,arv,arr,rv,rready,rlast,awv,awr,wv,wr,wlast,bv,br,ar_count,aw_count,b_count,rd_grant,ar_owner,ar_left,wr_grant,aw_owner,aw_left,b_owner,rd_bursts,wr_bursts,r_beats,w_beats,busy,done,fault,matrix_busy,vector_busy,layout_busy,matrix_st,wstrb,sf_req_v,qreq,vr_arvalid,lr_arvalid,vw_awvalid\n");
  rst_n = 0;
  repeat (12) @(posedge clk);
  rst_n = 1;
  repeat (5) @(posedge clk);
  // Host: only plan pointer + one START, then wait for IRQ.
  $display("HOST write plan_base=%h", plan_base);
  csr_write(24'h08, plan_base);
  $display("HOST plan_base written");
  csr_write(24'h0c, 32'd1);
  $display("HOST plan_count written");
  csr_write(24'h10, 32'd1);
  $display("HOST START written at cycle %0d", cyc);
  while (!done && !fault && cyc < timeout) begin
   @(posedge clk);
   if (cyc % 2000 == 0) $display("WAIT cycle=%0d busy=%0d mat=%0d vec=%0d lay=%0d mst=%0d mcore=%0d mdone=%0d merr=%02x mcomp=%0d mrb=%0d mwb=%0d ar=%0d own=%0d left=%0d rv=%0d rr=%0d",
     cyc, busy, matrix_busy, vector_busy, layout_busy, dut.matrix.st, dut.matrix.core_busy, dut.matrix.core_done, matrix_error,
     matrix_compute_cycles, dut.matrix.telem_rb, dut.matrix.telem_wb, dut.xbar.ar_count, dut.xbar.ar_owner, dut.xbar.ar_left_now, m_rvalid, m_rready);
  end
  repeat (10) @(posedge clk);

  csr_read(24'h04, val);
  $display("INTEGRATED_STATUS busy=%0d done=%0d fault=%0d err=%02x cycles=%0d completed=%0d last=%0d",
           busy, done_latch, fault, error_code, cycles, completed, last_node);
  $display("INTEGRATED_MATRIX cycles=%0d compute=%0d err=%02x", matrix_cycles, matrix_compute_cycles, matrix_error);
  $display("INTEGRATED_VECLAY vcyc=%0d lcyc=%0d vrb=%0d vwb=%0d lrb=%0d lwb=%0d",
           vector_cycles, layout_cycles, vector_read_bytes, vector_write_bytes,
           layout_read_bytes, layout_write_bytes);
  $display("INTEGRATED_AXI rburst=%0d wburst=%0d rbeats=%0d wbeats=%0d rdpeak=%0d wrpeak=%0d rdstall=%0d wrstall=%0d tag_err=%0d bfm_rbeats=%0d bfm_wbeats=%0d",
           rd_bursts, wr_bursts, r_beats, w_beats, rd_peak, wr_peak,
           rd_stall_cycles, wr_stall_cycles, axi_tag_errors, bfm_rbeats, bfm_wbeats);
  $display("INTEGRATED_END done=%0d fault=%0d error=%02x cycle=%0d", done_latch, fault, error_code, cyc);

  // Dump the final layout output (1024 x i16 at 0x04008000 -> word 0x12000).
  begin : dump
   integer fd;
   fd = $fopen(outfile, "w");
   for (i = 0; i < 512; i = i + 1)
     $fwrite(fd, "%08x\n", bfm.memw[32'h12000 + i]);
   $fclose(fd);
  end
  $fclose(trace_fd);
  begin : dump_stages
   integer fd2,k;
   fd2 = $fopen("logs/stage_c48.hex","w");
   for (k=0;k<1536;k=k+1) $fwrite(fd2,"%08x\n",bfm.memw[32'h10800+k]);
   $fclose(fd2);
   fd2 = $fopen("logs/stage_d0.hex","w");
   for (k=0;k<1024;k=k+1) $fwrite(fd2,"%08x\n",bfm.memw[32'h11000+k]);
   $fclose(fd2);
   fd2 = $fopen("logs/stage_d1.hex","w");
   for (k=0;k<1024;k=k+1) $fwrite(fd2,"%08x\n",bfm.memw[32'h11400+k]);
   $fclose(fd2);
   fd2 = $fopen("logs/stage_d2.hex","w");
   for (k=0;k<1024;k=k+1) $fwrite(fd2,"%08x\n",bfm.memw[32'h11800+k]);
   $fclose(fd2);
   fd2 = $fopen("logs/stage_i16.hex","w");
   for (k=0;k<512;k=k+1) $fwrite(fd2,"%08x\n",bfm.memw[32'h11c00+k]);
   $fclose(fd2);
  end
  if (allow_fault) begin
   if (!fault || !done_latch) errors = errors + 1;
   if (expect_error >= 0 && error_code != expect_error[7:0]) errors = errors + 1;
  end else if (fault || !done_latch) errors = errors + 1;
  if (cyc >= timeout) errors = errors + 1;
  if (errors) $display("INTEGRATED_RESULT FAIL errors=%0d", errors);
  else $display("INTEGRATED_RESULT PASS");
  $finish;
 end


 always @(posedge clk) begin
  cyc <= cyc + 1;
  if (cyc > timeout + 1000) begin
   $display("INTEGRATED_TIMEOUT cycle=%0d busy=%0d fault=%0d err=%02x", cyc, busy, fault, error_code);
   $finish;
  end
 end
endmodule
