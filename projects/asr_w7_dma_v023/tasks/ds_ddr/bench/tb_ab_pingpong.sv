`timescale 1ns/1ps
// A/W ping-pong before/after：同一 RTL、同一 BFM、同一 4 页负载。
// +prefetch=0：消费者释放当前页后才送下一描述符（串行）。
// +prefetch=1：启动时把 4 个描述符全部入队（真实页预取）。
`ifndef LATMIN
 `define LATMIN 32
`endif
`ifndef LATMAX
 `define LATMAX 32
`endif
`ifndef SEED
 `define SEED 5
`endif
module tb_ab_pingpong;
 localparam integer BASE=40'h04000000;
 localparam integer MEM_BYTES=262144;
 localparam integer PAGE_BEATS=64;
 localparam integer NDESC=4;
 localparam integer CONSUME_CYCLES=300;
 reg clk=0,rst_n=0;
 always #5 clk=~clk;
 integer prefetch;
 integer cyc_start,cyc_end;
 reg pass;
 integer i,page_count;
 reg [127:0] wtmp;

 reg [39:0] araddr;reg [7:0] arlen;reg [2:0] arsize;reg [1:0] arburst;reg arvalid;wire arready;
 wire [127:0] rdata;wire [1:0] rresp;wire rlast,rvalid;wire rready;
 reg [39:0] awaddr;reg [7:0] awlen;reg [2:0] awsize;reg [1:0] awburst;reg awvalid;wire awready;
 reg [127:0] wdata;reg [15:0] wstrb;reg wlast,wvalid;wire wready;
 wire [1:0] bresp;wire bvalid;reg bready;
 wire [63:0] total_cycles,read_beats,write_beats;
 axi128_ddr_bfm #(.PORTS(1),.MAX_OUT(8),.LAT_MIN(`LATMIN),.LAT_MAX(`LATMAX),
   .BLAT_MIN(4),.BLAT_MAX(12),.TURNAROUND(0),.READY_STALL_PCT(0),.SEED(`SEED)) bfm(
  .clk(clk),.rst_n(rst_n),.araddr(araddr),.arlen(arlen),.arsize(arsize),.arburst(arburst),.arvalid(arvalid),.arready(arready),
  .rdata(rdata),.rresp(rresp),.rlast(rlast),.rvalid(rvalid),.rready(rready),
  .awaddr(awaddr),.awlen(awlen),.awsize(awsize),.awburst(awburst),.awvalid(awvalid),.awready(awready),
  .wdata(wdata),.wstrb(wstrb),.wlast(wlast),.wvalid(wvalid),.wready(wready),.bresp(bresp),.bvalid(bvalid),.bready(bready),
  .inject_read_error(1'b0),.inject_write_error(1'b0),
  .cycles(total_cycles),.bus_read_beats(read_beats),.bus_write_beats(write_beats),
  .bus_idle_cycles(),.bus_turnaround_cycles(),.bus_busy_cycles(),
  .read_bursts(),.write_bursts(),.max_rd_out(),.max_wr_out(),
  .ar_stall_cycles(),.aw_stall_cycles(),.r_stall_cycles(),.w_stall_cycles());

 wire dma_req_valid,dma_req_ready;wire [31:0] dma_req_addr;wire [15:0] dma_req_beats;
 wire dma_read_valid,dma_read_ready;wire [127:0] dma_read_data;wire [15:0] dma_read_index;
 wire dma_done,dma_error;
 wire rd_valid;wire [127:0] rd_data;wire [15:0] rd_index;
 wire rd_done,rd_error;
 axi_dma_v020_multi #(.MAX_OUT(8),.FIFO_BEATS(128)) dma(
  .clk(clk),.rst_n(rst_n),.request_valid(dma_req_valid),.request_ready(dma_req_ready),.request_write(1'b0),
  .request_address(dma_req_addr),.request_beats(dma_req_beats),
  .read_valid(rd_valid),.read_ready(dma_read_ready),.read_data(rd_data),.read_index(rd_index),
  .write_valid(1'b0),.write_ready(),.write_data(128'd0),.write_strobe(16'd0),.write_index(),
  .done(rd_done),.error(rd_error),.read_bytes(),.write_bytes(),.read_bursts(),.write_bursts(),
  .ar_outstanding_max(),.b_outstanding_max(),.read_bubble_cycles(),.write_bubble_cycles(),.read_fifo_high(),
  .m_axi_araddr(araddr),.m_axi_arlen(arlen),.m_axi_arsize(arsize),.m_axi_arburst(arburst),.m_axi_arcache(),.m_axi_arprot(),
  .m_axi_arvalid(arvalid),.m_axi_arready(arready),.m_axi_rdata(rdata),.m_axi_rresp(rresp),.m_axi_rlast(rlast),.m_axi_rvalid(rvalid),.m_axi_rready(rready),
  .m_axi_awaddr(),.m_axi_awlen(),.m_axi_awsize(),.m_axi_awburst(),.m_axi_awcache(),.m_axi_awprot(),.m_axi_awvalid(),.m_axi_awready(1'b0),
  .m_axi_wdata(),.m_axi_wstrb(),.m_axi_wlast(),.m_axi_wvalid(),.m_axi_wready(1'b0),.m_axi_bresp(2'b0),.m_axi_bvalid(1'b0),.m_axi_bready());
 assign dma_read_valid=rd_valid;assign dma_read_data=rd_data;assign dma_read_index=rd_index;
 assign dma_done=rd_done;assign dma_error=rd_error;

 reg start,desc_valid;wire desc_ready;reg [31:0] desc_addr;reg [15:0] desc_beats;reg [7:0] desc_tag;reg desc_last;
 wire [1:0] page_valid,page_busy;reg [1:0] consume_bank;reg consume_done;reg [5:0] consume_addr;wire [127:0] consume_data;
 wire pp_done,pp_error;wire [31:0] prefetch_count,consume_count,overlap_cycles,stall_cycles,fill_cycles;
 ab_pingpong_prefetch #(.PAGE_BEATS(PAGE_BEATS)) pp(
  .clk(clk),.rst_n(rst_n),.start(start),.desc_valid(desc_valid),.desc_ready(desc_ready),
  .desc_addr(desc_addr),.desc_beats(desc_beats),.desc_tag(desc_tag),.desc_last(desc_last),
  .dma_req_valid(dma_req_valid),.dma_req_ready(dma_req_ready),.dma_req_addr(dma_req_addr),.dma_req_beats(dma_req_beats),
  .dma_read_valid(dma_read_valid),.dma_read_ready(dma_read_ready),.dma_read_data(dma_read_data),.dma_read_index(dma_read_index),
  .dma_done(dma_done),.dma_error(dma_error),
  .consume_bank(consume_bank),.consume_done(consume_done),.consume_addr(consume_addr),.consume_data(consume_data),
  .page_valid(page_valid),.page_busy(page_busy),.done(pp_done),.error(pp_error),
  .prefetch_count(prefetch_count),.consume_count(consume_count),.overlap_cycles(overlap_cycles),.stall_cycles(stall_cycles),.fill_cycles(fill_cycles));

 function [127:0] pat(input integer word);
  begin
   pat=0;
   for(integer j=0;j<16;j=j+1)pat[j*8+:8]=(word*7+j*11+3)&255;
  end
 endfunction
 function [127:0] mem_word(input [39:0] a,input integer beat);
  integer lane;integer idx;
  begin
   idx=262144+(a-BASE)+beat*16;
   for(lane=0;lane<16;lane=lane+1)mem_word[lane*8+:8]=bfm.memory[idx+lane];
  end
 endfunction

 integer tbcyc=0;
 always @(posedge clk)begin tbcyc<=tbcyc+1;if(tbcyc%10000==0)$display("PPDBG state=%0d q=%0d req=%b rdy=%b dstate=%0d descv=%b desr=%b pv=%b pb=%b",pp.state,pp.q_cnt,dma_req_valid,dma_req_ready,dma.state,desc_valid,desc_ready,page_valid,page_busy);if(tbcyc>300000)$fatal(1,"TB watchdog");end

 task send_desc(input integer n);
  begin
   desc_addr<=BASE+n*32'h00001000;desc_beats<=PAGE_BEATS;desc_tag<=n;
   desc_last<=(n==NDESC-1);desc_valid<=1;
   @(posedge clk);
   while(!desc_ready)@(posedge clk);
   desc_valid<=0;
  end
 endtask

 task consume_page(input integer bank,input integer n);
  integer k;
  begin
   $display("CONSUME_START bank=%0d n=%0d",bank,n);
   for(k=0;k<PAGE_BEATS;k=k+1)begin
    consume_addr<=k[5:0];#1;
    if(consume_data!==mem_word(BASE+n*32'h00001000,k))begin
     $display("PAGE MISMATCH bank=%0d n=%0d k=%0d got=%h exp=%h",bank,n,k,consume_data,mem_word(BASE+n*32'h00001000,k));pass=0;
    end
   end
   repeat(CONSUME_CYCLES)@(posedge clk);
   consume_bank<=bank;consume_done<=1;@(posedge clk);consume_done<=0;$display("CONSUME_END bank=%0d n=%0d",bank,n);
  end
 endtask

 initial begin
  if(!$value$plusargs("prefetch=%d",prefetch))prefetch=1;
  for(i=0;i<MEM_BYTES/16;i=i+1)begin
   wtmp=pat(i);
   for(integer j=0;j<16;j=j+1)bfm.memory[262144+i*16+j]=wtmp[j*8+:8];
  end
  start=0;desc_valid=0;desc_addr=0;desc_beats=0;desc_tag=0;desc_last=0;
  consume_bank=0;consume_done=0;consume_addr=0;
  bready=1;
  repeat(8)@(posedge clk);rst_n=1;repeat(4)@(posedge clk);
  pass=1;page_count=0;cyc_start=total_cycles;
  start<=1;@(posedge clk);start<=0;
  if(prefetch==1)begin
   for(i=0;i<NDESC;i=i+1)send_desc(i);
   while(page_count<NDESC)begin
    @(posedge clk);
    if(page_valid[0])begin consume_page(0,page_count);page_count=page_count+1;end
    else if(page_valid[1])begin consume_page(1,page_count);page_count=page_count+1;end
   end
  end else begin
   for(i=0;i<NDESC;i=i+1)begin
    send_desc(i);
    while(!(page_valid[0]||page_valid[1]))@(posedge clk);
    if(page_valid[0])consume_page(0,i);else consume_page(1,i);
    page_count=page_count+1;
   end
  end
  while(!pp_done)@(posedge clk);
  cyc_end=total_cycles;
  if(pp_error)begin $display("PP ERROR");pass=0;end
  if(prefetch_count!=NDESC||consume_count!=NDESC)begin $display("PP COUNT p=%0d c=%0d",prefetch_count,consume_count);pass=0;end
  $display("PP_RESULT prefetch=%0d cycles=%0d fill_cycles=%0d overlap=%0d stall=%0d prefetch_n=%0d consume_n=%0d dma_rbeats=%0d pass=%0d",
   prefetch,cyc_end-cyc_start,fill_cycles,overlap_cycles,stall_cycles,prefetch_count,consume_count,read_beats,pass);
  if(!pass)$fatal(1,"PP mismatch");
  $finish;
 end
endmodule
