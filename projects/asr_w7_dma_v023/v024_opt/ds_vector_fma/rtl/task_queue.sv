`timescale 1ns/1ps
// Coarse task queue. All fetch/execute/retire transitions are autonomous.
// Memory client must report dma_done only after accepted transactions drain.
// An engine error is accepted only with engine_done (its transactions drained).
module task_queue #(
 parameter [15:0] BACKEND=21,
 parameter [31:0] ARENA_BASE=32'h03000000, ARENA_END=32'h08000000,
 parameter integer MAX_TASKS=4096
)(
 input wire clk,rst_n,start,
 input wire [31:0] queue_base,input wire [31:0] queue_count,
 output wire busy,output reg done,fault,output reg [7:0] error_code,
 output reg [31:0] completed_tasks,current_index,rejected_starts,
 output reg [63:0] queue_cycles,fetch_cycles,engine_wait_cycles,retire_wait_cycles,
 output wire dma_request_valid,input wire dma_request_ready,
 output wire [31:0] dma_address,output wire [15:0] dma_beats,
 input wire dma_read_valid,output wire dma_read_ready,
 input wire [15:0] dma_read_index,input wire [127:0] dma_read_data,
 input wire dma_done,dma_error,
 output wire engine_valid,input wire engine_ready,
 output wire [511:0] engine_descriptor,
 input wire engine_done,engine_fault,input wire [7:0] engine_error,
 input wire [63:0] engine_cycles,
 output wire completion_valid,input wire completion_ready,
 output wire [31:0] completion_index,completion_cookie,
 output wire [7:0] completion_error,output wire [63:0] completion_cycles
);
 localparam IDLE=0,FETCH=1,RECEIVE=2,CHECK=3,ISSUE=4,EXECUTE=5,RETIRE=6,STOP=7;
 reg [2:0] state;
 reg [31:0] base,count;
 reg [511:0] descriptor;
 reg [2:0] received;
 reg fetch_bad,retire_fault;
 reg [7:0] retire_error;
 reg [63:0] retired_cycles;
 wire [63:0] queue_end={32'd0,queue_base}+({32'd0,queue_count}<<6);
 assign busy=state!=IDLE&&state!=STOP;
 assign dma_request_valid=state==FETCH;
 assign dma_address=base+(current_index<<6);
 assign dma_beats=4;
 assign dma_read_ready=state==RECEIVE;
 assign engine_valid=state==ISSUE;
 assign engine_descriptor=descriptor;
 assign completion_valid=state==RETIRE;
 assign completion_index=current_index;
 assign completion_cookie=descriptor[95:64];
 assign completion_error=retire_error;
 assign completion_cycles=retired_cycles;
 task fail_queue(input [7:0] code);begin
  fault<=1;done<=1;error_code<=code;state<=STOP;
 end endtask
 always @(posedge clk)begin
  if(!rst_n)begin
   state<=IDLE;base<=0;count<=0;descriptor<=0;received<=0;fetch_bad<=0;
   done<=0;fault<=0;error_code<=0;completed_tasks<=0;current_index<=0;rejected_starts<=0;
   queue_cycles<=0;fetch_cycles<=0;engine_wait_cycles<=0;retire_wait_cycles<=0;
   retire_fault<=0;retire_error<=0;retired_cycles<=0;
  end else begin
   if(busy)begin
    queue_cycles<=queue_cycles+1;
    if(start)rejected_starts<=rejected_starts+1;
    if(state==FETCH||state==RECEIVE)fetch_cycles<=fetch_cycles+1;
    if(state==ISSUE||state==EXECUTE)engine_wait_cycles<=engine_wait_cycles+1;
    if(state==RETIRE)retire_wait_cycles<=retire_wait_cycles+1;
   end
   case(state)
    IDLE,STOP:if(start)begin
     done<=0;fault<=0;error_code<=0;completed_tasks<=0;current_index<=0;
     rejected_starts<=0;queue_cycles<=0;fetch_cycles<=0;engine_wait_cycles<=0;retire_wait_cycles<=0;
     if(queue_base[5:0]!=0||queue_count==0||queue_count>MAX_TASKS||
        queue_base<ARENA_BASE||queue_end>{32'd0,ARENA_END}||
        MAX_TASKS<1||MAX_TASKS>4096||(BACKEND!=19&&BACKEND!=20&&BACKEND!=21))fail_queue(1);
     else begin base<=queue_base;count<=queue_count;state<=FETCH;end
    end
    FETCH:if(dma_request_ready)begin
     descriptor<=0;received<=0;fetch_bad<=0;state<=RECEIVE;
    end
    RECEIVE:begin
     if(dma_read_valid)begin
      if(dma_read_index!=received||received>=4)fetch_bad<=1;
      if(received<4)begin descriptor[received*128+:128]<=dma_read_data;received<=received+1;end
     end
     if(dma_done)begin
      // The final data and done may share a clock; CHECK sees their registered state.
      if(dma_error)fetch_bad<=1;
      state<=CHECK;
     end
    end
    CHECK:begin
     if(fetch_bad||received!=4)fail_queue(2);
     else if(descriptor[31:0]!=32'h51415352||descriptor[47:32]!=16'd1||descriptor[63:48]!=BACKEND)fail_queue(3);
     else if(descriptor[127:96]!=32'hffffffff&&descriptor[127:96]>=current_index)fail_queue(4);
     else state<=ISSUE;
    end
    ISSUE:if(engine_ready)state<=EXECUTE;
    EXECUTE:if(engine_done)begin
     retire_fault<=engine_fault;retire_error<=engine_fault?(engine_error==0?8'h80:engine_error):0;
     retired_cycles<=engine_cycles;state<=RETIRE;
    end
    RETIRE:if(completion_ready)begin
     if(retire_fault)fail_queue(retire_error);
     else begin
      completed_tasks<=completed_tasks+1;
      if(current_index+1==count)begin done<=1;state<=STOP;end
      else begin current_index<=current_index+1;state<=FETCH;end
     end
    end
    default:fail_queue(8'hff);
   endcase
  end
 end
endmodule
