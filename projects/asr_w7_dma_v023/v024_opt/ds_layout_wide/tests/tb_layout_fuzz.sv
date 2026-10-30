`timescale 1ns/1ps
// Layout fuzz harness: same descriptor + same DDR image for original and
// candidate.  Logs fault/error/processed/cache counts and a hash of the 256 KiB
// private DDR window after DRAIN; no cycle count is logged.
module tb_layout_fuzz;
 integer cycle=0;
 reg clk=0;always #4 clk=~clk;
 reg rst_n=0,start=0;reg [1023:0] descriptor=0;reg [31:0] param_end=32'h10010000;
 wire ready,busy,done,fault;wire [7:0] error_code;
 wire [31:0] processed_elements,rejected_starts,cache_hits,cache_misses;
 wire [63:0] cycles;
 wire [31:0] read_bytes,write_bytes,read_bursts,write_bursts;
 wire [39:0] read_m_axi_araddr;wire [7:0] read_m_axi_arlen;wire [2:0] read_m_axi_arsize;
 wire [1:0] read_m_axi_arburst;wire [3:0] read_m_axi_arcache;wire [2:0] read_m_axi_arprot;
 wire read_m_axi_arvalid,read_m_axi_arready;wire [127:0] read_m_axi_rdata;wire [1:0] read_m_axi_rresp;
 wire read_m_axi_rlast,read_m_axi_rvalid,read_m_axi_rready;
 wire [39:0] read_m_axi_awaddr;wire [7:0] read_m_axi_awlen;wire [2:0] read_m_axi_awsize;
 wire [1:0] read_m_axi_awburst;wire [3:0] read_m_axi_awcache;wire [2:0] read_m_axi_awprot;
 wire read_m_axi_awvalid,read_m_axi_awready;wire [127:0] read_m_axi_wdata;wire [15:0] read_m_axi_wstrb;
 wire read_m_axi_wlast,read_m_axi_wvalid,read_m_axi_wready;wire [1:0] read_m_axi_bresp;
 wire read_m_axi_bvalid,read_m_axi_bready;
 wire [39:0] write_m_axi_araddr;wire [7:0] write_m_axi_arlen;wire [2:0] write_m_axi_arsize;
 wire [1:0] write_m_axi_arburst;wire [3:0] write_m_axi_arcache;wire [2:0] write_m_axi_arprot;
 wire write_m_axi_arvalid,write_m_axi_arready;wire [127:0] write_m_axi_rdata;wire [1:0] write_m_axi_rresp;
 wire write_m_axi_rlast,write_m_axi_rvalid,write_m_axi_rready;
 wire [39:0] write_m_axi_awaddr;wire [7:0] write_m_axi_awlen;wire [2:0] write_m_axi_awsize;
 wire [1:0] write_m_axi_awburst;wire [3:0] write_m_axi_awcache;wire [2:0] write_m_axi_awprot;
 wire write_m_axi_awvalid,write_m_axi_awready;wire [127:0] write_m_axi_wdata;wire [15:0] write_m_axi_wstrb;
 wire write_m_axi_wlast,write_m_axi_wvalid,write_m_axi_wready;wire [1:0] write_m_axi_bresp;
 wire write_m_axi_bvalid,write_m_axi_bready;
 ddr_layout_axi dut(.*);
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
 wire inject_read_error=0,inject_write_error=0;
 axi128_memory_bfm ddr(.read_bursts(read_requests),.write_bursts(write_requests),.*);
 reg [7:0] mem[0:262143];reg [31:0] desc_words[0:31];reg [4095:0] memfile,descfile,logfile;
 reg [63:0] h;integer i,lg;
 always @(posedge clk)if(rst_n)begin cycle<=cycle+1;if(cycle>5000000)$fatal(1,"Layout fuzz watchdog");end
 initial begin
  if(!$value$plusargs("mem=%s",memfile)||!$value$plusargs("desc=%s",descfile)||!$value$plusargs("log=%s",logfile))$fatal(1,"args");
  if($value$plusargs("pe=%d",param_end))begin end
  $readmemh(memfile,ddr.memory);$readmemh(descfile,desc_words);
  for(i=0;i<32;i=i+1)descriptor[i*32+:32]=desc_words[i];
  repeat(5)@(negedge clk);rst_n=1;repeat(2)@(negedge clk);start=1;@(negedge clk);start=0;
  wait(done);@(negedge clk);
  h=0;
  for(i=0;i<16384;i=i+1)h=h*64'd33+{ddr.memory[i*16],ddr.memory[i*16+1],ddr.memory[i*16+2],ddr.memory[i*16+3],
    ddr.memory[i*16+4],ddr.memory[i*16+5],ddr.memory[i*16+6],ddr.memory[i*16+7]};
  lg=$fopen(logfile,"w");
  $fwrite(lg,"FUZZ fault=%0d err=%02h processed=%0d hits=%0d misses=%0d rb=%0d wb=%0d rbeat=%0d wbeat=%0d cycles=%0d memhash=%016h\n",
    fault,error_code,processed_elements,cache_hits,cache_misses,read_requests,write_requests,read_beats,write_beats,cycles,h);
  $fclose(lg);$display("LAYOUT_FUZZ_DONE fault=%0d err=%02h",fault,error_code);$finish;
 end
endmodule
