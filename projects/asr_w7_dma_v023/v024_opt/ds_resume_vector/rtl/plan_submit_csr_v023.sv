`timescale 1ns/1ps
// v023 CSR fix (PA-001): every 64-bit counter has an independent high-word
// snapshot bank.  A low-word read samples {high,low} atomically for that
// register; a following high-word read returns that sample even if another
// 64-bit register is read in between.  Software should still read low then
// high; a high-only read samples the current high word if no low was seen.
//
// All other register/START/IRQ semantics are unchanged from plan_submit_csr.
module plan_submit_csr_v023(
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
 // 64-bit register banks, one high snapshot per bank.
 localparam integer NSNAP=9;
 localparam integer S_CYCLES=0,S_FETCH=1,S_OPERATOR=2,S_VECTOR=3,S_LAYOUT=4,
   S_RDOVL=5,S_WROVL=6,S_MATRIX=7,S_MATRIX_PE=8;
 reg awfull,wfull,done_latched;reg [23:0] aw;reg [31:0] wd;reg [3:0] ws;
 reg [31:0] snap_hi[0:NSNAP-1];reg snap_valid[0:NSNAP-1];
 reg [63:0] vector_total,layout_total,read_overlap_total,write_overlap_total;
 reg [31:0] vector_read_begin,vector_write_begin,layout_read_begin,layout_write_begin;
 reg [31:0] vector_elements_total,layout_elements_total,hits_total,misses_total;
 reg [7:0] flags_total;
 reg previous_matrix_done;reg [63:0] matrix_total,matrix_pe_total;
 integer si;
 function [3:0] snap_index(input [7:0] a);
  begin
   case(a)
    8'h20:snap_index=S_CYCLES; 8'h30:snap_index=S_FETCH;
    8'h38:snap_index=S_OPERATOR;8'h40:snap_index=S_VECTOR;
    8'h48:snap_index=S_LAYOUT; 8'h60:snap_index=S_RDOVL;
    8'h68:snap_index=S_WROVL;  8'hA0:snap_index=S_MATRIX;
    8'hA8:snap_index=S_MATRIX_PE;
    default:snap_index=4'hF;
   endcase
  end
 endfunction
 task clear_snapshots;begin
  for(si=0;si<NSNAP;si=si+1)begin snap_hi[si]<=0;snap_valid[si]<=0;end
 end endtask
 assign s_axi_awready=rst_n&&!awfull&&!s_axi_bvalid;
 assign s_axi_wready=rst_n&&!wfull&&!s_axi_bvalid;
 assign s_axi_arready=rst_n&&!s_axi_rvalid;
 assign irq=done_latched;
 always @(posedge clk)begin
  if(!rst_n)begin
   awfull<=0;wfull<=0;aw<=0;wd<=0;ws<=0;s_axi_bresp<=0;s_axi_bvalid<=0;
   s_axi_rdata<=0;s_axi_rresp<=0;s_axi_rvalid<=0;start<=0;plan_base<=0;plan_count<=0;done_latched<=0;
   vector_total<=0;layout_total<=0;read_overlap_total<=0;write_overlap_total<=0;
   vector_read_begin<=0;vector_write_begin<=0;layout_read_begin<=0;layout_write_begin<=0;
   vector_elements_total<=0;layout_elements_total<=0;hits_total<=0;misses_total<=0;flags_total<=0;
   previous_matrix_done<=0;matrix_total<=0;matrix_pe_total<=0;
   clear_snapshots;
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
      clear_snapshots;
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
     32:begin s_axi_rdata<=cycles[31:0];snap_hi[S_CYCLES]<=cycles[63:32];snap_valid[S_CYCLES]<=1;end
     36:begin if(snap_valid[S_CYCLES])s_axi_rdata<=snap_hi[S_CYCLES];else begin s_axi_rdata<=cycles[63:32];snap_hi[S_CYCLES]<=cycles[63:32];snap_valid[S_CYCLES]<=1;end end
     40:s_axi_rdata<=last_ticket;44:s_axi_rdata<=rejected_starts;
     48:begin s_axi_rdata<=fetch_cycles[31:0];snap_hi[S_FETCH]<=fetch_cycles[63:32];snap_valid[S_FETCH]<=1;end
     52:begin if(snap_valid[S_FETCH])s_axi_rdata<=snap_hi[S_FETCH];else begin s_axi_rdata<=fetch_cycles[63:32];snap_hi[S_FETCH]<=fetch_cycles[63:32];snap_valid[S_FETCH]<=1;end end
     56:begin s_axi_rdata<=operator_cycles[31:0];snap_hi[S_OPERATOR]<=operator_cycles[63:32];snap_valid[S_OPERATOR]<=1;end
     60:begin if(snap_valid[S_OPERATOR])s_axi_rdata<=snap_hi[S_OPERATOR];else begin s_axi_rdata<=operator_cycles[63:32];snap_hi[S_OPERATOR]<=operator_cycles[63:32];snap_valid[S_OPERATOR]<=1;end end
     64:begin s_axi_rdata<=vector_total[31:0];snap_hi[S_VECTOR]<=vector_total[63:32];snap_valid[S_VECTOR]<=1;end
     68:begin if(snap_valid[S_VECTOR])s_axi_rdata<=snap_hi[S_VECTOR];else begin s_axi_rdata<=vector_total[63:32];snap_hi[S_VECTOR]<=vector_total[63:32];snap_valid[S_VECTOR]<=1;end end
     72:begin s_axi_rdata<=layout_total[31:0];snap_hi[S_LAYOUT]<=layout_total[63:32];snap_valid[S_LAYOUT]<=1;end
     76:begin if(snap_valid[S_LAYOUT])s_axi_rdata<=snap_hi[S_LAYOUT];else begin s_axi_rdata<=layout_total[63:32];snap_hi[S_LAYOUT]<=layout_total[63:32];snap_valid[S_LAYOUT]<=1;end end
     80:s_axi_rdata<=vector_read_bytes-vector_read_begin;
     84:s_axi_rdata<=vector_write_bytes-vector_write_begin;
     88:s_axi_rdata<=layout_read_bytes-layout_read_begin;
     92:s_axi_rdata<=layout_write_bytes-layout_write_begin;
     96:begin s_axi_rdata<=read_overlap_total[31:0];snap_hi[S_RDOVL]<=read_overlap_total[63:32];snap_valid[S_RDOVL]<=1;end
     100:begin if(snap_valid[S_RDOVL])s_axi_rdata<=snap_hi[S_RDOVL];else begin s_axi_rdata<=read_overlap_total[63:32];snap_hi[S_RDOVL]<=read_overlap_total[63:32];snap_valid[S_RDOVL]<=1;end end
     104:begin s_axi_rdata<=write_overlap_total[31:0];snap_hi[S_WROVL]<=write_overlap_total[63:32];snap_valid[S_WROVL]<=1;end
     108:begin if(snap_valid[S_WROVL])s_axi_rdata<=snap_hi[S_WROVL];else begin s_axi_rdata<=write_overlap_total[63:32];snap_hi[S_WROVL]<=write_overlap_total[63:32];snap_valid[S_WROVL]<=1;end end
     112:s_axi_rdata<=vector_elements_total;116:s_axi_rdata<=layout_elements_total;
     120:s_axi_rdata<={24'd0,flags_total};124:s_axi_rdata<={16'd0,layout_error_code,vector_error_code};
     128:s_axi_rdata<=hits_total;132:s_axi_rdata<=misses_total;
     144:s_axi_rdata<={31'd0,parameter_ready};148:s_axi_rdata<=generation;
     152:s_axi_rdata<=param_end;156:s_axi_rdata<=32'h10102201;
     160:begin s_axi_rdata<=matrix_total[31:0];snap_hi[S_MATRIX]<=matrix_total[63:32];snap_valid[S_MATRIX]<=1;end
     164:begin if(snap_valid[S_MATRIX])s_axi_rdata<=snap_hi[S_MATRIX];else begin s_axi_rdata<=matrix_total[63:32];snap_hi[S_MATRIX]<=matrix_total[63:32];snap_valid[S_MATRIX]<=1;end end
     168:begin s_axi_rdata<=matrix_pe_total[31:0];snap_hi[S_MATRIX_PE]<=matrix_pe_total[63:32];snap_valid[S_MATRIX_PE]<=1;end
     172:begin if(snap_valid[S_MATRIX_PE])s_axi_rdata<=snap_hi[S_MATRIX_PE];else begin s_axi_rdata<=matrix_pe_total[63:32];snap_hi[S_MATRIX_PE]<=matrix_pe_total[63:32];snap_valid[S_MATRIX_PE]<=1;end end
     default:s_axi_rresp<=2;
    endcase
   end
  end
 end
endmodule
