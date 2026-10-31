`timescale 1ns/1ps
// v023 bounded-error plan executor.
//
// Difference from pl_execution_plan_v022:
//   * FETCH/VFETCH watchdog no longer just writes error_code=09 and keeps
//     waiting forever.  It enters DRAIN, asserts dma_abort (stop new requests;
//     accepted AXI bursts are never cancelled) and waits for dma_done.
//   * WAIT_OP watchdog asserts child_abort and waits for child_done OR the
//     explicit child_drained handshake.
//   * DRAIN has a second deadline.  On expiry the plan reports a fault plus
//     isolation_req and drained=0; it never claims "safe drain" without an
//     observed completion/drain handshake.
//   * A new START is rejected while isolation_req is latched; recovery needs
//     the external reset/firewall action that isolation_req requests.
//
// AXI cancellation is intentionally not implemented.  dma_abort is an
// advisory "stop issuing new bursts" request; dma_done/child_drained are the
// only evidence that accepted work is gone.
module pl_execution_plan_v023 #(
 parameter [31:0] PLAN_BASE=32'h10000000,PLAN_LIMIT=32'h40000000,
 parameter [31:0] ARENA_BASE=32'h03000000,ARENA_LIMIT=32'h08000000,
 parameter [63:0] WATCHDOG=64'd12500000000,
 parameter [63:0] DRAIN_WATCHDOG=64'd250000000
)(input wire clk,rst_n,start,input wire [31:0] plan_base,plan_count,param_end,
 input wire parameter_ready,input wire [31:0] generation,
 output reg busy,done,fault,output reg [7:0] error_code,
 output reg [31:0] completed,index,rejected_starts,last_ticket,
 output reg [63:0] cycles,fetch_cycles,operator_cycles,drain_cycles,
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
 input wire vector_done,vector_fault,
 output wire layout_valid,input wire layout_ready,
 output wire [1023:0] layout_descriptor,input wire layout_done,layout_fault,
 // v023 bounded-drain contract
 output reg child_abort,            // stop accepting new child work
 input wire child_drained,          // child has no accepted AXI work left
 output reg dma_abort,              // advisory: stop issuing new DMA bursts
 output reg drain_timeout,          // second deadline expired
 output reg isolation_req,          // request external AXI firewall/reset
 output reg drained,                // 1 only after observed drain/completion
 output wire unsafe_state,          // mirrored isolation_req
 output wire [3:0] state_code
);
 localparam IDLE=0,PRECHECK=1,REQ=2,FETCH=3,CHECK=4,VREQ=5,VFETCH=6,
  DISPATCH=7,WAIT_OP=8,DRAIN=9,FINISH=10;
 localparam DRAIN_NONE=0,DRAIN_DMA=1,DRAIN_CHILD=2;
 reg [3:0] state;
 reg [31:0] base,count,gen;
 reg [511:0] instruction;reg [1023:0] payload;
 reg [3:0] received;
 reg [63:0] wait_cycles,drain_wait;
 reg fetch_bad;
 reg [1:0] drain_src;
 reg child_active;
 wire [31:0] kind=instruction[63:32],ticket=instruction[95:64],dependency=instruction[127:96];
 wire [31:0] pointer=instruction[159:128],length=instruction[191:160];
 wire [63:0] plan_end={32'd0,base}+({32'd0,count}<<6);
 wire [63:0] payload_end={32'd0,pointer}+length;
 wire bad_start=!parameter_ready||plan_base[5:0]!=0||plan_count==0||plan_count>65535||
  plan_base<PLAN_BASE||({32'd0,plan_base}+({32'd0,plan_count}<<6))>{32'd0,param_end}||param_end>PLAN_LIMIT;
 wire bad_instruction=instruction[31:0]!=32'h22504c4e||!(kind==1||kind==2||kind==3)||ticket==0||
  dependency!=(index==0?32'hffffffff:index-1)||instruction[511:192]!=0||
  (kind==1?(pointer[5:0]!=0||length==0||length>4096||pointer<ARENA_BASE||
   ({32'd0,pointer}+({32'd0,length}<<6))>ARENA_LIMIT):
   ((kind==2?length!=64:length!=128)||pointer[5:0]!=0||pointer<PLAN_BASE||payload_end>param_end));
 assign irq=done;
 assign unsafe_state=isolation_req;
 assign state_code=state;
 assign dma_request_valid=state==REQ||state==VREQ;
 assign dma_address=state==VREQ?pointer:base+(index<<6);
 assign dma_beats=(state==VREQ||state==VFETCH)&&kind==3?8:4;
 assign dma_read_ready=state==FETCH||state==VFETCH||(state==DRAIN&&drain_src==DRAIN_DMA);
 assign matrix_valid=state==DISPATCH&&kind==1&&parameter_ready&&generation==gen;
 assign vector_valid=state==DISPATCH&&kind==2&&parameter_ready&&generation==gen;
 assign matrix_queue_base=pointer;assign matrix_queue_count=length;
 assign vector_descriptor=payload[511:0];
 assign layout_descriptor=payload;
 assign layout_valid=state==DISPATCH&&kind==3&&parameter_ready&&generation==gen;
 // Child activity is needed even when the fault came from the plan side.
 task enter_drain(input [1:0] src,input [7:0] code);begin
  drain_src<=src;drain_wait<=0;fault<=1;error_code<=code;
  if(src==DRAIN_DMA)dma_abort<=1;else dma_abort<=0;
  if(src==DRAIN_CHILD)child_abort<=1;
  state<=DRAIN;
 end endtask
 task finish_fault;begin state<=FINISH;end endtask
 always @(posedge clk)begin
  if(!rst_n)begin
   state<=IDLE;busy<=0;done<=0;fault<=0;error_code<=0;completed<=0;index<=0;
   rejected_starts<=0;last_ticket<=0;cycles<=0;fetch_cycles<=0;operator_cycles<=0;drain_cycles<=0;
   base<=0;count<=0;gen<=0;instruction<=0;payload<=0;received<=0;wait_cycles<=0;fetch_bad<=0;
   child_abort<=0;dma_abort<=0;drain_timeout<=0;isolation_req<=0;drained<=0;drain_wait<=0;
   drain_src<=DRAIN_NONE;child_active<=0;
  end else begin
   done<=0;
   if(start&&(busy||isolation_req))rejected_starts<=rejected_starts+1;
   if(busy)cycles<=cycles+1;
   if(state==FETCH||state==VFETCH)fetch_cycles<=fetch_cycles+1;
   if(state==WAIT_OP)operator_cycles<=operator_cycles+1;
   if(state==DRAIN)drain_cycles<=drain_cycles+1;
   case(state)
    IDLE:if(start)begin
     if(!isolation_req)begin
      busy<=1;fault<=0;error_code<=0;completed<=0;index<=0;last_ticket<=0;
      base<=plan_base;count<=plan_count;gen<=generation;cycles<=0;fetch_cycles<=0;operator_cycles<=0;wait_cycles<=0;
      drain_cycles<=0;drain_timeout<=0;drained<=0;child_abort<=0;dma_abort<=0;child_active<=0;
      drain_src<=DRAIN_NONE;drain_wait<=0;
      if(bad_start)begin fault<=1;error_code<=8'h01;drained<=1;state<=FINISH;end
      else state<=PRECHECK;
     end
    end
    PRECHECK:if(!parameter_ready||generation!=gen||plan_end>param_end)begin
      fault<=1;error_code<=8'h02;drained<=1;state<=FINISH;
     end else state<=REQ;
    REQ,VREQ:begin
     wait_cycles<=wait_cycles+1;
     if(!parameter_ready||generation!=gen)begin
      fault<=1;error_code<=8'h02;drained<=1;state<=FINISH;
     end else if(dma_request_ready)begin
      received<=0;fetch_bad<=0;wait_cycles<=0;
      if(state==REQ)instruction<=0;else payload<=0;
      state<=state==REQ?FETCH:VFETCH;
     end else if(wait_cycles>=WATCHDOG)begin
      // No AXI transaction was accepted (request not ready), so no drain is
      // required; this is a safe bounded fault.
      fault<=1;error_code<=8'h0B;drained<=1;state<=FINISH;
     end
    end
    FETCH,VFETCH:begin
     wait_cycles<=wait_cycles+1;
     if(dma_read_valid)begin
      if(dma_read_index!=received||dma_read_index>=dma_beats)fetch_bad<=1;
      else if(state==FETCH)instruction[dma_read_index*128+:128]<=dma_read_data;
      else payload[dma_read_index*128+:128]<=dma_read_data;
      received<=received+1;
     end
     if(!parameter_ready||generation!=gen)begin
      // Configuration changed after START; the accepted fetch must still
      // drain, but the plan must not continue with a mixed snapshot.
      enter_drain(DRAIN_DMA,8'h02);
     end else if(dma_done)begin
      if(dma_error||fetch_bad||received!=dma_beats||wait_cycles>=WATCHDOG)begin
       fault<=1;
       error_code<=(wait_cycles>=WATCHDOG)?8'h09:8'h03;
       drained<=1;state<=FINISH;
      end else begin
       drained<=0;state<=state==FETCH?CHECK:DISPATCH;
      end
     end else if(wait_cycles>=WATCHDOG)begin
      // AR has been accepted (dma_request_valid && ready happened earlier).
      // Do not cancel it; wait for dma_done under the second deadline.
      enter_drain(DRAIN_DMA,8'h09);
     end
    end
    CHECK:if(bad_instruction)begin fault<=1;error_code<=8'h04;drained<=1;state<=FINISH;end
     else if(!parameter_ready||generation!=gen)begin fault<=1;error_code<=8'h02;drained<=1;state<=FINISH;end
     else if(kind==2||kind==3)state<=VREQ;else state<=DISPATCH;
    DISPATCH:if(!parameter_ready||generation!=gen)begin
      fault<=1;error_code<=8'h02;drained<=1;state<=FINISH;
     end else if((kind==1&&matrix_ready)||(kind==2&&vector_ready)||(kind==3&&layout_ready))begin
      last_ticket<=ticket;wait_cycles<=0;child_active<=1;state<=WAIT_OP;
     end
    WAIT_OP:begin
     wait_cycles<=wait_cycles+1;
     if((kind==1&&matrix_done)||(kind==2&&vector_done)||(kind==3&&layout_done))begin
      child_active<=0;
      if(!parameter_ready||generation!=gen||wait_cycles>=WATCHDOG)begin
       fault<=1;error_code<=8'h09;drained<=1;state<=FINISH;
      end else if((kind==1&&matrix_fault)||(kind==2&&vector_fault)||(kind==3&&layout_fault))begin
       fault<=1;error_code<=8'h05;drained<=1;state<=FINISH;
      end else begin
       completed<=completed+1;
       if(index+1==count)begin drained<=1;state<=FINISH;end
       else begin index<=index+1;state<=PRECHECK;end
      end
     end else if(!parameter_ready||generation!=gen||wait_cycles>=WATCHDOG)begin
      enter_drain(DRAIN_CHILD,(!parameter_ready||generation!=gen)?8'h02:8'h09);
     end
    end
    DRAIN:begin
     drain_wait<=drain_wait+1;
     if(drain_src==DRAIN_DMA)begin
      if(dma_done)begin
       drained<=1;fault<=1;state<=FINISH;
      end else if(drain_wait>=DRAIN_WATCHDOG)begin
       // Bounded fault notification, explicitly NOT a safe drain.
       drain_timeout<=1;isolation_req<=1;drained<=0;fault<=1;error_code<=8'h0A;state<=FINISH;
      end
     end else begin
      if(child_drained||
         ((kind==1&&matrix_done)||(kind==2&&vector_done)||(kind==3&&layout_done)))begin
       child_active<=0;drained<=1;fault<=1;state<=FINISH;
      end else if(drain_wait>=DRAIN_WATCHDOG)begin
       drain_timeout<=1;isolation_req<=1;drained<=0;fault<=1;error_code<=8'h0A;state<=FINISH;
      end
     end
    end
    FINISH:begin busy<=0;done<=1;state<=IDLE;end
    default:begin fault<=1;error_code<=8'hff;drained<=0;state<=FINISH;end
   endcase
  end
 end
endmodule
