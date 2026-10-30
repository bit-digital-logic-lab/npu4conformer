`timescale 1ns/1ps
// PA-001 regression: interleaved 64-bit CSR readback.
// Compile with -DDUT_V023 to select the fixed CSR; without it, the original
// plan_submit_csr is exercised and the interleaved cases are expected to fail.
module tb_csr_pa001;
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
 reg [63:0] rcov=64'h0000000012345678,wcov=64'h000000009ABCDEF0;
 reg [31:0] vrb=100,vwb=200,lrb=300,lwb=400;
 reg [31:0] velems=7,lelems=8,chits=9,cmiss=10;

`ifdef DUT_V023
 plan_submit_csr_v023 dut(.clk(clk),.rst_n(rst_n),
`else
 plan_submit_csr dut(.clk(clk),.rst_n(rst_n),
`endif
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
   @(negedge clk);araddr={16'd0,a};arvalid=1;
   while(!arready)@(negedge clk);
   @(posedge clk);@(negedge clk);arvalid=0;
   while(!rvalid)@(negedge clk);
   rdval=rdata;rdresp=rresp;
   @(posedge clk);@(negedge clk);
  end
 endtask
 reg [1:0] wrresp;reg start_seen;
 task lite_write(input [7:0] a,input [31:0] d,input [3:0] s);
  begin
   @(negedge clk);awaddr={16'd0,a};awvalid=1;wdata=d;wstrb=s;wvalid=1;
   fork
    begin while(!awready)@(negedge clk);@(posedge clk);@(negedge clk);awvalid=0;end
    begin while(!wready)@(negedge clk);@(posedge clk);@(negedge clk);wvalid=0;end
   join
   while(!bvalid)@(negedge clk);
   wrresp=bresp;start_seen=start;@(posedge clk);@(negedge clk);
  end
 endtask
 integer i;
 reg [31:0] lo,hi;
 // low address, high address, expected low, expected high
 task pair_check(input [7:0] la,input [7:0] ha,input [31:0] elo,input [31:0] ehi,input [255:0] tag);
  begin
   lite_read(la);lo=rdval;
   lite_read(la+4);hi=rdval;
   if(lo!==elo||hi!==ehi)begin
    errors=errors+1;$display("FAIL pair %0s lo=%h/%h hi=%h/%h",tag,lo,elo,hi,ehi);$fflush();
   end
  end
 endtask
 initial begin
  repeat(4)@(negedge clk);rst_n=1;repeat(2)@(negedge clk);
  // Make accumulated counters nonzero exactly once before snapshot tests.
  @(negedge clk);busy=1;vdone=1;ldone=1;mdone=1;
  @(negedge clk);busy=0;vdone=0;ldone=0;mdone=0;
  repeat(2)@(negedge clk);
  // Baseline pairs first (should pass on both RTLs).
  pair_check(8'd32,8'd32,32'h55667788,32'h11223344,"cycles");
  pair_check(8'd48,8'd48,32'hEEFF0011,32'hAABBCCDD,"fetch");
  pair_check(8'd56,8'd56,32'h89ABCDEF,32'h01234567,"operator");
  pair_check(8'd64,8'd64,32'hBBBBCCCC,32'h9999AAAA,"vector");
  pair_check(8'd72,8'd72,32'hFFFF0001,32'hDDDDEEEE,"layout");
  pair_check(8'd96,8'd96,32'h12345678,32'h00000000,"rdovl");
  pair_check(8'd104,8'd104,32'h9ABCDEF0,32'h00000000,"wrovl");
  pair_check(8'd160,8'd160,32'h33334444,32'h11112222,"matrix");
  pair_check(8'd168,8'd168,32'h77778888,32'h55556666,"matrix_pe");
  $display("PA001_BASELINE pairs done errors=%0d",errors);$fflush();

  // Original PA-001 sequence: low(cycles), low(fetch), high(cycles).
  lite_read(8'd32);
  lite_read(8'd48);
  lite_read(8'd36);hi=rdval;
  $display("PA001_INTERLEAVED read20,read30,read24 -> %h (correct %h)",hi,32'h11223344);$fflush();
  if(hi==32'h11223344)$display("PA001_INTERLEAVED_OK");else $display("PA001_INTERLEAVED_BUG");
  if(hi!==32'h11223344)begin errors=errors+1;end

  // Low then unrelated low then high for every bank.
  lite_read(8'd56);lite_read(8'd72);lite_read(8'd60);hi=rdval;
  if(hi!==32'h01234567)begin errors=errors+1;$display("FAIL op interleave %h",hi);end
  lite_read(8'd64);lite_read(8'd160);lite_read(8'd68);hi=rdval;
  if(hi!==32'h9999AAAA)begin errors=errors+1;$display("FAIL vec interleave %h",hi);end
  lite_read(8'd72);lite_read(8'd96);lite_read(8'd76);hi=rdval;
  if(hi!==32'hDDDDEEEE)begin errors=errors+1;$display("FAIL lay interleave %h",hi);end
  lite_read(8'd160);lite_read(8'd168);lite_read(8'd164);hi=rdval;
  if(hi!==32'h11112222)begin errors=errors+1;$display("FAIL mat interleave %h",hi);end
  lite_read(8'd168);lite_read(8'd32);lite_read(8'd172);hi=rdval;
  if(hi!==32'h55556666)begin errors=errors+1;$display("FAIL mpe interleave %h",hi);end

  // Atomic pair: low samples high; a later high change must not leak into the
  // paired high read.
  cycles=64'h1111222233334444;
  lite_read(8'd32);lo=rdval;
  cycles=64'h9999888833334444;
  lite_read(8'd48);
  lite_read(8'd36);hi=rdval;
  $display("PA001_ATOMIC low=%h high=%h (expected high 11112222)",lo,hi);$fflush();
  if(lo!==32'h33334444||hi!==32'h11112222)begin errors=errors+1;$display("FAIL atomic snapshot");end

  // High-only read after a valid low sample returns that register's sampled
  // high word (documented pair-read contract), not another bank's high.
  lite_read(8'd36);hi=rdval;
  if(hi!==32'h11112222)begin errors=errors+1;$display("FAIL high-only read %h",hi);end

  // START clears snapshot banks; a high read after START sees current high.
  cycles=64'hAAAA555566667777;
  lite_read(8'd32);
  lite_write(8'd16,32'd1,4'hf);
  chk("START accepted",wrresp==0&&start_seen==1);
  cycles=64'hBBBB444466667777;
  lite_read(8'd36);hi=rdval;
  if(hi!==32'hBBBB4444)begin errors=errors+1;$display("FAIL post-START snapshot %h",hi);end

  // Unrelated register semantics.
  lite_read(8'd0);chk("magic",rdval==32'hA51A22D0);
  lite_read(8'd20);chk("completed",rdval==1);
  lite_read(8'd148);chk("generation",rdval==32'h101);

  // Invalid strobe must not change plan_count.
  lite_write(8'd12,32'hCAFEBABE,4'b0011);
  lite_read(8'd12);
  chk("bad strobe rejected",wrresp==2'b10&&rdval==0);

  // Busy START rejection.
  busy=1;lite_write(8'd16,32'd1,4'hf);
  chk("busy START rejected",wrresp==2'b10&&start_seen==0);
  busy=0;

  $display("PA001_TEST_END errors=%0d",errors);$fflush();
  if(errors==0)$display("PA001_PASS");else $display("PA001_FAIL");
  $finish;
 end
endmodule
