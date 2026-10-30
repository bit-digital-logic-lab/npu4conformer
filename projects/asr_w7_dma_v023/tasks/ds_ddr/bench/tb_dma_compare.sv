`timescale 1ns/1ps
// before/after 同负载 TB：同一 seed/延迟/背压/突发数，分别用 -DCAND 编译。
// MODE=read|write|mix；mix 同时驱动独立读/写 DMA，共享一个 AXI128 BFM。
`ifndef LATMIN
 `define LATMIN 8
`endif
`ifndef LATMAX
 `define LATMAX 32
`endif
`ifndef BP
 `define BP 0
`endif
`ifndef SEED
 `define SEED 1
`endif
`ifndef MAXOUT
 `define MAXOUT 8
`endif
module tb_dma_compare;
 integer nbeats=4096;       // 运行期 +beats=
 localparam integer BASE=40'h04000000;
 localparam integer MEM_BYTES=262144;
 reg clk=0,rst_n=0;
 always #5 clk=~clk;

 wire [39:0] ar0_addr,ar1_addr,aw0_addr,aw1_addr;
 wire [7:0] ar0_len,ar1_len,aw0_len,aw1_len;
 wire [2:0] ar0_size,ar1_size,aw0_size,aw1_size;
 wire [1:0] ar0_burst,ar1_burst,aw0_burst,aw1_burst;
 wire ar0_valid,ar1_valid,aw0_valid,aw1_valid;
 wire ar0_ready,ar1_ready,aw0_ready,aw1_ready;
 wire [127:0] r0_data,r1_data;
 wire [1:0] r0_resp,r1_resp;
 wire r0_last,r1_last,r0_valid,r1_valid,r0_ready,r1_ready;
 wire [127:0] w0_data,w1_data;
 wire [15:0] w0_strb,w1_strb;
 wire w0_last,w1_last,w0_valid,w1_valid,w0_ready,w1_ready;
 wire [1:0] b0_resp,b1_resp;
 wire b0_valid,b1_valid,b0_ready,b1_ready;
 wire [1:0] arvalid_bus,arready_bus,rlast_bus,rvalid_bus,rready_bus,awvalid_bus,awready_bus,wlast_bus,wvalid_bus,wready_bus,bvalid_bus,bready_bus;
 wire [79:0] araddr_bus,awaddr_bus;
 wire [15:0] arlen_bus,awlen_bus;
 wire [5:0] arsize_bus,awsize_bus;
 wire [3:0] arburst_bus,awburst_bus;
 wire [255:0] rdata_bus,wdata_bus;
 wire [3:0] rresp_bus,bresp_bus;
 wire [31:0] wstrb_bus;
 reg err_read=0,err_write=0;
 wire [63:0] total_cycles,busy_cycles,read_busy,write_busy,read_beats,write_beats,read_bursts,write_bursts;
 wire [63:0] bus_idle,turnaround,ar_stalls,aw_stalls,r_stalls,w_stalls;
 wire [31:0] max_rd,max_wr;
 // TB 驱动 BFM 输入
 assign arvalid_bus={ar1_valid,ar0_valid};
 assign rready_bus={r1_ready,r0_ready};
 assign awvalid_bus={aw1_valid,aw0_valid};
 assign wlast_bus={w1_last,w0_last};
 assign wvalid_bus={w1_valid,w0_valid};
 assign bready_bus={b1_ready,b0_ready};
 assign araddr_bus={ar1_addr,ar0_addr};
 assign arlen_bus={ar1_len,ar0_len};
 assign arsize_bus={ar1_size,ar0_size};
 assign arburst_bus={ar1_burst,ar0_burst};
 assign awaddr_bus={aw1_addr,aw0_addr};
 assign awlen_bus={aw1_len,aw0_len};
 assign awsize_bus={aw1_size,aw0_size};
 assign awburst_bus={aw1_burst,aw0_burst};
 assign wdata_bus={w1_data,w0_data};
 assign wstrb_bus={w1_strb,w0_strb};
 // BFM 输出接给 DUT
 assign ar0_ready=arready_bus[0];assign ar1_ready=arready_bus[1];
 assign r0_valid=rvalid_bus[0];assign r1_valid=rvalid_bus[1];
 assign r0_last=rlast_bus[0];assign r1_last=rlast_bus[1];
 assign r0_data=rdata_bus[127:0];assign r1_data=rdata_bus[255:128];
 assign r0_resp=rresp_bus[1:0];assign r1_resp=rresp_bus[3:2];
 assign aw0_ready=awready_bus[0];assign aw1_ready=awready_bus[1];
 assign w0_ready=wready_bus[0];assign w1_ready=wready_bus[1];
 assign b0_valid=bvalid_bus[0];assign b1_valid=bvalid_bus[1];
 assign b0_resp=bresp_bus[1:0];assign b1_resp=bresp_bus[3:2];

 axi128_ddr_bfm #(.PORTS(2),.MAX_OUT(`MAXOUT),
   .LAT_MIN(`LATMIN),.LAT_MAX(`LATMAX),.BLAT_MIN(4),.BLAT_MAX(12),
   .TURNAROUND(2),.READY_STALL_PCT(`BP),.SEED(`SEED)) bfm(
  .clk(clk),.rst_n(rst_n),
  .araddr(araddr_bus),.arlen(arlen_bus),.arsize(arsize_bus),.arburst(arburst_bus),
  .arvalid(arvalid_bus),.arready(arready_bus),
  .rdata(rdata_bus),.rresp(rresp_bus),.rlast(rlast_bus),.rvalid(rvalid_bus),.rready(rready_bus),
  .awaddr(awaddr_bus),.awlen(awlen_bus),.awsize(awsize_bus),.awburst(awburst_bus),
  .awvalid(awvalid_bus),.awready(awready_bus),
  .wdata(wdata_bus),.wstrb(wstrb_bus),.wlast(wlast_bus),.wvalid(wvalid_bus),.wready(wready_bus),
  .bresp(bresp_bus),.bvalid(bvalid_bus),.bready(bready_bus),
  .inject_read_error({2{err_read}}),.inject_write_error({2{err_write}}),
  .cycles(total_cycles),.bus_busy_cycles(busy_cycles),.bus_read_beats(read_beats),.bus_write_beats(write_beats),
  .bus_idle_cycles(bus_idle),.bus_turnaround_cycles(turnaround),
  .read_bursts(read_bursts),.write_bursts(write_bursts),
  .max_rd_out(max_rd),.max_wr_out(max_wr),
  .ar_stall_cycles(ar_stalls),.aw_stall_cycles(aw_stalls),
  .r_stall_cycles(r_stalls),.w_stall_cycles(w_stalls));

 // ---- 读 DMA（端口0） ----
 reg rd_req_valid;wire rd_req_ready;reg rd_req_write;reg [31:0] rd_req_addr;reg [15:0] rd_req_beats;
 wire rd_valid;reg rd_ready_d;wire [127:0] rd_data;wire [15:0] rd_index;
 wire rd_done,rd_error;wire [31:0] rd_bytes,rd_bursts,rd_armax,rd_bmax;wire [63:0] rd_bub,rd_fifo_hi;wire [63:0] rd_wbub;
 // ---- 写 DMA（端口1） ----
 reg wr_req_valid;wire wr_req_ready;reg wr_req_write;reg [31:0] wr_req_addr;reg [15:0] wr_req_beats;
 reg wr_valid_d;wire wr_ready_d;reg [127:0] wr_data_d;reg [15:0] wr_strobe_d;wire [15:0] wr_index_d;
 wire wr_done,wr_error;wire [31:0] wr_bytes,wr_bursts,wr_armax,wr_bmax;wire [63:0] wr_bub,wr_fifo_hi;wire [63:0] wr_wbub;

