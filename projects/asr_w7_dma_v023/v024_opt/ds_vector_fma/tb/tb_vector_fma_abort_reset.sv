`timescale 1ns/1ps
// Abort / reset mid-op, then a new-epoch plan, for ds_vector_fma.
// Scenario 1: abort while vector_busy; wait drained abort done; snapshot the
// old D region; quiescent window (no AW/B); start plan2; old D unchanged and
// plan2 output bit-exact.
// Scenario 2: reset while vector_busy; same old-region/new-epoch checks.
module tb_vector_fma_abort_reset;
 localparam integer OLD_MAX = 8734;
 reg clk = 0;
 always #4 clk = ~clk;
 reg rst_n = 0;
 reg abort = 0;

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

 wire busy, done, fault, aborted, irq, drain_timeout;
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
 integer timeout = 1500000;
 integer scenario = 1;
 integer plan1 = 32'h10008000;
 integer plan2 = 32'h10010000;
 integer total1 = 8734;
 integer total2 = 257;
 integer d1 = 32'h0401b000;
 integer d2 = 32'h04030000;
 integer abort_after_busy = 3000;
 integer quiescent = 32;
 integer post_window = 64;
 reg [1023:0] memfile;
 reg [1023:0] dumpfile;
 reg [31:0] old_snap [0:OLD_MAX-1];
 integer errors = 0;
 integer done_cycle = -1;
 integer abort_done_cycle = -1;
 integer last_b_cycle = -1;
 integer b_count_at_abort_done = 0;
 integer b_at_done = 0;
 integer b_old = 0, aw_old = 0, b_new = 0, aw_new = 0;
 integer phase = 0; // 1 old quiescent, 2 new post-done
 integer phase_cycle = 0;
 reg done_seen = 0;
 reg saw_busy = 0;
 integer busy_count = 0;
 integer fd;
 integer k, off;

 wire done_latch = dut.csr.done_latched;

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
  .MATRIX_WATCHDOG(500000),.VEC_WATCHDOG(2000000),.LAY_WATCHDOG(200000)
 ) dut (
  .clk(clk),.rst_n(rst_n),.abort(abort),
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
  .busy(busy),.done(done),.fault(fault),.aborted(aborted),.irq(irq),.drain_timeout(drain_timeout),
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

 function integer mem_word(input [31:0] addr);
 begin
  if (addr >= 32'h04000000 && addr < 32'h04040000)
   mem_word = (32'h00040000 + (addr - 32'h04000000)) >> 2;
  else if (addr >= 32'h08000000 && addr < 32'h08040000)
   mem_word = (32'h00080000 + (addr - 32'h08000000)) >> 2;
  else if (addr >= 32'h10000000 && addr < 32'h10040000)
   mem_word = (32'h000c0000 + (addr - 32'h10000000)) >> 2;
  else mem_word = -1;
 end
 endfunction

 task snapshot_old;
 begin
  off = mem_word(d1);
  for (k=0;k<total1;k=k+1) old_snap[k] = bfm.memw[off+k];
 end
 endtask

 task dump_region(input [31:0] base, input integer n, input [1023:0] name);
 begin
  off = mem_word(base);
  fd = $fopen(name, "w");
  for (k=0;k<n;k=k+1) $fwrite(fd, "%08x\n", bfm.memw[off+k]);
  $fclose(fd);
 end
 endtask

 always @(posedge clk) begin
  if (rst_n) begin
   if (m_bvalid && m_bready) last_b_cycle = cyc;
   if (vector_busy && !saw_busy) begin saw_busy = 1; busy_count = 0; end
   else if (saw_busy) busy_count = busy_count + 1;
   if (!done_latch) done_seen = 0;
   else if (!done_seen) begin done_seen = 1; done_cycle = cyc; b_at_done = dut.xbar.b_count; end
   if (phase == 1 && cyc > phase_cycle) begin
    if (m_bvalid && m_bready) b_old = b_old + 1;
    if (m_awvalid && m_awready) aw_old = aw_old + 1;
   end
   if (phase == 2 && cyc > phase_cycle) begin
    if (m_bvalid && m_bready) b_new = b_new + 1;
    if (m_awvalid && m_awready) aw_new = aw_new + 1;
   end
  end
 end

 initial begin
  if (!$value$plusargs("memfile=%s", memfile)) memfile = "fixtures/cases/abort_newepoch/mem.hex";
  if (!$value$plusargs("scenario=%d", scenario)) scenario = 1;
  if (!$value$plusargs("plan1=%d", plan1)) plan1 = 32'h10008000;
  if (!$value$plusargs("plan2=%d", plan2)) plan2 = 32'h10010000;
  if (!$value$plusargs("total1=%d", total1)) total1 = 8734;
  if (!$value$plusargs("total2=%d", total2)) total2 = 257;
  if (!$value$plusargs("d1=%d", d1)) d1 = 32'h0401b000;
  if (!$value$plusargs("d2=%d", d2)) d2 = 32'h04030000;
  if (!$value$plusargs("abort_after_busy=%d", abort_after_busy)) abort_after_busy = 3000;
  if (!$value$plusargs("watchdog=%d", timeout)) timeout = 1500000;
  if (!$value$plusargs("dump=%s", dumpfile)) dumpfile = "logs/newepoch.hex";

  rst_n = 0;
  repeat (12) @(posedge clk);
  rst_n = 1;
  repeat (5) @(posedge clk);

  csr_write(24'h08, plan1);
  csr_write(24'h0c, 32'd1);
  csr_write(24'h10, 32'd1);
  $display("HOST plan1 START cycle=%0d", cyc);

  while (!saw_busy && !done_latch && !fault && cyc < timeout) @(posedge clk);
  while (busy_count < abort_after_busy && !done_latch && !fault && cyc < timeout) @(posedge clk);

  if (scenario == 1) begin
   abort = 1;
   $display("HOST abort asserted cycle=%0d vector_busy=%0d busy_count=%0d", cyc, vector_busy, busy_count);
   repeat (4) @(posedge clk);
   abort = 0;
   while (!done_latch && !fault && cyc < timeout) @(posedge clk);
   repeat (4) @(posedge clk);
   abort_done_cycle = done_cycle;
   b_count_at_abort_done = dut.xbar.b_count;
   $display("HOST abort-drain done=%0d abort_done=%0d fault=%0d err=%02x cycle=%0d done_cycle=%0d last_b=%0d b_count=%0d",
            done_latch, aborted, fault, error_code, cyc, done_cycle, last_b_cycle, b_count_at_abort_done);
   if (!aborted) begin $display("CHECK_FAIL abort_done not set"); errors=errors+1; end
   if (fault) begin $display("CHECK_FAIL abort fault err=%02x", error_code); errors=errors+1; end
   if (last_b_cycle < 0 || last_b_cycle >= done_cycle) begin
    $display("CHECK_FAIL abort last_b=%0d done=%0d", last_b_cycle, done_cycle); errors=errors+1;
   end
   snapshot_old;
   phase = 1; phase_cycle = cyc;
   repeat (quiescent) @(posedge clk);
   phase = 0;
   $display("HOST abort-quiescent aw=%0d b=%0d", aw_old, b_old);
   if (aw_old != 0 || b_old != 0) begin
    $display("CHECK_FAIL abort quiescent aw=%0d b=%0d", aw_old, b_old); errors=errors+1;
   end
  end else begin
   rst_n = 0;
   $display("HOST reset asserted cycle=%0d vector_busy=%0d busy_count=%0d", cyc, vector_busy, busy_count);
   repeat (20) @(posedge clk);
   rst_n = 1;
   repeat (20) @(posedge clk);
   snapshot_old;
   phase = 1; phase_cycle = cyc;
   repeat (quiescent) @(posedge clk);
   phase = 0;
   $display("HOST reset-quiescent aw=%0d b=%0d", aw_old, b_old);
   if (aw_old != 0 || b_old != 0) begin
    $display("CHECK_FAIL reset quiescent aw=%0d b=%0d", aw_old, b_old); errors=errors+1;
   end
  end

  // new epoch
  csr_write(24'h08, plan2);
  csr_write(24'h0c, 32'd1);
  csr_write(24'h10, 32'd1);
  $display("HOST plan2 START cycle=%0d", cyc);
  done_cycle = -1;
  while (!done_latch && !fault && cyc < timeout) @(posedge clk);
  repeat (8) @(posedge clk);
  phase = 2; phase_cycle = cyc;
  repeat (post_window) @(posedge clk);
  phase = 0;
  $display("HOST plan2 done=%0d abort_done=%0d fault=%0d err=%02x cycle=%0d done_cycle=%0d last_b=%0d b_count=%0d",
           done_latch, aborted, fault, error_code, cyc, done_cycle, last_b_cycle, b_at_done);
  $display("HOST plan2-post aw=%0d b=%0d vcompleted=%0d vflags=%02x",
           aw_new, b_new, dut.graph.vec.arithmetic.completed_elements,
           dut.graph.vec.arithmetic.numeric_flags);

  if (fault) begin $display("CHECK_FAIL plan2 fault err=%02x", error_code); errors=errors+1; end
  if (!done_latch) begin $display("CHECK_FAIL plan2 no done"); errors=errors+1; end
  if (aborted) begin $display("CHECK_FAIL plan2 aborted"); errors=errors+1; end
  if (dut.graph.vec.arithmetic.completed_elements != total2) begin
   $display("CHECK_FAIL plan2 completed=%0d expected=%0d", dut.graph.vec.arithmetic.completed_elements, total2);
   errors=errors+1;
  end
  if (dut.graph.vec.arithmetic.numeric_flags != 0) begin
   $display("CHECK_FAIL plan2 numeric_flags=%02x", dut.graph.vec.arithmetic.numeric_flags); errors=errors+1;
  end
  if (b_at_done != 0) begin $display("CHECK_FAIL plan2 b_count_at_done=%0d", b_at_done); errors=errors+1; end
  if (b_new != 0 || aw_new != 0) begin
   $display("CHECK_FAIL plan2 post aw=%0d b=%0d", aw_new, b_new); errors=errors+1;
  end
  if (last_b_cycle < 0 || last_b_cycle >= done_cycle) begin
   $display("CHECK_FAIL plan2 last_b=%0d done=%0d", last_b_cycle, done_cycle); errors=errors+1;
  end

  // old D region must be byte-identical after the new epoch
  off = mem_word(d1);
  for (k=0;k<total1;k=k+1) begin
   if (bfm.memw[off+k] !== old_snap[k]) begin
    $display("CHECK_FAIL old_epoch_region_changed addr=%h old=%08x new=%08x",
             d1 + k*4, old_snap[k], bfm.memw[off+k]);
    errors = errors + 1;
    k = total1;
   end
  end

  if (errors == 0) begin
   dump_region(d2, total2, dumpfile);
   $display("VEC_FMA_ABORT_RESET PASS scenario=%0d total1=%0d total2=%0d done_cycle=%0d last_b=%0d",
            scenario, total1, total2, done_cycle, last_b_cycle);
   $finish;
  end else begin
   $display("VEC_FMA_ABORT_RESET FAIL errors=%0d", errors);
   $fatal(1, "abort/reset test failed");
  end
 end

 always @(posedge clk) begin
  cyc <= cyc + 1;
  if (cyc > timeout + 1000) begin
   $display("VEC_FMA_TIMEOUT cycle=%0d busy=%0d fault=%0d err=%02x", cyc, busy, fault, error_code);
   $fatal(1, "abort/reset timeout");
  end
 end
endmodule
