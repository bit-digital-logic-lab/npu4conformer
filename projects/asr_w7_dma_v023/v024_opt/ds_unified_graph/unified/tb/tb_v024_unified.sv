`timescale 1ns/1ps
// V0.24 unified small-graph TB.
//
// Modes:
//   0 fused plan: explicit MATF node, per-channel table, DIV + SQRT branches
//   1 fallback: MATF request refused (queue_count=2), legacy C48 path
//   2 fused plan with the A16 write B response held -> watchdog isolation
//   3 MATF word without header FUSION_ALLOW -> plan rejected (0x04)
//
// The per-channel table is host-preloaded once before START (not per tile).
// The TB dumps a fixed arena window for the independent checker.
module tb_v024_unified;
 localparam integer MAX_CYCLES = 200000;

 reg clk = 0;
 always #4 clk = ~clk;
 reg rst_n = 0;

 reg [23:0] awaddr=0; reg awvalid=0; wire awready;
 reg [31:0] wdata=0; reg [3:0] wstrb=0; reg wvalid=0; wire wready;
 wire [1:0] bresp; wire bvalid; reg bready=1;
 reg [23:0] araddr=0; reg arvalid=0; wire arready;
 wire [31:0] rdata; wire [1:0] rresp; wire rvalid; reg rready=1;

 wire [39:0] m_araddr; wire [7:0] m_arlen; wire [2:0] m_arsize;
 wire [1:0] m_arburst; wire m_arvalid; wire m_arready;
 wire [127:0] m_rdata; wire [1:0] m_rresp; wire m_rlast,m_rvalid; wire m_rready;
 wire [39:0] m_awaddr; wire [7:0] m_awlen; wire [2:0] m_awsize;
 wire [1:0] m_awburst; wire m_awvalid; wire m_awready;
 wire [127:0] m_wdata; wire [15:0] m_wstrb; wire m_wlast,m_wvalid; wire m_wready;
 wire [1:0] m_bresp; wire m_bvalid; wire m_bready;

 wire busy,done,fault,irq,drain_timeout;
 wire [7:0] error_code;
 wire [31:0] completed,last_node;
 wire [63:0] cycles;
 wire seq_active,vector_busy,layout_busy,matrix_busy;
 wire [7:0] matrix_error;
 wire [63:0] matrix_cycles;
 wire [31:0] matrix_compute_cycles;
 wire [63:0] vector_cycles,layout_cycles;
 wire [31:0] vector_read_bytes,vector_write_bytes,layout_read_bytes,layout_write_bytes;
 wire [31:0] rd_bursts,wr_bursts,r_beats,w_beats;
 wire [31:0] rd_peak,wr_peak,rd_stall_cycles,wr_stall_cycles,axi_tag_errors;
 wire isolation_req,requires_reset,port_quiesced;
 wire [31:0] rd_pending,wr_pending,b_pending,iso_blocked_reqs;
 wire seq_dto,seq_ito,fetch_to;
 wire [63:0] vector_total_cycles,layout_total_cycles,matrix_total_cycles;
 wire [31:0] vector_op_count,layout_op_count,matrix_op_count;
 wire seq_valid_o; wire [31:0] seq_base_o,seq_count_o;
 wire matrix_fused_used;
 wire [31:0] fuse_c48_ddr_bytes,fuse_a16_bytes;
 wire pc_wr_ready;

 wire [31:0] bfm_rb,bfm_wb,bfm_rbeats,bfm_wbeats;
 wire [31:0] bfm_held_r,bfm_held_b,bfm_returned_b;
 wire bfm_rheld,bfm_bheld;
 wc_safety_bfm bfm (
  .clk(clk),.rst_n(rst_n),
  .araddr(m_araddr),.arlen(m_arlen),.arsize(m_arsize),.arburst(m_arburst),
  .arvalid(m_arvalid),.arready(m_arready),
  .rdata(m_rdata),.rresp(m_rresp),.rlast(m_rlast),.rvalid(m_rvalid),.rready(m_rready),
  .awaddr(m_awaddr),.awlen(m_awlen),.awsize(m_awsize),.awburst(m_awburst),
  .awvalid(m_awvalid),.awready(m_awready),
  .wdata(m_wdata),.wstrb(m_wstrb),.wlast(m_wlast),.wvalid(m_wvalid),.wready(m_wready),
  .bresp(m_bresp),.bvalid(m_bvalid),.bready(m_bready),
  .read_bursts(bfm_rb),.write_bursts(bfm_wb),.read_beats(bfm_rbeats),.write_beats(bfm_wbeats),
  .held_r_bursts(bfm_held_r),.held_b_bursts(bfm_held_b),.returned_b(bfm_returned_b),
  .r_is_held(bfm_rheld),.b_is_held(bfm_bheld)
 );

 // host one-time per-channel preload
 reg pc_valid=0; reg [7:0] pc_addr=0; reg [31:0] pc_data=0;
 integer pc_i;

 v024_unified_top #(
  .PIPE_STAGES(4),.MAX_PREFETCH(16),.USE_APPROX_DIV_SQRT(1),
  .MATRIX_WATCHDOG(20000),.VEC_WATCHDOG(20000),.LAY_WATCHDOG(30000),
  .SEQ_WATCHDOG(3000),.FETCH_WATCHDOG(20000),
  .DRAIN_WATCHDOG(60000),.SEQ_ENABLE(0)
 ) dut (
  .clk(clk),.rst_n(rst_n),
  .seq_ready_i(1'b0),.seq_done_i(1'b0),.seq_fault_i(1'b0),.seq_error_i(8'd0),
  .seq_valid_o(seq_valid_o),.seq_base_o(seq_base_o),.seq_count_o(seq_count_o),
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
  .pc_wr_valid(pc_valid),.pc_wr_ready(pc_wr_ready),
  .pc_wr_addr(pc_addr),.pc_wr_data(pc_data),
  .matrix_fused_used(matrix_fused_used),
  .fuse_c48_ddr_bytes(fuse_c48_ddr_bytes),.fuse_a16_bytes(fuse_a16_bytes),
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
  .wr_stall_cycles(wr_stall_cycles),.axi_tag_errors(axi_tag_errors),
  .isolation_req(isolation_req),.requires_reset(requires_reset),
  .port_quiesced(port_quiesced),.rd_pending(rd_pending),.wr_pending(wr_pending),
  .b_pending(b_pending),.iso_blocked_reqs(iso_blocked_reqs),
  .seq_dispatch_timeout(seq_dto),.seq_inflight_timeout(seq_ito),.fetch_timeout(fetch_to),
  .vector_total_cycles(vector_total_cycles),.layout_total_cycles(layout_total_cycles),
  .matrix_total_cycles(matrix_total_cycles),.vector_op_count(vector_op_count),
  .layout_op_count(layout_op_count),.matrix_op_count(matrix_op_count)
 );

 integer cyc=0;
 integer timeout=40000;
 integer mode=0;
 integer expect_error=-1;
 integer errors=0;
 integer i;
 reg [31:0] plan_base;
 reg done_seen=0;
 integer iso_cycles=0, post_iso_req=0;
 always @(posedge clk) if (rst_n) begin
  if (dut.csr.done_latched) done_seen<=1;
  if (isolation_req) begin
   iso_cycles <= iso_cycles+1;
   if (m_arvalid || m_awvalid || m_wvalid) post_iso_req <= post_iso_req+1;
  end
 end

 task csr_write(input [23:0] a, input [31:0] d);
 begin
  @(posedge clk); awaddr<=a; wdata<=d; wstrb<=4'hf; awvalid<=1; wvalid<=1;
  while (!(awready&&wready)) @(posedge clk);
  @(posedge clk); awvalid<=0; wvalid<=0;
  while (!bvalid) @(posedge clk);
  @(posedge clk);
 end
 endtask

 task csr_read(input [23:0] a, output [31:0] d);
 begin
  @(posedge clk); araddr<=a; arvalid<=1;
  while (!arready) @(posedge clk);
  @(posedge clk); arvalid<=0;
  while (!rvalid) @(posedge clk);
  d = rdata;
  @(posedge clk);
 end
 endtask

 task read64(input [23:0] lo, output [63:0] d);
 reg [31:0] l,h;
 begin csr_read(lo,l); csr_read(lo+4,h); d={h,l}; end
 endtask

 // one-time host preload of 64 per-channel words from the fixture image
 task preload_pc;
 begin
  for (pc_i=0; pc_i<64; pc_i=pc_i+1) begin
   @(posedge clk);
   pc_addr <= pc_i;
   pc_data <= bfm.memw[32'h30C00 + pc_i];
   pc_valid <= 1;
   while (!pc_wr_ready) @(posedge clk);
   @(posedge clk);
   pc_valid <= 0;
  end
 end
 endtask

 reg [1023:0] memfile, outfile;
 integer fd;
 initial begin
  if (!$value$plusargs("memfile=%s", memfile)) memfile="fixtures/mem_v024_fused.hex";
  if (!$value$plusargs("outfile=%s", outfile)) outfile="logs/v024_out.hex";
  if (!$value$plusargs("watchdog=%d", timeout)) timeout=40000;
  if (!$value$plusargs("mode=%d", mode)) mode=0;
  if (!$value$plusargs("expect_error=%d", expect_error)) expect_error=-1;
  if (!$value$plusargs("plan=%d", plan_base)) plan_base=32'h10008000;
  rst_n=0;
  repeat (12) @(posedge clk);
  rst_n=1;
  repeat (5) @(posedge clk);
  preload_pc;
  csr_write(24'h08, plan_base);
  csr_write(24'h0c, 32'd1);
  csr_write(24'h10, 32'd1);
  while (!done_seen && !fault && cyc < timeout) begin
   @(posedge clk);
   if (cyc % 5000 == 0)
    $display("WAIT cyc=%0d busy=%0d fault=%0d err=%02x iso=%0d rd=%0d wr=%0d b=%0d",
      cyc,busy,fault,error_code,isolation_req,rd_pending,wr_pending,b_pending);
  end
  repeat (20) @(posedge clk);
  begin : dump
   reg [63:0] v,l,m,cy,f,op;
   reg [31:0] st,er,cp,ln,vops,lops,mops,rdp,wrp,bp;
   csr_read(24'h04,st); csr_read(24'h1c,er); csr_read(24'h14,cp); csr_read(24'h18,ln);
   read64(24'h20,cy); read64(24'h30,f); read64(24'h38,op);
   read64(24'h40,v); read64(24'h48,l); read64(24'hA0,m);
   csr_read(24'hB4,rdp); csr_read(24'hB8,wrp); csr_read(24'hBC,bp);
   $display("V024_CSR status=%08x err=%02x completed=%0d last=%0d cycles=%0d fetch=%0d op=%0d",
     st,er,cp,ln,cy,f,op);
   $display("V024_CSR vec_total=%0d layout_total=%0d matrix_total=%0d vec_ops=%0d layout_ops=%0d matrix_ops=%0d",
     v,l,m,vector_op_count,layout_op_count,matrix_op_count);
   $display("V024_FUSION used=%0d c48_ddr_bytes=%0d a16_bytes=%0d",matrix_fused_used,
     fuse_c48_ddr_bytes,fuse_a16_bytes);
   $display("V024_AXI rburst=%0d wburst=%0d rbeats=%0d wbeats=%0d tag_err=%0d rpeak=%0d wpeak=%0d",
     rd_bursts,wr_bursts,r_beats,w_beats,axi_tag_errors,rd_peak,wr_peak);
  end
  $display("V024_DRAIN rd_pending=%0d wr_pending=%0d b_pending=%0d quiesced=%0d iso_blocked=%0d held_b=%0d returned_b=%0d",
    rd_pending,wr_pending,b_pending,port_quiesced,iso_blocked_reqs,bfm_held_b,bfm_returned_b);
  $display("V024_END done=%0d fault=%0d error=%02x iso=%0d requires_reset=%0d fetch_to=%0d drain_timeout=%0d cycles=%0d",
    dut.csr.done_latched,fault,error_code,isolation_req,requires_reset,fetch_to,drain_timeout,cyc);

  if (expect_error >= 0 && error_code != expect_error[7:0]) begin
   $display("V024_ERROR_MISMATCH got=%02x want=%02x",error_code,expect_error); errors=errors+1;
  end
  if (mode==2) begin
   if (!dut.csr.done_latched || !fault || error_code != 8'h0E ||
       !isolation_req || !requires_reset) begin
    $display("V024_HOLD_NOT_ISOLATED done=%0d fault=%0d err=%02x iso=%0d rst=%0d",
      dut.csr.done_latched,fault,error_code,isolation_req,requires_reset); errors=errors+1;
   end
   if (b_pending == 0 || port_quiesced) begin
    $display("V024_HOLD_DRAIN_CLAIM_WRONG b=%0d quiesced=%0d",b_pending,port_quiesced); errors=errors+1;
   end
  end else if (mode==0) begin
   if (!dut.csr.done_latched || fault) begin $display("V024_FUSED_NOT_DONE done=%0d fault=%0d",dut.csr.done_latched,fault); errors=errors+1; end
   if (!matrix_fused_used) begin $display("V024_FUSED_NOT_USED"); errors=errors+1; end
   if (fuse_c48_ddr_bytes != 0) begin $display("V024_FUSED_C48_TRAFFIC=%0d",fuse_c48_ddr_bytes); errors=errors+1; end
   if (!port_quiesced || b_pending != 0) begin $display("V024_FUSED_NOT_DRAINED b=%0d q=%0d",b_pending,port_quiesced); errors=errors+1; end
  end else if (mode==1) begin
   if (!dut.csr.done_latched || fault) begin $display("V024_FB_NOT_DONE done=%0d fault=%0d",dut.csr.done_latched,fault); errors=errors+1; end
   if (matrix_fused_used) begin $display("V024_FB_UNEXPECTED_FUSION"); errors=errors+1; end
   if (!port_quiesced) begin $display("V024_FB_NOT_DRAINED"); errors=errors+1; end
  end else if (mode==4) begin
   // explicit MATF + count=1, but one of two consumers is not tagged A16C
   if (!dut.csr.done_latched || fault) begin $display("V024_MC_NOT_DONE done=%0d fault=%0d",dut.csr.done_latched,fault); errors=errors+1; end
   if (matrix_fused_used) begin $display("V024_MC_UNEXPECTED_FUSION"); errors=errors+1; end
   if (!port_quiesced) begin $display("V024_MC_NOT_DRAINED"); errors=errors+1; end
  end else begin
   if (!dut.csr.done_latched) begin $display("V024_DONE_MISSING"); errors=errors+1; end
  end
  if (cyc >= timeout) begin $display("V024_TIMEOUT cyc=%0d",cyc); errors=errors+1; end
  if (isolation_req) begin
   repeat (50) @(posedge clk);
   $display("V024_QUIESCE post_iso_req=%0d rd=%0d wr=%0d b=%0d quiesced=%0d",
     post_iso_req,rd_pending,wr_pending,b_pending,port_quiesced);
   if (post_iso_req != 0) begin $display("V024_ISO_NOT_QUIESCED"); errors=errors+1; end
  end

  // dump fixed window for the independent checker
  fd=$fopen(outfile,"w");
  for (i=0;i<8192;i=i+1) $fwrite(fd,"%08x\n",bfm.memw[(32'h40000 + 32'h4000)/4 + i]);
  $fclose(fd);
  if (errors) $display("V024_RESULT FAIL errors=%0d",errors);
  else $display("V024_RESULT PASS");
  $finish;
 end

 always @(posedge clk) begin
  cyc <= cyc+1;
  if (cyc > timeout+2000) begin
   $display("V024_GLOBAL_TIMEOUT cyc=%0d busy=%0d fault=%0d err=%02x",cyc,busy,fault,error_code);
   $finish;
  end
 end
endmodule
