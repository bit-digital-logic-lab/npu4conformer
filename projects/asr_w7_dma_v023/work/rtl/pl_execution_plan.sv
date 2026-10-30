`timescale 1ns/1ps
// One PS doorbell executes an immutable DRAM plan. No CPU/network per-node query.
// Fetch and operation acknowledgements are distinct; failures drain before DONE.
module pl_execution_plan #(
 parameter [31:0] PLAN_BASE=32'h10000000,PLAN_LIMIT=32'h40000000,
 parameter [31:0] ARENA_BASE=32'h03000000,ARENA_LIMIT=32'h08000000,
 parameter [63:0] WATCHDOG=64'd12500000000
)(input wire clk,rst_n,start,input wire [31:0] plan_base,plan_count,param_end,
 input wire parameter_ready,input wire [31:0] generation,
 output reg busy,done,fault,output reg [7:0] error_code,
 output reg [31:0] completed,index,rejected_starts,last_ticket,
 output reg [63:0] cycles,fetch_cycles,operator_cycles,
 output wire irq,
 output wire dma_request_valid,input wire dma_request_ready,
 output wire [31:0] dma_address,output wire [15:0] dma_beats,
 input wire dma_read_valid,output wire dma_read_ready,
 input wire [127:0] dma_read_data,input wire [15:0] dma_read_index,
 input wire dma_done,dma_error,
 output wire matrix_valid,input wire matrix_ready,
 output wire [31:0] matrix_queue_base,matrix_queue_count,
 input wire matrix_done,matrix_fault,
 output wire vector_valid,input wire vector_ready,
 output wire [511:0] vector_descriptor,
 input wire vector_done,vector_fault);
 localparam IDLE=0,PRECHECK=1,REQ=2,FETCH=3,CHECK=4,VREQ=5,VFETCH=6,
  DISPATCH=7,WAIT_OP=8,FINISH=9,ERROR_DRAIN=10;
 reg [3:0] state;
 reg [31:0] base,count,gen;
 reg [511:0] instruction,payload;
 reg [2:0] received;
 reg [63:0] wait_cycles;
 reg fetch_bad;
 wire [31:0] kind=instruction[63:32],ticket=instruction[95:64],dependency=instruction[127:96];
 wire [31:0] pointer=instruction[159:128],length=instruction[191:160];
 wire [63:0] plan_end={32'd0,base}+({32'd0,count}<<6);
 wire [63:0] payload_end={32'd0,pointer}+64;
 wire bad_start=!parameter_ready||plan_base[5:0]!=0||plan_count==0||plan_count>65535||
  plan_base<PLAN_BASE||({32'd0,plan_base}+({32'd0,plan_count}<<6))>{32'd0,param_end}||param_end>PLAN_LIMIT;
 wire bad_instruction=instruction[31:0]!=32'h22504c4e||!(kind==1||kind==2)||ticket==0||
  dependency!=(index==0?32'hffffffff:index-1)||instruction[511:192]!=0||
  (kind==1?(pointer[5:0]!=0||length==0||length>4096||pointer<ARENA_BASE||
   ({32'd0,pointer}+({32'd0,length}<<6))>ARENA_LIMIT):
   (length!=64||pointer[5:0]!=0||pointer<PLAN_BASE||payload_end>param_end));
 assign irq=done;
 assign dma_request_valid=state==REQ||state==VREQ;
 assign dma_address=state==VREQ?pointer:base+(index<<6);
 assign dma_beats=4;
 assign dma_read_ready=state==FETCH||state==VFETCH;
 assign matrix_valid=state==DISPATCH&&kind==1&&parameter_ready&&generation==gen;
 assign vector_valid=state==DISPATCH&&kind==2&&parameter_ready&&generation==gen;
 assign matrix_queue_base=pointer;assign matrix_queue_count=length;
 assign vector_descriptor=payload;
 task fail(input [7:0] code);begin fault<=1;error_code<=code;state<=FINISH;end endtask
 always @(posedge clk)begin
  if(!rst_n)begin
   state<=IDLE;busy<=0;done<=0;fault<=0;error_code<=0;completed<=0;index<=0;
   rejected_starts<=0;last_ticket<=0;cycles<=0;fetch_cycles<=0;operator_cycles<=0;
   base<=0;count<=0;gen<=0;instruction<=0;payload<=0;received<=0;wait_cycles<=0;fetch_bad<=0;
  end else begin
   done<=0;if(start&&busy)rejected_starts<=rejected_starts+1;
   if(busy)cycles<=cycles+1;
   if(state==FETCH||state==VFETCH)fetch_cycles<=fetch_cycles+1;
   if(state==WAIT_OP)operator_cycles<=operator_cycles+1;
   case(state)
    IDLE:if(start)begin
     busy<=1;fault<=0;error_code<=0;completed<=0;index<=0;last_ticket<=0;
     base<=plan_base;count<=plan_count;gen<=generation;cycles<=0;fetch_cycles<=0;operator_cycles<=0;
     if(bad_start)fail(8'h01);else state<=PRECHECK;
    end
    PRECHECK:if(!parameter_ready||generation!=gen||plan_end>param_end)fail(8'h02);else state<=REQ;
    REQ,VREQ:if(dma_request_ready)begin
     received<=0;fetch_bad<=0;wait_cycles<=0;
     if(state==REQ)instruction<=0;else payload<=0;
     state<=state==REQ?FETCH:VFETCH;
    end
    FETCH,VFETCH:begin
     wait_cycles<=wait_cycles+1;
     if(dma_read_valid)begin
      if(dma_read_index!=received||dma_read_index>3)fetch_bad<=1;
      else if(state==FETCH)instruction[dma_read_index*128+:128]<=dma_read_data;
      else payload[dma_read_index*128+:128]<=dma_read_data;
      received<=received+1;
     end
     // Never cancel an accepted AXI transfer, including watchdog expiry.
     if(wait_cycles>=WATCHDOG)begin fetch_bad<=1;error_code<=8'h09;end
     if(dma_done)begin
      if(dma_error||fetch_bad||received!=4)fail(error_code == 8'h09 ? 8'h09 : 8'h03);
      else state<=state==FETCH?CHECK:DISPATCH;
     end
    end
    CHECK:if(bad_instruction)fail(8'h04);
     else if(!parameter_ready||generation!=gen)fail(8'h02);
     else if(kind==2)state<=VREQ;else state<=DISPATCH;
    DISPATCH:if(!parameter_ready||generation!=gen)fail(8'h02);
     else if((kind==1&&matrix_ready)||(kind==2&&vector_ready))begin last_ticket<=ticket;wait_cycles<=0;state<=WAIT_OP;end
    WAIT_OP:begin
     wait_cycles<=wait_cycles+1;
     if((kind==1&&matrix_done)||(kind==2&&vector_done))begin
      if(!parameter_ready||generation!=gen||wait_cycles>=WATCHDOG)fail(8'h09);
      else if((kind==1&&matrix_fault)||(kind==2&&vector_fault))fail(8'h05);
      else begin completed<=completed+1;if(index+1==count)state<=FINISH;else begin index<=index+1;state<=PRECHECK;end end
     end
     else if(!parameter_ready||generation!=gen||wait_cycles>=WATCHDOG)begin fault<=1;error_code<=8'h09;state<=ERROR_DRAIN;end
    end
    ERROR_DRAIN:if((kind==1&&matrix_done)||(kind==2&&vector_done))state<=FINISH;
    FINISH:begin busy<=0;done<=1;state<=IDLE;end
    default:fail(8'hff);
   endcase
  end
 end
endmodule
