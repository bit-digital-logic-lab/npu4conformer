`timescale 1ns/1ps
// Real data-chain tests for wc_plan_top_v023.
//   mode10: direct LAY(copy) -> VEC(add) -> VEC(mul), real engines.
//   mode11: one SEQ node, V022 plan = LAY(copy) then VEC(add), real engines.
//   mode12: direct LAY -> direct VEC -> SEQ(LAY,VEC) -> direct VEC (owner switch).
// The only stub is the optional external matrix handshake (control-only); modes
// 10..12 do not instantiate/use it for data.  FMA is a forbidden stub and is
// never invoked by the chosen ADD/MUL descriptors.
module tb_wc_top;
 reg clk=0;always #4 clk=~clk;
 reg rst_n=0,start=0,parameter_ready=1;
 reg [31:0] plan_base=32'h10008000,param_end=32'h10040000,generation=7;
 integer mode=10,cycle=0,done_pulses=0,check_base=32'h04002000;
 reg [31:0] gold[0:63];reg [31:0] g;
 wire busy,done,fault,irq,drain_timeout,seq_busy,vector_busy,layout_busy;
 wire [7:0] error_code;
 wire [31:0] completed,node_count,rejected_starts,last_node;
 wire [127:0] done_mask;wire [63:0] cycles,fetch_cycles,operator_cycles,drain_cycles;
 wire [39:0] sf_araddr,qf_araddr,vr_araddr,lr_araddr,vw_awaddr,lw_awaddr;
 wire [7:0] sf_arlen,qf_arlen,vr_arlen,lr_arlen,vw_awlen,lw_awlen;
 wire [2:0] sf_arsize,qf_arsize,vr_arsize,lr_arsize,vw_awsize,lw_awsize;
 wire [1:0] sf_arburst,qf_arburst,vr_arburst,lr_arburst,vw_awburst,lw_awburst;
 wire [3:0] sf_arcache,qf_arcache,vr_arcache,lr_arcache,vw_awcache,lw_awcache;
 wire [2:0] sf_arprot,qf_arprot,vr_arprot,lr_arprot,vw_awprot,lw_awprot;
 wire sf_arvalid,qf_arvalid,vr_arvalid,lr_arvalid,vw_awvalid,lw_awvalid;
 wire [127:0] sf_rdata,qf_rdata,vr_rdata,lr_rdata,vw_wdata,lw_wdata;
 wire [1:0] sf_rresp,qf_rresp,vr_rresp,lr_rresp,vw_bresp,lw_bresp;
 wire sf_rlast,qf_rlast,vr_rlast,lr_rlast,vw_wlast,lw_wlast;
 wire sf_rvalid,qf_rvalid,vr_rvalid,lr_rvalid,vw_wvalid,lw_wvalid;
 wire [15:0] sf_wstrb,qf_wstrb,vr_wstrb,lr_wstrb,vw_wstrb,lw_wstrb;
 wire [39:0] sf_awaddr,qf_awaddr;wire [7:0] sf_awlen,qf_awlen;
 wire [2:0] sf_awsize,qf_awsize;wire [1:0] sf_awburst,qf_awburst;
 wire [3:0] sf_awcache,qf_awcache;wire [2:0] sf_awprot,qf_awprot;
 wire [127:0] sf_wdata,qf_wdata;wire [1:0] sf_bresp,qf_bresp;
 wire sf_wlast,qf_wlast,sf_wvalid,qf_wvalid;
 wire sf_awvalid,qf_awvalid,sf_bvalid,qf_bvalid,vw_bvalid,lw_bvalid;
 wire sf_arready,sf_awready,sf_wready,sf_bready,qf_arready,qf_awready,qf_wready,qf_bready;
 wire vr_arready,vw_awready,vw_wready,vw_bready,lr_arready,lw_awready,lw_wready,lw_bready;
 wire sf_rready,qf_rready,vr_rready,lr_rready;
 wire matrix_valid,matrix_ready,matrix_done,matrix_fault;
 wire [31:0] matrix_queue_base,matrix_queue_count;
 wc_plan_top_v023 dut(.clk(clk),.rst_n(rst_n),.start(start),.plan_base(plan_base),
  .param_end(param_end),.parameter_ready(parameter_ready),.generation(generation),
  .busy(busy),.done(done),.fault(fault),.error_code(error_code),.completed(completed),
  .node_count(node_count),.rejected_starts(rejected_starts),.last_node(last_node),
  .done_mask(done_mask),.cycles(cycles),.fetch_cycles(fetch_cycles),
  .operator_cycles(operator_cycles),.drain_cycles(drain_cycles),.drain_timeout(drain_timeout),
  .irq(irq),.seq_busy(seq_busy),.vector_busy(vector_busy),.layout_busy(layout_busy),
  .sf_araddr(sf_araddr),.sf_arlen(sf_arlen),.sf_arsize(sf_arsize),.sf_arburst(sf_arburst),
  .sf_arcache(sf_arcache),.sf_arprot(sf_arprot),.sf_arvalid(sf_arvalid),
  .sf_arready(sf_arready),.sf_rdata(sf_rdata),.sf_rresp(sf_rresp),.sf_rlast(sf_rlast),
  .sf_rvalid(sf_rvalid),.sf_rready(sf_rready),
  .sf_awaddr(sf_awaddr),.sf_awlen(sf_awlen),.sf_awsize(sf_awsize),.sf_awburst(sf_awburst),
  .sf_awcache(sf_awcache),.sf_awprot(sf_awprot),.sf_awvalid(sf_awvalid),.sf_awready(sf_awready),
  .sf_wdata(sf_wdata),.sf_wstrb(sf_wstrb),.sf_wlast(sf_wlast),.sf_wvalid(sf_wvalid),
  .sf_wready(sf_wready),.sf_bresp(sf_bresp),.sf_bvalid(sf_bvalid),.sf_bready(sf_bready),
  .qf_araddr(qf_araddr),.qf_arlen(qf_arlen),.qf_arsize(qf_arsize),.qf_arburst(qf_arburst),
  .qf_arcache(qf_arcache),.qf_arprot(qf_arprot),.qf_arvalid(qf_arvalid),
  .qf_arready(qf_arready),.qf_rdata(qf_rdata),.qf_rresp(qf_rresp),.qf_rlast(qf_rlast),
  .qf_rvalid(qf_rvalid),.qf_rready(qf_rready),
  .qf_awaddr(qf_awaddr),.qf_awlen(qf_awlen),.qf_awsize(qf_awsize),.qf_awburst(qf_awburst),
  .qf_awcache(qf_awcache),.qf_awprot(qf_awprot),.qf_awvalid(qf_awvalid),.qf_awready(qf_awready),
  .qf_wdata(qf_wdata),.qf_wstrb(qf_wstrb),.qf_wlast(qf_wlast),.qf_wvalid(qf_wvalid),
  .qf_wready(qf_wready),.qf_bresp(qf_bresp),.qf_bvalid(qf_bvalid),.qf_bready(qf_bready),
  .vr_araddr(vr_araddr),.vr_arlen(vr_arlen),.vr_arsize(vr_arsize),.vr_arburst(vr_arburst),
  .vr_arcache(vr_arcache),.vr_arprot(vr_arprot),.vr_arvalid(vr_arvalid),
  .vr_arready(vr_arready),.vr_rdata(vr_rdata),.vr_rresp(vr_rresp),.vr_rlast(vr_rlast),
  .vr_rvalid(vr_rvalid),.vr_rready(vr_rready),
  .vw_awaddr(vw_awaddr),.vw_awlen(vw_awlen),.vw_awsize(vw_awsize),.vw_awburst(vw_awburst),
  .vw_awcache(vw_awcache),.vw_awprot(vw_awprot),.vw_awvalid(vw_awvalid),.vw_awready(vw_awready),
  .vw_wdata(vw_wdata),.vw_wstrb(vw_wstrb),.vw_wlast(vw_wlast),.vw_wvalid(vw_wvalid),
  .vw_wready(vw_wready),.vw_bresp(vw_bresp),.vw_bvalid(vw_bvalid),.vw_bready(vw_bready),
  .lr_araddr(lr_araddr),.lr_arlen(lr_arlen),.lr_arsize(lr_arsize),.lr_arburst(lr_arburst),
  .lr_arcache(lr_arcache),.lr_arprot(lr_arprot),.lr_arvalid(lr_arvalid),
  .lr_arready(lr_arready),.lr_rdata(lr_rdata),.lr_rresp(lr_rresp),.lr_rlast(lr_rlast),
  .lr_rvalid(lr_rvalid),.lr_rready(lr_rready),
  .lw_awaddr(lw_awaddr),.lw_awlen(lw_awlen),.lw_awsize(lw_awsize),.lw_awburst(lw_awburst),
  .lw_awcache(lw_awcache),.lw_awprot(lw_awprot),.lw_awvalid(lw_awvalid),.lw_awready(lw_awready),
  .lw_wdata(lw_wdata),.lw_wstrb(lw_wstrb),.lw_wlast(lw_wlast),.lw_wvalid(lw_wvalid),
  .lw_wready(lw_wready),.lw_bresp(lw_bresp),.lw_bvalid(lw_bvalid),.lw_bready(lw_bready),
  .matrix_valid(matrix_valid),.matrix_ready(matrix_ready),
  .matrix_queue_base(matrix_queue_base),.matrix_queue_count(matrix_queue_count),
  .matrix_done(matrix_done),.matrix_fault(matrix_fault));
 // Six independent AXI ports: 0 sf, 1 qf, 2 vr, 3 vw, 4 lr, 5 lw.
 wire [6*40-1:0] araddr,awaddr;wire [6*8-1:0] arlen,awlen;
 wire [6*3-1:0] arsize,awsize;wire [6*2-1:0] arburst,awburst;
 wire [6*4-1:0] arcache,awcache;wire [6*3-1:0] arprot,awprot;
 wire [6-1:0] arvalid,arready,awvalid,awready;
 wire [6*128-1:0] rdata,wdata;wire [6*2-1:0] rresp,bresp;
 wire [6-1:0] rlast,rvalid,rready,wlast,wvalid,wready,bvalid,bready;
 wire [6*16-1:0] wstrb;
 assign araddr[0*40+:40]=sf_araddr;assign araddr[1*40+:40]=qf_araddr;
 assign araddr[2*40+:40]=vr_araddr;assign araddr[3*40+:40]=40'd0;
 assign araddr[4*40+:40]=lr_araddr;assign araddr[5*40+:40]=40'd0;
 assign arlen[0*8+:8]=sf_arlen;assign arlen[1*8+:8]=qf_arlen;assign arlen[2*8+:8]=vr_arlen;
 assign arlen[3*8+:8]=8'd0;assign arlen[4*8+:8]=lr_arlen;assign arlen[5*8+:8]=8'd0;
 assign arsize[0*3+:3]=sf_arsize;assign arsize[1*3+:3]=qf_arsize;assign arsize[2*3+:3]=vr_arsize;
 assign arsize[3*3+:3]=3'd0;assign arsize[4*3+:3]=lr_arsize;assign arsize[5*3+:3]=3'd0;
 assign arburst[0*2+:2]=sf_arburst;assign arburst[1*2+:2]=qf_arburst;assign arburst[2*2+:2]=vr_arburst;
 assign arburst[3*2+:2]=2'd0;assign arburst[4*2+:2]=lr_arburst;assign arburst[5*2+:2]=2'd0;
 assign arcache[0*4+:4]=sf_arcache;assign arcache[1*4+:4]=qf_arcache;assign arcache[2*4+:4]=vr_arcache;
 assign arcache[3*4+:4]=4'd0;assign arcache[4*4+:4]=lr_arcache;assign arcache[5*4+:4]=4'd0;
 assign arprot[0*3+:3]=sf_arprot;assign arprot[1*3+:3]=qf_arprot;assign arprot[2*3+:3]=vr_arprot;
 assign arprot[3*3+:3]=3'd0;assign arprot[4*3+:3]=lr_arprot;assign arprot[5*3+:3]=3'd0;
 assign arvalid[0]=sf_arvalid;assign arvalid[1]=qf_arvalid;assign arvalid[2]=vr_arvalid;
 assign arvalid[3]=1'b0;assign arvalid[4]=lr_arvalid;assign arvalid[5]=1'b0;
 assign sf_arready=arready[0];assign qf_arready=arready[1];assign vr_arready=arready[2];
 assign lr_arready=arready[4];
 assign sf_rdata=rdata[0*128+:128];assign qf_rdata=rdata[1*128+:128];
 assign vr_rdata=rdata[2*128+:128];assign lr_rdata=rdata[4*128+:128];
 assign sf_rresp=rresp[0*2+:2];assign qf_rresp=rresp[1*2+:2];
 assign vr_rresp=rresp[2*2+:2];assign lr_rresp=rresp[4*2+:2];
 assign sf_rlast=rlast[0];assign qf_rlast=rlast[1];assign vr_rlast=rlast[2];assign lr_rlast=rlast[4];
 assign sf_rvalid=rvalid[0];assign qf_rvalid=rvalid[1];assign vr_rvalid=rvalid[2];assign lr_rvalid=rvalid[4];
 assign rready[0]=sf_rready;assign rready[1]=qf_rready;assign rready[2]=vr_rready;
 assign rready[3]=1'b1;assign rready[4]=lr_rready;assign rready[5]=1'b1;
 assign awaddr[0*40+:40]=40'd0;assign awaddr[1*40+:40]=40'd0;assign awaddr[2*40+:40]=40'd0;
 assign awaddr[3*40+:40]=vw_awaddr;assign awaddr[4*40+:40]=40'd0;assign awaddr[5*40+:40]=lw_awaddr;
 assign awlen[0*8+:8]=8'd0;assign awlen[1*8+:8]=8'd0;assign awlen[2*8+:8]=8'd0;
 assign awlen[3*8+:8]=vw_awlen;assign awlen[4*8+:8]=8'd0;assign awlen[5*8+:8]=lw_awlen;
 assign awsize[0*3+:3]=3'd0;assign awsize[1*3+:3]=3'd0;assign awsize[2*3+:3]=3'd0;
 assign awsize[3*3+:3]=vw_awsize;assign awsize[4*3+:3]=3'd0;assign awsize[5*3+:3]=lw_awsize;
 assign awburst[0*2+:2]=2'd0;assign awburst[1*2+:2]=2'd0;assign awburst[2*2+:2]=2'd0;
 assign awburst[3*2+:2]=vw_awburst;assign awburst[4*2+:2]=2'd0;assign awburst[5*2+:2]=lw_awburst;
 assign awcache[0*4+:4]=4'd0;assign awcache[1*4+:4]=4'd0;assign awcache[2*4+:4]=4'd0;
 assign awcache[3*4+:4]=vw_awcache;assign awcache[4*4+:4]=4'd0;assign awcache[5*4+:4]=lw_awcache;
 assign awprot[0*3+:3]=3'd0;assign awprot[1*3+:3]=3'd0;assign awprot[2*3+:3]=3'd0;
 assign awprot[3*3+:3]=vw_awprot;assign awprot[4*3+:3]=3'd0;assign awprot[5*3+:3]=lw_awprot;
 assign awvalid[0]=1'b0;assign awvalid[1]=1'b0;assign awvalid[2]=1'b0;
 assign awvalid[3]=vw_awvalid;assign awvalid[4]=1'b0;assign awvalid[5]=lw_awvalid;
 assign vw_awready=awready[3];assign lw_awready=awready[5];
 assign wdata[0*128+:128]=128'd0;assign wdata[1*128+:128]=128'd0;assign wdata[2*128+:128]=128'd0;
 assign wdata[3*128+:128]=vw_wdata;assign wdata[4*128+:128]=128'd0;assign wdata[5*128+:128]=lw_wdata;
 assign wstrb[0*16+:16]=16'd0;assign wstrb[1*16+:16]=16'd0;assign wstrb[2*16+:16]=16'd0;
 assign wstrb[3*16+:16]=vw_wstrb;assign wstrb[4*16+:16]=16'd0;assign wstrb[5*16+:16]=lw_wstrb;
 assign wlast[0]=1'b0;assign wlast[1]=1'b0;assign wlast[2]=1'b0;
 assign wlast[3]=vw_wlast;assign wlast[4]=1'b0;assign wlast[5]=lw_wlast;
 assign wvalid[0]=1'b0;assign wvalid[1]=1'b0;assign wvalid[2]=1'b0;
 assign wvalid[3]=vw_wvalid;assign wvalid[4]=1'b0;assign wvalid[5]=lw_wvalid;
 assign vw_wready=wready[3];assign lw_wready=wready[5];
 assign vw_bvalid=bvalid[3];assign lw_bvalid=bvalid[5];
 assign vw_bresp=bresp[3*2+:2];assign lw_bresp=bresp[5*2+:2];
 assign bready[0]=1'b1;assign bready[1]=1'b1;assign bready[2]=1'b1;
 assign bready[3]=vw_bready;assign bready[4]=1'b1;assign bready[5]=lw_bready;
 wc_axi_bfm #(.PORTS(6)) ddr(.clk(clk),.rst_n(rst_n),
  .araddr(araddr),.arlen(arlen),.arsize(arsize),.arburst(arburst),.arvalid(arvalid),.arready(arready),
  .rdata(rdata),.rresp(rresp),.rlast(rlast),.rvalid(rvalid),.rready(rready),
  .awaddr(awaddr),.awlen(awlen),.awsize(awsize),.awburst(awburst),.awvalid(awvalid),.awready(awready),
  .wdata(wdata),.wstrb(wstrb),.wlast(wlast),.wvalid(wvalid),.wready(wready),
  .bresp(bresp),.bvalid(bvalid),.bready(bready),
  .inject_read_error(1'b0),.inject_write_error(1'b0));
 // External matrix stub: control-only; never used as numeric evidence.
 reg mbusy=0;reg [31:0] mtimer=0;reg mdone=0,mfault=0;reg mfail=0,dma_mode=0;
 assign matrix_ready=!mbusy;
 assign matrix_done=mdone;assign matrix_fault=mfault;
 always @(posedge clk)if(rst_n)begin
  mdone<=0;mfault<=0;
  if(matrix_valid&&matrix_ready)begin mbusy<=1;mtimer<=20;end
  if(mbusy)begin if(mtimer==0)begin mbusy<=0;mdone<=1;mfault<=mfail;end else mtimer<=mtimer-1;end
 end
 always @(posedge clk)if(rst_n)begin cycle<=cycle+1;if(done)done_pulses<=done_pulses+1;
  if($test$plusargs("verbose")&&cycle%500==0)
   $display("TOP c=%0d st=%0d busy=%b seq=%b vec=%b lay=%b done=%b fault=%b comp=%0d sf_ar=%b/%b addr=%h len=%h sf_r=%b/%b rl=%b done=%b hgot=%0d cyc=%0d",cycle,dut.ctrl.state,dut.busy,seq_busy,vector_busy,layout_busy,done,fault,completed,sf_arvalid,sf_arready,sf_araddr,sf_arlen,sf_rvalid,sf_rready,sf_rlast,dut.ctrl.fetch_done,dut.ctrl.hgot,ddr.cycle);
  if($test$plusargs("verbose")&&cycle%500==0)$display("BFM ra=%b vis=%b ri=%0d rn=%0d rv=%b rr=%b rl=%b",ddr.ra[0],ddr.vis[0],ddr.ri[0],ddr.rn[0],ddr.rvalid[0],ddr.rready[0],ddr.rlast[0]);
  if($test$plusargs("verbose")&&cycle%500==0)$display("LAY st=%0d lr=%b/%b rv=%b/%b lw=%b/%b wv=%b/%b bv=%b/%b rb=%0d wb=%0d",dut.lay.arithmetic.state,lr_arvalid,lr_arready,lr_rvalid,lr_rready,lw_awvalid,lw_awready,lw_wvalid,lw_wready,lw_bvalid,lw_bready,dut.lay.arithmetic.read_got,dut.lay.arithmetic.output_valid);
 end
 integer i;reg [1023:0] memfile,goldfile;
 initial begin
  if(!$value$plusargs("mode=%d",mode))mode=10;
  if(!$value$plusargs("plan=%h",plan_base))plan_base=32'h10008000;
  if(!$value$plusargs("memfile=%s",memfile))memfile="tests/fixtures/mem_init.hex";
  if(mode==10)begin check_base=32'h04002000;goldfile="tests/fixtures/gold_mode10.hex";end
  else if(mode==11)begin check_base=32'h04004000;goldfile="tests/fixtures/gold_mode11.hex";end
  else begin check_base=32'h04006000;goldfile="tests/fixtures/gold_mode12.hex";end
  $readmemh(goldfile,gold);
  repeat(5)@(negedge clk);rst_n=1;repeat(2)@(negedge clk);
  start=1;@(negedge clk);start=0;
  if($test$plusargs("verbose"))$display("TOP start plan=%h",plan_base);
  wait(done||cycle>500000);
  @(negedge clk);@(negedge clk);
  if(cycle>500000)$fatal(1,"timeout state=%d busy=%b seq=%b vec=%b lay=%b",dut.ctrl.state,busy,seq_busy,vector_busy,layout_busy);
  if(fault)begin
   $display("FAULTDBG st=%0d hash=%h hh=%h ngot=%0d ni=%0d nbuf0=%h nbuf1=%h nbuf7=%h nbuf8=%h",dut.ctrl.state,dut.ctrl.hash,dut.ctrl.header[255:224],dut.ctrl.ngot,dut.ctrl.nfetch_index,dut.ctrl.node_buf[31:0],dut.ctrl.node_buf[63:32],dut.ctrl.node_buf[255:224],dut.ctrl.node_buf[287:256]);
   $display("SEQDBG ec=%h idx=%0d cnt=%0d ins0=%h ins1=%h ins2=%h ins3=%h ins4=%h ins5=%h",dut.seqpl.error_code,dut.seqpl.index,dut.seqpl.count,dut.seqpl.instruction[31:0],dut.seqpl.instruction[63:32],dut.seqpl.instruction[95:64],dut.seqpl.instruction[127:96],dut.seqpl.instruction[159:128],dut.seqpl.instruction[191:160]);
   $fatal(1,"fault err=%h completed=%d",error_code,completed);
  end
  if(mode==10&&completed!=3)$fatal(1,"mode10 completed=%d",completed);
  if(mode==11&&completed!=1)$fatal(1,"mode11 completed=%d",completed);
  if(mode==12&&completed!=4)$fatal(1,"mode12 completed=%d",completed);
  if(done_pulses!=1||rejected_starts!=0)$fatal(1,"done/replay pulses=%d rej=%d",done_pulses,rejected_starts);
  if(busy||seq_busy||vector_busy||layout_busy||mbusy)$fatal(1,"done before drain");
  for(i=0;i<64;i=i+1)begin
   g=ddr.peek32(32'h40000+(check_base-32'h04000000)+i*4);
   if(g!==gold[i])$fatal(1,"data mismatch word %0d got=%h want=%h",i,g,gold[i]);
  end
  $display("WC_TOP_PASS mode=%d cycles=%d completed=%d err=%h seq=%b vec=%b lay=%b opcyc=%0d vec_cyc=%0d lay_cyc=%0d seq_cyc=%0d",mode,cycles,completed,error_code,seq_busy,vector_busy,layout_busy,operator_cycles,dut.vec.cycles,dut.lay.cycles,dut.seqpl.cycles);
  $finish;
 end
endmodule
