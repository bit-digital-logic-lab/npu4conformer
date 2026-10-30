`timescale 1ns/1ps
module tb_strobe;
reg clk=0;always #4 clk=~clk;
reg rst_n=0,req_valid=0;wire req_ready;reg req_write=0;reg [31:0] req_addr=0;reg [15:0] req_beats=0;
wire rd_valid;wire rd_ready=1;wire [127:0] rd_data;wire [15:0] rd_index;
reg wr_valid=0;wire wr_ready;reg [127:0] wr_data=0;reg [15:0] wr_strobe=16'hffff;wire [15:0] wr_index;
wire done,error;wire [31:0] rb,wb,rbu,wbu,am,bm;wire [63:0] b1,b2,b3;
wire [39:0] araddr;wire [7:0] arlen;wire [2:0] arsize;wire [1:0] arburst,arb;wire [3:0] arcache;wire [2:0] arprot;wire arvalid,arready;
wire [127:0] rdata;wire [1:0] rresp;wire rlast,rvalid,rready;
wire [39:0] awaddr;wire [7:0] awlen;wire [2:0] awsize;wire [1:0] awburst,awb;wire [3:0] awcache;wire [2:0] awprot;wire awvalid,awready;
wire [127:0] wdata;wire [15:0] wstrb;wire wlast,wvalid,wready;wire [1:0] bresp;wire bvalid,bready;
axi_dma_v020_multi_v2 dut(.clk(clk),.rst_n(rst_n),.request_valid(req_valid),.request_ready(req_ready),.request_write(req_write),
.request_address(req_addr),.request_beats(req_beats),.read_valid(rd_valid),.read_ready(rd_ready),.read_data(rd_data),.read_index(rd_index),
.write_valid(wr_valid),.write_ready(wr_ready),.write_data(wr_data),.write_strobe(wr_strobe),.write_index(wr_index),
.done(done),.error(error),.read_bytes(rb),.write_bytes(wb),.read_bursts(rbu),.write_bursts(wbu),.ar_outstanding_max(am),.b_outstanding_max(bm),
.read_bubble_cycles(b1),.write_bubble_cycles(b2),.read_fifo_high(b3),
.m_axi_araddr(araddr),.m_axi_arlen(arlen),.m_axi_arsize(arsize),.m_axi_arburst(arb),.m_axi_arcache(arcache),.m_axi_arprot(arprot),
.m_axi_arvalid(arvalid),.m_axi_arready(arready),.m_axi_rdata(rdata),.m_axi_rresp(rresp),.m_axi_rlast(rlast),.m_axi_rvalid(rvalid),.m_axi_rready(rready),
.m_axi_awaddr(awaddr),.m_axi_awlen(awlen),.m_axi_awsize(awsize),.m_axi_awburst(awb),.m_axi_awcache(awcache),.m_axi_awprot(awprot),
.m_axi_awvalid(awvalid),.m_axi_awready(awready),.m_axi_wdata(wdata),.m_axi_wstrb(wstrb),.m_axi_wlast(wlast),.m_axi_wvalid(wvalid),.m_axi_wready(wready),
.m_axi_bresp(bresp),.m_axi_bvalid(bvalid),.m_axi_bready(bready));
reg [7:0] mem[0:255];integer i;reg bv=0;reg [15:0] bd=0;
assign arready=1;assign awready=1;assign wready=1;assign bvalid=bv;
integer wi=0;
always @(posedge clk)begin
 if(wvalid&&wready)begin for(i=0;i<16;i=i+1)if(wstrb[i])mem[wi*16+i]<=wdata[i*8+:8]; wi<=wi+1; if(wlast)bv<=1; end
 if(bv&&bready)bv<=0;
end
initial begin
 for(i=0;i<256;i=i+1)mem[i]=8'h00;
 repeat(4)@(negedge clk);rst_n=1;repeat(2)@(negedge clk);
 @(negedge clk);req_valid=1;req_write=1;req_addr=32'h04000000;req_beats=1;
 while(!req_ready)@(negedge clk);@(posedge clk);@(negedge clk);req_valid=0;
 @(negedge clk);wr_valid=1;wr_data=128'h0f0e0d0c0b0a09080706050403020100;wr_strobe=16'h0007;
 while(!wr_ready)@(negedge clk);@(posedge clk);@(negedge clk);wr_valid=0;
 while(!done)@(posedge clk);@(negedge clk);
 $display("STROBE mem=%h %h %h %h write_bytes=%0d err=%0d",mem[0],mem[1],mem[2],mem[3],wb,error);
 if(wb!==3)begin $display("FAIL strobe write_bytes expected 3");$fatal(1);end
 $display("PASS tb_strobe");$finish;
end
endmodule
