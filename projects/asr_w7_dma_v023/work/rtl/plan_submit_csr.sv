`timescale 1ns/1ps
// PS: plan pointer/count/START, then completion/error only. Sticky DONE/IRQ.
// AXI-Lite AW and W are independent; replies hold under backpressure.
module plan_submit_csr(
 input wire clk,rst_n,
 input wire [23:0] s_axi_awaddr,input wire s_axi_awvalid,output wire s_axi_awready,
 input wire [31:0] s_axi_wdata,input wire [3:0] s_axi_wstrb,input wire s_axi_wvalid,output wire s_axi_wready,
 output reg [1:0] s_axi_bresp,output reg s_axi_bvalid,input wire s_axi_bready,
 input wire [23:0] s_axi_araddr,input wire s_axi_arvalid,output wire s_axi_arready,
 output reg [31:0] s_axi_rdata,output reg [1:0] s_axi_rresp,output reg s_axi_rvalid,input wire s_axi_rready,
 output reg start,output reg [31:0] plan_base,plan_count,
 input wire parameter_ready,input wire [31:0] generation,param_end,
 input wire busy,done,fault,input wire [7:0] error_code,
 input wire [31:0] completed,index,rejected_starts,last_ticket,
 input wire [63:0] cycles,fetch_cycles,operator_cycles,
 input wire matrix_done,input wire [63:0] matrix_cycles,matrix_pe_cycles,
 input wire vector_done,layout_done,input wire [7:0] vector_numeric_flags,vector_error_code,layout_error_code,
 input wire [63:0] vector_cycles,layout_cycles,vector_read_compute_overlap,vector_write_compute_overlap,
 input wire [31:0] vector_read_bytes,vector_write_bytes,layout_read_bytes,layout_write_bytes,
 input wire [31:0] vector_completed_elements,layout_processed_elements,layout_cache_hits,layout_cache_misses,
 output wire irq
);
 reg awfull,wfull,done_latched;reg [23:0] aw;reg [31:0] wd,snapshot_high;reg [3:0] ws;
 reg [63:0] vector_total,layout_total,read_overlap_total,write_overlap_total;
 reg [31:0] vector_read_begin,vector_write_begin,layout_read_begin,layout_write_begin;
 reg [31:0] vector_elements_total,layout_elements_total,hits_total,misses_total;
 reg [7:0] flags_total;
 reg previous_matrix_done;reg [63:0] matrix_total,matrix_pe_total;
 assign s_axi_awready=rst_n&&!awfull&&!s_axi_bvalid;
 assign s_axi_wready=rst_n&&!wfull&&!s_axi_bvalid;
 assign s_axi_arready=rst_n&&!s_axi_rvalid;
 assign irq=done_latched;
 always @(posedge clk)begin
  if(!rst_n)begin
   awfull<=0;wfull<=0;aw<=0;wd<=0;ws<=0;s_axi_bresp<=0;s_axi_bvalid<=0;
   s_axi_rdata<=0;s_axi_rresp<=0;s_axi_rvalid<=0;start<=0;plan_base<=0;plan_count<=0;done_latched<=0;snapshot_high<=0;
   vector_total<=0;layout_total<=0;read_overlap_total<=0;write_overlap_total<=0;
   vector_read_begin<=0;vector_write_begin<=0;layout_read_begin<=0;layout_write_begin<=0;
   vector_elements_total<=0;layout_elements_total<=0;hits_total<=0;misses_total<=0;flags_total<=0;
   previous_matrix_done<=0;matrix_total<=0;matrix_pe_total<=0;
  end else begin
   start<=0;
   previous_matrix_done<=matrix_done;
   if(busy&&matrix_done&&!previous_matrix_done)begin
    matrix_total<=matrix_total+matrix_cycles;matrix_pe_total<=matrix_pe_total+matrix_pe_cycles;
   end
   if(done)done_latched<=1;
   if(vector_done)begin
    vector_total<=vector_total+vector_cycles;
    read_overlap_total<=read_overlap_total+vector_read_compute_overlap;
    write_overlap_total<=write_overlap_total+vector_write_compute_overlap;
    vector_elements_total<=vector_elements_total+vector_completed_elements;
    flags_total<=flags_total|vector_numeric_flags;
   end
   if(layout_done)begin
    layout_total<=layout_total+layout_cycles;
    layout_elements_total<=layout_elements_total+layout_processed_elements;
    hits_total<=hits_total+layout_cache_hits;misses_total<=misses_total+layout_cache_misses;
   end
   if(s_axi_awvalid&&s_axi_awready)begin awfull<=1;aw<=s_axi_awaddr;end
   if(s_axi_wvalid&&s_axi_wready)begin wfull<=1;wd<=s_axi_wdata;ws<=s_axi_wstrb;end
   if(s_axi_bvalid&&s_axi_bready)s_axi_bvalid<=0;
   if(s_axi_rvalid&&s_axi_rready)s_axi_rvalid<=0;
   if(awfull&&wfull&&!s_axi_bvalid)begin
    awfull<=0;wfull<=0;s_axi_bvalid<=1;s_axi_bresp<=0;
    if(ws!=15||busy||start||aw[1:0]!=0||aw[23:8]!=0)s_axi_bresp<=2;
    else case(aw[7:0])
     8:plan_base<=wd;
     12:plan_count<=wd;
     16:if(wd==1&&parameter_ready)begin
      start<=1;done_latched<=0;vector_total<=0;layout_total<=0;read_overlap_total<=0;write_overlap_total<=0;
      vector_read_begin<=vector_read_bytes;vector_write_begin<=vector_write_bytes;
      layout_read_begin<=layout_read_bytes;layout_write_begin<=layout_write_bytes;
      vector_elements_total<=0;layout_elements_total<=0;hits_total<=0;misses_total<=0;flags_total<=0;
      matrix_total<=0;matrix_pe_total<=0;
     end else s_axi_bresp<=2;
     default:s_axi_bresp<=2;
    endcase
   end
   if(s_axi_arvalid&&s_axi_arready)begin
    s_axi_rvalid<=1;s_axi_rdata<=0;s_axi_rresp<=0;
    if(s_axi_araddr[23:8]!=0||s_axi_araddr[1:0]!=0)s_axi_rresp<=2;
    else case(s_axi_araddr[7:0])
     0:s_axi_rdata<=32'hA51A22D0;
     4:s_axi_rdata<={29'd0,fault,done_latched,busy};
     8:s_axi_rdata<=plan_base;12:s_axi_rdata<=plan_count;
     20:s_axi_rdata<=completed;24:s_axi_rdata<=index;28:s_axi_rdata<={24'd0,error_code};
     32:begin s_axi_rdata<=cycles[31:0];snapshot_high<=cycles[63:32];end
     36:s_axi_rdata<=snapshot_high;
     40:s_axi_rdata<=last_ticket;44:s_axi_rdata<=rejected_starts;
     48:begin s_axi_rdata<=fetch_cycles[31:0];snapshot_high<=fetch_cycles[63:32];end
     52:s_axi_rdata<=snapshot_high;
     56:begin s_axi_rdata<=operator_cycles[31:0];snapshot_high<=operator_cycles[63:32];end
     60:s_axi_rdata<=snapshot_high;
     64:begin s_axi_rdata<=vector_total[31:0];snapshot_high<=vector_total[63:32];end
     68:s_axi_rdata<=snapshot_high;
     72:begin s_axi_rdata<=layout_total[31:0];snapshot_high<=layout_total[63:32];end
     76:s_axi_rdata<=snapshot_high;
     80:s_axi_rdata<=vector_read_bytes-vector_read_begin;
     84:s_axi_rdata<=vector_write_bytes-vector_write_begin;
     88:s_axi_rdata<=layout_read_bytes-layout_read_begin;
     92:s_axi_rdata<=layout_write_bytes-layout_write_begin;
     96:begin s_axi_rdata<=read_overlap_total[31:0];snapshot_high<=read_overlap_total[63:32];end
     100:s_axi_rdata<=snapshot_high;
     104:begin s_axi_rdata<=write_overlap_total[31:0];snapshot_high<=write_overlap_total[63:32];end
     108:s_axi_rdata<=snapshot_high;
     112:s_axi_rdata<=vector_elements_total;116:s_axi_rdata<=layout_elements_total;
     120:s_axi_rdata<={24'd0,flags_total};124:s_axi_rdata<={16'd0,layout_error_code,vector_error_code};
     128:s_axi_rdata<=hits_total;132:s_axi_rdata<=misses_total;
     144:s_axi_rdata<={31'd0,parameter_ready};148:s_axi_rdata<=generation;
     152:s_axi_rdata<=param_end;156:s_axi_rdata<=32'h10102201;
     160:begin s_axi_rdata<=matrix_total[31:0];snapshot_high<=matrix_total[63:32];end
     164:s_axi_rdata<=snapshot_high;
     168:begin s_axi_rdata<=matrix_pe_total[31:0];snapshot_high<=matrix_pe_total[63:32];end
     172:s_axi_rdata<=snapshot_high;
     default:s_axi_rresp<=2;
    endcase
   end
  end
 end
endmodule
