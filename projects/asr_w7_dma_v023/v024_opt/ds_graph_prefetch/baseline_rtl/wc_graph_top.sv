`timescale 1ns/1ps
// WCPG v2 integration top: controller + PL fetch DMA + real DDR vector/layout
// engines + external matrix handshake.  SEQ is an exposed handshake so a
// control-only stub or the sealed V022 executor can be attached by the
// integrator; this top does not hide a second arithmetic copy.
module wc_graph_top_v023 #(
 parameter [31:0] PARAM_BASE=32'h10000000,
 parameter [31:0] PARAM_LIMIT=32'h40000000,
 parameter [31:0] ARENA_BASE=32'h03000000,
 parameter [31:0] ARENA_LIMIT=32'h08000000,
 parameter [31:0] EXTERNAL_BASE=32'h08000000,
 parameter [31:0] EXTERNAL_LIMIT=32'h10000000,
 parameter integer MAX_NODES=1024,
 parameter integer SEQ_WATCHDOG=200000,
 parameter integer FETCH_WATCHDOG=200000,
 parameter integer VEC_WATCHDOG=200000,
 parameter integer LAY_WATCHDOG=200000,
 parameter integer MAX_PREFETCH=16,
 parameter [63:0] DRAIN_WATCHDOG=64'd200000000
)(
 input wire clk,rst_n,
 input wire start,
 input wire [31:0] plan_base,
 input wire [31:0] param_end,
 input wire parameter_ready,
 input wire [31:0] generation,
 output wire busy,done,fault,irq,drain_timeout,
 output wire isolation_req,requires_reset,
 output wire seq_dispatch_timeout,seq_inflight_timeout,fetch_timeout,
 output wire [31:0] seq_wait_cycles,seq_run_cycles,
 output wire [7:0] error_code,
 output wire [31:0] completed,node_count,rejected_starts,last_node,
 output wire [MAX_NODES-1:0] done_mask,
 output wire [63:0] cycles,fetch_cycles,operator_cycles,drain_cycles,
 output wire output_retained,
 output wire [31:0] output_count,last_output_tid,last_output_base,last_output_bytes,
 output wire seq_busy,seq_active,vector_busy,layout_busy,
 output wire vec_done_pulse,lay_done_pulse,mat_done_pulse,
 input wire [7:0] matrix_error,
 output wire [7:0] vector_numeric_flags,vector_error_code,layout_error_code,
 output wire [63:0] vector_cycles_o,layout_cycles_o,vector_ro_o,vector_wo_o,
 output wire [63:0] vector_total_cycles_o,layout_total_cycles_o,
 output wire [31:0] vector_op_count_o,layout_op_count_o,
 output wire vector_isolation,layout_isolation,
 output wire [31:0] vector_read_bytes_o,vector_write_bytes_o,
 output wire [31:0] layout_read_bytes_o,layout_write_bytes_o,
 output wire [31:0] vector_elements_o,layout_elements_o,
 output wire [31:0] layout_hits_o,layout_misses_o,
 // sequential-program engine handshake (stub or sealed V022 executor)
 output wire seq_valid,input wire seq_ready,
 output wire [31:0] seq_base,seq_count,
 input wire seq_done,seq_fault,input wire [7:0] seq_error,
 // external matrix queue engine
 output wire matrix_valid,input wire matrix_ready,
 output wire [31:0] matrix_queue_base,matrix_queue_count,
 input wire matrix_done,matrix_fault,
 // fetch AXI master
 output wire [39:0] sf_araddr,output wire [7:0] sf_arlen,output wire [2:0] sf_arsize,
 output wire [1:0] sf_arburst,output wire [3:0] sf_arcache,output wire [2:0] sf_arprot,
 output wire sf_arvalid,input wire sf_arready,
 input wire [127:0] sf_rdata,input wire [1:0] sf_rresp,input wire sf_rlast,
 input wire sf_rvalid,output wire sf_rready,
 output wire [39:0] sf_awaddr,output wire [7:0] sf_awlen,output wire [2:0] sf_awsize,
 output wire [1:0] sf_awburst,output wire [3:0] sf_awcache,output wire [2:0] sf_awprot,
 output wire sf_awvalid,input wire sf_awready,
 output wire [127:0] sf_wdata,output wire [15:0] sf_wstrb,output wire sf_wlast,
 output wire sf_wvalid,input wire sf_wready,
 input wire [1:0] sf_bresp,input wire sf_bvalid,output wire sf_bready,
 // vector AXI masters
 output wire [39:0] vr_araddr,output wire [7:0] vr_arlen,output wire [2:0] vr_arsize,
 output wire [1:0] vr_arburst,output wire [3:0] vr_arcache,output wire [2:0] vr_arprot,
 output wire vr_arvalid,input wire vr_arready,
 input wire [127:0] vr_rdata,input wire [1:0] vr_rresp,input wire vr_rlast,
 input wire vr_rvalid,output wire vr_rready,
 output wire [39:0] vw_awaddr,output wire [7:0] vw_awlen,output wire [2:0] vw_awsize,
 output wire [1:0] vw_awburst,output wire [3:0] vw_awcache,output wire [2:0] vw_awprot,
 output wire vw_awvalid,input wire vw_awready,
 output wire [127:0] vw_wdata,output wire [15:0] vw_wstrb,output wire vw_wlast,
 output wire vw_wvalid,input wire vw_wready,
 input wire [1:0] vw_bresp,input wire vw_bvalid,output wire vw_bready,
 // layout AXI masters
 output wire [39:0] lr_araddr,output wire [7:0] lr_arlen,output wire [2:0] lr_arsize,
 output wire [1:0] lr_arburst,output wire [3:0] lr_arcache,output wire [2:0] lr_arprot,
 output wire lr_arvalid,input wire lr_arready,
 input wire [127:0] lr_rdata,input wire [1:0] lr_rresp,input wire lr_rlast,
 input wire lr_rvalid,output wire lr_rready,
 output wire [39:0] lw_awaddr,output wire [7:0] lw_awlen,output wire [2:0] lw_awsize,
 output wire [1:0] lw_awburst,output wire [3:0] lw_awcache,output wire [2:0] lw_awprot,
 output wire lw_awvalid,input wire lw_awready,
 output wire [127:0] lw_wdata,output wire [15:0] lw_wstrb,output wire lw_wlast,
 output wire lw_wvalid,input wire lw_wready,
 input wire [1:0] lw_bresp,input wire lw_bvalid,output wire lw_bready
);
 wire ctrl_seq_valid,ctrl_seq_done,ctrl_seq_fault;
 wire [31:0] ctrl_seq_base,ctrl_seq_count;
 wire [7:0] ctrl_seq_error;
 wire ctrl_mat_valid,ctrl_mat_done,ctrl_mat_fault;
 wire [31:0] ctrl_mat_base,ctrl_mat_count;
 wire [7:0] ctrl_mat_error;
 wire ctrl_vec_valid,ctrl_vec_done,ctrl_vec_fault;
 wire [511:0] ctrl_vec_descriptor;
 wire [7:0] ctrl_vec_error;
 wire ctrl_lay_valid,ctrl_lay_done,ctrl_lay_fault;
 wire [1023:0] ctrl_lay_descriptor;
 wire [7:0] ctrl_lay_error;
 wire ctrl_direct_idle;
 wire seq_active_i;
 wire sf_req_valid,sf_req_ready,sf_read_valid,sf_read_ready,sf_done,sf_err;
 wire [31:0] sf_address;wire [7:0] sf_beats,sf_ridx;wire [15:0] sf_beats16,sf_ridx16;
 wire [127:0] sf_rdata_i;
 assign sf_beats16={8'd0,sf_beats};assign sf_ridx=sf_ridx16[7:0];
 wire vec_ready,vec_done,vec_fault,lay_ready,lay_done,lay_fault;
 wire [7:0] vec_error,lay_error;
 wire [63:0] vec_cycles,lay_cycles,vec_ro,vec_wo;
 wire [31:0] vec_rb,vec_wb,lay_rb,lay_wb,vec_elems,lay_elems,lay_hits,lay_misses;
 wire [7:0] vec_flags;
 wire [511:0] vec_descriptor;
 wire [1023:0] lay_descriptor;
 wire vec_iso,vec_rst,lay_iso,lay_rst;
 wire [63:0] vec_total_cycles,lay_total_cycles;
 wire [31:0] vec_ops,lay_ops;
 assign vector_total_cycles_o=vec_total_cycles;
 assign layout_total_cycles_o=lay_total_cycles;
 assign vector_op_count_o=vec_ops;
 assign layout_op_count_o=lay_ops;
 assign vector_isolation=vec_iso;
 assign layout_isolation=lay_iso;

 assign seq_valid=ctrl_seq_valid;assign seq_base=ctrl_seq_base;
 assign seq_count=ctrl_seq_count;
 assign ctrl_seq_done=seq_done;assign ctrl_seq_fault=seq_fault;
 assign ctrl_seq_error=seq_error;
 assign matrix_valid=ctrl_mat_valid;assign matrix_queue_base=ctrl_mat_base;
 assign matrix_queue_count=ctrl_mat_count;
 assign ctrl_mat_done=matrix_done;assign ctrl_mat_fault=matrix_fault;
 assign ctrl_mat_error=matrix_error;
 assign vec_descriptor=ctrl_vec_descriptor;assign lay_descriptor=ctrl_lay_descriptor;
 assign ctrl_vec_done=vec_done;assign ctrl_vec_fault=vec_fault;assign ctrl_vec_error=vec_error;
 assign ctrl_lay_done=lay_done;assign ctrl_lay_fault=lay_fault;assign ctrl_lay_error=lay_error;

 wc_graph_ctrl #(.PARAM_BASE(PARAM_BASE),.PARAM_LIMIT(PARAM_LIMIT),
  .ARENA_BASE(ARENA_BASE),.ARENA_LIMIT(ARENA_LIMIT),
  .EXTERNAL_BASE(EXTERNAL_BASE),.EXTERNAL_LIMIT(EXTERNAL_LIMIT),
  .MAX_NODES(MAX_NODES),.SEQ_WATCHDOG(SEQ_WATCHDOG),
  .FETCH_WATCHDOG(FETCH_WATCHDOG),.DRAIN_WATCHDOG(DRAIN_WATCHDOG)) ctrl(
  .clk(clk),.rst_n(rst_n),.start(start),.plan_base(plan_base),.param_end(param_end),
  .parameter_ready(parameter_ready),.generation(generation),
  .busy(busy),.done(done),.fault(fault),.error_code(error_code),.completed(completed),
  .node_count(node_count),.rejected_starts(rejected_starts),.last_node(last_node),
  .done_mask(done_mask),.cycles(cycles),.fetch_cycles(fetch_cycles),
  .operator_cycles(operator_cycles),.drain_cycles(drain_cycles),.drain_timeout(drain_timeout),
  .isolation_req(isolation_req),.requires_reset(requires_reset),
  .seq_dispatch_timeout(seq_dispatch_timeout),.seq_inflight_timeout(seq_inflight_timeout),
  .fetch_timeout(fetch_timeout),.seq_wait_cycles(seq_wait_cycles),.seq_run_cycles(seq_run_cycles),
  .irq(irq),.output_retained(output_retained),.output_count(output_count),
  .last_output_tid(last_output_tid),.last_output_base(last_output_base),
  .last_output_bytes(last_output_bytes),
  .fetch_req_valid(sf_req_valid),.fetch_req_ready(sf_req_ready),.fetch_address(sf_address),
  .fetch_beats(sf_beats),.fetch_read_valid(sf_read_valid),.fetch_read_ready(sf_read_ready),
  .fetch_read_data(sf_rdata_i),.fetch_read_index(sf_ridx),.fetch_done(sf_done),
  .fetch_error(sf_err),
  .seq_valid(ctrl_seq_valid),.seq_ready(seq_ready),.seq_base(ctrl_seq_base),
  .seq_count(ctrl_seq_count),.seq_done(ctrl_seq_done),.seq_fault(ctrl_seq_fault),
  .seq_error(ctrl_seq_error),
  .mat_valid(ctrl_mat_valid),.mat_ready(matrix_ready&&!seq_active_i),.mat_base(ctrl_mat_base),
  .mat_count(ctrl_mat_count),.mat_done(ctrl_mat_done),.mat_fault(ctrl_mat_fault),
  .mat_error(ctrl_mat_error),
  .vec_valid(ctrl_vec_valid),.vec_ready(vec_ready&&!seq_active_i),.vec_descriptor(ctrl_vec_descriptor),
  .vec_done(ctrl_vec_done),.vec_fault(ctrl_vec_fault),.vec_error(ctrl_vec_error),
  .lay_valid(ctrl_lay_valid),.lay_ready(lay_ready&&!seq_active_i),.lay_descriptor(ctrl_lay_descriptor),
  .lay_done(ctrl_lay_done),.lay_fault(ctrl_lay_fault),.lay_error(ctrl_lay_error),
  .direct_idle(ctrl_direct_idle),.seq_active(seq_active_i));
 assign seq_active=seq_active_i;

 axi_dma_v019 sf_dma(.clk(clk),.rst_n(rst_n),.request_valid(sf_req_valid),
  .request_ready(sf_req_ready),.request_write(1'b0),.request_address(sf_address),
  .request_beats(sf_beats16),.read_valid(sf_read_valid),.read_ready(sf_read_ready),
  .read_data(sf_rdata_i),.read_index(sf_ridx16),.write_valid(1'b0),.write_ready(),
  .write_data(128'd0),.write_strobe(16'd0),.write_index(),.done(sf_done),.error(sf_err),
  .read_bytes(),.write_bytes(),.read_bursts(),.write_bursts(),
  .m_axi_araddr(sf_araddr),.m_axi_arlen(sf_arlen),.m_axi_arsize(sf_arsize),
  .m_axi_arburst(sf_arburst),.m_axi_arcache(sf_arcache),.m_axi_arprot(sf_arprot),
  .m_axi_arvalid(sf_arvalid),.m_axi_arready(sf_arready),.m_axi_rdata(sf_rdata),
  .m_axi_rresp(sf_rresp),.m_axi_rlast(sf_rlast),.m_axi_rvalid(sf_rvalid),.m_axi_rready(sf_rready),
  .m_axi_awaddr(sf_awaddr),.m_axi_awlen(sf_awlen),.m_axi_awsize(sf_awsize),
  .m_axi_awburst(sf_awburst),.m_axi_awcache(sf_awcache),.m_axi_awprot(sf_awprot),
  .m_axi_awvalid(sf_awvalid),.m_axi_awready(sf_awready),.m_axi_wdata(sf_wdata),
  .m_axi_wstrb(sf_wstrb),.m_axi_wlast(sf_wlast),.m_axi_wvalid(sf_wvalid),.m_axi_wready(sf_wready),
  .m_axi_bresp(sf_bresp),.m_axi_bvalid(sf_bvalid),.m_axi_bready(sf_bready));

 v023_vector_guard #(.WATCHDOG(VEC_WATCHDOG)) vec(.clk(clk),.rst_n(rst_n),.start(ctrl_vec_valid&&vec_ready&&!seq_active_i),
  .descriptor(vec_descriptor),.param_end(param_end),.ready(vec_ready),
  .busy(vector_busy),.done(vec_done),.fault(vec_fault),.error_code(vec_error),
  .numeric_flags(vec_flags),.completed_elements(vec_elems),.rejected_starts(),
  .cycles(vec_cycles),.read_compute_overlap(vec_ro),.write_compute_overlap(vec_wo),
  .read_bytes(vec_rb),.write_bytes(vec_wb),.read_bursts(),.write_bursts(),
  .isolation_req(vec_iso),.requires_reset(vec_rst),.total_cycles(vec_total_cycles),
  .total_busy_cycles(),.op_count(vec_ops),
  .read_m_axi_araddr(vr_araddr),.read_m_axi_arlen(vr_arlen),.read_m_axi_arsize(vr_arsize),
  .read_m_axi_arburst(vr_arburst),.read_m_axi_arcache(vr_arcache),.read_m_axi_arprot(vr_arprot),
  .read_m_axi_arvalid(vr_arvalid),.read_m_axi_arready(vr_arready),.read_m_axi_rdata(vr_rdata),
  .read_m_axi_rresp(vr_rresp),.read_m_axi_rlast(vr_rlast),.read_m_axi_rvalid(vr_rvalid),
  .read_m_axi_rready(vr_rready),
  .read_m_axi_awaddr(),.read_m_axi_awlen(),.read_m_axi_awsize(),.read_m_axi_awburst(),
  .read_m_axi_awcache(),.read_m_axi_awprot(),.read_m_axi_awvalid(),.read_m_axi_awready(1'b1),
  .read_m_axi_wdata(),.read_m_axi_wstrb(),.read_m_axi_wlast(),.read_m_axi_wvalid(),
  .read_m_axi_wready(1'b1),.read_m_axi_bresp(2'd0),.read_m_axi_bvalid(1'b0),.read_m_axi_bready(),
  .write_m_axi_araddr(),.write_m_axi_arlen(),.write_m_axi_arsize(),.write_m_axi_arburst(),
  .write_m_axi_arcache(),.write_m_axi_arprot(),.write_m_axi_arvalid(),.write_m_axi_arready(1'b1),
  .write_m_axi_rdata(128'd0),.write_m_axi_rresp(2'd0),.write_m_axi_rlast(1'b0),
  .write_m_axi_rvalid(1'b0),.write_m_axi_rready(),
  .write_m_axi_awaddr(vw_awaddr),.write_m_axi_awlen(vw_awlen),.write_m_axi_awsize(vw_awsize),
  .write_m_axi_awburst(vw_awburst),.write_m_axi_awcache(vw_awcache),.write_m_axi_awprot(vw_awprot),
  .write_m_axi_awvalid(vw_awvalid),.write_m_axi_awready(vw_awready),.write_m_axi_wdata(vw_wdata),
  .write_m_axi_wstrb(vw_wstrb),.write_m_axi_wlast(vw_wlast),.write_m_axi_wvalid(vw_wvalid),
  .write_m_axi_wready(vw_wready),.write_m_axi_bresp(vw_bresp),.write_m_axi_bvalid(vw_bvalid),
  .write_m_axi_bready(vw_bready));

 v023_layout_guard #(.WATCHDOG(LAY_WATCHDOG),.MAX_PREFETCH(MAX_PREFETCH)) lay(.clk(clk),.rst_n(rst_n),.start(ctrl_lay_valid&&lay_ready&&!seq_active_i),
  .descriptor(lay_descriptor),.param_end(param_end),.ready(lay_ready),
  .busy(layout_busy),.done(lay_done),.fault(lay_fault),.error_code(lay_error),
  .processed_elements(lay_elems),.rejected_starts(),.cache_hits(lay_hits),
  .cache_misses(lay_misses),.cycles(lay_cycles),.read_bytes(lay_rb),.write_bytes(lay_wb),
  .read_bursts(),.write_bursts(),
  .isolation_req(lay_iso),.requires_reset(lay_rst),.total_cycles(lay_total_cycles),
  .total_busy_cycles(),.op_count(lay_ops),
  .read_m_axi_araddr(lr_araddr),.read_m_axi_arlen(lr_arlen),.read_m_axi_arsize(lr_arsize),
  .read_m_axi_arburst(lr_arburst),.read_m_axi_arcache(lr_arcache),.read_m_axi_arprot(lr_arprot),
  .read_m_axi_arvalid(lr_arvalid),.read_m_axi_arready(lr_arready),.read_m_axi_rdata(lr_rdata),
  .read_m_axi_rresp(lr_rresp),.read_m_axi_rlast(lr_rlast),.read_m_axi_rvalid(lr_rvalid),
  .read_m_axi_rready(lr_rready),
  .read_m_axi_awaddr(),.read_m_axi_awlen(),.read_m_axi_awsize(),.read_m_axi_awburst(),
  .read_m_axi_awcache(),.read_m_axi_awprot(),.read_m_axi_awvalid(),.read_m_axi_awready(1'b1),
  .read_m_axi_wdata(),.read_m_axi_wstrb(),.read_m_axi_wlast(),.read_m_axi_wvalid(),
  .read_m_axi_wready(1'b1),.read_m_axi_bresp(2'd0),.read_m_axi_bvalid(1'b0),.read_m_axi_bready(),
  .write_m_axi_araddr(),.write_m_axi_arlen(),.write_m_axi_arsize(),.write_m_axi_arburst(),
  .write_m_axi_arcache(),.write_m_axi_arprot(),.write_m_axi_arvalid(),.write_m_axi_arready(1'b1),
  .write_m_axi_rdata(128'd0),.write_m_axi_rresp(2'd0),.write_m_axi_rlast(1'b0),
  .write_m_axi_rvalid(1'b0),.write_m_axi_rready(),
  .write_m_axi_awaddr(lw_awaddr),.write_m_axi_awlen(lw_awlen),.write_m_axi_awsize(lw_awsize),
  .write_m_axi_awburst(lw_awburst),.write_m_axi_awcache(lw_awcache),.write_m_axi_awprot(lw_awprot),
  .write_m_axi_awvalid(lw_awvalid),.write_m_axi_awready(lw_awready),.write_m_axi_wdata(lw_wdata),
  .write_m_axi_wstrb(lw_wstrb),.write_m_axi_wlast(lw_wlast),.write_m_axi_wvalid(lw_wvalid),
  .write_m_axi_wready(lw_wready),.write_m_axi_bresp(lw_bresp),.write_m_axi_bvalid(lw_bvalid),
  .write_m_axi_bready(lw_bready));

 assign seq_busy=seq_active;
 assign vec_done_pulse=vec_done;
 assign lay_done_pulse=lay_done;
 assign mat_done_pulse=ctrl_mat_done;
 assign vector_numeric_flags=vec_flags;
 assign vector_error_code=vec_error;
 assign layout_error_code=lay_error;
 assign vector_cycles_o=vec_cycles;
 assign layout_cycles_o=lay_cycles;
 assign vector_ro_o=vec_ro;
 assign vector_wo_o=vec_wo;
 assign vector_read_bytes_o=vec_rb;
 assign vector_write_bytes_o=vec_wb;
 assign layout_read_bytes_o=lay_rb;
 assign layout_write_bytes_o=lay_wb;
 assign vector_elements_o=vec_elems;
 assign layout_elements_o=lay_elems;
 assign layout_hits_o=lay_hits;
 assign layout_misses_o=lay_misses;
endmodule
