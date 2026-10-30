`timescale 1ns/1ps
// Before-style baseline: the sealed V022 linear-plan executor, one START per
// program (four programs, same real descriptors/engines/DDR BFM as tb_wc_top
// mode12).  This is the comparison leg for start/IRQ/control overhead; it is
// not a full host/network emulation.
module tb_wc_before;
 reg clk=0;always #4 clk=~clk;
 reg rst_n=0,start=0,parameter_ready=1;
 reg [31:0] param_end=32'h10040000,generation=7;
 integer gap=0,cycle=0,starts=0,dones=0,idx=0;
 reg [31:0] plans[0:3];
 reg [31:0] gold[0:63];reg [31:0] g;
 wire busy,done,fault,irq;wire [7:0] error_code;
 wire [31:0] completed,index,rejected,last_ticket;wire [63:0] cycles,fetch_cycles,operator_cycles;
 wire [31:0] mb_queue_base,mq_count;
 wire mb_valid,mb_ready,mb_done,mb_fault;
 wire vec_busy,vec_done,vec_fault;wire [7:0] vec_ec,vec_flags;
 wire [31:0] vec_elems,vec_rej,vec_rb,vec_wb,vec_rbursts,vec_wbursts;
 wire [63:0] vec_cycles,vec_ro,vec_wo;
 wire lay_busy,lay_done,lay_fault;wire [7:0] lay_ec;
 wire [31:0] lay_elems,lay_rej,lay_hits,lay_misses,lay_rb,lay_wb,lay_rbursts,lay_wbursts;
 wire [63:0] lay_cycles;
 wire req_valid,req_ready,rd_valid,rd_ready,rd_done,rd_err;
 wire [31:0] req_address;wire [15:0] req_beats,rd_index;wire [127:0] rd_data;
 wire vec_valid,vec_ready;wire [511:0] vec_desc;
 wire lay_valid,lay_ready;wire [1023:0] lay_desc;
 wire [39:0] qf_araddr,vr_araddr,lr_araddr,vw_awaddr,lw_awaddr;
 wire [7:0] qf_arlen,vr_arlen,lr_arlen,vw_awlen,lw_awlen;
 wire [2:0] qf_arsize,vr_arsize,lr_arsize,vw_awsize,lw_awsize;
 wire [1:0] qf_arburst,vr_arburst,lr_arburst,vw_awburst,lw_awburst;
 wire [3:0] qf_arcache,vr_arcache,lr_arcache,vw_awcache,lw_awcache;
 wire [2:0] qf_arprot,vr_arprot,lr_arprot,vw_awprot,lw_awprot;
 wire qf_arvalid,vr_arvalid,lr_arvalid,vw_awvalid,lw_awvalid;
 wire [127:0] qf_rdata,vr_rdata,lr_rdata,vw_wdata,lw_wdata;
 wire [1:0] qf_rresp,vr_rresp,lr_rresp,vw_bresp,lw_bresp;
 wire qf_rlast,vr_rlast,lr_rlast,vw_wlast,lw_wlast;
 wire qf_rvalid,vr_rvalid,lr_rvalid,vw_wvalid,lw_wvalid;
 wire [15:0] vw_wstrb,lw_wstrb;
 wire qf_arready,vr_arready,lr_arready,vw_awready,lw_awready,vw_wready,lw_wready;
 wire qf_rready,vr_rready,lr_rready;wire vw_bvalid,lw_bvalid;wire vw_bready,lw_bready;
 pl_execution_plan_v022 planner(.clk(clk),.rst_n(rst_n),.start(start),.plan_base(plans[idx]),
  .plan_count(idx==2?32'd2:32'd1),.param_end(param_end),.parameter_ready(parameter_ready),
  .generation(generation),.busy(busy),.done(done),.fault(fault),.error_code(error_code),
  .completed(completed),.index(index),.rejected_starts(rejected),.last_ticket(last_ticket),
  .cycles(cycles),.fetch_cycles(fetch_cycles),.operator_cycles(operator_cycles),.irq(irq),
  .dma_request_valid(req_valid),.dma_request_ready(req_ready),.dma_address(req_address),
  .dma_beats(req_beats),.dma_read_valid(rd_valid),.dma_read_ready(rd_ready),.dma_read_data(rd_data),
  .dma_read_index(rd_index),.dma_done(rd_done),.dma_error(rd_err),
  .matrix_valid(mb_valid),.matrix_ready(mb_ready),.matrix_queue_base(mb_queue_base),
  .matrix_queue_count(mq_count),.matrix_done(mb_done),.matrix_fault(mb_fault),
  .vector_valid(vec_valid),.vector_ready(vec_ready),.vector_descriptor(vec_desc),
  .vector_done(vec_done),.vector_fault(vec_fault),
  .layout_valid(lay_valid),.layout_ready(lay_ready),.layout_descriptor(lay_desc),
  .layout_done(lay_done),.layout_fault(lay_fault));
 axi_dma_v019 qdma(.clk(clk),.rst_n(rst_n),.request_valid(req_valid),.request_ready(req_ready),
  .request_write(1'b0),.request_address(req_address),.request_beats(req_beats),
  .read_valid(rd_valid),.read_ready(rd_ready),.read_data(rd_data),.read_index(rd_index),
  .write_valid(1'b0),.write_ready(),.write_data(128'd0),.write_strobe(16'd0),.write_index(),
  .done(rd_done),.error(rd_err),.read_bytes(),.write_bytes(),.read_bursts(),.write_bursts(),
  .m_axi_araddr(qf_araddr),.m_axi_arlen(qf_arlen),.m_axi_arsize(qf_arsize),.m_axi_arburst(qf_arburst),
  .m_axi_arcache(qf_arcache),.m_axi_arprot(qf_arprot),.m_axi_arvalid(qf_arvalid),.m_axi_arready(qf_arready),
  .m_axi_rdata(qf_rdata),.m_axi_rresp(qf_rresp),.m_axi_rlast(qf_rlast),.m_axi_rvalid(qf_rvalid),
  .m_axi_rready(qf_rready),.m_axi_awaddr(),.m_axi_awlen(),.m_axi_awsize(),.m_axi_awburst(),
  .m_axi_awcache(),.m_axi_awprot(),.m_axi_awvalid(),.m_axi_awready(1'b1),.m_axi_wdata(),
  .m_axi_wstrb(),.m_axi_wlast(),.m_axi_wvalid(),.m_axi_wready(1'b1),.m_axi_bresp(2'd0),
  .m_axi_bvalid(1'b0),.m_axi_bready());
 ddr_vector_axi vec(.clk(clk),.rst_n(rst_n),.start(vec_valid&&vec_ready),.descriptor(vec_desc),
  .param_end(param_end),.ready(vec_ready),.busy(vec_busy),.done(vec_done),.fault(vec_fault),
  .error_code(vec_ec),.numeric_flags(vec_flags),.completed_elements(vec_elems),.rejected_starts(vec_rej),
  .cycles(vec_cycles),.read_compute_overlap(vec_ro),.write_compute_overlap(vec_wo),
  .read_bytes(vec_rb),.write_bytes(vec_wb),.read_bursts(vec_rbursts),.write_bursts(vec_wbursts),
  .read_m_axi_araddr(vr_araddr),.read_m_axi_arlen(vr_arlen),.read_m_axi_arsize(vr_arsize),
  .read_m_axi_arburst(vr_arburst),.read_m_axi_arcache(vr_arcache),.read_m_axi_arprot(vr_arprot),
  .read_m_axi_arvalid(vr_arvalid),.read_m_axi_arready(vr_arready),.read_m_axi_rdata(vr_rdata),
  .read_m_axi_rresp(vr_rresp),.read_m_axi_rlast(vr_rlast),.read_m_axi_rvalid(vr_rvalid),
  .read_m_axi_rready(vr_rready),
  .read_m_axi_awaddr(),.read_m_axi_awlen(),.read_m_axi_awsize(),.read_m_axi_awburst(),
  .read_m_axi_awcache(),.read_m_axi_awprot(),.read_m_axi_awvalid(),.read_m_axi_awready(1'b1),
  .read_m_axi_wdata(),.read_m_axi_wstrb(),.read_m_axi_wlast(),.read_m_axi_wvalid(),
  .read_m_axi_wready(1'b1),.read_m_axi_bresp(2'd0),.read_m_axi_bvalid(1'b0),.read_m_axi_bready(),
  .write_m_axi_araddr(),.write_m_axi_arlen(),.write_m_axi_arsize(),.write_m_axi_arburst(),
  .write_m_axi_arcache(),.write_m_axi_arprot(),.write_m_axi_arvalid(),.write_m_axi_arready(1'b1),
  .write_m_axi_rdata(128'd0),.write_m_axi_rresp(2'd0),.write_m_axi_rlast(1'b0),
  .write_m_axi_rvalid(1'b0),.write_m_axi_rready(),
  .write_m_axi_awaddr(vw_awaddr),.write_m_axi_awlen(vw_awlen),.write_m_axi_awsize(vw_awsize),
  .write_m_axi_awburst(vw_awburst),.write_m_axi_awcache(vw_awcache),.write_m_axi_awprot(vw_awprot),
  .write_m_axi_awvalid(vw_awvalid),.write_m_axi_awready(vw_awready),.write_m_axi_wdata(vw_wdata),
  .write_m_axi_wstrb(vw_wstrb),.write_m_axi_wlast(vw_wlast),.write_m_axi_wvalid(vw_wvalid),
  .write_m_axi_wready(vw_wready),.write_m_axi_bresp(vw_bresp),.write_m_axi_bvalid(vw_bvalid),
  .write_m_axi_bready(vw_bready));
 ddr_layout_axi lay(.clk(clk),.rst_n(rst_n),.start(lay_valid&&lay_ready),.descriptor(lay_desc),
  .param_end(param_end),.ready(lay_ready),.busy(lay_busy),.done(lay_done),.fault(lay_fault),
  .error_code(lay_ec),.processed_elements(lay_elems),.rejected_starts(lay_rej),
  .cache_hits(lay_hits),.cache_misses(lay_misses),.cycles(lay_cycles),
  .read_bytes(lay_rb),.write_bytes(lay_wb),.read_bursts(lay_rbursts),.write_bursts(lay_wbursts),
  .read_m_axi_araddr(lr_araddr),.read_m_axi_arlen(lr_arlen),.read_m_axi_arsize(lr_arsize),
  .read_m_axi_arburst(lr_arburst),.read_m_axi_arcache(lr_arcache),.read_m_axi_arprot(lr_arprot),
  .read_m_axi_arvalid(lr_arvalid),.read_m_axi_arready(lr_arready),.read_m_axi_rdata(lr_rdata),
  .read_m_axi_rresp(lr_rresp),.read_m_axi_rlast(lr_rlast),.read_m_axi_rvalid(lr_rvalid),
  .read_m_axi_rready(lr_rready),
  .read_m_axi_awaddr(),.read_m_axi_awlen(),.read_m_axi_awsize(),.read_m_axi_awburst(),
  .read_m_axi_awcache(),.read_m_axi_awprot(),.read_m_axi_awvalid(),.read_m_axi_awready(1'b1),
  .read_m_axi_wdata(),.read_m_axi_wstrb(),.read_m_axi_wlast(),.read_m_axi_wvalid(),
  .read_m_axi_wready(1'b1),.read_m_axi_bresp(2'd0),.read_m_axi_bvalid(1'b0),.read_m_axi_bready(),
  .write_m_axi_araddr(),.write_m_axi_awaddr(lw_awaddr),.write_m_axi_awlen(lw_awlen),
  .write_m_axi_awsize(lw_awsize),.write_m_axi_awburst(lw_awburst),.write_m_axi_awcache(lw_awcache),
  .write_m_axi_awprot(lw_awprot),.write_m_axi_awvalid(lw_awvalid),.write_m_axi_awready(lw_awready),
  .write_m_axi_wdata(lw_wdata),.write_m_axi_wstrb(lw_wstrb),.write_m_axi_wlast(lw_wlast),
  .write_m_axi_wvalid(lw_wvalid),.write_m_axi_wready(lw_wready),.write_m_axi_bresp(lw_bresp),
  .write_m_axi_bvalid(lw_bvalid),.write_m_axi_bready(lw_bready));
 // Five-port shared BFM (qf/vr/vw/lr/lw).
 wire [5*40-1:0] araddr,awaddr;wire [5*8-1:0] arlen,awlen;
 wire [5*3-1:0] arsize,awsize;wire [5*2-1:0] arburst,awburst;
 wire [5*4-1:0] arcache,awcache;wire [5*3-1:0] arprot,awprot;
 wire [5-1:0] arvalid,arready,awvalid,awready,rready,wready,bready;
 wire [5*128-1:0] rdata,wdata;wire [5*2-1:0] rresp,bresp;
 wire [5-1:0] rlast,rvalid,wlast,wvalid,bvalid;wire [5*16-1:0] wstrb;
 assign araddr[0*40+:40]=qf_araddr;assign araddr[1*40+:40]=vr_araddr;assign araddr[2*40+:40]=40'd0;
 assign araddr[3*40+:40]=lr_araddr;assign araddr[4*40+:40]=40'd0;
 assign arlen[0*8+:8]=qf_arlen;assign arlen[1*8+:8]=vr_arlen;assign arlen[2*8+:8]=8'd0;
 assign arlen[3*8+:8]=lr_arlen;assign arlen[4*8+:8]=8'd0;
 assign arsize[0*3+:3]=qf_arsize;assign arsize[1*3+:3]=vr_arsize;assign arsize[2*3+:3]=3'd0;
 assign arsize[3*3+:3]=lr_arsize;assign arsize[4*3+:3]=3'd0;
 assign arburst[0*2+:2]=qf_arburst;assign arburst[1*2+:2]=vr_arburst;assign arburst[2*2+:2]=2'd0;
 assign arburst[3*2+:2]=lr_arburst;assign arburst[4*2+:2]=2'd0;
 assign arcache[0*4+:4]=qf_arcache;assign arcache[1*4+:4]=vr_arcache;assign arcache[2*4+:4]=4'd0;
 assign arcache[3*4+:4]=lr_arcache;assign arcache[4*4+:4]=4'd0;
 assign arprot[0*3+:3]=qf_arprot;assign arprot[1*3+:3]=vr_arprot;assign arprot[2*3+:3]=3'd0;
 assign arprot[3*3+:3]=lr_arprot;assign arprot[4*3+:3]=3'd0;
 assign arvalid[0]=qf_arvalid;assign arvalid[1]=vr_arvalid;assign arvalid[2]=1'b0;
 assign arvalid[3]=lr_arvalid;assign arvalid[4]=1'b0;
 assign qf_arready=arready[0];assign vr_arready=arready[1];assign lr_arready=arready[3];
 assign qf_rdata=rdata[0*128+:128];assign vr_rdata=rdata[1*128+:128];assign lr_rdata=rdata[3*128+:128];
 assign qf_rresp=rresp[0*2+:2];assign vr_rresp=rresp[1*2+:2];assign lr_rresp=rresp[3*2+:2];
 assign qf_rlast=rlast[0];assign vr_rlast=rlast[1];assign lr_rlast=rlast[3];
 assign qf_rvalid=rvalid[0];assign vr_rvalid=rvalid[1];assign lr_rvalid=rvalid[3];
 assign rready[0]=qf_rready;assign rready[1]=vr_rready;assign rready[2]=1'b1;
 assign rready[3]=lr_rready;assign rready[4]=1'b1;
 assign awaddr[0*40+:40]=40'd0;assign awaddr[1*40+:40]=40'd0;assign awaddr[2*40+:40]=vw_awaddr;
 assign awaddr[3*40+:40]=40'd0;assign awaddr[4*40+:40]=lw_awaddr;
 assign awlen[0*8+:8]=8'd0;assign awlen[1*8+:8]=8'd0;assign awlen[2*8+:8]=vw_awlen;
 assign awlen[3*8+:8]=8'd0;assign awlen[4*8+:8]=lw_awlen;
 assign awsize[0*3+:3]=3'd0;assign awsize[1*3+:3]=3'd0;assign awsize[2*3+:3]=vw_awsize;
 assign awsize[3*3+:3]=3'd0;assign awsize[4*3+:3]=lw_awsize;
 assign awburst[0*2+:2]=2'd0;assign awburst[1*2+:2]=2'd0;assign awburst[2*2+:2]=vw_awburst;
 assign awburst[3*2+:2]=2'd0;assign awburst[4*2+:2]=lw_awburst;
 assign awcache[0*4+:4]=4'd0;assign awcache[1*4+:4]=4'd0;assign awcache[2*4+:4]=vw_awcache;
 assign awcache[3*4+:4]=4'd0;assign awcache[4*4+:4]=lw_awcache;
 assign awprot[0*3+:3]=3'd0;assign awprot[1*3+:3]=3'd0;assign awprot[2*3+:3]=vw_awprot;
 assign awprot[3*3+:3]=3'd0;assign awprot[4*3+:3]=lw_awprot;
 assign awvalid[0]=1'b0;assign awvalid[1]=1'b0;assign awvalid[2]=vw_awvalid;
 assign awvalid[3]=1'b0;assign awvalid[4]=lw_awvalid;
 assign vw_awready=awready[2];assign lw_awready=awready[4];
 assign wdata[0*128+:128]=128'd0;assign wdata[1*128+:128]=128'd0;assign wdata[2*128+:128]=vw_wdata;
 assign wdata[3*128+:128]=128'd0;assign wdata[4*128+:128]=lw_wdata;
 assign wstrb[0*16+:16]=16'd0;assign wstrb[1*16+:16]=16'd0;assign wstrb[2*16+:16]=vw_wstrb;
 assign wstrb[3*16+:16]=16'd0;assign wstrb[4*16+:16]=lw_wstrb;
 assign wlast[0]=1'b0;assign wlast[1]=1'b0;assign wlast[2]=vw_wlast;
 assign wlast[3]=1'b0;assign wlast[4]=lw_wlast;
 assign wvalid[0]=1'b0;assign wvalid[1]=1'b0;assign wvalid[2]=vw_wvalid;
 assign wvalid[3]=1'b0;assign wvalid[4]=lw_wvalid;
 assign vw_wready=wready[2];assign lw_wready=wready[4];
 assign vw_bvalid=bvalid[2];assign lw_bvalid=bvalid[4];
 assign vw_bresp=bresp[2*2+:2];assign lw_bresp=bresp[4*2+:2];
 assign bready[0]=1'b1;assign bready[1]=1'b1;assign bready[2]=vw_bready;
 assign bready[3]=1'b1;assign bready[4]=lw_bready;
 wc_axi_bfm #(.PORTS(5),.PORT_OFFSET(1)) ddr(.clk(clk),.rst_n(rst_n),
  .araddr(araddr),.arlen(arlen),.arsize(arsize),.arburst(arburst),.arvalid(arvalid),.arready(arready),
  .rdata(rdata),.rresp(rresp),.rlast(rlast),.rvalid(rvalid),.rready(rready),
  .awaddr(awaddr),.awlen(awlen),.awsize(awsize),.awburst(awburst),.awvalid(awvalid),.awready(awready),
  .wdata(wdata),.wstrb(wstrb),.wlast(wlast),.wvalid(wvalid),.wready(wready),
  .bresp(bresp),.bvalid(bvalid),.bready(bready),
  .inject_read_error(1'b0),.inject_write_error(1'b0));
 assign mb_ready=1'b1;assign mb_done=1'b0;assign mb_fault=1'b0;
 always @(posedge clk)if(rst_n)begin cycle<=cycle+1;
  if($test$plusargs("verbose")&&cycle%1000==0)
   $display("BEF c=%0d idx=%0d st=%0d busy=%b done=%b fault=%b ec=%h pc=%0d pb=%h starts=%0d comp=%0d ix=%0d ins0=%h lv=%b lr=%b lb=%b ld=%b vv=%b vr=%b vb=%b vd=%b",cycle,idx,planner.state,busy,done,fault,error_code,(idx==2?2:1),plans[idx],starts,planner.completed,planner.index,planner.instruction[31:0],lay_valid,lay_ready,lay_busy,lay_done,vec_valid,vec_ready,vec_busy,vec_done);
 end
 integer i;
 initial begin
  plans[0]=32'h1000b000;plans[1]=32'h1000b100;plans[2]=32'h10009800;plans[3]=32'h1000b300;
  if(!$value$plusargs("gap=%d",gap))gap=0;
  $readmemh("tests/fixtures/gold_mode12.hex",gold);
  repeat(5)@(negedge clk);rst_n=1;repeat(2)@(negedge clk);
  for(idx=0;idx<4;idx=idx+1)begin
   wait(!busy);
   wait(!done); // separate cycles so the previous done pulse is gone
   @(negedge clk);start=1;starts=starts+1;@(negedge clk);start=0;
   if(gap>0)repeat(gap)@(negedge clk);
   wait(done||fault||cycle>500000);
   @(negedge clk);@(negedge clk);
   if(fault)$fatal(1,"before program %0d fault ec=%h",idx,error_code);
   dones=dones+1;
  end
  for(i=0;i<64;i=i+1)begin
   g=ddr.peek32(32'h40000+32'h6000+i*4);
   if(g!==gold[i])$fatal(1,"before data mismatch %0d got=%h want=%h",i,g,gold[i]);
  end
  $display("WC_BEFORE_PASS starts=%0d dones=%0d cycles=%0d gap=%0d vec_cyc=%0d lay_cyc=%0d pl_cyc=%0d",starts,dones,cycles,gap,vec.cycles,lay.cycles,planner.cycles);
  $finish;
 end
endmodule
