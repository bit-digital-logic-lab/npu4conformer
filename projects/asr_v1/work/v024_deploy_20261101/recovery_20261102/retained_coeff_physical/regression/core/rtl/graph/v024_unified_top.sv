`timescale 1ns/1ps
// V0.23 integrated single-clock logic candidate.
//
// One CSR START submits one preloaded WCPG v2 superplan.  From then on the PL
// graph controller fetches nodes, the MAT child fetches V022 queue descriptors
// and drives the matrix cluster, and vector/layout children execute their
// descriptors.  All data DMA masters share one AXI128 port through
// v023_axi_shared (tagged in-order read FIFO, write AW order, per-master
// credit).  The host does not issue per-node or per-block DMA.
//
// Scope: logic simulation only.  Single clock; no CDC/async FIFO is assumed or
// implemented.  No synthesis/STA/board/DDR-PHY claim.
module v024_unified_top #(
 // AXU15EGB bounded small-graph deployment; not a 591-node model configuration.
 parameter integer MAX_NODES = 128,
 parameter integer PIPE_STAGES = 4,
 parameter integer MAX_PREFETCH = 16,
 parameter integer USE_APPROX_DIV_SQRT = 1,
 parameter integer MATRIX_WATCHDOG = 500000,
 parameter integer VEC_WATCHDOG = 200000,
 parameter integer LAY_WATCHDOG = 200000,
 parameter integer SEQ_WATCHDOG = 200000,
 parameter integer FETCH_WATCHDOG = 200000,
 parameter [63:0] DRAIN_WATCHDOG = 64'd200000000,
 parameter integer SEQ_ENABLE = 0,
 parameter [31:0] PARAM_END = 32'h10040000
)(
 input wire clk,
 input wire rst_n,

 // External SEQ child handshake.  SEQ_ENABLE=0 keeps the original integrated
 // behaviour (ready tied low, no SEQ node can start).  SEQ_ENABLE=1 lets a
 // test or the sealed V022 executor drive this port.
 input  wire        seq_ready_i,
 input  wire        seq_done_i,
 input  wire        seq_fault_i,
 input  wire [7:0]  seq_error_i,
 output wire        seq_valid_o,
 output wire [31:0] seq_base_o,
 output wire [31:0] seq_count_o,

 // control/status CSR (AXI4-Lite, 24-bit address)
 input  wire [23:0] s_axi_awaddr,
 input  wire        s_axi_awvalid,
 output wire        s_axi_awready,
 input  wire [31:0] s_axi_wdata,
 input  wire [3:0]  s_axi_wstrb,
 input  wire        s_axi_wvalid,
 output wire        s_axi_wready,
 output wire [1:0]  s_axi_bresp,
 output wire        s_axi_bvalid,
 input  wire        s_axi_bready,
 input  wire [23:0] s_axi_araddr,
 input  wire        s_axi_arvalid,
 output wire        s_axi_arready,
 output wire [31:0] s_axi_rdata,
 output wire [1:0]  s_axi_rresp,
 output wire        s_axi_rvalid,
 input  wire        s_axi_rready,

 // shared AXI128 data slave port
 output wire [39:0] m_araddr,
 output wire [7:0]  m_arlen,
 output wire [2:0]  m_arsize,
 output wire [1:0]  m_arburst,
 output wire        m_arvalid,
 input  wire        m_arready,
 input  wire [127:0] m_rdata,
 input  wire [1:0]   m_rresp,
 input  wire         m_rlast,
 input  wire         m_rvalid,
 output wire         m_rready,
 output wire [39:0] m_awaddr,
 output wire [7:0]  m_awlen,
 output wire [2:0]  m_awsize,
 output wire [1:0]  m_awburst,
 output wire        m_awvalid,
 input  wire        m_awready,
 output wire [127:0] m_wdata,
 output wire [15:0]  m_wstrb,
 output wire         m_wlast,
 output wire         m_wvalid,
 input  wire         m_wready,
 input  wire [1:0]   m_bresp,
 input  wire         m_bvalid,
 output wire         m_bready,

 // V0.24 host one-time per-channel parameter preload (not per-tile DMA).
 // addr 0..31 scale, 32..63 bias, 64 broadcast scale, 65 broadcast bias.
 input  wire         pc_wr_valid,
 output wire         pc_wr_ready,
 input  wire [7:0]   pc_wr_addr,
 input  wire [31:0]  pc_wr_data,
 output wire         matrix_fused_used,
 output wire [31:0]  fuse_c48_ddr_bytes,
 output wire [31:0]  fuse_a16_bytes,

 // status / telemetry
 output wire busy,
 output wire done,
 output wire fault,
 output wire irq,
 output wire drain_timeout,
 output wire [7:0] error_code,
 output wire [31:0] completed,
 output wire [31:0] last_node,
 output wire [63:0] cycles,
 output wire seq_active,
 output wire vector_busy,
 output wire layout_busy,
 output wire matrix_busy,
 output wire [7:0] matrix_error,
 output wire [63:0] matrix_cycles,
 output wire [31:0] matrix_compute_cycles,
 output wire [63:0] vector_cycles,
 output wire [63:0] layout_cycles,
 output wire [31:0] vector_read_bytes,
 output wire [31:0] vector_write_bytes,
 output wire [31:0] layout_read_bytes,
 output wire [31:0] layout_write_bytes,
 output wire [31:0] rd_bursts,
 output wire [31:0] wr_bursts,
 output wire [31:0] r_beats,
 output wire [31:0] w_beats,
 output wire [31:0] rd_peak,
 output wire [31:0] wr_peak,
 output wire [31:0] rd_stall_cycles,
 output wire [31:0] wr_stall_cycles,
 output wire [31:0] axi_tag_errors,
 // terminal-isolation / drain-boundary contract
 output wire isolation_req,
 output wire requires_reset,
 output wire port_quiesced,
 output wire [31:0] rd_pending,
 output wire [31:0] wr_pending,
 output wire [31:0] b_pending,
 output wire [31:0] iso_blocked_reqs,
 output wire seq_dispatch_timeout,
 output wire seq_inflight_timeout,
 output wire fetch_timeout,
 // per-operation totals (not last-operation snapshots)
 output wire [63:0] vector_total_cycles,
 output wire [63:0] layout_total_cycles,
 output wire [63:0] matrix_total_cycles,
 output wire [31:0] vector_op_count,
 output wire [31:0] layout_op_count,
 output wire [31:0] matrix_op_count
);
 // CSR <-> graph
 wire csr_start;
 wire [31:0] csr_plan_base, csr_plan_count;
 wire csr_irq;

 // graph status / terminal isolation
 wire graph_iso, graph_req_rst, graph_seq_dto, graph_seq_ito, graph_fetch_to;
 wire [31:0] graph_seq_wait, graph_seq_run, graph_rejected_starts;
 wire [63:0] graph_fetch_cycles, graph_op_cycles;
 wire matrix_iso, matrix_req_rst, vec_iso, vec_req_rst, lay_iso, lay_req_rst;
 wire iso_all;
 wire [31:0] x_rd_pending, x_wr_pending, x_b_pending, x_iso_blocked;
 wire x_quiesced;
 reg requires_reset_r;
 wire [63:0] vec_total_cycles, lay_total_cycles;
 wire [31:0] vec_ops, lay_ops;
 wire [63:0] mat_total_cycles;
 wire [31:0] mat_ops;
 wire seq_ready_eff, seq_done_eff, seq_fault_eff;
 wire [7:0] seq_error_eff;

 assign seq_ready_eff = SEQ_ENABLE ? seq_ready_i : 1'b0;
 assign seq_done_eff  = SEQ_ENABLE ? seq_done_i  : 1'b0;
 assign seq_fault_eff = SEQ_ENABLE ? seq_fault_i : 1'b0;
 assign seq_error_eff = SEQ_ENABLE ? seq_error_i : 8'd0;
 assign iso_all = graph_iso | matrix_iso | vec_iso | lay_iso;
 assign isolation_req = iso_all;
 always @(posedge clk) begin
  if(!rst_n) requires_reset_r <= 0;
  else if(iso_all || graph_req_rst) requires_reset_r <= 1;
 end
 assign requires_reset = requires_reset_r;
 assign port_quiesced = x_quiesced;
 assign rd_pending = x_rd_pending;
 assign wr_pending = x_wr_pending;
 assign b_pending = x_b_pending;
 assign iso_blocked_reqs = x_iso_blocked;
 assign seq_dispatch_timeout = graph_seq_dto;
 assign seq_inflight_timeout = graph_seq_ito;
 assign fetch_timeout = graph_fetch_to;
 assign vector_total_cycles = vec_total_cycles;
 assign layout_total_cycles = lay_total_cycles;
 assign matrix_total_cycles = mat_total_cycles;
 assign vector_op_count = vec_ops;
 assign layout_op_count = lay_ops;
 assign matrix_op_count = mat_ops;

 // graph <-> engines
 wire graph_matrix_valid, graph_matrix_done, graph_matrix_fault;
 wire [31:0] graph_matrix_base, graph_matrix_count;
 wire graph_matrix_fused, graph_matrix_pc_en, graph_matrix_relu;
 wire [31:0] graph_matrix_pc_base;
 wire [1:0] graph_matrix_fma_mode;
 wire [7:0] graph_vec_flags, graph_vec_error, graph_lay_error;
 wire [63:0] graph_vec_cycles, graph_lay_cycles, graph_vec_ro, graph_vec_wo;
 wire [31:0] graph_vec_rb, graph_vec_wb, graph_lay_rb, graph_lay_wb;
 wire [31:0] graph_vec_elems, graph_lay_elems, graph_lay_hits, graph_lay_misses;
 wire graph_vec_done, graph_lay_done;

 // graph fetch AXI
 wire [39:0] sf_araddr; wire [7:0] sf_arlen; wire [2:0] sf_arsize;
 wire [1:0] sf_arburst; wire [3:0] sf_arcache; wire [2:0] sf_arprot;
 wire sf_arvalid, sf_arready, sf_rlast, sf_rvalid, sf_rready;
 wire [127:0] sf_rdata; wire [1:0] sf_rresp;
 wire [39:0] sf_awaddr; wire [7:0] sf_awlen; wire [2:0] sf_awsize;
 wire [1:0] sf_awburst; wire [3:0] sf_awcache; wire [2:0] sf_awprot;
 wire sf_awvalid; wire [127:0] sf_wdata; wire [15:0] sf_wstrb;
 wire sf_wlast, sf_wvalid; wire [1:0] sf_bresp; wire sf_bvalid, sf_bready;

 // vector AXI masters
 wire [39:0] vr_araddr; wire [7:0] vr_arlen; wire [2:0] vr_arsize;
 wire [1:0] vr_arburst; wire [3:0] vr_arcache; wire [2:0] vr_arprot;
 wire vr_arvalid, vr_arready, vr_rlast, vr_rvalid, vr_rready;
 wire [127:0] vr_rdata; wire [1:0] vr_rresp;
 wire [39:0] vw_awaddr; wire [7:0] vw_awlen; wire [2:0] vw_awsize;
 wire [1:0] vw_awburst; wire [3:0] vw_awcache; wire [2:0] vw_awprot;
 wire vw_awvalid, vw_awready, vw_wlast, vw_wvalid, vw_wready;
 wire [127:0] vw_wdata; wire [15:0] vw_wstrb; wire [1:0] vw_bresp;
 wire vw_bvalid, vw_bready;

 // layout AXI masters
 wire [39:0] lr_araddr; wire [7:0] lr_arlen; wire [2:0] lr_arsize;
 wire [1:0] lr_arburst; wire [3:0] lr_arcache; wire [2:0] lr_arprot;
 wire lr_arvalid, lr_arready, lr_rlast, lr_rvalid, lr_rready;
 wire [127:0] lr_rdata; wire [1:0] lr_rresp;
 wire [39:0] lw_awaddr; wire [7:0] lw_awlen; wire [2:0] lw_awsize;
 wire [1:0] lw_awburst; wire [3:0] lw_awcache; wire [2:0] lw_awprot;
 wire lw_awvalid, lw_awready, lw_wlast, lw_wvalid, lw_wready;
 wire [127:0] lw_wdata; wire [15:0] lw_wstrb; wire [1:0] lw_bresp;
 wire lw_bvalid, lw_bready;

 // matrix AXI
 wire [39:0] q_araddr; wire [7:0] q_arlen; wire [2:0] q_arsize;
 wire [1:0] q_arburst; wire q_arvalid, q_arready, q_rlast, q_rvalid, q_rready;
 wire [127:0] q_rdata; wire [1:0] q_rresp;
 wire [39:0] mr_araddr; wire [7:0] mr_arlen; wire [2:0] mr_arsize;
 wire [1:0] mr_arburst; wire mr_arvalid, mr_arready, mr_rlast, mr_rvalid, mr_rready;
 wire [127:0] mr_rdata; wire [1:0] mr_rresp;
 wire [39:0] mw_awaddr; wire [7:0] mw_awlen; wire [2:0] mw_awsize;
 wire [1:0] mw_awburst; wire mw_awvalid, mw_awready, mw_wlast, mw_wvalid, mw_wready;
 wire [127:0] mw_wdata; wire [15:0] mw_wstrb; wire [1:0] mw_bresp;
 wire mw_bvalid, mw_bready;

 wire [31:0] matrix_rejected, matrix_current;
 wire [63:0] matrix_qcycles, matrix_fcycles, matrix_ewait, matrix_rwait;
 wire [31:0] matrix_rb, matrix_wb, matrix_hits, matrix_misses;
 wire [31:0] matrix_cg, matrix_cc;
 wire [7:0] matrix_pd, matrix_ad;
 wire matrix_wd_fired;

 // ---------------- CSR ----------------
 plan_submit_csr_v023 csr (
  .clk(clk),.rst_n(rst_n),
  .s_axi_awaddr(s_axi_awaddr),.s_axi_awvalid(s_axi_awvalid),.s_axi_awready(s_axi_awready),
  .s_axi_wdata(s_axi_wdata),.s_axi_wstrb(s_axi_wstrb),.s_axi_wvalid(s_axi_wvalid),.s_axi_wready(s_axi_wready),
  .s_axi_bresp(s_axi_bresp),.s_axi_bvalid(s_axi_bvalid),.s_axi_bready(s_axi_bready),
  .s_axi_araddr(s_axi_araddr),.s_axi_arvalid(s_axi_arvalid),.s_axi_arready(s_axi_arready),
  .s_axi_rdata(s_axi_rdata),.s_axi_rresp(s_axi_rresp),.s_axi_rvalid(s_axi_rvalid),.s_axi_rready(s_axi_rready),
  .start(csr_start),.plan_base(csr_plan_base),.plan_count(csr_plan_count),
  .parameter_ready(1'b1),.generation(32'd0),.param_end(PARAM_END),
  .busy(busy),.done(done),.fault(fault),.error_code(error_code),
  .lockout(requires_reset),.isolation(iso_all),.requires_reset(requires_reset),
  .port_quiesced(x_quiesced),.rd_pending(x_rd_pending),.wr_pending(x_wr_pending),
  .b_pending(x_b_pending),.iso_blocked(x_iso_blocked),
  .completed(completed),.index(last_node),.rejected_starts(graph_rejected_starts),.last_ticket(32'd0),
  .cycles(cycles),.fetch_cycles(graph_fetch_cycles),.operator_cycles(graph_op_cycles),
  .matrix_done(graph_matrix_done),.matrix_cycles(mat_total_cycles),
  .matrix_pe_cycles({32'd0,matrix_compute_cycles}),
  .vector_done(graph_vec_done),.layout_done(graph_lay_done),
  .vector_numeric_flags(graph_vec_flags),.vector_error_code(graph_vec_error),
  .layout_error_code(graph_lay_error),
  .vector_cycles(graph_vec_cycles),.layout_cycles(graph_lay_cycles),
  .vector_read_compute_overlap(graph_vec_ro),.vector_write_compute_overlap(graph_vec_wo),
  .vector_read_bytes(graph_vec_rb),.vector_write_bytes(graph_vec_wb),
  .layout_read_bytes(graph_lay_rb),.layout_write_bytes(graph_lay_wb),
  .vector_completed_elements(graph_vec_elems),.layout_processed_elements(graph_lay_elems),
  .layout_cache_hits(graph_lay_hits),.layout_cache_misses(graph_lay_misses),
  .irq(irq)
 );
 assign csr_irq = irq;

 // ---------------- graph controller + vector/layout ----------------
 wc_graph_top_v023 #(.MAX_NODES(MAX_NODES),.ARENA_BASE(32'h04000000),.ARENA_LIMIT(32'h08000000),
  .SEQ_WATCHDOG(SEQ_WATCHDOG),.FETCH_WATCHDOG(FETCH_WATCHDOG),
  .VEC_WATCHDOG(VEC_WATCHDOG),.LAY_WATCHDOG(LAY_WATCHDOG),
  .MAX_PREFETCH(MAX_PREFETCH),.DRAIN_WATCHDOG(DRAIN_WATCHDOG),
  .USE_APPROX_DIV_SQRT(USE_APPROX_DIV_SQRT)) graph (
  .clk(clk),.rst_n(rst_n),.start(csr_start),.plan_base(csr_plan_base),
  .param_end(PARAM_END),.parameter_ready(1'b1),.generation(32'd0),
  .busy(busy),.done(done),.fault(fault),.irq(),.drain_timeout(drain_timeout),
  .isolation_req(graph_iso),.requires_reset(graph_req_rst),
  .seq_dispatch_timeout(graph_seq_dto),.seq_inflight_timeout(graph_seq_ito),
  .fetch_timeout(graph_fetch_to),.seq_wait_cycles(graph_seq_wait),
  .seq_run_cycles(graph_seq_run),
  .error_code(error_code),.completed(completed),.node_count(),
  .rejected_starts(graph_rejected_starts),
  .last_node(last_node),.done_mask(),.cycles(cycles),
  .fetch_cycles(graph_fetch_cycles),.operator_cycles(graph_op_cycles),
  .drain_cycles(),.output_retained(),.output_count(),.last_output_tid(),
  .last_output_base(),.last_output_bytes(),
  .seq_busy(),.seq_active(seq_active),.vector_busy(vector_busy),.layout_busy(layout_busy),
  .vec_done_pulse(graph_vec_done),.lay_done_pulse(graph_lay_done),.mat_done_pulse(),
  .matrix_error(matrix_error),
  .vector_numeric_flags(graph_vec_flags),.vector_error_code(graph_vec_error),
  .layout_error_code(graph_lay_error),
  .vector_cycles_o(graph_vec_cycles),.layout_cycles_o(graph_lay_cycles),
  .vector_ro_o(graph_vec_ro),.vector_wo_o(graph_vec_wo),
  .vector_total_cycles_o(vec_total_cycles),.layout_total_cycles_o(lay_total_cycles),
  .vector_op_count_o(vec_ops),.layout_op_count_o(lay_ops),
  .vector_isolation(vec_iso),.layout_isolation(lay_iso),
  .vector_read_bytes_o(graph_vec_rb),.vector_write_bytes_o(graph_vec_wb),
  .layout_read_bytes_o(graph_lay_rb),.layout_write_bytes_o(graph_lay_wb),
  .vector_elements_o(graph_vec_elems),.layout_elements_o(graph_lay_elems),
  .layout_hits_o(graph_lay_hits),.layout_misses_o(graph_lay_misses),
  .seq_valid(seq_valid_o),.seq_ready(seq_ready_eff),.seq_base(seq_base_o),
  .seq_count(seq_count_o),.seq_done(seq_done_eff),
  .seq_fault(seq_fault_eff),.seq_error(seq_error_eff),
  .matrix_valid(graph_matrix_valid),.matrix_ready(!matrix_busy),
  .matrix_queue_base(graph_matrix_base),.matrix_queue_count(graph_matrix_count),
  .matrix_done(graph_matrix_done),.matrix_fault(graph_matrix_fault),
  .matrix_fused(graph_matrix_fused),.matrix_pc_en(graph_matrix_pc_en),
  .matrix_pc_base(graph_matrix_pc_base),.matrix_fma_mode(graph_matrix_fma_mode),
  .matrix_relu(graph_matrix_relu),
  .sf_araddr(sf_araddr),.sf_arlen(sf_arlen),.sf_arsize(sf_arsize),
  .sf_arburst(sf_arburst),.sf_arcache(sf_arcache),.sf_arprot(sf_arprot),
  .sf_arvalid(sf_arvalid),.sf_arready(sf_arready),.sf_rdata(sf_rdata),
  .sf_rresp(sf_rresp),.sf_rlast(sf_rlast),.sf_rvalid(sf_rvalid),.sf_rready(sf_rready),
  .sf_awaddr(sf_awaddr),.sf_awlen(sf_awlen),.sf_awsize(sf_awsize),
  .sf_awburst(sf_awburst),.sf_awcache(sf_awcache),.sf_awprot(sf_awprot),
  .sf_awvalid(sf_awvalid),.sf_awready(1'b1),.sf_wdata(sf_wdata),.sf_wstrb(sf_wstrb),
  .sf_wlast(sf_wlast),.sf_wvalid(sf_wvalid),.sf_wready(1'b1),.sf_bresp(2'd0),
  .sf_bvalid(1'b0),.sf_bready(),
  .vr_araddr(vr_araddr),.vr_arlen(vr_arlen),.vr_arsize(vr_arsize),
  .vr_arburst(vr_arburst),.vr_arcache(vr_arcache),.vr_arprot(vr_arprot),
  .vr_arvalid(vr_arvalid),.vr_arready(vr_arready),.vr_rdata(vr_rdata),
  .vr_rresp(vr_rresp),.vr_rlast(vr_rlast),.vr_rvalid(vr_rvalid),.vr_rready(vr_rready),
  .vw_awaddr(vw_awaddr),.vw_awlen(vw_awlen),.vw_awsize(vw_awsize),
  .vw_awburst(vw_awburst),.vw_awcache(vw_awcache),.vw_awprot(vw_awprot),
  .vw_awvalid(vw_awvalid),.vw_awready(vw_awready),.vw_wdata(vw_wdata),
  .vw_wstrb(vw_wstrb),.vw_wlast(vw_wlast),.vw_wvalid(vw_wvalid),.vw_wready(vw_wready),
  .vw_bresp(vw_bresp),.vw_bvalid(vw_bvalid),.vw_bready(vw_bready),
  .lr_araddr(lr_araddr),.lr_arlen(lr_arlen),.lr_arsize(lr_arsize),
  .lr_arburst(lr_arburst),.lr_arcache(lr_arcache),.lr_arprot(lr_arprot),
  .lr_arvalid(lr_arvalid),.lr_arready(lr_arready),.lr_rdata(lr_rdata),
  .lr_rresp(lr_rresp),.lr_rlast(lr_rlast),.lr_rvalid(lr_rvalid),.lr_rready(lr_rready),
  .lw_awaddr(lw_awaddr),.lw_awlen(lw_awlen),.lw_awsize(lw_awsize),
  .lw_awburst(lw_awburst),.lw_awcache(lw_awcache),.lw_awprot(lw_awprot),
  .lw_awvalid(lw_awvalid),.lw_awready(lw_awready),.lw_wdata(lw_wdata),
  .lw_wstrb(lw_wstrb),.lw_wlast(lw_wlast),.lw_wvalid(lw_wvalid),.lw_wready(lw_wready),
  .lw_bresp(lw_bresp),.lw_bvalid(lw_bvalid),.lw_bready(lw_bready)
 );

 // ---------------- matrix queue child ----------------
 v024_matrix_queue_engine #(
  .ARENA_BASE(32'h04000000),.ARENA_END(32'h08000000),
  .PIPE_STAGES(PIPE_STAGES),.WATCHDOG(MATRIX_WATCHDOG)
 ) matrix (
  .clk(clk),.rst_n(rst_n),.start(graph_matrix_valid && !matrix_busy),
  .queue_base(graph_matrix_base),.queue_count(graph_matrix_count),.param_end(PARAM_END),
  .fused(graph_matrix_fused),.fuse_fma_mode(graph_matrix_fma_mode),
  .fuse_relu(graph_matrix_relu),.fuse_perchannel_en(graph_matrix_pc_en),
  .fuse_scale(32'h3f800000),.fuse_bias(32'd0),
  .pc_wr_valid(pc_wr_valid),.pc_wr_ready(pc_wr_ready),
  .pc_wr_addr(pc_wr_addr),.pc_wr_data(pc_wr_data),
  .fused_used(matrix_fused_used),.fuse_c48_ddr_bytes(fuse_c48_ddr_bytes),
  .fuse_a16_bytes(fuse_a16_bytes),
  .busy(matrix_busy),.done(graph_matrix_done),.fault(graph_matrix_fault),
  .error_code(matrix_error),.completed_tasks(),.current_index(matrix_current),
  .rejected_starts(matrix_rejected),.queue_cycles(matrix_qcycles),.fetch_cycles(matrix_fcycles),
  .engine_wait_cycles(matrix_ewait),.retire_wait_cycles(matrix_rwait),
  .compute_cycles(matrix_compute_cycles),.read_blocks(matrix_rb),.write_blocks(matrix_wb),
  .cache_hits(matrix_hits),.cache_misses(matrix_misses),
  .c_collect_groups(matrix_cg),.c_collect_cycles(matrix_cc),
  .pe_drain_cycles(matrix_pd),.array_drain_cycles(matrix_ad),
  .isolation_req(matrix_iso),.watchdog_fired(matrix_wd_fired),
  .requires_reset(matrix_req_rst),
  .matrix_cycles(matrix_cycles),.matrix_total_cycles(mat_total_cycles),
  .matrix_total_compute(),.matrix_total_rb(),.matrix_total_wb(),
  .matrix_op_count(mat_ops),
  .q_araddr(q_araddr),.q_arlen(q_arlen),.q_arsize(q_arsize),.q_arburst(q_arburst),
  .q_arvalid(q_arvalid),.q_arready(q_arready),.q_rdata(q_rdata),.q_rresp(q_rresp),
  .q_rlast(q_rlast),.q_rvalid(q_rvalid),.q_rready(q_rready),
  .rd_araddr(mr_araddr),.rd_arlen(mr_arlen),.rd_arsize(mr_arsize),.rd_arburst(mr_arburst),
  .rd_arvalid(mr_arvalid),.rd_arready(mr_arready),.rd_rdata(mr_rdata),.rd_rresp(mr_rresp),
  .rd_rlast(mr_rlast),.rd_rvalid(mr_rvalid),.rd_rready(mr_rready),
  .wr_awaddr(mw_awaddr),.wr_awlen(mw_awlen),.wr_awsize(mw_awsize),.wr_awburst(mw_awburst),
  .wr_awvalid(mw_awvalid),.wr_awready(mw_awready),.wr_wdata(mw_wdata),.wr_wstrb(mw_wstrb),
  .wr_wlast(mw_wlast),.wr_wvalid(mw_wvalid),.wr_wready(mw_wready),
  .wr_bresp(mw_bresp),.wr_bvalid(mw_bvalid),.wr_bready(mw_bready)
 );

 // ---------------- shared AXI concentrator ----------------
 wire [4:0] xr_arvalid = {q_arvalid, mr_arvalid, lr_arvalid, vr_arvalid, sf_arvalid};
 wire [4:0] xr_arready;
 wire [5*40-1:0] xr_araddr = {q_araddr, mr_araddr, lr_araddr, vr_araddr, sf_araddr};
 wire [5*8-1:0]  xr_arlen  = {q_arlen, mr_arlen, lr_arlen, vr_arlen, sf_arlen};
 wire [5*3-1:0]  xr_arsize = {q_arsize, mr_arsize, lr_arsize, vr_arsize, sf_arsize};
 wire [5*2-1:0]  xr_arburst= {q_arburst, mr_arburst, lr_arburst, vr_arburst, sf_arburst};
 wire [5*128-1:0] xr_rdata;
 wire [5*2-1:0]   xr_rresp;
 wire [4:0]       xr_rlast, xr_rvalid;
 wire [4:0]       xr_rready = {q_rready, mr_rready, lr_rready, vr_rready, sf_rready};

 wire [2:0] xw_awvalid = {mw_awvalid, lw_awvalid, vw_awvalid};
 wire [2:0] xw_awready;
 wire [3*40-1:0] xw_awaddr = {mw_awaddr, lw_awaddr, vw_awaddr};
 wire [3*8-1:0]  xw_awlen  = {mw_awlen, lw_awlen, vw_awlen};
 wire [3*3-1:0]  xw_awsize = {mw_awsize, lw_awsize, vw_awsize};
 wire [3*2-1:0]  xw_awburst= {mw_awburst, lw_awburst, vw_awburst};
 wire [3*128-1:0] xw_wdata = {mw_wdata, lw_wdata, vw_wdata};
 wire [3*16-1:0]  xw_wstrb = {mw_wstrb, lw_wstrb, vw_wstrb};
 wire [2:0]       xw_wlast = {mw_wlast, lw_wlast, vw_wlast};
 wire [2:0]       xw_wvalid= {mw_wvalid, lw_wvalid, vw_wvalid};
 wire [2:0]       xw_wready;
 wire [2:0]       xw_bready= {mw_bready, lw_bready, vw_bready};
 wire [3*2-1:0]   xw_bresp;
 wire [2:0]       xw_bvalid;

 v023_axi_shared #(.NR(5),.NW(3),.CREDIT(8),.QDEPTH(32)) xbar (
  .clk(clk),.rst_n(rst_n),.isolate(iso_all),
  .m_arvalid(xr_arvalid),.m_arready(xr_arready),.m_araddr(xr_araddr),
  .m_arlen(xr_arlen),.m_arsize(xr_arsize),.m_arburst(xr_arburst),
  .m_rdata(xr_rdata),.m_rresp(xr_rresp),.m_rlast(xr_rlast),.m_rvalid(xr_rvalid),
  .m_rready(xr_rready),
  .s_araddr(m_araddr),.s_arlen(m_arlen),.s_arsize(m_arsize),.s_arburst(m_arburst),
  .s_arvalid(m_arvalid),.s_arready(m_arready),.s_rdata(m_rdata),.s_rresp(m_rresp),
  .s_rlast(m_rlast),.s_rvalid(m_rvalid),.s_rready(m_rready),
  .m_awvalid(xw_awvalid),.m_awready(xw_awready),.m_awaddr(xw_awaddr),
  .m_awlen(xw_awlen),.m_awsize(xw_awsize),.m_awburst(xw_awburst),
  .m_wdata(xw_wdata),.m_wstrb(xw_wstrb),.m_wlast(xw_wlast),.m_wvalid(xw_wvalid),
  .m_wready(xw_wready),.m_bready(xw_bready),.m_bresp(xw_bresp),.m_bvalid(xw_bvalid),
  .s_awaddr(m_awaddr),.s_awlen(m_awlen),.s_awsize(m_awsize),.s_awburst(m_awburst),
  .s_awvalid(m_awvalid),.s_awready(m_awready),.s_wdata(m_wdata),.s_wstrb(m_wstrb),
  .s_wlast(m_wlast),.s_wvalid(m_wvalid),.s_wready(m_wready),.s_bresp(m_bresp),
  .s_bvalid(m_bvalid),.s_bready(m_bready),
  .rd_bursts(rd_bursts),.wr_bursts(wr_bursts),.r_beats(r_beats),.w_beats(w_beats),
  .rd_peak(rd_peak),.wr_peak(wr_peak),.rd_stall_cycles(rd_stall_cycles),
  .wr_stall_cycles(wr_stall_cycles),.tag_errors(axi_tag_errors),
  .rd_pending(x_rd_pending),.wr_pending(x_wr_pending),.b_pending(x_b_pending),
  .quiesced(x_quiesced),.iso_blocked(x_iso_blocked)
 );

 assign vector_cycles = graph_vec_cycles;
 assign layout_cycles = graph_lay_cycles;
 assign vector_read_bytes = graph_vec_rb;
 assign vector_write_bytes = graph_vec_wb;
 assign layout_read_bytes = graph_lay_rb;
 assign layout_write_bytes = graph_lay_wb;
 assign sf_arready = xr_arready[0]; assign vr_arready = xr_arready[1];
 assign lr_arready = xr_arready[2]; assign mr_arready = xr_arready[3];
 assign q_arready  = xr_arready[4];
 assign sf_rdata = xr_rdata[0*128 +: 128]; assign vr_rdata = xr_rdata[1*128 +: 128];
 assign lr_rdata = xr_rdata[2*128 +: 128]; assign mr_rdata = xr_rdata[3*128 +: 128];
 assign q_rdata  = xr_rdata[4*128 +: 128];
 assign sf_rresp = xr_rresp[0*2 +: 2]; assign vr_rresp = xr_rresp[1*2 +: 2];
 assign lr_rresp = xr_rresp[2*2 +: 2]; assign mr_rresp = xr_rresp[3*2 +: 2];
 assign q_rresp  = xr_rresp[4*2 +: 2];
 assign sf_rlast = xr_rlast[0]; assign vr_rlast = xr_rlast[1];
 assign lr_rlast = xr_rlast[2]; assign mr_rlast = xr_rlast[3];
 assign q_rlast  = xr_rlast[4];
 assign sf_rvalid= xr_rvalid[0]; assign vr_rvalid= xr_rvalid[1];
 assign lr_rvalid= xr_rvalid[2]; assign mr_rvalid= xr_rvalid[3];
 assign q_rvalid = xr_rvalid[4];

 assign vw_awready = xw_awready[0]; assign lw_awready = xw_awready[1];
 assign mw_awready = xw_awready[2];
 assign vw_wready = xw_wready[0]; assign lw_wready = xw_wready[1];
 assign mw_wready = xw_wready[2];
 assign vw_bvalid = xw_bvalid[0]; assign lw_bvalid = xw_bvalid[1];
 assign mw_bvalid = xw_bvalid[2];
 assign vw_bresp = xw_bresp[0*2 +: 2]; assign lw_bresp = xw_bresp[1*2 +: 2];
 assign mw_bresp = xw_bresp[2*2 +: 2];

endmodule
