`timescale 1ns/1ps
// 部分 WSTRB 字节计数回归：同一个写负载分别驱动 V019 与 V020。
// 两种 DMA 的 write_bytes 都必须等于 sum(popcount(WSTRB))，不能把尾拍算成 16B。
// -DUSE_V019 选择原始 work/rtl/axi_dma_v019.sv；默认是 candidate v020。
module tb_strobe_account;
 localparam integer TB_BASE=40'h04000000;
 localparam integer NBEATS=64;          // 4 个 16beat 突发
 localparam integer TB_MEM_BYTES=65536;

 reg clk=0,rst_n=0;
 always #5 clk=~clk;

 // 单端口 AXI128 BFM
 wire [39:0] araddr,awaddr;
 wire [7:0]  arlen,awlen;
 wire [2:0]  arsize,awsize;
 wire [1:0]  arburst,awburst;
 wire arvalid,arready,awvalid,awready;
 wire [127:0] rdata,wdata;
 wire [1:0] rresp,bresp;
 wire rlast,rvalid,rready,wlast,wvalid,wready;
 wire [15:0] wstrb;
 wire bvalid,bready;
 wire [63:0] total_cycles,wbeats,rbeats;

 axi128_ddr_bfm #(.PORTS(1),.MAX_OUT(4),
   .LAT_MIN(4),.LAT_MAX(16),.BLAT_MIN(2),.BLAT_MAX(8),
   .TURNAROUND(2),.READY_STALL_PCT(0),.SEED(7)) bfm(
  .clk(clk),.rst_n(rst_n),
  .araddr(araddr),.arlen(arlen),.arsize(arsize),.arburst(arburst),
  .arvalid(arvalid),.arready(arready),
  .rdata(rdata),.rresp(rresp),.rlast(rlast),.rvalid(rvalid),.rready(rready),
  .awaddr(awaddr),.awlen(awlen),.awsize(awsize),.awburst(awburst),
  .awvalid(awvalid),.awready(awready),
  .wdata(wdata),.wstrb(wstrb),.wlast(wlast),.wvalid(wvalid),.wready(wready),
  .bresp(bresp),.bvalid(bvalid),.bready(bready),
  .inject_read_error(1'b0),.inject_write_error(1'b0),
  .cycles(total_cycles),.bus_read_beats(rbeats),.bus_write_beats(wbeats),
  .bus_idle_cycles(),.bus_turnaround_cycles(),.bus_busy_cycles(),
  .read_bursts(),.write_bursts(),.max_rd_out(),.max_wr_out(),
  .ar_stall_cycles(),.aw_stall_cycles(),.r_stall_cycles(),.w_stall_cycles());

 reg req_valid;wire req_ready;reg req_write;reg [31:0] req_addr;reg [15:0] req_beats;
 wire rd_valid;wire [127:0] rd_data;wire [15:0] rd_index;
 reg wr_valid;wire wr_ready;reg [127:0] wr_data;reg [15:0] wr_strobe;wire [15:0] wr_index;
 wire done,error;
 wire [31:0] rbytes,wbytes,rburst_dma,wburst_dma;

`ifdef USE_V019
 axi_dma_v019 dut(
  .clk(clk),.rst_n(rst_n),
  .request_valid(req_valid),.request_ready(req_ready),.request_write(req_write),
  .request_address(req_addr),.request_beats(req_beats),
  .read_valid(rd_valid),.read_ready(1'b1),.read_data(rd_data),.read_index(rd_index),
  .write_valid(wr_valid),.write_ready(wr_ready),.write_data(wr_data),
  .write_strobe(wr_strobe),.write_index(wr_index),
  .done(done),.error(error),
  .read_bytes(rbytes),.write_bytes(wbytes),
  .read_bursts(rburst_dma),.write_bursts(wburst_dma),
  .m_axi_araddr(araddr),.m_axi_arlen(arlen),.m_axi_arsize(arsize),
  .m_axi_arburst(arburst),.m_axi_arcache(),.m_axi_arprot(),
  .m_axi_arvalid(arvalid),.m_axi_arready(arready),
  .m_axi_rdata(rdata),.m_axi_rresp(rresp),.m_axi_rlast(rlast),
  .m_axi_rvalid(rvalid),.m_axi_rready(rready),
  .m_axi_awaddr(awaddr),.m_axi_awlen(awlen),.m_axi_awsize(awsize),
  .m_axi_awburst(awburst),.m_axi_awcache(),.m_axi_awprot(),
  .m_axi_awvalid(awvalid),.m_axi_awready(awready),
  .m_axi_wdata(wdata),.m_axi_wstrb(wstrb),.m_axi_wlast(wlast),
  .m_axi_wvalid(wvalid),.m_axi_wready(wready),
  .m_axi_bresp(bresp),.m_axi_bvalid(bvalid),.m_axi_bready(bready));
`else
 axi_dma_v020_multi #(.MAX_OUT(4),.FIFO_BEATS(64),.MAX_BURST(16)) dut(
  .clk(clk),.rst_n(rst_n),
  .request_valid(req_valid),.request_ready(req_ready),.request_write(req_write),
  .request_address(req_addr),.request_beats(req_beats),
  .read_valid(rd_valid),.read_ready(1'b1),.read_data(rd_data),.read_index(rd_index),
  .write_valid(wr_valid),.write_ready(wr_ready),.write_data(wr_data),
  .write_strobe(wr_strobe),.write_index(wr_index),
  .done(done),.error(error),
  .read_bytes(rbytes),.write_bytes(wbytes),
  .read_bursts(rburst_dma),.write_bursts(wburst_dma),
  .ar_outstanding_max(),.b_outstanding_max(),
  .read_bubble_cycles(),.write_bubble_cycles(),.read_fifo_high(),
  .m_axi_araddr(araddr),.m_axi_arlen(arlen),.m_axi_arsize(arsize),
  .m_axi_arburst(arburst),.m_axi_arcache(),.m_axi_arprot(),
  .m_axi_arvalid(arvalid),.m_axi_arready(arready),
  .m_axi_rdata(rdata),.m_axi_rresp(rresp),.m_axi_rlast(rlast),
  .m_axi_rvalid(rvalid),.m_axi_rready(rready),
  .m_axi_awaddr(awaddr),.m_axi_awlen(awlen),.m_axi_awsize(awsize),
  .m_axi_awburst(awburst),.m_axi_awcache(),.m_axi_awprot(),
  .m_axi_awvalid(awvalid),.m_axi_awready(awready),
  .m_axi_wdata(wdata),.m_axi_wstrb(wstrb),.m_axi_wlast(wlast),
  .m_axi_wvalid(wvalid),.m_axi_wready(wready),
  .m_axi_bresp(bresp),.m_axi_bvalid(bvalid),.m_axi_bready(bready));
`endif

 // 8 种部分 strobe 循环；每 8 beat 共 49 字节
 function automatic [15:0] pat(input integer i);
  begin
   case(i%8)
    0:pat=16'hffff; 1:pat=16'h0001; 2:pat=16'h8000; 3:pat=16'h0f0f;
    4:pat=16'h00ff; 5:pat=16'hffff; 6:pat=16'h0100; default:pat=16'h0003;
   endcase
  end
 endfunction
 function automatic integer pc(input [15:0] b);
  integer j;begin pc=0;for(j=0;j<16;j=j+1)pc=pc+b[j];end
 endfunction

 integer i,exp_bytes,timeout,prev,dbg;
 initial begin
  exp_bytes=0;
  for(i=0;i<NBEATS;i=i+1)exp_bytes=exp_bytes+pc(pat(i));
  req_valid=0;req_write=0;req_addr=0;req_beats=0;
  wr_valid=0;wr_data=0;wr_strobe=0;
  repeat(5) @(posedge clk);
  @(negedge clk);rst_n=1;
  repeat(2) @(posedge clk);

  // 发一笔 64beat 写请求
  @(negedge clk);req_valid=1;req_write=1;req_addr=TB_BASE;req_beats=NBEATS;
  while(!req_ready) @(negedge clk);
  @(posedge clk);
  @(negedge clk);req_valid=0;

  // 每个 beat 使用不同部分 strobe；用 write_index 递增确认真正被接收，
  // 避免在 wready 于 negedge/posedge 之间变化时丢 beat。
  for(i=0;i<NBEATS;i=i+1)begin
   wr_valid=1;wr_strobe=pat(i);wr_data={4{32'hA5A50000+i[15:0]}};
   prev=wr_index;
   while(wr_index==prev) @(negedge clk);
  end
  wr_valid=0;wr_strobe=0;

  timeout=0;
  while(!done&&timeout<200000)begin @(posedge clk);timeout=timeout+1;end
  $display("STROBE_RESULT exp=%0d got=%0d error=%0d cycles=%0d dma_wbeats=%0d bfm_wbeats=%0d",
           exp_bytes,wbytes,error,timeout,wburst_dma,wbeats);
  if(!done)begin $display("STROBE_FAIL timeout");$fatal;end
  if(error)begin $display("STROBE_FAIL error");$fatal;end
  if(wbytes!==exp_bytes)begin $display("STROBE_FAIL byte_account");$fatal;end
  $display("STROBE_PASS");
  $finish;
 end
endmodule
