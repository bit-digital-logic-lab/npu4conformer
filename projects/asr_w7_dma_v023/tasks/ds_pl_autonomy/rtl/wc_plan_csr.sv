`timescale 1ns/1ps
// AXI-Lite control/status for wc_superplan_ctrl.  PS writes header base and one
// START, then only reads completion/error.  No per-node or per-matrix MMIO.
module wc_plan_csr #(
 parameter [31:0] VERSION=32'h00010001
)(
 input wire clk,rst_n,
 input wire [23:0] s_axi_awaddr,input wire s_axi_awvalid,output wire s_axi_awready,
 input wire [31:0] s_axi_wdata,input wire [3:0] s_axi_wstrb,input wire s_axi_wvalid,output wire s_axi_wready,
 output reg [1:0] s_axi_bresp,output reg s_axi_bvalid,input wire s_axi_bready,
 input wire [23:0] s_axi_araddr,input wire s_axi_arvalid,output wire s_axi_arready,
 output reg [31:0] s_axi_rdata,output reg [1:0] s_axi_rresp,output reg s_axi_rvalid,input wire s_axi_rready,
 output reg [31:0] plan_base,
 output reg start,
 input wire parameter_ready,
 input wire busy,done,fault,input wire [7:0] error_code,
 input wire [31:0] completed,node_count,last_node,rejected_starts,
 input wire [127:0] done_mask,
 input wire [63:0] cycles,fetch_cycles,operator_cycles,drain_cycles,
 input wire drain_timeout,
 input wire [31:0] generation,param_end,
 output wire irq
);
 reg awfull,wfull;reg [23:0] aw;reg [31:0] wd;reg [3:0] ws;
 reg done_sticky;reg [31:0] snap;
 assign s_axi_awready=rst_n&&!awfull&&!s_axi_bvalid;
 assign s_axi_wready=rst_n&&!wfull&&!s_axi_bvalid;
 assign s_axi_arready=rst_n&&!s_axi_rvalid;
 assign irq=done_sticky;
 always @(posedge clk)begin
  if(!rst_n)begin
   awfull<=0;wfull<=0;aw<=0;wd<=0;ws<=0;s_axi_bresp<=0;s_axi_bvalid<=0;
   s_axi_rdata<=0;s_axi_rresp<=0;s_axi_rvalid<=0;plan_base<=0;start<=0;done_sticky<=0;snap<=0;
  end else begin
   start<=0;
   if(done)done_sticky<=1;
   if(s_axi_awvalid&&s_axi_awready)begin awfull<=1;aw<=s_axi_awaddr;end
   if(s_axi_wvalid&&s_axi_wready)begin wfull<=1;wd<=s_axi_wdata;ws<=s_axi_wstrb;end
   if(s_axi_bvalid&&s_axi_bready)s_axi_bvalid<=0;
   if(s_axi_rvalid&&s_axi_rready)s_axi_rvalid<=0;
   if(awfull&&wfull&&!s_axi_bvalid)begin
    awfull<=0;wfull<=0;s_axi_bvalid<=1;s_axi_bresp<=0;
    if(ws!=15||aw[1:0]!=0||aw[23:8]!=0)s_axi_bresp<=2;
    else case(aw[7:0])
     8:plan_base<=wd;
     16:begin
      if(wd[0]&&!wd[1])begin
       if(!busy&&parameter_ready)begin start<=1;done_sticky<=0;end else s_axi_bresp<=2;
      end else if(wd[1]&&!wd[0])begin done_sticky<=0;s_axi_bresp<=0;end
      else s_axi_bresp<=2;
     end
     default:s_axi_bresp<=2;
    endcase
   end
   if(s_axi_arvalid&&s_axi_arready)begin
    s_axi_rvalid<=1;s_axi_rdata<=0;s_axi_rresp<=0;
    if(s_axi_araddr[23:8]!=0||s_axi_araddr[1:0]!=0)s_axi_rresp<=2;
    else case(s_axi_araddr[7:0])
     0:s_axi_rdata<=32'h57434353;
     4:s_axi_rdata<={29'd0,fault,done_sticky,busy};
     8:s_axi_rdata<=plan_base;
     12:s_axi_rdata<=node_count;
     16:s_axi_rdata<={31'd0,parameter_ready};
     20:s_axi_rdata<=completed;
     24:s_axi_rdata<=last_node;
     28:s_axi_rdata<={24'd0,error_code};
     32:begin s_axi_rdata<=cycles[31:0];snap<=cycles[63:32];end
     36:s_axi_rdata<=snap;
     40:s_axi_rdata<=rejected_starts;
     44:s_axi_rdata<=done_mask[31:0];
     48:s_axi_rdata<=done_mask[63:32];
     52:s_axi_rdata<=done_mask[95:64];
     56:s_axi_rdata<=done_mask[127:96];
     60:s_axi_rdata<=generation;
     64:s_axi_rdata<=param_end;
     68:begin s_axi_rdata<=fetch_cycles[31:0];snap<=fetch_cycles[63:32];end
     72:s_axi_rdata<=snap;
     76:begin s_axi_rdata<=operator_cycles[31:0];snap<=operator_cycles[63:32];end
     80:s_axi_rdata<=snap;
     84:begin s_axi_rdata<=drain_cycles[31:0];snap<=drain_cycles[63:32];end
     88:s_axi_rdata<=snap;
     92:s_axi_rdata<={31'd0,drain_timeout};
     96:s_axi_rdata<=VERSION;
     default:s_axi_rresp<=2;
    endcase
   end
  end
 end
endmodule
