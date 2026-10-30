`timescale 1ns/1ps
// v023 multi-outstanding AXI128 DMA (matrix/DDR workers).
//
// Same functional shape as axi_dma_v020_multi plus:
//   * PA-003: 40-bit running address (no 4 GiB wrap).
//   * PA-004: write_bytes counts WSTRB popcount.
//   * abort/drained: stop issuing new AR/AW, drain accepted R/B, then finish.
//     Read beats already accepted into the internal FIFO are flushed on abort
//     only after the AXI side has no outstanding tag; this drops on-chip
//     samples, never an AXI response.
//   * b_out cannot underflow on a spurious B; it latches err_sticky instead.
//   * elaboration checks for the v020 parameter hazards.
module axi_dma_v023_multi #(
 parameter integer MAX_OUT=8,
 parameter integer FIFO_BEATS=128,
 parameter integer MAX_BURST=16
)(
 input wire clk,rst_n,
 input wire request_valid,output wire request_ready,input wire request_write,
 input wire [31:0] request_address,input wire [15:0] request_beats,
 output wire read_valid,input wire read_ready,output wire [127:0] read_data,
 output reg [15:0] read_index,
 input wire write_valid,output wire write_ready,input wire [127:0] write_data,
 input wire [15:0] write_strobe,output reg [15:0] write_index,
 output reg done,error,
 output reg [31:0] read_bytes,write_bytes,read_bursts,write_bursts,
 output reg [31:0] ar_outstanding_max,b_outstanding_max,
 output reg [63:0] read_bubble_cycles,write_bubble_cycles,read_fifo_high,
 input wire abort,
 output reg aborted,output reg drained,output reg busy,
 output wire [39:0] m_axi_araddr,output wire [7:0] m_axi_arlen,
 output wire [2:0] m_axi_arsize,output wire [1:0] m_axi_arburst,
 output wire [3:0] m_axi_arcache,output wire [2:0] m_axi_arprot,
 output wire m_axi_arvalid,input wire m_axi_arready,
 input wire [127:0] m_axi_rdata,input wire [1:0] m_axi_rresp,
 input wire m_axi_rlast,m_axi_rvalid,output wire m_axi_rready,
 output wire [39:0] m_axi_awaddr,output wire [7:0] m_axi_awlen,
 output wire [2:0] m_axi_awsize,output wire [1:0] m_axi_awburst,
 output wire [3:0] m_axi_awcache,output wire [2:0] m_axi_awprot,
 output wire m_axi_awvalid,input wire m_axi_awready,
 output wire [127:0] m_axi_wdata,output wire [15:0] m_axi_wstrb,
 output wire m_axi_wlast,output wire m_axi_wvalid,input wire m_axi_wready,
 input wire [1:0] m_axi_bresp,input wire m_axi_bvalid,output wire m_axi_bready
);
 localparam integer FW=$clog2(FIFO_BEATS);
 localparam integer TW=$clog2(MAX_OUT);
 localparam S_IDLE=0,S_RUN=1,S_FIN=2;
 reg [1:0] state;
 reg is_write;
 reg [39:0] next_addr;
 reg [15:0] remaining,beats,index;
 reg rd_active;
 reg [7:0] rd_idx;
 reg [31:0] ar_out,b_out;
 reg err_sticky;

 // read data FIFO
 reg [127:0] fifo[0:FIFO_BEATS-1];
 reg [FW:0] fifo_wr,fifo_rd,fifo_cnt;
 wire [FW:0] fifo_free=FIFO_BEATS-fifo_cnt;
 wire fifo_empty=(fifo_cnt==0);

 // in-flight AR beat-count tags, R returns in order
 reg [7:0] tag[0:MAX_OUT-1];
 reg [TW:0] tag_wr,tag_rd_tag,tag_cnt;

 wire [8:0] page_beats=(13'd4096-{1'b0,next_addr[11:0]})>>4;
 wire [15:0] limit=remaining>MAX_BURST?MAX_BURST[15:0]:remaining;
 wire [15:0] chosen=page_beats<limit?{7'd0,page_beats[8:0]}:limit;
 wire [7:0] chosen8=chosen[7:0];
 wire can_ar=(state==S_RUN)&&!is_write&&rd_active&&(remaining!=0)&&(tag_cnt<MAX_OUT)&&
             (fifo_free>=chosen)&&!err_sticky&&!abort;
 wire can_aw=(state==S_RUN)&&is_write&&(remaining!=0)&&(beats==0)&&(b_out<MAX_OUT)&&!err_sticky&&!abort;

 assign request_ready=(state==S_IDLE)&&rst_n;
 assign busy=state!=S_IDLE;
 assign m_axi_araddr=next_addr;
 assign m_axi_arlen=chosen8-8'd1;
 assign m_axi_arsize=3'd4;assign m_axi_arburst=2'd1;assign m_axi_arcache=4'd0;assign m_axi_arprot=3'd0;
 assign m_axi_arvalid=can_ar;
 assign m_axi_rready=(state==S_RUN)&&!is_write&&(tag_cnt!=0)&&(fifo_cnt!=FIFO_BEATS);
 assign read_valid=!fifo_empty;
 assign read_data=fifo[fifo_rd[FW-1:0]];
 assign m_axi_awaddr=next_addr;
 assign m_axi_awlen=chosen8-8'd1;
 assign m_axi_awsize=3'd4;assign m_axi_awburst=2'd1;assign m_axi_awcache=4'd0;assign m_axi_awprot=3'd0;
 assign m_axi_awvalid=can_aw;
 assign m_axi_wdata=write_data;assign m_axi_wstrb=write_strobe;
 assign m_axi_wlast=(beats!=0)&&(index+1==beats);
 assign m_axi_wvalid=(state==S_RUN)&&is_write&&(beats!=0)&&(index<beats)&&write_valid;
 assign write_ready=(state==S_RUN)&&is_write&&(beats!=0)&&m_axi_wready;
 assign m_axi_bready=1'b1;

 function automatic [4:0] pop16(input [15:0] bits);
  integer i;begin pop16=0;for(i=0;i<16;i=i+1)pop16=pop16+bits[i];end
 endfunction

 wire [7:0] cur_tag=tag[tag_rd_tag[TW-1:0]];
 wire r_hs=m_axi_rvalid&&m_axi_rready;
 wire w_hs=m_axi_wvalid&&m_axi_wready;
 wire ar_hs=m_axi_arvalid&&m_axi_arready;
 wire aw_hs=m_axi_awvalid&&m_axi_awready;
 wire rd_push=r_hs;
 wire rd_pop=read_valid&&read_ready;
 wire [TW:0] tag_cnt_next=tag_cnt+(ar_hs?1'b1:1'b0)-((r_hs&&m_axi_rlast)?1'b1:1'b0);
 wire [31:0] ar_out_next=ar_out+(ar_hs?1'b1:1'b0)-((r_hs&&m_axi_rlast)?1'b1:1'b0);
 wire [31:0] b_out_plus=b_out+(aw_hs?1'b1:1'b0);
 wire b_drop=m_axi_bvalid&&(b_out!=0);
 wire [31:0] b_out_next=b_out_plus-(b_drop?1'b1:1'b0);

 // Elaboration guards (simulation-only, no synthesis claim).
 generate
  if((MAX_OUT&(MAX_OUT-1))!=0) begin : g_bad_max
   initial begin $display("AXI_DMA_V023_MULTI_PARAM_ERROR MAX_OUT not power of two");$finish;end
  end
  if(MAX_BURST>16) begin : g_bad_burst
   initial begin $display("AXI_DMA_V023_MULTI_PARAM_ERROR MAX_BURST>16");$finish;end
  end
  if(FIFO_BEATS<MAX_OUT*MAX_BURST) begin : g_bad_fifo
   initial begin $display("AXI_DMA_V023_MULTI_PARAM_ERROR FIFO too small");$finish;end
  end
 endgenerate

 always @(posedge clk)begin
  if(!rst_n)begin
   state<=S_IDLE;is_write<=0;next_addr<=0;remaining<=0;beats<=0;index<=0;
   rd_active<=0;rd_idx<=0;ar_out<=0;b_out<=0;err_sticky<=0;
   fifo_wr<=0;fifo_rd<=0;fifo_cnt<=0;tag_wr<=0;tag_rd_tag<=0;tag_cnt<=0;
   read_index<=0;write_index<=0;done<=0;error<=0;read_bytes<=0;write_bytes<=0;
   read_bursts<=0;write_bursts<=0;ar_outstanding_max<=0;b_outstanding_max<=0;
   read_bubble_cycles<=0;write_bubble_cycles<=0;read_fifo_high<=0;
   aborted<=0;drained<=0;
  end else begin
   done<=0;
   if(state==S_IDLE&&request_valid)begin
    error<=0;err_sticky<=0;aborted<=0;drained<=0;
    next_addr<={8'd0,request_address};remaining<=request_beats;
    is_write<=request_write;read_index<=0;write_index<=0;
    ar_out<=0;b_out<=0;rd_active<=0;rd_idx<=0;tag_cnt<=0;tag_wr<=0;tag_rd_tag<=0;
    fifo_wr<=0;fifo_rd<=0;fifo_cnt<=0;beats<=0;index<=0;
    if(request_address[3:0]!=0||request_beats==0)begin
     error<=1;drained<=1;state<=S_FIN;
    end else begin
     state<=S_RUN;
     if(!request_write)rd_active<=1;
    end
   end
   // ---------------- read path ----------------
   if(state==S_RUN&&!is_write)begin
    if(ar_hs)begin
     tag[tag_wr[TW-1:0]]<=chosen8;
     tag_wr<=tag_wr+1;
     read_bursts<=read_bursts+1;
     next_addr<=next_addr+({24'd0,chosen}<<4);
     remaining<=remaining-chosen;
     if(ar_out+1>ar_outstanding_max)ar_outstanding_max<=ar_out+1;
    end
    if(r_hs)begin
     fifo[fifo_wr[FW-1:0]]<=m_axi_rdata;
     fifo_wr<=fifo_wr+1;
     read_bytes<=read_bytes+16;
     if(m_axi_rresp!=0)begin err_sticky<=1;error<=1;end
     if(m_axi_rlast!=(rd_idx+1==cur_tag[7:0]))begin err_sticky<=1;error<=1;end
     if(m_axi_rlast)rd_idx<=0;else rd_idx<=rd_idx+1;
     if(fifo_cnt+1>read_fifo_high)read_fifo_high<=fifo_cnt+1;
    end
    tag_cnt<=tag_cnt_next;
    ar_out<=ar_out_next;
    if(r_hs&&m_axi_rlast)tag_rd_tag<=tag_rd_tag+1;
    if(rd_pop)begin fifo_rd<=fifo_rd+1;read_index<=read_index+1;end
    if(abort&&(tag_cnt==0)&&!r_hs)begin
     // All accepted AR bursts have returned.  Drop the on-chip FIFO tail;
     // no AXI response is being cancelled.
     aborted<=1;drained<=1;fifo_cnt<=0;fifo_wr<=0;fifo_rd<=0;state<=S_FIN;
    end else if(err_sticky&&(tag_cnt_next==0))begin
     // Error path: accepted bursts are gone; the consumer cannot be required
     // to drain bytes that will never be used.
     fifo_cnt<=0;fifo_wr<=0;fifo_rd<=0;state<=S_FIN;
    end else begin
     fifo_cnt<=fifo_cnt+(rd_push?1'b1:1'b0)-(rd_pop?1'b1:1'b0);
     if(remaining==0&&tag_cnt_next==0&&fifo_empty&&!rd_push)begin
      state<=S_FIN;rd_active<=0;
     end
    end
    if(rd_active&&!m_axi_arvalid&&!r_hs&&remaining!=0&&!abort)read_bubble_cycles<=read_bubble_cycles+1;
   end
   // ---------------- write path ----------------
   if(state==S_RUN&&is_write)begin
    if(aw_hs)begin
     beats<=chosen;index<=0;write_bursts<=write_bursts+1;
    end
    if(w_hs)begin
     write_bytes<=write_bytes+pop16(write_strobe);write_index<=write_index+1;index<=index+1;
     if(index+1==beats)begin
      if(!err_sticky)begin
       next_addr<=next_addr+({24'd0,beats}<<4);
       remaining<=remaining-beats;
      end
      beats<=0;
     end
    end
    if(b_out==0&&m_axi_bvalid)begin
     // A compliant slave never returns a spurious B; latch it rather than
     // underflowing the credit counter.
     err_sticky<=1;error<=1;
    end
    b_out<=b_out_next;
    if(m_axi_bvalid&&m_axi_bresp!=0)begin err_sticky<=1;error<=1;end
    if(b_out_plus>b_outstanding_max)b_outstanding_max<=b_out_plus;
    if(err_sticky)remaining<=0;
    if(abort)begin remaining<=0;aborted<=1;end
    if(((remaining==0)||abort)&&(beats==0)&&(b_out_next==0))begin
     drained<=1;state<=S_FIN;
    end
    if(!m_axi_awvalid&&!w_hs&&!m_axi_bvalid&&remaining!=0&&!abort)write_bubble_cycles<=write_bubble_cycles+1;
   end
   // ---------------- completion ----------------
   if(state==S_FIN)begin
    done<=1;state<=S_IDLE;
    if(err_sticky)error<=1;
   end
  end
 end
endmodule
