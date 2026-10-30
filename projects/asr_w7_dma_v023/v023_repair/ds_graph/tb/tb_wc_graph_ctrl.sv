`timescale 1ns/1ps
// Control-only tests for wc_graph_ctrl: real plan fetch from the BFM, real
// dependency/scoreboard/ACL/root-provenance logic, stub engines.  No matrix,
// vector or layout arithmetic is executed here; the real-chain arithmetic is
// in tb_wc_graph_real.
module tb_wc_graph_ctrl;
 reg clk=0;always #4 clk=~clk;
 reg rst_n=0,start=0,parameter_ready=1;
 reg [31:0] plan_base=32'h10008000,param_end=32'h10040000,generation=7;
 integer mode=0,cycle=0,done_pulses=0,expected=0,expect_fault=0,check_ret=0;
 reg [31:0] expected_err=0;
 wire busy,done,fault,irq,drain_timeout,output_retained;
 wire [7:0] error_code;
 wire [31:0] completed,node_count,rejected_starts,last_node;
 wire [1023:0] done_mask;
 wire [63:0] cycles,fetch_cycles,operator_cycles,drain_cycles;
 wire [31:0] output_count,last_output_tid,last_output_base,last_output_bytes;
 wire seq_valid,seq_ready,seq_done,seq_fault;
 wire [31:0] seq_base,seq_count;
 wire mat_valid,mat_ready,mat_done,mat_fault;
 wire [31:0] mat_base,mat_count;
 wire vec_valid,vec_ready,vec_done,vec_fault;
 wire [511:0] vec_descriptor;
 wire lay_valid,lay_ready,lay_done,lay_fault;
 wire [1023:0] lay_descriptor;
 wire direct_idle;
 wire [7:0] seq_error,mat_error,vec_error,lay_error;
 wire sf_req_valid,sf_req_ready,sf_read_valid,sf_read_ready,sf_done,sf_err;
 wire [31:0] sf_address;wire [7:0] sf_beats,sf_ridx;wire [15:0] sf_ridx16;wire [127:0] sf_rdata_i;
 wire [39:0] ar_awaddr;wire [7:0] ar_awlen;wire [2:0] ar_awsize;
 wire [1:0] ar_awburst;wire [3:0] ar_awcache;wire [2:0] ar_awprot;
 wire ar_awvalid,ar_awready,rvalid,rlast,rready;
 wire [127:0] rdata;wire [1:0] rresp;
 wire [39:0] awaddr;wire [7:0] awlen;wire [2:0] awsize;
 wire [1:0] awburst;wire [3:0] awcache;wire [2:0] awprot;
 wire awvalid,awready,wlast,wvalid,wready,bvalid,bready;
 wire [127:0] wdata;wire [15:0] wstrb;wire [1:0] bresp;
 wire [31:0] bfm_rb,bfm_wb,bfm_rbeats,bfm_wbeats;
 assign sf_ridx=sf_ridx16[7:0];

 reg seq_busy=0,mat_busy=0,vec_busy=0,lay_busy=0;
 assign seq_ready=!seq_busy;assign mat_ready=!mat_busy;
 assign vec_ready=!vec_busy;assign lay_ready=!lay_busy;
 reg [7:0] seq_t=0,mat_t=0,vec_t=0,lay_t=0;
 reg seq_done_r=0,mat_done_r=0,vec_done_r=0,lay_done_r=0;
 assign seq_done=seq_done_r;assign mat_done=mat_done_r;
 assign vec_done=vec_done_r;assign lay_done=lay_done_r;
 reg lay_fail=0;reg [7:0] lay_err=0;
 assign seq_fault=0;assign mat_fault=0;assign vec_fault=0;assign lay_fault=lay_fail;
 assign seq_error=0;assign mat_error=0;assign vec_error=0;assign lay_error=lay_err;

 wc_graph_ctrl #(.PARAM_BASE(32'h10000000),.PARAM_LIMIT(32'h40000000),
  .ARENA_BASE(32'h03000000),.ARENA_LIMIT(32'h08000000),
  .EXTERNAL_BASE(32'h08000000),.EXTERNAL_LIMIT(32'h10000000),
  .MAX_NODES(1024)) dut(
  .clk(clk),.rst_n(rst_n),.start(start),.plan_base(plan_base),.param_end(param_end),
  .parameter_ready(parameter_ready),.generation(generation),
  .busy(busy),.done(done),.fault(fault),.error_code(error_code),.completed(completed),
  .node_count(node_count),.rejected_starts(rejected_starts),.last_node(last_node),
  .done_mask(done_mask),.cycles(cycles),.fetch_cycles(fetch_cycles),
  .operator_cycles(operator_cycles),.drain_cycles(drain_cycles),.drain_timeout(drain_timeout),
  .irq(irq),.output_retained(output_retained),.output_count(output_count),
  .last_output_tid(last_output_tid),.last_output_base(last_output_base),
  .last_output_bytes(last_output_bytes),
  .fetch_req_valid(sf_req_valid),.fetch_req_ready(sf_req_ready),.fetch_address(sf_address),
  .fetch_beats(sf_beats),.fetch_read_valid(sf_read_valid),.fetch_read_ready(sf_read_ready),
  .fetch_read_data(sf_rdata_i),.fetch_read_index(sf_ridx),.fetch_done(sf_done),.fetch_error(sf_err),
  .seq_valid(seq_valid),.seq_ready(seq_ready),.seq_base(seq_base),.seq_count(seq_count),
  .seq_done(seq_done),.seq_fault(seq_fault),.seq_error(seq_error),
  .mat_valid(mat_valid),.mat_ready(mat_ready),.mat_base(mat_base),.mat_count(mat_count),
  .mat_done(mat_done),.mat_fault(mat_fault),.mat_error(mat_error),
  .vec_valid(vec_valid),.vec_ready(vec_ready),.vec_descriptor(vec_descriptor),
  .vec_done(vec_done),.vec_fault(vec_fault),.vec_error(vec_error),
  .lay_valid(lay_valid),.lay_ready(lay_ready),.lay_descriptor(lay_descriptor),
  .lay_done(lay_done),.lay_fault(lay_fault),.lay_error(lay_error),
  .direct_idle(direct_idle));

 axi_dma_v019 sf_dma(.clk(clk),.rst_n(rst_n),.request_valid(sf_req_valid),
  .request_ready(sf_req_ready),.request_write(1'b0),.request_address(sf_address),
  .request_beats({8'd0,sf_beats}),.read_valid(sf_read_valid),.read_ready(sf_read_ready),
  .read_data(sf_rdata_i),.read_index(sf_ridx16),.write_valid(1'b0),.write_ready(),
  .write_data(128'd0),.write_strobe(16'd0),.write_index(),.done(sf_done),.error(sf_err),
  .read_bytes(),.write_bytes(),.read_bursts(),.write_bursts(),
  .m_axi_araddr(ar_awaddr),.m_axi_arlen(ar_awlen),.m_axi_arsize(ar_awsize),
  .m_axi_arburst(ar_awburst),.m_axi_arcache(ar_awcache),.m_axi_arprot(ar_awprot),
  .m_axi_arvalid(ar_awvalid),.m_axi_arready(ar_awready),.m_axi_rdata(rdata),
  .m_axi_rresp(rresp),.m_axi_rlast(rlast),.m_axi_rvalid(rvalid),.m_axi_rready(rready),
  .m_axi_awaddr(awaddr),.m_axi_awlen(awlen),.m_axi_awsize(awsize),
  .m_axi_awburst(awburst),.m_axi_awcache(awcache),.m_axi_awprot(awprot),
  .m_axi_awvalid(awvalid),.m_axi_awready(awready),.m_axi_wdata(wdata),
  .m_axi_wstrb(wstrb),.m_axi_wlast(wlast),.m_axi_wvalid(wvalid),.m_axi_wready(wready),
  .m_axi_bresp(bresp),.m_axi_bvalid(bvalid),.m_axi_bready(bready));

 wc_graph_bfm #(.PORTS(1)) ddr(.clk(clk),.rst_n(rst_n),
  .araddr(ar_awaddr),.arlen(ar_awlen),.arsize(ar_awsize),
  .arburst(ar_awburst),.arvalid(ar_awvalid),.arready(ar_awready),
  .rdata(rdata),.rresp(rresp),.rlast(rlast),.rvalid(rvalid),.rready(rready),
  .awaddr(40'd0),.awlen(8'd0),.awsize(3'd0),.awburst(2'd0),.awvalid(1'b0),.awready(),
  .wdata(128'd0),.wstrb(16'd0),.wlast(1'b0),.wvalid(1'b0),.wready(),
  .bresp(),.bvalid(),.bready(1'b1),
  .inject_read_error(1'b0),.inject_write_error(1'b0),
  .read_bursts(bfm_rb),.write_bursts(bfm_wb),
  .read_beats(bfm_rbeats),.write_beats(bfm_wbeats));

 // Independent control stubs.  They complete in 2 cycles and never execute
 // arithmetic; the real chain is a separate testbench.
 always @(posedge clk)begin
  if(!rst_n)begin seq_busy<=0;mat_busy<=0;vec_busy<=0;lay_busy<=0;
   seq_done_r<=0;mat_done_r<=0;vec_done_r<=0;lay_done_r<=0;end
  else begin
   seq_done_r<=0;mat_done_r<=0;vec_done_r<=0;lay_done_r<=0;
   if(seq_valid&&seq_ready)begin seq_busy<=1;seq_t<=2;end
   else if(seq_busy)begin if(seq_t==0)begin seq_busy<=0;seq_done_r<=1;end else seq_t<=seq_t-1;end
   if(mat_valid&&mat_ready)begin mat_busy<=1;mat_t<=2;end
   else if(mat_busy)begin if(mat_t==0)begin mat_busy<=0;mat_done_r<=1;end else mat_t<=mat_t-1;end
   if(vec_valid&&vec_ready)begin vec_busy<=1;vec_t<=2;end
   else if(vec_busy)begin if(vec_t==0)begin vec_busy<=0;vec_done_r<=1;end else vec_t<=vec_t-1;end
   if(lay_valid&&lay_ready)begin lay_busy<=1;lay_t<=2;
    if(mode==8)begin lay_fail<=1;lay_err<=8'h55;end else begin lay_fail<=0;lay_err<=0;end end
   else if(lay_busy)begin if(lay_t==0)begin lay_busy<=0;lay_done_r<=1;end else lay_t<=lay_t-1;end
  end
 end

 integer i,cnt;
 initial begin
  if(!$value$plusargs("mode=%d",mode))mode=0;
  if(!$value$plusargs("plan=%h",plan_base))plan_base=32'h10008000;
  case(mode)
   0:begin plan_base=32'h10008000;expected=4;end
   1:begin plan_base=32'h10010000;expected=136;end
   2:begin plan_base=32'h10020000;expected=591;end
   3:begin plan_base=32'h1000a000;expected=0;expect_fault=1;expected_err=8'h08;end
   4:begin plan_base=32'h1000b000;expected=4;expect_fault=1;expected_err=8'h0a;end
   5:begin plan_base=32'h1000c000;expected=0;expect_fault=1;expected_err=8'h04;end
   6:begin plan_base=32'h1000d000;expected=0;expect_fault=1;expected_err=8'h04;end
   7:begin plan_base=32'h10008000;expected=4;check_ret=1;end
   8:begin plan_base=32'h10008000;expected=1;expect_fault=1;expected_err=8'h55;end
   default:begin plan_base=32'h10008000;expected=4;end
  endcase
  repeat(5)@(negedge clk);rst_n=1;
  if(check_ret)ddr.poke32(32'h40000+(32'h04002000-32'h04000000),32'hdeadbeef);
  repeat(2)@(negedge clk);start=1;@(negedge clk);start=0;
  if($test$plusargs("verbose"))$display("CTRL start plan=%h mode=%d",plan_base,mode);
  wait(done||cycle>2000000);
  @(negedge clk);@(negedge clk);
  if(cycle>2000000)$fatal(1,"timeout state=%d",dut.state);
  if(done_pulses!=1)$fatal(1,"done pulses=%d",done_pulses);
  if(busy||seq_busy||mat_busy||vec_busy||lay_busy)$fatal(1,"busy after done");
  if(irq!==1)$fatal(1,"irq not sticky");
  if(completed!==expected)$fatal(1,"completed=%d expected=%d",completed,expected);
  if(node_count==0)$fatal(1,"node_count zero");
  if(expect_fault)begin
   if(!fault||error_code!==expected_err)$fatal(1,"fault=%b err=%h expected %h",fault,error_code,expected_err);
   if(mode==8&&drain_cycles==0)$fatal(1,"child fault without drain cycles");
  end else begin
   if(fault)$fatal(1,"unexpected fault %h",error_code);
   if(output_count==0)$fatal(1,"no output flagged");
   if(!output_retained)$fatal(1,"output not retained");
  end
  cnt=0;for(i=0;i<1024;i=i+1)if(done_mask[i])cnt=cnt+1;
  if(cnt!==(mode==8?2:expected))$fatal(1,"done_mask pop=%d expected=%d",cnt,(mode==8?2:expected));
  if(check_ret)begin
   if(ddr.peek32(32'h40000+(32'h04002000-32'h04000000))!==32'hdeadbeef)
    $fatal(1,"output storage changed after done");
   if(last_output_base!==32'h04002000)$fatal(1,"last output base %h",last_output_base);
   if(last_output_bytes!==256)$fatal(1,"last output bytes %d",last_output_bytes);
  end
  if(mode==2)begin
   if(output_count!==1)$fatal(1,"ledger outputs=%d",output_count);
  end
  if(mode==1)begin
   if(output_count!==68)$fatal(1,"closed outputs=%d",output_count);
  end
  $display("WC_GRAPH_CTRL_PASS mode=%d plan=%h cycles=%d completed=%d nodes=%d err=%h fetch=%d drain=%d rb=%d rbeats=%d out_ret=%b out_count=%d last_out=%h/%d",
   mode,plan_base,cycles,completed,node_count,error_code,fetch_cycles,drain_cycles,bfm_rb,bfm_rbeats,
   output_retained,output_count,last_output_base,last_output_bytes);
  $finish;
 end
 always @(posedge clk)if(rst_n)begin cycle<=cycle+1;if(done)done_pulses<=done_pulses+1;end
endmodule
