`timescale 1ns/1ps
// 真实 A/W ping-pong 预取候选（逻辑层）：
// - 描述符队列 -> 一个多 outstanding 读 DMA -> 两个页缓冲
// - 当前页被消费者占用时，后台把下一页写入空闲页
// - 无空闲页时停止发新描述符（缓冲信用），不会覆盖正在消费的页
// - 页面数据按 read_index 顺序写入，保持原 K 顺序
module ab_pingpong_prefetch #(
 parameter integer PAGE_BEATS=64,
 parameter integer PAGE_AW=6,
 parameter integer DESC_DEPTH=8
)(
 input wire clk,rst_n,start,
 input wire desc_valid,output wire desc_ready,
 input wire [31:0] desc_addr,input wire [15:0] desc_beats,
 input wire [7:0] desc_tag,input wire desc_last,
 output wire dma_req_valid,input wire dma_req_ready,
 output wire [31:0] dma_req_addr,output wire [15:0] dma_req_beats,
 input wire dma_read_valid,output wire dma_read_ready,
 input wire [127:0] dma_read_data,input wire [15:0] dma_read_index,
 input wire dma_done,dma_error,
 input wire [1:0] consume_bank,input wire consume_done,
 input wire [PAGE_AW-1:0] consume_addr,output wire [127:0] consume_data,
 output wire [1:0] page_valid,page_busy,
 output reg done,error,
 output reg [31:0] prefetch_count,consume_count,overlap_cycles,stall_cycles,fill_cycles
);
 localparam IDLE=0,ISSUE=1,FILL=2;
 reg [1:0] state;
 reg target;
 reg [127:0] page[0:1][0:PAGE_BEATS-1];
 reg [1:0] pvalid,pbusy;
 reg [15:0] fill_idx,fill_beats;
 reg [31:0] fill_addr;
 reg [7:0] fill_tag;
 reg last_loaded,last_consumed;reg last_bank;
 // 描述符 FIFO
 reg [31:0] q_addr[0:DESC_DEPTH-1];
 reg [15:0] q_beats[0:DESC_DEPTH-1];
 reg [7:0] q_tag[0:DESC_DEPTH-1];
 reg q_last[0:DESC_DEPTH-1];
 reg [31:0] q_wr,q_rd,q_cnt;
 wire q_empty=(q_cnt==0);
 wire free0=~pvalid[0]&~pbusy[0];
 wire free1=~pvalid[1]&~pbusy[1];
 wire [1:0] free_mask={free1,free0};

 assign desc_ready=(q_cnt<DESC_DEPTH)&&rst_n;
 assign page_valid=pvalid;assign page_busy=pbusy;
 assign consume_data=page[consume_bank[0]][consume_addr];
 assign dma_req_valid=(state==ISSUE);
 assign dma_req_addr=q_addr[q_rd[31:0]%(DESC_DEPTH)];
 assign dma_req_beats=q_beats[q_rd[31:0]%(DESC_DEPTH)];
 assign dma_read_ready=(state==FILL);

 integer bi;
 always @(posedge clk)begin
  if(!rst_n)begin
   state<=IDLE;target<=0;pvalid<=0;pbusy<=0;fill_idx<=0;fill_beats<=0;fill_addr<=0;fill_tag<=0;
   q_wr<=0;q_rd<=0;q_cnt<=0;done<=0;error<=0;
   prefetch_count<=0;consume_count<=0;overlap_cycles<=0;stall_cycles<=0;fill_cycles<=0;
   last_loaded<=0;last_consumed<=0;
  end else begin
   done<=0;
   // 描述符入队
   if(desc_valid&&desc_ready)begin
    q_addr[q_wr[31:0]%(DESC_DEPTH)]<=desc_addr;
    q_beats[q_wr[31:0]%(DESC_DEPTH)]<=desc_beats;
    q_tag[q_wr[31:0]%(DESC_DEPTH)]<=desc_tag;
    q_last[q_wr[31:0]%(DESC_DEPTH)]<=desc_last;
    q_wr<=q_wr+1;
   end
   q_cnt<=q_cnt+(desc_valid&&desc_ready?1:0)-((state==ISSUE&&dma_req_ready)?1:0);
   if(state==ISSUE&&dma_req_ready)begin
    fill_addr<=q_addr[q_rd[31:0]%(DESC_DEPTH)];
    fill_beats<=q_beats[q_rd[31:0]%(DESC_DEPTH)];
    fill_tag<=q_tag[q_rd[31:0]%(DESC_DEPTH)];
    last_loaded<=q_last[q_rd[31:0]%(DESC_DEPTH)];
    if(q_last[q_rd[31:0]%(DESC_DEPTH)])last_bank<=target;
    q_rd<=q_rd+1;
    fill_idx<=0;pbusy[target]<=1;state<=FILL;prefetch_count<=prefetch_count+1;
   end
   // 选择空闲页/发起下一描述符
   if(state==IDLE)begin
    if(!q_empty)begin
     if(free_mask!=0)begin
      target<=free0?1'b0:1'b1;
      state<=ISSUE;
     end else stall_cycles<=stall_cycles+1;
    end
   end
   // 页填充
   if(state==FILL)begin
    fill_cycles<=fill_cycles+1;
    if(dma_read_valid)begin
     if(dma_read_index!=fill_idx||fill_idx>=PAGE_BEATS)begin error<=1;end
     else page[target][fill_idx[PAGE_AW-1:0]]<=dma_read_data;
     fill_idx<=fill_idx+1;
    end
    if(dma_done)begin
     if(dma_error)begin error<=1;pvalid[target]<=0;end
     else begin pvalid[target]<=1;end
     pbusy[target]<=0;
     state<=IDLE;
    end
   end
   // 消费者释放页
   if(consume_done&&pvalid[consume_bank])begin
    pvalid[consume_bank]<=0;consume_count<=consume_count+1;
    if(consume_bank[0]==last_bank)last_consumed<=1;
   end
   // 填充与消费重叠计数
   if(pbusy!=0&&pvalid!=0)overlap_cycles<=overlap_cycles+1;
   // 完成：最后一个描述符已装载且其页已被消费
   if(last_loaded&&last_consumed&&pvalid==0&&pbusy==0&&q_empty&&state==IDLE)done<=1;
  end
 end
endmodule
