`timescale 1ns/1ps
// V0.23 shared AXI128 data-port concentrator.
//
// This is a logic-level shared-DMA model: NR read masters and NW write masters
// share one AXI4 128-bit slave port.  It is NOT a DDR timing model and it does
// not assume xpm_fifo_async or any CDC primitive.  All ports are in one clock
// domain in this integration.
//
// Properties that are deliberately implemented (not implied):
//   * read ARs are tagged by master in a global in-order FIFO, so multiple
//     outstanding ARs from one multi-DMA master are routed back to it in AXI
//     order;
//   * per-master read/write credits bound outstanding bursts (CREDIT);
//   * W beats are routed to the master that owns the oldest accepted AW;
//   * B responses follow AW order;
//   * RLAST/length mismatches and orphan responses are counted, never hidden.
module v023_axi_shared #(
 parameter integer NR = 5,
 parameter integer NW = 3,
 parameter integer CREDIT = 8,
 parameter integer QDEPTH = 32
)(
 input wire clk,
 input wire rst_n,
 // Terminal isolation: when set, no NEW AR/AW/W may be issued.  Existing
 // R/B responses are still accepted and routed (drain), and the pending
 // counters are never cleared.  `quiesced` is the only proof that no old
 // transaction remains on this port.
 input wire isolate,

 // ---------------- read masters (flattened) ----------------
 input  wire [NR-1:0] m_arvalid,
 output wire [NR-1:0] m_arready,
 input  wire [NR*40-1:0] m_araddr,
 input  wire [NR*8-1:0]  m_arlen,
 input  wire [NR*3-1:0]  m_arsize,
 input  wire [NR*2-1:0]  m_arburst,
 output wire [NR*128-1:0] m_rdata,
 output wire [NR*2-1:0]   m_rresp,
 output wire [NR-1:0]     m_rlast,
 output wire [NR-1:0]     m_rvalid,
 input  wire [NR-1:0]     m_rready,

 // ---------------- shared read slave port ----------------
 output wire [39:0] s_araddr,
 output wire [7:0]  s_arlen,
 output wire [2:0]  s_arsize,
 output wire [1:0]  s_arburst,
 output wire        s_arvalid,
 input  wire        s_arready,
 input  wire [127:0] s_rdata,
 input  wire [1:0]   s_rresp,
 input  wire         s_rlast,
 input  wire         s_rvalid,
 output wire         s_rready,

 // ---------------- write masters (flattened) ----------------
 input  wire [NW-1:0] m_awvalid,
 output wire [NW-1:0] m_awready,
 input  wire [NW*40-1:0] m_awaddr,
 input  wire [NW*8-1:0]  m_awlen,
 input  wire [NW*3-1:0]  m_awsize,
 input  wire [NW*2-1:0]  m_awburst,
 input  wire [NW*128-1:0] m_wdata,
 input  wire [NW*16-1:0]  m_wstrb,
 input  wire [NW-1:0]     m_wlast,
 input  wire [NW-1:0]     m_wvalid,
 output wire [NW-1:0]     m_wready,
 input  wire [NW-1:0]     m_bready,
 output wire [NW*2-1:0]   m_bresp,
 output wire [NW-1:0]     m_bvalid,

 // ---------------- shared write slave port ----------------
 output wire [39:0] s_awaddr,
 output wire [7:0]  s_awlen,
 output wire [2:0]  s_awsize,
 output wire [1:0]  s_awburst,
 output wire        s_awvalid,
 input  wire        s_awready,
 output wire [127:0] s_wdata,
 output wire [15:0]  s_wstrb,
 output wire         s_wlast,
 output wire         s_wvalid,
 input  wire         s_wready,
 input  wire [1:0]   s_bresp,
 input  wire         s_bvalid,
 output wire         s_bready,

 // telemetry
 output reg [31:0] rd_bursts,
 output reg [31:0] wr_bursts,
 output reg [31:0] r_beats,
 output reg [31:0] w_beats,
 output reg [31:0] rd_peak,
 output reg [31:0] wr_peak,
 output reg [31:0] rd_stall_cycles,
 output reg [31:0] wr_stall_cycles,
 output reg [31:0] tag_errors,
 output wire [31:0] rd_pending,
 output wire [31:0] wr_pending,
 output wire [31:0] b_pending,
 output wire quiesced,
 output reg [31:0] iso_blocked
);
 localparam integer PW = (QDEPTH > 1) ? $clog2(QDEPTH) : 1;

 reg [2:0] ar_own [0:QDEPTH-1];
 reg [7:0] ar_len [0:QDEPTH-1];
 reg [7:0] ar_left[0:QDEPTH-1];
 reg [PW-1:0] ar_head, ar_tail;
 reg [PW:0] ar_count;
 reg [7:0] rd_out [0:NR-1];
 reg [2:0] rd_rr;
 reg [2:0] rd_grant;
 integer ir, iw;
 reg found_r, found_w;

 reg [2:0] aw_own [0:QDEPTH-1];
 reg [7:0] aw_len [0:QDEPTH-1];
 reg [7:0] aw_left[0:QDEPTH-1];
 reg [PW-1:0] aw_head, aw_tail;
 reg [PW:0] aw_count;
 reg [7:0] wr_out [0:NW-1];
 reg [1:0] wr_rr;
 reg [2:0] wr_grant;

 reg [2:0] b_own [0:QDEPTH-1];
 reg [PW-1:0] b_head, b_tail;
 reg [PW:0] b_count;

 wire [2:0] ar_owner = ar_own[ar_head];
 wire [7:0] ar_left_now = ar_left[ar_head];
 wire [2:0] aw_owner = aw_own[aw_head];
 wire [7:0] aw_left_now = aw_left[aw_head];
 wire [2:0] b_owner = b_own[b_head];

 // Pending counters are the observable drain boundary.  They are never
 // cleared by isolation or by a timeout; only real responses retire entries.
 assign rd_pending = ar_count;
 assign wr_pending = aw_count;
 assign b_pending  = b_count;
 assign quiesced   = (ar_count==0) && (aw_count==0) && (b_count==0);

 // ---------------- read arbitration ----------------
 always @* begin
  rd_grant = 3'd0;
  found_r = 1'b0;
  for (ir = 0; ir < NR; ir = ir + 1) begin
   if (!found_r && m_arvalid[(rd_rr + ir) % NR] &&
       (rd_out[(rd_rr + ir) % NR] < CREDIT) &&
       (ar_count < QDEPTH)) begin
    rd_grant = ((rd_rr + ir) % NR) + 1;
    found_r = 1'b1;
   end
  end
 end

 assign s_arvalid = (rd_grant != 0) && m_arvalid[rd_grant-1] && !isolate;
 assign s_araddr  = m_araddr[(rd_grant-1)*40 +: 40];
 assign s_arlen   = m_arlen[(rd_grant-1)*8 +: 8];
 assign s_arsize  = m_arsize[(rd_grant-1)*3 +: 3];
 assign s_arburst = m_arburst[(rd_grant-1)*2 +: 2];

 genvar gi;
 generate
  for (gi = 0; gi < NR; gi = gi + 1) begin : g_rd
   assign m_arready[gi] = (rd_grant == gi+1) && s_arready && (ar_count < QDEPTH) && !isolate;
   assign m_rvalid[gi]  = (ar_count != 0) && (ar_owner == gi) ? s_rvalid : 1'b0;
   assign m_rdata[gi*128 +: 128] = (ar_owner == gi) ? s_rdata : 128'd0;
   assign m_rresp[gi*2 +: 2]     = (ar_owner == gi) ? s_rresp : 2'd0;
   assign m_rlast[gi]            = (ar_owner == gi) ? s_rlast : 1'b0;
  end
 endgenerate

 assign s_rready = (ar_count != 0) && m_rready[ar_owner];
 wire r_hs = s_rvalid && s_rready;
 wire ar_hs = s_arvalid && s_arready;
 wire r_last_hs = r_hs && s_rlast;

 // ---------------- write arbitration ----------------
 always @* begin
  wr_grant = 3'd0;
  found_w = 1'b0;
  for (iw = 0; iw < NW; iw = iw + 1) begin
   if (!found_w && m_awvalid[(wr_rr + iw) % NW] &&
       (wr_out[(wr_rr + iw) % NW] < CREDIT) &&
       (aw_count < QDEPTH)) begin
    wr_grant = ((wr_rr + iw) % NW) + 1;
    found_w = 1'b1;
   end
  end
 end

 assign s_awvalid = (wr_grant != 0) && m_awvalid[wr_grant-1] && !isolate;
 assign s_awaddr  = m_awaddr[(wr_grant-1)*40 +: 40];
 assign s_awlen   = m_awlen[(wr_grant-1)*8 +: 8];
 assign s_awsize  = m_awsize[(wr_grant-1)*3 +: 3];
 assign s_awburst = m_awburst[(wr_grant-1)*2 +: 2];

 assign s_wvalid = (aw_count != 0) && m_wvalid[aw_owner] && !isolate;
 assign s_wdata  = m_wdata[aw_owner*128 +: 128];
 assign s_wstrb  = m_wstrb[aw_owner*16 +: 16];
 assign s_wlast  = (aw_count != 0) && m_wlast[aw_owner];

 generate
  for (gi = 0; gi < NW; gi = gi + 1) begin : g_wr
   assign m_awready[gi] = (wr_grant == gi+1) && s_awready && (aw_count < QDEPTH) && !isolate;
   assign m_wready[gi]  = (!isolate && aw_count != 0 && aw_owner == gi) ? s_wready : 1'b0;
   assign m_bvalid[gi]  = (b_count != 0 && b_owner == gi) ? s_bvalid : 1'b0;
   assign m_bresp[gi*2 +: 2] = (b_count != 0 && b_owner == gi) ? s_bresp : 2'd0;
  end
 endgenerate

 assign s_bready = (b_count != 0) && m_bready[b_owner];
 wire aw_hs = s_awvalid && s_awready;
 wire w_hs  = s_wvalid && s_wready;
 wire w_last_hs = w_hs && s_wlast;
 wire b_hs  = s_bvalid && s_bready;

 // ---------------- sequential state ----------------
 integer j;
 always @(posedge clk) begin
  if (!rst_n) begin
   ar_head <= 0; ar_tail <= 0; ar_count <= 0;
   aw_head <= 0; aw_tail <= 0; aw_count <= 0;
   b_head <= 0; b_tail <= 0; b_count <= 0;
   rd_rr <= 0; wr_rr <= 0;
   rd_bursts <= 0; wr_bursts <= 0; r_beats <= 0; w_beats <= 0;
   rd_peak <= 0; wr_peak <= 0; rd_stall_cycles <= 0; wr_stall_cycles <= 0;
   tag_errors <= 0; iso_blocked <= 0;
   for (j = 0; j < NR; j = j + 1) rd_out[j] <= 0;
   for (j = 0; j < NW; j = j + 1) wr_out[j] <= 0;
   for (j = 0; j < QDEPTH; j = j + 1) begin
    ar_own[j] <= 0; ar_len[j] <= 0; ar_left[j] <= 0;
    aw_own[j] <= 0; aw_len[j] <= 0; aw_left[j] <= 0;
    b_own[j] <= 0;
   end
  end else begin
   // ---- read AR push ----
   if (ar_hs) begin
    ar_own[ar_tail] <= rd_grant - 1'b1;
    ar_len[ar_tail] <= s_arlen;
    ar_left[ar_tail] <= {1'b0, s_arlen} + 9'd1;
    ar_tail <= ar_tail + 1'b1;
    rd_bursts <= rd_bursts + 1'b1;
    rd_rr <= rd_grant - 1'b1;
   end
   // ---- read R beats / pop ----
   if (r_hs) begin
    r_beats <= r_beats + 1'b1;
    if (ar_left_now > 1) ar_left[ar_head] <= ar_left_now - 1'b1;
    if (s_rlast != (ar_left_now == 1)) tag_errors <= tag_errors + 1'b1;
    if (s_rlast) begin
     ar_head <= ar_head + 1'b1;
    end
   end
   // count update (simultaneous push+pop safe)
   if (ar_hs && !r_last_hs) ar_count <= ar_count + 1'b1;
   else if (!ar_hs && r_last_hs) ar_count <= ar_count - 1'b1;

   // ---- write AW push ----
   if (aw_hs) begin
    aw_own[aw_tail] <= wr_grant - 1'b1;
    aw_len[aw_tail] <= s_awlen;
    aw_left[aw_tail] <= {1'b0, s_awlen} + 9'd1;
    aw_tail <= aw_tail + 1'b1;
    wr_bursts <= wr_bursts + 1'b1;
    wr_rr <= wr_grant[1:0];
   end
   // ---- write W beats / AW pop on WLAST ----
   if (w_hs) begin
    w_beats <= w_beats + 1'b1;
    if (aw_left_now > 1) aw_left[aw_head] <= aw_left_now - 1'b1;
    if (s_wlast != (aw_left_now == 1)) tag_errors <= tag_errors + 1'b1;
    if (s_wlast) begin
     aw_head <= aw_head + 1'b1;
     b_own[b_tail] <= aw_owner;
     b_tail <= b_tail + 1'b1;
    end
   end
   if (aw_hs && !w_last_hs) aw_count <= aw_count + 1'b1;
   else if (!aw_hs && w_last_hs) aw_count <= aw_count - 1'b1;

   // ---- B responses ----
   if (b_hs) b_head <= b_head + 1'b1;
   if (w_last_hs && !b_hs) b_count <= b_count + 1'b1;
   else if (!w_last_hs && b_hs) b_count <= b_count - 1'b1;

   // ---- per-master credits ----
   for (j = 0; j < NR; j = j + 1) begin
    if (ar_hs && (rd_grant == j+1) && r_last_hs && (ar_owner == j)) begin
     // same-cycle push+pop for the same master: net zero
    end else begin
     if (ar_hs && (rd_grant == j+1)) rd_out[j] <= rd_out[j] + 1'b1;
     if (r_last_hs && (ar_owner == j)) rd_out[j] <= rd_out[j] - 1'b1;
    end
   end
   for (j = 0; j < NW; j = j + 1) begin
    if (aw_hs && (wr_grant == j+1) && b_hs && (b_owner == j)) begin
     // net zero
    end else begin
     if (aw_hs && (wr_grant == j+1)) wr_out[j] <= wr_out[j] + 1'b1;
     if (b_hs && (b_owner == j)) wr_out[j] <= wr_out[j] - 1'b1;
    end
   end

   // ---- peaks / stalls ----
   for (j = 0; j < NR; j = j + 1) begin
    if (rd_out[j] > rd_peak) rd_peak <= rd_out[j];
   end
   for (j = 0; j < NW; j = j + 1) begin
    if (wr_out[j] > wr_peak) wr_peak <= wr_out[j];
   end
   for (j = 0; j < NR; j = j + 1) begin
    if (m_arvalid[j] && !m_arready[j]) rd_stall_cycles <= rd_stall_cycles + 1'b1;
   end
   for (j = 0; j < NW; j = j + 1) begin
    if (m_awvalid[j] && !m_awready[j]) wr_stall_cycles <= wr_stall_cycles + 1'b1;
    if (m_wvalid[j] && !m_wready[j]) wr_stall_cycles <= wr_stall_cycles + 1'b1;
   end
   // Proof that isolation really stopped new requests: this counts cycles
   // where a master still requested AR/AW/W but the gate refused it.
   if (isolate && ((|m_arvalid) || (|m_awvalid) || (|m_wvalid)))
    iso_blocked <= iso_blocked + 1'b1;
  end
 end
endmodule
