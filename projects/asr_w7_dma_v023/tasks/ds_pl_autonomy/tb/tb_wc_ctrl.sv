`timescale 1ns/1ps
// Control-only test for wc_superplan_ctrl.  Engines are labelled stubs: they
// only prove scheduling/dependency/drain/IRQ behaviour and never claim numeric
// correctness.  Real operator data chains are in tb_wc_top.sv.
module tb_wc_ctrl;
 reg clk=0;always #4 clk=~clk;
 reg rst_n=0,start=0,parameter_ready=1;
 reg [31:0] plan_base=32'h10000000,param_end=32'h10040000,generation=7;
 integer mode=0,dly_seq=20,dly_mat=15,dly_vec=25,dly_lay=12,fault_mat=0,fault_vec=0;
 integer cycle=0,seq_calls=0,mat_calls=0,vec_calls=0,lay_calls=0,done_pulses=0;
 integer order[0:127];integer norder=0;
 wire busy,done,fault,irq,drain_timeout,direct_idle;
 wire [7:0] error_code;
 wire [31:0] completed,node_count,rejected_starts,last_node;
 wire [127:0] done_mask;
 wire [63:0] cycles,fetch_cycles,operator_cycles,drain_cycles;
 wire fetch_req_valid,fetch_req_ready,fetch_read_valid,fetch_read_ready,fetch_done,fetch_error;
 wire [31:0] fetch_address;wire [15:0] fetch_beats,fetch_read_index;wire [127:0] fetch_read_data;
 wire seq_valid,seq_ready,seq_done,seq_fault;wire [31:0] seq_base,seq_count;
 wire mat_valid,mat_ready,mat_done,mat_fault;wire [31:0] mat_base,mat_count;
 wire vec_valid,vec_ready,vec_done,vec_fault;wire [511:0] vec_descriptor;
 wire lay_valid,lay_ready,lay_done,lay_fault;wire [1023:0] lay_descriptor;
 wire [7:0] seq_error,mat_error,vec_error,lay_error;
 wc_superplan_ctrl dut(.clk(clk),.rst_n(rst_n),.start(start),.plan_base(plan_base),
  .param_end(param_end),.parameter_ready(parameter_ready),.generation(generation),
  .busy(busy),.done(done),.fault(fault),.error_code(error_code),.completed(completed),
  .node_count(node_count),.rejected_starts(rejected_starts),.last_node(last_node),
  .done_mask(done_mask),.cycles(cycles),.fetch_cycles(fetch_cycles),
  .operator_cycles(operator_cycles),.drain_cycles(drain_cycles),.drain_timeout(drain_timeout),
  .irq(irq),
  .fetch_req_valid(fetch_req_valid),.fetch_req_ready(fetch_req_ready),
  .fetch_address(fetch_address),.fetch_beats(fetch_beats),
  .fetch_read_valid(fetch_read_valid),.fetch_read_ready(fetch_read_ready),
  .fetch_read_data(fetch_read_data),.fetch_read_index(fetch_read_index),
  .fetch_done(fetch_done),.fetch_error(fetch_error),
  .seq_valid(seq_valid),.seq_ready(seq_ready),.seq_base(seq_base),.seq_count(seq_count),
  .seq_done(seq_done),.seq_fault(seq_fault),.seq_error(seq_error),
  .mat_valid(mat_valid),.mat_ready(mat_ready),.mat_base(mat_base),.mat_count(mat_count),
  .mat_done(mat_done),.mat_fault(mat_fault),.mat_error(mat_error),
  .vec_valid(vec_valid),.vec_ready(vec_ready),.vec_descriptor(vec_descriptor),
  .vec_done(vec_done),.vec_fault(vec_fault),.vec_error(vec_error),
  .lay_valid(lay_valid),.lay_ready(lay_ready),.lay_descriptor(lay_descriptor),
  .lay_done(lay_done),.lay_fault(lay_fault),.lay_error(lay_error),
  .direct_idle(direct_idle));
 // Fetch DMA is the real sealed axi_dma_v019, not a stub.
 wire [39:0] faraddr;wire [7:0] farlen;wire [2:0] farsize;wire [1:0] farburst;
 wire [3:0] farcache;wire [2:0] farprot;wire farvalid,farready,frvalid,frready,frlast;
 wire [127:0] frdata;wire [1:0] frresp;wire [15:0] fri;
 wire [39:0] fawaddr;wire [7:0] fawlen;wire [2:0] fawsize;wire [1:0] fawburst;
 wire [3:0] fawcache;wire [2:0] fawprot;wire fawvalid,fawready,fwvalid,fwready,fwlast;
 wire [127:0] fwdata;wire [15:0] fwstrb;wire [1:0] fbresp;wire fbvalid,fbready;
 axi_dma_v019 fdma(.clk(clk),.rst_n(rst_n),.request_valid(fetch_req_valid),
  .request_ready(fetch_req_ready),.request_write(1'b0),.request_address(fetch_address),
  .request_beats(fetch_beats),.read_valid(fetch_read_valid),.read_ready(fetch_read_ready),
  .read_data(fetch_read_data),.read_index(fetch_read_index),
  .write_valid(1'b0),.write_ready(),.write_data(128'd0),.write_strobe(16'd0),.write_index(),
  .done(fetch_done),.error(fetch_error),.read_bytes(),.write_bytes(),.read_bursts(),.write_bursts(),
  .m_axi_araddr(faraddr),.m_axi_arlen(farlen),.m_axi_arsize(farsize),.m_axi_arburst(farburst),
  .m_axi_arcache(farcache),.m_axi_arprot(farprot),.m_axi_arvalid(farvalid),.m_axi_arready(farready),
  .m_axi_rdata(frdata),.m_axi_rresp(frresp),.m_axi_rlast(frlast),.m_axi_rvalid(frvalid),.m_axi_rready(frready),
  .m_axi_awaddr(fawaddr),.m_axi_awlen(fawlen),.m_axi_awsize(fawsize),.m_axi_awburst(fawburst),
  .m_axi_awcache(fawcache),.m_axi_awprot(fawprot),.m_axi_awvalid(fawvalid),.m_axi_awready(fawready),
  .m_axi_wdata(fwdata),.m_axi_wstrb(fwstrb),.m_axi_wlast(fwlast),.m_axi_wvalid(fwvalid),.m_axi_wready(fwready),
  .m_axi_bresp(fbresp),.m_axi_bvalid(fbvalid),.m_axi_bready(fbready));
 wc_axi_bfm #(.PORTS(1)) ddr(.clk(clk),.rst_n(rst_n),
  .araddr(faraddr),.arlen(farlen),.arsize(farsize),.arburst(farburst),.arvalid(farvalid),.arready(farready),
  .rdata(frdata),.rresp(frresp),.rlast(frlast),.rvalid(frvalid),.rready(frready),
  .awaddr(fawaddr),.awlen(fawlen),.awsize(fawsize),.awburst(fawburst),.awvalid(fawvalid),.awready(fawready),
  .wdata(fwdata),.wstrb(fwstrb),.wlast(fwlast),.wvalid(fwvalid),.wready(fwready),
  .bresp(fbresp),.bvalid(fbvalid),.bready(fbready),
  .inject_read_error(1'b0),.inject_write_error(1'b0));
 // Stub engines: control evidence only.
 reg sbusy=0,mbusy=0,vbusy=0,lbusi=0;integer stim=0,mtim=0,vtim=0,ltim=0;
 reg sd=0,md=0,vd=0,ld=0,sf=0,mf=0,vf=0,lf=0;
 assign seq_ready=!sbusy;assign mat_ready=!mbusy;assign vec_ready=!vbusy;assign lay_ready=!lbusi;
 assign seq_done=sd;assign seq_fault=sf;assign seq_error=8'h44;
 assign mat_done=md;assign mat_fault=mf;assign mat_error=8'h55;
 assign vec_done=vd;assign vec_fault=vf;assign vec_error=8'h66;
 assign lay_done=ld;assign lay_fault=lf;assign lay_error=8'h77;
 task push(input integer v);begin order[norder]=v;norder=norder+1;end endtask
`ifdef WC_DEBUG
 always @(posedge clk)if(rst_n&&cycle<400)
  $display("DBG c=%0d st=%0d ns0=%0d t0=%0d dm=%h comp=%0d fl=%b act=%b req=%b rdy=%b rv=%b rr=%b fd=%b fe=%b ngot=%0d hgot=%0d ni=%0d hc=%0d typ=%0d",
   cycle,dut.state,dut.nstate[0],dut.nd[0][63:32],done_mask,completed,dut.fault_latched,dut.e_active,fetch_req_valid,fetch_req_ready,fetch_read_valid,fetch_read_ready,
   fetch_done,fetch_error,dut.ngot,dut.hgot,dut.nfetch_index,dut.header[95:64],dut.node_buf[63:32]);
