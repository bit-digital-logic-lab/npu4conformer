`timescale 1ns/1ps
// Host-sequenced exact sealed-RTL baseline for the same small chain as the
// integrated candidate:
//   LAY(A) -> LAY(W) -> MAT(32x32x32) -> I48->F32 -> MUL -> ADD -> F32->I16
//   -> LAY(copy)
// All engines share one AXI128 port through the same v023_axi_shared harness and
// the same scenario BFM used by the candidate harness.  The matrix path uses the
// sealed work/rtl baseline engine/storage plus axi_dma_v019.
//
// This is NOT the same control/interface boundary as the integrated superplan:
// the host starts every stage here.  Report comparable chain intervals, not a
// whole-machine speedup.
module tb_chain_baseline;
 localparam integer MAX_CYCLES = 400000;
 parameter [31:0] ARENA_A = 32'h04000000;
 parameter [31:0] ARENA_B = 32'h04001000;
 parameter [31:0] ARENA_C = 32'h04002000;
 parameter [31:0] ARENA_D0 = 32'h04004000;
 parameter [31:0] ARENA_D1 = 32'h04005000;
 parameter [31:0] ARENA_D2 = 32'h04006000;
 parameter [31:0] ARENA_I16 = 32'h04007000;
 parameter [31:0] ARENA_OUT = 32'h04008000;
 parameter [31:0] PARAM_END = 32'h10040000;
 parameter [31:0] PARAM_A = 32'h10001000;
 parameter [31:0] PARAM_W = 32'h10002000;
 parameter [31:0] SCALAR_SCALE = 32'h10000004;
 parameter [31:0] SCALAR_HALF = 32'h10000008;
 parameter [31:0] SCALAR_DUMMY = 32'h1000000C;

 reg clk=0; always #4 clk=~clk;
 reg rst_n=0;
 integer cyc=0, i, k;
 integer timeout=120000;
 integer errors=0;
 reg [1023:0] memfile, outfile, expfile;

 // ---------------- shared AXI port / BFM ----------------
 wire [39:0] s_araddr; wire [7:0] s_arlen; wire [2:0] s_arsize; wire [1:0] s_arburst;
 wire s_arvalid, s_arready; wire [127:0] s_rdata; wire [1:0] s_rresp; wire s_rlast,s_rvalid,s_rready;
 wire [39:0] s_awaddr; wire [7:0] s_awlen; wire [2:0] s_awsize; wire [1:0] s_awburst;
 wire s_awvalid, s_awready; wire [127:0] s_wdata; wire [15:0] s_wstrb; wire s_wlast,s_wvalid,s_wready;
 wire [1:0] s_bresp; wire s_bvalid,s_bready;
 wire [31:0] bfm_rb,bfm_wb,bfm_rbeats,bfm_wbeats,bfm_rbusy,bfm_wbusy,bfm_bwait;
 wire bfm_idle;
 axi128_bfm_scenario bfm(
  .clk(clk),.rst_n(rst_n),
  .araddr(s_araddr),.arlen(s_arlen),.arsize(s_arsize),.arburst(s_arburst),
  .arvalid(s_arvalid),.arready(s_arready),
  .rdata(s_rdata),.rresp(s_rresp),.rlast(s_rlast),.rvalid(s_rvalid),.rready(s_rready),
  .awaddr(s_awaddr),.awlen(s_awlen),.awsize(s_awsize),.awburst(s_awburst),
  .awvalid(s_awvalid),.awready(s_awready),
  .wdata(s_wdata),.wstrb(s_wstrb),.wlast(s_wlast),.wvalid(s_wvalid),.wready(s_wready),
  .bresp(s_bresp),.bvalid(s_bvalid),.bready(s_bready),
  .inject_read_error(1'b0),.inject_write_error(1'b0),
  .read_bursts(bfm_rb),.write_bursts(bfm_wb),.read_beats(bfm_rbeats),.write_beats(bfm_wbeats),
  .read_busy_cycles(bfm_rbusy),.write_busy_cycles(bfm_wbusy),.bresp_wait_cycles(bfm_bwait),
  .idle(bfm_idle));

 // ---------------- shared xbar (same harness as candidate) ----------------
 wire [2:0] xr_arvalid,xr_arready; wire [3*40-1:0] xr_araddr; wire [3*8-1:0] xr_arlen;
 wire [3*3-1:0] xr_arsize; wire [3*2-1:0] xr_arburst;
 wire [3*128-1:0] xr_rdata; wire [3*2-1:0] xr_rresp; wire [2:0] xr_rlast,xr_rvalid,xr_rready;
 wire [2:0] xw_awvalid,xw_awready; wire [3*40-1:0] xw_awaddr; wire [3*8-1:0] xw_awlen;
 wire [3*3-1:0] xw_awsize; wire [3*2-1:0] xw_awburst; wire [3*128-1:0] xw_wdata;
 wire [3*16-1:0] xw_wstrb; wire [2:0] xw_wlast,xw_wvalid,xw_wready,xw_bready;
 wire [3*2-1:0] xw_bresp; wire [2:0] xw_bvalid;
 wire [31:0] xrdb,xwrb,xrb,xwb,xrp,xwp,xrds,xwrs,xte;

 v023_axi_shared #(.NR(3),.NW(3),.CREDIT(8),.QDEPTH(32)) xbar(
  .clk(clk),.rst_n(rst_n),
  .m_arvalid(xr_arvalid),.m_arready(xr_arready),.m_araddr(xr_araddr),
  .m_arlen(xr_arlen),.m_arsize(xr_arsize),.m_arburst(xr_arburst),
  .m_rdata(xr_rdata),.m_rresp(xr_rresp),.m_rlast(xr_rlast),.m_rvalid(xr_rvalid),
  .m_rready(xr_rready),
  .s_araddr(s_araddr),.s_arlen(s_arlen),.s_arsize(s_arsize),.s_arburst(s_arburst),
  .s_arvalid(s_arvalid),.s_arready(s_arready),.s_rdata(s_rdata),.s_rresp(s_rresp),
  .s_rlast(s_rlast),.s_rvalid(s_rvalid),.s_rready(s_rready),
  .m_awvalid(xw_awvalid),.m_awready(xw_awready),.m_awaddr(xw_awaddr),
  .m_awlen(xw_awlen),.m_awsize(xw_awsize),.m_awburst(xw_awburst),
  .m_wdata(xw_wdata),.m_wstrb(xw_wstrb),.m_wlast(xw_wlast),.m_wvalid(xw_wvalid),
  .m_wready(xw_wready),.m_bready(xw_bready),.m_bresp(xw_bresp),.m_bvalid(xw_bvalid),
  .s_awaddr(s_awaddr),.s_awlen(s_awlen),.s_awsize(s_awsize),.s_awburst(s_awburst),
  .s_awvalid(s_awvalid),.s_awready(s_awready),.s_wdata(s_wdata),.s_wstrb(s_wstrb),
  .s_wlast(s_wlast),.s_wvalid(s_wvalid),.s_wready(s_wready),.s_bresp(s_bresp),
  .s_bvalid(s_bvalid),.s_bready(s_bready),
  .rd_bursts(xrdb),.wr_bursts(xwrb),.r_beats(xrb),.w_beats(xwb),.rd_peak(xrp),
  .wr_peak(xwp),.rd_stall_cycles(xrds),.wr_stall_cycles(xwrs),.tag_errors(xte));

 // ---------------- baseline matrix engine ----------------
 reg mat_start=0;
 reg [31:0] mat_epoch=32'd1;
 reg [15:0] mat_m=16'd32,mat_n=16'd32,mat_k=16'd32,mat_layer=16'd0;
 reg [15:0] mat_a_id=16'd1,mat_b_id=16'd2,mat_c_id=16'd3;
 reg [15:0] mat_target_high=16'd0,mat_allowed=16'd1,mat_requested=16'd1;
 reg [15:0] mat_positions=16'h3210,mat_c_completed=16'd0;
 reg mat_clip=1'b1,mat_c_valid=1'b0;
 wire mat_busy,mat_done,mat_fault; wire [7:0] mat_error; wire [63:0] mat_task_cycles;
 wire [31:0] mat_compute,mat_rblk,mat_wblk,mat_hits,mat_miss;
 wire mat_req_valid,mat_req_ready,mat_req_write;
 wire [31:0] mat_req_address,mat_req_epoch;
 wire [15:0] mat_req_layer,mat_req_matrix,mat_req_row,mat_req_col,mat_req_allowed,mat_req_completed;
 wire [1:0] mat_req_enc; wire mat_req_bvalid,mat_req_inop;
 wire mat_hdr_valid,mat_hdr_ready,mat_hdr_exists,mat_hdr_bvalid,mat_hdr_inop;
 wire [31:0] mat_hdr_epoch; wire [15:0] mat_hdr_layer,mat_hdr_matrix,mat_hdr_row,mat_hdr_col,mat_hdr_allowed,mat_hdr_completed;
 wire [1:0] mat_hdr_enc;
 wire mat_data_valid,mat_data_ready; wire [191:0] mat_data_in; wire [9:0] mat_data_index,mat_out_index;
 wire mat_data_last,mat_out_valid,mat_out_ready,mat_out_last,mat_write_ack,mat_write_error;
 wire [47:0] mat_out_data;
 wire mat_result_valid; wire [31:0] mat_result_cache_address,mat_result_epoch;
 wire [15:0] mat_result_target_low,mat_result_layer,mat_result_matrix,mat_result_block_row,mat_result_block_col,mat_result_op_tag;
 wire [49151:0] mat_result_data; wire mat_result_block_valid,mat_result_in_operation;
 wire [15:0] mat_result_allowed_ops,mat_result_completed_ops;
 wire [31:0] st_rblk,st_wblk,st_err; wire [63:0] st_rdwait,st_wrwait,st_scalar;
 wire mat_dma_request_valid,mat_dma_request_ready,mat_dma_request_write;
 wire [31:0] mat_dma_address; wire [15:0] mat_dma_beats;
 wire mat_dma_read_valid,mat_dma_read_ready; wire [127:0] mat_dma_read_data; wire [15:0] mat_dma_read_index;
 wire mat_dma_write_valid,mat_dma_write_ready; wire [127:0] mat_dma_write_data;
 wire [15:0] mat_dma_write_strobe,mat_dma_write_index;
 reg mat_dma_dir=0;
 wire mat_dma_done,mat_dma_error;
 wire m_rd_done,m_rd_error,m_wr_done,m_wr_error;

 // matrix read/write AXI masters (sealed axi_dma_v019)
 wire [39:0] m_rd_araddr; wire [7:0] m_rd_arlen; wire [2:0] m_rd_arsize; wire [1:0] m_rd_arburst;
 wire m_rd_arvalid,m_rd_arready; wire [127:0] m_rd_rdata; wire [1:0] m_rd_rresp; wire m_rd_rlast,m_rd_rvalid,m_rd_rready;
 wire [39:0] m_wr_awaddr; wire [7:0] m_wr_awlen; wire [2:0] m_wr_awsize; wire [1:0] m_wr_awburst;
 wire m_wr_awvalid,m_wr_awready; wire [127:0] m_wr_wdata; wire [15:0] m_wr_wstrb;
 wire m_wr_wlast,m_wr_wvalid,m_wr_wready; wire [1:0] m_wr_bresp; wire m_wr_bvalid,m_wr_bready;
 wire m_rd_req_ready,m_wr_req_ready;

 block_engine_banked_v020 #(.SLOTS(2)) meng(
  .clk(clk),.reset(!rst_n),.start(mat_start),
  .cfg_a_base(ARENA_A),.cfg_b_base(ARENA_B),.cfg_c_base(ARENA_C),.cfg_epoch(mat_epoch),
  .cfg_m(mat_m),.cfg_n(mat_n),.cfg_k(mat_k),.cfg_layer(mat_layer),.cfg_a_id(mat_a_id),
  .cfg_b_id(mat_b_id),.cfg_c_id(mat_c_id),.cfg_target_high(mat_target_high),
  .cfg_allowed_ops(mat_allowed),.cfg_requested_op(mat_requested),.cfg_positions(mat_positions),
  .cfg_clip(mat_clip),.busy(mat_busy),.done(mat_done),.fault(mat_fault),.error_code(mat_error),
  .task_cycles(mat_task_cycles),.compute_cycles(mat_compute),.read_blocks(mat_rblk),
  .write_blocks(mat_wblk),.cache_hits(mat_hits),.cache_misses(mat_miss),
  .req_valid(mat_req_valid),.req_ready(mat_req_ready),.req_write(mat_req_write),
  .req_address(mat_req_address),.req_epoch(mat_req_epoch),.req_layer(mat_req_layer),
  .req_matrix(mat_req_matrix),.req_block_row(mat_req_row),.req_block_col(mat_req_col),
  .req_allowed_ops(mat_req_allowed),.req_completed_ops(mat_req_completed),
  .req_encoding(mat_req_enc),.req_block_valid(mat_req_bvalid),.req_in_operation(mat_req_inop),
  .header_valid(mat_hdr_valid),.header_ready(mat_hdr_ready),.header_exists(mat_hdr_exists),
  .header_block_valid(mat_hdr_bvalid),.header_in_operation(mat_hdr_inop),
  .header_epoch(mat_hdr_epoch),.header_layer(mat_hdr_layer),.header_matrix(mat_hdr_matrix),
  .header_block_row(mat_hdr_row),.header_block_col(mat_hdr_col),.header_allowed_ops(mat_hdr_allowed),
  .header_completed_ops(mat_hdr_completed),.header_encoding(mat_hdr_enc),
  .data_valid(mat_data_valid),.data_ready(mat_data_ready),.data_in(mat_data_in),
  .data_index(mat_data_index),.data_last(mat_data_last),
  .out_valid(mat_out_valid),.out_ready(mat_out_ready),.out_data(mat_out_data),
  .out_index(mat_out_index),.out_last(mat_out_last),.write_ack(mat_write_ack),
  .write_error(mat_write_error),.result_valid(mat_result_valid),.result_ready(1'b1),
  .result_cache_address(mat_result_cache_address),.result_epoch(mat_result_epoch),
  .result_target_low(mat_result_target_low),.result_layer(mat_result_layer),
  .result_matrix(mat_result_matrix),.result_block_row(mat_result_block_row),
  .result_block_col(mat_result_block_col),.result_op_tag(mat_result_op_tag),
  .result_data(mat_result_data),.result_block_valid(mat_result_block_valid),
  .result_in_operation(mat_result_in_operation),.result_allowed_ops(mat_result_allowed_ops),
  .result_completed_ops(mat_result_completed_ops));

 block_storage_dma_wide4 #(.ARENA_BASE(32'h04000000),.ARENA_END(32'h08000000)) msto(
  .clk(clk),.rst_n(rst_n),.abort_scalar(mat_fault),.param_end(PARAM_END),
  .cfg_a_base(ARENA_A),.cfg_b_base(ARENA_B),.cfg_c_base(ARENA_C),.cfg_epoch(mat_epoch),
  .cfg_m(mat_m),.cfg_n(mat_n),.cfg_k(mat_k),.cfg_layer(mat_layer),.cfg_a_id(mat_a_id),
  .cfg_b_id(mat_b_id),.cfg_c_id(mat_c_id),.cfg_allowed(mat_allowed),.cfg_c_valid(mat_c_valid),
  .cfg_c_completed(mat_c_completed),
  .req_valid(mat_req_valid),.req_ready(mat_req_ready),.req_write(mat_req_write),
  .req_address(mat_req_address),.req_epoch(mat_req_epoch),.req_layer(mat_req_layer),
  .req_matrix(mat_req_matrix),.req_block_row(mat_req_row),.req_block_col(mat_req_col),
  .req_allowed_ops(mat_req_allowed),.req_completed_ops(mat_req_completed),
  .req_encoding(mat_req_enc),.req_block_valid(mat_req_bvalid),.req_in_operation(mat_req_inop),
  .header_valid(mat_hdr_valid),.header_ready(mat_hdr_ready),.header_exists(mat_hdr_exists),
  .header_block_valid(mat_hdr_bvalid),.header_in_operation(mat_hdr_inop),
  .header_epoch(mat_hdr_epoch),.header_layer(mat_hdr_layer),.header_matrix(mat_hdr_matrix),
  .header_block_row(mat_hdr_row),.header_block_col(mat_hdr_col),.header_allowed_ops(mat_hdr_allowed),
  .header_completed_ops(mat_hdr_completed),.header_encoding(mat_hdr_enc),
  .data_valid(mat_data_valid),.data_ready(mat_data_ready),.data_in(mat_data_in),
  .data_index(mat_data_index),.data_last(mat_data_last),
  .out_valid(mat_out_valid),.out_ready(mat_out_ready),.out_data(mat_out_data),
  .out_index(mat_out_index),.out_last(mat_out_last),.write_ack(mat_write_ack),
  .write_error(mat_write_error),
  .dma_request_valid(mat_dma_request_valid),.dma_request_ready(mat_dma_request_ready),
  .dma_request_write(mat_dma_request_write),.dma_address(mat_dma_address),.dma_beats(mat_dma_beats),
  .dma_read_valid(mat_dma_read_valid),.dma_read_ready(mat_dma_read_ready),
  .dma_read_data(mat_dma_read_data),.dma_read_index(mat_dma_read_index),
  .dma_write_valid(mat_dma_write_valid),.dma_write_ready(mat_dma_write_ready),
  .dma_write_data(mat_dma_write_data),.dma_write_strobe(mat_dma_write_strobe),
  .dma_write_index(mat_dma_write_index),.dma_done(mat_dma_done),.dma_error(mat_dma_error),
  .idle(),.transactions(),.read_blocks(st_rblk),.write_blocks(st_wblk),
  .error_transactions(st_err),.read_wait_cycles(st_rdwait),.write_wait_cycles(st_wrwait),
  .scalar_cycles(st_scalar));

 assign mat_dma_request_ready = mat_dma_request_write ? m_wr_req_ready : m_rd_req_ready;
 assign mat_dma_done = mat_dma_dir ? m_wr_done : m_rd_done;
 assign mat_dma_error = mat_dma_dir ? m_wr_error : m_rd_error;
 always @(posedge clk) if (rst_n && mat_dma_request_valid && mat_dma_request_ready)
  mat_dma_dir <= mat_dma_request_write;

 axi_dma_v019 mrd(
  .clk(clk),.rst_n(rst_n),
  .request_valid(mat_dma_request_valid && !mat_dma_request_write),.request_ready(m_rd_req_ready),
  .request_write(1'b0),.request_address(mat_dma_address),.request_beats(mat_dma_beats),
  .read_valid(mat_dma_read_valid),.read_ready(mat_dma_read_ready),.read_data(mat_dma_read_data),
  .read_index(mat_dma_read_index),.write_valid(1'b0),.write_ready(),.write_data(128'd0),
  .write_strobe(16'd0),.write_index(),.done(m_rd_done),.error(m_rd_error),
  .read_bytes(),.write_bytes(),.read_bursts(),.write_bursts(),
  .m_axi_araddr(m_rd_araddr),.m_axi_arlen(m_rd_arlen),.m_axi_arsize(m_rd_arsize),
  .m_axi_arburst(m_rd_arburst),.m_axi_arcache(),.m_axi_arprot(),
  .m_axi_arvalid(m_rd_arvalid),.m_axi_arready(m_rd_arready),
  .m_axi_rdata(m_rd_rdata),.m_axi_rresp(m_rd_rresp),.m_axi_rlast(m_rd_rlast),
  .m_axi_rvalid(m_rd_rvalid),.m_axi_rready(m_rd_rready),
  .m_axi_awaddr(),.m_axi_awlen(),.m_axi_awsize(),.m_axi_awburst(),.m_axi_awcache(),
  .m_axi_awprot(),.m_axi_awvalid(),.m_axi_awready(1'b0),.m_axi_wdata(),.m_axi_wstrb(),
  .m_axi_wlast(),.m_axi_wvalid(),.m_axi_wready(1'b0),.m_axi_bresp(2'd0),
  .m_axi_bvalid(1'b0),.m_axi_bready());

 axi_dma_v019 mwr(
  .clk(clk),.rst_n(rst_n),
  .request_valid(mat_dma_request_valid && mat_dma_request_write),.request_ready(m_wr_req_ready),
  .request_write(1'b1),.request_address(mat_dma_address),.request_beats(mat_dma_beats),
  .read_valid(),.read_ready(1'b1),.read_data(),.read_index(),
  .write_valid(mat_dma_write_valid),.write_ready(mat_dma_write_ready),
  .write_data(mat_dma_write_data),.write_strobe(mat_dma_write_strobe),
  .write_index(mat_dma_write_index),.done(m_wr_done),.error(m_wr_error),
  .read_bytes(),.write_bytes(),.read_bursts(),.write_bursts(),
  .m_axi_araddr(),.m_axi_arlen(),.m_axi_arsize(),.m_axi_arburst(),.m_axi_arcache(),
  .m_axi_arprot(),.m_axi_arvalid(),.m_axi_arready(1'b0),.m_axi_rdata(128'd0),
  .m_axi_rresp(2'd0),.m_axi_rlast(1'b0),.m_axi_rvalid(1'b0),.m_axi_rready(),
  .m_axi_awaddr(m_wr_awaddr),.m_axi_awlen(m_wr_awlen),.m_axi_awsize(m_wr_awsize),
  .m_axi_awburst(m_wr_awburst),.m_axi_awcache(),.m_axi_awprot(),
  .m_axi_awvalid(m_wr_awvalid),.m_axi_awready(m_wr_awready),
  .m_axi_wdata(m_wr_wdata),.m_axi_wstrb(m_wr_wstrb),.m_axi_wlast(m_wr_wlast),
  .m_axi_wvalid(m_wr_wvalid),.m_axi_wready(m_wr_wready),
  .m_axi_bresp(m_wr_bresp),.m_axi_bvalid(m_wr_bvalid),.m_axi_bready(m_wr_bready));

 // ---------------- baseline vector / layout ----------------
 reg v_start=0,l_start=0;
 reg [511:0] v_desc=0; reg [1023:0] l_desc=0;
 wire v_ready,v_busy,v_done,v_fault; wire [7:0] v_error,v_flags;
 wire [31:0] v_elems,v_rej; wire [63:0] v_cycles,v_ro,v_wo;
 wire [31:0] v_rb,v_wb,v_rburst,v_wburst;
 wire l_ready,l_busy,l_done,l_fault; wire [7:0] l_error;
 wire [31:0] l_elems,l_rej,l_hits,l_misses; wire [63:0] l_cycles;
 wire [31:0] l_rb,l_wb,l_rburst,l_wburst;

 wire [39:0] v_rd_araddr,v_rd_awaddr,v_wr_araddr,v_wr_awaddr;
 wire [7:0] v_rd_arlen,v_rd_awlen,v_wr_arlen,v_wr_awlen;
 wire [2:0] v_rd_arsize,v_rd_awsize,v_wr_arsize,v_wr_awsize;
 wire [1:0] v_rd_arburst,v_rd_awburst,v_wr_arburst,v_wr_awburst;
 wire v_rd_arvalid,v_rd_arready,v_rd_rlast,v_rd_rvalid,v_rd_rready;
 wire [127:0] v_rd_rdata; wire [1:0] v_rd_rresp;
 wire v_rd_awvalid,v_rd_awready,v_rd_wlast,v_rd_wvalid,v_rd_wready;
 wire [127:0] v_rd_wdata; wire [15:0] v_rd_wstrb; wire [1:0] v_rd_bresp; wire v_rd_bvalid,v_rd_bready;
 wire v_wr_arvalid,v_wr_arready,v_wr_rlast,v_wr_rvalid,v_wr_rready;
 wire [127:0] v_wr_rdata; wire [1:0] v_wr_rresp;
 wire v_wr_awvalid,v_wr_awready,v_wr_wlast,v_wr_wvalid,v_wr_wready;
 wire [127:0] v_wr_wdata; wire [15:0] v_wr_wstrb; wire [1:0] v_wr_bresp; wire v_wr_bvalid,v_wr_bready;

 ddr_vector_axi vec(
  .clk(clk),.rst_n(rst_n),.start(v_start),.descriptor(v_desc),.param_end(PARAM_END),
  .ready(v_ready),.busy(v_busy),.done(v_done),.fault(v_fault),.error_code(v_error),
  .numeric_flags(v_flags),.completed_elements(v_elems),.rejected_starts(v_rej),
  .cycles(v_cycles),.read_compute_overlap(v_ro),.write_compute_overlap(v_wo),
  .read_bytes(v_rb),.write_bytes(v_wb),.read_bursts(v_rburst),.write_bursts(v_wburst),
  .read_m_axi_araddr(v_rd_araddr),.read_m_axi_arlen(v_rd_arlen),.read_m_axi_arsize(v_rd_arsize),
  .read_m_axi_arburst(v_rd_arburst),.read_m_axi_arcache(),.read_m_axi_arprot(),
  .read_m_axi_arvalid(v_rd_arvalid),.read_m_axi_arready(v_rd_arready),
  .read_m_axi_rdata(v_rd_rdata),.read_m_axi_rresp(v_rd_rresp),.read_m_axi_rlast(v_rd_rlast),
  .read_m_axi_rvalid(v_rd_rvalid),.read_m_axi_rready(v_rd_rready),
  .read_m_axi_awaddr(v_rd_awaddr),.read_m_axi_awlen(v_rd_awlen),.read_m_axi_awsize(v_rd_awsize),
  .read_m_axi_awburst(v_rd_awburst),.read_m_axi_awcache(),.read_m_axi_awprot(),
  .read_m_axi_awvalid(v_rd_awvalid),.read_m_axi_awready(v_rd_awready),
  .read_m_axi_wdata(v_rd_wdata),.read_m_axi_wstrb(v_rd_wstrb),.read_m_axi_wlast(v_rd_wlast),
  .read_m_axi_wvalid(v_rd_wvalid),.read_m_axi_wready(v_rd_wready),
  .read_m_axi_bresp(v_rd_bresp),.read_m_axi_bvalid(v_rd_bvalid),.read_m_axi_bready(v_rd_bready),
  .write_m_axi_araddr(v_wr_araddr),.write_m_axi_arlen(v_wr_arlen),.write_m_axi_arsize(v_wr_arsize),
  .write_m_axi_arburst(v_wr_arburst),.write_m_axi_arcache(),.write_m_axi_arprot(),
  .write_m_axi_arvalid(v_wr_arvalid),.write_m_axi_arready(v_wr_arready),
  .write_m_axi_rdata(v_wr_rdata),.write_m_axi_rresp(v_wr_rresp),.write_m_axi_rlast(v_wr_rlast),
  .write_m_axi_rvalid(v_wr_rvalid),.write_m_axi_rready(v_wr_rready),
  .write_m_axi_awaddr(v_wr_awaddr),.write_m_axi_awlen(v_wr_awlen),.write_m_axi_awsize(v_wr_awsize),
  .write_m_axi_awburst(v_wr_awburst),.write_m_axi_awcache(),.write_m_axi_awprot(),
  .write_m_axi_awvalid(v_wr_awvalid),.write_m_axi_awready(v_wr_awready),
  .write_m_axi_wdata(v_wr_wdata),.write_m_axi_wstrb(v_wr_wstrb),.write_m_axi_wlast(v_wr_wlast),
  .write_m_axi_wvalid(v_wr_wvalid),.write_m_axi_wready(v_wr_wready),
  .write_m_axi_bresp(v_wr_bresp),.write_m_axi_bvalid(v_wr_bvalid),.write_m_axi_bready(v_wr_bready));

 wire [39:0] l_rd_araddr,l_rd_awaddr,l_wr_araddr,l_wr_awaddr;
 wire [7:0] l_rd_arlen,l_rd_awlen,l_wr_arlen,l_wr_awlen;
 wire [2:0] l_rd_arsize,l_rd_awsize,l_wr_arsize,l_wr_awsize;
 wire [1:0] l_rd_arburst,l_rd_awburst,l_wr_arburst,l_wr_awburst;
 wire l_rd_arvalid,l_rd_arready,l_rd_rlast,l_rd_rvalid,l_rd_rready;
 wire [127:0] l_rd_rdata; wire [1:0] l_rd_rresp;
 wire l_rd_awvalid,l_rd_awready,l_rd_wlast,l_rd_wvalid,l_rd_wready;
 wire [127:0] l_rd_wdata; wire [15:0] l_rd_wstrb; wire [1:0] l_rd_bresp; wire l_rd_bvalid,l_rd_bready;
 wire l_wr_arvalid,l_wr_arready,l_wr_rlast,l_wr_rvalid,l_wr_rready;
 wire [127:0] l_wr_rdata; wire [1:0] l_wr_rresp;
 wire l_wr_awvalid,l_wr_awready,l_wr_wlast,l_wr_wvalid,l_wr_wready;
 wire [127:0] l_wr_wdata; wire [15:0] l_wr_wstrb; wire [1:0] l_wr_bresp; wire l_wr_bvalid,l_wr_bready;

 ddr_layout_axi lay(
  .clk(clk),.rst_n(rst_n),.start(l_start),.descriptor(l_desc),.param_end(PARAM_END),
  .ready(l_ready),.busy(l_busy),.done(l_done),.fault(l_fault),.error_code(l_error),
  .processed_elements(l_elems),.rejected_starts(l_rej),.cache_hits(l_hits),.cache_misses(l_misses),
  .cycles(l_cycles),.read_bytes(l_rb),.write_bytes(l_wb),.read_bursts(l_rburst),.write_bursts(l_wburst),
  .read_m_axi_araddr(l_rd_araddr),.read_m_axi_arlen(l_rd_arlen),.read_m_axi_arsize(l_rd_arsize),
  .read_m_axi_arburst(l_rd_arburst),.read_m_axi_arcache(),.read_m_axi_arprot(),
  .read_m_axi_arvalid(l_rd_arvalid),.read_m_axi_arready(l_rd_arready),
  .read_m_axi_rdata(l_rd_rdata),.read_m_axi_rresp(l_rd_rresp),.read_m_axi_rlast(l_rd_rlast),
  .read_m_axi_rvalid(l_rd_rvalid),.read_m_axi_rready(l_rd_rready),
  .read_m_axi_awaddr(l_rd_awaddr),.read_m_axi_awlen(l_rd_awlen),.read_m_axi_awsize(l_rd_awsize),
  .read_m_axi_awburst(l_rd_awburst),.read_m_axi_awcache(),.read_m_axi_awprot(),
  .read_m_axi_awvalid(l_rd_awvalid),.read_m_axi_awready(l_rd_awready),
  .read_m_axi_wdata(l_rd_wdata),.read_m_axi_wstrb(l_rd_wstrb),.read_m_axi_wlast(l_rd_wlast),
  .read_m_axi_wvalid(l_rd_wvalid),.read_m_axi_wready(l_rd_wready),
  .read_m_axi_bresp(l_rd_bresp),.read_m_axi_bvalid(l_rd_bvalid),.read_m_axi_bready(l_rd_bready),
  .write_m_axi_araddr(l_wr_araddr),.write_m_axi_arlen(l_wr_arlen),.write_m_axi_arsize(l_wr_arsize),
  .write_m_axi_arburst(l_wr_arburst),.write_m_axi_arcache(),.write_m_axi_arprot(),
  .write_m_axi_arvalid(l_wr_arvalid),.write_m_axi_arready(l_wr_arready),
  .write_m_axi_rdata(l_wr_rdata),.write_m_axi_rresp(l_wr_rresp),.write_m_axi_rlast(l_wr_rlast),
  .write_m_axi_rvalid(l_wr_rvalid),.write_m_axi_rready(l_wr_rready),
  .write_m_axi_awaddr(l_wr_awaddr),.write_m_axi_awlen(l_wr_awlen),.write_m_axi_awsize(l_wr_awsize),
  .write_m_axi_awburst(l_wr_awburst),.write_m_axi_awcache(),.write_m_axi_awprot(),
  .write_m_axi_awvalid(l_wr_awvalid),.write_m_axi_awready(l_wr_awready),
  .write_m_axi_wdata(l_wr_wdata),.write_m_axi_wstrb(l_wr_wstrb),.write_m_axi_wlast(l_wr_wlast),
  .write_m_axi_wvalid(l_wr_wvalid),.write_m_axi_wready(l_wr_wready),
  .write_m_axi_bresp(l_wr_bresp),.write_m_axi_bvalid(l_wr_bvalid),.write_m_axi_bready(l_wr_bready));

 // ---------------- xbar master wiring: 0=matrix, 1=vector, 2=layout ----------------
 assign xr_arvalid[0]=m_rd_arvalid; assign xr_araddr[0*40+:40]=m_rd_araddr; assign xr_arlen[0*8+:8]=m_rd_arlen;
 assign xr_arsize[0*3+:3]=m_rd_arsize; assign xr_arburst[0*2+:2]=m_rd_arburst; assign m_rd_arready=xr_arready[0];
 assign m_rd_rdata=xr_rdata[0*128+:128]; assign m_rd_rresp=xr_rresp[0*2+:2]; assign m_rd_rlast=xr_rlast[0];
 assign m_rd_rvalid=xr_rvalid[0]; assign xr_rready[0]=m_rd_rready;
 assign xr_arvalid[1]=v_rd_arvalid; assign xr_araddr[1*40+:40]=v_rd_araddr; assign xr_arlen[1*8+:8]=v_rd_arlen;
 assign xr_arsize[1*3+:3]=v_rd_arsize; assign xr_arburst[1*2+:2]=v_rd_arburst; assign v_rd_arready=xr_arready[1];
 assign v_rd_rdata=xr_rdata[1*128+:128]; assign v_rd_rresp=xr_rresp[1*2+:2]; assign v_rd_rlast=xr_rlast[1];
 assign v_rd_rvalid=xr_rvalid[1]; assign xr_rready[1]=v_rd_rready;
 assign xr_arvalid[2]=l_rd_arvalid; assign xr_araddr[2*40+:40]=l_rd_araddr; assign xr_arlen[2*8+:8]=l_rd_arlen;
 assign xr_arsize[2*3+:3]=l_rd_arsize; assign xr_arburst[2*2+:2]=l_rd_arburst; assign l_rd_arready=xr_arready[2];
 assign l_rd_rdata=xr_rdata[2*128+:128]; assign l_rd_rresp=xr_rresp[2*2+:2]; assign l_rd_rlast=xr_rlast[2];
 assign l_rd_rvalid=xr_rvalid[2]; assign xr_rready[2]=l_rd_rready;

 assign xw_awvalid[0]=m_wr_awvalid; assign xw_awaddr[0*40+:40]=m_wr_awaddr; assign xw_awlen[0*8+:8]=m_wr_awlen;
 assign xw_awsize[0*3+:3]=m_wr_awsize; assign xw_awburst[0*2+:2]=m_wr_awburst; assign m_wr_awready=xw_awready[0];
 assign xw_wdata[0*128+:128]=m_wr_wdata; assign xw_wstrb[0*16+:16]=m_wr_wstrb; assign xw_wlast[0]=m_wr_wlast;
 assign xw_wvalid[0]=m_wr_wvalid; assign m_wr_wready=xw_wready[0]; assign m_wr_bvalid=xw_bvalid[0];
 assign m_wr_bresp=xw_bresp[0*2+:2]; assign xw_bready[0]=m_wr_bready;
 assign xw_awvalid[1]=v_wr_awvalid; assign xw_awaddr[1*40+:40]=v_wr_awaddr; assign xw_awlen[1*8+:8]=v_wr_awlen;
 assign xw_awsize[1*3+:3]=v_wr_awsize; assign xw_awburst[1*2+:2]=v_wr_awburst; assign v_wr_awready=xw_awready[1];
 assign xw_wdata[1*128+:128]=v_wr_wdata; assign xw_wstrb[1*16+:16]=v_wr_wstrb; assign xw_wlast[1]=v_wr_wlast;
 assign xw_wvalid[1]=v_wr_wvalid; assign v_wr_wready=xw_wready[1]; assign v_wr_bvalid=xw_bvalid[1];
 assign v_wr_bresp=xw_bresp[1*2+:2]; assign xw_bready[1]=v_wr_bready;
 assign xw_awvalid[2]=l_wr_awvalid; assign xw_awaddr[2*40+:40]=l_wr_awaddr; assign xw_awlen[2*8+:8]=l_wr_awlen;
 assign xw_awsize[2*3+:3]=l_wr_awsize; assign xw_awburst[2*2+:2]=l_wr_awburst; assign l_wr_awready=xw_awready[2];
 assign xw_wdata[2*128+:128]=l_wr_wdata; assign xw_wstrb[2*16+:16]=l_wr_wstrb; assign xw_wlast[2]=l_wr_wlast;
 assign xw_wvalid[2]=l_wr_wvalid; assign l_wr_wready=xw_wready[2]; assign l_wr_bvalid=xw_bvalid[2];
 assign l_wr_bresp=xw_bresp[2*2+:2]; assign xw_bready[2]=l_wr_bready;

 // ---------------- tasks / measurement ----------------
 integer chain_start=-1, chain_done=-1, chain_drain=-1;
 integer mat_first=-1, mat_last=-1, vec_first=-1, vec_last=-1, lay_first=-1, lay_last=-1;
 integer ar_wait=0, aw_wait=0, w_wait=0, r_wait=0, b_wait=0;
 integer mat_busy_cycles=0, vec_busy_cycles=0, lay_busy_cycles=0, any_busy=0;
 integer mat_cycles=0, vec_cycles_sum=0, lay_cycles_sum=0;
 integer vcyc[0:3]; integer lcyc[0:2];
 integer c48_errs=0;
 reg [47:0] expv[0:1023];

 always @(posedge clk) begin
  if (rst_n) begin
   if (mat_busy) begin if(mat_first<0)mat_first=cyc; mat_last=cyc; mat_busy_cycles=mat_busy_cycles+1; end
   if (v_busy) begin if(vec_first<0)vec_first=cyc; vec_last=cyc; vec_busy_cycles=vec_busy_cycles+1; end
   if (l_busy) begin if(lay_first<0)lay_first=cyc; lay_last=cyc; lay_busy_cycles=lay_busy_cycles+1; end
   if (mat_busy||v_busy||l_busy) any_busy=any_busy+1;
   if (s_arvalid && !s_arready) ar_wait=ar_wait+1;
   if (s_awvalid && !s_awready) aw_wait=aw_wait+1;
   if (s_wvalid && !s_wready) w_wait=w_wait+1;
   if (s_rvalid && !s_rready) r_wait=r_wait+1;
   if (s_bvalid && !s_bready) b_wait=b_wait+1;
  end
 end

 always @(posedge clk) if (rst_n && mat_result_valid && !mat_fault) begin
  for (integer ci=0; ci<1024; ci=ci+1)
   if (mat_result_data[ci*48+:48] !== expv[ci]) c48_errs = c48_errs + 1;
 end

 task drain_idle;
  integer guard;
 begin
  guard=0;
  while (!(bfm_idle && xbar.ar_count==0 && xbar.aw_count==0 && xbar.b_count==0) && guard<30000) begin
   @(posedge clk); guard=guard+1;
  end
  if (guard>=30000) begin
   $display("WATCHDOG_FIRED at=drain_idle cycle=%0d bfm_idle=%0d ar=%0d aw=%0d b=%0d mat_busy=%0d v_busy=%0d l_busy=%0d mat_st=%0d",
    cyc,bfm_idle,xbar.ar_count,xbar.aw_count,xbar.b_count,mat_busy,v_busy,l_busy,meng.state);
   $display("BASE_RESULT FAIL watchdog_drain");
   $fatal(1,"baseline drain watchdog");
  end
 end endtask

 task run_vec(input [511:0] d, output integer cyc_o);
 begin
  v_desc=d; @(negedge clk); while(!v_ready)@(negedge clk);
  if(chain_start<0)chain_start=cyc;
  v_start=1; @(negedge clk); v_start=0;
  while(!v_done)@(posedge clk);
  cyc_o=v_cycles;
  if(v_fault)begin $display("BASE_VEC_FAULT %02x",v_error);errors=errors+1;end
  drain_idle;
 end endtask

 task run_lay(input [1023:0] d, output integer cyc_o);
 begin
  l_desc=d; @(negedge clk); while(!l_ready)@(negedge clk);
  if(chain_start<0)chain_start=cyc;
  l_start=1; @(negedge clk); l_start=0;
  while(!l_done)@(posedge clk);
  cyc_o=l_cycles;
  if(l_fault)begin $display("BASE_LAY_FAULT %02x",l_error);errors=errors+1;end
  drain_idle;
 end endtask

 task run_mat;
 begin
  @(negedge clk); while(!msto.idle)@(negedge clk);
  if(chain_start<0)chain_start=cyc;
  mat_start=1; @(negedge clk); mat_start=0;
  while(!mat_done)@(posedge clk);
  mat_cycles=mat_task_cycles;
  if(mat_fault)begin $display("BASE_MAT_FAULT %02x",mat_error);errors=errors+1;end
  drain_idle;
 end endtask

 function [511:0] vd(input [15:0] wa, input [31:0] a,b,c,d, input [31:0] n);
 begin
  vd=512'd0; vd[31:0]=32'h22564543; vd[47:32]=wa;
  vd[95:64]=a; vd[127:96]=b; vd[159:128]=c; vd[191:160]=d; vd[223:192]=n;
 end endfunction
 function [1023:0] ld(input [31:0] mode,src,dst,total,nb);
 begin
  ld=1024'd0; ld[31:0]=32'h224c4159; ld[63:32]=mode; ld[95:64]=src; ld[127:96]=dst;
  ld[159:128]=total; ld[191:160]=nb;
 end endfunction

 initial begin
  if(!$value$plusargs("memfile=%s",memfile))memfile="inputs/mem_integrated.hex";
  if(!$value$plusargs("outfile=%s",outfile))outfile="out.hex";
  if(!$value$plusargs("exp=%s",expfile))expfile="inputs/mat32/exp_c.txt";
  if(!$value$plusargs("watchdog=%d",timeout))timeout=120000;
  $readmemh(expfile,expv);
  repeat(10)@(posedge clk); rst_n=1; repeat(6)@(posedge clk);

  $display("BASE_HOST_SEQUENCE begin at cycle %0d",cyc);
  run_lay(ld(0,PARAM_A,ARENA_A,1024,2),lcyc[0]); lay_cycles_sum=lay_cycles_sum+lcyc[0];
  run_lay(ld(0,PARAM_W,ARENA_B,512,2),lcyc[1]);  lay_cycles_sum=lay_cycles_sum+lcyc[1];
  run_mat;
  run_vec(vd(16'h200e,ARENA_C,SCALAR_DUMMY,0,ARENA_D0,1024),vcyc[0]); vec_cycles_sum=vec_cycles_sum+vcyc[0];
  run_vec(vd(16'h0402,ARENA_D0,SCALAR_SCALE,0,ARENA_D1,1024),vcyc[1]); vec_cycles_sum=vec_cycles_sum+vcyc[1];
  run_vec(vd(16'h0400,ARENA_D1,SCALAR_HALF,0,ARENA_D2,1024),vcyc[2]);  vec_cycles_sum=vec_cycles_sum+vcyc[2];
  run_vec(vd(16'h020f,ARENA_D2,0,0,ARENA_I16,1024),vcyc[3]);           vec_cycles_sum=vec_cycles_sum+vcyc[3];
  run_lay(ld(0,ARENA_I16,ARENA_OUT,1024,2),lcyc[2]); lay_cycles_sum=lay_cycles_sum+lcyc[2];
  chain_done=cyc;
  drain_idle;
  repeat(3)@(posedge clk);
  chain_drain=cyc;

  $display("BASE_TOTAL start=%0d done=%0d drain=%0d total_start_to_drain=%0d done_to_drain=%0d",
   chain_start,chain_done,chain_drain,chain_drain-chain_start,chain_drain-chain_done);
  $display("BASE_WINDOW matrix=%0d..%0d (%0d) vector=%0d..%0d (%0d) layout=%0d..%0d (%0d) any_busy=%0d",
   mat_first,mat_last,mat_busy_cycles,vec_first,vec_last,vec_busy_cycles,
   lay_first,lay_last,lay_busy_cycles,any_busy);
  $display("BASE_MATRIX cycles=%0d compute=%0d rblk=%0d wblk=%0d rdwait=%0d wrwait=%0d scalar=%0d c48_errs=%0d",
   mat_cycles,mat_compute,mat_rblk,mat_wblk,st_rdwait,st_wrwait,st_scalar,c48_errs);
  $display("BASE_VECLAY vcyc=%0d/%0d/%0d/%0d sum=%0d lcyc=%0d/%0d/%0d sum=%0d",
   vcyc[0],vcyc[1],vcyc[2],vcyc[3],vec_cycles_sum,lcyc[0],lcyc[1],lcyc[2],lay_cycles_sum);
  $display("BASE_AXI rburst=%0d wburst=%0d rbeats=%0d wbeats=%0d rdpeak=%0d wrpeak=%0d rdstall=%0d wrstall=%0d tag_err=%0d bfm_rbeats=%0d bfm_wbeats=%0d",
   xrdb,xwrb,xrb,xwb,xrp,xwp,xrds,xwrs,xte,bfm_rbeats,bfm_wbeats);
  $display("BASE_WAIT ar_stall=%0d aw_stall=%0d w_stall=%0d r_stall=%0d b_stall=%0d bfm_read_busy=%0d bfm_write_busy=%0d bfm_bresp_wait=%0d",
   ar_wait,aw_wait,w_wait,r_wait,b_wait,bfm_rbusy,bfm_wbusy,bfm_bwait);

  begin : dump
   integer fd;
   fd=$fopen(outfile,"w");
   for(i=0;i<512;i=i+1)$fwrite(fd,"%08x\n",bfm.memw[32'h12000+i]);
   $fclose(fd);
   fd=$fopen("stage_c48.hex","w");
   for(k=0;k<1536;k=k+1)$fwrite(fd,"%08x\n",bfm.memw[32'h10800+k]);
   $fclose(fd);
   fd=$fopen("stage_d0.hex","w");
   for(k=0;k<1024;k=k+1)$fwrite(fd,"%08x\n",bfm.memw[32'h11000+k]);
   $fclose(fd);
   fd=$fopen("stage_d1.hex","w");
   for(k=0;k<1024;k=k+1)$fwrite(fd,"%08x\n",bfm.memw[32'h11400+k]);
   $fclose(fd);
   fd=$fopen("stage_d2.hex","w");
   for(k=0;k<1024;k=k+1)$fwrite(fd,"%08x\n",bfm.memw[32'h11800+k]);
   $fclose(fd);
   fd=$fopen("stage_i16.hex","w");
   for(k=0;k<512;k=k+1)$fwrite(fd,"%08x\n",bfm.memw[32'h11c00+k]);
   $fclose(fd);
  end

  if(c48_errs!=0)errors=errors+1;
  if(chain_start<0||chain_drain<=chain_start)errors=errors+1;
  if(errors)$display("BASE_RESULT FAIL errors=%0d",errors); else $display("BASE_RESULT PASS");
  $finish;
 end

 always @(posedge clk) begin
  cyc<=cyc+1;
  if(cyc>timeout+2000)begin
   $display("WATCHDOG_FIRED at=global cycle=%0d mat_busy=%0d mat_st=%0d v_busy=%0d l_busy=%0d bfm_idle=%0d ar=%0d aw=%0d b=%0d",
    cyc,mat_busy,meng.state,v_busy,l_busy,bfm_idle,xbar.ar_count,xbar.aw_count,xbar.b_count);
   $display("BASE_RESULT FAIL watchdog_global");
   $fatal(1,"baseline global watchdog");
  end
 end
endmodule
