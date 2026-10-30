`timescale 1ns/1ps
// Coarse CPU interface: QUEUE_BASE, QUEUE_COUNT, START. No bank/tile/PE register.
// AW and W may arrive in either order; responses and read data hold under stalls.
module queue_submit_csr_board(
 input wire clk,rst_n,plan_lock,
 output wire [31:0] param_generation_out,
 output wire parameter_ready_out,
 input wire [7:0] s_axi_awaddr,input wire s_axi_awvalid,output wire s_axi_awready,
 input wire [31:0] s_axi_wdata,input wire [3:0] s_axi_wstrb,input wire s_axi_wvalid,output wire s_axi_wready,
 output reg [1:0] s_axi_bresp,output reg s_axi_bvalid,input wire s_axi_bready,
 input wire [7:0] s_axi_araddr,input wire s_axi_arvalid,output wire s_axi_arready,
 output reg [31:0] s_axi_rdata,output reg [1:0] s_axi_rresp,output reg s_axi_rvalid,input wire s_axi_rready,
 output reg start,output reg [31:0] queue_base,queue_count,
 output wire [31:0] param_end,
 input wire busy,done,fault,input wire [7:0] error_code,
 input wire [31:0] completed_tasks,current_index,rejected_starts,
 input wire [63:0] queue_cycles,
 input wire [63:0] total_compute_cycles,fetch_cycles,engine_wait_cycles,retire_wait_cycles,
 input wire [31:0] dma_read_bytes,dma_write_bytes,dma_read_bursts,dma_write_bursts,last_core_compute,last_core_reads,last_core_writes,last_core_hits,last_core_misses,
 input wire completion_valid,output wire completion_ready,
 input wire [31:0] completion_cookie,completion_index,input wire [7:0] completion_error,
 input wire [63:0] completion_cycles,
 output wire irq
);
 reg param_ready,load_mode;reg [31:0] model_lo,model_hi,param_bytes,param_crc,param_generation;
 assign parameter_ready_out=param_ready;assign param_generation_out=param_generation;
 assign param_end=32'h10000000+param_bytes;
 reg awfull,wfull;reg [7:0] aw;reg [31:0] wd;reg [3:0] ws;
 reg [31:0] last_cookie,last_index,read_cycles_high;
 reg [7:0] last_error;reg [63:0] last_cycles;
 assign s_axi_awready=rst_n&&!awfull&&!s_axi_bvalid;
 assign s_axi_wready=rst_n&&!wfull&&!s_axi_bvalid;
 assign s_axi_arready=rst_n&&!s_axi_rvalid;
 assign completion_ready=rst_n;assign irq=done||fault;
 always @(posedge clk)begin
  if(!rst_n)begin
   awfull<=0;wfull<=0;aw<=0;wd<=0;ws<=0;s_axi_bvalid<=0;s_axi_bresp<=0;
   s_axi_rdata<=0;s_axi_rresp<=0;s_axi_rvalid<=0;start<=0;queue_base<=0;queue_count<=0;
   last_cookie<=0;last_index<=0;last_error<=0;last_cycles<=0;read_cycles_high<=0;
   param_ready<=0;load_mode<=0;model_lo<=0;model_hi<=0;param_bytes<=0;param_crc<=0;param_generation<=0;
  end else begin
   start<=0;
   if(s_axi_awvalid&&s_axi_awready)begin aw<=s_axi_awaddr;awfull<=1;end
   if(s_axi_wvalid&&s_axi_wready)begin wd<=s_axi_wdata;ws<=s_axi_wstrb;wfull<=1;end
   if(s_axi_bvalid&&s_axi_bready)s_axi_bvalid<=0;
   if(s_axi_rvalid&&s_axi_rready)s_axi_rvalid<=0;
   if(awfull&&wfull&&!s_axi_bvalid)begin
    awfull<=0;wfull<=0;s_axi_bvalid<=1;s_axi_bresp<=0;
    if(ws!=15||busy||start||plan_lock||aw[1:0]!=0)s_axi_bresp<=2;
    else case(aw)
     8:queue_base<=wd;
     12:queue_count<=wd;
     16:if(wd==1&&param_ready)begin start<=1;last_cookie<=0;last_index<=0;last_error<=0;last_cycles<=0;end else s_axi_bresp<=2;
     144:if(wd==1)begin param_ready<=0;load_mode<=1;model_lo<=0;model_hi<=0;param_bytes<=0;param_crc<=0;end
         else if(wd==2&&load_mode&&param_bytes!=0&&param_bytes<=32'h30000000&&(model_lo!=0||model_hi!=0))begin param_ready<=1;load_mode<=0;param_generation<=param_generation+1;end else s_axi_bresp<=2;
     148:if(load_mode)model_lo<=wd;else s_axi_bresp<=2;
     152:if(load_mode)model_hi<=wd;else s_axi_bresp<=2;
     156:if(load_mode)param_bytes<=wd;else s_axi_bresp<=2;
     160:if(load_mode)param_crc<=wd;else s_axi_bresp<=2;
     default:s_axi_bresp<=2;
    endcase
   end
   if(s_axi_arvalid&&s_axi_arready)begin
    s_axi_rvalid<=1;s_axi_rresp<=0;s_axi_rdata<=0;
    case(s_axi_araddr)
     0:s_axi_rdata<=32'hA51A21C1;
     4:s_axi_rdata<={29'd0,fault,done,busy};
     8:s_axi_rdata<=queue_base;
     12:s_axi_rdata<=queue_count;
     20:s_axi_rdata<=completed_tasks;
     24:s_axi_rdata<=current_index;
     28:s_axi_rdata<={24'd0,error_code};
     32:begin s_axi_rdata<=queue_cycles[31:0];read_cycles_high<=queue_cycles[63:32];end
     36:s_axi_rdata<=read_cycles_high;
     40:s_axi_rdata<=last_cookie;
     44:s_axi_rdata<=last_index;
     48:s_axi_rdata<={24'd0,last_error};
     52:s_axi_rdata<=last_cycles[31:0];
     56:s_axi_rdata<=last_cycles[63:32];
     60:s_axi_rdata<=rejected_starts;
     64:s_axi_rdata<=dma_read_bytes;
     68:s_axi_rdata<=dma_write_bytes;
     72:s_axi_rdata<=dma_read_bursts;
     76:s_axi_rdata<=dma_write_bursts;
     80:s_axi_rdata<=total_compute_cycles[31:0];
     84:s_axi_rdata<=total_compute_cycles[63:32];
     88:s_axi_rdata<=last_core_reads;
     92:s_axi_rdata<=last_core_writes;
     96:s_axi_rdata<=last_core_hits;
     100:s_axi_rdata<=last_core_misses;
     104:s_axi_rdata<=last_core_compute;
     112:s_axi_rdata<=fetch_cycles[31:0];
     116:s_axi_rdata<=fetch_cycles[63:32];
     120:s_axi_rdata<=engine_wait_cycles[31:0];
     124:s_axi_rdata<=engine_wait_cycles[63:32];
     128:s_axi_rdata<=retire_wait_cycles[31:0];
     132:s_axi_rdata<=retire_wait_cycles[63:32];
     136:s_axi_rdata<=32'h10102131;
     144:s_axi_rdata<={30'd0,load_mode,param_ready};
     148:s_axi_rdata<=model_lo;152:s_axi_rdata<=model_hi;156:s_axi_rdata<=param_bytes;160:s_axi_rdata<=param_crc;164:s_axi_rdata<=param_generation;
     default:s_axi_rresp<=2;
    endcase
   end
   if(completion_valid)begin
    last_cookie<=completion_cookie;last_index<=completion_index;last_error<=completion_error;last_cycles<=completion_cycles;
   end
  end
 end
endmodule
