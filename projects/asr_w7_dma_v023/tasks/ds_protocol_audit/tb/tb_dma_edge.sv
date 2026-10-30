`timescale 1ns/1ps
// Independent adversarial AXI4 slave for axi_dma_v019 (READ-ONLY DUT).
// Controls: 4KiB framing, AR/AW/R/W/B stalls, early/late/absent RLAST,
// RRESP/BRESP errors, tail WSTRB, back-to-back requests, 32-bit address wrap.
// Every check is printed; any mismatch increments errors and is fatal at end.
module tb_dma_edge;
 reg clk=0; always #4 clk=~clk;
 integer errors=0; integer trace_w=0; integer trace_b=0;
 integer cyc=0;
 always @(posedge clk) cyc<=cyc+1;

 reg rst_n=0;
 reg req_valid=0; wire req_ready; reg req_write=0;
 reg [31:0] req_addr=0; reg [15:0] req_beats=0;
 wire rd_valid; reg rd_ready=1; wire [127:0] rd_data; wire [15:0] rd_index;
 reg wr_valid=0; wire wr_ready; reg [127:0] wr_data=0; reg [15:0] wr_strobe=0;
 wire [15:0] wr_index;
 reg wr_active=0; integer wr_n=0, wr_beat=0, wr_tail=-1; reg [31:0] wr_base=0;
 // Counter-driven W producer: data/strobe are functions of wr_beat and only
 // change on an accepted handshake, so stalls cannot desynchronise them.
 always @* begin
  wr_valid = wr_active && (wr_beat < wr_n);
  wr_data  = wgen(wr_base,wr_beat);
  if(wr_beat==wr_n-1 && wr_tail>=0) wr_strobe = (16'h0001<<wr_tail)-1;
  else wr_strobe = 16'hffff;
 end
 always @(posedge clk) if(rst_n && wr_active && wr_valid && wr_ready) begin
  if(wr_beat+1==wr_n) wr_active<=0; else wr_beat<=wr_beat+1;
 end
 wire done,error;
 wire [31:0] rd_bytes,wr_bytes,rd_bursts,wr_bursts;
 wire [39:0] araddr; wire [7:0] arlen; wire [2:0] arsize; wire [1:0] arburst;
 wire [3:0] arcache; wire [2:0] arprot; wire arvalid; wire arready;
 wire [127:0] rdata; wire [1:0] rresp; wire rlast,rvalid; wire rready;
 wire [39:0] awaddr; wire [7:0] awlen; wire [2:0] awsize; wire [1:0] awburst;
 wire [3:0] awcache; wire [2:0] awprot; wire awvalid; wire awready;
 wire [127:0] wdata; wire [15:0] wstrb; wire wlast,wvalid; wire wready;
 reg [1:0] bresp=0; reg bvalid=0; wire bready;

 axi_dma_v019 dut(.clk(clk),.rst_n(rst_n),
  .request_valid(req_valid),.request_ready(req_ready),.request_write(req_write),
  .request_address(req_addr),.request_beats(req_beats),
  .read_valid(rd_valid),.read_ready(rd_ready),.read_data(rd_data),.read_index(rd_index),
  .write_valid(wr_valid),.write_ready(wr_ready),.write_data(wr_data),
  .write_strobe(wr_strobe),.write_index(wr_index),
  .done(done),.error(error),.read_bytes(rd_bytes),.write_bytes(wr_bytes),
  .read_bursts(rd_bursts),.write_bursts(wr_bursts),
  .m_axi_araddr(araddr),.m_axi_arlen(arlen),.m_axi_arsize(arsize),.m_axi_arburst(arburst),
  .m_axi_arcache(arcache),.m_axi_arprot(arprot),.m_axi_arvalid(arvalid),.m_axi_arready(arready),
  .m_axi_rdata(rdata),.m_axi_rresp(rresp),.m_axi_rlast(rlast),.m_axi_rvalid(rvalid),.m_axi_rready(rready),
  .m_axi_awaddr(awaddr),.m_axi_awlen(awlen),.m_axi_awsize(awsize),.m_axi_awburst(awburst),
  .m_axi_awcache(awcache),.m_axi_awprot(awprot),.m_axi_awvalid(awvalid),.m_axi_awready(awready),
  .m_axi_wdata(wdata),.m_axi_wstrb(wstrb),.m_axi_wlast(wlast),.m_axi_wvalid(wvalid),.m_axi_wready(wready),
  .m_axi_bresp(bresp),.m_axi_bvalid(bvalid),.m_axi_bready(bready));

 // ---------------- slave configuration ----------------
 integer r_mode=0;      // 0 normal,1 early rlast,2 extra/late beat,3 no rlast
 integer rresp_at=-1;   // beat number within burst (0 based)
 integer bresp_burst=-1;// AW burst number (global) that returns SLVERR
 integer ar_stall=0, aw_stall=0, w_stall=0; // levels held by tests
 integer b_delay=2, r_delay=2;
 reg r_active=0; reg [39:0] ar_addr_q=0; reg [7:0] r_beat=0; reg [7:0] r_total=0; reg [7:0] r_target=0;
 integer rwait=0; reg [7:0] rd_burst_seen=0;
 reg [39:0] ar_log_addr[0:8191]; reg [7:0] ar_log_len[0:8191];
 integer ar_hs_count=0, aw_hs_count=0, r_hs_count=0, w_hs_count=0, b_hs_count=0;
 reg [39:0] aw_addr_q=0; reg [7:0] aw_len_q=0; reg aw_open=0; reg [7:0] w_beat=0;
 integer bwait=0; integer b_burst_q=0;
 reg b_drop=0; // if 1, never answer B (watchdog/abort probe)
 reg [7:0] mem[0:1048575];

 function [127:0] rgen(input [39:0] a,input [7:0] b);
  integer l;
  begin
   for(l=0;l<16;l=l+1) rgen[l*8+:8]=(a[7:0]+b*16+l)&8'hff;
  end
 endfunction
 function [127:0] wgen(input [31:0] a,input integer b);
  integer l;
  begin
   for(l=0;l<16;l=l+1) wgen[l*8+:8]=(a[7:0]+b*16+l)&8'hff;
  end
 endfunction
 function integer midx(input [39:0] a); begin midx=a[19:0]; end endfunction
 function [127:0] gen128(input [39:0] a);
  integer q;
  begin for(q=0;q<16;q=q+1) gen128[q*8+:8]=(a[7:0]+q)&8'hff; end
 endfunction

 assign rdata = rgen(ar_addr_q,r_beat);
 assign rresp = (rresp_at>=0 && r_beat==rresp_at) ? 2'b10 : 2'b00;
 assign rlast = r_active && (r_beat+1==r_target);
 assign rvalid = r_active && (rwait==0);
 assign arready = rst_n && !r_active && !ar_stall;
 assign awready = rst_n && !aw_open && !aw_stall;
 assign wready = aw_open && !w_stall;

 // ---------------- protocol checkers ----------------
 reg p_arvalid=0; reg [39:0] p_araddr=0; reg [7:0] p_arlen=0; reg p_arready=0;
 reg p_awvalid=0; reg [39:0] p_awaddr=0; reg [7:0] p_awlen=0; reg p_awready=0;
 reg p_wvalid=0; reg [127:0] p_wdata=0; reg [15:0] p_wstrb=0; reg p_wlast=0; reg p_wready=0;
 integer k;
 task chk(input [255:0] what,input cond);
  begin if(!cond)begin errors=errors+1;$display("FAIL[%0d] %0s",errors,what);end end
 endtask

 always @(posedge clk) if(rst_n) begin
  // AXI VALID/payload stability under backpressure
  if(p_arvalid && !p_arready) chk("AR payload unstable",arvalid && araddr==p_araddr && arlen==p_arlen);
  if(p_awvalid && !p_awready) chk("AW payload unstable",awvalid && awaddr==p_awaddr && awlen==p_awlen);
  if(p_wvalid && !p_wready) chk("W payload unstable",wvalid && wdata==p_wdata && wstrb==p_wstrb && wlast==p_wlast);
  p_arvalid<=arvalid;p_araddr<=araddr;p_arlen<=arlen;p_arready<=arready;
  p_awvalid<=awvalid;p_awaddr<=awaddr;p_awlen<=awlen;p_awready<=awready;
  p_wvalid<=wvalid;p_wdata<=wdata;p_wstrb<=wstrb;p_wlast<=wlast;p_wready<=wready;

  // framing at handshake
  if(arvalid && arready) begin
   chk("AR address not 16B aligned",araddr[3:0]==0);
   chk("AR len > 16 beats",arlen<=8'd15);
   chk("AR crosses 4KiB",({1'b0,araddr[11:0]}+(arlen+1)*16)<=4096);
   chk("AR issued while previous R burst open",!r_active);
   ar_log_addr[ar_hs_count]=araddr; ar_log_len[ar_hs_count]=arlen;
   ar_hs_count<=ar_hs_count+1;
  end
  if(awvalid && awready) begin
   chk("AW address not 16B aligned",awaddr[3:0]==0);
   chk("AW len > 16 beats",awlen<=8'd15);
   chk("AW crosses 4KiB",({1'b0,awaddr[11:0]}+(awlen+1)*16)<=4096);
   chk("AW issued while previous B open",!aw_open);
   aw_hs_count<=aw_hs_count+1;
  end
  // slave-side ordering
  if(rvalid && rready) begin
   chk("R beat beyond declared burst (late rlast undetected?)",r_beat < r_target || r_mode==3);
   r_hs_count<=r_hs_count+1;
  end
  if(wvalid && wready) begin
   chk("WLAST wrong beat",wlast==(w_beat+1==aw_len_q+1));
   chk("WSTRB zero on beat",wstrb!=0);
   w_hs_count<=w_hs_count+1;
  end
 end

 always @(posedge clk) if(rst_n && trace_b)
  begin $display("CY t=%0t st=%0d bv=%0d br=%0d ao=%0d wv=%0d wr=%0d d=%0d bhs=%0d",$time,dut.state,bvalid,bready,aw_open,wvalid,wready,done,b_hs_count); $fflush(); end

 // ---------------- slave read engine ----------------
 always @(posedge clk) begin
  if(!rst_n) begin
   r_active<=0;r_beat<=0;rwait<=0;r_total<=0;r_target<=0;
  end else begin
   if(arvalid&&arready) begin
    ar_addr_q<=araddr; r_total<=arlen+1; r_beat<=0;
    if(r_mode==1) r_target<=(arlen==0)?1:(arlen); // one beat early
    else if(r_mode==2) r_target<=arlen+2;         // one extra beat
    else if(r_mode==3) r_target<=8'd200;          // never rlast in window
    else r_target<=arlen+1;
    r_active<=1; rwait<=r_delay;
   end else if(r_active) begin
    if(rwait!=0) rwait<=rwait-1;
    if(rvalid&&rready) begin
     if(rlast) begin r_active<=0; r_beat<=0; end
     else r_beat<=r_beat+1;
    end
   end
  end
 end

 // ---------------- slave write engine ----------------
 always @(posedge clk) begin
  if(!rst_n) begin
   aw_open<=0;w_beat<=0;bvalid<=0;bwait<=0;b_burst_q<=0;
  end else begin
   if(awvalid&&awready) begin
    aw_addr_q<=awaddr;aw_len_q<=awlen;aw_open<=1;w_beat<=0;
    b_burst_q<=aw_hs_count;
    if(trace_w)$display("TRACE AW t=%0t addr=%h len=%0d cnt=%0d",$time,awaddr,awlen,aw_hs_count); $fflush();
   end
   if(wvalid&&wready) begin
    if(trace_w)$display("TRACE WH t=%0t wb=%0d awlen=%0d d0=%h last=%0d open=%0d",$time,w_beat,aw_len_q,wdata[7:0],wlast,aw_open); $fflush();
    for(k=0;k<16;k=k+1) if(wstrb[k]) mem[midx(aw_addr_q)+w_beat*16+k]<=wdata[k*8+:8];
    if(w_beat+1==aw_len_q+1) begin
     aw_open<=0; w_beat<=0; bwait<=b_delay;
    end else w_beat<=w_beat+1;
   end
   if(!aw_open && bwait!=0 && !bvalid) begin
    if(bwait==1 && b_burst_q==bresp_burst) $display("TRACE B match burst=%0d bresp=%0d",b_burst_q,bresp); $fflush();
    bwait<=bwait-1;
    if(bwait==1 && !b_drop) begin
     bvalid<=1; bresp<=(b_burst_q==bresp_burst)?2'b10:2'b00;
     if(trace_w)$display("TRACE BSET t=%0t burst=%0d want=%0d bresp=%0d",$time,b_burst_q,bresp_burst,(b_burst_q==bresp_burst)?2:0); $fflush();
    end
   end
   if(bvalid&&bready) begin
    bvalid<=0; b_hs_count<=b_hs_count+1;
   end
  end
 end

 // ---------------- master driver helpers ----------------
 task automatic do_reset;
  begin
   rst_n=0;req_valid=0;rd_ready=1;wr_active=0;wr_beat=0;wr_n=0;wr_tail=-1;
   r_mode=0;rresp_at=-1;bresp_burst=-1;ar_stall=0;aw_stall=0;w_stall=0;b_drop=0;b_delay=2;r_delay=2;
   repeat(5) @(negedge clk); rst_n=1; repeat(3) @(negedge clk);
  end
 endtask
 task automatic issue_req(input w,input [31:0] a,input [15:0] b);
  begin
   @(negedge clk); req_write=w;req_addr=a;req_beats=b;req_valid=1;
   while(!req_ready) @(negedge clk);
   @(posedge clk); // handshake edge
   @(negedge clk); req_valid=0;
  end
 endtask
 task automatic rd_burst(input [31:0] a,input integer nbeats);
  integer i; reg [31:0] rb,rw; reg er;
  begin
   rb=rd_bytes; rw=wr_bytes;
   issue_req(0,a,nbeats);
   @(posedge clk);
   while(!done) @(posedge clk);
   @(negedge clk);
   chk("read done before slave drained",!r_active && !aw_open && !bvalid);
  end
 endtask
 task automatic start_w(input integer nbeats,input integer tail_bytes);
  begin
   @(negedge clk);
   wr_base=req_addr; wr_n=nbeats; wr_tail=tail_bytes; wr_beat=0; wr_active=1;
   while(wr_active) @(negedge clk);
  end
 endtask
 task automatic wr_burst(input [31:0] a,input integer nbeats,input integer tail_bytes);
  integer i; reg [31:0] rb; reg [15:0] bs;
  begin
   rb=wr_bytes; bs=wr_bursts;
   issue_req(1,a,nbeats);
   start_w(nbeats,tail_bytes);
   while(!done) @(posedge clk);
   if(trace_w)$display("TRACE DONEW t=%0t open=%0d bvalid=%0d state=%0d whs=%0d awcnt=%0d",$time,aw_open,bvalid,dut.state,w_hs_count,aw_hs_count); $fflush();
   @(negedge clk);
   if(aw_open||bvalid)$display("TRACE BADEND t=%0t open=%0d bvalid=%0d",$time,aw_open,bvalid); $fflush();
   chk("write done before B drained",!aw_open && !bvalid);
  end
 endtask

 integer base_rd_bytes,base_wr_bytes,base_rd_bursts,base_wr_bursts,base_r_hs,base_w_hs,base_b_hs;
 integer i,l,exp_bytes,aw0,w0,b0;
 reg [31:0] aa;
 reg [39:0] exp_addr;

 // reference data checkers (word compare: fast enough for 65535 beats)
 integer data_errors=0;
 always @(posedge clk) if(rst_n && rd_valid && rd_ready) begin
  if(rd_data!==gen128(req_addr+rd_index*16)) begin
   data_errors=data_errors+1;
   if(data_errors<6)$display("FAIL R data idx=%0d got=%h exp=%h",rd_index,rd_data,gen128(req_addr+rd_index*16)); $fflush();
  end
 end
 always @(posedge clk) if(rst_n && wr_valid && wr_ready) begin
  if(wr_data!==gen128(req_addr+wr_index*16)) begin
   data_errors=data_errors+1;
   if(data_errors<6)$display("FAIL W data idx=%0d got=%h exp=%h",wr_index,wr_data,gen128(req_addr+wr_index*16)); $fflush();
  end
 end

 initial begin : gtimeout
  repeat(4000000) @(posedge clk);
  $display("GLOBAL_TIMEOUT cycles=%0d",cyc); $display("DMA_EDGE_FAIL timeout"); $fflush(); $finish;
 end
 initial begin : main
  for(i=0;i<524288;i=i+1) mem[i]=8'h00;
  do_reset;

  // ---- T1 normal single-beat read ----
  base_rd_bytes=rd_bytes;base_wr_bytes=wr_bytes;base_rd_bursts=rd_bursts;base_wr_bursts=wr_bursts;
  base_r_hs=r_hs_count;base_w_hs=w_hs_count;base_b_hs=b_hs_count;
  rd_burst(32'h04000000,1);
  chk("T1 done/error",!error);
  chk("T1 bytes",rd_bytes-base_rd_bytes==16);
  chk("T1 bursts",rd_bursts-base_rd_bursts==1);
  chk("T1 index",rd_index==1);
  $display("T1 normal_read cycles=%0d rd_bytes=%0d bursts=%0d",cyc,rd_bytes-base_rd_bytes,rd_bursts-base_rd_bursts); $fflush();

  // ---- T2 zero length ----
  base_r_hs=r_hs_count;base_rd_bursts=rd_bursts;base_rd_bytes=rd_bytes;
  issue_req(0,32'h04000000,0);
  @(posedge clk); while(!done) @(posedge clk);
  @(negedge clk);
  chk("T2 zero-length must be rejected",error==1);
  chk("T2 zero-length issued AXI",r_hs_count==base_r_hs && rd_bursts==base_rd_bursts && rd_bytes==base_rd_bytes);
  $display("T2 zero_len error=%0d ar_bursts_delta=%0d",error,rd_bursts-base_rd_bursts); $fflush();

  // ---- T3 unaligned ----
  base_r_hs=r_hs_count;
  issue_req(0,32'h04000008,1);
  @(posedge clk); while(!done) @(posedge clk);
  @(negedge clk);
  chk("T3 unaligned must be rejected",error==1 && r_hs_count==base_r_hs);
  $display("T3 unaligned error=%0d",error); $fflush();

  // ---- T4 page-aligned 16-beat (single burst) ----
  base_rd_bytes=rd_bytes;base_rd_bursts=rd_bursts;ar_hs_count=0;
  rd_burst(32'h04001000,16);
  chk("T4 no error",!error);
  chk("T4 one burst",rd_bursts-base_rd_bursts==1 && ar_hs_count==1);
  chk("T4 len15",ar_log_len[0]==15);
  chk("T4 bytes",rd_bytes-base_rd_bytes==256);
  $display("T4 page_aligned bursts=%0d len0=%0d",ar_hs_count,ar_log_len[0]); $fflush();

  // ---- T5 4KiB crossing at 0xFF0 ----
  base_rd_bytes=rd_bytes;base_rd_bursts=rd_bursts;ar_hs_count=0;
  rd_burst(32'h04000FF0,16);
  chk("T5 no error",!error);
  chk("T5 two bursts",rd_bursts-base_rd_bursts==2 && ar_hs_count==2);
  chk("T5 first len0",ar_log_len[0]==0);
  chk("T5 first addr",ar_log_addr[0]==40'h0004000FF0);
  chk("T5 second addr",ar_log_addr[1]==40'h0004001000);
  chk("T5 second len14",ar_log_len[1]==14);
  chk("T5 bytes",rd_bytes-base_rd_bytes==256);
  $display("T5 4k_cross bursts=%0d a0=%h l0=%0d a1=%h l1=%0d",ar_hs_count,ar_log_addr[0],ar_log_len[0],ar_log_addr[1],ar_log_len[1]); $fflush();

  // ---- T6 early RLAST ----
  r_mode=1; base_rd_bytes=rd_bytes;base_rd_bursts=rd_bursts;base_r_hs=r_hs_count;
  rd_burst(32'h04002000,8);
  chk("T6 early rlast error",error==1);
  chk("T6 early rlast stopped one beat early",r_hs_count-base_r_hs==7);
  $display("T6 early_rlast error=%0d beats=%0d bytes=%0d",error,r_hs_count-base_r_hs,rd_bytes-base_rd_bytes); $fflush();
  r_mode=0;

  // ---- T7 late RLAST (one extra beat) ----
  r_mode=2; base_rd_bytes=rd_bytes;base_rd_bursts=rd_bursts;base_r_hs=r_hs_count;
  rd_burst(32'h04003000,8);
  chk("T7 extra beat marked error",error==1);
  chk("T7 all beats drained",r_hs_count-base_r_hs==9);
  $display("T7 late_rlast error=%0d beats=%0d bytes=%0d",error,r_hs_count-base_r_hs,rd_bytes-base_rd_bytes); $fflush();
  r_mode=0;

  // ---- T8 RRESP SLVERR mid-burst, must drain accepted burst ----
  rresp_at=2; base_rd_bytes=rd_bytes;base_r_hs=r_hs_count;
  rd_burst(32'h04004000,8);
  chk("T8 rresp error",error==1);
  chk("T8 accepted burst fully drained",r_hs_count-base_r_hs==8);
  $display("T8 rresp_drain error=%0d beats=%0d",error,r_hs_count-base_r_hs); $fflush();
  rresp_at=-1;

  // ---- T9 normal write 1 beat ----
  trace_b=0;
  base_wr_bytes=wr_bytes;base_wr_bursts=wr_bursts;base_w_hs=w_hs_count;base_b_hs=b_hs_count;
  wr_burst(32'h04010000,1,-1);
  chk("T9 write ok",!error);
  chk("T9 bytes",wr_bytes-base_wr_bytes==16);
  chk("T9 mem",mem[midx(32'h04010000)]==((32'h04010000+0)&8'hff));
  $display("T9 write1 ok=%0d bytes=%0d mem0=%h",!error,wr_bytes-base_wr_bytes,mem[midx(32'h04010000)]); $fflush();
  trace_b=0;

  // ---- T10 write tail strobe ----
  base_wr_bytes=wr_bytes;base_wr_bursts=wr_bursts;
  wr_burst(32'h04011000,4,3); // last beat 3 valid bytes
  chk("T10 tail ok",!error);
  chk("T10 tail byte count",wr_bytes-base_wr_bytes==3*16+3);
  chk("T10 tail first byte",mem[midx(32'h04011000)+48]==((32'h04011000+48)&8'hff));
  chk("T10 tail last valid byte",mem[midx(32'h04011000)+50]==((32'h04011000+50)&8'hff));
  chk("T10 tail masked byte",mem[midx(32'h04011000)+51]==8'h00);
  $display("T10 write_tail ok=%0d bytes=%0d",!error,wr_bytes-base_wr_bytes); $fflush();

  // ---- T11 4KiB crossing write, 2 bursts ----
  base_wr_bytes=wr_bytes;base_wr_bursts=wr_bursts;aw_hs_count=0;
  wr_burst(32'h04011FF0,16,-1);
  chk("T11 write 2 bursts",!error && wr_bursts-base_wr_bursts==2 && aw_hs_count==2);
  chk("T11 bytes",wr_bytes-base_wr_bytes==256);
  $display("T11 write_4k bursts=%0d bytes=%0d",wr_bursts-base_wr_bursts,wr_bytes-base_wr_bytes); $fflush();

  // ---- T12 BRESP error on first of two bursts: no second AW ----
  base_wr_bytes=wr_bytes;base_wr_bursts=wr_bursts;aw_hs_count=0;bresp_burst=0;base_b_hs=b_hs_count;
  wr_burst(32'h04020000,16,-1); // page aligned: 1 burst, inject SLVERR
  chk("T12 bresp error",error==1);
  chk("T12 no extra AW",aw_hs_count==1);
  chk("T12 B drained",b_hs_count-base_b_hs==1);
  $display("T12 bresp_error error=%0d aw=%0d",error,aw_hs_count); $fflush();
  bresp_burst=-1;

  // ---- T12b multi-burst write: BRESP error on the first (1-beat) page burst ----
  aw0=aw_hs_count; w0=w_hs_count; b0=b_hs_count;
  bresp_burst=aw_hs_count;
  base_wr_bytes=wr_bytes;
  issue_req(1,32'h04020FF0,16);
  @(negedge clk);wr_base=req_addr;wr_n=16;wr_tail=-1;wr_beat=0;wr_active=1;
  for(i=0;i<500 && !done;i=i+1)@(posedge clk);
  @(negedge clk);wr_active=0;
  chk("T12b bresp abort no second AW/W",error==1 && aw_hs_count-aw0==1 && w_hs_count-w0==1 && b_hs_count-b0==1);
  $display("T12b bresp_abort error=%0d aw_delta=%0d w_delta=%0d b_delta=%0d",error,aw_hs_count-aw0,w_hs_count-w0,b_hs_count-b0); $fflush();
  bresp_burst=-1;

  // ---- T13 AW/W/B independent backpressure ----
  trace_w=0; aw_stall=1; w_stall=1; b_delay=12;
  base_wr_bytes=wr_bytes;
  fork
   begin // request + producer
    wr_burst(32'h04030000,4,-1);
   end
   begin // deassert AW ready then W ready then release
    repeat(5) @(negedge clk); aw_stall=0;
    repeat(7) @(negedge clk); w_stall=0;
   end
  join
  trace_w=0; chk("T13 backpressure ok",!error);
  chk("T13 bytes",wr_bytes-base_wr_bytes==64);
  for(i=0;i<64;i=i+1) chk("T13 mem pattern",mem[midx(32'h04030000)+i]==((32'h04030000+i)&8'hff));
  $display("T13 aw_w_b_stall ok=%0d",!error); $fflush();

  // ---- T14 ARREADY stall: AR payload stable (checker), read ok ----
  ar_stall=1; r_delay=5;
  base_rd_bytes=rd_bytes;
  fork
   begin rd_burst(32'h04040000,8); end
   begin repeat(9) @(negedge clk); ar_stall=0; end
  join
  chk("T14 arready stall ok",!error && rd_bytes-base_rd_bytes==128);
  $display("T14 arready_stall ok=%0d",!error); $fflush();

  // ---- T15 RREADY stall from consumer; slave holds R data ----
  base_rd_bytes=rd_bytes;
  fork
   begin rd_burst(32'h04050000,16); end
   begin repeat(4) @(negedge clk); rd_ready=0; repeat(13) @(negedge clk); rd_ready=1; end
  join
  chk("T15 rready stall ok",!error && rd_bytes-base_rd_bytes==256);
  $display("T15 rready_stall ok=%0d",!error); $fflush();

  // ---- T16 late BVALID; BREADY must stay asserted ----
  b_delay=20;
  base_wr_bytes=wr_bytes;
  wr_burst(32'h04060000,8,-1);
  chk("T16 late B ok",!error && wr_bytes-base_wr_bytes==128);
  $display("T16 late_b ok=%0d",!error); $fflush();
  b_delay=2;

  // ---- T17 max legal beat count: 65535 beats over 4096 bursts ----
  r_delay=0; base_rd_bytes=rd_bytes;base_rd_bursts=rd_bursts;
  rd_burst(32'h04000000,16'hFFFF);
  chk("T17 max beats ok",!error);
  chk("T17 max bytes",rd_bytes-base_rd_bytes==32'd1048560);
  chk("T17 max bursts",rd_bursts-base_rd_bursts==4096);
  chk("T17 index final",rd_index==16'hFFFF);
  $display("T17 max_beats ok=%0d bytes=%0d bursts=%0d index=%0d",!error,rd_bytes-base_rd_bytes,rd_bursts-base_rd_bursts,rd_index); $fflush();
  r_delay=2;

  // ---- T18 32-bit address wrap probe (does NOT assert 4K violation) ----
  ar_hs_count=0;
  rd_burst(32'hFFFFFFF0,2);
  chk("T18 wrap still reports no error (silent wrap)",error==0);
  chk("T18 two zero-length bursts",ar_hs_count==2);
  $display("T18 addr_wrap bursts=%0d a0=%h a1=%h error=%0d",ar_hs_count,ar_log_addr[0],ar_log_addr[1],error); $fflush();

  // ---- T19 no RLAST: bounded observation ----
  r_mode=3; r_delay=0;
  base_r_hs=r_hs_count;
  issue_req(0,32'h04070000,4);
  repeat(120) @(posedge clk);
  chk("T19 no-rlast stays busy (no done)",done==0);
  $display("T19 no_rlast done=%0d beats_accepted=%0d (no internal timeout)",done,r_hs_count-base_r_hs); $fflush();
  r_mode=0;
  // do not wait for done; the DUT is intentionally left mid-burst then reset
  do_reset;

  errors=errors+data_errors;
  if(errors==0) begin $display("DMA_EDGE_PASS checks=%0d cycles=%0d",0,cyc); $fflush(); end
  else begin $display("DMA_EDGE_FAIL errors=%0d cycles=%0d",errors,cyc); $fflush(); end
  $finish;
 end
endmodule
