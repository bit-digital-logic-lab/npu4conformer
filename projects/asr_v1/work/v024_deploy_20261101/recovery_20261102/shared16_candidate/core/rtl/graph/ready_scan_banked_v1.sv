`timescale 1ns/1ps
// Banked / pipelined ready-mask scanner for up to 128 plan nodes.
//
// Replaces a single 128-node priority chain in the controller SCAN state with
// four registered 32-node bank scans:
//   B0 -> B1 -> B2 -> B3 -> PICK -> OUT
// Each bank evaluates (pending & (dep_mask & ~done_mask)==0 & engine_free).
// PICK selects the lowest-index ready bank, not merely the first found.
//
// pending/done_mask/engine_free are snapshotted at scan_start; dep_mask_flat is
// the immutable node descriptor and is not re-latched.  done_mask is
// monotonically growing in the controller, so a node that was ready in the
// snapshot remains ready; a node whose last predecessor completes during the
// scan is picked by the next scan.  This avoids a mid-scan mask change
// producing an inconsistent choice.  The output additionally rechecks the live
// pending bit and engine availability before cand_valid; the caller must still
// accept the candidate with scan_ack.
//
// Latency: 6 cycles from scan_start to cand_valid/scan_done (4 banks + pick +
// output register); throughput is one scan per 6 cycles in this simple form.
module ready_scan_banked_v1 #(
 parameter integer MAX_NODES=128,
 parameter integer BANK_NODES=32,
 parameter integer BANKS=4
)(
 input wire clk,rst_n,
 input wire scan_start,
 input wire scan_ack,
 input wire [MAX_NODES-1:0] pending,
 input wire [MAX_NODES*128-1:0] dep_mask_flat,
 input wire [MAX_NODES*3-1:0] node_type_flat,
 input wire [127:0] done_mask,
 input wire [3:0] engine_free,
 output reg cand_valid,
 output reg scan_done,
 output reg [6:0] cand_id,
 output reg [2:0] cand_type,
 output reg [1:0] cand_bank,
 output reg [31:0] scan_cycles,
 output wire scan_busy
);
 localparam IDLE=0,B0=1,B1=2,B2=3,B3=4,PICK=5,OUT=6;
 reg [2:0] state;
 reg [127:0] done_snap;
 reg [MAX_NODES-1:0] pend_snap;
 reg [3:0] eng_snap;
 reg cand_v[0:BANKS-1];
 reg [6:0] cand_i[0:BANKS-1];
 reg [1:0] pick_bank;
 reg picked;
 integer b,n,base;
 reg [6:0] local_i;
 reg found;
 wire [6:0] cand_id_now=cand_id;

 assign scan_busy=state!=IDLE;

 function automatic ready_one;
  input integer idx;
  input [MAX_NODES-1:0] pend;
  input [MAX_NODES*128-1:0] deps;
  input [127:0] done;
  input [3:0] ef;
  input [MAX_NODES*3-1:0] types;
  reg [127:0] dm;
  reg [2:0] ty;
  begin
   dm=deps[idx*128+:128];
   ty=types[idx*3+:3];
   ready_one=pend[idx] && ((dm&~done)==128'd0) &&
     ((ty==3'd1&&ef[1])||(ty==3'd2&&ef[2])||(ty==3'd3&&ef[3])||(ty==3'd4&&ef[0]));
  end
 endfunction

 integer i;
 always @(posedge clk)begin
  if(!rst_n)begin
   state<=IDLE;done_snap<=0;pend_snap<=0;eng_snap<=0;
   for(i=0;i<BANKS;i=i+1)begin cand_v[i]<=0;cand_i[i]<=0;end
   cand_valid<=0;scan_done<=0;cand_id<=0;cand_type<=0;cand_bank<=0;scan_cycles<=0;
   pick_bank<=0;picked<=0;local_i<=0;
  end else begin
   if(state!=OUT)cand_valid<=0;
   scan_done<=0;
   if(state!=IDLE)scan_cycles<=scan_cycles+1;
   case(state)
    IDLE:if(scan_start)begin
     done_snap<=done_mask;pend_snap<=pending;eng_snap<=engine_free;
     for(i=0;i<BANKS;i=i+1)begin cand_v[i]<=0;cand_i[i]<=0;end
     picked<=0;pick_bank<=0;state<=B0;
    end
    B0,B1,B2,B3:begin
     b=(state==B0)?0:(state==B1)?1:(state==B2)?2:3;
     found=0;local_i=0;
     for(n=0;n<BANK_NODES;n=n+1)begin
      base=b*BANK_NODES;
      if(!found&&(base+n)<MAX_NODES&&
         ready_one(base+n,pend_snap,dep_mask_flat,done_snap,eng_snap,node_type_flat))begin
       found=1;local_i=n[6:0];
      end
     end
     cand_v[b]<=found;
     cand_i[b]<=(b*BANK_NODES)+local_i;
     state<=(state==B0)?B1:(state==B1)?B2:(state==B2)?B3:PICK;
    end
    PICK:begin
     picked=0;pick_bank=0;
     for(b=0;b<BANKS;b=b+1)begin
      if(!picked&&cand_v[b])begin picked=1;pick_bank=b[1:0];end
     end
     if(!picked)begin
      scan_done<=1;state<=IDLE;
     end else begin
      cand_id<=cand_i[pick_bank];
      cand_type<=node_type_flat[cand_i[pick_bank]*3+:3];
      cand_bank<=pick_bank;
      // Live checks: the caller may have dispatched another node during scan.
      cand_valid<=pending[cand_i[pick_bank]]&&
        ((node_type_flat[cand_i[pick_bank]*3+:3]==3'd1&&engine_free[1])||
         (node_type_flat[cand_i[pick_bank]*3+:3]==3'd2&&engine_free[2])||
         (node_type_flat[cand_i[pick_bank]*3+:3]==3'd3&&engine_free[3])||
         (node_type_flat[cand_i[pick_bank]*3+:3]==3'd4&&engine_free[0]));
      state<=OUT;
     end
    end
    OUT:begin
     if(scan_ack)begin cand_valid<=0;state<=IDLE;end
     else if(!pending[cand_id_now])begin cand_valid<=0;state<=IDLE;end
    end
    default:state<=IDLE;
   endcase
  end
 end
endmodule
