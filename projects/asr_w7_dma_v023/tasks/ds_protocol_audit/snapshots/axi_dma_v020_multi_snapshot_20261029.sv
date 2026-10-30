`timescale 1ns/1ps
// V020 候选：多 outstanding + 读数据 FIFO + posted write，保留 V019 的
// 16beat/4KiB 切分、每笔顺序和错误后已接受事务排空语义。
//
// 读：最多 MAX_OUT 个 AR 在途；R 数据先入 FIFO，消费者可慢于存储器。
// 写：在 B 信用允许时提前发下一笔 AW，B 可多笔在途；W 数据仍严格按序。
// MAX_OUT 必须为 2 的幂。该模块不改变上游每 C 的 K 累加顺序；上游按
// read_index 递增消费即可保持原顺序。
module axi_dma_v020_multi #(
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
 output wire m_axi_wlast,m_axi_wvalid,input wire m_axi_wready,
 input wire [1:0] m_axi_bresp,input wire m_axi_bvalid,output wire m_axi_bready
);
 localparam integer FW=$clog2(FIFO_BEATS);
 localparam integer TW=$clog2(MAX_OUT);
 localparam S_IDLE=0,S_RUN=1,S_FIN=2;
 reg [1:0] state;
 reg is_write;
 reg [31:0] next_addr;
 reg [15:0] remaining,beats,index;
 reg rd_active;
 reg [7:0] rd_idx;
 reg [31:0] ar_out,b_out;
 reg [31:0] dbg_aw,dbg_b;
 reg err_sticky;

 // 读数据 FIFO
 reg [127:0] fifo[0:FIFO_BEATS-1];
 reg [FW:0] fifo_wr,fifo_rd,fifo_cnt;
 wire [FW:0] fifo_free=FIFO_BEATS-fifo_cnt;
 wire fifo_empty=(fifo_cnt==0);

 // AR tag FIFO：每笔在途 AR 的 beat 数；R 严格按序返回
 reg [7:0] tag[0:MAX_OUT-1];
 reg [TW:0] tag_wr,tag_rd_tag,tag_cnt;

 wire [8:0] page_beats=(13'd4096-{1'b0,next_addr[11:0]})>>4;
 wire [4:0] limit=remaining>MAX_BURST?MAX_BURST[4:0]:remaining[4:0];
 wire [4:0] chosen=page_beats<limit?page_beats[4:0]:limit;
 wire [4:0] wchosen=chosen;
 wire can_ar=(state==S_RUN)&&!is_write&&rd_active&&(remaining!=0)&&(tag_cnt<MAX_OUT)&&
             (fifo_free>=chosen)&&!err_sticky;
 wire can_aw=(state==S_RUN)&&is_write&&(remaining!=0)&&(beats==0)&&(b_out<MAX_OUT)&&!err_sticky;

 assign request_ready=(state==S_IDLE)&&rst_n;
 assign m_axi_araddr={8'd0,next_addr};
 assign m_axi_arlen=chosen-1;
 assign m_axi_arsize=3'd4;assign m_axi_arburst=2'd1;assign m_axi_arcache=4'd0;assign m_axi_arprot=3'd0;
 assign m_axi_arvalid=can_ar;
 assign m_axi_rready=(state==S_RUN)&&!is_write&&(tag_cnt!=0)&&(fifo_cnt!=FIFO_BEATS);
 assign read_valid=!fifo_empty;
 assign read_data=fifo[fifo_rd[FW-1:0]];
 assign m_axi_awaddr={8'd0,next_addr};
 assign m_axi_awlen=wchosen-1;
 assign m_axi_awsize=3'd4;assign m_axi_awburst=2'd1;assign m_axi_awcache=4'd0;assign m_axi_awprot=3'd0;
 assign m_axi_awvalid=can_aw;
 assign m_axi_wdata=write_data;assign m_axi_wstrb=write_strobe;
 assign m_axi_wlast=(beats!=0)&&(index+1==beats);
 assign m_axi_wvalid=(state==S_RUN)&&is_write&&(beats!=0)&&(index<beats)&&write_valid;
 assign write_ready=(state==S_RUN)&&is_write&&(beats!=0)&&m_axi_wready;
 assign m_axi_bready=1'b1;

 wire [7:0] cur_tag=tag[tag_rd_tag[TW-1:0]];
 wire r_hs=m_axi_rvalid&&m_axi_rready;
 wire w_hs=m_axi_wvalid&&m_axi_wready;
 wire ar_hs=m_axi_arvalid&&m_axi_arready;
 wire aw_hs=m_axi_awvalid&&m_axi_awready;
 wire rd_push=r_hs;
 wire rd_pop=read_valid&&read_ready;

 always @(posedge clk)begin
  if(!rst_n)begin
   state<=S_IDLE;is_write<=0;next_addr<=0;remaining<=0;beats<=0;index<=0;
   rd_active<=0;rd_idx<=0;ar_out<=0;b_out<=0;err_sticky<=0;
   fifo_wr<=0;fifo_rd<=0;fifo_cnt<=0;tag_wr<=0;tag_rd_tag<=0;tag_cnt<=0;
   read_index<=0;write_index<=0;done<=0;error<=0;read_bytes<=0;write_bytes<=0;
   read_bursts<=0;write_bursts<=0;ar_outstanding_max<=0;b_outstanding_max<=0;
   read_bubble_cycles<=0;write_bubble_cycles<=0;read_fifo_high<=0;dbg_aw<=0;dbg_b<=0;
  end else begin
   done<=0;
   // ---------- 请求接收 ----------
   if(state==S_IDLE&&request_valid)begin
    error<=0;err_sticky<=0;next_addr<=request_address;remaining<=request_beats;
    is_write<=request_write;read_index<=0;write_index<=0;
    ar_out<=0;b_out<=0;rd_active<=0;rd_idx<=0;tag_cnt<=0;tag_wr<=0;tag_rd_tag<=0;
    fifo_wr<=0;fifo_rd<=0;fifo_cnt<=0;beats<=0;index<=0;
    if(request_address[3:0]!=0||request_beats==0)begin
     error<=1;state<=S_FIN;
    end else begin
     state<=S_RUN;
     if(!request_write)rd_active<=1;
    end
   end
   // ---------- 读路径 ----------
   if(state==S_RUN&&!is_write)begin
    if(ar_hs)begin
     tag[tag_wr[TW-1:0]]<=chosen;
     tag_wr<=tag_wr+1;
     read_bursts<=read_bursts+1;
     next_addr<=next_addr+({27'd0,chosen}<<4);
     remaining<=remaining-chosen;
     if(ar_out+1>ar_outstanding_max)ar_outstanding_max<=ar_out+1;
    end
    if(r_hs)begin
     fifo[fifo_wr[FW-1:0]]<=m_axi_rdata;
     fifo_wr<=fifo_wr+1;
     read_bytes<=read_bytes+16;
     if(m_axi_rresp!=0)begin err_sticky<=1;error<=1;end
     if(m_axi_rlast!=(rd_idx+1==cur_tag))begin err_sticky<=1;error<=1;end
     if(m_axi_rlast)rd_idx<=0;else rd_idx<=rd_idx+1;
     if(fifo_cnt+1>read_fifo_high)read_fifo_high<=fifo_cnt+1;
    end
    tag_cnt<=tag_cnt+(ar_hs?1:0)-((r_hs&&m_axi_rlast)?1:0);
    ar_out<=ar_out+(ar_hs?1:0)-((r_hs&&m_axi_rlast)?1:0);
    if(r_hs&&m_axi_rlast)tag_rd_tag<=tag_rd_tag+1;
    if(rd_pop)begin fifo_rd<=fifo_rd+1;read_index<=read_index+1;end
    fifo_cnt<=fifo_cnt+(rd_push?1:0)-(rd_pop?1:0);
    // 错误后不再发新 AR；已接受的 tag 继续排空
    if(err_sticky)remaining<=0;
    if(remaining==0&&tag_cnt==0&&fifo_empty&&!rd_push)begin
     state<=S_FIN;rd_active<=0;
    end
    if(rd_active&&!m_axi_arvalid&&!r_hs&&remaining!=0)read_bubble_cycles<=read_bubble_cycles+1;
   end
   // ---------- 写路径 ----------
   if(state==S_RUN&&is_write)begin
    if(aw_hs)begin
     beats<=wchosen;index<=0;write_bursts<=write_bursts+1;
    end
    if(w_hs)begin
     write_bytes<=write_bytes+16;write_index<=write_index+1;index<=index+1;
     if(index+1==beats)begin
      if(!err_sticky)begin
       next_addr<=next_addr+({27'd0,beats}<<4);
       remaining<=remaining-beats;
      end
      beats<=0;
     end
    end
    b_out<=b_out+(aw_hs?1:0)-(m_axi_bvalid?1:0);
    if(aw_hs)dbg_aw<=dbg_aw+1;
    if(m_axi_bvalid)dbg_b<=dbg_b+1;
    if(m_axi_bvalid&&m_axi_bresp!=0)begin err_sticky<=1;error<=1;end
    if(b_out+(aw_hs?1:0)>b_outstanding_max)b_outstanding_max<=b_out+(aw_hs?1:0);
    if(err_sticky)remaining<=0;
    if((remaining==0)&&(beats==0)&&
       ((b_out+(aw_hs?1:0)-(m_axi_bvalid?1:0))==0))state<=S_FIN;
    if(!m_axi_awvalid&&!w_hs&&!m_axi_bvalid&&remaining!=0)write_bubble_cycles<=write_bubble_cycles+1;
   end
   // ---------- 完成 ----------
   if(state==S_FIN)begin
    done<=1;state<=S_IDLE;
    if(err_sticky)error<=1;
   end
  end
 end
endmodule
