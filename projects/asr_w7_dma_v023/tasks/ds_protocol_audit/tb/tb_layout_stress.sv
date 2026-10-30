`timescale 1ns/1ps
// Seeded-backpressure rerun of the layout fixture set (COPY/im2col/tiled/NCHW).
// Covers 6-byte C48 fragments crossing 128-bit lines, unaligned dst, and
// non-multiple-of-16 output tails. Protocol/packing evidence only.
module tb_layout_stress;
 integer mode=0,nbytes,cycle=0,seed=1; reg acl=0;
 reg clk=0;always #4 clk=~clk;
 reg rst_n=0,start=0;reg [1023:0] descriptor=0;reg [31:0] param_end=32'h20000000;
 wire ready,busy,done,fault;wire [7:0] error_code;
 wire [31:0] processed_elements,rejected_starts,cache_hits,cache_misses;
 wire [63:0] cycles;wire [31:0] read_bytes,write_bytes,read_bursts,write_bursts;
 wire [39:0] read_m_axi_araddr;wire [7:0] read_m_axi_arlen;wire [2:0] read_m_axi_arsize;wire [1:0] read_m_axi_arburst;
 wire [3:0] read_m_axi_arcache;wire [2:0] read_m_axi_arprot;wire read_m_axi_arvalid,read_m_axi_arready;
 wire [127:0] read_m_axi_rdata;wire [1:0] read_m_axi_rresp;wire read_m_axi_rlast,read_m_axi_rvalid,read_m_axi_rready;
 wire [39:0] read_m_axi_awaddr;wire [7:0] read_m_axi_awlen;wire [2:0] read_m_axi_awsize;wire [1:0] read_m_axi_awburst;
 wire [3:0] read_m_axi_awcache;wire [2:0] read_m_axi_awprot;wire read_m_axi_awvalid,read_m_axi_awready;
 wire [127:0] read_m_axi_wdata;wire [15:0] read_m_axi_wstrb;wire read_m_axi_wlast,read_m_axi_wvalid,read_m_axi_wready;
 wire [1:0] read_m_axi_bresp;wire read_m_axi_bvalid,read_m_axi_bready;
 wire [39:0] write_m_axi_araddr;wire [7:0] write_m_axi_arlen;wire [2:0] write_m_axi_arsize;wire [1:0] write_m_axi_arburst;
 wire [3:0] write_m_axi_arcache;wire [2:0] write_m_axi_arprot;wire write_m_axi_arvalid,write_m_axi_arready;
 wire [127:0] write_m_axi_rdata;wire [1:0] write_m_axi_rresp;wire write_m_axi_rlast,write_m_axi_rvalid,write_m_axi_rready;
 wire [39:0] write_m_axi_awaddr;wire [7:0] write_m_axi_awlen;wire [2:0] write_m_axi_awsize;wire [1:0] write_m_axi_awburst;
 wire [3:0] write_m_axi_awcache;wire [2:0] write_m_axi_awprot;wire write_m_axi_awvalid,write_m_axi_awready;
 wire [127:0] write_m_axi_wdata;wire [15:0] write_m_axi_wstrb;wire write_m_axi_wlast,write_m_axi_wvalid,write_m_axi_wready;
 wire [1:0] write_m_axi_bresp;wire write_m_axi_bvalid,write_m_axi_bready;
 ddr_layout_axi dut(.clk(clk),.rst_n(rst_n),.start(start),.descriptor(descriptor),.param_end(param_end),
  .ready(ready),.busy(busy),.done(done),.fault(fault),.error_code(error_code),
  .processed_elements(processed_elements),.rejected_starts(rejected_starts),.cache_hits(cache_hits),.cache_misses(cache_misses),
  .cycles(cycles),.read_bytes(read_bytes),.write_bytes(write_bytes),.read_bursts(read_bursts),.write_bursts(write_bursts),.*);
 wire [79:0] araddr;assign araddr[0+:40]=read_m_axi_araddr;assign araddr[40+:40]=write_m_axi_araddr;
 wire [15:0] arlen;assign arlen[0+:8]=read_m_axi_arlen;assign arlen[8+:8]=write_m_axi_arlen;
 wire [5:0] arsize;assign arsize[0+:3]=read_m_axi_arsize;assign arsize[3+:3]=write_m_axi_arsize;
 wire [3:0] arburst;assign arburst[0+:2]=read_m_axi_arburst;assign arburst[2+:2]=write_m_axi_arburst;
 wire [1:0] arvalid;assign arvalid[0+:1]=read_m_axi_arvalid;assign arvalid[1+:1]=write_m_axi_arvalid;
 wire [1:0] arready;assign read_m_axi_arready=arready[0+:1];assign write_m_axi_arready=arready[1+:1];
 wire [255:0] rdata;assign read_m_axi_rdata=rdata[0+:128];assign write_m_axi_rdata=rdata[128+:128];
 wire [3:0] rresp;assign read_m_axi_rresp=rresp[0+:2];assign write_m_axi_rresp=rresp[2+:2];
 wire [1:0] rlast;assign read_m_axi_rlast=rlast[0+:1];assign write_m_axi_rlast=rlast[1+:1];
 wire [1:0] rvalid;assign read_m_axi_rvalid=rvalid[0+:1];assign write_m_axi_rvalid=rvalid[1+:1];
 wire [1:0] rready;assign rready[0+:1]=read_m_axi_rready;assign rready[1+:1]=write_m_axi_rready;
 wire [79:0] awaddr;assign awaddr[0+:40]=read_m_axi_awaddr;assign awaddr[40+:40]=write_m_axi_awaddr;
 wire [15:0] awlen;assign awlen[0+:8]=read_m_axi_awlen;assign awlen[8+:8]=write_m_axi_awlen;
 wire [5:0] awsize;assign awsize[0+:3]=read_m_axi_awsize;assign awsize[3+:3]=write_m_axi_awsize;
 wire [3:0] awburst;assign awburst[0+:2]=read_m_axi_awburst;assign awburst[2+:2]=write_m_axi_awburst;
 wire [1:0] awvalid;assign awvalid[0+:1]=read_m_axi_awvalid;assign awvalid[1+:1]=write_m_axi_awvalid;
 wire [1:0] awready;assign read_m_axi_awready=awready[0+:1];assign write_m_axi_awready=awready[1+:1];
 wire [255:0] wdata;assign wdata[0+:128]=read_m_axi_wdata;assign wdata[128+:128]=write_m_axi_wdata;
 wire [31:0] wstrb;assign wstrb[0+:16]=read_m_axi_wstrb;assign wstrb[16+:16]=write_m_axi_wstrb;
 wire [1:0] wlast;assign wlast[0+:1]=read_m_axi_wlast;assign wlast[1+:1]=write_m_axi_wlast;
 wire [1:0] wvalid;assign wvalid[0+:1]=read_m_axi_wvalid;assign wvalid[1+:1]=write_m_axi_wvalid;
 wire [1:0] wready;assign read_m_axi_wready=wready[0+:1];assign write_m_axi_wready=wready[1+:1];
 wire [3:0] bresp;assign read_m_axi_bresp=bresp[0+:2];assign write_m_axi_bresp=bresp[2+:2];
 wire [1:0] bvalid;assign read_m_axi_bvalid=bvalid[0+:1];assign write_m_axi_bvalid=bvalid[1+:1];
 wire [1:0] bready;assign bready[0+:1]=read_m_axi_bready;assign bready[1+:1]=write_m_axi_bready;
 wire [31:0] read_requests,write_requests,read_beats,write_beats;
 wire inject_read_error=0,inject_write_error=0,stall_r=0;
 axi128_stress_bfm ddr(.read_bursts(read_requests),.write_bursts(write_requests),
  .read_beats(read_beats),.write_beats(write_beats),.*);
 reg [7:0] gold[0:262143];reg [31:0] desc_words[0:31];string folder;
 always @(posedge clk)if(rst_n)begin cycle<=cycle+1;if(cycle>4000000)$fatal(1,"layout stress watchdog state=%d",dut.arithmetic.state);end
 initial begin
  if(!$value$plusargs("folder=%s",folder)||!$value$plusargs("nbytes=%d",nbytes)||!$value$plusargs("seed=%d",seed))
   $fatal(1,"Arguments folder/nbytes/seed");
  ddr.lfsr=seed|32'h1; acl=$test$plusargs("acl");
  $readmemh({folder,"/memory.hex"},ddr.memory);$readmemh({folder,"/gold.hex"},gold,0,nbytes-1);
  $readmemh({folder,"/descriptor.hex"},desc_words);
  for(integer j=0;j<32;j=j+1)descriptor[j*32+:32]=desc_words[j];
  if(acl)begin descriptor[95:64]=32'hFFFFFFF0;descriptor[127:96]=32'hFFFFFFF0;end // 64-bit extent must reject
  repeat(5)@(negedge clk);rst_n=1;repeat(2)@(negedge clk);start=1;@(negedge clk);start=0;
  wait(done);@(negedge clk);
  if(ddr.ra[0]||ddr.ra[1]||ddr.wa[0]||ddr.wa[1]||ddr.bp[0]||ddr.bp[1])$fatal(1,"Layout DONE before drain");
  if(acl)begin if(!fault||read_requests!=0||write_requests!=0)$fatal(1,"ACL not rejected: fault=%0d rb=%0d wb=%0d err=%h",fault,read_requests,write_requests,error_code); $display("LAYOUT_ACL_PASS fault=%0d err=%h rb=%0d wb=%0d",fault,error_code,read_requests,write_requests);$fflush();$finish; end
  if(fault||processed_elements!=desc_words[4])$fatal(1,"layout fault=%h err=%h processed=%d expected=%d",fault,error_code,processed_elements,desc_words[4]);
  for(integer j=0;j<nbytes;j=j+1)if(ddr.memory[65536+j]!==gold[j])$fatal(1,"Output mismatch byte=%d got=%h expected=%h",j,ddr.memory[65536+j],gold[j]);
  for(integer j=nbytes;j<nbytes+32;j=j+1)if(ddr.memory[65536+j]!==8'ha5)$fatal(1,"Tail byte overwritten at %d",j);
  if(read_requests==0||write_requests==0)$fatal(1,"No AXI traffic");
  $display("LAYOUT_STRESS_PASS seed=%0d bytes=%0d cycles=%0d hits=%0d misses=%0d rb=%0d wb=%0d rbytes=%0d wbytes=%0d",
   seed,nbytes,cycles,cache_hits,cache_misses,read_bursts,write_bursts,read_bytes,write_bytes);
  $finish;
 end
endmodule
