`timescale 1ns/1ps
// Same-load graph testbench for the v024 graph/prefetch candidate.
//
// One CSR START, one preloaded WCPG plan, the same wc_safety_bfm slave and the
// same fixture as the v023 safety task.  It dumps:
//   * final 512-word I16 output (same offset as the v023 safety TB),
//   * matrix C48 (1024 x 48-bit) for the independent matrix golden,
//   * a per-cycle CSV trace used to rebuild the per-node time account.
//
// The trace is sampled from real RTL state; the RTL also exports exclusive
// ledger counters, which the Python checker cross-checks against the trace.
//
// Compile:
//   -DLOOKAHEAD_ON  : our RTL with LOOKAHEAD_EN=1
//   (no define)     : our RTL with LOOKAHEAD_EN=0
//   -DBASELINE_RTL  : frozen v023 RTL (no lookahead ports)
module tb_graph_prefetch;
 localparam integer MAX_CYCLES = 200000;

 reg clk = 0;
 always #4 clk = ~clk;
 reg rst_n = 0;

`ifdef LOOKAHEAD_ON
 localparam integer LU_EN = 1;
`else
 localparam integer LU_EN = 0;
`endif

 // CSR
 reg [23:0] awaddr=0; reg awvalid=0; wire awready;
 reg [31:0] wdata=0; reg [3:0] wstrb=0; reg wvalid=0; wire wready;
 wire [1:0] bresp; wire bvalid; reg bready=1;
 reg [23:0] araddr=0; reg arvalid=0; wire arready;
 wire [31:0] rdata; wire [1:0] rresp; wire rvalid; reg rready=1;

 // data AXI
 wire [39:0] m_araddr; wire [7:0] m_arlen; wire [2:0] m_arsize;
 wire [1:0] m_arburst; wire m_arvalid; wire m_arready;
 wire [127:0] m_rdata; wire [1:0] m_rresp; wire m_rlast,m_rvalid; wire m_rready;
 wire [39:0] m_awaddr; wire [7:0] m_awlen; wire [2:0] m_awsize;
 wire [1:0] m_awburst; wire m_awvalid; wire m_awready;
 wire [127:0] m_wdata; wire [15:0] m_wstrb; wire m_wlast,m_wvalid; wire m_wready;
 wire [1:0] m_bresp; wire m_bvalid; wire m_bready;

 // status
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

 // BFM
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

 // SEQ child is not used in the normal chain; tie it off.  SEQ_ENABLE=0 in
 // the DUT keeps the original integrated behaviour.
 reg seq_ready_r=0, seq_done_r=0, seq_fault_r=0;
 reg [7:0] seq_error_r=0;

`ifndef BASELINE_RTL
 wire lookahead_valid;
 wire [31:0] lookahead_hits,lookahead_misses,lookahead_fetches,lookahead_aborts,lookahead_epoch;
 wire [63:0] ledger_fetch,ledger_dispatch,ledger_engine,ledger_idle;
 wire [63:0] ledger_fetch_only,ledger_engine_only,ledger_dispatch_only;
 wire [63:0] ledger_fetch_engine,ledger_dispatch_engine,ledger_fetch_dispatch,ledger_all;
 wire [63:0] ledger_header_fetch,ledger_node_fetch,ledger_payload_fetch,ledger_lookahead_fetch;
`endif