`ifdef CAND
 axi_dma_v020_multi #(.MAX_OUT(`MAXOUT),.FIFO_BEATS(128)) dut_r(
  .clk(clk),.rst_n(rst_n),.request_valid(rd_req_valid),.request_ready(rd_req_ready),.request_write(1'b0),
  .request_address(rd_req_addr),.request_beats(rd_req_beats),
  .read_valid(rd_valid),.read_ready(rd_ready_d),.read_data(rd_data),.read_index(rd_index),
  .write_valid(1'b0),.write_ready(),.write_data(128'd0),.write_strobe(16'd0),.write_index(),
  .done(rd_done),.error(rd_error),.read_bytes(rd_bytes),.write_bytes(),.read_bursts(rd_bursts),.write_bursts(),
  .ar_outstanding_max(rd_armax),.b_outstanding_max(rd_bmax),.read_bubble_cycles(rd_bub),.write_bubble_cycles(rd_wbub),.read_fifo_high(rd_fifo_hi),
  .m_axi_araddr(ar0_addr),.m_axi_arlen(ar0_len),.m_axi_arsize(ar0_size),.m_axi_arburst(ar0_burst),.m_axi_arcache(),.m_axi_arprot(),
  .m_axi_arvalid(ar0_valid),.m_axi_arready(ar0_ready),.m_axi_rdata(r0_data),.m_axi_rresp(r0_resp),.m_axi_rlast(r0_last),.m_axi_rvalid(r0_valid),.m_axi_rready(r0_ready),
  .m_axi_awaddr(),.m_axi_awlen(),.m_axi_awsize(),.m_axi_awburst(),.m_axi_awcache(),.m_axi_awprot(),.m_axi_awvalid(),.m_axi_awready(1'b0),
  .m_axi_wdata(),.m_axi_wstrb(),.m_axi_wlast(),.m_axi_wvalid(),.m_axi_wready(1'b0),.m_axi_bresp(2'b0),.m_axi_bvalid(1'b0),.m_axi_bready());
 axi_dma_v020_multi #(.MAX_OUT(`MAXOUT),.FIFO_BEATS(128)) dut_w(
  .clk(clk),.rst_n(rst_n),.request_valid(wr_req_valid),.request_ready(wr_req_ready),.request_write(1'b1),
  .request_address(wr_req_addr),.request_beats(wr_req_beats),
  .read_valid(),.read_ready(1'b1),.read_data(),.read_index(),
  .write_valid(wr_valid_d),.write_ready(wr_ready_d),.write_data(wr_data_d),.write_strobe(wr_strobe_d),.write_index(wr_index_d),
  .done(wr_done),.error(wr_error),.read_bytes(),.write_bytes(wr_bytes),.read_bursts(),.write_bursts(wr_bursts),
  .ar_outstanding_max(wr_armax),.b_outstanding_max(wr_bmax),.read_bubble_cycles(wr_bub),.write_bubble_cycles(wr_wbub),.read_fifo_high(wr_fifo_hi),
  .m_axi_araddr(),.m_axi_arlen(),.m_axi_arsize(),.m_axi_arburst(),.m_axi_arcache(),.m_axi_arprot(),.m_axi_arvalid(),.m_axi_arready(1'b0),
  .m_axi_rdata(128'd0),.m_axi_rresp(2'b0),.m_axi_rlast(1'b0),.m_axi_rvalid(1'b0),.m_axi_rready(),
  .m_axi_awaddr(aw1_addr),.m_axi_awlen(aw1_len),.m_axi_awsize(aw1_size),.m_axi_awburst(aw1_burst),.m_axi_awcache(),.m_axi_awprot(),
  .m_axi_awvalid(aw1_valid),.m_axi_awready(aw1_ready),
  .m_axi_wdata(w1_data),.m_axi_wstrb(w1_strb),.m_axi_wlast(w1_last),.m_axi_wvalid(w1_valid),.m_axi_wready(w1_ready),.m_axi_bresp(b1_resp),.m_axi_bvalid(b1_valid),.m_axi_bready(b1_ready));
`else
 axi_dma_v019 dut_r(
  .clk(clk),.rst_n(rst_n),.request_valid(rd_req_valid),.request_ready(rd_req_ready),.request_write(1'b0),
  .request_address(rd_req_addr),.request_beats(rd_req_beats),
  .read_valid(rd_valid),.read_ready(rd_ready_d),.read_data(rd_data),.read_index(rd_index),
  .write_valid(1'b0),.write_ready(),.write_data(128'd0),.write_strobe(16'd0),.write_index(),
  .done(rd_done),.error(rd_error),.read_bytes(rd_bytes),.write_bytes(),.read_bursts(rd_bursts),.write_bursts(),
  .m_axi_araddr(ar0_addr),.m_axi_arlen(ar0_len),.m_axi_arsize(ar0_size),.m_axi_arburst(ar0_burst),.m_axi_arcache(),.m_axi_arprot(),
  .m_axi_arvalid(ar0_valid),.m_axi_arready(ar0_ready),.m_axi_rdata(r0_data),.m_axi_rresp(r0_resp),.m_axi_rlast(r0_last),.m_axi_rvalid(r0_valid),.m_axi_rready(r0_ready),
  .m_axi_awaddr(),.m_axi_awlen(),.m_axi_awsize(),.m_axi_awburst(),.m_axi_awcache(),.m_axi_awprot(),.m_axi_awvalid(),.m_axi_awready(1'b0),
  .m_axi_wdata(),.m_axi_wstrb(),.m_axi_wlast(),.m_axi_wvalid(),.m_axi_wready(1'b0),.m_axi_bresp(2'b0),.m_axi_bvalid(1'b0),.m_axi_bready());
 axi_dma_v019 dut_w(
  .clk(clk),.rst_n(rst_n),.request_valid(wr_req_valid),.request_ready(wr_req_ready),.request_write(1'b1),
  .request_address(wr_req_addr),.request_beats(wr_req_beats),
  .read_valid(),.read_ready(1'b1),.read_data(),.read_index(),
  .write_valid(wr_valid_d),.write_ready(wr_ready_d),.write_data(wr_data_d),.write_strobe(wr_strobe_d),.write_index(wr_index_d),
  .done(wr_done),.error(wr_error),.read_bytes(),.write_bytes(wr_bytes),.read_bursts(),.write_bursts(wr_bursts),
  .m_axi_araddr(),.m_axi_arlen(),.m_axi_arsize(),.m_axi_arburst(),.m_axi_arcache(),.m_axi_arprot(),.m_axi_arvalid(),.m_axi_arready(1'b0),
  .m_axi_rdata(128'd0),.m_axi_rresp(2'b0),.m_axi_rlast(1'b0),.m_axi_rvalid(1'b0),.m_axi_rready(),
  .m_axi_awaddr(aw1_addr),.m_axi_awlen(aw1_len),.m_axi_awsize(aw1_size),.m_axi_awburst(aw1_burst),.m_axi_awcache(),.m_axi_awprot(),
  .m_axi_awvalid(aw1_valid),.m_axi_awready(aw1_ready),
  .m_axi_wdata(w1_data),.m_axi_wstrb(w1_strb),.m_axi_wlast(w1_last),.m_axi_wvalid(w1_valid),.m_axi_wready(w1_ready),.m_axi_bresp(b1_resp),.m_axi_bvalid(b1_valid),.m_axi_bready(b1_ready));
`endif

 function [127:0] pat(input integer word,input integer lane);
  reg [7:0] b;
  begin
   b=(word*13+lane*29+17)&255;
   pat={16{b}}; // 同 word 的 16 lane 都是同一个字节，便于逐 lane 比较
   for(integer j=0;j<16;j=j+1)pat[j*8+:8]=(word*13+j*29+17)&255;
  end
 endfunction

 // 新 BFM 是字节数组，0x0400_0000 窗口映射到 256KiB 偏移。
 function [127:0] mem_word(input [39:0] a,input integer beat);
  integer lane;integer idx;
  begin
   idx=262144+(a-BASE)+beat*16;
   for(lane=0;lane<16;lane=lane+1)mem_word[lane*8+:8]=bfm.memory[idx+lane];
  end
 endfunction

 integer i,j,seed_r,seed_w;
 reg [127:0] wtmp;
 integer mode; // 0=read 1=write 2=mix
 integer rd_off,wr_off,err_mode;
 integer cyc_start,cyc_end,cyc_mix;
 reg pass;reg rd_running,wr_running;
 reg [15:0] exp_idx;
 integer ar_seen,aw_seen,rlast_seen,b_seen;
 integer last_mode;
 reg [63:0] read_bubble,write_bubble;
 reg [31:0] ar_max,aw_max;

 initial begin
  if(!$value$plusargs("mode=%d",mode))mode=0;
  if(!$value$plusargs("seed=%d",seed_r))seed_r=1;
  if(!$value$plusargs("seedw=%d",seed_w))seed_w=2;
  if(!$value$plusargs("beats=%d",nbeats))nbeats=4096;
  if(!$value$plusargs("rdoff=%d",rd_off))rd_off=0;
  if(!$value$plusargs("wroff=%d",wr_off))wr_off=0;
  if(!$value$plusargs("err=%d",err_mode))err_mode=0;
  err_read=(err_mode==1);err_write=(err_mode==2);
  // 存储预置：每个 16B word 按 pat 填充；写测试结束后再检查
  for(i=0;i<MEM_BYTES/16;i=i+1)begin
   wtmp=pat(i,0);
   for(j=0;j<16;j=j+1)bfm.memory[262144+i*16+j]=wtmp[j*8+:8];
  end
  rd_req_valid=0;wr_req_valid=0;rd_req_write=0;wr_req_write=1;
  rd_req_addr=BASE+rd_off;wr_req_addr=BASE+32'h00010000+wr_off;
  rd_req_beats=nbeats;wr_req_beats=nbeats;
  rd_ready_d=1;
  repeat(8)@(posedge clk);rst_n=1;repeat(4)@(posedge clk);
  $display("TB_START mode=%0d rst=%b req_ready=%b ar_ready=%b",mode,rst_n,rd_req_ready,ar0_ready);
  pass=1;read_bubble=0;write_bubble=0;ar_max=0;aw_max=0;ar_seen=0;rlast_seen=0;aw_seen=0;b_seen=0;rd_running=0;wr_running=0;
  if(mode==0)begin
   cyc_start=total_cycles;fork read_task; join
  end else if(mode==1)begin
   cyc_start=total_cycles;fork write_task; join
  end else begin
   cyc_start=total_cycles;fork read_task; write_task; join
  end
  cyc_end=total_cycles;
  // 写回检查（只检查写任务区）
  if(mode!=0)begin
   for(i=0;i<nbeats;i=i+1)begin
    if(mem_word(wr_req_addr,i)!==pat(i,0))pass=0;
   end
  end
  $display("DMA_RESULT mode=%0d dut=%s beats=%0d cycles=%0d total_bfm_cycles=%0d busy=%0d rbeats=%0d wbeats=%0d rbursts=%0d wbursts=%0d rbubble=%0d wbubble=%0d armax=%0d awmax=%0d pass=%0d",
   mode,`ifdef CAND "cand" `else "base" `endif,nbeats,cyc_end-cyc_start,total_cycles,busy_cycles,read_beats,write_beats,read_bursts,write_bursts,read_bubble,write_bubble,ar_max,aw_max,pass);
  if(!pass)$fatal(1,"DMA golden mismatch");
  $finish;
 end

 // 统计 bubble/outstanding（与 DMA 型号无关，全部从 AXI 握手测）
 always @(posedge clk)if(rst_n)begin
  if(rd_running)begin
   if(!ar0_valid&&!r0_valid)read_bubble<=read_bubble+1;
  end
  if(wr_running)begin
   if(!aw1_valid&&!w1_valid&&!b1_valid)write_bubble<=write_bubble+1;
  end
  if(ar0_valid&&ar0_ready)ar_seen<=ar_seen+1;
  if(r0_last&&r0_valid&&r0_ready)rlast_seen<=rlast_seen+1;
  if(aw1_valid&&aw1_ready)aw_seen<=aw_seen+1;
  if(b1_valid&&b1_ready)b_seen<=b_seen+1;
  if(ar_seen-rlast_seen>ar_max)ar_max<=ar_seen-rlast_seen;
  if(aw_seen-b_seen>aw_max)aw_max<=aw_seen-b_seen;
 end

 integer tbcyc=0;
 always @(posedge clk)begin tbcyc<=tbcyc+1; if(tbcyc>500000)$fatal(1,"TB watchdog"); end

 task read_task;
  integer beats_seen;
  begin
   beats_seen=0;
   @(posedge clk);rd_req_valid<=1;
   while(!rd_req_ready)@(posedge clk);
   @(posedge clk);rd_req_valid<=0;rd_running<=1;
   while(!rd_done)begin
    @(posedge clk);
    if(rd_valid&&rd_ready_d)begin
     if(rd_data!==mem_word(rd_req_addr,beats_seen))begin
      $display("READ MISMATCH idx=%0d got=%h exp=%h",beats_seen,rd_data,mem_word(rd_req_addr,beats_seen));pass=0;
     end
     if(rd_index!==beats_seen)begin $display("READ INDEX idx=%0d got=%0d",beats_seen,rd_index);pass=0;end
     beats_seen=beats_seen+1;
    end
   end
   if(err_mode==1)begin
    if(!rd_error)begin $display("READ MISSING EXPECTED ERROR");pass=0;end
   end else begin
    if(beats_seen!=nbeats)begin $display("READ COUNT %0d",beats_seen);pass=0;end
    if(rd_error)begin $display("READ ERROR");pass=0;end
   end
   rd_running<=0;
  end
 endtask

 task write_task;
  integer sent;
  begin
   sent=0;
   @(posedge clk);wr_req_valid<=1;
   while(!wr_req_ready)@(posedge clk);
   @(posedge clk);wr_req_valid<=0;wr_running<=1;
   while(!wr_done)begin
    wr_valid_d<=1;wr_data_d<=pat(sent,0);wr_strobe_d<=16'hffff;
    @(posedge clk);
    if(wr_valid_d&&wr_ready_d)sent=sent+1;
   end
   wr_valid_d<=0;
   if(err_mode==2)begin
    if(!wr_error)begin $display("WRITE MISSING EXPECTED ERROR");pass=0;end
   end else begin
    if(sent!=nbeats)begin $display("WRITE COUNT %0d",sent);pass=0;end
    if(wr_error)begin $display("WRITE ERROR");pass=0;end
   end
   wr_running<=0;
  end
 endtask
endmodule
