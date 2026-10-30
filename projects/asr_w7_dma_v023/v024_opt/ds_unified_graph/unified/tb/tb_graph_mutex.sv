`timescale 1ns/1ps
// SEQ-exclusive-ownership unit test for the WCPG controller.
//
// Build with -DPATCHED to test the fixed controller.  Without it, the same TB
// is compiled against the delivered integrated_copy/wc_graph_ctrl.sv and acts
// as the negative control: the LAY bit is missing from direct_idle and direct
// children are not gated by SEQ, so the overlap monitor must fire.
module tb_graph_mutex;
 reg clk=0;
 always #4 clk=~clk;
 reg rst_n=0;
 reg start=0;
 reg [31:0] plan_base=32'h10008000;
 reg [31:0] param_end=32'h10040000;
 reg parameter_ready=1;
 reg [31:0] generation=0;

 wire busy,done,fault,irq,drain_timeout;
 wire [7:0] error_code;
 wire [31:0] completed,node_count,rejected_starts,last_node;
 wire [1023:0] done_mask;
 wire [63:0] cycles,fetch_cycles,operator_cycles,drain_cycles;
 wire output_retained;
 wire [31:0] output_count,last_output_tid,last_output_base,last_output_bytes;

 wire sf_req_valid,sf_req_ready,sf_read_valid,sf_read_ready,sf_done,sf_err;
 wire [31:0] sf_address;
 wire [7:0] sf_beats,sf_ridx;
 wire [15:0] sf_beats16,sf_ridx16;
 wire [127:0] sf_rdata_i;
 assign sf_beats16={8'd0,sf_beats}; assign sf_ridx=sf_ridx16[7:0];

 wire seq_valid,seq_ready,seq_done,seq_fault;
 wire [31:0] seq_base,seq_count;
 wire [7:0] seq_error;
 wire mat_valid,mat_ready,mat_done,mat_fault;
 wire [31:0] mat_base,mat_count;
 wire [7:0] mat_error;
 wire vec_valid,vec_ready,vec_done,vec_fault;
 wire [511:0] vec_descriptor;
 wire [7:0] vec_error;
 wire lay_valid,lay_ready,lay_done,lay_fault;
 wire [1023:0] lay_descriptor;
 wire [7:0] lay_error;
 wire direct_idle,seq_active;

 wire [39:0] m_araddr; wire [7:0] m_arlen; wire [2:0] m_arsize; wire [1:0] m_arburst;
 wire m_arvalid,m_arready,m_rlast,m_rvalid,m_rready;
 wire [127:0] m_rdata; wire [1:0] m_rresp;
 wire [39:0] m_awaddr; wire [7:0] m_awlen; wire [2:0] m_awsize; wire [1:0] m_awburst;
 wire m_awvalid,m_awready,m_wlast,m_wvalid,m_wready;
 wire [127:0] m_wdata; wire [15:0] m_wstrb; wire [1:0] m_bresp;
 wire m_bvalid,m_bready;

`ifdef PATCHED
 wire isolation_req,requires_reset,seq_dto,seq_ito,fetch_to;
 wire [31:0] seq_wait_cycles,seq_run_cycles;
 wc_graph_ctrl #(.SEQ_WATCHDOG(3000),.FETCH_WATCHDOG(200000),
  .DRAIN_WATCHDOG(64'd20000)) ctrl (
`else
 wc_graph_ctrl ctrl (
`endif
  .clk(clk),.rst_n(rst_n),.start(start),.plan_base(plan_base),.param_end(param_end),
  .parameter_ready(parameter_ready),.generation(generation),
  .busy(busy),.done(done),.fault(fault),.error_code(error_code),.completed(completed),
  .node_count(node_count),.rejected_starts(rejected_starts),.last_node(last_node),
  .done_mask(done_mask),.cycles(cycles),.fetch_cycles(fetch_cycles),
  .operator_cycles(operator_cycles),.drain_cycles(drain_cycles),.drain_timeout(drain_timeout),
  .irq(irq),.output_retained(output_retained),.output_count(output_count),
  .last_output_tid(last_output_tid),.last_output_base(last_output_base),
  .last_output_bytes(last_output_bytes),
  .fetch_req_valid(sf_req_valid),.fetch_req_ready(sf_req_ready),
  .fetch_address(sf_address),.fetch_beats(sf_beats),
  .fetch_read_valid(sf_read_valid),.fetch_read_ready(sf_read_ready),
  .fetch_read_data(sf_rdata_i),.fetch_read_index(sf_ridx),
  .fetch_done(sf_done),.fetch_error(sf_err),
  .seq_valid(seq_valid),.seq_ready(seq_ready),.seq_base(seq_base),.seq_count(seq_count),
  .seq_done(seq_done),.seq_fault(seq_fault),.seq_error(seq_error),
  .mat_valid(mat_valid),.mat_ready(mat_ready),.mat_base(mat_base),.mat_count(mat_count),
  .mat_done(mat_done),.mat_fault(mat_fault),.mat_error(mat_error),
  .vec_valid(vec_valid),.vec_ready(vec_ready),.vec_descriptor(vec_descriptor),
  .vec_done(vec_done),.vec_fault(vec_fault),.vec_error(vec_error),
  .lay_valid(lay_valid),.lay_ready(lay_ready),.lay_descriptor(lay_descriptor),
  .lay_done(lay_done),.lay_fault(lay_fault),.lay_error(lay_error),
  .direct_idle(direct_idle),.seq_active(seq_active)
`ifdef PATCHED
  ,.isolation_req(isolation_req),.requires_reset(requires_reset),
  .seq_dispatch_timeout(seq_dto),.seq_inflight_timeout(seq_ito),
  .fetch_timeout(fetch_to),.seq_wait_cycles(seq_wait_cycles),
  .seq_run_cycles(seq_run_cycles)
`endif
 );

 axi_dma_v019 sf_dma(
  .clk(clk),.rst_n(rst_n),.request_valid(sf_req_valid),.request_ready(sf_req_ready),
  .request_write(1'b0),.request_address(sf_address),.request_beats(sf_beats16),
  .read_valid(sf_read_valid),.read_ready(sf_read_ready),.read_data(sf_rdata_i),
  .read_index(sf_ridx16),.write_valid(1'b0),.write_ready(),.write_data(128'd0),
  .write_strobe(16'd0),.write_index(),.done(sf_done),.error(sf_err),
  .read_bytes(),.write_bytes(),.read_bursts(),.write_bursts(),
  .m_axi_araddr(m_araddr),.m_axi_arlen(m_arlen),.m_axi_arsize(m_arsize),
  .m_axi_arburst(m_arburst),.m_axi_arcache(),.m_axi_arprot(),
  .m_axi_arvalid(m_arvalid),.m_axi_arready(m_arready),
  .m_axi_rdata(m_rdata),.m_axi_rresp(m_rresp),.m_axi_rlast(m_rlast),
  .m_axi_rvalid(m_rvalid),.m_axi_rready(m_rready),
  .m_axi_awaddr(m_awaddr),.m_axi_awlen(m_awlen),.m_axi_awsize(m_awsize),
  .m_axi_awburst(m_awburst),.m_axi_awcache(),.m_axi_awprot(),
  .m_axi_awvalid(m_awvalid),.m_axi_awready(1'b0),.m_axi_wdata(m_wdata),
  .m_axi_wstrb(m_wstrb),.m_axi_wlast(m_wlast),.m_axi_wvalid(m_wvalid),
  .m_axi_wready(1'b0),.m_axi_bresp(2'd0),.m_axi_bvalid(1'b0),.m_axi_bready()
 );

 wc_safety_bfm bfm(
  .clk(clk),.rst_n(rst_n),
  .araddr(m_araddr),.arlen(m_arlen),.arsize(m_arsize),.arburst(m_arburst),
  .arvalid(m_arvalid),.arready(m_arready),
  .rdata(m_rdata),.rresp(m_rresp),.rlast(m_rlast),.rvalid(m_rvalid),.rready(m_rready),
  .awaddr(m_awaddr),.awlen(m_awlen),.awsize(m_awsize),.awburst(m_awburst),
  .awvalid(m_awvalid),.awready(m_awready),
  .wdata(m_wdata),.wstrb(m_wstrb),.wlast(m_wlast),.wvalid(m_wvalid),.wready(m_wready),
  .bresp(m_bresp),.bvalid(m_bvalid),.bready(m_bready),
  .read_bursts(),.write_bursts(),.read_beats(),.write_beats(),
  .held_r_bursts(),.held_b_bursts(),.returned_b(),.r_is_held(),.b_is_held()
 );

 // ---------------- stub children ----------------
 reg seq_ready_r=0,seq_done_r=0;
 reg seq_seen=0,seq_started=0;
 integer seq_ready_cnt=0,seq_run_cnt=0;
 integer seq_ready_delay=2,seq_done_delay=20;
 integer mode=0; // 0 healthy, 1 hang-wait, 2 hang-run
 always @(posedge clk) begin
  if(!rst_n) begin seq_ready_r<=0;seq_done_r<=0;seq_seen<=0;seq_started<=0;
   seq_ready_cnt<=0;seq_run_cnt<=0; end
  else begin
   seq_done_r<=0;
   if(seq_valid) begin
    if(!seq_seen)begin seq_seen<=1;seq_ready_cnt<=0;end
    if(mode==1)seq_ready_r<=0;
    else if(seq_ready_cnt<seq_ready_delay)begin seq_ready_cnt<=seq_ready_cnt+1;seq_ready_r<=0;end
    else seq_ready_r<=1;
   end else seq_ready_r<=0;
   if(seq_ready_r&&seq_valid&&!seq_started)begin seq_started<=1;seq_run_cnt<=0;end
   if(seq_started)begin
    if(mode==2)begin end
    else if(seq_run_cnt<seq_done_delay)seq_run_cnt<=seq_run_cnt+1;
    else begin seq_done_r<=1;seq_started<=0;end
   end
  end
 end
 assign seq_ready=seq_ready_r; assign seq_done=seq_done_r;
 assign seq_fault=1'b0; assign seq_error=8'd0;
 assign mat_ready=1'b1; assign mat_done=1'b0; assign mat_fault=1'b0;
 assign mat_error=8'd0;
 assign vec_ready=1'b1; assign vec_done=1'b0; assign vec_fault=1'b0;
 assign vec_error=8'd0;

 reg lay_busy=0,lay_done_r=0;
 integer lay_cnt=0,lay_delay=50;
 always @(posedge clk) begin
  if(!rst_n)begin lay_busy<=0;lay_done_r<=0;lay_cnt<=0;end
  else begin
   lay_done_r<=0;
   if(lay_valid&&lay_ready&&!lay_busy)begin lay_busy<=1;lay_cnt<=0;end
   else if(lay_busy)begin
    if(lay_cnt>=lay_delay)begin lay_busy<=0;lay_done_r<=1;end
    else lay_cnt<=lay_cnt+1;
   end
  end
 end
 assign lay_ready=!lay_busy; assign lay_done=lay_done_r;
 assign lay_fault=1'b0; assign lay_error=8'd0;

 integer cyc=0,timeout=40000,errors=0;
 integer ov_seq_lay=0,ov_seq_vec=0,ov_seq_mat=0,ov_seq_direct=0;
 integer seq_start_cycle=-1,lay_start_cycle=-1;
 integer expect_no_overlap=0,expect_iso=0,expect_fault=0;
 reg done_seen=0;
 always @(posedge clk) if(rst_n) begin
  if(done) done_seen<=1;
  if(ctrl.e_active[0])begin
   if(ctrl.e_active[3])ov_seq_lay<=ov_seq_lay+1;
   if(ctrl.e_active[2])ov_seq_vec<=ov_seq_vec+1;
   if(ctrl.e_active[1])ov_seq_mat<=ov_seq_mat+1;
   if(|ctrl.e_active[3:1])ov_seq_direct<=ov_seq_direct+1;
  end
  if(ctrl.e_active[0]&&seq_start_cycle<0)seq_start_cycle<=cyc;
  if(ctrl.e_active[3]&&lay_start_cycle<0)lay_start_cycle<=cyc;
 end

 reg [1023:0] memfile;
 initial begin
  if(!$value$plusargs("memfile=%s",memfile))memfile="fixtures/mutex_lay_first.hex";
  if(!$value$plusargs("watchdog=%d",timeout))timeout=40000;
  if(!$value$plusargs("mode=%d",mode))mode=0;
  if(!$value$plusargs("lay_delay=%d",lay_delay))lay_delay=50;
  if(!$value$plusargs("seq_done_delay=%d",seq_done_delay))seq_done_delay=20;
  if(!$value$plusargs("seq_ready_delay=%d",seq_ready_delay))seq_ready_delay=2;
  if(!$value$plusargs("expect_no_overlap=%d",expect_no_overlap))expect_no_overlap=0;
  if(!$value$plusargs("expect_iso=%d",expect_iso))expect_iso=0;
  if(!$value$plusargs("expect_fault=%d",expect_fault))expect_fault=0;
  rst_n=0; repeat(10)@(posedge clk); rst_n=1; repeat(3)@(posedge clk);
  @(posedge clk); start<=1; @(posedge clk); start<=0;
  while(!done_seen&&!fault&&cyc<timeout)@(posedge clk);
  repeat(5)@(posedge clk);
  $display("MUTEX_END done=%0d fault=%0d error=%02x busy=%0d seq_active=%0d ov_seq_lay=%0d ov_seq_vec=%0d ov_seq_mat=%0d ov_seq_direct=%0d seq_start=%0d lay_start=%0d cyc=%0d",
   done_seen,fault,error_code,busy,seq_active,ov_seq_lay,ov_seq_vec,ov_seq_mat,ov_seq_direct,
   seq_start_cycle,lay_start_cycle,cyc);
`ifdef PATCHED
  $display("MUTEX_ISO iso=%0d requires_reset=%0d seq_dto=%0d seq_ito=%0d fetch_to=%0d",
   isolation_req,requires_reset,seq_dto,seq_ito,fetch_to);
`endif
  if(!done_seen)begin $display("MUTEX_NO_TERMINAL"); errors=errors+1; end
  if(expect_fault && !fault)begin $display("MUTEX_FAULT_MISSING"); errors=errors+1; end
`ifdef PATCHED
  if(expect_iso && !isolation_req)begin $display("MUTEX_ISO_MISSING"); errors=errors+1; end
  if(expect_iso && !requires_reset)begin $display("MUTEX_RESET_MISSING"); errors=errors+1; end
`endif
  if(expect_no_overlap && ov_seq_direct!=0)begin
   $display("MUTEX_OVERLAP_VIOLATION seq_direct=%0d",ov_seq_direct); errors=errors+1;
  end
  if(cyc>=timeout)begin $display("MUTEX_TIMEOUT cyc=%0d",cyc); errors=errors+1; end
  if(errors)$display("MUTEX_RESULT FAIL");
  else $display("MUTEX_RESULT PASS");
  $finish;
 end
 always @(posedge clk) begin
  cyc<=cyc+1;
  if(cyc>timeout+1000)begin
   $display("MUTEX_GLOBAL_TIMEOUT cyc=%0d busy=%0d done=%0d fault=%0d",cyc,busy,done,fault);
   $finish;
  end
 end
endmodule
