`timescale 1ns/1ps
// V211 legacy INFO-only facade. ALL neural matrices use the DDR queue core.
// Keep host initialization INFO ABI; explicitly reject 60/61/62/63/65.
module lowbit_cached_engine(input wire clk,rst_n,input wire rx_valid,
 input wire [7:0] rx_data,input wire rx_error,
 output wire tx_valid,input wire tx_ready,output reg [7:0] tx_data,output wire busy);
 localparam IDLE=0,SYNC=1,HEAD=2,DATA=3,C0=4,C1=5,CHECK=6,REPLY=7;
 reg [2:0] state,hi;reg [7:0] op,flags,status,crc_low;
 reg [15:0] seq,length,crc,reply_crc,index,reply_length;
 reg [31:0] watchdog;
 assign busy=state!=IDLE&&state!=SYNC;assign tx_valid=state==REPLY;
 function automatic [15:0] crc_byte(input [15:0] prior,input [7:0] b);
  reg [15:0] c;integer j;begin c=prior^{b,8'd0};for(j=0;j<8;j=j+1)c=c[15]?(c<<1)^16'h1021:c<<1;crc_byte=c;end
 endfunction
 task automatic reply(input [7:0] s,input [15:0] n);
  begin status<=s;reply_length<=n;index<=0;reply_crc<=16'hffff;state<=REPLY;end
 endtask
 always @*begin
  case(index)
   0:tx_data=8'h5a;1:tx_data=8'ha5;2:tx_data=seq[7:0];3:tx_data=seq[15:8];4:tx_data=op;5:tx_data=status;
   6:tx_data=reply_length[7:0];7:tx_data=reply_length[15:8];
   default:begin
    if(index==reply_length+8)tx_data=reply_crc[7:0];
    else if(index==reply_length+9)tx_data=reply_crc[15:8];
    else case(index)
     8:tx_data=8'h32;9:tx_data=8'h07;10:tx_data=8'h1a;11:tx_data=8'ha5;
     12:tx_data=0;13:tx_data=8'h10;14:tx_data=0;15:tx_data=0;
     16:tx_data=0;17:tx_data=1;18:tx_data=0;19:tx_data=0;
     default:tx_data=0;
    endcase
   end
  endcase
 end
 always @(posedge clk)begin
  if(!rst_n)begin state<=IDLE;hi<=0;op<=0;flags<=0;status<=0;crc_low<=0;seq<=0;length<=0;crc<=16'hffff;reply_crc<=16'hffff;index<=0;reply_length<=0;watchdog<=0;end
  else begin
   if(rx_valid||state==IDLE||(tx_valid&&tx_ready))watchdog<=0;else watchdog<=watchdog+1;
   if(rx_error||watchdog>=125000000)state<=IDLE;
   else case(state)
    IDLE:if(rx_valid&&rx_data==8'ha5)state<=SYNC;
    SYNC:if(rx_valid)begin if(rx_data==8'h5a)begin state<=HEAD;hi<=0;crc<=16'hffff;end else state<=IDLE;end
    HEAD:if(rx_valid)begin crc<=crc_byte(crc,rx_data);hi<=hi+1;case(hi)
     0:seq[7:0]<=rx_data;1:seq[15:8]<=rx_data;2:op<=rx_data;3:flags<=rx_data;4:length[7:0]<=rx_data;
     5:begin length[15:8]<=rx_data;index<=0;state<=({rx_data,length[7:0]}==0)?C0:DATA;end
    endcase end
    DATA:if(rx_valid)begin crc<=crc_byte(crc,rx_data);index<=index+1;if(index+1==length)state<=C0;end
    C0:if(rx_valid)begin crc_low<=rx_data;state<=C1;end
    C1:if(rx_valid)begin if({rx_data,crc_low}!=crc)reply(1,0);else state<=CHECK;end
    CHECK:if(flags==0&&op==8'h64&&length==0)reply(0,12);else reply(2,0);
    REPLY:if(tx_ready)begin
     if(index>=2&&index<reply_length+8)reply_crc<=crc_byte(reply_crc,tx_data);
     if(index==reply_length+9)state<=IDLE;else index<=index+1;
    end
    default:state<=IDLE;
   endcase
  end
 end
endmodule
