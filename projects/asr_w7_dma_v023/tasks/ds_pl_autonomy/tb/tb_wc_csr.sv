`timescale 1ns/1ps
// AXI-Lite unit test for wc_plan_csr: independent AW/W, START guard, sticky
// DONE/IRQ, readback and error responses.  Status inputs are static test regs;
// this is control evidence, not an arithmetic test.
module tb_wc_csr;
 reg clk=0;always #4 clk=~clk;
 reg rst_n=0;
 reg [23:0] awaddr=0;reg awvalid=0;wire awready;
 reg [31:0] wdata=0;reg [3:0] wstrb=15;reg wvalid=0;wire wready;
 wire [1:0] bresp;wire bvalid;reg bready=1;
 reg [23:0] araddr=0;reg arvalid=0;wire arready;
 wire [31:0] rdata;wire [1:0] rresp;wire rvalid;reg rready=1;
 wire [31:0] plan_base;wire start;reg parameter_ready=1;
 reg busy=0,done=0,fault=0;reg [7:0] error_code=0;
 reg [31:0] completed=0,node_count=9,last_node=8,rejected=0;
 reg [127:0] done_mask=128'h0;
 reg [63:0] cycles=0,fetch=0,operator=0,drain=0;reg drain_timeout=0;
 reg [31:0] generation=7,param_end=32'h10040000;
 wire irq;
 integer starts=0,checks=0;
 wc_plan_csr dut(.clk(clk),.rst_n(rst_n),
  .s_axi_awaddr(awaddr),.s_axi_awvalid(awvalid),.s_axi_awready(awready),
  .s_axi_wdata(wdata),.s_axi_wstrb(wstrb),.s_axi_wvalid(wvalid),.s_axi_wready(wready),
  .s_axi_bresp(bresp),.s_axi_bvalid(bvalid),.s_axi_bready(bready),
  .s_axi_araddr(araddr),.s_axi_arvalid(arvalid),.s_axi_arready(arready),
  .s_axi_rdata(rdata),.s_axi_rresp(rresp),.s_axi_rvalid(rvalid),.s_axi_rready(rready),
  .plan_base(plan_base),.start(start),.parameter_ready(parameter_ready),
  .busy(busy),.done(done),.fault(fault),.error_code(error_code),.completed(completed),
  .node_count(node_count),.last_node(last_node),.rejected_starts(rejected),.done_mask(done_mask),
  .cycles(cycles),.fetch_cycles(fetch),.operator_cycles(operator),.drain_cycles(drain),
  .drain_timeout(drain_timeout),.generation(generation),.param_end(param_end),.irq(irq));
 always @(posedge clk)if(rst_n&&start)starts<=starts+1;
 task check(input c,input [255:0] msg);begin
  checks=checks+1;if(!c)$fatal(1,"check failed: %0s",msg);
 end endtask
 task write(input [23:0] a,input [31:0] d,input [3:0] st,input [1:0] er);begin
  while(bvalid)@(negedge clk);
  awaddr=a;awvalid=1;wdata=d;wstrb=st;wvalid=1;
  @(posedge clk);@(negedge clk);awvalid=0;wvalid=0;
  while(!bvalid)@(negedge clk);
  check(bresp==er,"write BRESP");@(negedge clk);
 end endtask
 task read(input [23:0] a,input [1:0] er,output [31:0] d);begin
  while(rvalid)@(negedge clk);
  araddr=a;arvalid=1;
  @(posedge clk);@(negedge clk);arvalid=0;
  while(!rvalid)@(negedge clk);
  d=rdata;check(rresp==er,"read RRESP");@(negedge clk);
 end endtask
 reg [31:0] d;
 initial begin
  repeat(3)@(negedge clk);rst_n=1;repeat(2)@(negedge clk);
  read(0,0,d);check(d==32'h57434353,"magic");
  read(96,0,d);check(d==32'h00010001,"version");
  write(8,32'h10030000,15,0);check(plan_base==32'h10030000,"base write");
  read(8,0,d);check(d==32'h10030000,"base read");
  // START without parameter ready is rejected.
  parameter_ready=0;write(16,1,15,2);check(starts==0,"guard start");
  parameter_ready=1;write(16,1,15,0);@(negedge clk);check(starts==1,"start pulse");
  // START while busy is rejected and does not pulse again.
  busy=1;write(16,1,15,2);@(negedge clk);check(starts==1,"busy start reject");
  read(4,0,d);check(d[0]==1&&d[1]==0&&d[2]==0,"busy status");
  // DONE sticky and IRQ.
  done=1;@(negedge clk);done=0;@(negedge clk);
  read(4,0,d);check(d[1]==1,"done sticky");check(irq==1,"irq sticky");
  // WSTRB and unknown offsets are SLVERR.
  write(8,32'hdeadbeef,1,2);check(plan_base==32'h10030000,"wstrb reject");
  write(24,0,15,2);check(1,"offset reject");
  read(256,2,d);check(1,"read offset reject");
  // Clear sticky, then a new START is accepted.
  write(16,2,15,0);check(irq==0,"clear sticky");
  busy=0;write(16,1,15,0);@(negedge clk);check(starts==2,"second start");
  // Status fields are visible.
  completed=9;last_node=8;fault=1;error_code=8'h55;done_mask=128'h1ff;
  read(20,0,d);check(d==9,"completed read");
  read(24,0,d);check(d==8,"last node read");
  read(28,0,d);check(d==32'h55,"error read");
  read(44,0,d);check(d==32'h1ff,"done mask read");
  read(0,0,d);check(d==32'h57434353,"magic final");
  $display("WC_CSR_PASS checks=%0d starts=%0d",checks,starts);
  $finish;
 end
endmodule