`ifdef BASELINE_RTL
 v023_integrated_top #(
  .PIPE_STAGES(4),.MAX_PREFETCH(16),.USE_APPROX_DIV_SQRT(0),
  .MATRIX_WATCHDOG(3000),.VEC_WATCHDOG(3000),.LAY_WATCHDOG(20000),
  .SEQ_WATCHDOG(3000),.FETCH_WATCHDOG(3000),
  .DRAIN_WATCHDOG(20000),.SEQ_ENABLE(0)
 ) dut (
`else
 v023_integrated_top #(
  .PIPE_STAGES(4),.MAX_PREFETCH(16),.USE_APPROX_DIV_SQRT(0),
  .MATRIX_WATCHDOG(3000),.VEC_WATCHDOG(3000),.LAY_WATCHDOG(20000),
  .SEQ_WATCHDOG(3000),.FETCH_WATCHDOG(3000),
  .DRAIN_WATCHDOG(20000),.SEQ_ENABLE(0),
  .LOOKAHEAD_EN(LU_EN),.LOOKAHEAD_WINDOW(8)
 ) dut (
`endif
  .clk(clk),.rst_n(rst_n),
  .seq_ready_i(seq_ready_r),.seq_done_i(seq_done_r),.seq_fault_i(seq_fault_r),
  .seq_error_i(seq_error_r),.seq_valid_o(seq_valid_o),
  .seq_base_o(seq_base_o),.seq_count_o(seq_count_o),
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
  .wr_stall_cycles(wr_stall_cycles),.axi_tag_errors(axi_tag_errors),
  .isolation_req(isolation_req),.requires_reset(requires_reset),
  .port_quiesced(port_quiesced),.rd_pending(rd_pending),.wr_pending(wr_pending),
  .b_pending(b_pending),.iso_blocked_reqs(iso_blocked_reqs),
  .seq_dispatch_timeout(seq_dto),.seq_inflight_timeout(seq_ito),.fetch_timeout(fetch_to),
  .vector_total_cycles(vector_total_cycles),.layout_total_cycles(layout_total_cycles),
  .matrix_total_cycles(matrix_total_cycles),.vector_op_count(vector_op_count),
  .layout_op_count(layout_op_count),.matrix_op_count(matrix_op_count)
`ifndef BASELINE_RTL
  ,.lookahead_valid(lookahead_valid),.lookahead_hits(lookahead_hits),
  .lookahead_misses(lookahead_misses),.lookahead_fetches(lookahead_fetches),
  .lookahead_aborts(lookahead_aborts),.lookahead_epoch(lookahead_epoch),
  .ledger_fetch(ledger_fetch),.ledger_dispatch(ledger_dispatch),
  .ledger_engine(ledger_engine),.ledger_idle(ledger_idle),
  .ledger_fetch_only(ledger_fetch_only),.ledger_engine_only(ledger_engine_only),
  .ledger_dispatch_only(ledger_dispatch_only),
  .ledger_fetch_engine(ledger_fetch_engine),
  .ledger_dispatch_engine(ledger_dispatch_engine),
  .ledger_fetch_dispatch(ledger_fetch_dispatch),.ledger_all(ledger_all),
  .ledger_header_fetch(ledger_header_fetch),.ledger_node_fetch(ledger_node_fetch),
  .ledger_payload_fetch(ledger_payload_fetch),
  .ledger_lookahead_fetch(ledger_lookahead_fetch)
`endif
 );


 integer cyc=0;
 integer timeout=40000;
 integer errors=0;
 integer i,b;
 reg done_seen=0;
 reg [31:0] plan_base;
 reg [1023:0] memfile,outfile,tracefile,finalfile,c48file;
 integer fd,td;
 integer trace_en=0;
 reg [31:0] wtmp;
 reg [47:0] c48;
 reg [31:0] st,er,cp,ln,isost,rdp,wrp,bp;
 reg [63:0] cy,v,l,m,f,op;

 function [31:0] mapped_word(input [39:0] a);
  begin
   if (a>=40'h04000000 && a<40'h04040000)
    mapped_word = (40'h00040000 + (a-40'h04000000)) >> 2;
   else if (a>=40'h08000000 && a<40'h08040000)
    mapped_word = (40'h00080000 + (a-40'h08000000)) >> 2;
   else if (a>=40'h10000000 && a<40'h10040000)
    mapped_word = (40'h000c0000 + (a-40'h10000000)) >> 2;
   else if (a>=40'h03000000 && a<40'h03040000)
    mapped_word = (a-40'h03000000) >> 2;
   else mapped_word = 0;
  end
 endfunction
 function [7:0] byte_at(input [39:0] a);
  begin byte_at = (bfm.memw[mapped_word(a)] >> ((a&3)*8)) & 8'hff; end
 endfunction

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

 reg [31:0] t_fetch_r,t_dispatch_r,t_engine_r,t_idle_r;
 reg [31:0] t_fo_r,t_eo_r,t_do_r,t_fe_r,t_de_r,t_fd_r,t_all_r;
 reg [31:0] t_hdr_r,t_node_r,t_pay_r,t_lu_r;

 always @(posedge clk) if (rst_n) begin
  if (dut.csr.done_latched) done_seen<=1;
  if (trace_en && td != 0) begin
`ifdef BASELINE_RTL
   $fwrite(td,"%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d\n",
    cyc,busy,dut.graph.ctrl.state,dut.graph.ctrl.target,dut.graph.ctrl.e_active,
    dut.graph.ctrl.e_node[0],dut.graph.ctrl.e_node[1],dut.graph.ctrl.e_node[2],dut.graph.ctrl.e_node[3],
    dut.graph.ctrl.scan_idx,dut.graph.ctrl.nfetch_index,dut.graph.ctrl.payload_node,
    dut.graph.ctrl.payload_type,dut.graph.ctrl.completed,dut.graph.ctrl.done_mask[31:0],
    vector_busy,layout_busy,matrix_busy,rd_pending,wr_pending,b_pending,
    dut.graph.ctrl.fault_latched,isolation_req,0,0);
`else
   $fwrite(td,"%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d\n",
    cyc,busy,dut.graph.ctrl.state,dut.graph.ctrl.target,dut.graph.ctrl.e_active,
    dut.graph.ctrl.e_node[0],dut.graph.ctrl.e_node[1],dut.graph.ctrl.e_node[2],dut.graph.ctrl.e_node[3],
    dut.graph.ctrl.scan_idx,dut.graph.ctrl.nfetch_index,dut.graph.ctrl.payload_node,
    dut.graph.ctrl.payload_type,dut.graph.ctrl.completed,dut.graph.ctrl.done_mask[31:0],
    vector_busy,layout_busy,matrix_busy,rd_pending,wr_pending,b_pending,
    dut.graph.ctrl.fault_latched,isolation_req,dut.graph.ctrl.lu_valid,dut.graph.ctrl.lu_busy,
    dut.graph.ctrl.lu_cand,dut.graph.ctrl.lk_found,dut.graph.ctrl.has_seq,seq_active,dut.graph.ctrl.lu_skip_valid,
    dut.graph.ctrl.lu_req_node,dut.graph.ctrl.lu_node);
`endif
  end
 end

 initial begin
  if (!$value$plusargs("memfile=%s", memfile)) memfile="fixtures/mem_normal.hex";
  if (!$value$plusargs("finalfile=%s", finalfile)) finalfile="logs/gp_final.hex";
  if (!$value$plusargs("c48file=%s", c48file)) c48file="logs/gp_c48.hex";
  if (!$value$plusargs("watchdog=%d", timeout)) timeout=40000;
  if (!$value$plusargs("plan=%d", plan_base)) plan_base=32'h10008000;
  if ($value$plusargs("trace=%s", tracefile)) trace_en=1;
  else trace_en=0;
  if (trace_en) td=$fopen(tracefile,"w");
  else td=0;
  if (trace_en) $fwrite(td,"cyc,busy,state,target,e_active,e_node0,e_node1,e_node2,e_node3,scan_idx,nfetch_idx,payload_node,payload_type,completed,done_mask,vec_busy,lay_busy,mat_busy,rd_pending,wr_pending,b_pending,fault,iso,lu_valid,lu_busy,lu_cand,lk_found,has_seq,seq_active,lu_skip,lu_req_node,lu_node\n");

  rst_n=0;
  repeat (12) @(posedge clk);
  rst_n=1;
  repeat (5) @(posedge clk);
  csr_write(24'h08, plan_base);
  csr_write(24'h0c, 32'd1);
  csr_write(24'h10, 32'd1);
  while (!done_seen && !fault && cyc < timeout) begin
   @(posedge clk);
   if (cyc % 5000 == 0)
    $display("GP_WAIT cyc=%0d busy=%0d fault=%0d err=%02x iso=%0d rd=%0d wr=%0d b=%0d",
      cyc,busy,fault,error_code,isolation_req,rd_pending,wr_pending,b_pending);
  end
  repeat (20) @(posedge clk);

  csr_read(24'h04,st);
  csr_read(24'h1c,er);
  csr_read(24'h14,cp);
  csr_read(24'h18,ln);
  read64(24'h20,cy);
  read64(24'h30,f);
  read64(24'h38,op);
  read64(24'h40,v);
  read64(24'h48,l);
  read64(24'hA0,m);
  csr_read(24'hB0,isost);
  csr_read(24'hB4,rdp);
  csr_read(24'hB8,wrp);
  csr_read(24'hBC,bp);

  // Final I16 output (same offset as the v023 safety TB).
  fd=$fopen(finalfile,"w");
  for (i=0;i<512;i=i+1) $fwrite(fd,"%08x\n",bfm.memw[32'h12000+i]);
  $fclose(fd);
  // Matrix C48 (1024 x 48-bit little-endian) from ARENA_C.
  fd=$fopen(c48file,"w");
  for (i=0;i<1024;i=i+1) begin
   c48 = 0;
   for (b=0;b<6;b=b+1) c48 = c48 | ({40'd0,byte_at(32'h04002000 + i*6 + b)} << (8*b));
   $fwrite(fd,"%012x\n",c48);
  end
  $fclose(fd);

  $display("GP_CSR status=%08x err=%02x completed=%0d last=%0d cycles=%0d fetch=%0d op=%0d",
    st,er,cp,ln,cy,f,op);
  $display("GP_CSR vec_total=%0d layout_total=%0d matrix_total=%0d vec_ops=%0d layout_ops=%0d matrix_ops=%0d",
    v,l,m,vector_op_count,layout_op_count,matrix_op_count);
  $display("GP_CSR last_vec=%0d last_lay=%0d last_mat=%0d",vector_cycles,layout_cycles,matrix_cycles);
  $display("GP_DRAIN rd_pending=%0d wr_pending=%0d b_pending=%0d quiesced=%0d iso=%0d",
    rd_pending,wr_pending,b_pending,port_quiesced,isolation_req);
  $display("GP_AXI rburst=%0d wburst=%0d rbeats=%0d wbeats=%0d tag_err=%0d peak_rd=%0d peak_wr=%0d",
    rd_bursts,wr_bursts,r_beats,w_beats,axi_tag_errors,rd_peak,wr_peak);
  $display("GP_END done=%0d fault=%0d error=%02x iso=%0d requires_reset=%0d cycles=%0d",
    dut.csr.done_latched,fault,error_code,isolation_req,requires_reset,cy);
`ifndef BASELINE_RTL
  $display("GP_LU valid=%0d hits=%0d misses=%0d fetches=%0d aborts=%0d epoch=%0d",
    lookahead_valid,lookahead_hits,lookahead_misses,lookahead_fetches,lookahead_aborts,lookahead_epoch);
  $display("GP_LEDGER fetch=%0d dispatch=%0d engine=%0d idle=%0d",ledger_fetch,ledger_dispatch,ledger_engine,ledger_idle);
  $display("GP_LEDGER_X fetch_only=%0d engine_only=%0d dispatch_only=%0d fetch_engine=%0d dispatch_engine=%0d fetch_dispatch=%0d all=%0d",
    ledger_fetch_only,ledger_engine_only,ledger_dispatch_only,ledger_fetch_engine,
    ledger_dispatch_engine,ledger_fetch_dispatch,ledger_all);
  $display("GP_LEDGER_F fetch_hdr=%0d fetch_node=%0d fetch_payload=%0d fetch_lookahead=%0d",
    ledger_header_fetch,ledger_node_fetch,ledger_payload_fetch,ledger_lookahead_fetch);
`endif

  if (!dut.csr.done_latched) begin $display("GP_FAIL no_done"); errors=errors+1; end
  if (fault) begin $display("GP_FAIL fault"); errors=errors+1; end
  if (!port_quiesced || rd_pending!=0 || wr_pending!=0 || b_pending!=0) begin
   $display("GP_FAIL drain"); errors=errors+1;
  end
  if (axi_tag_errors!=0) begin $display("GP_FAIL tag_err"); errors=errors+1; end
  if (completed!=9) begin $display("GP_FAIL completed=%0d",completed); errors=errors+1; end
  if (cyc>=timeout) begin $display("GP_FAIL timeout"); errors=errors+1; end
  if (trace_en) $fclose(td);

`ifndef BASELINE_RTL
  // Exclusive-union invariant from the RTL counters.
  if ((ledger_fetch_only+ledger_engine_only+ledger_dispatch_only+
       ledger_fetch_engine+ledger_dispatch_engine+ledger_fetch_dispatch+
       ledger_all+ledger_idle) != cy) begin
   $display("GP_FAIL ledger_sum=%0d cycles=%0d",
    (ledger_fetch_only+ledger_engine_only+ledger_dispatch_only+
     ledger_fetch_engine+ledger_dispatch_engine+ledger_fetch_dispatch+
     ledger_all+ledger_idle),cy);
   errors=errors+1;
  end
`endif

  if (errors) begin $display("GP_RESULT FAIL errors=%0d",errors); $fatal(1); end
  else $display("GP_RESULT PASS");
  $finish;
 end

 always @(posedge clk) begin
  cyc <= cyc+1;
  if (cyc > timeout+2000) begin
   $display("GP_GLOBAL_TIMEOUT cyc=%0d busy=%0d fault=%0d err=%02x iso=%0d rd=%0d wr=%0d b=%0d",
     cyc,busy,fault,error_code,isolation_req,rd_pending,wr_pending,b_pending);
   $fatal(1);
  end
 end
endmodule
