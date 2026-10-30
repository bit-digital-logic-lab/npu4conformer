`timescale 1ns/1ps
// W023 integration candidate: one whole-plan scheduler above the sealed V022
// linear-program executor, sharing the real DDR vector/layout engines.
//
// Ownership rule (resource-honest, no synthesis/STA claim):
//   * SEQ node  -> seq planner owns vector/layout/matrix while seq_owner=1.
//   * direct MAT/VEC/LAY nodes -> ctrl owns them; direct engines may overlap.
//   * a SEQ node only starts when no direct engine is active, and direct nodes
//     are held off while seq_owner=1.  One arithmetic copy of each engine.
//
// The matrix engine is an external board port (the existing accelerator).
// Vector/layout are the sealed real engines.  No numeric stub is instantiated.
module wc_plan_top_v023 #(
 parameter [31:0] PARAM_BASE=32'h10000000,
 parameter [31:0] PARAM_LIMIT=32'h40000000,
 parameter [31:0] ARENA_BASE=32'h03000000,
 parameter [31:0] ARENA_LIMIT=32'h08000000,
 parameter integer MAX_NODES=128
)(
 input wire clk,rst_n,
 input wire start,
 input wire [31:0] plan_base,
 input wire [31:0] param_end,
 input wire parameter_ready,
 input wire [31:0] generation,
 output wire busy,
 output wire done,
 output wire fault,
 output wire [7:0] error_code,
 output wire [31:0] completed,
 output wire [31:0] node_count,
 output wire [31:0] rejected_starts,
 output wire [31:0] last_node,
 output wire [127:0] done_mask,
 output wire [63:0] cycles,
 output wire [63:0] fetch_cycles,
 output wire [63:0] operator_cycles,
 output wire [63:0] drain_cycles,
 output wire drain_timeout,
 output wire irq,
 output wire seq_busy,
 output wire vector_busy,
 output wire layout_busy,
 // superplan fetch AXI master
 output wire [39:0] sf_araddr,output wire [7:0] sf_arlen,output wire [2:0] sf_arsize,
 output wire [1:0] sf_arburst,output wire [3:0] sf_arcache,output wire [2:0] sf_arprot,
 output wire sf_arvalid,input wire sf_arready,
 input wire [127:0] sf_rdata,input wire [1:0] sf_rresp,input wire sf_rlast,input wire sf_rvalid,output wire sf_rready,
 output wire [39:0] sf_awaddr,output wire [7:0] sf_awlen,output wire [2:0] sf_awsize,
 output wire [1:0] sf_awburst,output wire [3:0] sf_awcache,output wire [2:0] sf_awprot,
 output wire sf_awvalid,input wire sf_awready,
 output wire [127:0] sf_wdata,output wire [15:0] sf_wstrb,output wire sf_wlast,output wire sf_wvalid,input wire sf_wready,
 input wire [1:0] sf_bresp,input wire sf_bvalid,output wire sf_bready,
 // sequential-program fetch AXI master
 output wire [39:0] qf_araddr,output wire [7:0] qf_arlen,output wire [2:0] qf_arsize,
 output wire [1:0] qf_arburst,output wire [3:0] qf_arcache,output wire [2:0] qf_arprot,
 output wire qf_arvalid,input wire qf_arready,
 input wire [127:0] qf_rdata,input wire [1:0] qf_rresp,input wire qf_rlast,input wire qf_rvalid,output wire qf_rready,
 output wire [39:0] qf_awaddr,output wire [7:0] qf_awlen,output wire [2:0] qf_awsize,
 output wire [1:0] qf_awburst,output wire [3:0] qf_awcache,output wire [2:0] qf_awprot,
 output wire qf_awvalid,input wire qf_awready,
 output wire [127:0] qf_wdata,output wire [15:0] qf_wstrb,output wire qf_wlast,output wire qf_wvalid,input wire qf_wready,
 input wire [1:0] qf_bresp,input wire qf_bvalid,output wire qf_bready,
 // vector engine AXI masters
 output wire [39:0] vr_araddr,output wire [7:0] vr_arlen,output wire [2:0] vr_arsize,
 output wire [1:0] vr_arburst,output wire [3:0] vr_arcache,output wire [2:0] vr_arprot,
 output wire vr_arvalid,input wire vr_arready,
 input wire [127:0] vr_rdata,input wire [1:0] vr_rresp,input wire vr_rlast,input wire vr_rvalid,output wire vr_rready,
 output wire [39:0] vw_awaddr,output wire [7:0] vw_awlen,output wire [2:0] vw_awsize,
 output wire [1:0] vw_awburst,output wire [3:0] vw_awcache,output wire [2:0] vw_awprot,
 output wire vw_awvalid,input wire vw_awready,
 output wire [127:0] vw_wdata,output wire [15:0] vw_wstrb,output wire vw_wlast,output wire vw_wvalid,input wire vw_wready,
 input wire [1:0] vw_bresp,input wire vw_bvalid,output wire vw_bready,
 // layout engine AXI masters
 output wire [39:0] lr_araddr,output wire [7:0] lr_arlen,output wire [2:0] lr_arsize,
 output wire [1:0] lr_arburst,output wire [3:0] lr_arcache,output wire [2:0] lr_arprot,
 output wire lr_arvalid,input wire lr_arready,
 input wire [127:0] lr_rdata,input wire [1:0] lr_rresp,input wire lr_rlast,input wire lr_rvalid,output wire lr_rready,
 output wire [39:0] lw_awaddr,output wire [7:0] lw_awlen,output wire [2:0] lw_awsize,
 output wire [1:0] lw_awburst,output wire [3:0] lw_awcache,output wire [2:0] lw_awprot,
 output wire lw_awvalid,input wire lw_awready,
 output wire [127:0] lw_wdata,output wire [15:0] lw_wstrb,output wire lw_wlast,output wire lw_wvalid,input wire lw_wready,
 input wire [1:0] lw_bresp,input wire lw_bvalid,output wire lw_bready,
 // external matrix queue engine
 output wire matrix_valid,input wire matrix_ready,
 output wire [31:0] matrix_queue_base,matrix_queue_count,
 input wire matrix_done,matrix_fault
);
 wire ctrl_seq_valid,ctrl_seq_ready,ctrl_seq_done,ctrl_seq_fault;
 wire [31:0] ctrl_seq_base,ctrl_seq_count;
 wire ctrl_mat_valid,ctrl_mat_ready,ctrl_mat_done,ctrl_mat_fault;
 wire [31:0] ctrl_mat_base,ctrl_mat_count;
 wire ctrl_vec_valid,ctrl_vec_ready,ctrl_vec_done,ctrl_vec_fault;
 wire [511:0] ctrl_vec_descriptor;
 wire ctrl_lay_valid,ctrl_lay_ready,ctrl_lay_done,ctrl_lay_fault;
 wire [1023:0] ctrl_lay_descriptor;
 wire [7:0] ctrl_seq_error,ctrl_mat_error,ctrl_vec_error,ctrl_lay_error;
 wire ctrl_direct_idle;
 wire seq_vec_valid,seq_vec_ready,seq_vec_done,seq_vec_fault;
 wire [511:0] seq_vec_descriptor;
 wire seq_lay_valid,seq_lay_ready,seq_lay_done,seq_lay_fault;
 wire [1023:0] seq_lay_descriptor;
 wire seq_mat_valid,seq_mat_ready,seq_mat_done,seq_mat_fault;
 wire [31:0] seq_mat_base,seq_mat_count;
 wire [7:0] seq_vec_error,seq_lay_error,seq_mat_error;
 wire sf_req_valid,sf_req_ready,sf_read_valid,sf_read_ready,sf_done,sf_err;
 wire [31:0] sf_address;wire [15:0] sf_beats,sf_ridx;wire [127:0] sf_rdata_i;
 wire qf_req_valid,qf_req_ready,qf_read_valid,qf_read_ready,qf_done,qf_err;
 wire [31:0] qf_address;wire [15:0] qf_beats,qf_ridx;wire [127:0] qf_rdata_i;
 wire vec_ready,vec_done,vec_fault,lay_ready,lay_done,lay_fault;
 wire [7:0] vec_error,lay_error;
 wire [63:0] vec_cycles,lay_cycles,vec_ro,vec_wo;
 wire [31:0] vec_rb,vec_wb,lay_rb,lay_wb,vec_elems,lay_elems,lay_hits,lay_misses;
 wire [7:0] vec_flags;
 wire use_seq;
 wire vec_start,lay_start;
 wire [511:0] vec_descriptor;
 wire [1023:0] lay_descriptor;
 reg seq_owner;

 assign use_seq=seq_owner;
 assign vec_start=use_seq?(seq_vec_valid&&vec_ready):(ctrl_vec_valid&&vec_ready);
 assign lay_start=use_seq?(seq_lay_valid&&lay_ready):(ctrl_lay_valid&&lay_ready);
 assign vec_descriptor=use_seq?seq_vec_descriptor:ctrl_vec_descriptor;
 assign lay_descriptor=use_seq?seq_lay_descriptor:ctrl_lay_descriptor;
 assign ctrl_vec_ready=vec_ready&&!use_seq;assign ctrl_lay_ready=lay_ready&&!use_seq;
 assign seq_vec_ready=vec_ready;assign seq_lay_ready=lay_ready;
 assign ctrl_vec_done=vec_done&&!use_seq;assign seq_vec_done=vec_done&&use_seq;
 assign ctrl_lay_done=lay_done&&!use_seq;assign seq_lay_done=lay_done&&use_seq;
 assign ctrl_vec_fault=vec_fault&&!use_seq;assign seq_vec_fault=vec_fault&&use_seq;
 assign ctrl_lay_fault=lay_fault&&!use_seq;assign seq_lay_fault=lay_fault&&use_seq;
 assign ctrl_seq_ready=!seq_busy&&!seq_owner&&ctrl_direct_idle;
 assign ctrl_mat_ready=matrix_ready&&!use_seq;assign seq_mat_ready=matrix_ready;
 assign ctrl_mat_done=matrix_done&&!use_seq;assign seq_mat_done=matrix_done&&use_seq;
 assign ctrl_mat_fault=matrix_fault&&!use_seq;assign seq_mat_fault=matrix_fault&&use_seq;
 assign matrix_valid=use_seq?seq_mat_valid:ctrl_mat_valid;
 assign matrix_queue_base=use_seq?seq_mat_base:ctrl_mat_base;
 assign matrix_queue_count=use_seq?seq_mat_count:ctrl_mat_count;

 wc_superplan_ctrl ctrl(
  .clk(clk),.rst_n(rst_n),.start(start),.plan_base(plan_base),.param_end(param_end),
  .parameter_ready(parameter_ready),.generation(generation),
  .busy(busy),.done(done),.fault(fault),.error_code(error_code),.completed(completed),
  .node_count(node_count),.rejected_starts(rejected_starts),.last_node(last_node),
  .done_mask(done_mask),.cycles(cycles),.fetch_cycles(fetch_cycles),
  .operator_cycles(operator_cycles),.drain_cycles(drain_cycles),.drain_timeout(drain_timeout),
  .irq(irq),
  .fetch_req_valid(sf_req_valid),.fetch_req_ready(sf_req_ready),.fetch_address(sf_address),
  .fetch_beats(sf_beats),.fetch_read_valid(sf_read_valid),.fetch_read_ready(sf_read_ready),
  .fetch_read_data(sf_rdata_i),.fetch_read_index(sf_ridx),.fetch_done(sf_done),.fetch_error(sf_err),
  .seq_valid(ctrl_seq_valid),.seq_ready(ctrl_seq_ready),.seq_base(ctrl_seq_base),
  .seq_count(ctrl_seq_count),.seq_done(ctrl_seq_done),.seq_fault(ctrl_seq_fault),
  .seq_error(ctrl_seq_error),
  .mat_valid(ctrl_mat_valid),.mat_ready(ctrl_mat_ready),.mat_base(ctrl_mat_base),
  .mat_count(ctrl_mat_count),.mat_done(ctrl_mat_done),.mat_fault(ctrl_mat_fault),
  .mat_error(ctrl_mat_error),
  .vec_valid(ctrl_vec_valid),.vec_ready(ctrl_vec_ready),.vec_descriptor(ctrl_vec_descriptor),
  .vec_done(ctrl_vec_done),.vec_fault(ctrl_vec_fault),.vec_error(ctrl_vec_error),
  .lay_valid(ctrl_lay_valid),.lay_ready(ctrl_lay_ready),.lay_descriptor(ctrl_lay_descriptor),
  .lay_done(ctrl_lay_done),.lay_fault(ctrl_lay_fault),.lay_error(ctrl_lay_error),
  .direct_idle(ctrl_direct_idle));

 axi_dma_v019 sf_dma(.clk(clk),.rst_n(rst_n),.request_valid(sf_req_valid),
  .request_ready(sf_req_ready),.request_write(1'b0),.request_address(sf_address),
  .request_beats(sf_beats),.read_valid(sf_read_valid),.read_ready(sf_read_ready),
  .read_data(sf_rdata_i),.read_index(sf_ridx),.write_valid(1'b0),.write_ready(),
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

 pl_execution_plan_v022 seqpl(
  .clk(clk),.rst_n(rst_n),.start(ctrl_seq_valid&&ctrl_seq_ready),
  .plan_base(ctrl_seq_base),.plan_count(ctrl_seq_count),.param_end(param_end),
  .parameter_ready(parameter_ready),.generation(generation),
  .busy(seq_busy),.done(ctrl_seq_done),.fault(ctrl_seq_fault),.error_code(ctrl_seq_error),
  .completed(),.index(),.rejected_starts(),.last_ticket(),
  .cycles(),.fetch_cycles(),.operator_cycles(),.irq(),
  .dma_request_valid(qf_req_valid),.dma_request_ready(qf_req_ready),
  .dma_address(qf_address),.dma_beats(qf_beats),
  .dma_read_valid(qf_read_valid),.dma_read_ready(qf_read_ready),
  .dma_read_data(qf_rdata_i),.dma_read_index(qf_ridx),
  .dma_done(qf_done),.dma_error(qf_err),
  .matrix_valid(seq_mat_valid),.matrix_ready(seq_mat_ready),
  .matrix_queue_base(seq_mat_base),.matrix_queue_count(seq_mat_count),
  .matrix_done(seq_mat_done),.matrix_fault(seq_mat_fault),
  .vector_valid(seq_vec_valid),.vector_ready(seq_vec_ready),
  .vector_descriptor(seq_vec_descriptor),.vector_done(seq_vec_done),.vector_fault(seq_vec_fault),
  .layout_valid(seq_lay_valid),.layout_ready(seq_lay_ready),
  .layout_descriptor(seq_lay_descriptor),.layout_done(seq_lay_done),.layout_fault(seq_lay_fault));

 axi_dma_v019 qf_dma(.clk(clk),.rst_n(rst_n),.request_valid(qf_req_valid),
  .request_ready(qf_req_ready),.request_write(1'b0),.request_address(qf_address),
  .request_beats(qf_beats),.read_valid(qf_read_valid),.read_ready(qf_read_ready),
  .read_data(qf_rdata_i),.read_index(qf_ridx),.write_valid(1'b0),.write_ready(),
  .write_data(128'd0),.write_strobe(16'd0),.write_index(),.done(qf_done),.error(qf_err),
  .read_bytes(),.write_bytes(),.read_bursts(),.write_bursts(),
  .m_axi_araddr(qf_araddr),.m_axi_arlen(qf_arlen),.m_axi_arsize(qf_arsize),
  .m_axi_arburst(qf_arburst),.m_axi_arcache(qf_arcache),.m_axi_arprot(qf_arprot),
  .m_axi_arvalid(qf_arvalid),.m_axi_arready(qf_arready),.m_axi_rdata(qf_rdata),
  .m_axi_rresp(qf_rresp),.m_axi_rlast(qf_rlast),.m_axi_rvalid(qf_rvalid),.m_axi_rready(qf_rready),
  .m_axi_awaddr(qf_awaddr),.m_axi_awlen(qf_awlen),.m_axi_awsize(qf_awsize),
  .m_axi_awburst(qf_awburst),.m_axi_awcache(qf_awcache),.m_axi_awprot(qf_awprot),
  .m_axi_awvalid(qf_awvalid),.m_axi_awready(qf_awready),.m_axi_wdata(qf_wdata),
  .m_axi_wstrb(qf_wstrb),.m_axi_wlast(qf_wlast),.m_axi_wvalid(qf_wvalid),.m_axi_wready(qf_wready),
  .m_axi_bresp(qf_bresp),.m_axi_bvalid(qf_bvalid),.m_axi_bready(qf_bready));

 ddr_vector_axi vec(.clk(clk),.rst_n(rst_n),.start(vec_start),.descriptor(vec_descriptor),
  .param_end(param_end),.ready(vec_ready),.busy(vector_busy),.done(vec_done),.fault(vec_fault),
  .error_code(vec_error),.numeric_flags(vec_flags),.completed_elements(vec_elems),
  .rejected_starts(),.cycles(vec_cycles),.read_compute_overlap(vec_ro),.write_compute_overlap(vec_wo),
  .read_bytes(vec_rb),.write_bytes(vec_wb),.read_bursts(),.write_bursts(),
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

 ddr_layout_axi lay(.clk(clk),.rst_n(rst_n),.start(lay_start),.descriptor(lay_descriptor),
  .param_end(param_end),.ready(lay_ready),.busy(layout_busy),.done(lay_done),.fault(lay_fault),
  .error_code(lay_error),.processed_elements(lay_elems),.rejected_starts(),.cache_hits(lay_hits),
  .cache_misses(lay_misses),.cycles(lay_cycles),.read_bytes(lay_rb),.write_bytes(lay_wb),
  .read_bursts(),.write_bursts(),
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

 always @(posedge clk)begin
  if(!rst_n)seq_owner<=0;
  else if(ctrl_seq_valid&&ctrl_seq_ready)seq_owner<=1;
  else if(ctrl_seq_done)seq_owner<=0;
 end
endmodule
