`timescale 1ns/1ps
// Candidate (PL-autonomous integrated superplan) cycle harness.
// Reuses the frozen integrated snapshot RTL unchanged.  Adds:
//  * selectable shared-BFM storage latency / back-pressure (+lat_mode)
//  * host START -> done -> final write-response drain cycle accounting
//  * per-engine windows and shared-AXI stall counters
//  * a diagnosable watchdog (prints child states before $fatal)
module tb_chain_integrated;
 localparam integer MAX_CYCLES = 400000;
 reg clk = 0;
 always #4 clk = ~clk;
 reg rst_n = 0;

 reg [23:0] awaddr = 0; reg awvalid = 0; wire awready;
 reg [31:0] wdata = 0; reg [3:0] wstrb = 0; reg wvalid = 0; wire wready;
 wire [1:0] bresp; wire bvalid; reg bready = 1;
 reg [23:0] araddr = 0; reg arvalid = 0; wire arready;
 wire [31:0] rdata; wire [1:0] rresp; wire rvalid; reg rready = 1;

 wire [39:0] m_araddr; wire [7:0] m_arlen; wire [2:0] m_arsize;
 wire [1:0] m_arburst; wire m_arvalid; wire m_arready;
 wire [127:0] m_rdata; wire [1:0] m_rresp; wire m_rlast, m_rvalid; wire m_rready;
 wire [39:0] m_awaddr; wire [7:0] m_awlen; wire [2:0] m_awsize;
 wire [1:0] m_awburst; wire m_awvalid; wire m_awready;
 wire [127:0] m_wdata; wire [15:0] m_wstrb; wire m_wlast, m_wvalid; wire m_wready;
 wire [1:0] m_bresp; wire m_bvalid; wire m_bready;

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
 integer timeout = 120000;
 integer i, k;
 reg [1023:0] memfile, outfile;
 integer errors = 0;
 wire done_latch = dut.csr.done_latched;

 // BFM telemetry
 wire [31:0] bfm_rb, bfm_wb, bfm_rbeats, bfm_wbeats;
 wire [31:0] bfm_rbusy, bfm_wbusy, bfm_bwait;
 wire bfm_idle;

 axi128_bfm_scenario bfm (
  .clk(clk),.rst_n(rst_n),
  .araddr(m_araddr),.arlen(m_arlen),.arsize(m_arsize),.arburst(m_arburst),
  .arvalid(m_arvalid),.arready(m_arready),
  .rdata(m_rdata),.rresp(m_rresp),.rlast(m_rlast),.rvalid(m_rvalid),.rready(m_rready),
  .awaddr(m_awaddr),.awlen(m_awlen),.awsize(m_awsize),.awburst(m_awburst),
  .awvalid(m_awvalid),.awready(m_awready),
  .wdata(m_wdata),.wstrb(m_wstrb),.wlast(m_wlast),.wvalid(m_wvalid),.wready(m_wready),
  .bresp(m_bresp),.bvalid(m_bvalid),.bready(m_bready),
  .inject_read_error(1'b0),.inject_write_error(1'b0),
  .read_bursts(bfm_rb),.write_bursts(bfm_wb),.read_beats(bfm_rbeats),.write_beats(bfm_wbeats),
  .read_busy_cycles(bfm_rbusy),.write_busy_cycles(bfm_wbusy),.bresp_wait_cycles(bfm_bwait),
  .idle(bfm_idle)
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

 // cycle markers / engine windows / channel wait counters
 integer t_start = -1, t_done = -1, t_drain = -1;
 integer mat_first = -1, mat_last = -1, vec_first = -1, vec_last = -1, lay_first = -1, lay_last = -1;
 integer ar_wait = 0, aw_wait = 0, w_wait = 0, r_wait = 0, b_wait = 0;
 integer any_busy = 0, mat_busy_cycles = 0, vec_busy_cycles = 0, lay_busy_cycles = 0;
 integer m_ar_w=0,m_aw_w=0,m_w_w=0,m_r_w=0,m_b_w=0;
 integer v_ar_w=0,v_aw_w=0,v_w_w=0,v_r_w=0,v_b_w=0;
 integer l_ar_w=0,l_aw_w=0,l_w_w=0,l_r_w=0,l_b_w=0;
 integer f_ar_w=0,f_r_w=0, q_ar_w=0,q_r_w=0;
 reg done_seen = 0;
 always @(posedge clk) begin
  if (rst_n) begin
   if (dut.csr.start && t_start < 0) t_start = cyc;
   if (matrix_busy) begin if (mat_first < 0) mat_first = cyc; mat_last = cyc; mat_busy_cycles = mat_busy_cycles + 1; end
   if (vector_busy) begin if (vec_first < 0) vec_first = cyc; vec_last = cyc; vec_busy_cycles = vec_busy_cycles + 1; end
   if (layout_busy) begin if (lay_first < 0) lay_first = cyc; lay_last = cyc; lay_busy_cycles = lay_busy_cycles + 1; end
   if (matrix_busy || vector_busy || layout_busy || seq_active) any_busy = any_busy + 1;
   if (m_arvalid && !m_arready) ar_wait = ar_wait + 1;
   if (m_awvalid && !m_awready) aw_wait = aw_wait + 1;
   if (m_wvalid && !m_wready) w_wait = w_wait + 1;
   if (m_rvalid && !m_rready) r_wait = r_wait + 1;
   if (m_bvalid && !m_bready) b_wait = b_wait + 1;
   if (dut.mr_arvalid && !dut.mr_arready) m_ar_w = m_ar_w + 1;
   if (dut.mw_awvalid && !dut.mw_awready) m_aw_w = m_aw_w + 1;
   if (dut.mw_wvalid && !dut.mw_wready) m_w_w = m_w_w + 1;
   if (dut.mr_rvalid && !dut.mr_rready) m_r_w = m_r_w + 1;
   if (dut.mw_bvalid && !dut.mw_bready) m_b_w = m_b_w + 1;
   if (dut.vr_arvalid && !dut.vr_arready) v_ar_w = v_ar_w + 1;
   if (dut.vw_awvalid && !dut.vw_awready) v_aw_w = v_aw_w + 1;
   if (dut.vw_wvalid && !dut.vw_wready) v_w_w = v_w_w + 1;
   if (dut.vr_rvalid && !dut.vr_rready) v_r_w = v_r_w + 1;
   if (dut.vw_bvalid && !dut.vw_bready) v_b_w = v_b_w + 1;
   if (dut.lr_arvalid && !dut.lr_arready) l_ar_w = l_ar_w + 1;
   if (dut.lw_awvalid && !dut.lw_awready) l_aw_w = l_aw_w + 1;
   if (dut.lw_wvalid && !dut.lw_wready) l_w_w = l_w_w + 1;
   if (dut.lr_rvalid && !dut.lr_rready) l_r_w = l_r_w + 1;
   if (dut.lw_bvalid && !dut.lw_bready) l_b_w = l_b_w + 1;
   if (dut.sf_arvalid && !dut.sf_arready) f_ar_w = f_ar_w + 1;
   if (dut.sf_rvalid && !dut.sf_rready) f_r_w = f_r_w + 1;
   if (dut.q_arvalid && !dut.q_arready) q_ar_w = q_ar_w + 1;
   if (dut.q_rvalid && !dut.q_rready) q_r_w = q_r_w + 1;
   if (done_latch && t_done < 0) begin t_done = cyc; done_seen = 1; end
   if (done_latch && bfm_idle && dut.xbar.ar_count == 0 && dut.xbar.aw_count == 0 &&
       dut.xbar.b_count == 0 && t_drain < 0) t_drain = cyc;
  end
 end

 task diag(input [255:0] where);
 begin
  $display("WATCHDOG_FIRED at=%0s cycle=%0d t_start=%0d t_done=%0d t_drain=%0d",
           where, cyc, t_start, t_done, t_drain);
  $display("WATCHDOG_STATE rst_n=%0d busy=%0d done=%0d done_latch=%0d fault=%0d err=%02x",
           rst_n, busy, done, done_latch, fault, error_code);
  $display("WATCHDOG_GRAPH seq=%0d mat=%0d vec=%0d lay=%0d mst=%0d mcore=%0d mdone=%0d merr=%02x",
           seq_active, matrix_busy, vector_busy, layout_busy,
           dut.matrix.st, dut.matrix.core_busy, dut.matrix.core_done, matrix_error);
  $display("WATCHDOG_XBAR ar_count=%0d ar_owner=%0d ar_left=%0d aw_count=%0d aw_owner=%0d aw_left=%0d b_count=%0d b_owner=%0d",
           dut.xbar.ar_count, dut.xbar.ar_owner, dut.xbar.ar_left_now,
           dut.xbar.aw_count, dut.xbar.aw_owner, dut.xbar.aw_left_now,
           dut.xbar.b_count, dut.xbar.b_owner);
  $display("WATCHDOG_AXI arv=%0d arr=%0d rv=%0d rr=%0d rlast=%0d awv=%0d awr=%0d wv=%0d wr=%0d wlast=%0d bv=%0d br=%0d br_ready=%0d",
           m_arvalid,m_arready,m_rvalid,m_rready,m_rlast,m_awvalid,m_awready,
           m_wvalid,m_wready,m_wlast,m_bvalid,m_bready,bready);
  $display("WATCHDOG_BFM rbusy=%0d wbusy=%0d bpend=%0d idle=%0d rb=%0d wb=%0d",
           bfm.rbusy, bfm.wbusy, bfm.bpend, bfm_idle, bfm_rb, bfm_wb);
  $display("WATCHDOG_MATRIX qcyc=%0d fcyc=%0d ewait=%0d rwait=%0d comp=%0d rblk=%0d wblk=%0d",
           dut.matrix.queue_cycles, dut.matrix.fetch_cycles, dut.matrix.engine_wait_cycles,
           dut.matrix.retire_wait_cycles, matrix_compute_cycles,
           dut.matrix.read_blocks, dut.matrix.write_blocks);
  $display("CAND_RESULT FAIL watchdog");
  $fatal(1, "candidate watchdog at %0s cycle %0d", where, cyc);
 end
 endtask

 initial begin
  if (!$value$plusargs("memfile=%s", memfile)) memfile = "inputs/mem_integrated.hex";
  if (!$value$plusargs("outfile=%s", outfile)) outfile = "out.hex";
  if (!$value$plusargs("watchdog=%d", timeout)) timeout = 120000;
  rst_n = 0;
  repeat (12) @(posedge clk);
  rst_n = 1;
  repeat (5) @(posedge clk);
  $display("HOST write plan_base=%h", 32'h10008000);
  csr_write(24'h08, 32'h10008000);
  csr_write(24'h0c, 32'd1);
  $display("HOST START write begins at cycle %0d", cyc);
  csr_write(24'h10, 32'd1);
  $display("HOST START accepted at cycle %0d (monitor t_start=%0d)", cyc, t_start);

  while (!done_latch && !fault && cyc < timeout) begin
   @(posedge clk);
   if (cyc % 5000 == 0)
    $display("WAIT cycle=%0d busy=%0d mat=%0d vec=%0d lay=%0d mst=%0d mcore=%0d mdone=%0d merr=%02x ar=%0d own=%0d left=%0d rv=%0d rr=%0d",
      cyc, busy, matrix_busy, vector_busy, layout_busy, dut.matrix.st,
      dut.matrix.core_busy, dut.matrix.core_done, matrix_error,
      dut.xbar.ar_count, dut.xbar.ar_owner, dut.xbar.ar_left_now, m_rvalid, m_rready);
  end
  if (!done_latch) diag("waiting_done");

  // Wait for the final write response and all shared-port traffic to drain,
  // not merely for the graph done bit.
  while (!(bfm_idle && dut.xbar.ar_count == 0 && dut.xbar.aw_count == 0 && dut.xbar.b_count == 0) && cyc < timeout)
   @(posedge clk);
  if (!(bfm_idle && dut.xbar.ar_count == 0 && dut.xbar.aw_count == 0 && dut.xbar.b_count == 0))
   diag("waiting_drain");
  repeat (2) @(posedge clk);

  $display("CAND_TOTAL start=%0d done=%0d drain=%0d total_start_to_drain=%0d done_to_drain=%0d csr_cycles=%0d",
           t_start, t_done, t_drain, t_drain - t_start, t_drain - t_done, cycles);
  $display("CAND_WINDOW matrix=%0d..%0d (%0d) vector=%0d..%0d (%0d) layout=%0d..%0d (%0d) any_busy=%0d",
           mat_first, mat_last, mat_busy_cycles, vec_first, vec_last, vec_busy_cycles,
           lay_first, lay_last, lay_busy_cycles, any_busy);
  $display("CAND_MATRIX cycles=%0d compute=%0d queue=%0d fetch=%0d engine_wait=%0d retire_wait=%0d rblk=%0d wblk=%0d cg=%0d cc=%0d",
           matrix_cycles, matrix_compute_cycles, dut.matrix.queue_cycles, dut.matrix.fetch_cycles,
           dut.matrix.engine_wait_cycles, dut.matrix.retire_wait_cycles,
           dut.matrix.read_blocks, dut.matrix.write_blocks,
           dut.matrix.c_collect_groups, dut.matrix.c_collect_cycles);
  $display("CAND_VECLAY vcyc=%0d lcyc=%0d vrb=%0d vwb=%0d lrb=%0d lwb=%0d",
           vector_cycles, layout_cycles, vector_read_bytes, vector_write_bytes,
           layout_read_bytes, layout_write_bytes);
  $display("CAND_AXI rburst=%0d wburst=%0d rbeats=%0d wbeats=%0d rdpeak=%0d wrpeak=%0d rdstall=%0d wrstall=%0d tag_err=%0d bfm_rbeats=%0d bfm_wbeats=%0d",
           rd_bursts, wr_bursts, r_beats, w_beats, rd_peak, wr_peak,
           rd_stall_cycles, wr_stall_cycles, axi_tag_errors, bfm_rbeats, bfm_wbeats);
  $display("CAND_WAIT ar_stall=%0d aw_stall=%0d w_stall=%0d r_stall=%0d b_stall=%0d bfm_read_busy=%0d bfm_write_busy=%0d bfm_bresp_wait=%0d",
           ar_wait, aw_wait, w_wait, r_wait, b_wait, bfm_rbusy, bfm_wbusy, bfm_bwait);
  $display("CAND_ENGWAIT matrix ar=%0d aw=%0d w=%0d r=%0d b=%0d | vector ar=%0d aw=%0d w=%0d r=%0d b=%0d | layout ar=%0d aw=%0d w=%0d r=%0d b=%0d | graph_fetch ar=%0d r=%0d | queue ar=%0d r=%0d",
           m_ar_w,m_aw_w,m_w_w,m_r_w,m_b_w, v_ar_w,v_aw_w,v_w_w,v_r_w,v_b_w,
           l_ar_w,l_aw_w,l_w_w,l_r_w,l_b_w, f_ar_w,f_r_w, q_ar_w,q_r_w);
  $display("CAND_GRAPH fetch=%0d operator=%0d drain=%0d busy_cycles=%0d",
           dut.graph.ctrl.fetch_cycles, dut.graph.ctrl.operator_cycles,
           dut.graph.ctrl.drain_cycles, dut.graph.ctrl.cycles);
  $display("CAND_STATUS busy=%0d done=%0d fault=%0d err=%02x completed=%0d last=%0d",
           busy, done_latch, fault, error_code, completed, last_node);

  // Raw output dumps for independent golden checks.
  begin : dump
   integer fd;
   fd = $fopen(outfile, "w");
   for (i = 0; i < 512; i = i + 1) $fwrite(fd, "%08x\n", bfm.memw[32'h12000 + i]);
   $fclose(fd);
   fd = $fopen("stage_c48.hex","w");
   for (k = 0; k < 1536; k = k + 1) $fwrite(fd, "%08x\n", bfm.memw[32'h10800 + k]);
   $fclose(fd);
   fd = $fopen("stage_d0.hex","w");
   for (k = 0; k < 1024; k = k + 1) $fwrite(fd, "%08x\n", bfm.memw[32'h11000 + k]);
   $fclose(fd);
   fd = $fopen("stage_d1.hex","w");
   for (k = 0; k < 1024; k = k + 1) $fwrite(fd, "%08x\n", bfm.memw[32'h11400 + k]);
   $fclose(fd);
   fd = $fopen("stage_d2.hex","w");
   for (k = 0; k < 1024; k = k + 1) $fwrite(fd, "%08x\n", bfm.memw[32'h11800 + k]);
   $fclose(fd);
   fd = $fopen("stage_i16.hex","w");
   for (k = 0; k < 512; k = k + 1) $fwrite(fd, "%08x\n", bfm.memw[32'h11c00 + k]);
   $fclose(fd);
  end

  if (fault || !done_latch) errors = errors + 1;
  if (cyc >= timeout) errors = errors + 1;
  if (errors) $display("CAND_RESULT FAIL errors=%0d", errors);
  else $display("CAND_RESULT PASS");
  $finish;
 end

 always @(posedge clk) begin
  cyc <= cyc + 1;
  if (cyc > timeout + 2000) diag("global_cycle_limit");
 end
endmodule
