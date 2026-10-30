`timescale 1ns/1ps
// Independent AXI4 128-bit slave BFM for the integration audit.
// This is NOT derived from any worker TB.  It deliberately models only the
// protocol facts needed to audit tag/abort/drain/tail behaviour:
//   * AR/AW queues allow multiple outstanding transactions;
//   * R returns strictly in AR order (single ID, no RID);
//   * R/W data are held stable while VALID&&!READY;
//   * WSTRB byte writes;
//   * delayed B responses, spurious-B injection;
//   * optional R/AW/W stalls and early/late RLAST injection.
// It is a logic model, not DDR timing/bandwidth.
module axi128_audit_bfm #(
 parameter integer MEM_BYTES = 1<<22,
 parameter integer QDEPTH    = 32,
 parameter integer BASE      = 32'h00000000
)(
 input  wire clk,
 input  wire rst_n,
 // read address channel
 input  wire [39:0] araddr,
 input  wire [7:0]  arlen,
 input  wire [2:0]  arsize,
 input  wire [1:0]  arburst,
 input  wire        arvalid,
 output reg         arready,
 // read data channel
 output wire [127:0] rdata,
 output wire [1:0]   rresp,
 output wire         rlast,
 output reg          rvalid,
 input  wire         rready,
 // write address channel
 input  wire [39:0] awaddr,
 input  wire [7:0]  awlen,
 input  wire [2:0]  awsize,
 input  wire [1:0]  awburst,
 input  wire        awvalid,
 output reg         awready,
 // write data channel
 input  wire [127:0] wdata,
 input  wire [15:0]  wstrb,
 input  wire         wlast,
 input  wire         wvalid,
 output reg          wready,
 // write response channel
 output reg  [1:0]   bresp,
 output reg          bvalid,
 input  wire         bready,
 // controls / telemetry
 input  wire         r_stall,      // hold R valid/data, do not advance
 input  wire         ar_stall,     // hold ARREADY low
 input  wire         aw_stall,
 input  wire         w_stall,
 input  wire [2:0]   r_delay,      // delay before each burst
 input  wire [2:0]   b_delay,      // delay before each B
 input  wire         inject_rresp, // next burst gets SLVERR
 input  wire         inject_bresp,
 input  wire         inject_spurious_b,
 input  wire         rlast_mode,   // 0 normal, 1 early (last-1), 2 late (last+1)
 output reg  [31:0]  ar_bursts,
 output reg  [31:0]  ar_beats,
 output reg  [31:0]  r_beats,
 output reg  [31:0]  aw_bursts,
 output reg  [31:0]  w_beats,
 output reg  [31:0]  w_bytes,
 output reg  [31:0]  b_responses,
 output reg  [31:0]  max_ar_out,
 output reg  [31:0]  max_b_out,
 output reg  [31:0]  protocol_errors,
 // deterministic read/write check port
 input  wire [39:0]  chk_addr,
 output wire [127:0] chk_data
);
 localparam integer AW = (MEM_BYTES>1) ? $clog2(MEM_BYTES) : 1;
 reg [7:0] mem[0:MEM_BYTES-1];

 function automatic [AW-1:0] moff(input [39:0] a);
  begin moff = a[AW-1:0]; end
 endfunction

 // ---------------- read address queue ----------------
 reg [39:0] ar_q_addr[0:QDEPTH-1];
 reg [7:0]  ar_q_len [0:QDEPTH-1];
 reg [31:0] ar_qc;
 integer ar_h, ar_t;
 reg        ar_active;
 reg [39:0] cur_addr;
 reg [7:0]  cur_len, cur_beat;
 reg [2:0]  cur_delay;
 reg [1:0]  cur_resp;

 // ---------------- write address queue ----------------
 reg [39:0] aw_q_addr[0:QDEPTH-1];
 reg [7:0]  aw_q_len [0:QDEPTH-1];
 reg [31:0] aw_qc;
 integer aw_h, aw_t;
 reg        w_active;
 reg [39:0] cur_waddr;
 reg [7:0]  cur_wlen, cur_wbeat;
 reg [2:0]  cur_bdelay;
 reg [1:0]  cur_bresp;

 // ---------------- B queue ----------------
 reg [2:0]  bq_delay[0:QDEPTH-1];
 reg [1:0]  bq_resp [0:QDEPTH-1];
 reg [31:0] bq_c, b_out;
 integer b_h, b_t;

 wire ar_hs = arvalid && arready;
 wire r_hs  = rvalid && rready;
 wire aw_hs = awvalid && awready;
 wire w_hs  = wvalid && wready;
 wire b_hs  = bvalid && bready;

 function automatic [127:0] mem_word(input [39:0] a);
  integer i;
  begin
   for(i=0;i<16;i=i+1) mem_word[i*8+:8] = mem[moff(a)+i];
  end
 endfunction

 assign chk_data = mem_word(chk_addr);
 assign rdata = mem_word(cur_addr + {27'd0,cur_beat,4'd0});
 assign rresp = cur_resp;
 // rlast_mode: 0 normal, 1 early, 2 late
 assign rlast = (rlast_mode==0) ? (cur_beat+1 == cur_len) :
                (rlast_mode==1) ? (cur_beat+2 == cur_len) :
                                  (cur_beat   == cur_len);

 integer mi;
 initial begin
  for(mi=0;mi<MEM_BYTES;mi=mi+1) mem[mi] = mi[7:0];
 end

 // queued write bytes (byte address may cross a 128-bit word; the DMA always
 // issues 16-B aligned beats, so one word per beat is sufficient here).
 wire [AW-1:0] wbase = moff(cur_waddr + {27'd0,cur_wbeat,4'd0});
 wire ar_pop = !ar_active && (ar_qc != 0);
 wire aw_pop = !w_active && (aw_qc != 0);
 wire b_push = w_active && w_hs && (cur_wbeat+1 == cur_wlen);
 wire b_pop  = bvalid && bready && (bq_c != 0);

 always @(posedge clk) begin
  if(!rst_n) begin
   arready<=1; awready<=1; rvalid<=0;
   wready<=0; bvalid<=0; bresp<=0;
   ar_qc<=0; aw_qc<=0; bq_c<=0; b_out<=0;
   ar_h<=0; ar_t<=0; aw_h<=0; aw_t<=0; b_h<=0; b_t<=0;
   ar_active<=0; w_active<=0; cur_beat<=0; cur_wbeat<=0;
   ar_bursts<=0; ar_beats<=0; r_beats<=0; aw_bursts<=0; w_beats<=0;
   w_bytes<=0; b_responses<=0; max_ar_out<=0; max_b_out<=0; protocol_errors<=0;
   for(integer q=0;q<QDEPTH;q=q+1) begin ar_q_addr[q]<=0; ar_q_len[q]<=0; aw_q_addr[q]<=0; aw_q_len[q]<=0; end
  end else begin
   // ---------------- AR ----------------
   arready <= (ar_qc < QDEPTH) && !ar_stall;
   if(ar_hs) begin
    ar_q_addr[ar_t] <= araddr;
    ar_q_len[ar_t]  <= arlen + 8'd1;
    ar_t <= (ar_t + 1) % QDEPTH;
    ar_bursts <= ar_bursts + 1;
    ar_beats <= ar_beats + {24'd0,arlen} + 1;
    if(ar_qc + 1 > max_ar_out) max_ar_out <= ar_qc + 1;
    if(arsize != 3'd4 || arburst != 2'd1) protocol_errors <= protocol_errors + 1;
    if(araddr[3:0] != 0) protocol_errors <= protocol_errors + 1;
   end

   // ---------------- R ----------------
   if(!ar_active) begin
    rvalid <= 0;
    if(ar_qc != 0) begin
     cur_addr <= ar_q_addr[ar_h];
     cur_len  <= ar_q_len[ar_h];
     ar_h <= (ar_h + 1) % QDEPTH;
     cur_beat <= 0;
     cur_delay <= r_delay;
     cur_resp <= inject_rresp ? 2'b10 : 2'b00;
     ar_active <= 1;
    end
   end else begin
    if(cur_delay != 0) begin
     cur_delay <= cur_delay - 1;
    end else begin
     rvalid <= 1;
     if(r_hs && !r_stall) begin
      r_beats <= r_beats + 1;
      if((rlast_mode==0 && cur_beat+1==cur_len) ||
         (rlast_mode==1 && cur_beat+2==cur_len) ||
         (rlast_mode==2 && cur_beat==cur_len)) begin
       ar_active <= 0;
       rvalid <= 0;
      end else begin
       cur_beat <= cur_beat + 1;
      end
     end
    end
   end

   // ---------------- AW ----------------
   awready <= (aw_qc < QDEPTH) && !aw_stall;
   if(aw_hs) begin
    aw_q_addr[aw_t] <= awaddr;
    aw_q_len[aw_t]  <= awlen + 8'd1;
    aw_t <= (aw_t + 1) % QDEPTH;
    aw_bursts <= aw_bursts + 1;
    if(awsize != 3'd4 || awburst != 2'd1) protocol_errors <= protocol_errors + 1;
    if(awaddr[3:0] != 0) protocol_errors <= protocol_errors + 1;
   end

   // ---------------- W ----------------
   if(!w_active) begin
    wready <= 0;
    if(aw_qc != 0) begin
     cur_waddr <= aw_q_addr[aw_h];
     cur_wlen  <= aw_q_len[aw_h];
     aw_h <= (aw_h + 1) % QDEPTH;
     cur_wbeat <= 0;
     w_active <= 1;
    end
   end else begin
    wready <= !w_stall;
    if(w_hs && !w_stall) begin
     for(integer k=0;k<16;k=k+1) if(wstrb[k]) mem[wbase+k] <= wdata[k*8+:8];
     w_beats <= w_beats + 1;
     w_bytes <= w_bytes + ((wstrb[0]?1:0)+(wstrb[1]?1:0)+(wstrb[2]?1:0)+(wstrb[3]?1:0)+
                           (wstrb[4]?1:0)+(wstrb[5]?1:0)+(wstrb[6]?1:0)+(wstrb[7]?1:0)+
                           (wstrb[8]?1:0)+(wstrb[9]?1:0)+(wstrb[10]?1:0)+(wstrb[11]?1:0)+
                           (wstrb[12]?1:0)+(wstrb[13]?1:0)+(wstrb[14]?1:0)+(wstrb[15]?1:0));
     if(cur_wbeat+1 == cur_wlen) begin
      w_active <= 0;
      wready <= 0;
      bq_delay[b_t] <= b_delay;
      bq_resp[b_t]  <= inject_bresp ? 2'b10 : 2'b00;
      b_t <= (b_t + 1) % QDEPTH;
     end else begin
      cur_wbeat <= cur_wbeat + 1;
     end
    end
   end

   // ---------------- B ----------------
   if(inject_spurious_b && !bvalid && bq_c==0 && b_out==0) begin
    bvalid <= 1; bresp <= 2'b10;
   end
   if(bq_c != 0 && !bvalid) begin
    if(bq_delay[b_h]==0) begin
     bvalid <= 1; bresp <= bq_resp[b_h];
     b_h <= (b_h + 1) % QDEPTH;
    end else bq_delay[b_h] <= bq_delay[b_h] - 1;
   end
   if(b_hs) begin
    bvalid <= 0;
    b_responses <= b_responses + 1;
   end
   ar_qc <= ar_qc + (ar_hs?1:0) - (ar_pop?1:0);
   aw_qc <= aw_qc + (aw_hs?1:0) - (aw_pop?1:0);
   bq_c  <= bq_c  + (b_push?1:0) - (b_pop?1:0);
   b_out <= bq_c + (b_push?1:0) - (b_pop?1:0);
   if(bq_c > max_b_out) max_b_out <= bq_c;
  end
 end
endmodule
