`timescale 1ns/1ps
module v024_ddr_core_wrapper (
 (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI ARUSER" *) output wire [0:0] m_aruser,
 (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI AWUSER" *) output wire [0:0] m_awuser,
 (* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 aclk CLK" *)
 (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME aclk, ASSOCIATED_BUSIF S_AXI:M_AXI, ASSOCIATED_RESET core_reset_n" *)
 input wire aclk,
 (* X_INTERFACE_INFO = "xilinx.com:signal:reset:1.0 core_reset_n RST" *)
 (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME core_reset_n, POLARITY ACTIVE_LOW" *)
 input wire core_reset_n,
 (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI AWADDR" *)
 (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME S_AXI, PROTOCOL AXI4LITE, DATA_WIDTH 32, ADDR_WIDTH 24, READ_WRITE_MODE READ_WRITE, NUM_READ_OUTSTANDING 1, NUM_WRITE_OUTSTANDING 1" *)
 input wire [23:0] s_axi_awaddr,
 (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI AWVALID" *)
 input wire  s_axi_awvalid,
 (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI AWREADY" *)
 output wire  s_axi_awready,
 (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI WDATA" *)
 input wire [31:0] s_axi_wdata,
 (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI WSTRB" *)
 input wire [3:0] s_axi_wstrb,
 (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI WVALID" *)
 input wire  s_axi_wvalid,
 (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI WREADY" *)
 output wire  s_axi_wready,
 (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI BRESP" *)
 output wire [1:0] s_axi_bresp,
 (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI BVALID" *)
 output wire  s_axi_bvalid,
 (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI BREADY" *)
 input wire  s_axi_bready,
 (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI ARADDR" *)
 input wire [23:0] s_axi_araddr,
 (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI ARVALID" *)
 input wire  s_axi_arvalid,
 (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI ARREADY" *)
 output wire  s_axi_arready,
 (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI RDATA" *)
 output wire [31:0] s_axi_rdata,
 (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI RRESP" *)
 output wire [1:0] s_axi_rresp,
 (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI RVALID" *)
 output wire  s_axi_rvalid,
 (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI RREADY" *)
 input wire  s_axi_rready,
 (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI ARADDR" *)
 (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME M_AXI, PROTOCOL AXI4, ARUSER_WIDTH 1, AWUSER_WIDTH 1, DATA_WIDTH 128, ADDR_WIDTH 40, ID_WIDTH 0, HAS_BURST 1, HAS_LOCK 0, HAS_CACHE 0, HAS_PROT 0, HAS_QOS 0, HAS_REGION 0, MAX_BURST_LENGTH 256, NUM_READ_OUTSTANDING 32, NUM_WRITE_OUTSTANDING 32, READ_WRITE_MODE READ_WRITE" *)
 output wire [39:0] m_araddr,
 (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI ARLEN" *)
 output wire [7:0] m_arlen,
 (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI ARSIZE" *)
 output wire [2:0] m_arsize,
 (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI ARBURST" *)
 output wire [1:0] m_arburst,
 (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI ARVALID" *)
 output wire  m_arvalid,
 (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI ARREADY" *)
 input wire  m_arready,
 (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI RDATA" *)
 input wire [127:0] m_rdata,
 (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI RRESP" *)
 input wire [1:0] m_rresp,
 (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI RLAST" *)
 input wire  m_rlast,
 (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI RVALID" *)
 input wire  m_rvalid,
 (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI RREADY" *)
 output wire  m_rready,
 (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI AWADDR" *)
 output wire [39:0] m_awaddr,
 (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI AWLEN" *)
 output wire [7:0] m_awlen,
 (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI AWSIZE" *)
 output wire [2:0] m_awsize,
 (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI AWBURST" *)
 output wire [1:0] m_awburst,
 (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI AWVALID" *)
 output wire  m_awvalid,
 (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI AWREADY" *)
 input wire  m_awready,
 (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI WDATA" *)
 output wire [127:0] m_wdata,
 (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI WSTRB" *)
 output wire [15:0] m_wstrb,
 (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI WLAST" *)
 output wire  m_wlast,
 (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI WVALID" *)
 output wire  m_wvalid,
 (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI WREADY" *)
 input wire  m_wready,
 (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI BRESP" *)
 input wire [1:0] m_bresp,
 (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI BVALID" *)
 input wire  m_bvalid,
 (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI BREADY" *)
 output wire  m_bready,
 input wire  pc_wr_valid,
 output wire  pc_wr_ready,
 input wire [7:0] pc_wr_addr,
 input wire [31:0] pc_wr_data,
 output wire  matrix_fused_used,
 output wire [31:0] fuse_c48_ddr_bytes,
 output wire [31:0] fuse_a16_bytes,
 output wire  busy,
 output wire  done,
 output wire  fault,
 output wire [7:0] error_code,
 output wire [31:0] completed,
 output wire [31:0] last_node,
 output wire [63:0] cycles,
 output wire  requires_reset,
 output wire  port_quiesced,
 output wire [31:0] rd_pending,
 output wire [31:0] wr_pending,
 output wire [31:0] b_pending,
 (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI AWPROT" *)
 input wire [2:0] s_axi_awprot,
 (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI ARPROT" *)
 input wire [2:0] s_axi_arprot
);
 assign m_aruser = 1'b0;
 assign m_awuser = 1'b0;
 (* DONT_TOUCH = "yes" *) v024_unified_top #(.MAX_NODES(128), .SEQ_ENABLE(0), .PARAM_END(32'h20000000)) core_i (
  .clk(aclk),
  .rst_n(core_reset_n),
  .seq_ready_i(1'b0),
  .seq_done_i(1'b0),
  .seq_fault_i(1'b0),
  .seq_error_i(8'b0),
  .seq_valid_o(),
  .seq_base_o(),
  .seq_count_o(),
  .s_axi_awaddr(s_axi_awaddr),
  .s_axi_awvalid(s_axi_awvalid),
  .s_axi_awready(s_axi_awready),
  .s_axi_wdata(s_axi_wdata),
  .s_axi_wstrb(s_axi_wstrb),
  .s_axi_wvalid(s_axi_wvalid),
  .s_axi_wready(s_axi_wready),
  .s_axi_bresp(s_axi_bresp),
  .s_axi_bvalid(s_axi_bvalid),
  .s_axi_bready(s_axi_bready),
  .s_axi_araddr(s_axi_araddr),
  .s_axi_arvalid(s_axi_arvalid),
  .s_axi_arready(s_axi_arready),
  .s_axi_rdata(s_axi_rdata),
  .s_axi_rresp(s_axi_rresp),
  .s_axi_rvalid(s_axi_rvalid),
  .s_axi_rready(s_axi_rready),
  .m_araddr(m_araddr),
  .m_arlen(m_arlen),
  .m_arsize(m_arsize),
  .m_arburst(m_arburst),
  .m_arvalid(m_arvalid),
  .m_arready(m_arready),
  .m_rdata(m_rdata),
  .m_rresp(m_rresp),
  .m_rlast(m_rlast),
  .m_rvalid(m_rvalid),
  .m_rready(m_rready),
  .m_awaddr(m_awaddr),
  .m_awlen(m_awlen),
  .m_awsize(m_awsize),
  .m_awburst(m_awburst),
  .m_awvalid(m_awvalid),
  .m_awready(m_awready),
  .m_wdata(m_wdata),
  .m_wstrb(m_wstrb),
  .m_wlast(m_wlast),
  .m_wvalid(m_wvalid),
  .m_wready(m_wready),
  .m_bresp(m_bresp),
  .m_bvalid(m_bvalid),
  .m_bready(m_bready),
  .pc_wr_valid(pc_wr_valid),
  .pc_wr_ready(pc_wr_ready),
  .pc_wr_addr(pc_wr_addr),
  .pc_wr_data(pc_wr_data),
  .matrix_fused_used(matrix_fused_used),
  .fuse_c48_ddr_bytes(fuse_c48_ddr_bytes),
  .fuse_a16_bytes(fuse_a16_bytes),
  .busy(busy),
  .done(done),
  .fault(fault),
  .irq(),
  .drain_timeout(),
  .error_code(error_code),
  .completed(completed),
  .last_node(last_node),
  .cycles(cycles),
  .seq_active(),
  .vector_busy(),
  .layout_busy(),
  .matrix_busy(),
  .matrix_error(),
  .matrix_cycles(),
  .matrix_compute_cycles(),
  .vector_cycles(),
  .layout_cycles(),
  .vector_read_bytes(),
  .vector_write_bytes(),
  .layout_read_bytes(),
  .layout_write_bytes(),
  .rd_bursts(),
  .wr_bursts(),
  .r_beats(),
  .w_beats(),
  .rd_peak(),
  .wr_peak(),
  .rd_stall_cycles(),
  .wr_stall_cycles(),
  .axi_tag_errors(),
  .isolation_req(),
  .requires_reset(requires_reset),
  .port_quiesced(port_quiesced),
  .rd_pending(rd_pending),
  .wr_pending(wr_pending),
  .b_pending(b_pending),
  .iso_blocked_reqs(),
  .seq_dispatch_timeout(),
  .seq_inflight_timeout(),
  .fetch_timeout(),
  .vector_total_cycles(),
  .layout_total_cycles(),
  .matrix_total_cycles(),
  .vector_op_count(),
  .layout_op_count(),
  .matrix_op_count()
 );
endmodule
