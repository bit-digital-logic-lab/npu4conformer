`timescale 1ns/1ps
// AXI-Lite CSR readback audit: interleaved 64-bit halves, AW/W independence,
// B backpressure, invalid-strobe atomicity and busy START rejection.
module tb_csr_snapshot;
 reg clk=0;always #4 clk=~clk;
 reg rst_n=0;
 reg [23:0] awaddr=0;reg awvalid=0;wire awready;
 reg [31:0] wdata=0;reg [3:0] wstrb=0;reg wvalid=0;wire wready;
 wire [1:0] bresp;wire bvalid;reg bready=1;
 reg [23:0] araddr=0;reg arvalid=0;wire arready;
 wire [31:0] rdata;wire [1:0] rresp;wire rvalid;reg rready=1;
 wire start;wire [31:0] plan_base,plan_count;wire irq;
 integer errors=0;
 reg param_ready=1;reg busy=0,done=0,fault=0;reg [7:0] error_code=0;
 reg [31:0] completed=1,idx=2,rej=3,last_ticket=4;
 reg [63:0] cycles=64'h1122334455667788;
 reg [63:0] fcycles=64'hAABBCCDDEEFF0011;
 reg [63:0] ocycles=64'h0123456789ABCDEF;
 reg mdone=0;reg [63:0] mcycles=64'h1111222233334444,mpe=64'h5555666677778888;
 reg vdone=0,ldone=0;reg [7:0] vflags=0,verr=0,lerr=0;
 reg [63:0] vcycles=64'h9999AAAABBBBCCCC,lcycles=64'hDDDDEEEEFFFF0001;
 reg [63:0] rcov=64'h1234,wcov=64'h5678;
 reg [31:0] vrb=100,vwb=200,lrb=300,lwb=400;
 reg [31:0] velems=7,lelems=8,chits=9,cmiss=10;
 plan_submit_csr dut(.clk(clk),.rst_n(rst_n),
  .s_axi_awaddr(awaddr),.s_axi_awvalid(awvalid),.s_axi_awready(awready),
  .s_axi_wdata(wdata),.s_axi_wstrb(wstrb),.s_axi_wvalid(wvalid),.s_axi_wready(wready),
  .s_axi_bresp(bresp),.s_axi_bvalid(bvalid),.s_axi_bready(bready),
  .s_axi_araddr(araddr),.s_axi_arvalid(arvalid),.s_axi_arready(arready),
  .s_axi_rdata(rdata),.s_axi_rresp(rresp),.s_axi_rvalid(rvalid),.s_axi_rready(rready),
  .start(start),.plan_base(plan_base),.plan_count(plan_count),
  .parameter_ready(param_ready),.generation(32'h101),.param_end(32'h20000000),
  .busy(busy),.done(done),.fault(fault),.error_code(error_code),
  .completed(completed),.index(idx),.rejected_starts(rej),.last_ticket(last_ticket),
  .cycles(cycles),.fetch_cycles(fcycles),.operator_cycles(ocycles),
  .matrix_done(mdone),.matrix_cycles(mcycles),.matrix_pe_cycles(mpe),
  .vector_done(vdone),.layout_done(ldone),.vector_numeric_flags(vflags),
  .vector_error_code(verr),.layout_error_code(lerr),.vector_cycles(vcycles),.layout_cycles(lcycles),
  .vector_read_compute_overlap(rcov),.vector_write_compute_overlap(wcov),
  .vector_read_bytes(vrb),.vector_write_bytes(vwb),.layout_read_bytes(lrb),.layout_write_bytes(lwb),
  .vector_completed_elements(velems),.layout_processed_elements(lelems),.layout_cache_hits(chits),.layout_cache_misses(cmiss),
  .irq(irq));
 task chk(input [255:0] what,input cond);begin if(!cond)begin errors=errors+1;$display("FAIL %0s",what);$fflush();end end endtask
 reg [31:0] rdval;reg [1:0] rdresp;
 task lite_read(input [7:0] a);
  begin
   @(negedge clk);araddr=a;arvalid=1;
   while(!arready)@(negedge clk);
   @(posedge clk);@(negedge clk);arvalid=0;
   while(!rvalid)@(negedge clk);
   rdval=rdata;rdresp=rresp;
   @(posedge clk);@(negedge clk);
  end
 endtask
 reg [1:0] wrresp; reg start_seen;
 task lite_write(input [7:0] a,input [31:0] d,input [3:0] s);
  begin
   @(negedge clk);awaddr=a;awvalid=1;wdata=d;wstrb=s;wvalid=1;
   fork
    begin while(!awready)@(negedge clk);@(posedge clk);@(negedge clk);awvalid=0;end
    begin while(!wready)@(negedge clk);@(posedge clk);@(negedge clk);wvalid=0;end
   join
   while(!bvalid)@(negedge clk);
   wrresp=bresp;start_seen=start;@(posedge clk);@(negedge clk);
  end
 endtask
 reg [31:0] lo1,hi1,lo2,hi2,hi_bad,hi_good;
 initial begin
  repeat(4)@(negedge clk);rst_n=1;repeat(2)@(negedge clk);
  // ---- baseline halves ----
  lite_read(8'd32); lo1=rdval;
  lite_read(8'd36); hi1=rdval;
  lite_read(8'd48); lo2=rdval;
  lite_read(8'd52); hi2=rdval;
  $display("BASE cycles_lo=%h hi=%h fetch_lo=%h hi=%h",lo1,hi1,lo2,hi2);$fflush();
  chk("baseline cycles low",lo1==32'h55667788);
  chk("baseline cycles high",hi1==32'h11223344);
  chk("baseline fetch low",lo2==32'hEEFF0011);
  chk("baseline fetch high",hi2==32'hAABBCCDD);
  // ---- interleaved: low(cycles), low(fetch), high(cycles) ----
  lite_read(8'd32);
  lite_read(8'd48);
  lite_read(8'd36); hi_bad=rdval;
  $display("INTERLEAVED read32,read48,read36 -> %h (correct would be %h)",hi_bad,32'h11223344);$fflush();
  // read fetch high after re-reading its low
  lite_read(8'd48); lite_read(8'd52); hi_good=rdval;
  $display("FETCH high after own low -> %h",hi_good);$fflush();
  chk("fetch high still correct",hi_good==32'hAABBCCDD);
  if(hi_bad==32'hAABBCCDD)$display("CSR_SNAPSHOT_BUG_CONFIRMED");$fflush();
  if(hi_bad==32'h11223344)$display("CSR_SNAPSHOT_OK");$fflush();
  // ---- interleaved with operator ----
  lite_read(8'd56); lite_read(8'd64); lite_read(8'd60);
  $display("INTERLEAVED read56,read64,read60 -> %h (correct %h)",rdval,32'h01234567);$fflush();
  // ---- AW/W independent: W before AW (and BREADY held low) ----
  bready=0;
  @(negedge clk);wdata=32'hDEADBEEF;wstrb=4'hf;wvalid=1;
  while(!wready)@(negedge clk);@(posedge clk);@(negedge clk);wvalid=0;
  repeat(3)@(negedge clk);
  @(negedge clk);awaddr=8'd8;awvalid=1;
  while(!awready)@(negedge clk);@(posedge clk);@(negedge clk);awvalid=0;
  while(!bvalid)@(negedge clk);
  wrresp=bresp;
  repeat(4)@(negedge clk);
  bready=1;@(posedge clk);@(negedge clk);
  lite_read(8'd8);
  chk("plan_base from W-before-AW",rdval==32'hDEADBEEF);
  $display("W_BEFORE_AW plan_base=%h bresp=%0d",rdval,wrresp);$fflush();
  // ---- invalid strobe must not change plan_count ----
  lite_write(8'd12,32'hCAFEBABE,4'b0011);
  lite_read(8'd12);
  chk("bad strobe rejected",wrresp==2'b10 && rdval==0);
  $display("BAD_STROBE bresp=%0d plan_count=%h",wrresp,rdval);$fflush();
  // ---- START while busy rejected ----
  busy=1; lite_write(8'd16,32'd1,4'hf);
  @(negedge clk);
  chk("START while busy rejected",wrresp==2'b10 && start_seen==0);
  $display("BUSY_START bresp=%0d start=%0d",wrresp,start_seen);$fflush();
  busy=0;
  // ---- real START ----
  lite_write(8'd16,32'd1,4'hf);
  chk("START accepted",wrresp==0 && start_seen==1);
  $display("START_OK bresp=%0d start=%0d",wrresp,start_seen);$fflush();
  // ---- readback of constants ----
  lite_read(8'd0);chk("magic",rdval==32'hA51A22D0);
  lite_read(8'd20);chk("completed",rdval==1);
  lite_read(8'd148);chk("generation",rdval==32'h101);
  if(errors==0)$display("CSR_BASELINE_PASS");$fflush();
  $finish;
 end
endmodule
