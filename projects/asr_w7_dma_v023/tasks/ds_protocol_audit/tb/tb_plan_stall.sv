`timescale 1ns/1ps
// Does the plan watchdog actually bound completion when an AXI child or an
// operator never drains? WATCHDOG is shrunk to 16 cycles for observation.
// Phase1: AR accepted, R channel never returns -> plan FETCH.
// Phase2: instruction valid, matrix operator never asserts done -> ERROR_DRAIN.
// Phase3: same but operator completes -> control-path sanity (not arithmetic).
module tb_plan_stall;
 reg clk=0;always #4 clk=~clk;
 reg rst_n=0,start=0;
 reg [31:0] plan_base=32'h10000000,plan_count=1,param_end=32'h20000000,generation=32'h101;
 reg parameter_ready=1;
 wire busy,done,fault,irq;wire [7:0] error_code;wire [31:0] completed,index,rejected_starts,last_ticket;
 wire [63:0] cycles,fetch_cycles,operator_cycles;
 wire dma_req_valid,dma_req_ready,dma_read_valid,dma_read_ready,dma_done,dma_error;
 wire [31:0] dma_address;wire [15:0] dma_beats,dma_read_index;wire [127:0] dma_read_data;
 wire matrix_valid,matrix_ready,matrix_done;wire [31:0] matrix_queue_base,matrix_queue_count;assign matrix_ready=1;
 wire vector_valid,vector_ready;wire [511:0] vector_descriptor;assign vector_ready=0;
 wire layout_valid,layout_ready;wire [1023:0] layout_descriptor;assign layout_ready=0;
 wire vector_done,vector_fault,layout_done,layout_fault,matrix_fault;
 assign vector_done=0;assign vector_fault=0;assign layout_done=0;assign layout_fault=0;assign matrix_fault=0;
 pl_execution_plan_v022 #(.WATCHDOG(64'd400)) dut(
  .clk(clk),.rst_n(rst_n),.start(start),.plan_base(plan_base),.plan_count(plan_count),.param_end(param_end),
  .parameter_ready(parameter_ready),.generation(generation),
  .busy(busy),.done(done),.fault(fault),.error_code(error_code),.completed(completed),.index(index),
  .rejected_starts(rejected_starts),.last_ticket(last_ticket),.cycles(cycles),.fetch_cycles(fetch_cycles),
  .operator_cycles(operator_cycles),.irq(irq),
  .dma_request_valid(dma_req_valid),.dma_request_ready(dma_req_ready),.dma_address(dma_address),.dma_beats(dma_beats),
  .dma_read_valid(dma_read_valid),.dma_read_ready(dma_read_ready),.dma_read_data(dma_read_data),.dma_read_index(dma_read_index),
  .dma_done(dma_done),.dma_error(dma_error),
  .matrix_valid(matrix_valid),.matrix_ready(matrix_ready),.matrix_queue_base(matrix_queue_base),.matrix_queue_count(matrix_queue_count),
  .matrix_done(matrix_done),.matrix_fault(matrix_fault),
  .vector_valid(vector_valid),.vector_ready(vector_ready),.vector_descriptor(vector_descriptor),.vector_done(vector_done),.vector_fault(vector_fault),
  .layout_valid(layout_valid),.layout_ready(layout_ready),.layout_descriptor(layout_descriptor),.layout_done(layout_done),.layout_fault(layout_fault));
 wire [39:0] ar_a;wire [7:0] ar_l;wire [2:0] ar_s;wire [1:0] ar_b;wire ar_v,ar_r;
 wire [127:0] r_d;wire [1:0] r_r;wire r_last,r_v,r_ready;
 wire [39:0] aw_a;wire [7:0] aw_l;wire [2:0] aw_s;wire [1:0] aw_b;wire aw_v,aw_r;
 wire [127:0] w_d;wire [15:0] w_s;wire w_last,w_v,w_ready;
 wire [1:0] b_r;wire b_v,b_ready;
 axi_dma_v019 dma(.clk(clk),.rst_n(rst_n),
  .request_valid(dma_req_valid),.request_ready(dma_req_ready),.request_write(1'b0),
  .request_address(dma_address),.request_beats(dma_beats),
  .read_valid(dma_read_valid),.read_ready(dma_read_ready),.read_data(dma_read_data),.read_index(dma_read_index),
  .write_valid(1'b0),.write_ready(),.write_data(128'd0),.write_strobe(16'd0),.write_index(),
  .done(dma_done),.error(dma_error),.read_bytes(),.write_bytes(),.read_bursts(),.write_bursts(),
  .m_axi_araddr(ar_a),.m_axi_arlen(ar_l),.m_axi_arsize(ar_s),.m_axi_arburst(ar_b),.m_axi_arcache(),.m_axi_arprot(),
  .m_axi_arvalid(ar_v),.m_axi_arready(ar_r),.m_axi_rdata(r_d),.m_axi_rresp(r_r),.m_axi_rlast(r_last),
  .m_axi_rvalid(r_v),.m_axi_rready(r_ready),
  .m_axi_awaddr(aw_a),.m_axi_awlen(aw_l),.m_axi_awsize(aw_s),.m_axi_awburst(aw_b),.m_axi_awcache(),.m_axi_awprot(),
  .m_axi_awvalid(aw_v),.m_axi_awready(aw_r),.m_axi_wdata(w_d),.m_axi_wstrb(w_s),.m_axi_wlast(w_last),
  .m_axi_wvalid(w_v),.m_axi_wready(w_ready),.m_axi_bresp(b_r),.m_axi_bvalid(b_v),.m_axi_bready(b_ready));
 reg stall_r=0;
 wire inject_read_error=0,inject_write_error=0;
 axi128_stress_bfm #(.PORTS(1)) ddr(
  .clk(clk),.rst_n(rst_n),.araddr(ar_a),.arlen(ar_l),.arsize(ar_s),.arburst(ar_b),
  .arvalid(ar_v),.arready(ar_r),.rdata(r_d),.rresp(r_r),.rlast(r_last),.rvalid(r_v),.rready(r_ready),
  .awaddr(aw_a),.awlen(aw_l),.awsize(aw_s),.awburst(aw_b),.awvalid(aw_v),.awready(aw_r),
  .wdata(w_d),.wstrb(w_s),.wlast(w_last),.wvalid(w_v),.wready(w_ready),
  .bresp(b_r),.bvalid(b_v),.bready(b_ready),
  .inject_read_error(inject_read_error),.inject_write_error(inject_write_error),.stall_r(stall_r),
  .read_bursts(),.write_bursts(),.read_beats(),.write_beats());
 reg [511:0] instr;
 reg [3:0] mcount=0;reg md=0;reg op_stall=1;
 assign matrix_done=md;
 always @(posedge clk)begin
  md<=0;
  if(!op_stall&&matrix_valid&&matrix_ready&&mcount==0)mcount<=4;
  else if(mcount!=0)begin if(mcount==1)begin md<=1;mcount<=0;end else mcount<=mcount-1;end
 end
 task do_start;begin @(negedge clk);start=1;@(negedge clk);start=0;end endtask
 task do_reset;begin
  rst_n=0;stall_r=0;start=0;mcount=0;
  repeat(5)@(negedge clk);rst_n=1;repeat(2)@(negedge clk);
 end endtask
 integer i,cy;
 initial begin : gtimeout
  repeat(30000)@(posedge clk);
  $display("PLAN_TIMEOUT busy=%0d done=%0d state=%0d",busy,done,dut.state);$fflush();$finish;
 end
 initial begin
  instr=512'd0;
  instr[31:0]=32'h22504c4e;instr[63:32]=1;instr[95:64]=1;instr[127:96]=32'hffffffff;
  instr[159:128]=32'h03000000;instr[191:160]=1;
  for(i=0;i<64;i=i+1)ddr.memory[196608+i]=instr[i*8+:8];
  // ---- phase 1: AR accepted, R never returns ----
  do_reset;
  stall_r=1;
  do_start;
  repeat(1000)@(posedge clk);
  $display("PHASE1_R_STALL busy=%0d done=%0d fault=%0d err=%h plan_state=%0d wait=%0d dma_state=%0d bfm_ra=%0d",
   busy,done,fault,error_code,dut.state,dut.wait_cycles,dma.state,ddr.ra[0]);$fflush();
  if(busy!==1||done!==0||fault!==0||error_code!==8'h09||dut.wait_cycles<400)
   $display("PHASE1_UNEXPECTED");$fflush();
  // ---- phase 2: instruction fetched, operator never done ----
  do_reset;
  stall_r=0;op_stall=1;
  do_start;
  for(cy=0;cy<3000;cy=cy+1)begin
   @(posedge clk);
   if(cy%200==0)$display("P2MON cy=%0d state=%0d busy=%0d fault=%0d err=%h dma_done=%0d rdvalid=%0d req=%0d dma_state=%0d",
     cy,dut.state,busy,fault,error_code,dma_done,dma_read_valid,dma_req_valid,dma.state);
   if(cy%200==0)$display("   BFM cyc=%0d ra=%0d vis=%0d rng=%h arv=%0d arr=%0d stall=%0d rst=%0d",ddr.cycle,ddr.ra[0],ddr.visible[0],ddr.lfsr,ar_v,ar_r,stall_r,rst_n);$fflush();
   if(matrix_valid)cy=5000;
  end
  repeat(600)@(posedge clk);
  $display("PHASE2_OP_STALL busy=%0d done=%0d fault=%0d err=%h plan_state=%0d wait=%0d completed=%0d",
   busy,done,fault,error_code,dut.state,dut.wait_cycles,completed);$fflush();
  if(busy!==1||done!==0||fault!==1||error_code!==8'h09||dut.state!==10)
   $display("PHASE2_UNEXPECTED");$fflush();
  // ---- phase 3: operator completes: control path sanity ----
  do_reset;
  stall_r=0;op_stall=0;
  do_start;
  wait(done);@(negedge clk);
  $display("PHASE3_DONE busy=%0d done=%0d fault=%0d err=%h completed=%0d",busy,done,fault,error_code,completed);$fflush();
  if(done!==1||fault!==0||completed!==1)$display("PHASE3_UNEXPECTED");$fflush();
  $display("PLAN_STALL_TEST_END");$fflush();
  $finish;
 end
endmodule
