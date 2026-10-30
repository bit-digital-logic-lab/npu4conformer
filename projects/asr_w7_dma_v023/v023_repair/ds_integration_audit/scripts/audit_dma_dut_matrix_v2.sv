`timescale 1ns/1ps
// Uniform audit wrapper for ds_matrix axi_dma_v020_multi_v2.
// NOTE: this DMA has no abort/aborted/drained ports.  The wrapper ties them
// off so the same functional test can run; the missing abort contract is a
// reported integration blocker, not a PASS.
module audit_dma_dut #(
 parameter integer MAX_OUT=8,
 parameter integer FIFO_BEATS=128
)(
 input wire clk,rst_n,
 input wire req_valid,output wire req_ready,input wire req_write,
 input wire [31:0] req_addr,input wire [15:0] req_beats,
 output wire rd_valid,input wire rd_ready,output wire [127:0] rd_data,
 output wire [15:0] rd_index,
 input wire wr_valid,output wire wr_ready,input wire [127:0] wr_data,
 input wire [15:0] wr_strobe,output wire [15:0] wr_index,
 output wire done,error,
 output wire [31:0] rd_bytes,wr_bytes,rd_bursts,wr_bursts,
 output wire [31:0] ar_max,b_max,output wire [63:0] rd_fifo_high,
 input wire abort,output wire aborted,output wire drained,output wire busy,
 output wire [39:0] araddr,output wire [7:0] arlen,output wire [2:0] arsize,
 output wire [1:0] arburst,output wire [3:0] arcache,output wire [2:0] arprot,
 output wire arvalid,input wire arready,
 input wire [127:0] rdata,input wire [1:0] rresp,
 input wire rlast,rvalid,output wire rready,
 output wire [39:0] awaddr,output wire [7:0] awlen,output wire [2:0] awsize,
 output wire [1:0] awburst,output wire [3:0] awcache,output wire [2:0] awprot,
 output wire awvalid,input wire awready,
 output wire [127:0] wdata,output wire [15:0] wstrb,
 output wire wlast,wvalid,input wire wready,
 input wire [1:0] bresp,input wire bvalid,output wire bready
);
 reg done_r;
 axi_dma_v020_multi_v2 #(.MAX_OUT(MAX_OUT),.FIFO_BEATS(FIFO_BEATS)) u(
  .clk(clk),.rst_n(rst_n),
  .request_valid(req_valid),.request_ready(req_ready),.request_write(req_write),
  .request_address(req_addr),.request_beats(req_beats),
  .read_valid(rd_valid),.read_ready(rd_ready),.read_data(rd_data),.read_index(rd_index),
  .write_valid(wr_valid),.write_ready(wr_ready),.write_data(wr_data),
  .write_strobe(wr_strobe),.write_index(wr_index),
  .done(done_r),.error(error),.read_bytes(rd_bytes),.write_bytes(wr_bytes),
  .read_bursts(rd_bursts),.write_bursts(wr_bursts),
  .ar_outstanding_max(ar_max),.b_outstanding_max(b_max),
  .read_bubble_cycles(),.write_bubble_cycles(),.read_fifo_high(rd_fifo_high),
  .m_axi_araddr(araddr),.m_axi_arlen(arlen),.m_axi_arsize(arsize),
  .m_axi_arburst(arburst),.m_axi_arcache(arcache),.m_axi_arprot(arprot),
  .m_axi_arvalid(arvalid),.m_axi_arready(arready),
  .m_axi_rdata(rdata),.m_axi_rresp(rresp),.m_axi_rlast(rlast),
  .m_axi_rvalid(rvalid),.m_axi_rready(rready),
  .m_axi_awaddr(awaddr),.m_axi_awlen(awlen),.m_axi_awsize(awsize),
  .m_axi_awburst(awburst),.m_axi_awcache(awcache),.m_axi_awprot(awprot),
  .m_axi_awvalid(awvalid),.m_axi_awready(awready),
  .m_axi_wdata(wdata),.m_axi_wstrb(wstrb),.m_axi_wlast(wlast),
  .m_axi_wvalid(wvalid),.m_axi_wready(wready),
  .m_axi_bresp(bresp),.m_axi_bvalid(bvalid),.m_axi_bready(bready));
 assign done=done_r;
 assign aborted=1'b0;
 assign drained=done_r;
 assign busy=!done_r && (req_valid || rd_valid || arvalid || awvalid);
endmodule
