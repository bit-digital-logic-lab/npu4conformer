`timescale 1ns/1ps
// Control-only scaling baseline: 68 independent one-node superplans, one START
// each, against the same SEQ stub and DDR BFM as the 68-node one-START plan.
// No arithmetic and no whole-model claim.
module tb_wc_ctrl68_before;
 reg clk=0;always #4 clk=~clk;
 reg rst_n=0,start=0,parameter_ready=1;
 reg [31:0] plan_base=32'h10030000,param_end=32'h40000000,generation=7;
 integer cycle=0,starts=0,dones=0,k=0,begin_cycle=0,end_cycle=0;
 wire busy,done,fault,irq,drain_timeout,direct_idle;wire [7:0] error_code;
 wire [31:0] completed,node_count,rejected_starts,last_node;wire [127:0] done_mask;
 wire [63:0] cycles,fetch_cycles,operator_cycles,drain_cycles;
 wire req_valid,req_ready,rv,rr,fd,fe;wire [31:0] ra;wire [15:0] rb,ri;wire [127:0] rda;
 wire sv,sr,sd,sf;wire [31:0] sb,sc;wire mv,mr,md,mf;wire [31:0] mb,mc;
 wire vv,vr,vd,vf;wire [511:0] vdesc;wire lv,lr,ld,lf;wire [1023:0] ldesc;
 wire [7:0] se,me,ve,le;
 wc_superplan_ctrl dut(.clk(clk),.rst_n(rst_n),.start(start),.plan_base(plan_base),
  .param_end(param_end),.parameter_ready(parameter_ready),.generation(generation),
  .busy(busy),.done(done),.fault(fault),.error_code(error_code),.completed(completed),
  .node_count(node_count),.rejected_starts(rejected_starts),.last_node(last_node),
  .done_mask(done_mask),.cycles(cycles),.fetch_cycles(fetch_cycles),
  .operator_cycles(operator_cycles),.drain_cycles(drain_cycles),.drain_timeout(drain_timeout),
  .irq(irq),
  .fetch_req_valid(req_valid),.fetch_req_ready(req_ready),.fetch_address(ra),.fetch_beats(rb),
  .fetch_read_valid(rv),.fetch_read_ready(rr),.fetch_read_data(rda),.fetch_read_index(ri),
  .fetch_done(fd),.fetch_error(fe),
  .seq_valid(sv),.seq_ready(sr),.seq_base(sb),.seq_count(sc),.seq_done(sd),.seq_fault(sf),.seq_error(se),
  .mat_valid(mv),.mat_ready(mr),.mat_base(mb),.mat_count(mc),.mat_done(md),.mat_fault(mf),.mat_error(me),
  .vec_valid(vv),.vec_ready(vr),.vec_descriptor(vdesc),.vec_done(vd),.vec_fault(vf),.vec_error(ve),
  .lay_valid(lv),.lay_ready(lr),.lay_descriptor(ldesc),.lay_done(ld),.lay_fault(lf),.lay_error(le),
  .direct_idle(direct_idle));
 wire [39:0] fa;wire [7:0] fl;wire [2:0] fs;wire [1:0] fb;wire [3:0] fc;wire [2:0] fp;
 wire fav,far,frv,frr,frl;wire [127:0] frd;wire [1:0] fresp;wire [15:0] fri;
 wire [39:0] wa;wire [7:0] wl;wire [2:0] ws;wire [1:0] wb;wire [3:0] wc;wire [2:0] wp;
 wire wav,war,wvv,wvr,wvl;wire [127:0] wvd;wire [15:0] wvs;wire [1:0] wbr;wire wbv,wbrd;
 axi_dma_v019 dma(.clk(clk),.rst_n(rst_n),.request_valid(req_valid),.request_ready(req_ready),
  .request_write(1'b0),.request_address(ra),.request_beats(rb),.read_valid(rv),.read_ready(rr),
  .read_data(rda),.read_index(ri),.write_valid(1'b0),.write_ready(),.write_data(128'd0),
  .write_strobe(16'd0),.write_index(),.done(fd),.error(fe),.read_bytes(),.write_bytes(),
  .read_bursts(),.write_bursts(),.m_axi_araddr(fa),.m_axi_arlen(fl),.m_axi_arsize(fs),
  .m_axi_arburst(fb),.m_axi_arcache(fc),.m_axi_arprot(fp),.m_axi_arvalid(fav),.m_axi_arready(far),
  .m_axi_rdata(frd),.m_axi_rresp(fresp),.m_axi_rlast(frl),.m_axi_rvalid(frv),.m_axi_rready(frr),
  .m_axi_awaddr(wa),.m_axi_awlen(wl),.m_axi_awsize(ws),.m_axi_awburst(wb),.m_axi_awcache(wc),
  .m_axi_awprot(wp),.m_axi_awvalid(wav),.m_axi_awready(war),.m_axi_wdata(wvd),.m_axi_wstrb(wvs),
  .m_axi_wlast(wvl),.m_axi_wvalid(wvv),.m_axi_wready(wvr),.m_axi_bresp(wbr),.m_axi_bvalid(wbv),
  .m_axi_bready(wbrd));
 wc_axi_bfm #(.PORTS(1)) ddr(.clk(clk),.rst_n(rst_n),
  .araddr(fa),.arlen(fl),.arsize(fs),.arburst(fb),.arvalid(fav),.arready(far),
  .rdata(frd),.rresp(fresp),.rlast(frl),.rvalid(frv),.rready(frr),
  .awaddr(wa),.awlen(wl),.awsize(ws),.awburst(wb),.awvalid(wav),.awready(war),
  .wdata(wvd),.wstrb(wvs),.wlast(wvl),.wvalid(wvv),.wready(wvr),
  .bresp(wbr),.bvalid(wbv),.bready(wbrd),
  .inject_read_error(1'b0),.inject_write_error(1'b0));
 // SEQ stub: control only.
 reg sbusy=0;integer stim=0;reg sdd=0,sff=0;
 assign sr=!sbusy;assign sd=sdd;assign sf=sff;assign se=8'h44;
 assign mr=1'b1;assign md=1'b0;assign mf=1'b0;assign me=8'h55;
 assign vr=1'b1;assign vd=1'b0;assign vf=1'b0;assign ve=8'h66;
 assign lr=1'b1;assign ld=1'b0;assign lf=1'b0;assign le=8'h77;
 always @(posedge clk)if(rst_n)begin
  sdd<=0;sff<=0;cycle<=cycle+1;
  if(sv&&sr)begin sbusy<=1;stim<=2;end
  if(sbusy)begin if(stim==0)begin sbusy<=0;sdd<=1;end else stim<=stim-1;end
 end
 initial begin
  repeat(5)@(negedge clk);rst_n=1;repeat(2)@(negedge clk);
  for(k=0;k<68;k=k+1)begin
   plan_base=32'h10030000+k*128;
   wait(!busy);@(negedge clk);
   if(k==0)begin_cycle=cycle;
   start=1;starts=starts+1;@(negedge clk);start=0;
   wait(done||fault||cycle>500000);
   @(negedge clk);@(negedge clk);
   if(fault)$fatal(1,"before68 fault k=%0d ec=%h",k,error_code);
   dones=dones+1;
  end
  end_cycle=cycle;
  if(starts!=68||dones!=68)$fatal(1,"starts/dones %0d/%0d",starts,dones);
  $display("WC_CTRL68_BEFORE_PASS starts=%0d dones=%0d cycles=%0d",starts,dones,end_cycle-begin_cycle);
  $finish;
 end
endmodule
