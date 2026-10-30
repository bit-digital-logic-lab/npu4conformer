`timescale 1ns/1ps
// V0.23 numeric-closeout graph testbench.
//
// One CSR START submits a WCPG superplan.  The graph fetches descriptors from
// the parameter (DDR) window; the vector engine reads A/B/C planes from the
// external DDR window and writes results to the arena, all through the single
// shared AXI128 port.  The testbench only writes CSR registers.
//
// Scenarios:
//   normal (default) : plan1 = FMA(op17) -> DIV(op3) -> SQRT(op4)
//   abort            : start plan1, pulse abort mid-op, wait DONE, then start
//                      plan2 (new epoch) and verify only plan2 output changes
//   reset            : start plan1, assert rst_n mid-op, then start plan2
`include "fixtures/closeout_params.svh"

module tb_closeout_numeric;
 localparam integer MAX_CYCLES = 4000000;
 reg clk = 0;
 always #4 clk = ~clk;
 reg rst_n = 0;
 reg abort = 0;

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
 integer timeout = 3000000;
 reg [1023:0] memfile;
 integer i;
 reg [31:0] plan_base;
 reg [31:0] val;
 integer errors = 0;
 integer scenario = 0;       // 0 normal, 1 abort, 2 reset
 integer abort_at = 0;
 integer reset_at = 0;
 integer done_cycle = -1;
 integer last_b_cycle = -1;
 integer b_after_done = 0;
 integer aw_after_done = 0;
 integer b_count_at_done = 0;
 integer abort_cycle = -1;
 integer reset_cycle = -1;
 integer plan2_started = 0;
 reg boundary_enable = 0;
 reg boundary_arm = 0;
 integer boundary_cycle = 0;
 reg done_seen = 0;
 reg [31:0] fma_snapshot [0:FMA_COUNT-1];
 reg [31:0] fma2_snapshot [0:FMA2_COUNT-1];
 integer fd;

 wire done_latch = dut.csr.done_latched;

 // BFM: one shared AXI128 slave, sparse 1 MiB logic memory.
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
  .PIPE_STAGES(4),.MAX_PREFETCH(16),.USE_APPROX_DIV_SQRT(`USE_APPROX),
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

 task dump_region(input [31:0] base, input integer n, input [1023:0] name);
 integer k, off;
 begin
  off = mem_word(base);
  fd = $fopen(name, "w");
  for (k=0;k<n;k=k+1) $fwrite(fd, "%08x\n", bfm.memw[off+k]);
  $fclose(fd);
 end
 endtask

 task snapshot_region(input [31:0] base, input integer n, output integer dummy);
 integer k, off;
 begin
  off = mem_word(base);
  for (k=0;k<n;k=k+1) begin
   if (base == FMA_OUT) fma_snapshot[k] = bfm.memw[off+k];
   else if (base == FMA2_OUT) fma2_snapshot[k] = bfm.memw[off+k];
  end
  dummy = 0;
 end
 endtask

 task start_plan(input [31:0] pbase, input [1023:0] tag);
 begin
  $display("HOST %0s plan_base=%h", tag, pbase);
  csr_write(24'h08, pbase);
  csr_write(24'h0c, 32'd1);
  csr_write(24'h10, 32'd1);
  $display("HOST %0s START cycle=%0d", tag, cyc);
 end
 endtask

 task wait_done(input [1023:0] tag);
 begin
  while (!done_latch && !fault && cyc < timeout) @(posedge clk);
  repeat (8) @(posedge clk);
  $display("HOST %0s done=%0d abort_done=%0d fault=%0d err=%02x cycle=%0d done_cycle=%0d",
           tag, done_latch, aborted, fault, error_code, cyc, done_cycle);
 end
 endtask

 // Real AXI write-response / AW boundary monitor.
 // done_cycle is the cycle in which the CSR done latch first rises.
 // boundary_enable is opened after an abort/reset drain and closed before the
 // new epoch starts, so AW/B counters cover only the quiescent window.
 always @(posedge clk) begin
  if (rst_n) begin
   if (m_bvalid && m_bready) last_b_cycle = cyc;
   if (!done_latch) done_seen = 0;
   else if (!done_seen) begin
    done_seen = 1; done_cycle = cyc; b_count_at_done = dut.xbar.b_count;
    if (boundary_arm) begin boundary_enable = 1; boundary_cycle = cyc; end
   end
   if (boundary_enable && cyc > boundary_cycle) begin
    if (m_bvalid && m_bready) b_after_done = b_after_done + 1;
    if (m_awvalid && m_awready) aw_after_done = aw_after_done + 1;
   end
  end
 end

 initial begin
  if (!$value$plusargs("memfile=%s", memfile)) memfile = "fixtures/mem_closeout.hex";
  if (!$value$plusargs("watchdog=%d", timeout)) timeout = 3000000;
  if (!$value$plusargs("scenario=%d", scenario)) scenario = 0;
  if (!$value$plusargs("abort_at=%d", abort_at)) abort_at = 2500;
  if (!$value$plusargs("reset_at=%d", reset_at)) reset_at = 3000;

  rst_n = 0;
  repeat (12) @(posedge clk);
  rst_n = 1;
  repeat (5) @(posedge clk);

  if (scenario == 0) begin
   start_plan(PLAN1, "plan1");
   while (!done_latch && !fault && cyc < timeout) @(posedge clk);
   repeat (8) @(posedge clk);
  end else if (scenario == 1) begin
   boundary_arm = 1;
   start_plan(PLAN1, "plan1-abort");
   while (cyc < abort_at && !done_latch && !fault) @(posedge clk);
   abort = 1; abort_cycle = cyc;
   repeat (4) @(posedge clk);
   abort = 0;
   $display("HOST abort asserted cycle=%0d vector_busy=%0d", abort_cycle, vector_busy);
   wait_done("abort-drain");
   if (!aborted) begin $display("CHECK_FAIL abort_done not asserted"); errors=errors+1; end
   snapshot_region(FMA_OUT, FMA_COUNT, i);
   repeat (32) @(posedge clk);
   boundary_enable = 0; boundary_arm = 0;
   $display("HOST abort-quiescent aw=%0d b=%0d done_cycle=%0d last_b=%0d",
            aw_after_done, b_after_done, done_cycle, last_b_cycle);
   start_plan(PLAN2, "plan2-new-epoch");
   wait_done("plan2");
   if (aborted) begin $display("CHECK_FAIL plan2 aborted"); errors=errors+1; end
  end else begin
   start_plan(PLAN1, "plan1-reset");
   while (cyc < reset_at && !done_latch && !fault) @(posedge clk);
   rst_n = 0; reset_cycle = cyc;
   $display("HOST reset asserted cycle=%0d", reset_cycle);
   repeat (20) @(posedge clk);
   rst_n = 1;
   repeat (20) @(posedge clk);
   snapshot_region(FMA_OUT, FMA_COUNT, i);
   boundary_cycle = cyc; boundary_enable = 1;
   repeat (32) @(posedge clk);
   boundary_enable = 0;
   $display("HOST reset-quiescent aw=%0d b=%0d last_b=%0d",
            aw_after_done, b_after_done, last_b_cycle);
   start_plan(PLAN2, "plan2-after-reset");
   wait_done("plan2-after-reset");
   if (aborted) begin $display("CHECK_FAIL post-reset plan aborted"); errors=errors+1; end
  end

  csr_read(24'h04, val);
  $display("CLOSEOUT_STATUS busy=%0d done=%0d fault=%0d aborted=%0d err=%02x cycles=%0d completed=%0d last=%0d",
           busy, done_latch, fault, aborted, error_code, cycles, completed, last_node);
  $display("CLOSEOUT_VEC vcyc=%0d lcyc=%0d vrb=%0d vwb=%0d", vector_cycles, layout_cycles,
           vector_read_bytes, vector_write_bytes);
  $display("CLOSEOUT_AXI rburst=%0d wburst=%0d rbeats=%0d wbeats=%0d rdpeak=%0d wrpeak=%0d rdstall=%0d wrstall=%0d tag_err=%0d bfm_rbeats=%0d bfm_wbeats=%0d",
           rd_bursts, wr_bursts, r_beats, w_beats, rd_peak, wr_peak,
           rd_stall_cycles, wr_stall_cycles, axi_tag_errors, bfm_rbeats, bfm_wbeats);
  $display("CLOSEOUT_BOUNDARY done_cycle=%0d last_b_cycle=%0d b_count_at_done=%0d b_after_done=%0d aw_after_done=%0d",
           done_cycle, last_b_cycle, b_count_at_done, b_after_done, aw_after_done);

  if (scenario == 0) begin
   dump_region(FMA_OUT, FMA_COUNT, "logs/fma_out.hex");
   dump_region(DIV_OUT, DIV_COUNT, "logs/div_out.hex");
   dump_region(SQRT_OUT, SQRT_COUNT, "logs/sqrt_out.hex");
  end else begin
   dump_region(FMA2_OUT, FMA2_COUNT, "logs/fma2_out.hex");
   // no post-abort/post-reset old-epoch traffic
   if (aw_after_done != 0) begin
    $display("CHECK_FAIL aw_after_done=%0d", aw_after_done); errors=errors+1;
   end
   if (b_after_done != 0) begin
    $display("CHECK_FAIL b_after_done=%0d", b_after_done); errors=errors+1;
   end
   if (scenario != 0) begin
    begin : cmp_old_epoch
     integer k, off;
     off = mem_word(FMA_OUT);
     for (k=0;k<FMA_COUNT;k=k+1) begin
      if (bfm.memw[off+k] !== fma_snapshot[k]) begin
       $display("CHECK_FAIL old_epoch_region_changed addr=%h old=%08x new=%08x",
                FMA_OUT + k*4, fma_snapshot[k], bfm.memw[off+k]);
       errors = errors + 1;
       k = FMA_COUNT;
      end
     end
    end
   end
  end

  if (fault || !done_latch) errors = errors + 1;
  if (cyc >= timeout) errors = errors + 1;
  if (errors) begin
   $display("CLOSEOUT_RESULT FAIL errors=%0d", errors);
   $fatal(1, "closeout numeric test failed");
  end
  $display("CLOSEOUT_RESULT PASS");
  $finish;
 end

 always @(posedge clk) begin
  cyc <= cyc + 1;
  if (cyc > timeout + 1000) begin
   $display("CLOSEOUT_TIMEOUT cycle=%0d busy=%0d fault=%0d err=%02x", cyc, busy, fault, error_code);
   $fatal(1, "closeout numeric timeout");
  end
 end
endmodule
