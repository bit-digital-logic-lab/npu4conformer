`timescale 1ns/1ps
// Real arithmetic chain: IN -> real ddr_layout_axi copy -> real ddr_vector_axi
// ADD -> real ddr_vector_axi MUL.  The only stub is the unused external matrix
// port and the unused SEQ handshake.  All numeric work is the sealed FP32 RTL.
module tb_wc_graph_real;
 reg clk=0;always #4 clk=~clk;
 reg rst_n=0,start=0,parameter_ready=1;
 reg [31:0] plan_base=32'h10008000,param_end=32'h10040000,generation=7;
 integer mode=10,cycle=0,done_pulses=0;
 reg [31:0] gold[0:63];reg [31:0] g;
 wire busy,done,fault,irq,drain_timeout,output_retained;
 wire [7:0] error_code;
 wire [31:0] completed,node_count,rejected_starts,last_node;
 wire [1023:0] done_mask;
 wire [63:0] cycles,fetch_cycles,operator_cycles,drain_cycles;
 wire [31:0] output_count,last_output_tid,last_output_base,last_output_bytes;
 wire seq_busy,vector_busy,layout_busy;
 wire seq_valid,seq_ready,seq_done,seq_fault;
 wire [31:0] seq_base,seq_count;wire [7:0] seq_error;
 wire matrix_valid,matrix_ready,matrix_done,matrix_fault;
 wire [31:0] matrix_queue_base,matrix_queue_count;
 wire [39:0] sf_araddr,vr_araddr,vw_awaddr,lr_araddr,lw_awaddr;
 wire [7:0] sf_arlen,vr_arlen,vw_awlen,lr_arlen,lw_awlen;
 wire [2:0] sf_arsize,vr_arsize,vw_awsize,lr_arsize,lw_awsize;
 wire [1:0] sf_arburst,vr_arburst,vw_awburst,lr_arburst,lw_awburst;
 wire [3:0] sf_arcache,vr_arcache,vw_awcache,lr_arcache,lw_awcache;
 wire [2:0] sf_arprot,vr_arprot,vw_awprot,lr_arprot,lw_awprot;
 wire sf_arvalid,vr_arvalid,vw_awvalid,lr_arvalid,lw_awvalid;
 wire [127:0] sf_rdata,vr_rdata,vw_wdata,lr_rdata,lw_wdata;
 wire [1:0] sf_rresp,vr_rresp,vw_bresp,lr_rresp,lw_bresp;
 wire sf_rlast,vr_rlast,vw_wlast,lr_rlast,lw_wlast;
 wire sf_rvalid,vr_rvalid,vw_wvalid,lr_rvalid,lw_wvalid;
 wire [15:0] sf_wstrb,vw_wstrb,lw_wstrb;
 wire [39:0] sf_awaddr;wire [7:0] sf_awlen;wire [2:0] sf_awsize;
 wire [1:0] sf_awburst;wire [3:0] sf_awcache;wire [2:0] sf_awprot;
 wire [127:0] sf_wdata;wire [1:0] sf_bresp;
 wire sf_wlast,sf_wvalid,sf_awvalid,sf_bvalid;
 wire sf_arready,sf_awready,sf_wready,sf_bready;
 wire vr_arready,vw_awready,vw_wready,vw_bready,lr_arready,lw_awready,lw_wready,lw_bready;
 wire sf_rready,vr_rready,lr_rready;
 wire [31:0] bfm_rb,bfm_wb,bfm_rbeats,bfm_wbeats;
 wire [39:0] araddr[0:4],awaddr[0:4];
 wire [7:0] arlen[0:4],awlen[0:4];
 wire [2:0] arsize[0:4],awsize[0:4];
 wire [1:0] arburst[0:4],awburst[0:4];
 wire [3:0] arcache[0:4],awcache[0:4];
 wire [2:0] arprot[0:4],awprot[0:4];
 wire arvalid[0:4],arready[0:4],awvalid[0:4],awready[0:4];
 wire [127:0] rdata[0:4],wdata[0:4];
 wire [1:0] rresp[0:4],bresp[0:4];
 wire [15:0] wstrb[0:4];
 wire rlast[0:4],rvalid[0:4],rready[0:4],wlast[0:4],wvalid[0:4],wready[0:4];
 wire bvalid[0:4],bready[0:4];

 assign seq_ready=1'b0;assign seq_done=1'b0;assign seq_fault=1'b0;assign seq_error=8'd0;
 assign matrix_ready=1'b1;assign matrix_done=1'b0;assign matrix_fault=1'b0;
 assign araddr[0]=sf_araddr;assign arlen[0]=sf_arlen;assign arsize[0]=sf_arsize;
 assign arburst[0]=sf_arburst;assign arcache[0]=sf_arcache;assign arprot[0]=sf_arprot;
 assign arvalid[0]=sf_arvalid;assign sf_arready=arready[0];
 assign sf_rdata=rdata[0];assign sf_rresp=rresp[0];assign sf_rlast=rlast[0];
 assign sf_rvalid=rvalid[0];assign rready[0]=sf_rready;
 assign araddr[1]=vr_araddr;assign arlen[1]=vr_arlen;assign arsize[1]=vr_arsize;
 assign arburst[1]=vr_arburst;assign arcache[1]=vr_arcache;assign arprot[1]=vr_arprot;
 assign arvalid[1]=vr_arvalid;assign vr_arready=arready[1];
 assign vr_rdata=rdata[1];assign vr_rresp=rresp[1];assign vr_rlast=rlast[1];
 assign vr_rvalid=rvalid[1];assign rready[1]=vr_rready;
 assign awaddr[2]=vw_awaddr;assign awlen[2]=vw_awlen;assign awsize[2]=vw_awsize;
 assign awburst[2]=vw_awburst;assign awcache[2]=vw_awcache;assign awprot[2]=vw_awprot;
 assign awvalid[2]=vw_awvalid;assign vw_awready=awready[2];
 assign wdata[2]=vw_wdata;assign wstrb[2]=vw_wstrb;assign wlast[2]=vw_wlast;
 assign wvalid[2]=vw_wvalid;assign vw_wready=wready[2];
 assign vw_bvalid=bvalid[2];assign vw_bresp=bresp[2];assign bready[2]=vw_bready;
 assign araddr[3]=lr_araddr;assign arlen[3]=lr_arlen;assign arsize[3]=lr_arsize;
 assign arburst[3]=lr_arburst;assign arcache[3]=lr_arcache;assign arprot[3]=lr_arprot;
 assign arvalid[3]=lr_arvalid;assign lr_arready=arready[3];
 assign lr_rdata=rdata[3];assign lr_rresp=rresp[3];assign lr_rlast=rlast[3];
 assign lr_rvalid=rvalid[3];assign rready[3]=lr_rready;
 assign awaddr[4]=lw_awaddr;assign awlen[4]=lw_awlen;assign awsize[4]=lw_awsize;
 assign awburst[4]=lw_awburst;assign awcache[4]=lw_awcache;assign awprot[4]=lw_awprot;
 assign awvalid[4]=lw_awvalid;assign lw_awready=awready[4];
 assign wdata[4]=lw_wdata;assign wstrb[4]=lw_wstrb;assign wlast[4]=lw_wlast;
 assign wvalid[4]=lw_wvalid;assign lw_wready=wready[4];
 assign lw_bvalid=bvalid[4];assign lw_bresp=bresp[4];assign bready[4]=lw_bready;
 assign awaddr[0]=40'd0;assign awlen[0]=8'd0;assign awsize[0]=3'd0;
 assign awburst[0]=2'd0;assign awcache[0]=4'd0;assign awprot[0]=3'd0;
 assign awvalid[0]=1'b0;assign wdata[0]=128'd0;assign wstrb[0]=16'd0;
 assign wlast[0]=1'b0;assign wvalid[0]=1'b0;assign bready[0]=1'b1;
 assign awaddr[1]=40'd0;assign awlen[1]=8'd0;assign awsize[1]=3'd0;
 assign awburst[1]=2'd0;assign awcache[1]=4'd0;assign awprot[1]=3'd0;
 assign awvalid[1]=1'b0;assign wdata[1]=128'd0;assign wstrb[1]=16'd0;
 assign wlast[1]=1'b0;assign wvalid[1]=1'b0;assign bready[1]=1'b1;
 assign araddr[2]=40'd0;assign arlen[2]=8'd0;assign arsize[2]=3'd0;
 assign arburst[2]=2'd0;assign arcache[2]=4'd0;assign arprot[2]=3'd0;
 assign arvalid[2]=1'b0;assign rready[2]=1'b1;
 assign araddr[4]=40'd0;assign arlen[4]=8'd0;assign arsize[4]=3'd0;
 assign arburst[4]=2'd0;assign arcache[4]=4'd0;assign arprot[4]=3'd0;
 assign arvalid[4]=1'b0;assign rready[4]=1'b1;
 assign bready[3]=1'b1;

 wc_graph_top #(.MAX_NODES(1024)) dut(
  .clk(clk),.rst_n(rst_n),.start(start),.plan_base(plan_base),.param_end(param_end),
  .parameter_ready(parameter_ready),.generation(generation),
  .busy(busy),.done(done),.fault(fault),.irq(irq),.drain_timeout(drain_timeout),
  .error_code(error_code),.completed(completed),.node_count(node_count),
  .rejected_starts(rejected_starts),.last_node(last_node),.done_mask(done_mask),
  .cycles(cycles),.fetch_cycles(fetch_cycles),.operator_cycles(operator_cycles),
  .drain_cycles(drain_cycles),.output_retained(output_retained),
  .output_count(output_count),.last_output_tid(last_output_tid),
  .last_output_base(last_output_base),.last_output_bytes(last_output_bytes),
  .seq_busy(seq_busy),.vector_busy(vector_busy),.layout_busy(layout_busy),
  .seq_valid(seq_valid),.seq_ready(seq_ready),.seq_base(seq_base),.seq_count(seq_count),
  .seq_done(seq_done),.seq_fault(seq_fault),.seq_error(seq_error),
  .matrix_valid(matrix_valid),.matrix_ready(matrix_ready),
  .matrix_queue_base(matrix_queue_base),.matrix_queue_count(matrix_queue_count),
  .matrix_done(matrix_done),.matrix_fault(matrix_fault),
  .sf_araddr(sf_araddr),.sf_arlen(sf_arlen),.sf_arsize(sf_arsize),
  .sf_arburst(sf_arburst),.sf_arcache(sf_arcache),.sf_arprot(sf_arprot),
  .sf_arvalid(sf_arvalid),.sf_arready(sf_arready),.sf_rdata(sf_rdata),
  .sf_rresp(sf_rresp),.sf_rlast(sf_rlast),.sf_rvalid(sf_rvalid),.sf_rready(sf_rready),
  .sf_awaddr(sf_awaddr),.sf_awlen(sf_awlen),.sf_awsize(sf_awsize),
  .sf_awburst(sf_awburst),.sf_awcache(sf_awcache),.sf_awprot(sf_awprot),
  .sf_awvalid(sf_awvalid),.sf_awready(sf_awready),.sf_wdata(sf_wdata),
  .sf_wstrb(sf_wstrb),.sf_wlast(sf_wlast),.sf_wvalid(sf_wvalid),.sf_wready(sf_wready),
  .sf_bresp(sf_bresp),.sf_bvalid(sf_bvalid),.sf_bready(sf_bready),
  .vr_araddr(vr_araddr),.vr_arlen(vr_arlen),.vr_arsize(vr_arsize),
  .vr_arburst(vr_arburst),.vr_arcache(vr_arcache),.vr_arprot(vr_arprot),
  .vr_arvalid(vr_arvalid),.vr_arready(vr_arready),.vr_rdata(vr_rdata),
  .vr_rresp(vr_rresp),.vr_rlast(vr_rlast),.vr_rvalid(vr_rvalid),.vr_rready(vr_rready),
  .vw_awaddr(vw_awaddr),.vw_awlen(vw_awlen),.vw_awsize(vw_awsize),
  .vw_awburst(vw_awburst),.vw_awcache(vw_awcache),.vw_awprot(vw_awprot),
  .vw_awvalid(vw_awvalid),.vw_awready(vw_awready),.vw_wdata(vw_wdata),
  .vw_wstrb(vw_wstrb),.vw_wlast(vw_wlast),.vw_wvalid(vw_wvalid),.vw_wready(vw_wready),
  .vw_bresp(vw_bresp),.vw_bvalid(vw_bvalid),.vw_bready(vw_bready),
  .lr_araddr(lr_araddr),.lr_arlen(lr_arlen),.lr_arsize(lr_arsize),
  .lr_arburst(lr_arburst),.lr_arcache(lr_arcache),.lr_arprot(lr_arprot),
  .lr_arvalid(lr_arvalid),.lr_arready(lr_arready),.lr_rdata(lr_rdata),
  .lr_rresp(lr_rresp),.lr_rlast(lr_rlast),.lr_rvalid(lr_rvalid),.lr_rready(lr_rready),
  .lw_awaddr(lw_awaddr),.lw_awlen(lw_awlen),.lw_awsize(lw_awsize),
  .lw_awburst(lw_awburst),.lw_awcache(lw_awcache),.lw_awprot(lw_awprot),
  .lw_awvalid(lw_awvalid),.lw_awready(lw_awready),.lw_wdata(lw_wdata),
  .lw_wstrb(lw_wstrb),.lw_wlast(lw_wlast),.lw_wvalid(lw_wvalid),.lw_wready(lw_wready),
  .lw_bresp(lw_bresp),.lw_bvalid(lw_bvalid),.lw_bready(lw_bready));

 wc_graph_bfm #(.PORTS(5)) ddr(.clk(clk),.rst_n(rst_n),
  .araddr({araddr[4],araddr[3],araddr[2],araddr[1],araddr[0]}),
  .arlen({arlen[4],arlen[3],arlen[2],arlen[1],arlen[0]}),
  .arsize({arsize[4],arsize[3],arsize[2],arsize[1],arsize[0]}),
  .arburst({arburst[4],arburst[3],arburst[2],arburst[1],arburst[0]}),
  .arvalid({arvalid[4],arvalid[3],arvalid[2],arvalid[1],arvalid[0]}),
  .arready({arready[4],arready[3],arready[2],arready[1],arready[0]}),
  .rdata({rdata[4],rdata[3],rdata[2],rdata[1],rdata[0]}),
  .rresp({rresp[4],rresp[3],rresp[2],rresp[1],rresp[0]}),
  .rlast({rlast[4],rlast[3],rlast[2],rlast[1],rlast[0]}),
  .rvalid({rvalid[4],rvalid[3],rvalid[2],rvalid[1],rvalid[0]}),
  .rready({rready[4],rready[3],rready[2],rready[1],rready[0]}),
  .awaddr({awaddr[4],awaddr[3],awaddr[2],awaddr[1],awaddr[0]}),
  .awlen({awlen[4],awlen[3],awlen[2],awlen[1],awlen[0]}),
  .awsize({awsize[4],awsize[3],awsize[2],awsize[1],awsize[0]}),
  .awburst({awburst[4],awburst[3],awburst[2],awburst[1],awburst[0]}),
  .awvalid({awvalid[4],awvalid[3],awvalid[2],awvalid[1],awvalid[0]}),
  .awready({awready[4],awready[3],awready[2],awready[1],awready[0]}),
  .wdata({wdata[4],wdata[3],wdata[2],wdata[1],wdata[0]}),
  .wstrb({wstrb[4],wstrb[3],wstrb[2],wstrb[1],wstrb[0]}),
  .wlast({wlast[4],wlast[3],wlast[2],wlast[1],wlast[0]}),
  .wvalid({wvalid[4],wvalid[3],wvalid[2],wvalid[1],wvalid[0]}),
  .wready({wready[4],wready[3],wready[2],wready[1],wready[0]}),
  .bresp({bresp[4],bresp[3],bresp[2],bresp[1],bresp[0]}),
  .bvalid({bvalid[4],bvalid[3],bvalid[2],bvalid[1],bvalid[0]}),
  .bready({bready[4],bready[3],bready[2],bready[1],bready[0]}),
  .inject_read_error(1'b0),.inject_write_error(1'b0),
  .read_bursts(bfm_rb),.write_bursts(bfm_wb),
  .read_beats(bfm_rbeats),.write_beats(bfm_wbeats));

 integer i,vec_cycles=0,lay_cycles=0;
 always @(posedge clk)if(rst_n)begin
  if(dut.ctrl.lay_valid||dut.ctrl.vec_valid||dut.ctrl.seq_valid||dut.ctrl.mat_valid)
   $display("DISPATCH c=%0d layv=%b layr=%b vecv=%b vecr=%b tgt=%0d type=%0d",cycle,
    dut.ctrl.lay_valid,dut.ctrl.lay_ready,dut.ctrl.vec_valid,dut.ctrl.vec_ready,
    dut.ctrl.target,dut.ctrl.nd_meta[dut.ctrl.target][63:32]);
  if(cycle>=140&&cycle<=160)
   $display("TRACE c=%0d cst=%0d st=%0d start=%b ready=%b busy=%b rdr=%b wrr=%b",cycle,dut.ctrl.state,
    dut.lay.arithmetic.state,dut.lay.start,dut.lay.ready,dut.lay.busy,
    dut.lay.arithmetic.rd_request_ready,dut.lay.arithmetic.wr_request_ready);
  if(cycle>=150&&cycle<=160)
   $display("DONE c=%0d laydone=%b layfault=%b err=%h eact=%b",cycle,dut.ctrl.lay_done,dut.ctrl.lay_fault,dut.lay.error_code,dut.ctrl.e_active);
  if(dut.ctrl.lay_valid)
   $display("LAYSTART laystart=%b arithstart=%b arithstate=%0d layready=%b laybusy=%b desc0=%h",
    dut.lay.start,dut.lay.arithmetic.start,dut.lay.arithmetic.state,dut.lay.ready,dut.lay.busy,
    dut.lay.descriptor[31:0]);
  cycle<=cycle+1;if(done)done_pulses<=done_pulses+1;
  if(vector_busy)vec_cycles<=vec_cycles+1;
  if(layout_busy)lay_cycles<=lay_cycles+1;
  if($test$plusargs("verbose")&&cycle%2000==0)
   $display("REAL c=%0d st=%0d arv=%b arr=%b rv=%b rr=%b rl=%b sf_done=%b err=%b a=%h len=%h bfm_ra=%b vis=%b ri=%0d rn=%0d",
    cycle,dut.ctrl.state,sf_arvalid,sf_arready,sf_rvalid,sf_rready,sf_rlast,dut.sf_done,dut.sf_err,
    sf_araddr,sf_arlen,ddr.ra[0],ddr.vis[0],ddr.ri[0],ddr.rn[0]);
  if($test$plusargs("verbose")&&cycle%2000==0)
   $display("SCAN idx=%0d n0state=%0d dep0=%h comp=%0d nc=%0d meta0=%h flags0=%h type0=%0d eact=%b",
    dut.ctrl.scan_idx,dut.ctrl.nstate[0],dut.ctrl.nd_dep[0],dut.ctrl.completed,dut.ctrl.node_count,
    dut.ctrl.nd_meta[0][31:0],dut.ctrl.nd_meta[0][127:96],dut.ctrl.nd_meta[0][63:32],dut.ctrl.e_active);
  if($test$plusargs("verbose")&&cycle%2000==0)
   $display("LAY busy=%b ready=%b done=%b fault=%b st=%0d lr_arv=%b/%b rv=%b/%b rl=%b lw_awv=%b/%b wv=%b/%b bv=%b/%b",
    layout_busy,dut.lay.ready,dut.ctrl.lay_done,dut.ctrl.lay_fault,dut.lay.arithmetic.state,
    lr_arvalid,lr_arready,lr_rvalid,lr_rready,lr_rlast,lw_awvalid,lw_awready,lw_wvalid,lw_wready,lw_bvalid,lw_bready);
 end
 initial begin
  if(!$value$plusargs("mode=%d",mode))mode=10;
  $readmemh("tests/fixtures/gold_small.hex",gold);
  repeat(5)@(negedge clk);rst_n=1;repeat(2)@(negedge clk);
  start=1;@(negedge clk);start=0;
  wait(done||cycle>200000);
  @(negedge clk);@(negedge clk);
  if(cycle>200000)$fatal(1,"timeout state=%d",dut.ctrl.state);
  if(fault)$fatal(1,"fault err=%h",error_code);
  if(done_pulses!=1)$fatal(1,"done pulses=%d",done_pulses);
  if(completed!==4)$fatal(1,"completed=%d",completed);
  if(busy||vector_busy||layout_busy)$fatal(1,"busy after done");
  if(!output_retained||output_count!==1)$fatal(1,"output retention");
  if(last_output_base!==32'h04002000||last_output_bytes!==256)
   $fatal(1,"last output %h/%d",last_output_base,last_output_bytes);
  for(i=0;i<64;i=i+1)begin
   g=ddr.peek32(32'h40000+(32'h04002000-32'h04000000)+i*4);
   if(g!==gold[i])$fatal(1,"word %0d got %h want %h",i,g,gold[i]);
  end
  if(bfm_wb==0||bfm_rb==0)$fatal(1,"no data DMA");
  if(vec_cycles==0||lay_cycles==0)$fatal(1,"engine not active");
  $display("WC_GRAPH_REAL_PASS mode=%d cycles=%d completed=%d err=%h fetch=%d rb=%d wb=%d rbeats=%d wbeats=%d vec_cyc=%d lay_cyc=%d out=%h/%d",
   mode,cycles,completed,error_code,fetch_cycles,bfm_rb,bfm_wb,bfm_rbeats,bfm_wbeats,
   vec_cycles,lay_cycles,last_output_base,last_output_bytes);
  $finish;
 end
endmodule
