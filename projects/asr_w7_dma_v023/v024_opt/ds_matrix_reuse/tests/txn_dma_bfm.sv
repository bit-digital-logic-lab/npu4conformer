`timescale 1ns/1ps
// Transactional DMA BFM for the storage/engine contract.
// Independent read and write ports, deterministic pseudo-random stalls, byte
// strobes, multiple posted write responses, and an optional shared 1-beat/cycle
// bandwidth limit so read+write cannot exceed one physical 128b beat/cycle.
module txn_dma_bfm #(
 parameter [31:0] BASE=32'h03000000,
 parameter integer MEM_WORDS=768,          // 128b words = 2 MiB
 parameter integer SEED=1,
 parameter integer RD_LAT=3,
 parameter integer RD_GAP=0,
 parameter integer WR_GAP=0,
 parameter integer B_DELAY=4,
 parameter integer SHARED_BW=0,
 parameter integer MAX_B=8
)(
 input wire inject_rd_error,inject_wr_error,
 input wire clk,rst_n,
 // read transaction port
 input wire rd_req_valid,output reg rd_req_ready,
 input wire [31:0] rd_req_address,input wire [15:0] rd_req_beats,
 output wire rd_valid,input wire rd_ready,output reg [127:0] rd_data,
 output reg [15:0] rd_index,output reg rd_done,rd_error,
 // write transaction port
 input wire wr_req_valid,output reg wr_req_ready,
 input wire [31:0] wr_req_address,input wire [15:0] wr_req_beats,
 input wire wr_valid,output wire wr_ready,input wire [127:0] wr_data,
 input wire [15:0] wr_strobe,output reg wr_done,wr_error,
 // initialization / checking
 input wire init_valid,input wire [31:0] init_addr,input wire [127:0] init_data,
 input wire [31:0] chk_addr,output wire [127:0] chk_data,
 // counters
 output reg [31:0] rd_cmds,wr_cmds,rd_beats_c,wr_beats_c,shared_conflict,
 output reg [31:0] max_b_out,rd_stall_cycles,wr_stall_cycles,
 output wire [31:0] b_outstanding,output wire w_busy
);
 reg [7:0] mem[0:MEM_WORDS*16-1];
 integer seed_arg;
 initial begin seed_arg=SEED; if(!$value$plusargs("seed=%d",seed_arg))seed_arg=SEED; end
 reg [31:0] lfsr;
 reg [31:0] r_addr;reg [15:0] r_beats,r_idx;reg r_active;reg [15:0] r_delay;
 reg [31:0] w_addr;reg [15:0] w_beats,w_idx;reg w_active;reg [15:0] w_delay;
 reg [15:0] b_cnt[0:MAX_B-1];reg b_err[0:MAX_B-1];reg [2:0] b_wr,b_rd;reg [3:0] b_num;reg [31:0] b_out;
 reg rd_err_latch;
 reg bw_owner;
 wire r_want=r_active&&(r_delay==0);
 wire w_want=w_active&&(w_delay==0);
 wire r_grant=r_want&&(SHARED_BW==0||!w_want||bw_owner==0);
 wire w_grant=w_want&&(SHARED_BW==0||!r_want||bw_owner==1);
 wire r_hs=r_grant&&rd_ready;
 wire w_hs=w_grant&&wr_valid;
 wire [31:0] r_off=r_addr-BASE+r_idx*16;
 wire [31:0] w_off=w_addr-BASE+w_idx*16;

 assign rd_valid=r_grant;
 assign wr_ready=w_grant;
 assign chk_data={mem[(chk_addr-BASE)+15],mem[(chk_addr-BASE)+14],mem[(chk_addr-BASE)+13],mem[(chk_addr-BASE)+12],
                  mem[(chk_addr-BASE)+11],mem[(chk_addr-BASE)+10],mem[(chk_addr-BASE)+9],mem[(chk_addr-BASE)+8],
                  mem[(chk_addr-BASE)+7],mem[(chk_addr-BASE)+6],mem[(chk_addr-BASE)+5],mem[(chk_addr-BASE)+4],
                  mem[(chk_addr-BASE)+3],mem[(chk_addr-BASE)+2],mem[(chk_addr-BASE)+1],mem[(chk_addr-BASE)+0]};

 function [31:0] rnd;begin
  lfsr={lfsr[30:0],lfsr[31]^lfsr[21]^lfsr[1]^lfsr[0]};
  rnd=lfsr;
 end endfunction

 always @*begin
  rd_data=0;
  for(integer lane=0;lane<16;lane=lane+1)
   rd_data[lane*8+:8]=(r_off+lane<MEM_WORDS*16)?mem[r_off+lane]:8'h00;
  rd_index=r_idx;
 end

 integer i;
 always @(posedge clk)begin
  if(!rst_n)begin
   lfsr<=seed_arg[31:0]^32'h1a2b3c4d;
   rd_req_ready<=1;rd_done<=0;rd_error<=0;
   wr_req_ready<=1;wr_done<=0;wr_error<=0;
   r_active<=0;r_delay<=0;r_idx<=0;r_beats<=0;r_addr<=0;
   w_active<=0;w_delay<=0;w_idx<=0;w_beats<=0;w_addr<=0;
   b_wr<=0;b_rd<=0;b_num<=0;b_out<=0;bw_owner<=0;rd_err_latch<=0;
   for(i=0;i<MAX_B;i=i+1)b_err[i]<=0;
   rd_cmds<=0;wr_cmds<=0;rd_beats_c<=0;wr_beats_c<=0;shared_conflict<=0;
   max_b_out<=0;rd_stall_cycles<=0;wr_stall_cycles<=0;
   for(i=0;i<MAX_B;i=i+1)b_cnt[i]<=0;
  end else begin
   rd_done<=0;rd_error<=0;wr_done<=0;wr_error<=0;
   // initialization port (one 128b word per cycle)
   if(init_valid)begin
    for(integer lane=0;lane<16;lane=lane+1)
     mem[(init_addr-BASE)+lane]<=init_data[lane*8+:8];
   end

   // ---------------- read ----------------
   if(rd_req_valid&&rd_req_ready)begin
    r_active<=1;r_addr<=rd_req_address;r_beats<=rd_req_beats;r_idx<=0;
    r_delay<=(RD_LAT==0)?0:(rnd()%RD_LAT);
    rd_req_ready<=0;rd_cmds<=rd_cmds+1;rd_err_latch<=inject_rd_error;
   end
   if(r_active)begin
    if(r_delay!=0)begin
     r_delay<=r_delay-1;rd_stall_cycles<=rd_stall_cycles+1;
    end else if(r_hs)begin
     rd_beats_c<=rd_beats_c+1;
     if(r_idx+1==r_beats)begin
      r_active<=0;rd_done<=1;rd_req_ready<=1;rd_error<=rd_err_latch;
     end else begin
      r_idx<=r_idx+1;
      if(RD_GAP!=0)r_delay<=(rnd()%RD_GAP);
     end
    end
   end

   // ---------------- write ----------------
   if(wr_req_valid&&wr_req_ready)begin
    w_active<=1;w_addr<=wr_req_address;w_beats<=wr_req_beats;w_idx<=0;
    w_delay<=(WR_GAP==0)?0:(rnd()%(WR_GAP+1));
    wr_req_ready<=0;wr_cmds<=wr_cmds+1;
   end
   if(w_active)begin
    if(w_delay!=0)begin w_delay<=w_delay-1;wr_stall_cycles<=wr_stall_cycles+1;end
    else if(w_hs)begin
     for(integer lane=0;lane<16;lane=lane+1)
      if(wr_strobe[lane])mem[(w_off+lane)]<=wr_data[lane*8+:8];
     wr_beats_c<=wr_beats_c+1;
     if(w_idx+1==w_beats)begin
      w_active<=0;wr_req_ready<=1;
      if(b_num<MAX_B)begin
       b_cnt[b_wr]<=1+(B_DELAY==0?0:(rnd()%B_DELAY));
       b_err[b_wr]<=inject_wr_error;
       b_wr<=b_wr+1;b_num<=b_num+1;
      end
     end else begin
      w_idx<=w_idx+1;
      if(WR_GAP!=0)w_delay<=(rnd()%WR_GAP);
     end
    end
   end
   // posted B responses in command order
   if(b_num!=0)begin
    if(b_cnt[b_rd]>0)b_cnt[b_rd]<=b_cnt[b_rd]-1;
    else begin wr_done<=1;wr_error<=b_err[b_rd];b_rd<=b_rd+1;b_num<=b_num-1;end
   end
   b_out<=b_num+(w_active?0:0);
   if(b_num>max_b_out)max_b_out<=b_num;
   if(SHARED_BW!=0&&r_want&&w_want)shared_conflict<=shared_conflict+1;
   if(r_hs&&w_hs)bw_owner<=~bw_owner;
   else if(r_hs)bw_owner<=1;
   else if(w_hs)bw_owner<=0;
  end
 end
 assign b_outstanding={28'd0,b_num};
 assign w_busy=w_active;
endmodule
