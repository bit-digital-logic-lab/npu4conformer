`timescale 1ns/1ps
// New integration wrapper; original V0.20 block engine and V0.19 DMA are read-only.
module queued_v020_monitored #(
 parameter [31:0] ARENA_BASE=32'h03000000,ARENA_END=32'h08000000
)(
 input wire clk,rst_n,start,input wire [31:0] queue_base,queue_count,param_end,epoch_bias,
 output wire busy,done,fault,output wire [7:0] error_code,
 output wire [31:0] completed_tasks,current_index,rejected_starts,
 output wire [63:0] queue_cycles,fetch_cycles,engine_wait_cycles,retire_wait_cycles,
 output reg [63:0] total_compute_cycles,
 output wire [31:0] last_core_compute,last_core_reads,last_core_writes,last_core_hits,last_core_misses,
 output wire completion_valid,input wire completion_ready,
 output wire [31:0] completion_index,completion_cookie,output wire [7:0] completion_error,
 output wire [63:0] completion_cycles,
 output wire [31:0] dma_read_bytes,dma_write_bytes,dma_read_bursts,dma_write_bursts,
 output wire [39:0] m_axi_araddr,output wire [7:0] m_axi_arlen,
 output wire [2:0] m_axi_arsize,output wire [1:0] m_axi_arburst,
 output wire [3:0] m_axi_arcache,output wire [2:0] m_axi_arprot,
 output wire m_axi_arvalid,input wire m_axi_arready,
 input wire [127:0] m_axi_rdata,input wire [1:0] m_axi_rresp,
 input wire m_axi_rlast,m_axi_rvalid,output wire m_axi_rready,
 output wire [39:0] m_axi_awaddr,output wire [7:0] m_axi_awlen,
 output wire [2:0] m_axi_awsize,output wire [1:0] m_axi_awburst,
 output wire [3:0] m_axi_awcache,output wire [2:0] m_axi_awprot,
 output wire m_axi_awvalid,input wire m_axi_awready,
 output wire [127:0] m_axi_wdata,output wire [15:0] m_axi_wstrb,
 output wire m_axi_wlast,m_axi_wvalid,input wire m_axi_wready,
 input wire [1:0] m_axi_bresp,input wire m_axi_bvalid,output wire m_axi_bready
);
 wire qreq,qready,qrvalid,qrready,qdone,qerror;wire [31:0] qaddr;
 wire [15:0] qbeats,qrindex;wire [127:0] qrdata;
 wire [31:0] relative_cookie;
 assign completion_cookie=relative_cookie+epoch_bias;
 wire ev,er;wire [511:0] ed;wire e_done,e_fault;wire [7:0] e_error;wire [63:0] e_cycles;
 task_queue #(.BACKEND(21),.ARENA_BASE(ARENA_BASE),.ARENA_END(ARENA_END)) queue(
  .clk(clk),.rst_n(rst_n),.start(start),.queue_base(queue_base),.queue_count(queue_count),
  .busy(busy),.done(done),.fault(fault),.error_code(error_code),.completed_tasks(completed_tasks),.current_index(current_index),.rejected_starts(rejected_starts),
  .queue_cycles(queue_cycles),.fetch_cycles(fetch_cycles),.engine_wait_cycles(engine_wait_cycles),.retire_wait_cycles(retire_wait_cycles),
  .dma_request_valid(qreq),.dma_request_ready(qready),.dma_address(qaddr),.dma_beats(qbeats),
  .dma_read_valid(qrvalid),.dma_read_ready(qrready),.dma_read_index(qrindex),.dma_read_data(qrdata),.dma_done(qdone),.dma_error(qerror),
  .engine_valid(ev),.engine_ready(er),.engine_descriptor(ed),.engine_done(e_done),.engine_fault(e_fault),.engine_error(e_error),.engine_cycles(e_cycles),
  .completion_valid(completion_valid),.completion_ready(completion_ready),.completion_index(completion_index),.completion_cookie(relative_cookie),.completion_error(completion_error),.completion_cycles(completion_cycles));

 reg [2:0] estate;
 reg [511:0] cfg;
 reg [31:0] protect_base,protect_count;
 reg config_error;
 wire core_busy,core_done,core_fault;wire [7:0] core_error;wire [63:0] core_cycles;
 wire storage_idle;
 wire [31:0] abase=cfg[159:128],bbase=cfg[191:160],cbase=cfg[223:192];
 wire [31:0] mdim=cfg[255:224],ndim=cfg[287:256],kdim=cfg[319:288],epoch=cfg[351:320];
 wire [15:0] layer=cfg[367:352],aid=cfg[383:368],bid=cfg[399:384],cid=cfg[415:400];
 wire [15:0] positions=cfg[431:416],target_high=cfg[463:448],allowed=cfg[479:464];
 wire clip=cfg[432],cvalid=cfg[480];wire [15:0] ccompleted=cfg[511:496];
 wire [63:0] rows=({32'd0,mdim}+31)>>5,cols=({32'd0,ndim}+31)>>5,depths=({32'd0,kdim}+31)>>5;
 wire [63:0] aend={32'd0,abase}+rows*depths*2048;
 wire [63:0] bend={32'd0,bbase}+depths*cols*1024;
 wire [63:0] cend={32'd0,cbase}+rows*cols*6144;
 wire [63:0] qend={32'd0,protect_base}+({32'd0,protect_count}<<6);
 wire overlaps_queue=(abase<qend&&protect_base<aend)||(bbase<qend&&protect_base<bend)||(cbase<qend&&protect_base<cend);
 wire bad_cfg=epoch==0||mdim==0||ndim==0||kdim==0||mdim>4096||ndim>4096||kdim>4096||
  cfg[447:433]!=0||cfg[495:481]!=0||(!cvalid&&ccompleted!=0)||(ccompleted&~allowed)!=0||
  abase<ARENA_BASE||cbase<ARENA_BASE||aend>ARENA_END||cend>ARENA_END||
  !((bbase>=ARENA_BASE&&bend<=ARENA_END)||(bbase>=32'h10000000&&bend<={32'd0,param_end}&&param_end<=32'h40000000))||overlaps_queue;
 assign er=estate==0;
 assign e_done=estate==4;
 assign e_fault=config_error||core_fault;
 assign e_error=config_error?8'h81:core_error;
 assign e_cycles=config_error?64'd0:core_cycles;
 always @(posedge clk)begin
  if(!rst_n)begin estate<=0;cfg<=0;protect_base<=0;protect_count<=0;config_error<=0;end
  else begin
   if(start&&!busy)begin protect_base<=queue_base;protect_count<=queue_count;end
   case(estate)
    0:if(ev)begin cfg<=ed;cfg[351:320]<=ed[351:320]+epoch_bias;config_error<=0;estate<=1;end
    1:if(bad_cfg)begin config_error<=1;estate<=4;end else estate<=2;
    2:estate<=3;
    3:if(core_done&&storage_idle)estate<=4;
    4:estate<=0;
   endcase
  end
 end
 wire rq,rready,rwrite;wire [31:0] raddr,repoch;
 wire [15:0] rlayer,rmat,rrow,rcol,rallowed,rcompleted;wire [1:0] renc;wire rbvalid,rinop;
 wire hv,hr,he,hbv,hinop;wire [31:0] hepoch;
 wire [15:0] hlayer,hmat,hrow,hcol,hallowed,hcompleted;wire [1:0] henc;
 wire dv,dr,dl;
`ifdef V020_WIDE4
 wire [191:0] din;
