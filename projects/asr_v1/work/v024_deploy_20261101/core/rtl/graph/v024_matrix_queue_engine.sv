`timescale 1ns/1ps
// V0.23 matrix queue child for the integrated superplan.
//
// The WCPG controller hands one MAT node (queue_base/queue_count).  This
// adapter fetches each 64-byte V022 queue descriptor with task_queue (the
// sealed descriptor layout, BACKEND=21), decodes the cfg_* fields used by
// queued_v020_monitored, and drives the ds_matrix P2 cluster.  It is a
// direct-config sequencer, not a re-lowered sealed payload.
//
// It also adds the terminal watchdog that the graph direct-child path lacked:
// a child that never asserts done is turned into a defined fault + isolation
// request instead of hanging the controller forever.  The cluster has no
// abort/drain port, so this is an isolation exit, not a false "drained" claim.
module v024_matrix_queue_engine #(
 parameter [31:0] ARENA_BASE = 32'h04000000,
 parameter [31:0] ARENA_END  = 32'h08000000,
 parameter integer MAX_TASKS = 64,
 parameter integer WATCHDOG  = 500000,
 parameter integer PIPE_STAGES = 4
)(
 input wire clk,
 input wire rst_n,
 input wire start,
 input wire [31:0] queue_base,
 input wire [31:0] queue_count,
 input wire [31:0] param_end,
 // V0.24 explicit fused-MAT descriptor select (never inferred from the plan
 // graph).  `fused=1` only for a MAT node that passed the controller's
 // explicit MATF/A16C validation; otherwise the legacy C48 cluster runs.
 input wire        fused,
 input wire [1:0]  fuse_fma_mode,
 input wire        fuse_relu,
 input wire        fuse_perchannel_en,
 input wire [31:0] fuse_scale,
 input wire [31:0] fuse_bias,
 input wire        pc_wr_valid,
 output wire       pc_wr_ready,
 input wire [7:0]  pc_wr_addr,
 input wire [31:0] pc_wr_data,
 output reg        fused_used,
 output wire [31:0] fuse_c48_ddr_bytes,
 output wire [31:0] fuse_a16_bytes,

 output wire busy,
 output wire done,
 output wire fault,
 output wire [7:0] error_code,
 output wire [31:0] completed_tasks,
 output wire [31:0] current_index,
 output wire [31:0] rejected_starts,
 output wire [63:0] queue_cycles,
 output wire [63:0] fetch_cycles,
 output wire [63:0] engine_wait_cycles,
 output wire [63:0] retire_wait_cycles,

 output wire [31:0] compute_cycles,
 output wire [31:0] read_blocks,
 output wire [31:0] write_blocks,
 output wire [31:0] cache_hits,
 output wire [31:0] cache_misses,
 output wire [31:0] c_collect_groups,
 output wire [31:0] c_collect_cycles,
 output wire [7:0]  pe_drain_cycles,
 output wire [7:0]  array_drain_cycles,
 output reg  isolation_req,
 output reg  watchdog_fired,
 output wire [63:0] matrix_cycles,
 // Per-task accumulation over the whole queue child.  `matrix_cycles` is the
 // last task only (kept for compatibility); software must use the totals.
 output wire [63:0] matrix_total_cycles,
 output wire [31:0] matrix_total_compute,
 output wire [31:0] matrix_total_rb,
 output wire [31:0] matrix_total_wb,
 output wire [31:0] matrix_op_count,
 output wire requires_reset,

 // queue-descriptor fetch DMA (read only)
 output wire [39:0] q_araddr,
 output wire [7:0]  q_arlen,
 output wire [2:0]  q_arsize,
 output wire [1:0]  q_arburst,
 output wire        q_arvalid,
 input  wire        q_arready,
 input  wire [127:0] q_rdata,
 input  wire [1:0]   q_rresp,
 input  wire         q_rlast,
 input  wire         q_rvalid,
 output wire         q_rready,

 // matrix read DMA
 output wire [39:0] rd_araddr,
 output wire [7:0]  rd_arlen,
 output wire [2:0]  rd_arsize,
 output wire [1:0]  rd_arburst,
 output wire        rd_arvalid,
 input  wire        rd_arready,
 input  wire [127:0] rd_rdata,
 input  wire [1:0]   rd_rresp,
 input  wire         rd_rlast,
 input  wire         rd_rvalid,
 output wire         rd_rready,

 // matrix write DMA
 output wire [39:0] wr_awaddr,
 output wire [7:0]  wr_awlen,
 output wire [2:0]  wr_awsize,
 output wire [1:0]  wr_awburst,
 output wire        wr_awvalid,
 input  wire        wr_awready,
 output wire [127:0] wr_wdata,
 output wire [15:0]  wr_wstrb,
 output wire         wr_wlast,
 output wire         wr_wvalid,
 input  wire         wr_wready,
 input  wire [1:0]   wr_bresp,
 input  wire         wr_bvalid,
 output wire         wr_bready
);
 wire qreq,qready,qrvalid,qrready,qdone,qerror;
 wire [31:0] qaddr;
 wire [15:0] qbeats,qrindex;
 wire [127:0] qrdata;

 wire ev,er;
 wire [511:0] ed;
 wire e_done,e_fault;
 wire [7:0] e_error;
 wire [63:0] e_cycles;
 wire completion_valid,completion_ready;
 wire [31:0] completion_index,completion_cookie;
 wire [7:0] completion_error;
 wire [63:0] completion_cycles;

 task_queue #(
  .BACKEND(16'd21),
  .ARENA_BASE(ARENA_BASE),
  .ARENA_END(ARENA_END),
  .MAX_TASKS(MAX_TASKS)
 ) queue (
  .clk(clk),.rst_n(rst_n),.start(start),
  .queue_base(queue_base),.queue_count(queue_count),
  .busy(busy),.done(done),.fault(fault),.error_code(error_code),
  .completed_tasks(completed_tasks),.current_index(current_index),
  .rejected_starts(rejected_starts),
  .queue_cycles(queue_cycles),.fetch_cycles(fetch_cycles),
  .engine_wait_cycles(engine_wait_cycles),.retire_wait_cycles(retire_wait_cycles),
  .dma_request_valid(qreq),.dma_request_ready(qready),.dma_address(qaddr),
  .dma_beats(qbeats),.dma_read_valid(qrvalid),.dma_read_ready(qrready),
  .dma_read_index(qrindex),.dma_read_data(qrdata),.dma_done(qdone),.dma_error(qerror),
  .engine_valid(ev),.engine_ready(er),.engine_descriptor(ed),
  .engine_done(e_done),.engine_fault(e_fault),.engine_error(e_error),
  .engine_cycles(e_cycles),
  .completion_valid(completion_valid),.completion_ready(completion_ready),
  .completion_index(completion_index),.completion_cookie(completion_cookie),
  .completion_error(completion_error),.completion_cycles(completion_cycles)
 );

 axi_dma_v019 qdma (
  .clk(clk),.rst_n(rst_n),
  .request_valid(qreq),.request_ready(qready),.request_write(1'b0),
  .request_address(qaddr),.request_beats(qbeats),
  .read_valid(qrvalid),.read_ready(qrready),.read_data(qrdata),.read_index(qrindex),
  .write_valid(1'b0),.write_ready(),.write_data(128'd0),.write_strobe(16'd0),
  .write_index(),.done(qdone),.error(qerror),
  .read_bytes(),.write_bytes(),.read_bursts(),.write_bursts(),
  .m_axi_araddr(q_araddr),.m_axi_arlen(q_arlen),.m_axi_arsize(q_arsize),
  .m_axi_arburst(q_arburst),.m_axi_arcache(),.m_axi_arprot(),
  .m_axi_arvalid(q_arvalid),.m_axi_arready(q_arready),
  .m_axi_rdata(q_rdata),.m_axi_rresp(q_rresp),.m_axi_rlast(q_rlast),
  .m_axi_rvalid(q_rvalid),.m_axi_rready(q_rready),
  .m_axi_awaddr(),.m_axi_awlen(),.m_axi_awsize(),.m_axi_awburst(),
  .m_axi_awcache(),.m_axi_awprot(),.m_axi_awvalid(),.m_axi_awready(1'b0),
  .m_axi_wdata(),.m_axi_wstrb(),.m_axi_wlast(),.m_axi_wvalid(),
  .m_axi_wready(1'b0),.m_axi_bresp(2'd0),.m_axi_bvalid(1'b0),.m_axi_bready()
 );

 // ------------------------- config decode -------------------------
 reg [511:0] cfg;
 reg [2:0] st;
 localparam S_IDLE=0,S_CHECK=1,S_START=2,S_WAIT=3,S_RUN=4,S_DONE=5,S_ISO=6;

 wire [31:0] abase = cfg[159:128];
 wire [31:0] bbase = cfg[191:160];
 wire [31:0] cbase = cfg[223:192];
 wire [31:0] mdim  = cfg[255:224];
 wire [31:0] ndim  = cfg[287:256];
 wire [31:0] kdim  = cfg[319:288];
 wire [31:0] epoch = cfg[351:320];
 wire [15:0] layer = cfg[367:352];
 wire [15:0] aid   = cfg[383:368];
 wire [15:0] bid   = cfg[399:384];
 wire [15:0] cid   = cfg[415:400];
 wire [15:0] positions = cfg[431:416];
 wire        clip = cfg[432];
 wire [15:0] target_high = cfg[463:448];
 wire [15:0] allowed = cfg[479:464];
 wire        cvalid = cfg[480];
 wire [15:0] ccompleted = cfg[511:496];

 wire [63:0] rows = ({32'd0,mdim} + 31) >> 5;
 wire [63:0] cols = ({32'd0,ndim} + 31) >> 5;
 wire [63:0] depths = ({32'd0,kdim} + 31) >> 5;
 wire [63:0] aend = {32'd0,abase} + rows*depths*64'd2048;
 wire [63:0] bend = {32'd0,bbase} + depths*cols*64'd1024;
 wire [63:0] cend = {32'd0,cbase} + rows*cols*64'd6144;
 wire [63:0] qend = {32'd0,queue_base} + ({32'd0,queue_count} << 6);
 wire b_in_arena = (bbase >= ARENA_BASE) && (bend <= ARENA_END);
 wire b_in_param = (bbase >= 32'h10000000) && (bend <= {32'd0,param_end}) &&
                   (param_end <= 32'h40000000);
 wire overlap_q = (abase < qend && queue_base < aend) ||
                  (cbase < qend && queue_base < cend) ||
                  (b_in_arena && (bbase < qend && queue_base < bend));
 wire overlap_ca = (abase < cend && cbase < aend);
 wire overlap_cb = b_in_arena && (bbase < cend && cbase < bend);
 wire bad_cfg = (epoch == 0) || (mdim == 0) || (ndim == 0) || (kdim == 0) ||
                (mdim > 4096) || (ndim > 4096) || (kdim > 4096) ||
                (cfg[447:433] != 0) || (cfg[495:481] != 0) ||
                (!cvalid && ccompleted != 0) || ((ccompleted & ~allowed) != 0) ||
                (abase < ARENA_BASE) || (cbase < ARENA_BASE) ||
                (aend > ARENA_END) || (cend > ARENA_END) ||
                (!b_in_arena && !b_in_param) || overlap_q ||
                (fused && (cvalid || ccompleted != 0 || overlap_ca || overlap_cb));

 reg start_pulse;
 reg done_pulse;
 reg fault_latched;
 reg [7:0] err_latched;
 reg [63:0] wd_count;
 reg [63:0] telem_cycles;
 reg [31:0] telem_compute,telem_rb,telem_wb,telem_hits,telem_misses;
 reg [31:0] telem_cg,telem_cc;
 reg [7:0] telem_pd,telem_ad;
 reg [63:0] acc_cycles;
 reg [31:0] acc_compute,acc_rb,acc_wb,acc_ops;

 // legacy cluster nets
 wire cl_busy,cl_done,cl_fault;
 wire [7:0] cl_error;
 wire [63:0] cl_cycles;
 wire [31:0] cl_compute,cl_rb,cl_wb,cl_hits,cl_misses;
 wire [31:0] cl_cg,cl_cc;
 wire [7:0] cl_pd,cl_ad;
 wire [31:0] cl_ro,cl_wo;
 wire [31:0] cl_craw;
 wire [39:0] cl_rd_araddr; wire [7:0] cl_rd_arlen; wire [2:0] cl_rd_arsize;
 wire [1:0] cl_rd_arburst; wire cl_rd_arvalid,cl_rd_arready,cl_rd_rlast,cl_rd_rvalid,cl_rd_rready;
 wire [127:0] cl_rd_rdata; wire [1:0] cl_rd_rresp;
 wire [39:0] cl_wr_awaddr; wire [7:0] cl_wr_awlen; wire [2:0] cl_wr_awsize;
 wire [1:0] cl_wr_awburst; wire cl_wr_awvalid,cl_wr_awready,cl_wr_wlast,cl_wr_wvalid,cl_wr_wready;
 wire [127:0] cl_wr_wdata; wire [15:0] cl_wr_wstrb; wire [1:0] cl_wr_bresp; wire cl_wr_bvalid,cl_wr_bready;
 // fused engine nets
 wire fu_busy,fu_done,fu_fault;
 wire [7:0] fu_error;
 wire [63:0] fu_cycles;
 wire [31:0] fu_compute,fu_rb,fu_wb,fu_cg,fu_cc,fu_craw;
 wire [7:0] fu_pd,fu_ad;
 wire [39:0] fu_rd_araddr; wire [7:0] fu_rd_arlen; wire [2:0] fu_rd_arsize;
 wire [1:0] fu_rd_arburst; wire fu_rd_arvalid,fu_rd_arready,fu_rd_rlast,fu_rd_rvalid,fu_rd_rready;
 wire [127:0] fu_rd_rdata; wire [1:0] fu_rd_rresp;
 wire [39:0] fu_wr_awaddr; wire [7:0] fu_wr_awlen; wire [2:0] fu_wr_awsize;
 wire [1:0] fu_wr_awburst; wire fu_wr_awvalid,fu_wr_awready,fu_wr_wlast,fu_wr_wvalid,fu_wr_wready;
 wire [127:0] fu_wr_wdata; wire [15:0] fu_wr_wstrb; wire [1:0] fu_wr_bresp; wire fu_wr_bvalid,fu_wr_bready;
 wire [31:0] fu_c48beats,fu_a16words,fu_fifo_high,fu_fifo_stalls,fu_c48ddr;
 wire [31:0] fu_drain_cycles,fu_lastw,fu_dmadone;
 wire [15:0] fu_tiles;
 wire [31:0] fu_rd_bytes,fu_rd_bursts,fu_wr_bytes,fu_wr_bursts,fu_rd_peak,fu_wr_peak;
 reg  fused_r;
 reg  fused_req_r, relu_req_r, pc_req_r;
 reg  [1:0] fma_req_r;
 // Latched at node start; the graph target may advance to the next node while
 // the queue descriptor is still being fetched.

 wire core_busy,core_done,core_fault;
 wire [7:0] core_error;
 wire [63:0] core_cycles;
 wire [31:0] core_compute,core_rb,core_wb,core_hits,core_misses;
 wire [31:0] core_cg,core_cc;
 wire [7:0] core_pd,core_ad;
 wire [31:0] core_ro,core_wo;
 wire [31:0] core_craw;

 assign core_busy  = fused_r ? fu_busy  : cl_busy;
 assign core_done  = fused_r ? fu_done  : cl_done;
 assign core_fault = fused_r ? fu_fault : cl_fault;
 assign core_error = fused_r ? fu_error : cl_error;
 assign core_cycles= fused_r ? fu_cycles: cl_cycles;
 assign core_compute=fused_r ? fu_compute:cl_compute;
 assign core_rb    = fused_r ? fu_rb    : cl_rb;
 assign core_wb    = fused_r ? fu_wb    : cl_wb;
 assign core_hits  = fused_r ? 32'd0    : cl_hits;
 assign core_misses= fused_r ? 32'd0    : cl_misses;
 assign core_cg    = fused_r ? fu_cg    : cl_cg;
 assign core_cc    = fused_r ? fu_cc    : cl_cc;
 assign core_pd    = fused_r ? fu_pd    : cl_pd;
 assign core_ad    = fused_r ? fu_ad    : cl_ad;
 assign core_ro    = fused_r ? 32'd0    : cl_ro;
 assign core_wo    = fused_r ? 32'd0    : cl_wo;
 assign core_craw  = fused_r ? fu_craw  : cl_craw;
 assign fuse_c48_ddr_bytes = fu_c48ddr; // fusion top: C48 DDR traffic, proven 0
 assign fuse_a16_bytes = fu_a16words * 16; // stat_a16_words counts 128-bit words

 // AXI owner mux: exactly one engine is selected per MAT child.
 assign rd_araddr  = fused_r ? fu_rd_araddr  : cl_rd_araddr;
 assign rd_arlen   = fused_r ? fu_rd_arlen   : cl_rd_arlen;
 assign rd_arsize  = fused_r ? fu_rd_arsize  : cl_rd_arsize;
 assign rd_arburst = fused_r ? fu_rd_arburst : cl_rd_arburst;
 assign rd_arvalid = fused_r ? fu_rd_arvalid : cl_rd_arvalid;
 assign rd_rready  = fused_r ? fu_rd_rready  : cl_rd_rready;
 assign wr_awaddr  = fused_r ? fu_wr_awaddr  : cl_wr_awaddr;
 assign wr_awlen   = fused_r ? fu_wr_awlen   : cl_wr_awlen;
 assign wr_awsize  = fused_r ? fu_wr_awsize  : cl_wr_awsize;
 assign wr_awburst = fused_r ? fu_wr_awburst : cl_wr_awburst;
 assign wr_awvalid = fused_r ? fu_wr_awvalid : cl_wr_awvalid;
 assign wr_wdata   = fused_r ? fu_wr_wdata   : cl_wr_wdata;
 assign wr_wstrb   = fused_r ? fu_wr_wstrb   : cl_wr_wstrb;
 assign wr_wlast   = fused_r ? fu_wr_wlast   : cl_wr_wlast;
 assign wr_wvalid  = fused_r ? fu_wr_wvalid  : cl_wr_wvalid;
 assign wr_bready  = fused_r ? fu_wr_bready  : cl_wr_bready;
 assign fu_rd_arready = rd_arready; assign fu_rd_rdata = rd_rdata;
 assign fu_rd_rresp = rd_rresp; assign fu_rd_rlast = rd_rlast; assign fu_rd_rvalid = rd_rvalid;
 assign fu_wr_awready = wr_awready; assign fu_wr_wready = wr_wready;
 assign fu_wr_bresp = wr_bresp; assign fu_wr_bvalid = wr_bvalid;
 assign cl_rd_arready = rd_arready; assign cl_rd_rdata = rd_rdata;
 assign cl_rd_rresp = rd_rresp; assign cl_rd_rlast = rd_rlast; assign cl_rd_rvalid = rd_rvalid;
 assign cl_wr_awready = wr_awready; assign cl_wr_wready = wr_wready;
 assign cl_wr_bresp = wr_bresp; assign cl_wr_bvalid = wr_bvalid;

 assign er = (st == S_IDLE);
 assign e_done = done_pulse;
 assign e_fault = fault_latched;
 assign e_error = err_latched;
 assign e_cycles = telem_cycles;
 assign matrix_cycles = telem_cycles;
 assign matrix_total_cycles = acc_cycles;
 assign matrix_total_compute = acc_compute;
 assign matrix_total_rb = acc_rb;
 assign matrix_total_wb = acc_wb;
 assign matrix_op_count = acc_ops;
 assign requires_reset = isolation_req;
 assign compute_cycles = telem_compute;
 assign read_blocks = telem_rb;
 assign write_blocks = telem_wb;
 assign cache_hits = telem_hits;
 assign cache_misses = telem_misses;
 assign c_collect_groups = telem_cg;
 assign c_collect_cycles = telem_cc;
 assign pe_drain_cycles = telem_pd;
 assign array_drain_cycles = telem_ad;
 assign completion_ready = 1'b1;

 matrix_p2_cluster_v2 #(
  .PIPE_STAGES(PIPE_STAGES),
  .ARENA_BASE(ARENA_BASE),
  .ARENA_END(ARENA_END)
 ) cluster (
  .clk(clk),.reset(!rst_n || (st == S_ISO) || fused_r),.start(start_pulse && !fused_r),
  .cfg_a_base(abase),.cfg_b_base(bbase),.cfg_c_base(cbase),.cfg_epoch(epoch),
  .cfg_m(mdim[15:0]),.cfg_n(ndim[15:0]),.cfg_k(kdim[15:0]),
  .cfg_layer(layer),.cfg_a_id(aid),.cfg_b_id(bid),.cfg_c_id(cid),
  .cfg_target_high(target_high),.cfg_allowed_ops(allowed),.cfg_requested_op(16'd1),
  .cfg_positions(positions),.cfg_clip(clip),.cfg_c_valid(cvalid),
  .cfg_c_completed(ccompleted),.param_end(param_end),
  .busy(cl_busy),.done(cl_done),.fault(cl_fault),.error_code(cl_error),
  .task_cycles(cl_cycles),.compute_cycles(cl_compute),.read_blocks(cl_rb),
  .write_blocks(cl_wb),.cache_hits(cl_hits),.cache_misses(cl_misses),
  .prefetch_hits(),.prefetch_wait_cycles(),
  .overlap_compute_read_cycles(cl_ro),.overlap_compute_write_cycles(cl_wo),
  .c_collect_groups(cl_cg),.c_collect_cycles(cl_cc),
  .c_raw_bypass_cycles(cl_craw),.pe_drain_cycles(cl_pd),
  .array_drain_cycles(cl_ad),
  .result_valid(),.result_ready(1'b1),.result_cache_address(),.result_epoch(),
  .result_target_low(),.result_layer(),.result_matrix(),.result_block_row(),
  .result_block_col(),.result_op_tag(),.result_data(),.result_block_valid(),
  .result_in_operation(),.result_allowed_ops(),.result_completed_ops(),
  .rd_m_axi_araddr(cl_rd_araddr),.rd_m_axi_arlen(cl_rd_arlen),
  .rd_m_axi_arsize(cl_rd_arsize),.rd_m_axi_arburst(cl_rd_arburst),
  .rd_m_axi_arvalid(cl_rd_arvalid),.rd_m_axi_arready(cl_rd_arready),
  .rd_m_axi_rdata(cl_rd_rdata),.rd_m_axi_rresp(cl_rd_rresp),
  .rd_m_axi_rlast(cl_rd_rlast),.rd_m_axi_rvalid(cl_rd_rvalid),
  .rd_m_axi_rready(cl_rd_rready),
  .wr_m_axi_awaddr(cl_wr_awaddr),.wr_m_axi_awlen(cl_wr_awlen),
  .wr_m_axi_awsize(cl_wr_awsize),.wr_m_axi_awburst(cl_wr_awburst),
  .wr_m_axi_awvalid(cl_wr_awvalid),.wr_m_axi_awready(cl_wr_awready),
  .wr_m_axi_wdata(cl_wr_wdata),.wr_m_axi_wstrb(cl_wr_wstrb),
  .wr_m_axi_wlast(cl_wr_wlast),.wr_m_axi_wvalid(cl_wr_wvalid),
  .wr_m_axi_wready(cl_wr_wready),.wr_m_axi_bresp(cl_wr_bresp),
  .wr_m_axi_bvalid(cl_wr_bvalid),.wr_m_axi_bready(cl_wr_bready),
  .rd_ar_outstanding_max(),.rd_read_bytes(),.rd_read_bursts(),
  .wr_b_outstanding_max(),.wr_write_bytes(),.wr_write_bursts(),
  .rd_read_fifo_high()
 );

 // ---------------------------------------------------------------------
 // V0.24 fused-MAT engine (selected only by the explicit MATF descriptor).
 // Reset policy: held in reset during a legacy run; released while the child
 // is idle so the host can preload the per-channel table once before START.
 // ---------------------------------------------------------------------
 wire fusion_reset = !rst_n || (st == S_ISO) || (!fused_r && st != S_IDLE);

 matrix_stream_fusion_top_v024 #(
  .SLOTS(2), .MAX_DIM(4096), .PIPE_STAGES(PIPE_STAGES),
  .ACCUM_MODE(0), .CPA_PIPE(1), .MAX_OUT(8), .FIFO_BEATS(128),
  .ARENA_BASE(ARENA_BASE), .ARENA_END(ARENA_END),
  .WR_OUT(8), .BRIDGE_FIFO(16), .A16_WORDS(128)
 ) u_fusion (
  .clk(clk), .reset(fusion_reset), .start(start_pulse && fused_r),
  .cfg_a_base(abase), .cfg_b_base(bbase), .cfg_a16_base(cbase),
  .cfg_epoch(epoch),
  .cfg_m(mdim[15:0]), .cfg_n(ndim[15:0]), .cfg_k(kdim[15:0]),
  .cfg_layer(layer), .cfg_a_id(aid), .cfg_b_id(bid), .cfg_c_id(cid),
  .cfg_target_high(target_high), .cfg_allowed_ops(allowed),
  .cfg_requested_op(16'd1), .cfg_positions(positions), .cfg_clip(clip),
  .cfg_c_valid(1'b0), .cfg_c_completed(16'd0), .param_end(param_end),
  .cfg_fma_mode(fma_req_r), .cfg_relu_en(relu_req_r),
  .cfg_perchannel_en(pc_req_r),
  .cfg_scale(fuse_scale), .cfg_bias(fuse_bias),
  .param_wr_valid(pc_wr_valid), .param_wr_ready(pc_wr_ready),
  .param_wr_addr(pc_wr_addr), .param_wr_data(pc_wr_data),
  .busy(fu_busy), .done(fu_done), .fault(fu_fault), .error_code(fu_error),
  .task_cycles(fu_cycles), .compute_cycles(fu_compute),
  .read_blocks(fu_rb), .write_blocks(fu_wb),
  .c_collect_groups(fu_cg), .c_collect_cycles(fu_cc),
  .c_raw_bypass_cycles(fu_craw), .pe_drain_cycles(fu_pd),
  .array_drain_cycles(fu_ad),
  .stat_c48_beats(fu_c48beats), .stat_a16_words(fu_a16words),
  .stat_a16_bytes(), .stat_fifo_high(fu_fifo_high),
  .stat_fifo_stalls(fu_fifo_stalls), .stat_c48_ddr_bytes(fu_c48ddr),
  .stat_drain_cycles(fu_drain_cycles), .stat_last_w_cycle(fu_lastw),
  .stat_dma_done_cycle(fu_dmadone), .stat_tiles(fu_tiles),
  .rd_m_axi_araddr(fu_rd_araddr), .rd_m_axi_arlen(fu_rd_arlen),
  .rd_m_axi_arsize(fu_rd_arsize), .rd_m_axi_arburst(fu_rd_arburst),
  .rd_m_axi_arvalid(fu_rd_arvalid), .rd_m_axi_arready(fu_rd_arready),
  .rd_m_axi_rdata(fu_rd_rdata), .rd_m_axi_rresp(fu_rd_rresp),
  .rd_m_axi_rlast(fu_rd_rlast), .rd_m_axi_rvalid(fu_rd_rvalid),
  .rd_m_axi_rready(fu_rd_rready),
  .wr_m_axi_awaddr(fu_wr_awaddr), .wr_m_axi_awlen(fu_wr_awlen),
  .wr_m_axi_awsize(fu_wr_awsize), .wr_m_axi_awburst(fu_wr_awburst),
  .wr_m_axi_awvalid(fu_wr_awvalid), .wr_m_axi_awready(fu_wr_awready),
  .wr_m_axi_wdata(fu_wr_wdata), .wr_m_axi_wstrb(fu_wr_wstrb),
  .wr_m_axi_wlast(fu_wr_wlast), .wr_m_axi_wvalid(fu_wr_wvalid),
  .wr_m_axi_wready(fu_wr_wready), .wr_m_axi_bresp(fu_wr_bresp),
  .wr_m_axi_bvalid(fu_wr_bvalid), .wr_m_axi_bready(fu_wr_bready),
  .rd_read_bytes(fu_rd_bytes), .rd_read_bursts(fu_rd_bursts),
  .wr_write_bytes(fu_wr_bytes), .wr_write_bursts(fu_wr_bursts),
  .rd_ar_outstanding_max(fu_rd_peak), .wr_b_outstanding_max(fu_wr_peak)
 );

 always @(posedge clk) begin
  if (!rst_n) begin
   cfg <= 0; st <= S_IDLE; start_pulse <= 0; done_pulse <= 0;
   fault_latched <= 0; err_latched <= 0; wd_count <= 0;
   telem_cycles <= 0; telem_compute <= 0; telem_rb <= 0; telem_wb <= 0;
   telem_hits <= 0; telem_misses <= 0; telem_cg <= 0; telem_cc <= 0;
   telem_pd <= 0; telem_ad <= 0;
   isolation_req <= 0; watchdog_fired <= 0;
   fused_r <= 0; fused_used <= 0;
   fused_req_r <= 0; fma_req_r <= 0; relu_req_r <= 0; pc_req_r <= 0;
   acc_cycles <= 0; acc_compute <= 0; acc_rb <= 0; acc_wb <= 0; acc_ops <= 0;
  end else begin
   start_pulse <= 0;
   done_pulse <= 0;
   case (st)
    S_IDLE: begin
     // Snapshot the explicit fusion descriptor at child start.
     if (start && er) begin
      fused_req_r <= fused; fma_req_r <= fuse_fma_mode;
      relu_req_r <= fuse_relu; pc_req_r <= fuse_perchannel_en;
     end
     // Reset the per-queue totals once, when the whole queue child starts.
     // `ev` is asserted once per descriptor by task_queue, so resetting there
     // would report only the last descriptor (the delivered bug).
     if (start && er) begin
      acc_cycles <= 0; acc_compute <= 0; acc_rb <= 0; acc_wb <= 0; acc_ops <= 0;
     end
     if (ev) begin
      cfg <= ed;
      fused_r <= fused_req_r;
      fused_used <= fused_req_r;
      // snapshot queue protect window is in task_queue; the adapter uses the
      // start-time queue_base/count inputs for overlap checks.
      st <= S_CHECK;
     end
    end
    S_CHECK: begin
     if (bad_cfg) begin
      fault_latched <= 1; err_latched <= 8'h81;
      done_pulse <= 1; telem_cycles <= 0;
      st <= S_DONE;
     end else begin
      st <= S_START;
     end
    end
    S_START: begin
     start_pulse <= 1; wd_count <= 0; st <= S_WAIT;
    end
    S_WAIT: begin
     // The cluster's `done` is a level that is cleared only by the next
     // start.  Entering RUN in the same cycle would consume the previous
     // task's done as this task's completion (multi-descriptor queues).
     if (!core_done) st <= S_RUN;
     else if (wd_count >= WATCHDOG) begin
      telem_cycles <= wd_count;
      fault_latched <= 1; err_latched <= 8'h0E;
      isolation_req <= 1; watchdog_fired <= 1;
      done_pulse <= 1;
      st <= S_ISO;
     end else wd_count <= wd_count + 1;
    end
    S_RUN: begin
     wd_count <= wd_count + 1;
     if (core_done) begin
      telem_cycles <= core_cycles;
      telem_compute <= core_compute; telem_rb <= core_rb; telem_wb <= core_wb;
      telem_hits <= core_hits; telem_misses <= core_misses;
      telem_cg <= core_cg; telem_cc <= core_cc;
      telem_pd <= core_pd; telem_ad <= core_ad;
      // One queue child can hold many descriptors.  Accumulate every task;
      // never report only the last task's counter as the queue total.
      acc_cycles <= acc_cycles + core_cycles;
      acc_compute <= acc_compute + core_compute;
      acc_rb <= acc_rb + core_rb;
      acc_wb <= acc_wb + core_wb;
      acc_ops <= acc_ops + 1;
      fault_latched <= core_fault;
      err_latched <= core_fault ? (core_error == 0 ? 8'h80 : core_error) : 8'h00;
      done_pulse <= 1;
      st <= S_DONE;
     end else if (wd_count >= WATCHDOG) begin
      // No abort port on the cluster: terminate the child contract and
      // request external isolation.  This is not a drained completion.
      telem_cycles <= wd_count;
      fault_latched <= 1; err_latched <= 8'h0E;
      isolation_req <= 1; watchdog_fired <= 1;
      done_pulse <= 1;
      st <= S_ISO;
     end
    end
    S_DONE: begin
     st <= S_IDLE;
    end
    S_ISO: begin
     // Latched until reset; the cluster is held in reset by st==S_ISO.
    end
    default: st <= S_IDLE;
   endcase
  end
 end
endmodule
