// 中文说明：CRC32 UART 数据桥；主机只运输原始字节，HLS 完成整个 head。
module ax7035_top #(parameter CLK_HZ=50_000_000,BAUD=115_200,RX_TIMEOUT_CYCLES=5_000_000)
(input wire sys_clk,sys_rst_n,uart_rxd,output wire uart_txd,output wire [3:0] led);
 (* ASYNC_REG="TRUE" *) reg [1:0] rst_sync=0;
 always @(posedge sys_clk or negedge sys_rst_n)
  if(!sys_rst_n)rst_sync<=0;else rst_sync<={rst_sync[0],1'b1};
 // BRAM 控制仅由同步复位寄存器驱动，避免异步复位直接进入 RAM 控制口。
 reg reset_run=0;
 always @(posedge sys_clk)reset_run<=rst_sync[1];
 wire rst_n=reset_run;
 wire [7:0] rx_data;wire rx_valid,rx_error,tx_busy,tx_done;
 reg tx_start;reg [7:0] tx_data;
 uart_rx #(.CLK_HZ(CLK_HZ),.BAUD(BAUD)) rx(.clk(sys_clk),.rst_n(rst_n),.rxd(uart_rxd),
  .data(rx_data),.valid(rx_valid),.framing_error(rx_error));
 uart_tx #(.CLK_HZ(CLK_HZ),.BAUD(BAUD)) tx(.clk(sys_clk),.rst_n(rst_n),.start(tx_start),
  .data(tx_data),.txd(uart_txd),.busy(tx_busy),.done(tx_done));
 function [31:0] crc_byte(input [31:0] previous,input [7:0] value);
  reg [31:0] v;integer b;begin
   v=previous^value;
   for(b=0;b<8;b=b+1)v=v[0]?(v>>1)^32'hedb88320:v>>1;
   crc_byte=v;
  end
 endfunction
 localparam S1=0,S2=1,META=2,PAYLOAD=3,CRC_RX=4,CHECK=5,RESET_CORE=6,
  FETCH=7,FETCH_WAIT=8,FEED=9,ACK_SEND=10,ACK_WAIT=11,HEAD_SEND=12,HEAD_WAIT=13,
  GET_WORD=14,WORD_SEND=15,WORD_WAIT=16,CRC_SEND=17,CRC_WAIT=18;
 reg [4:0] state;reg [2:0] meta_index;reg [7:0] command,flags;
 reg [15:0] packet_tag,expected_tag,packet_words;
 reg [8:0] write_index,forward_index;reg [1:0] byte_index;
 reg [31:0] assembled,crc_in,crc_received;
 (* ram_style="block" *) reg [31:0] packet_mem[0:511];
 reg [31:0] packet_read;
 always @(posedge sys_clk)packet_read<=packet_mem[forward_index];
 reg [7:0] ack_status;reg ack_final;reg [3:0] ack_index;
 wire [31:0] ack_crc=~crc_byte(crc_byte(crc_byte(32'hffffffff,ack_status),packet_tag[7:0]),packet_tag[15:8]);
 reg header_index;reg [31:0] output_word,result_crc;
 reg [15:0] result_index,result_words;reg [3:0] kernel_hold;reg kernel_start;
 wire kernel_done,kernel_idle,kernel_ready,input_read,output_write;wire [31:0] output_data;
 wire kernel_rst_n=rst_n&&(kernel_hold==0);
 conformer_head core(.ap_clk(sys_clk),.ap_rst_n(kernel_rst_n),.ap_start(kernel_start),
  .ap_done(kernel_done),.ap_idle(kernel_idle),.ap_ready(kernel_ready),
  .in_words_dout(packet_read),.in_words_empty_n(state==FEED),.in_words_read(input_read),
  .out_words_din(output_data),.out_words_full_n(state==GET_WORD),.out_words_write(output_write));
 reg [23:0] idle_count;reg [25:0] heartbeat;reg complete,error_seen;
 assign led=~{error_seen,complete,(state!=S1),heartbeat[25]};
 always @(posedge sys_clk)begin
  if(!rst_n)begin
   state<=S1;meta_index<=0;command<=0;flags<=0;packet_tag<=0;expected_tag<=0;packet_words<=0;
   write_index<=0;forward_index<=0;byte_index<=0;assembled<=0;crc_in<=32'hffffffff;
   crc_received<=0;ack_status<=0;ack_final<=0;ack_index<=0;header_index<=0;
   output_word<=0;result_crc<=32'hffffffff;result_index<=0;result_words<=3;
   kernel_hold<=0;kernel_start<=0;idle_count<=0;heartbeat<=0;complete<=0;error_seen<=0;
   tx_start<=0;tx_data<=0;
  end else begin
   tx_start<=0;heartbeat<=heartbeat+1;
   if(kernel_hold!=0)kernel_hold<=kernel_hold-1;
   if(state>=META&&state<=CRC_RX&&!rx_valid)idle_count<=idle_count+1;else idle_count<=0;
   if(state>=META&&state<=CRC_RX&&(rx_error||(!rx_valid&&idle_count==RX_TIMEOUT_CYCLES-1)))begin
    state<=ACK_SEND;ack_status<=2;ack_final<=0;ack_index<=0;error_seen<=1;idle_count<=0;
   end else case(state)
    S1:if(rx_valid&&rx_data==8'ha5)state<=S2;
    S2:if(rx_valid)begin
     if(rx_data==8'hc3)begin state<=META;meta_index<=0;crc_in<=32'hffffffff;end
     else if(rx_data!=8'ha5)state<=S1;
    end
    META:if(rx_valid)begin
     crc_in<=crc_byte(crc_in,rx_data);
     case(meta_index)
      0:command<=rx_data;1:packet_tag[7:0]<=rx_data;2:packet_tag[15:8]<=rx_data;
      3:packet_words[7:0]<=rx_data;4:packet_words[15:8]<=rx_data;
      5:begin
       flags<=rx_data;byte_index<=0;write_index<=0;
       if(command!=8'h41||packet_words==0||packet_words>512)begin
        ack_status<=3;ack_final<=0;ack_index<=0;state<=ACK_SEND;error_seen<=1;
       end else state<=PAYLOAD;
      end
     endcase
     meta_index<=meta_index+1;
    end
    PAYLOAD:if(rx_valid)begin
     crc_in<=crc_byte(crc_in,rx_data);
     case(byte_index)
      0:assembled[7:0]<=rx_data;1:assembled[15:8]<=rx_data;2:assembled[23:16]<=rx_data;
      3:begin
       packet_mem[write_index]<={rx_data,assembled[23:0]};
       if({7'b0,write_index}+16'd1==packet_words)state<=CRC_RX;
       else write_index<=write_index+1;
      end
     endcase
     byte_index<=byte_index+1;
    end
    CRC_RX:if(rx_valid)begin
     case(byte_index)
      0:crc_received[7:0]<=rx_data;1:crc_received[15:8]<=rx_data;2:crc_received[23:16]<=rx_data;
      3:begin crc_received[31:24]<=rx_data;state<=CHECK;end
     endcase
     byte_index<=byte_index+1;
    end
    CHECK:begin
     ack_index<=0;ack_status<=0;ack_final<=0;
     if(crc_received!=~crc_in)begin state<=ACK_SEND;ack_status<=1;error_seen<=1;end
     else if(packet_tag==expected_tag)begin
      forward_index<=0;ack_final<=flags[0];
      if(packet_tag==0)begin
       kernel_hold<=8;kernel_start<=0;state<=RESET_CORE;complete<=0;error_seen<=0;
      end else state<=FETCH;
     end else if(expected_tag!=0&&packet_tag==expected_tag-1)begin
      // 相同序号重传只确认，不向算法重复提交数据。
      state<=ACK_SEND;
     end else begin state<=ACK_SEND;ack_status<=3;error_seen<=1;end
    end
    RESET_CORE:if(kernel_hold==0)begin kernel_start<=1;state<=FETCH;end
    FETCH:state<=FETCH_WAIT;
    FETCH_WAIT:state<=FEED;
    FEED:if(input_read)begin
     if({7'b0,forward_index}+16'd1==packet_words)begin expected_tag<=expected_tag+1;state<=ACK_SEND;end
     else begin forward_index<=forward_index+1;state<=FETCH;end
    end
    ACK_SEND:if(!tx_busy)begin
     case(ack_index)
      0:tx_data<=8'h5a;1:tx_data<=8'hc4;2:tx_data<=ack_status;
      3:tx_data<=packet_tag[7:0];4:tx_data<=packet_tag[15:8];
      default:tx_data<=ack_crc>>((ack_index-5)*8);
     endcase
     tx_start<=1;state<=ACK_WAIT;
    end
    ACK_WAIT:if(tx_done)begin
     if(ack_index==8)begin
      if(ack_final&&ack_status==0)begin state<=HEAD_SEND;header_index<=0;result_index<=0;result_words<=3;result_crc<=32'hffffffff;end
      else state<=S1;
     end else begin ack_index<=ack_index+1;state<=ACK_SEND;end
    end
    HEAD_SEND:if(!tx_busy)begin tx_data<=header_index?8'hc5:8'h5a;tx_start<=1;state<=HEAD_WAIT;end
    HEAD_WAIT:if(tx_done)begin
     if(header_index)state<=GET_WORD;else begin header_index<=1;state<=HEAD_SEND;end
    end
    GET_WORD:if(output_write)begin
     output_word<=output_data;byte_index<=0;state<=WORD_SEND;
     if(result_index==2)result_words<=output_data[15:0]+3;
    end
    WORD_SEND:if(!tx_busy)begin
     tx_data<=output_word>>(byte_index*8);tx_start<=1;state<=WORD_WAIT;
     result_crc<=crc_byte(result_crc,output_word>>(byte_index*8));
    end
    WORD_WAIT:if(tx_done)begin
     if(byte_index==3)begin
      if(result_index+1==result_words)begin state<=CRC_SEND;byte_index<=0;end
      else begin result_index<=result_index+1;state<=GET_WORD;end
     end else begin byte_index<=byte_index+1;state<=WORD_SEND;end
    end
    CRC_SEND:if(!tx_busy)begin tx_data<=(~result_crc)>>(byte_index*8);tx_start<=1;state<=CRC_WAIT;end
    CRC_WAIT:if(tx_done)begin
     if(byte_index==3)begin complete<=1;state<=S1;expected_tag<=0;kernel_start<=0;end
     else begin byte_index<=byte_index+1;state<=CRC_SEND;end
    end
    default:state<=S1;
   endcase
  end
 end
endmodule