`else
 wire [47:0] din;
`endif
 wire [9:0] dindex;
 wire ov,ore,ol;wire [47:0] od;wire [9:0] oi;wire ack,werr;
 wire [31:0] compute,reads,writes,hits,misses;
 assign last_core_compute=compute;
 assign last_core_reads=reads;
 assign last_core_writes=writes;
 assign last_core_hits=hits;
 assign last_core_misses=misses;
 always @(posedge clk)begin
  if(!rst_n)total_compute_cycles<=0;
  else if(start&&!busy)total_compute_cycles<=0;
  else if(e_done&&!config_error)total_compute_cycles<=total_compute_cycles+{32'd0,compute};
 end
`ifdef V020_CBANK
 block_engine_banked_v020 #(.SLOTS(2)) core(
`elsif V020_WIDE4
 block_engine_wide4_v020 #(.SLOTS(2)) core(
`elsif V020_COLLECT4
 block_engine_collect4_v020 #(.SLOTS(2)) core(
`else
 block_engine_v020 #(.SLOTS(2)) core(
`endif
  .clk(clk),.reset(!rst_n),.start(estate==2),
  .cfg_a_base(abase),.cfg_b_base(bbase),.cfg_c_base(cbase),.cfg_epoch(epoch),
  .cfg_m(mdim[15:0]),.cfg_n(ndim[15:0]),.cfg_k(kdim[15:0]),.cfg_layer(layer),.cfg_a_id(aid),.cfg_b_id(bid),.cfg_c_id(cid),
  .cfg_target_high(target_high),.cfg_allowed_ops(allowed),.cfg_requested_op(16'd1),.cfg_positions(positions),.cfg_clip(clip),
  .busy(core_busy),.done(core_done),.fault(core_fault),.error_code(core_error),.task_cycles(core_cycles),.compute_cycles(compute),.read_blocks(reads),.write_blocks(writes),.cache_hits(hits),.cache_misses(misses),
  .req_valid(rq),.req_ready(rready),.req_write(rwrite),.req_address(raddr),.req_epoch(repoch),.req_layer(rlayer),.req_matrix(rmat),.req_block_row(rrow),.req_block_col(rcol),.req_allowed_ops(rallowed),.req_completed_ops(rcompleted),.req_encoding(renc),.req_block_valid(rbvalid),.req_in_operation(rinop),
  .header_valid(hv),.header_ready(hr),.header_exists(he),.header_block_valid(hbv),.header_in_operation(hinop),.header_epoch(hepoch),.header_layer(hlayer),.header_matrix(hmat),.header_block_row(hrow),.header_block_col(hcol),.header_allowed_ops(hallowed),.header_completed_ops(hcompleted),.header_encoding(henc),
  .data_valid(dv),.data_ready(dr),.data_in(din),.data_index(dindex),.data_last(dl),
  .out_valid(ov),.out_ready(ore),.out_data(od),.out_index(oi),.out_last(ol),.write_ack(ack),.write_error(werr),
  .result_valid(),.result_ready(1'b1),.result_cache_address(),.result_epoch(),.result_target_low(),.result_layer(),.result_matrix(),.result_block_row(),.result_block_col(),.result_op_tag(),.result_data(),.result_block_valid(),.result_in_operation(),.result_allowed_ops(),.result_completed_ops());
 wire sreq,sready,swrite,srv,srr,swv,swr,sdone,serror;
 wire [31:0] saddr;wire [15:0] sbeats,sri,swi,sws;wire [127:0] srd,swd;
`ifdef V020_WIDE4
 block_storage_dma_wide4 #(.ARENA_BASE(ARENA_BASE),.ARENA_END(ARENA_END)) storage(
`else
 block_storage_dma #(.ARENA_BASE(ARENA_BASE),.ARENA_END(ARENA_END)) storage(
`endif
  .clk(clk),.rst_n(rst_n),.param_end(param_end),.abort_scalar(core_done&&core_fault),.cfg_a_base(abase),.cfg_b_base(bbase),.cfg_c_base(cbase),.cfg_epoch(epoch),
  .cfg_m(mdim[15:0]),.cfg_n(ndim[15:0]),.cfg_k(kdim[15:0]),.cfg_layer(layer),.cfg_a_id(aid),.cfg_b_id(bid),.cfg_c_id(cid),.cfg_allowed(allowed),.cfg_c_valid(cvalid),.cfg_c_completed(ccompleted),
  .req_valid(rq),.req_ready(rready),.req_write(rwrite),.req_address(raddr),.req_epoch(repoch),.req_layer(rlayer),.req_matrix(rmat),.req_block_row(rrow),.req_block_col(rcol),.req_allowed_ops(rallowed),.req_completed_ops(rcompleted),.req_encoding(renc),.req_block_valid(rbvalid),.req_in_operation(rinop),
  .header_valid(hv),.header_ready(hr),.header_exists(he),.header_block_valid(hbv),.header_in_operation(hinop),.header_epoch(hepoch),.header_layer(hlayer),.header_matrix(hmat),.header_block_row(hrow),.header_block_col(hcol),.header_allowed_ops(hallowed),.header_completed_ops(hcompleted),.header_encoding(henc),
  .data_valid(dv),.data_ready(dr),.data_in(din),.data_index(dindex),.data_last(dl),
  .out_valid(ov),.out_ready(ore),.out_data(od),.out_index(oi),.out_last(ol),.write_ack(ack),.write_error(werr),
  .dma_request_valid(sreq),.dma_request_ready(sready),.dma_request_write(swrite),.dma_address(saddr),.dma_beats(sbeats),
  .dma_read_valid(srv),.dma_read_ready(srr),.dma_read_data(srd),.dma_read_index(sri),
  .dma_write_valid(swv),.dma_write_ready(swr),.dma_write_data(swd),.dma_write_strobe(sws),.dma_write_index(swi),.dma_done(sdone),.dma_error(serror),
  .idle(storage_idle),.transactions(),.read_blocks(),.write_blocks(),.error_transactions(),.read_wait_cycles(),.write_wait_cycles(),.scalar_cycles());
 reg [1:0] owner;
 wire dreq,dready,dwrite,drv,drr,dwv,dwr,ddone,derror;
 wire [31:0] daddr;wire [15:0] dbeats,dri,dwi,dws;wire [127:0] drd,dwd;
 assign dreq=owner==0&&(qreq||sreq);
 assign dwrite=!qreq&&swrite;assign daddr=qreq?qaddr:saddr;assign dbeats=qreq?qbeats:sbeats;
 assign qready=owner==0&&dready;assign sready=owner==0&&!qreq&&dready;
 assign qrvalid=owner==1&&drv;assign qrdata=drd;assign qrindex=dri;
 assign qdone=owner==1&&ddone;assign qerror=derror;
 assign srv=owner==2&&drv;assign srd=drd;assign sri=dri;
 assign sdone=owner==2&&ddone;assign serror=derror;
 assign drr=owner==1?qrready:owner==2?srr:1'b0;
 assign dwv=owner==2&&swv;assign dwd=swd;assign dws=sws;assign swr=owner==2&&dwr;assign swi=dwi;
 always @(posedge clk)begin
  if(!rst_n)owner<=0;
  else if(owner==0&&dreq&&dready)owner<=qreq?1:2;
  else if(ddone)owner<=0;
 end
 axi_dma_v019 dma(
  .clk(clk),.rst_n(rst_n),.request_valid(dreq),.request_ready(dready),.request_write(dwrite),.request_address(daddr),.request_beats(dbeats),
  .read_valid(drv),.read_ready(drr),.read_data(drd),.read_index(dri),.write_valid(dwv),.write_ready(dwr),.write_data(dwd),.write_strobe(dws),.write_index(dwi),
  .done(ddone),.error(derror),.read_bytes(dma_read_bytes),.write_bytes(dma_write_bytes),.read_bursts(dma_read_bursts),.write_bursts(dma_write_bursts),
  .m_axi_araddr(m_axi_araddr),.m_axi_arlen(m_axi_arlen),.m_axi_arsize(m_axi_arsize),.m_axi_arburst(m_axi_arburst),.m_axi_arcache(m_axi_arcache),.m_axi_arprot(m_axi_arprot),.m_axi_arvalid(m_axi_arvalid),.m_axi_arready(m_axi_arready),
  .m_axi_rdata(m_axi_rdata),.m_axi_rresp(m_axi_rresp),.m_axi_rlast(m_axi_rlast),.m_axi_rvalid(m_axi_rvalid),.m_axi_rready(m_axi_rready),
  .m_axi_awaddr(m_axi_awaddr),.m_axi_awlen(m_axi_awlen),.m_axi_awsize(m_axi_awsize),.m_axi_awburst(m_axi_awburst),.m_axi_awcache(m_axi_awcache),.m_axi_awprot(m_axi_awprot),.m_axi_awvalid(m_axi_awvalid),.m_axi_awready(m_axi_awready),
  .m_axi_wdata(m_axi_wdata),.m_axi_wstrb(m_axi_wstrb),.m_axi_wlast(m_axi_wlast),.m_axi_wvalid(m_axi_wvalid),.m_axi_wready(m_axi_wready),.m_axi_bresp(m_axi_bresp),.m_axi_bvalid(m_axi_bvalid),.m_axi_bready(m_axi_bready));
endmodule
