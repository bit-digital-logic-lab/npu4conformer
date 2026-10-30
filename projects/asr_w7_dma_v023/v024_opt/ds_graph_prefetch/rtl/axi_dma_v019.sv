`timescale 1ns/1ps
// Single-outstanding AXI128 DMA with <=16beat bursts and 4KiB splitting.
// Errors are reported after draining accepted transactions, never cancelled.
module axi_dma_v019(
 input wire clk,rst_n,
 input wire request_valid,output wire request_ready,input wire request_write,
 input wire [31:0] request_address,input wire [15:0] request_beats,
 output wire read_valid,input wire read_ready,output wire [127:0] read_data,
 output reg [15:0] read_index,
 input wire write_valid,output wire write_ready,input wire [127:0] write_data,
 input wire [15:0] write_strobe,output reg [15:0] write_index,
 output reg done,error,
 output reg [31:0] read_bytes,write_bytes,read_bursts,write_bursts,
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
 localparam IDLE=0,AR=1,RDATA=2,AW=3,WDATA=4,BRESP=5,FINISH=6;
 reg [2:0] state;
 reg [31:0] address;reg [15:0] remaining;reg [4:0] beats,index;
 wire [8:0] page_beats=(13'd4096-{1'b0,address[11:0]})>>4;
 wire [4:0] limit=remaining>16?5'd16:remaining[4:0];
 wire [4:0] chosen=page_beats<limit?page_beats[4:0]:limit;
 assign request_ready=state==IDLE&&rst_n;
 assign m_axi_araddr={8'd0,address};assign m_axi_arlen=chosen-1;
 assign m_axi_arsize=4;assign m_axi_arburst=1;assign m_axi_arcache=0;assign m_axi_arprot=0;
 assign m_axi_arvalid=state==AR;
 assign read_valid=state==RDATA&&m_axi_rvalid;
 assign read_data=m_axi_rdata;assign m_axi_rready=state==RDATA&&read_ready;
 assign m_axi_awaddr={8'd0,address};assign m_axi_awlen=chosen-1;
 assign m_axi_awsize=4;assign m_axi_awburst=1;assign m_axi_awcache=0;assign m_axi_awprot=0;
 assign m_axi_awvalid=state==AW;
 assign m_axi_wdata=write_data;assign m_axi_wstrb=write_strobe;
 assign m_axi_wlast=index+1==beats;
 assign m_axi_wvalid=state==WDATA&&write_valid;assign write_ready=state==WDATA&&m_axi_wready;
 assign m_axi_bready=state==BRESP;
 function automatic [4:0] pop16(input [15:0] bits);
  integer i;begin pop16=0;for(i=0;i<16;i=i+1)pop16=pop16+bits[i];end
 endfunction
 always @(posedge clk)begin
  if(!rst_n)begin
   state<=IDLE;address<=0;remaining<=0;beats<=0;index<=0;read_index<=0;write_index<=0;
   done<=0;error<=0;read_bytes<=0;write_bytes<=0;read_bursts<=0;write_bursts<=0;
  end else begin
   done<=0;
   case(state)
    IDLE:if(request_valid)begin
     error<=0;address<=request_address;remaining<=request_beats;read_index<=0;write_index<=0;
     if(request_address[3:0]!=0||request_beats==0)begin error<=1;state<=FINISH;end
     else state<=request_write?AW:AR;
    end
    AR:if(m_axi_arready)begin beats<=chosen;index<=0;read_bursts<=read_bursts+1;state<=RDATA;end
    RDATA:if(m_axi_rvalid&&read_ready)begin
     read_index<=read_index+1;read_bytes<=read_bytes+16;index<=index+1;
     if(m_axi_rresp!=0 || m_axi_rlast!=(index+1==beats))error<=1;
     if(m_axi_rlast)begin
      if(error||m_axi_rresp!=0||index+1!=beats||remaining==beats)state<=FINISH;
      else begin remaining<=remaining-beats;address<=address+({27'd0,beats}<<4);state<=AR;end
     end
    end
    AW:if(m_axi_awready)begin beats<=chosen;index<=0;write_bursts<=write_bursts+1;state<=WDATA;end
    WDATA:if(write_valid&&m_axi_wready)begin
     write_index<=write_index+1;write_bytes<=write_bytes+pop16(write_strobe);index<=index+1;
     if(index+1==beats)state<=BRESP;
    end
    BRESP:if(m_axi_bvalid)begin
     if(m_axi_bresp!=0)error<=1;
     if(m_axi_bresp!=0||remaining==beats)state<=FINISH;
     else begin remaining<=remaining-beats;address<=address+({27'd0,beats}<<4);state<=AW;end
    end
    FINISH:begin done<=1;state<=IDLE;end
   endcase
  end
 end
endmodule
