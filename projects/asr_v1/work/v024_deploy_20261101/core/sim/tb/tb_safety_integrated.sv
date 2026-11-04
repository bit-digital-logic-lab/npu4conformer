`timescale 1ns/1ps
// V0.23 abnormal-closeout / safety testbench.
//
// One CSR START, then the PL graph runs.  The external SEQ child is driven by
// this TB so a real hung/waiting child can be injected.  The shared AXI slave
// can withhold R or B permanently.  Every run prints the terminal state and
// the AXI drain boundary; nothing is inferred from a timeout alone.
module tb_safety_integrated;
 localparam integer MAX_CYCLES = 200000;

 // mode encoding
 localparam integer M_NORMAL=0, M_MUTEX_LAY=1, M_MUTEX_SEQ=2,
   M_HANG_WAIT=3, M_HANG_RUN=4, M_MULTITASK=5;

 reg clk = 0;
 always #4 clk = ~clk;
 reg rst_n = 0;

 // CSR
 reg [23:0] awaddr=0; reg awvalid=0; wire awready;
 reg [31:0] wdata=0; reg [3:0] wstrb=0; reg wvalid=0; wire wready;
 wire [1:0] bresp; wire bvalid; reg bready=1;
 reg [23:0] araddr=0; reg arvalid=0; wire arready;
 wire [31:0] rdata; wire [1:0] rresp; wire rvalid; reg rready=1;

 // data AXI
 wire [39:0] m_araddr; wire [7:0] m_arlen; wire [2:0] m_arsize;
 wire [1:0] m_arburst; wire m_arvalid; wire m_arready;
 wire [127:0] m_rdata; wire [1:0] m_rresp; wire m_rlast,m_rvalid; wire m_rready;
 wire [39:0] m_awaddr; wire [7:0] m_awlen; wire [2:0] m_awsize;
 wire [1:0] m_awburst; wire m_awvalid; wire m_awready;
 wire [127:0] m_wdata; wire [15:0] m_wstrb; wire m_wlast,m_wvalid; wire m_wready;
 wire [1:0] m_bresp; wire m_bvalid; wire m_bready;

 // status
 wire busy,done,fault,irq,drain_timeout;
 wire [7:0] error_code;
 wire [31:0] completed,last_node;
 wire [63:0] cycles;
 wire seq_active,vector_busy,layout_busy,matrix_busy;
 wire [7:0] matrix_error;
 wire [63:0] matrix_cycles;
 wire [31:0] matrix_compute_cycles;
 wire [63:0] vector_cycles,layout_cycles;
 wire [31:0] vector_read_bytes,vector_write_bytes,layout_read_bytes,layout_write_bytes;
 wire [31:0] rd_bursts,wr_bursts,r_beats,w_beats;
 wire [31:0] rd_peak,wr_peak,rd_stall_cycles,wr_stall_cycles,axi_tag_errors;
 wire isolation_req,requires_reset,port_quiesced;
 wire [31:0] rd_pending,wr_pending,b_pending,iso_blocked_reqs;
 wire seq_dto,seq_ito,fetch_to;
 wire [63:0] vector_total_cycles,layout_total_cycles,matrix_total_cycles;
 wire [31:0] vector_op_count,layout_op_count,matrix_op_count;
 wire seq_valid_o; wire [31:0] seq_base_o,seq_count_o;

 // BFM
 wire [31:0] bfm_rb,bfm_wb,bfm_rbeats,bfm_wbeats;
 wire [31:0] bfm_held_r,bfm_held_b,bfm_returned_b;
 wire bfm_rheld,bfm_bheld;
 wc_safety_bfm bfm (
  .clk(clk),.rst_n(rst_n),
  .araddr(m_araddr),.arlen(m_arlen),.arsize(m_arsize),.arburst(m_arburst),
  .arvalid(m_arvalid),.arready(m_arready),
  .rdata(m_rdata),.rresp(m_rresp),.rlast(m_rlast),.rvalid(m_rvalid),.rready(m_rready),
  .awaddr(m_awaddr),.awlen(m_awlen),.awsize(m_awsize),.awburst(m_awburst),
  .awvalid(m_awvalid),.awready(m_awready),
  .wdata(m_wdata),.wstrb(m_wstrb),.wlast(m_wlast),.wvalid(m_wvalid),.wready(m_wready),
  .bresp(m_bresp),.bvalid(m_bvalid),.bready(m_bready),
  .read_bursts(bfm_rb),.write_bursts(bfm_wb),.read_beats(bfm_rbeats),.write_beats(bfm_wbeats),
  .held_r_bursts(bfm_held_r),.held_b_bursts(bfm_held_b),.returned_b(bfm_returned_b),
  .r_is_held(bfm_rheld),.b_is_held(bfm_bheld)
 );

 // SEQ child driven by this TB
 reg seq_ready_r=0, seq_done_r=0, seq_fault_r=0;
 reg [7:0] seq_error_r=0;
 reg seq_seen=0, seq_started=0;
 integer seq_ready_cnt=0, seq_run_cnt=0;

 v023_integrated_top #(
  .PIPE_STAGES(4),.MAX_PREFETCH(16),.USE_APPROX_DIV_SQRT(0),
  .MATRIX_WATCHDOG(3000),.VEC_WATCHDOG(3000),.LAY_WATCHDOG(20000),
  .SEQ_WATCHDOG(3000),.FETCH_WATCHDOG(3000),
  .DRAIN_WATCHDOG(20000),.SEQ_ENABLE(1)
 ) dut (
  .clk(clk),.rst_n(rst_n),
  .seq_ready_i(seq_ready_r),.seq_done_i(seq_done_r),.seq_fault_i(seq_fault_r),
  .seq_error_i(seq_error_r),.seq_valid_o(seq_valid_o),
  .seq_base_o(seq_base_o),.seq_count_o(seq_count_o),
  .s_axi_awaddr(awaddr),.s_axi_awvalid(awvalid),.s_axi_awready(awready),
  .s_axi_wdata(wdata),.s_axi_wstrb(wstrb),.s_axi_wvalid(wvalid),.s_axi_wready(wready),
  .s_axi_bresp(bresp),.s_axi_bvalid(bvalid),.s_axi_bready(bready),
  .s_axi_araddr(araddr),.s_axi_arvalid(arvalid),.s_axi_arready(arready),
  .s_axi_rdata(rdata),.s_axi_rresp(rresp),.s_axi_rvalid(rvalid),.s_axi_rready(rready),
  .m_araddr(m_araddr),.m_arlen(m_arlen),.m_arsize(m_arsize),.m_arburst(m_arburst),
  .m_arvalid(m_arvalid),.m_arready(m_arready),
  .m_rdata(m_rdata),.m_rresp(m_rresp),.m_rlast(m_rlast),.m_rvalid(m_rvalid),.m_rready(m_rready),
  .m_awaddr(m_awaddr),.m_awlen(m_awlen),.m_awsize(m_awsize),.m_awburst(m_awburst),
  .m_awvalid(m_awvalid),.m_awready(m_awready),
  .m_wdata(m_wdata),.m_wstrb(m_wstrb),.m_wlast(m_wlast),.m_wvalid(m_wvalid),.m_wready(m_wready),
  .m_bresp(m_bresp),.m_bvalid(m_bvalid),.m_bready(m_bready),
  .busy(busy),.done(done),.fault(fault),.irq(irq),.drain_timeout(drain_timeout),
  .error_code(error_code),.completed(completed),.last_node(last_node),.cycles(cycles),
  .seq_active(seq_active),.vector_busy(vector_busy),.layout_busy(layout_busy),
  .matrix_busy(matrix_busy),.matrix_error(matrix_error),.matrix_cycles(matrix_cycles),
  .matrix_compute_cycles(matrix_compute_cycles),
  .vector_cycles(vector_cycles),.layout_cycles(layout_cycles),
  .vector_read_bytes(vector_read_bytes),.vector_write_bytes(vector_write_bytes),
  .layout_read_bytes(layout_read_bytes),.layout_write_bytes(layout_write_bytes),
  .rd_bursts(rd_bursts),.wr_bursts(wr_bursts),.r_beats(r_beats),.w_beats(w_beats),
  .rd_peak(rd_peak),.wr_peak(wr_peak),.rd_stall_cycles(rd_stall_cycles),
  .wr_stall_cycles(wr_stall_cycles),.axi_tag_errors(axi_tag_errors),
  .isolation_req(isolation_req),.requires_reset(requires_reset),
  .port_quiesced(port_quiesced),.rd_pending(rd_pending),.wr_pending(wr_pending),
  .b_pending(b_pending),.iso_blocked_reqs(iso_blocked_reqs),
  .seq_dispatch_timeout(seq_dto),.seq_inflight_timeout(seq_ito),.fetch_timeout(fetch_to),
  .vector_total_cycles(vector_total_cycles),.layout_total_cycles(layout_total_cycles),
  .matrix_total_cycles(matrix_total_cycles),.vector_op_count(vector_op_count),
  .layout_op_count(layout_op_count),.matrix_op_count(matrix_op_count)
 );

 integer cyc=0;
 integer timeout=40000;
 integer mode=M_NORMAL;
 integer seq_ready_delay=4, seq_done_delay=20;
 integer expect_error=-1;
 integer expect_iso=0;
 integer expect_requires_reset=0;
 integer expect_quiesced=0;
 integer errors=0;
 integer i;
 reg [31:0] plan_base;
 reg [31:0] val;
 integer trace_en=0;
 integer allow_fault=0;
 integer test_restart=0;
 reg [31:0] lockrej2;
 integer new_req=0;

 // concurrency monitor: SEQ vs each direct engine
 integer ov_seq_lay=0, ov_seq_vec=0, ov_seq_mat=0, ov_seq_direct=0;
 integer iso_cycles=0, post_iso_req=0;
 integer vec_done_seen=0, lay_done_seen=0, mat_done_seen=0;
 integer mat_core_done=0;
 integer vec_sum=0, lay_sum=0;
 integer last_vec_cycles=0, last_lay_cycles=0;
 reg done_seen=0;
 reg [2:0] prev_st=0;
 always @(posedge clk) if (rst_n) begin
  if (dut.csr.done_latched) done_seen<=1;
  if (dut.graph.ctrl.e_active[0]) begin
   if (dut.graph.ctrl.e_active[3]) ov_seq_lay <= ov_seq_lay+1;
   if (dut.graph.ctrl.e_active[2]) ov_seq_vec <= ov_seq_vec+1;
   if (dut.graph.ctrl.e_active[1]) ov_seq_mat <= ov_seq_mat+1;
   if (|dut.graph.ctrl.e_active[3:1]) ov_seq_direct <= ov_seq_direct+1;
  end
  if (dut.graph.vec_done_pulse) begin
   vec_done_seen <= vec_done_seen+1; vec_sum <= vec_sum + vector_cycles;
  end
  if (dut.graph.lay_done_pulse) begin
   lay_done_seen <= lay_done_seen+1; lay_sum <= lay_sum + layout_cycles;
  end
  if (dut.matrix.core_done) mat_core_done <= mat_core_done+1;
  if (dut.matrix.done_pulse) $display("MATDONE t=%0d st=%0d acc=%0d core_done=%0d cyc=%0d",$time,dut.matrix.st,dut.matrix.acc_ops,dut.matrix.core_done,dut.matrix.telem_cycles);
  if (dut.matrix.st != prev_st) begin
   $display("MATST t=%0d st=%0d core_done=%0d acc=%0d",$time,dut.matrix.st,dut.matrix.core_done,dut.matrix.acc_ops);
   prev_st <= dut.matrix.st;
  end
  if (isolation_req) begin
   iso_cycles <= iso_cycles+1;
   if (m_arvalid || m_awvalid || m_wvalid) post_iso_req <= post_iso_req+1;
  end
 end

 // SEQ child model
 always @(posedge clk) begin
  if (!rst_n) begin
   seq_ready_r<=0;seq_done_r<=0;seq_fault_r<=0;seq_seen<=0;seq_started<=0;
   seq_ready_cnt<=0;seq_run_cnt<=0;
  end else begin
   seq_done_r<=0;
   if (seq_valid_o) begin
    if (!seq_seen) begin seq_seen<=1; seq_ready_cnt<=0; end
    if (mode==M_HANG_WAIT) seq_ready_r<=0;
    else if (seq_ready_cnt < seq_ready_delay) begin
     seq_ready_cnt<=seq_ready_cnt+1; seq_ready_r<=0;
    end else seq_ready_r<=1;
   end else if (mode==M_HANG_WAIT) begin
    // never accept
   end else seq_ready_r<=0;
   if (seq_ready_r && seq_valid_o && !seq_started) begin
    seq_started<=1; seq_run_cnt<=0;
   end
   if (seq_started) begin
    if (mode==M_HANG_RUN) begin
     // accepted but never returns done
    end else if (seq_run_cnt < seq_done_delay) seq_run_cnt<=seq_run_cnt+1;
    else begin seq_done_r<=1; seq_started<=0; end
   end
  end
 end

 reg [1:0] last_bresp=0;
 task csr_write(input [23:0] a, input [31:0] d);
 begin
  @(posedge clk); awaddr<=a; wdata<=d; wstrb<=4'hf; awvalid<=1; wvalid<=1;
  while (!(awready&&wready)) @(posedge clk);
  @(posedge clk); awvalid<=0; wvalid<=0;
  while (!bvalid) @(posedge clk);
  last_bresp = bresp;
  @(posedge clk);
 end
 endtask

 task csr_read(input [23:0] a, output [31:0] d);
 begin
  @(posedge clk); araddr<=a; arvalid<=1;
  while (!arready) @(posedge clk);
  @(posedge clk); arvalid<=0;
  while (!rvalid) @(posedge clk);
  d = rdata;
  @(posedge clk);
 end
 endtask

 task read64(input [23:0] lo, output [63:0] d);
 reg [31:0] l,h;
 begin
  csr_read(lo,l); csr_read(lo+4,h); d={h,l};
 end
 endtask

 reg [1023:0] memfile, outfile;
 integer fd;
 initial begin
  if (!$value$plusargs("memfile=%s", memfile)) memfile="sim/fixtures/mem_integrated.hex";
  if (!$value$plusargs("outfile=%s", outfile)) outfile="logs/safety_out.hex";
  if (!$value$plusargs("watchdog=%d", timeout)) timeout=40000;
  if (!$value$plusargs("mode=%d", mode)) mode=M_NORMAL;
  if (!$value$plusargs("seq_ready_delay=%d", seq_ready_delay)) seq_ready_delay=4;
  if (!$value$plusargs("seq_done_delay=%d", seq_done_delay)) seq_done_delay=20;
  if (!$value$plusargs("expect_error=%d", expect_error)) expect_error=-1;
  if (!$value$plusargs("expect_iso=%d", expect_iso)) expect_iso=0;
  if (!$value$plusargs("expect_requires_reset=%d", expect_requires_reset)) expect_requires_reset=0;
  if (!$value$plusargs("expect_quiesced=%d", expect_quiesced)) expect_quiesced=0;
  if (!$value$plusargs("allow_fault=%d", allow_fault)) allow_fault=0;
  if (!$value$plusargs("test_restart=%d", test_restart)) test_restart=0;
  if (!$value$plusargs("plan=%d", plan_base)) plan_base=32'h10008000;
  rst_n=0;
  repeat (12) @(posedge clk);
  rst_n=1;
  repeat (5) @(posedge clk);
  csr_write(24'h08, plan_base);
  csr_write(24'h0c, 32'd1);
  csr_write(24'h10, 32'd1);
  while (!done_seen && !fault && cyc < timeout) begin
   @(posedge clk);
   if (cyc % 5000 == 0)
    $display("WAIT cyc=%0d busy=%0d fault=%0d err=%02x iso=%0d rd=%0d wr=%0d b=%0d",
      cyc,busy,fault,error_code,isolation_req,rd_pending,wr_pending,b_pending);
  end
  repeat (20) @(posedge clk);

  // CSR totals (must be per-op sums, not the last counter)
  begin : csr_dump
   reg [63:0] v,l,m,cy,f,op;
   reg [31:0] st,er,cp,ln,vops,lops,mops,isost,rdp,wrp,bp,isob,lockrej;
   csr_read(24'h04,st);
   csr_read(24'h1c,er);
   csr_read(24'h14,cp);
   csr_read(24'h18,ln);
   read64(24'h20,cy);
   read64(24'h30,f);
   read64(24'h38,op);
   read64(24'h40,v);
   read64(24'h48,l);
   read64(24'hA0,m);
   csr_read(24'hB0,isost);
   csr_read(24'hB4,rdp);
   csr_read(24'hB8,wrp);
   csr_read(24'hBC,bp);
   csr_read(24'hC0,isob);
   csr_read(24'hC4,lockrej);
   csr_read(24'hC8,lockrej);
   $display("SAFETY_CSR status=%08x err=%02x completed=%0d last=%0d cycles=%0d fetch=%0d op=%0d",
     st,er,cp,ln,cy,f,op);
   $display("SAFETY_CSR vec_total=%0d layout_total=%0d matrix_total=%0d vec_ops=%0d layout_ops=%0d matrix_ops=%0d",
     v,l,m,vector_op_count,layout_op_count,matrix_op_count);
   $display("SAFETY_CSR iso_status=%08x rd_pending=%0d wr_pending=%0d b_pending=%0d iso_blocked=%0d lockout_rej=%0d",
     isost,rdp,wrp,bp,isob,lockrej);
   $display("SAFETY_SUM vec_done=%0d vec_sum=%0d lay_done=%0d lay_sum=%0d mat_core_done=%0d",
     vec_done_seen,vec_sum,lay_done_seen,lay_sum,mat_core_done);
   $display("SAFETY_MATRIX ops=%0d acc=%0d st=%0d completed=%0d index=%0d err=%02x cyc=%0d total=%0d",
     matrix_op_count,dut.matrix.acc_ops,dut.matrix.st,dut.matrix.completed_tasks,
     dut.matrix.current_index,matrix_error,matrix_cycles,matrix_total_cycles);
   if (v != vec_sum || l != lay_sum) begin
    $display("SAFETY_COUNT_MISMATCH csr_vec=%0d sum_vec=%0d csr_lay=%0d sum_lay=%0d",v,vec_sum,l,lay_sum);
    errors=errors+1;
   end
  end

  $display("SAFETY_OVERLAP seq_lay=%0d seq_vec=%0d seq_mat=%0d seq_direct=%0d",
    ov_seq_lay,ov_seq_vec,ov_seq_mat,ov_seq_direct);
  $display("SAFETY_DRAIN rd_pending=%0d wr_pending=%0d b_pending=%0d quiesced=%0d iso_blocked=%0d held_r=%0d held_b=%0d returned_b=%0d",
    rd_pending,wr_pending,b_pending,port_quiesced,iso_blocked_reqs,bfm_held_r,bfm_held_b,bfm_returned_b);
  $display("SAFETY_END done=%0d fault=%0d error=%02x iso=%0d requires_reset=%0d seq_dto=%0d seq_ito=%0d fetch_to=%0d drain_timeout=%0d cycles=%0d",
    dut.csr.done_latched,fault,error_code,isolation_req,requires_reset,seq_dto,seq_ito,fetch_to,drain_timeout,cyc);
  $display("SAFETY_AXI rburst=%0d wburst=%0d rbeats=%0d wbeats=%0d tag_err=%0d bfm_rbeats=%0d bfm_wbeats=%0d",
    rd_bursts,wr_bursts,r_beats,w_beats,axi_tag_errors,bfm_rbeats,bfm_wbeats);

  if (mode==M_MUTEX_LAY || mode==M_MUTEX_SEQ) begin
   if (ov_seq_direct != 0) begin
    $display("SAFETY_MUTEX_VIOLATION seq_direct=%0d",ov_seq_direct); errors=errors+1;
   end
  end
  if (mode==M_HANG_WAIT) begin
   if (!seq_dto || !isolation_req) begin
    $display("SAFETY_HANG_WAIT_NOT_ISOLATED"); errors=errors+1;
   end
  end
  if (mode==M_HANG_RUN) begin
   if (!seq_ito || !isolation_req) begin
    $display("SAFETY_HANG_RUN_NOT_ISOLATED"); errors=errors+1;
   end
  end
  if (expect_iso && !isolation_req) begin
   $display("SAFETY_ISO_MISSING"); errors=errors+1;
  end
  if (expect_requires_reset && !requires_reset) begin
   $display("SAFETY_RESET_REQUIRED_MISSING"); errors=errors+1;
  end
  if (expect_error >= 0 && error_code != expect_error[7:0]) begin
   $display("SAFETY_ERROR_MISMATCH got=%02x want=%02x",error_code,expect_error);
   errors=errors+1;
  end
  if (!allow_fault) begin
   if (fault || !dut.csr.done_latched) errors=errors+1;
  end else begin
   if (!dut.csr.done_latched) errors=errors+1;
  end
  if (cyc >= timeout) begin $display("SAFETY_TIMEOUT cyc=%0d",cyc); errors=errors+1; end
  // After a terminal isolation, prove no new request is issued.
  if (isolation_req) begin
   repeat (50) @(posedge clk);
   $display("SAFETY_QUIESCE post_iso_req=%0d rd_pending=%0d wr_pending=%0d b_pending=%0d quiesced=%0d",
     post_iso_req,rd_pending,wr_pending,b_pending,port_quiesced);
   if (post_iso_req != 0) begin
    $display("SAFETY_ISO_NOT_QUIESCED"); errors=errors+1;
   end
   if (expect_quiesced && !port_quiesced) begin
    $display("SAFETY_EXPECT_QUIESCED_MISSING"); errors=errors+1;
   end
  end
  // Restart-after-isolation contract: the CSR must refuse START while
  // requires_reset is set, must not clear done_latched, and must not put a
  // new AR/AW/W on a port that may still own an old transaction.
  if (test_restart && isolation_req) begin
   new_req = 0;
   csr_write(24'h10, 32'd1);
   if (last_bresp != 2) begin
    $display("SAFETY_RESTART_NOT_REFUSED bresp=%0d", last_bresp); errors=errors+1;
   end
   csr_read(24'hC8, lockrej2);
   $display("SAFETY_RESTART bresp=%0d lockout_rej=%0d done_latched=%0d requires_reset=%0d",
     last_bresp, lockrej2, dut.csr.done_latched, requires_reset);
   if (lockrej2 == 0) begin $display("SAFETY_LOCKOUT_NOT_COUNTED"); errors=errors+1; end
   if (!dut.csr.done_latched) begin $display("SAFETY_DONE_CLEARED_ON_LOCKOUT"); errors=errors+1; end
   repeat (50) begin
    @(posedge clk);
    if (m_arvalid || m_awvalid || m_wvalid) new_req = new_req+1;
   end
   $display("SAFETY_RESTART_TRAFFIC new_req=%0d", new_req);
   if (new_req != 0) begin $display("SAFETY_PORT_REUSED"); errors=errors+1; end
  end

  // dump final output for comparison (normal/multitask)
  fd=$fopen(outfile,"w");
  for (i=0;i<512;i=i+1) $fwrite(fd,"%08x\n",bfm.memw[32'h12000+i]);
  $fclose(fd);
  if (errors) $display("SAFETY_RESULT FAIL errors=%0d",errors);
  else $display("SAFETY_RESULT PASS");
  $finish;
 end

 always @(posedge clk) begin
  cyc <= cyc+1;
  if (cyc > timeout+2000) begin
   $display("SAFETY_GLOBAL_TIMEOUT cyc=%0d busy=%0d fault=%0d err=%02x iso=%0d rd=%0d wr=%0d b=%0d",
     cyc,busy,fault,error_code,isolation_req,rd_pending,wr_pending,b_pending);
   $finish;
  end
 end
endmodule
