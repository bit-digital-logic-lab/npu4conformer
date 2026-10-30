`timescale 1ns/1ps
// pl_graph_runner_v1 自检：节点表在本地 64B 行存储，op_* 用桩响应。
// +case=0 正常依赖乱序；+case=1 循环依赖应 fault；+case=2 子算子 fault。
module tb_graph_runner;
 localparam integer BASE=32'h04000000;
 reg clk=0,rst_n=0;always #5 clk=~clk;
 reg start;reg [31:0] node_count;
 wire fetch_req;wire [31:0] fetch_addr;wire fetch_ready=1;
 reg [511:0] fetch_data;reg fetch_valid;
 wire busy,done,fault;wire [7:0] error_code;wire [31:0] completed,node_index;
 wire op_start;wire [7:0] op_kind;wire [31:0] op_plan_addr,op_plan_count,op_in_addr,op_out_addr,op_bytes;
 reg op_done,op_fault;wire [31:0] done_mask_dbg;
 pl_graph_runner_v1 #(.MAX_NODES(32)) dut(
  .clk(clk),.rst_n(rst_n),.start(start),.node_count(node_count),
  .fetch_req(fetch_req),.fetch_addr(fetch_addr),.fetch_ready(fetch_ready),
  .fetch_data(fetch_data),.fetch_valid(fetch_valid),
  .busy(busy),.done(done),.fault(fault),.error_code(error_code),
  .completed(completed),.node_index(node_index),
  .op_start(op_start),.op_kind(op_kind),.op_plan_addr(op_plan_addr),.op_plan_count(op_plan_count),
  .op_in_addr(op_in_addr),.op_out_addr(op_out_addr),.op_bytes(op_bytes),
  .op_done(op_done),.op_fault(op_fault),.done_mask_dbg(done_mask_dbg));
 reg [511:0] mem[0:63];
 integer case_id,i,seqn,errors,tbcyc=0;
 integer expected[0:7];
 always @(posedge clk)begin
  if(fetch_req&&fetch_ready)begin fetch_valid<=1;fetch_data<=mem[(fetch_addr-BASE)>>6];end
  else fetch_valid<=0;
  if(op_start)begin
   $display("OP_START seq=%0d node=%0d kind=%0d plan=%h cnt=%0d",seqn+1,node_index,op_kind,op_plan_addr,op_plan_count);
   if(case_id==0&&seqn<4)begin
    if(node_index!==expected[seqn])begin $display("ORDER MISMATCH got=%0d exp=%0d",node_index,expected[seqn]);errors=errors+1;end
   end
   seqn=seqn+1;
   repeat(30+seqn*3)@(posedge clk);
   op_done<=1;@(posedge clk);op_done<=0;
  end
  if(op_done&&op_fault)op_fault<=0;
  tbcyc<=tbcyc+1;if(tbcyc>20000)$fatal(1,"graph watchdog");
  if(done)begin
   $display("GRAPH_RESULT case=%0d completed=%0d seq=%0d fault=%0d err=%h pass=%0d",case_id,completed,seqn,fault,error_code,
     (case_id==0&&!fault&&completed==4&&seqn==4)?1:(case_id!=0&&fault)?1:0);
   if(case_id==0&&(fault||completed!=4||seqn!=4))$fatal(1,"graph normal failed");
   if(case_id!=0&&!fault)$fatal(1,"graph fault not reported");
   $finish;
  end
 end
 task node(input integer at,input [31:0] id,input [31:0] dep,input [31:0] kind,input [31:0] plan);
  begin
   mem[at]=0;
   mem[at][31:0]=32'h47525048;mem[at][63:32]=kind;mem[at][95:64]=id;mem[at][127:96]=dep;
   mem[at][159:128]=plan;mem[at][191:160]=4;mem[at][223:192]=32'h04001000+id*64;
   mem[at][255:224]=32'h04002000+id*64;mem[at][287:256]=256;
  end
 endtask
 initial begin
  if(!$value$plusargs("case=%d",case_id))case_id=0;
  errors=0;seqn=0;op_done=0;op_fault=0;start=0;node_count=4;
  for(i=0;i<64;i=i+1)mem[i]=0;
  if(case_id==0)begin
   // 正常：0 -> 2,1 -> 3；表顺序 0,3,1,2 测试扫描
   node(0,0,0,0,32'h1000);node(1,3,32'h00000003,2,32'h2000);
   node(2,2,32'h00000001,1,32'h3000);node(3,1,32'h00000001,0,32'h4000);
   expected[0]=0;expected[1]=2;expected[2]=1;expected[3]=3;
  end else if(case_id==1)begin
   // 循环依赖：0 等 1，1 等 0
   node(0,0,32'h00000002,0,32'h1000);node(1,1,32'h00000001,1,32'h2000);
   node(2,2,0,2,32'h3000);node(3,3,0,2,32'h4000);
  end else begin
   node(0,0,0,0,32'h1000);node(1,1,1,1,32'h2000);
   node(2,2,2,2,32'h3000);node(3,3,3,2,32'h4000);
   op_fault=1;
  end
  repeat(6)@(posedge clk);rst_n=1;repeat(3)@(posedge clk);
  start<=1;@(posedge clk);start<=0;
 end
endmodule