`endif
 always @(posedge clk)if(rst_n)begin
  sd<=0;md<=0;vd<=0;ld<=0;sf<=0;mf<=0;vf<=0;lf<=0;cycle<=cycle+1;
  if(seq_valid&&seq_ready)begin sbusy<=1;stim<=(seq_base[15:0]==16'h7000)?dly_seq+80:dly_seq;seq_calls<=seq_calls+1;push(100+node_count);end
  if(mat_valid&&mat_ready)begin mbusy<=1;mtim<=dly_mat;mat_calls<=mat_calls+1;end
  if(vec_valid&&vec_ready)begin vbusy<=1;vtim<=dly_vec;vec_calls<=vec_calls+1;end
  if(lay_valid&&lay_ready)begin lbusi<=1;ltim<=dly_lay;lay_calls<=lay_calls+1;end
  if(sbusy)begin if(stim==0)begin sbusy<=0;sd<=1;end else stim<=stim-1;end
  if(mbusy)begin if(mtim==0)begin mbusy<=0;md<=1;if(fault_mat)mf<=1;end else mtim<=mtim-1;end
  if(vbusy)begin if(vtim==0)begin vbusy<=0;vd<=1;if(fault_vec)vf<=1;end else vtim<=vtim-1;end
  if(lbusi)begin if(ltim==0)begin lbusi<=0;ld<=1;end else ltim<=ltim-1;end
  if(done)done_pulses<=done_pulses+1;
 end
 integer seen_done_cycle=0,fault_cycle=0;
 always @(posedge clk)begin
  if(rst_n&&done&&seen_done_cycle==0)seen_done_cycle=cycle;
  if(rst_n&&fault&&fault_cycle==0)fault_cycle=cycle;
 end
 integer fd,rc,j;reg [1023:0] folder;
 initial begin
  if(!$value$plusargs("mode=%d",mode))mode=0;
  if(!$value$plusargs("plan=%h",plan_base))plan_base=32'h10000000;
  if(!$value$plusargs("param_end=%h",param_end))param_end=32'h10040000;
  if(!$value$plusargs("dly_seq=%d",dly_seq))dly_seq=(mode==7)?2:20;
  if(!$value$plusargs("dly_mat=%d",dly_mat))dly_mat=15;
  if(!$value$plusargs("dly_vec=%d",dly_vec))dly_vec=25;
  if(!$value$plusargs("dly_lay=%d",dly_lay))dly_lay=12;
  if(!$value$plusargs("fault_mat=%d",fault_mat))fault_mat=0;
  if(!$value$plusargs("fault_vec=%d",fault_vec))fault_vec=0;
  repeat(5)@(negedge clk);rst_n=1;repeat(2)@(negedge clk);
  start=1;@(negedge clk);start=0;
  if(mode==2)begin wait(completed>=1);repeat(3)@(negedge clk);generation=8;end
  if(mode==5)begin wait(busy);repeat(5)@(negedge clk);start=1;@(negedge clk);start=0;end
  wait(done||cycle>400000);
  @(negedge clk);@(negedge clk);
  if(cycle>400000)$fatal(1,"timeout state=%d busy=%d active=%b",dut.state,busy,dut.e_active);
  case(mode)
   0:if(fault||completed!=7||node_count!=7||done_mask!=128'h7f||done_pulses!=1||
        seq_calls!=1||mat_calls!=1||vec_calls!=3||lay_calls!=2)
      $fatal(1,"diamond failed comp=%d err=%h done=%b calls=%d/%d/%d/%d",
        completed,error_code,done_pulses,seq_calls,mat_calls,vec_calls,lay_calls);
   1:if(!fault||error_code!=8'h55||completed!=2||done_pulses!=1||
        seen_done_cycle-fault_cycle<100)
      $fatal(1,"fault/drain failed comp=%d err=%h done=%d fault=%d",completed,error_code,seen_done_cycle,fault_cycle);
   2:if(!fault||error_code!=8'h02||done_pulses!=1)$fatal(1,"generation failed err=%h",error_code);
   3:if(!fault||error_code!=8'h04||completed!=0||vec_calls!=0)$fatal(1,"hash failed err=%h",error_code);
   4:if(!fault||error_code!=8'h07||completed!=0)$fatal(1,"ACL failed err=%h",error_code);
   5:if(fault||rejected_starts!=1||done_pulses!=1)$fatal(1,"replay failed rej=%d err=%h",rejected_starts,error_code);
   6:if(fault||completed!=8||done_mask!=8'hff)$fatal(1,"eight failed comp=%d err=%h",completed,error_code);
   7:if(fault||completed!=68||last_node!=67||seq_calls!=68||
        done_mask[63:0]!=64'hffffffffffffffff||done_mask[67:64]!=4'hf||done_mask[127:68]!=60'd0)
      $fatal(1,"real68 control failed comp=%d last=%d calls=%d err=%h",completed,last_node,seq_calls,error_code);
   default:$fatal(1,"mode");
  endcase
  $display("WC_CTRL_PASS mode=%d cycles=%d completed=%d err=%h done_pulses=%d fetches=%d/%d/%d/%d irq=%b",
   mode,cycles,completed,error_code,done_pulses,seq_calls,mat_calls,vec_calls,lay_calls,irq);
  $finish;
 end
endmodule
