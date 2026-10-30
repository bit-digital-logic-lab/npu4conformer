`timescale 1ns/1ps
// PL 自主图控制骨架：一次 start，PL 自己扫描预提交节点表、检查依赖、
// 依次/按就绪顺序启动子算子，单一 done/fault 出口。节点表读取用
// fetch_* 抽象成“DDR 行读取”；实际可接本任务的多 outstanding DMA。
// 这不是完整 CASE 集成：矩阵/向量/布局子算子用 op_* 握手桩表示。
module pl_graph_runner_v1 #(
 parameter integer MAX_NODES=32,
 parameter [31:0] NODE_MAGIC=32'h47525048 // "GRPH"
)(
 input wire clk,rst_n,start,
 input wire [31:0] node_count,
 output wire fetch_req,output wire [31:0] fetch_addr,
 input wire fetch_ready,input wire [511:0] fetch_data,input wire fetch_valid,
 output reg busy,done,fault,output reg [7:0] error_code,
 output reg [31:0] completed,node_index,
 output reg op_start,output reg [7:0] op_kind,
 output reg [31:0] op_plan_addr,op_plan_count,op_in_addr,op_out_addr,op_bytes,
 input wire op_done,input wire op_fault,
 output wire [MAX_NODES-1:0] done_mask_dbg
);
 localparam IDLE=0,FETCH=1,WAIT=2,CHECK=3,DISPATCH=4,WAITOP=5,FINISH=6,FAIL=7;
 reg [2:0] state;
 reg [31:0] count,scan,done_mask,seen;
 reg [31:0] node_id,dep_mask;
 reg [7:0] kind;
 reg [31:0] plan_addr,plan_count,in_addr,out_addr,bytes;
 assign done_mask_dbg=done_mask;
 assign fetch_req=(state==FETCH);
 assign fetch_addr=32'h04000000+scan*64;
 wire [31:0] w_magic=fetch_data[31:0];
 wire [31:0] w_kind=fetch_data[63:32];
 wire [31:0] w_id=fetch_data[95:64];
 wire [31:0] w_dep=fetch_data[127:96];
 wire [31:0] w_plan=fetch_data[159:128];
 wire [31:0] w_pcnt=fetch_data[191:160];
 wire [31:0] w_in=fetch_data[223:192];
 wire [31:0] w_out=fetch_data[255:224];
 wire [31:0] w_bytes=fetch_data[287:256];

 task fail(input [7:0] code);begin fault<=1;error_code<=code;busy<=0;done<=1;state<=FAIL;end endtask

 always @(posedge clk)begin
  if(!rst_n)begin
   state<=IDLE;busy<=0;done<=0;fault<=0;error_code<=0;completed<=0;node_index<=0;
   op_start<=0;op_kind<=0;op_plan_addr<=0;op_plan_count<=0;op_in_addr<=0;op_out_addr<=0;op_bytes<=0;
   count<=0;scan<=0;done_mask<=0;seen<=0;node_id<=0;dep_mask<=0;kind<=0;
   plan_addr<=0;plan_count<=0;in_addr<=0;out_addr<=0;bytes<=0;
  end else begin
   done<=0;op_start<=0;
   case(state)
    IDLE:if(start)begin
     busy<=1;fault<=0;error_code<=0;completed<=0;node_index<=0;done_mask<=0;seen<=0;
     count<=node_count;scan<=0;
     if(node_count==0||node_count>MAX_NODES||node_count>32)fail(8'h01);
     else state<=FETCH;
    end
    FETCH:if(fetch_ready)state<=WAIT;
    WAIT:if(fetch_valid)begin
     if(w_magic!=NODE_MAGIC||w_kind>32'd2||w_id>=count)fail(8'h02);
     else begin
      node_id<=w_id;dep_mask<=w_dep;kind<=w_kind[7:0];
      plan_addr<=w_plan;plan_count<=w_pcnt;in_addr<=w_in;out_addr<=w_out;bytes<=w_bytes;
      state<=CHECK;
     end
    end
    CHECK:begin
     if(done_mask[node_id])begin
      // 已完成的节点：跳过
      if(seen>=count)fail(8'h03);else begin scan<=(scan+1)%count;state<=FETCH;end
     end else if((dep_mask&~done_mask)!=0)begin
      // 依赖未满足：扫描下一个节点；一轮没有新进展则死锁
      seen<=seen+1;
      if(seen+1>=count)fail(8'h04);
      else begin scan<=(scan+1)%count;state<=FETCH;end
     end else begin
      seen<=0;state<=DISPATCH;
     end
    end
    DISPATCH:begin
     op_start<=1;op_kind<=kind;op_plan_addr<=plan_addr;op_plan_count<=plan_count;
     op_in_addr<=in_addr;op_out_addr<=out_addr;op_bytes<=bytes;node_index<=node_id;
     state<=WAITOP;
    end
    WAITOP:if(op_done)begin
     if(op_fault)fail(8'h05);
     else begin
      done_mask[node_id]<=1;completed<=completed+1;
      if(completed+1==count)state<=FINISH;
      else begin scan<=(node_id+1)%count;seen<=0;state<=FETCH;end
     end
    end
    FINISH:begin busy<=0;done<=1;state<=IDLE;end
    FAIL:begin busy<=0;end
    default:fail(8'hff);
   endcase
  end
 end
endmodule
