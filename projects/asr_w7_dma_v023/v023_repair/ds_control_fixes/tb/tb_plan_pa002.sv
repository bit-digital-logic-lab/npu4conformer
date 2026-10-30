`timescale 1ns/1ps
// PA-002 regression: bounded fetch/operator error handling.
//
// The AXI slave can (a) answer immediately, (b) accept AR and answer late,
// (c) accept AR and never answer.  The child model can complete normally,
// complete late, only assert child_drained, report a fault, or never respond.
// A dead child/slave must end in a fault + isolation_req with drained=0, never
// in a fake "safe drain"; a late response must drain and finish with drained=1.
module tb_plan_pa002;
 reg clk=0;always #4 clk=~clk;
 reg rst_n=0,start=0;
 reg [31:0] plan_base=32'h10000000,plan_count=1,param_end=32'h20000000,generation=32'h101;
 reg parameter_ready=1;
 wire busy,done,fault,irq;wire [7:0] error_code;
 wire [31:0] completed,index,rejected_starts,last_ticket;
 wire [63:0] cycles,fetch_cycles,operator_cycles,drain_cycles;
 wire dma_req_valid,dma_req_ready,dma_read_valid,dma_read_ready,dma_done,dma_error;
 wire [31:0] dma_address;wire [15:0] dma_beats,dma_read_index;wire [127:0] dma_read_data;
 wire matrix_valid,matrix_ready,matrix_done,matrix_fault;
 wire [31:0] matrix_queue_base,matrix_queue_count;
 wire vector_valid,vector_ready;wire [511:0] vector_descriptor;
 wire layout_valid,layout_ready;wire [1023:0] layout_descriptor;
 wire child_abort,dma_abort,drain_timeout,isolation_req,drained,unsafe_state;
 wire child_drained;
 wire [3:0] state_code;
 reg force_req_block=0;
 wire dma_req_ready_eff=force_req_block?1'b0:dma_req_ready;
 wire dma_req_valid_eff=force_req_block?1'b0:dma_req_valid;
 assign matrix_ready=1;assign vector_ready=0;
 assign vector_done=0;assign vector_fault=0;
 assign layout_done=0;assign layout_fault=0;

 pl_execution_plan_v023 #(.WATCHDOG(64'd64),.DRAIN_WATCHDOG(64'd160)) dut(
  .clk(clk),.rst_n(rst_n),.start(start),.plan_base(plan_base),.plan_count(plan_count),.param_end(param_end),
  .parameter_ready(parameter_ready),.generation(generation),
  .busy(busy),.done(done),.fault(fault),.error_code(error_code),.completed(completed),.index(index),
  .rejected_starts(rejected_starts),.last_ticket(last_ticket),.cycles(cycles),.fetch_cycles(fetch_cycles),
  .operator_cycles(operator_cycles),.drain_cycles(drain_cycles),.irq(irq),
  .dma_request_valid(dma_req_valid),.dma_request_ready(dma_req_ready_eff),.dma_address(dma_address),.dma_beats(dma_beats),
  .dma_read_valid(dma_read_valid),.dma_read_ready(dma_read_ready),.dma_read_data(dma_read_data),.dma_read_index(dma_read_index),
  .dma_done(dma_done),.dma_error(dma_error),
  .matrix_valid(matrix_valid),.matrix_ready(matrix_ready),.matrix_queue_base(matrix_queue_base),.matrix_queue_count(matrix_queue_count),
  .matrix_done(matrix_done),.matrix_fault(matrix_fault),
  .vector_valid(vector_valid),.vector_ready(vector_ready),.vector_descriptor(vector_descriptor),.vector_done(vector_done),.vector_fault(vector_fault),
  .layout_valid(layout_valid),.layout_ready(layout_ready),.layout_descriptor(layout_descriptor),.layout_done(layout_done),.layout_fault(layout_fault),
  .child_abort(child_abort),.child_drained(child_drained),.dma_abort(dma_abort),
  .drain_timeout(drain_timeout),.isolation_req(isolation_req),.drained(drained),
  .unsafe_state(unsafe_state),.state_code(state_code));

 // ---------------- real DMA under test (bounded v023) ----------------
 wire [39:0] ar_a;wire [7:0] ar_l;wire [2:0] ar_s;wire [1:0] ar_b;wire ar_v,ar_r;
 wire [127:0] r_d;wire [1:0] r_r;wire r_last,r_v,r_ready;
 wire [39:0] aw_a;wire [7:0] aw_l;wire [2:0] aw_s;wire [1:0] aw_b;wire aw_v,aw_r;
 wire [127:0] w_d;wire [15:0] w_s;wire w_last,w_v,w_ready;
 wire [1:0] b_r;wire b_v,b_ready;
 wire dma_busy,dma_aborted,dma_drained;
 axi_dma_v023_bounded dma(.clk(clk),.rst_n(rst_n),
  .request_valid(dma_req_valid_eff),.request_ready(dma_req_ready),.request_write(1'b0),
  .request_address(dma_address),.request_beats(dma_beats),
  .read_valid(dma_read_valid),.read_ready(dma_read_ready),.read_data(dma_read_data),.read_index(dma_read_index),
  .write_valid(1'b0),.write_ready(),.write_data(128'd0),.write_strobe(16'd0),.write_index(),
  .done(dma_done),.error(dma_error),.read_bytes(),.write_bytes(),.read_bursts(),.write_bursts(),
  .abort(dma_abort),.aborted(dma_aborted),.drained(dma_drained),.busy(dma_busy),
  .m_axi_araddr(ar_a),.m_axi_arlen(ar_l),.m_axi_arsize(ar_s),.m_axi_arburst(ar_b),.m_axi_arcache(),.m_axi_arprot(),
  .m_axi_arvalid(ar_v),.m_axi_arready(ar_r),.m_axi_rdata(r_d),.m_axi_rresp(r_r),.m_axi_rlast(r_last),
  .m_axi_rvalid(r_v),.m_axi_rready(r_ready),
  .m_axi_awaddr(aw_a),.m_axi_awlen(aw_l),.m_axi_awsize(aw_s),.m_axi_awburst(aw_b),.m_axi_awcache(),.m_axi_awprot(),
  .m_axi_awvalid(aw_v),.m_axi_awready(1'b0),.m_axi_wdata(w_d),.m_axi_wstrb(w_s),.m_axi_wlast(w_last),
  .m_axi_wvalid(w_v),.m_axi_wready(1'b0),.m_axi_bresp(b_r),.m_axi_bvalid(1'b0),.m_axi_bready());

 // ---------------- read-only AXI slave ----------------
 localparam S_IDLE=0,S_WAIT=1,S_SEND=2;
 reg [1:0] sstate=0;
 reg [39:0] sar=0;reg [15:0] sbeats=0,scnt=0,swait=0;
 reg [2:0] smode=0; // 0 immediate, 1 late, 2 dead
 integer late_cycles=0;
 reg [1:0] rresp_r;
 assign r_r=rresp_r;
 reg [127:0] plan_words[0:3];
 wire [31:0] eff_addr=sar[31:0]+({16'd0,scnt}<<4);
 reg [127:0] rdata_c;
 always @* begin
  if(eff_addr>=32'h10000000&&eff_addr<32'h10000040)rdata_c=plan_words[(eff_addr-32'h10000000)>>4];
  else rdata_c=128'd0;
 end
 assign ar_r=(sstate==S_IDLE);
 assign r_v=(sstate==S_SEND);
 assign r_d=rdata_c;
 assign r_last=(sstate==S_SEND)&&(scnt+1==sbeats);
 // B side tied off
 assign b_v=1'b0;assign b_r=2'd0;
 always @(posedge clk)begin
  if(!rst_n)begin
   sstate<=S_IDLE;sar<=0;sbeats<=0;scnt<=0;swait<=0;rresp_r<=0;
  end else begin
   case(sstate)
    S_IDLE:if(ar_v&&ar_r)begin
     sar<=ar_a;sbeats<={8'd0,ar_l}+16'd1;scnt<=0;rresp_r<=0;
     if(smode==2)begin swait<=16'hffff;sstate<=S_WAIT;end
     else if(late_cycles==0)sstate<=S_SEND;
     else begin swait<=late_cycles[15:0];sstate<=S_WAIT;end
    end
    S_WAIT:if(smode!=2)begin
     if(swait==0)sstate<=S_SEND;else swait<=swait-1;
    end
    S_SEND:if(r_v&&r_ready)begin
     if(scnt+1==sbeats)sstate<=S_IDLE;else scnt<=scnt+1;
    end
   endcase
  end
 end

 // ---------------- matrix child model ----------------
 localparam C_NORMAL=0,C_LATE=1,C_DRAINONLY=2,C_DEAD=3,C_FAULT=4;
 reg [2:0] cmode=0;integer clate=0;
 reg cactive=0;reg [31:0] ccnt=0;
 reg md=0,cd=0,mf=0;
 assign matrix_done=md;assign matrix_fault=mf;assign child_drained=cd;
 always @(posedge clk)begin
  if(!rst_n)begin cactive<=0;ccnt<=0;md<=0;cd<=0;mf<=0;end
  else begin
   md<=0;cd<=0;mf<=0;
   if(matrix_valid&&matrix_ready)begin cactive<=1;ccnt<=0;end
   else if(cactive)begin
    ccnt<=ccnt+1;
    case(cmode)
     C_NORMAL:if(ccnt>=2)begin md<=1;cactive<=0;end
     C_LATE:if(ccnt>=clate)begin md<=1;cd<=1;cactive<=0;end
     C_DRAINONLY:if(ccnt>=clate)begin cd<=1;cactive<=0;end
     C_DEAD:;
     C_FAULT:if(ccnt>=2)begin md<=1;mf<=1;cactive<=0;end
    endcase
   end
  end
 end

 integer errors=0,elapsed=0,saw_abort=0,saw_isolation_before_done=0;
 task chk(input [255:0] what,input cond);begin if(!cond)begin errors=errors+1;$display("FAIL %0s",what);$fflush();end end endtask
 task do_reset;begin
  rst_n=0;start=0;force_req_block=0;smode=0;late_cycles=0;cmode=C_NORMAL;clate=0;
  repeat(5)@(negedge clk);rst_n=1;repeat(2)@(negedge clk);
 end endtask
 task do_start;begin @(negedge clk);start=1;@(negedge clk);start=0;end endtask
 // Wait for done or max cycles; returns elapsed and observes abort flags.
 task wait_done(input integer maxc);
  begin
   elapsed=0;saw_abort=0;saw_isolation_before_done=0;
   while(!done&&elapsed<maxc)begin
    @(posedge clk);elapsed=elapsed+1;
    if(dma_abort||child_abort)saw_abort=1;
    if(isolation_req&&!done)saw_isolation_before_done=1;
   end
  end
 endtask
 task wait_state(input [3:0] st,input integer maxc);
  begin
   elapsed=0;
   while(state_code!=st&&elapsed<maxc)begin @(posedge clk);elapsed=elapsed+1;end
  end
 endtask
 reg [63:0] t_cycles;
 initial begin
  // plan: kind=1 MAT, one queue descriptor at ARENA base.
  plan_words[0]=128'h00000001000000010000000022504c4e;
  plan_words[1]=128'h00000000000000000000000003000000;
  plan_words[2]=128'h0;
  plan_words[3]=128'h0;
  // Actually place fields explicitly (little-endian words).
  begin : setplan
   integer w;
   reg [511:0] instr;
   instr=0;
   instr[31:0]=32'h22504c4e;instr[63:32]=32'd1;instr[95:64]=32'd1;
   instr[127:96]=32'hffffffff;instr[159:128]=32'h03000000;instr[191:160]=32'd1;
   for(w=0;w<4;w=w+1)plan_words[w]=instr[w*128+:128];
  end

  // ---------- normal ----------
  do_reset;smode=0;cmode=C_NORMAL;do_start;wait_done(2000);
  $display("P_NORMAL done=%0d fault=%0d err=%h completed=%0d drained=%0d iso=%0d cyc=%0d",done,fault,error_code,completed,drained,isolation_req,elapsed);
  chk("normal done",done==1);chk("normal no fault",fault==0);chk("normal completed",completed==1);
  chk("normal drained",drained==1);chk("normal no isolation",isolation_req==0);

  // ---------- dead read: AR accepted, no R ----------
  do_reset;smode=2;cmode=C_NORMAL;do_start;
  wait_state(4'd9,1000); // DRAIN
  $display("P_DEAD_READ drain state=%0d dma_abort=%0d child_abort=%0d cyc=%0d",state_code,dma_abort,child_abort,elapsed);
  chk("dead read entered DRAIN",state_code==4'd9);chk("dead read dma_abort",dma_abort==1);
  wait_done(2000);
  $display("P_DEAD_READ_RESULT done=%0d fault=%0d err=%h drained=%0d iso=%0d timeout=%0d cyc=%0d",done,fault,error_code,drained,isolation_req,drain_timeout,elapsed);
  chk("dead read done",done==1);chk("dead read fault",fault==1);chk("dead read error 0A",error_code==8'h0A);
  chk("dead read not drained",drained==0);chk("dead read isolation",isolation_req==1);
  chk("dead read drain_timeout",drain_timeout==1);
  // START while isolation must be rejected and must not run.
  t_cycles=cycles;do_start;repeat(5)@(negedge clk);
  chk("isolation START rejected",busy==0&&rejected_starts!=0);
  $display("P_ISOLATION_START busy=%0d rejected=%0d",busy,rejected_starts);

  // ---------- recovery after reset ----------
  do_reset;smode=0;cmode=C_NORMAL;do_start;wait_done(2000);
  $display("P_RECOVER done=%0d fault=%0d completed=%0d drained=%0d iso=%0d",done,fault,completed,drained,isolation_req);
  chk("recover done",done==1&&fault==0&&completed==1&&isolation_req==0);

  // ---------- late R drains safely ----------
  do_reset;smode=1;late_cycles=110;cmode=C_NORMAL;do_start;wait_done(2000);
  $display("P_LATE_R done=%0d fault=%0d err=%h drained=%0d iso=%0d saw_abort=%0d cyc=%0d",done,fault,error_code,drained,isolation_req,saw_abort,elapsed);
  chk("late R done",done==1);chk("late R fault",fault==1);chk("late R err 09",error_code==8'h09);
  chk("late R drained",drained==1);chk("late R no isolation",isolation_req==0);
  chk("late R abort seen",saw_abort==1);

  // ---------- child never responds ----------
  do_reset;smode=0;cmode=C_DEAD;do_start;
  wait_state(4'd9,1000);
  $display("P_DEAD_CHILD drain state=%0d child_abort=%0d cyc=%0d",state_code,child_abort,elapsed);
  chk("dead child entered DRAIN",state_code==4'd9);chk("dead child abort",child_abort==1);
  wait_done(2000);
  $display("P_DEAD_CHILD_RESULT done=%0d fault=%0d err=%h drained=%0d iso=%0d timeout=%0d",done,fault,error_code,drained,isolation_req,drain_timeout);
  chk("dead child done",done==1);chk("dead child err 0A",error_code==8'h0A);
  chk("dead child not drained",drained==0);chk("dead child isolation",isolation_req==1);

  // ---------- child only drains late ----------
  do_reset;smode=0;cmode=C_DRAINONLY;clate=110;do_start;wait_done(2000);
  $display("P_LATE_DRAIN done=%0d fault=%0d err=%h drained=%0d iso=%0d cyc=%0d",done,fault,error_code,drained,isolation_req,elapsed);
  chk("late drain done",done==1);chk("late drain err 09",error_code==8'h09);
  chk("late drain drained",drained==1);chk("late drain no isolation",isolation_req==0);

  // ---------- child reports fault after done ----------
  do_reset;smode=0;cmode=C_FAULT;do_start;wait_done(2000);
  $display("P_CHILD_FAULT done=%0d fault=%0d err=%h drained=%0d iso=%0d",done,fault,error_code,drained,isolation_req);
  chk("child fault done",done==1);chk("child fault err 05",error_code==8'h05);
  chk("child fault drained",drained==1);chk("child fault no isolation",isolation_req==0);

  // ---------- generation/config change after START: no mixed snapshot ----------
  do_reset;generation=32'h101;smode=0;cmode=C_DRAINONLY;clate=40;do_start;
  wait(matrix_valid);wait_state(4'd8,100);@(negedge clk);generation=32'h102;
  wait_state(4'd9,200);
  $display("P_CFG_CHANGE drain state=%0d child_abort=%0d err=%h",state_code,child_abort,error_code);
  chk("cfg change enters DRAIN",state_code==4'd9);chk("cfg change child_abort",child_abort==1);
  chk("cfg change error 02",error_code==8'h02);
  wait_done(2000);
  $display("P_CFG_CHANGE_RESULT done=%0d fault=%0d err=%h drained=%0d iso=%0d",done,fault,error_code,drained,isolation_req);
  chk("cfg change fault 02",fault==1&&error_code==8'h02);
  chk("cfg change drained",drained==1);chk("cfg change no isolation",isolation_req==0);
  generation=32'h101;

  // ---------- request never accepted: safe bounded fault, no isolation ----------
  do_reset;force_req_block=1;do_start;wait_done(1000);
  $display("P_REQ_TIMEOUT done=%0d fault=%0d err=%h drained=%0d iso=%0d dma_busy=%0d",done,fault,error_code,drained,isolation_req,dma_busy);
  chk("req timeout done",done==1);chk("req timeout err 0B",error_code==8'h0B);
  chk("req timeout drained",drained==1);chk("req timeout no isolation",isolation_req==0);
  chk("req timeout no accepted DMA",dma_busy==0);

  $display("PA002_TEST_END errors=%0d",errors);$fflush();
  if(errors==0)$display("PA002_PASS");else $display("PA002_FAIL");
  $finish;
 end
 // global timeout
 initial begin repeat(60000)@(posedge clk);$display("PA002_GLOBAL_TIMEOUT state=%0d busy=%0d",state_code,busy);$finish;end
endmodule
