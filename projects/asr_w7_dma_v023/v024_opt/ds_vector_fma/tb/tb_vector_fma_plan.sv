`timescale 1ns/1ps
// One-node WCPG plan runner for the ds_vector_fma regression.
// The TB only writes CSR registers; the graph controller fetches the plan,
// node and 512-bit vector descriptor from the parameter window.  The vector
// engine reads A/B/C and writes D through the shared AXI128 BFM.
//
// Checks: fault/done/abort, vector completed_elements==total, numeric_flags=0,
// b_count_at_done=0, no AW/B in a 64-cycle post-done window, last B < done.
module tb_vector_fma_plan;
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
 integer timeout = 1000000;
 integer plan_base = 32'h10008000;
 integer total = 0;
 integer out_addr = 32'h04010000;
 integer outwords = 0;
 reg [1023:0] memfile;
 reg [1023:0] dumpfile;
 reg [31:0] val;
 integer errors = 0;
 integer done_cycle = -1;
 integer last_b_cycle = -1;
 integer b_count_at_done = 0;
 integer b_after_done = 0;
 integer aw_after_done = 0;
 integer post_window = 64;
 reg boundary_enable = 0;
 integer boundary_cycle = 0;
 reg done_seen = 0;
 integer fd;

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

 // Real AXI boundary monitor for the post-done window.
 always @(posedge clk) begin
  if (rst_n) begin
   if (m_bvalid && m_bready) last_b_cycle = cyc;
   if (!done_latch) done_seen = 0;
   else if (!done_seen) begin
    done_seen = 1; done_cycle = cyc; b_count_at_done = dut.xbar.b_count;
   end
   if (boundary_enable && cyc > boundary_cycle) begin
    if (m_bvalid && m_bready) b_after_done = b_after_done + 1;
    if (m_awvalid && m_awready) aw_after_done = aw_after_done + 1;
   end
  end
 end

 initial begin
  if (!$value$plusargs("memfile=%s", memfile)) memfile = "fixtures/cases/full8734/mem.hex";
  if (!$value$plusargs("plan=%d", plan_base)) plan_base = 32'h10008000;
  if (!$value$plusargs("total=%d", total)) total = 8734;
  if (!$value$plusargs("out=%d", out_addr)) out_addr = 32'h0401b000;
  if (!$value$plusargs("outwords=%d", outwords)) outwords = total;
  if (!$value$plusargs("dump=%s", dumpfile)) dumpfile = "logs/out.hex";
  if (!$value$plusargs("watchdog=%d", timeout)) timeout = 1000000;

  rst_n = 0;
  repeat (12) @(posedge clk);
  rst_n = 1;
  repeat (5) @(posedge clk);

  $display("HOST START plan=%h total=%0d out=%h outwords=%0d cycle=%0d", plan_base, total, out_addr, outwords, cyc);
  csr_write(24'h08, plan_base);
  csr_write(24'h0c, 32'd1);
  csr_write(24'h10, 32'd1);

  while (!done_latch && !fault && cyc < timeout) @(posedge clk);
  repeat (8) @(posedge clk);
  boundary_enable = 1; boundary_cycle = cyc;
  repeat (post_window) @(posedge clk);
  boundary_enable = 0;

  csr_read(24'h04, val);
  $display("STATUS busy=%0d done=%0d fault=%0d aborted=%0d err=%02x cycles=%0d completed=%0d last=%0d",
           busy, done_latch, fault, aborted, error_code, cycles, completed, last_node);
  $display("VEC vcyc=%0d vrb=%0d vwb=%0d vcompleted=%0d vflags=%02x vfault=%0d vaborted=%0d vrejected=%0d",
           vector_cycles, vector_read_bytes, vector_write_bytes,
           dut.graph.vec.arithmetic.completed_elements,
           dut.graph.vec.arithmetic.numeric_flags,
           dut.graph.vec.arithmetic.fault,
           dut.graph.vec.arithmetic.aborted,
           dut.graph.vec.arithmetic.rejected_starts);
  $display("AXI rburst=%0d wburst=%0d rbeats=%0d wbeats=%0d rdstall=%0d wrstall=%0d tag_err=%0d",
           rd_bursts, wr_bursts, r_beats, w_beats, rd_stall_cycles, wr_stall_cycles, axi_tag_errors);
  $display("BOUNDARY done_cycle=%0d last_b_cycle=%0d b_count_at_done=%0d b_after_done=%0d aw_after_done=%0d",
           done_cycle, last_b_cycle, b_count_at_done, b_after_done, aw_after_done);

  if (fault) begin $display("CHECK_FAIL fault err=%02x", error_code); errors=errors+1; end
  if (!done_latch) begin $display("CHECK_FAIL no done"); errors=errors+1; end
  if (aborted) begin $display("CHECK_FAIL unexpected aborted"); errors=errors+1; end
  if (dut.graph.vec.arithmetic.fault) begin $display("CHECK_FAIL vector fault"); errors=errors+1; end
  if (dut.graph.vec.arithmetic.aborted) begin $display("CHECK_FAIL vector aborted"); errors=errors+1; end
  if (dut.graph.vec.arithmetic.completed_elements != total) begin
   $display("CHECK_FAIL completed=%0d expected=%0d", dut.graph.vec.arithmetic.completed_elements, total);
   errors=errors+1;
  end
  if (dut.graph.vec.arithmetic.numeric_flags != 0) begin
   $display("CHECK_FAIL numeric_flags=%02x", dut.graph.vec.arithmetic.numeric_flags); errors=errors+1;
  end
  if (b_count_at_done != 0) begin $display("CHECK_FAIL b_count_at_done=%0d", b_count_at_done); errors=errors+1; end
  if (b_after_done != 0) begin $display("CHECK_FAIL b_after_done=%0d", b_after_done); errors=errors+1; end
  if (aw_after_done != 0) begin $display("CHECK_FAIL aw_after_done=%0d", aw_after_done); errors=errors+1; end
  if (last_b_cycle < 0 || last_b_cycle >= done_cycle) begin
   $display("CHECK_FAIL last_b=%0d done=%0d", last_b_cycle, done_cycle); errors=errors+1;
  end
  if (cyc >= timeout) begin $display("CHECK_FAIL watchdog cycle=%0d", cyc); errors=errors+1; end

  if (errors == 0) begin
   dump_region(out_addr, outwords, dumpfile);
   $display("VEC_FMA_PLAN PASS total=%0d outwords=%0d done_cycle=%0d last_b=%0d vcyc=%0d rbeats=%0d wbeats=%0d",
            total, outwords, done_cycle, last_b_cycle, vector_cycles, r_beats, w_beats);
   $finish;
  end else begin
   $display("VEC_FMA_PLAN FAIL errors=%0d", errors);
   $fatal(1, "vector fma plan failed");
  end
 end

 always @(posedge clk) begin
  cyc <= cyc + 1;
  if (cyc > timeout + 1000) begin
   $display("VEC_FMA_TIMEOUT cycle=%0d busy=%0d fault=%0d err=%02x", cyc, busy, fault, error_code);
   $fatal(1, "vector fma timeout");
  end
 end
endmodule
