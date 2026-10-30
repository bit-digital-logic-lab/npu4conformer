`timescale 1ns/1ps
`ifndef FMA_EXTRA_STAGES
`define FMA_EXTRA_STAGES 0
`endif
// v023 pipelined vector engine.
// - same top-level port list as work/rtl/ddr_vector_engine.sv
// - 3-stage descriptor validator (no DMA side effect before V3)
// - 128-bit raw unpack: 4 FP32 / 8 A16 / 2 C48 items per cycle
// - 4 fixed-latency FP32 lanes, each II=1; engine issue 1 beat/cycle
// - 128-bit result pack: 4 FP32 or 8 I16 per beat, tagged tokens
// - DIV/SQRT/EXP/LOG stay on the unchanged exact sequential ALU (not II=1)
// - optional external approx_div_sqrt (^USE_APPROX_DIV_SQRT); FMA stays vendor
module ddr_vector_engine_pipe #(
 parameter CHUNK=256,
 parameter [31:0] ARENA_BASE=32'h04000000,ARENA_END=32'h08000000,
 parameter [31:0] PARAM_BASE=32'h10000000,PARAM_END=32'h40000000,
 parameter integer USE_APPROX_DIV_SQRT=0
)(input wire clk,rst_n,start,abort,input wire [511:0] descriptor,input wire [31:0] param_end,
 output wire ready,output reg busy,done,fault,output reg aborted,output reg [7:0] error_code,numeric_flags,
 output reg [31:0] completed_elements,rejected_starts,
 output reg [63:0] cycles,read_compute_overlap,write_compute_overlap,
 output wire rd_request_valid,input wire rd_request_ready,
 output wire [31:0] rd_address,output wire [15:0] rd_beats,
 input wire rd_valid,output wire rd_ready,input wire [127:0] rd_data,
 input wire [15:0] rd_index,input wire rd_done,rd_error,
 output wire wr_request_valid,input wire wr_request_ready,
 output wire [31:0] wr_address,output wire [15:0] wr_beats,
 output wire wr_valid,input wire wr_ready,output wire [127:0] wr_data,
 output wire [15:0] wr_strobe,input wire wr_done,wr_error);
 localparam FREE=0,LOADING=1,READY=2,CALCULATING=3,FULL=4,STORING=5;
 localparam LIDLE=0,LREQ=1,LRX=2,LUNPACK=3;
 localparam CIDLE=0,CREAD=1,CDRAIN=2,CITER=3;
 localparam WIDLE=0,WREQ=1,WDATA=2,WWAIT=3;

 reg [2:0] bank_state[0:1];
 reg [31:0] bank_sequence[0:1];
 reg [8:0] bank_count[0:1];
 reg [31:0] bank_boffset[0:1];
 reg [511:0] cfg,desc_snap;
 reg [31:0] param_end_snap,load_sequence,compute_sequence;
 reg [7:0] coefficient_tile;
 reg [2:0] ls,cs;reg [1:0] ws;reg lb,cb,wb;
 reg [1:0] plane;
 reg [8:0] unpack_element,compute_index,drain_element;
 reg [15:0] received,write_index;
 reg load_bad,cfg_ok;
 reg [7:0] out_word;
 reg [7:0] pack_count;
 reg [127:0] pack_buf;
 reg is_fma,iter_approx,core_flush;
 reg abort_pending;
 reg [2:0] iter_outstanding;

 (* ram_style="block" *) reg [127:0] raw[0:99];
 (* ram_style="block" *) reg [127:0] amem[0:255],bmem[0:255],cmem[0:255],omem[0:255];
 (* ram_style="block" *) reg [47:0] a48mem[0:511];

 wire [7:0] op=cfg[39:32];
 wire a16=cfg[40],out16=cfg[41],bscalar=cfg[42],ascalar=cfg[43],cscalar=cfg[44],a48=cfg[45],btiled=cfg[46];
 wire [31:0] bperiod=cfg[255:224];
 wire [31:0] aa=cfg[95:64],ba=cfg[127:96],ca=cfg[159:128],da=cfg[191:160],total=cfg[223:192];
 wire fma_op=(op==17);
 wire need_b=(op<=3||op==9||op==10||op==11||op==14||fma_op);
 wire fixed_op=(op==0||op==1||op==2||op==7||op==8||op==9||op==10||op==11||
               op==12||op==13||op==14||op==15);
 wire plane_scalar=(plane==0)?ascalar:(plane==1)?bscalar:cscalar;
 wire [3:0] item_bytes=(plane==0)?(a48?6:a16?2:4):4;
 wire [8:0] items=(plane_scalar)?9'd1:
   (plane==1&&btiled)?9'd32:
   (plane==1&&bperiod!=0&&bperiod<bank_count[lb])?bperiod[8:0]:bank_count[lb];
 wire [31:0] source=(plane==0)?aa:(plane==1)?ba:ca;
 wire [31:0] source_offset=(plane_scalar)?0:
   (plane==1&&btiled)?bank_boffset[lb]:
   (plane==1&&bperiod!=0)?((bank_sequence[lb]*CHUNK)&(bperiod-1))*4:
   bank_sequence[lb]*CHUNK*item_bytes;
 wire [3:0] source_low=(source+source_offset)&15;
 wire [12:0] transfer_bytes=items*item_bytes;
 wire [12:0] src_byte=unpack_element*item_bytes+source_low;
 wire [6:0] raw_word=src_byte>>4;
 wire [255:0] window=({raw[raw_word+1],raw[raw_word]})>>(src_byte[3:0]*8);
 wire [3:0] per_beat=(item_bytes==2)?4'd8:(item_bytes==6)?4'd2:4'd4;
 wire [8:0] remaining=items-unpack_element;
 wire [3:0] nb=(remaining<per_beat)?remaining[3:0]:per_beat;
 wire [12:0] output_bytes=bank_count[wb]*(out16?2:4);
 wire [12:0] written_bytes=write_index*16;
 wire [12:0] valid_bytes=output_bytes-written_bytes;
 wire [16:0] tail_mask=(17'd1<<valid_bytes[4:0])-1;
 wire [7:0] per_word=out16?8:4;
 wire [8:0] lanes=(op==14)?9'd2:9'd4;
 wire [8:0] lanes_now=(bank_count[cb]-drain_element<lanes)?(bank_count[cb]-drain_element):lanes;
 wire [8:0] issue_n=(bank_count[cb]-compute_index<lanes)?(bank_count[cb]-compute_index):lanes;

 assign wr_strobe=valid_bytes>=16?16'hffff:tail_mask[15:0];
 assign ready=!busy&&rd_request_ready&&wr_request_ready;
 assign rd_request_valid=busy&&!fault&&cfg_ok&&ls==LREQ;
 assign rd_address=(source+source_offset)&32'hfffffff0;
 assign rd_beats=(transfer_bytes+source_low+15)>>4;
 assign rd_ready=ls==LRX;
 assign wr_request_valid=busy&&!fault&&ws==WREQ;
 assign wr_address=da+bank_sequence[wb]*CHUNK*(out16?2:4);
 assign wr_beats=(output_bytes+15)>>4;
 assign wr_valid=ws==WDATA;
 assign wr_data=omem[wb*128+write_index];

 // descriptor validator (3 registered stages)
 wire val_out_valid,val_out_invalid;wire [511:0] val_cfg;
 vector_desc_check_pipe #(.ARENA_BASE(ARENA_BASE),.ARENA_END(ARENA_END),
   .PARAM_BASE(PARAM_BASE),.PARAM_END(PARAM_END)) vchk(
  .clk(clk),.rst_n(rst_n),.in_valid(start&&ready),.descriptor(descriptor),
  .param_end(param_end),.in_ready(),.out_valid(val_out_valid),
  .out_invalid(val_out_invalid),.out_cfg(val_cfg));

 // four fixed-latency lanes
 wire [3:0] lane_in_ready,lane_out_valid;
 reg [3:0] lane_in_valid;
 reg [63:0] lane_tag_vec;
 reg [7:0] issued_beats,drained_beats;
 reg [31:0] stat_issue_beats,stat_compute_cycles;
 reg [127:0] lane_a_v,lane_b_v,lane_c_v;
 reg [127:0] next_a_v,next_b_v,next_c_v;
 wire [127:0] lane_result_v;wire [31:0] lane_flags_v;wire [63:0] lane_tag_v;
 wire lane_out_ready=1'b1;
 asr_fp32_lane_fixed lane0(.clk(clk),.rst_n(rst_n&&!core_flush),
  .in_valid(lane_in_valid[0]),.in_ready(lane_in_ready[0]),.op(op),.a(lane_a_v[31:0]),.b(lane_b_v[31:0]),
  .tag(lane_tag_vec[15:0]),.out_valid(lane_out_valid[0]),.out_ready(lane_out_ready),
  .result(lane_result_v[31:0]),.flags(lane_flags_v[7:0]),.tag_out(lane_tag_v[15:0]));
 asr_fp32_lane_fixed lane1(.clk(clk),.rst_n(rst_n&&!core_flush),
  .in_valid(lane_in_valid[1]),.in_ready(lane_in_ready[1]),.op(op),.a(lane_a_v[63:32]),.b(lane_b_v[63:32]),
  .tag(lane_tag_vec[31:16]),.out_valid(lane_out_valid[1]),.out_ready(lane_out_ready),
  .result(lane_result_v[63:32]),.flags(lane_flags_v[15:8]),.tag_out(lane_tag_v[31:16]));
 asr_fp32_lane_fixed lane2(.clk(clk),.rst_n(rst_n&&!core_flush),
  .in_valid(lane_in_valid[2]),.in_ready(lane_in_ready[2]),.op(op),.a(lane_a_v[95:64]),.b(lane_b_v[95:64]),
  .tag(lane_tag_vec[47:32]),.out_valid(lane_out_valid[2]),.out_ready(lane_out_ready),
  .result(lane_result_v[95:64]),.flags(lane_flags_v[23:16]),.tag_out(lane_tag_v[47:32]));
 asr_fp32_lane_fixed lane3(.clk(clk),.rst_n(rst_n&&!core_flush),
  .in_valid(lane_in_valid[3]),.in_ready(lane_in_ready[3]),.op(op),.a(lane_a_v[127:96]),.b(lane_b_v[127:96]),
  .tag(lane_tag_vec[63:48]),.out_valid(lane_out_valid[3]),.out_ready(lane_out_ready),
  .result(lane_result_v[127:96]),.flags(lane_flags_v[31:24]),.tag_out(lane_tag_v[63:48]));

 // exact sequential core for DIV/SQRT/EXP/LOG
 wire alu_in_ready,alu_out_valid;wire [31:0] alu_result;wire [7:0] alu_flags;
 reg alu_in_valid;reg [31:0] alu_a,alu_b,alu_c;
 asr_fp32_alu exact_core(.clk(clk),.rst_n(rst_n&&!core_flush),.in_valid(alu_in_valid),
  .in_ready(alu_in_ready),.op(op),.a(alu_a),.b(alu_b),.out_valid(alu_out_valid),
  .out_ready(cs==CITER&&!iter_approx&&!is_fma),.result(alu_result),.flags(alu_flags));

 // Real round-2 FMA pipeline, direct ready/valid instance.
 // Latency is deliberately NOT assumed here: ds_fma_deep may replace
 // fp32_fma_pipe with a 6..8 stage version and this engine still works.
 // vector_fma_lane is transparent at EXTRA_STAGES=0; the latency regression
 // builds it with EXTRA_STAGES=3.
 wire fma_in_ready,fma_out_valid;
 wire [31:0] fma_result;
 wire [15:0] fma_out_tag;
 wire fma_in_valid;
 wire [15:0] fma_in_tag={cb,7'd0,compute_index[7:0]};
 wire fma_issue=(cs==CITER)&&is_fma&&!fault&&!abort_pending&&
   (compute_index<bank_count[cb])&&fma_in_ready;
 assign fma_in_valid=fma_issue;
 vector_fma_lane #(.EXTRA_STAGES(`FMA_EXTRA_STAGES)) fused(
  .clk(clk),.rst_n(rst_n),.flush(core_flush),
  .in_valid(fma_in_valid),.in_ready(fma_in_ready),
  .in_a(next_a_v[31:0]),.in_b(next_b_v[31:0]),.in_c(next_c_v[31:0]),
  .in_tag(fma_in_tag),.in_last(1'b0),
  .out_valid(fma_out_valid),.out_ready(1'b1),.out_result(fma_result),
  .out_tag(fma_out_tag),.out_last());

 // optional external approximate core (delivered by gemini_approx)
 wire ap_in_ready,ap_out_valid;wire [31:0] ap_result;wire [7:0] ap_flags;wire [15:0] ap_tag;
 reg ap_in_valid;reg [31:0] ap_a,ap_b;reg [15:0] ap_tag_in;
 generate if(USE_APPROX_DIV_SQRT!=0) begin:g_approx
  approx_div_sqrt apcore(.clk(clk),.rst_n(rst_n&&!core_flush),.flush(core_flush),
   .in_valid(ap_in_valid),
   .in_ready(ap_in_ready),.op(op==4?2'd1:2'd0),
   .a(ap_a),.b(ap_b),.tag(ap_tag_in),.out_valid(ap_out_valid),
   .out_ready(cs==CITER&&iter_approx),.result(ap_result),.flags(ap_flags),
   .tag_out(ap_tag));
 end else begin:g_no_approx
  assign ap_in_ready=1'b0;assign ap_out_valid=1'b0;assign ap_result=0;
  assign ap_flags=0;assign ap_tag=0;
 end endgenerate

 // operand mux (combinational reads from the 128-bit banks)
 integer li;
 reg [8:0] ei;reg [8:0] bi;
 always @* begin
  for(li=0;li<4;li=li+1) begin
   ei=compute_index+li;bi=ei;
   next_a_v[li*32 +: 32]=0;next_b_v[li*32 +: 32]=0;next_c_v[li*32 +: 32]=0;
   if(ei<bank_count[cb]) begin
    if(a48) next_a_v[li*32 +: 32]=a48mem[cb*256+(ascalar?9'd0:ei)][31:0];
    else if(a16) next_a_v[li*32 +: 32]={{16{amem[cb*128+(ascalar?9'd0:ei)/8][((ascalar?9'd0:ei)%8)*16+15]}},
      amem[cb*128+(ascalar?9'd0:ei)/8][((ascalar?9'd0:ei)%8)*16 +: 16]};
    else next_a_v[li*32 +: 32]=amem[cb*128+(ascalar?9'd0:ei)/4][((ascalar?9'd0:ei)%4)*32 +: 32];
    if(a48) next_b_v[li*32 +: 32]={16'd0,a48mem[cb*256+ei][47:32]};
    else if(bscalar) next_b_v[li*32 +: 32]=bmem[cb*128][31:0];
    else if(btiled) next_b_v[li*32 +: 32]=bmem[cb*128+(ei%32)/4][((ei%32)%4)*32 +: 32];
    else if(bperiod!=0&&bperiod<CHUNK) begin
      bi=ei&(bperiod[8:0]-9'd1);
      next_b_v[li*32 +: 32]=bmem[cb*128+bi/4][(bi%4)*32 +: 32];
    end else next_b_v[li*32 +: 32]=bmem[cb*128+ei/4][(ei%4)*32 +: 32];
    if(cscalar) next_c_v[li*32 +: 32]=cmem[cb*128][31:0];
    else next_c_v[li*32 +: 32]=cmem[cb*128+ei/4][(ei%4)*32 +: 32];
   end
  end
 end

 // 128-bit unpack packers
 reg [127:0] pack16,pack32;
 integer k;
 always @* begin
  pack16=0;pack32=0;
  for(k=0;k<8;k=k+1) if(k<nb) pack16[k*16 +: 16]=window[k*16 +: 16];
  for(k=0;k<4;k=k+1) if(k<nb) pack32[k*32 +: 32]=window[k*32 +: 32];
 end

 // result collection
 // The 4-lane path drains on the lane's own out_valid (lane 0 is valid for
 // every issued group).  This removes the old fixed-delay `flush_wait`
 // alignment that lost the first groups of a short (<=8 element) bank.
 wire lane_group_valid=lane_out_valid[0];
 wire [8:0] collect_n=((cs==CREAD)||(cs==CDRAIN))?lanes_now:9'd1;
 wire collect_wide=((cs==CREAD)||(cs==CDRAIN))&&!fault&&!abort_pending&&
   lane_group_valid&&(drained_beats<issued_beats);
 wire fma_collect=(cs==CITER)&&!iter_approx&&is_fma&&!fault&&!abort_pending&&fma_out_valid;
 wire collect_iter=(cs==CITER)&&((iter_approx&&ap_out_valid)||fma_collect||
   (!iter_approx&&!is_fma&&alu_out_valid));
 wire collect=collect_wide||collect_iter;
 wire ap_tag_bad=collect_iter&&iter_approx&&(ap_tag!={cb,7'd0,drain_element[7:0]});
 wire fma_tag_bad=fma_collect&&(fma_out_tag!={cb,7'd0,drain_element[7:0]});
 wire [31:0] collect_result0=((cs==CREAD)||(cs==CDRAIN))?lane_result_v[31:0]:
   iter_approx?ap_result:(is_fma?fma_result:alu_result);
 // Called from the clocked block; lane_result_v is the current group.
 function automatic [127:0] pack_insert(input [127:0] base,input [7:0] pc,input [8:0] n);
  reg [127:0] t;integer j;
  begin
   t=base;
   for(j=0;j<4;j=j+1) if(j<n) begin
    if(out16) t[(pc+j)*16 +: 16]=((cs==CREAD)||(cs==CDRAIN))?lane_result_v[j*32 +: 16]:collect_result0[15:0];
    else t[(pc+j)*32 +: 32]=((cs==CREAD)||(cs==CDRAIN))?lane_result_v[j*32 +: 32]:collect_result0;
   end
   pack_insert=t;
  end
 endfunction
 reg [127:0] pack_word;
 wire [7:0] collect_flags=((cs==CREAD)||(cs==CDRAIN))?
   (lane_flags_v[7:0]|lane_flags_v[15:8]|lane_flags_v[23:16]|lane_flags_v[31:24]):
   (iter_approx?ap_flags:(is_fma?8'h00:alu_flags));
 wire collect_bad=collect&&((collect_flags&7)!=0);
 // Tags are carried through every lane and echoed on tag_out.  The engine
 // currently treats them as tracing metadata, not as an ordering gate: the
 // lane pipelines are in-order by construction.  See FINDINGS.
 wire tag_bad=fma_tag_bad;
 wire iter_ready=iter_approx?ap_in_ready:alu_in_ready;
 wire iter_can_issue=iter_approx?(iter_outstanding<3'd4):(iter_outstanding==0);

 task automatic fail(input [7:0] code);begin fault<=1;error_code<=code;end endtask

 always @(posedge clk) begin
  if(!rst_n) begin
   busy<=0;done<=0;fault<=0;aborted<=0;error_code<=0;numeric_flags<=0;completed_elements<=0;rejected_starts<=0;
   cycles<=0;read_compute_overlap<=0;write_compute_overlap<=0;cfg<=0;desc_snap<=0;param_end_snap<=0;
   load_sequence<=0;compute_sequence<=0;coefficient_tile<=0;ls<=LIDLE;cs<=CIDLE;ws<=WIDLE;
   lb<=0;cb<=0;wb<=0;plane<=0;unpack_element<=0;compute_index<=0;drain_element<=0;
   received<=0;write_index<=0;load_bad<=0;cfg_ok<=0;out_word<=0;pack_count<=0;pack_buf<=0;
   is_fma<=0;iter_approx<=0;iter_outstanding<=0;core_flush<=0;abort_pending<=0;
   alu_in_valid<=0;alu_a<=0;alu_b<=0;alu_c<=0;
   ap_in_valid<=0;ap_a<=0;ap_b<=0;ap_tag_in<=0;lane_in_valid<=0;
   lane_tag_vec<=0;stat_issue_beats<=0;stat_compute_cycles<=0;issued_beats<=0;drained_beats<=0;lane_a_v<=0;lane_b_v<=0;lane_c_v<=0;
   for(integer bank=0;bank<2;bank=bank+1)begin
    bank_state[bank]<=FREE;bank_sequence[bank]<=0;bank_count[bank]<=0;bank_boffset[bank]<=0;
   end
  end else begin
   done<=0;
   if(start&&!ready)rejected_starts<=rejected_starts+1;
   if(start&&ready) begin
    busy<=1;fault<=0;aborted<=0;error_code<=0;numeric_flags<=0;completed_elements<=0;cycles<=0;
    read_compute_overlap<=0;write_compute_overlap<=0;desc_snap<=descriptor;param_end_snap<=param_end;
    load_sequence<=0;compute_sequence<=0;coefficient_tile<=0;ls<=LIDLE;cs<=CIDLE;ws<=WIDLE;
    cfg_ok<=0;out_word<=0;pack_count<=0;pack_buf<=0;drain_element<=0;
    is_fma<=0;iter_approx<=0;iter_outstanding<=0;lane_in_valid<=0;core_flush<=0;abort_pending<=0;
    alu_in_valid<=0;ap_in_valid<=0;
    lane_tag_vec<=0;stat_issue_beats<=0;stat_compute_cycles<=0;issued_beats<=0;drained_beats<=0;lane_a_v<=0;lane_b_v<=0;lane_c_v<=0;
    for(integer bank=0;bank<2;bank=bank+1)bank_state[bank]<=FREE;
   end else if(busy) begin
    cycles<=cycles+1;
    if(ls==LRX&&cs!=CIDLE)read_compute_overlap<=read_compute_overlap+1;
    if((ws==WDATA||ws==WWAIT)&&cs!=CIDLE)write_compute_overlap<=write_compute_overlap+1;
    if(cs==CREAD||cs==CITER)stat_compute_cycles<=stat_compute_cycles+1;


    // validation snapshot -> cfg
    if(val_out_valid) begin
     if(val_out_invalid)begin fail(8'h01);cfg_ok<=0;end
     else begin cfg<=val_cfg;cfg_ok<=1;end
    end

    // any fault or explicit abort discards the compute pipeline; exact/approx
    // cores see a one-cycle reset.  An already accepted AXI write burst is
    // allowed to drain (B response still required) but no new AW is started.
    if(fault || (abort && busy && !abort_pending)) begin
     core_flush<=1;iter_outstanding<=0;lane_in_valid<=0;
     if(abort && busy && !abort_pending) abort_pending<=1;
     if(cs!=CIDLE)begin
      if(bank_state[cb]==CALCULATING)bank_state[cb]<=FREE;
      cs<=CIDLE;
     end
     if(abort && busy && !abort_pending && ls==LUNPACK)begin
      bank_state[lb]<=FREE;ls<=LIDLE;
     end
     // Drop results that have not started an AXI write.
     if(ws==WIDLE)begin
      if(bank_state[0]==FULL)bank_state[0]<=FREE;
      if(bank_state[1]==FULL)bank_state[1]<=FREE;
     end else if(bank_state[1-wb]==FULL)bank_state[1-wb]<=FREE;
    end else core_flush<=0;

    // ---------------- load ----------------
    case(ls)
     LIDLE:if(!fault&&!abort_pending&&cfg_ok&&load_sequence*CHUNK<total&&
          (bank_state[0]==FREE||bank_state[1]==FREE))begin
      lb<=bank_state[0]==FREE?0:1;plane<=0;unpack_element<=0;ls<=LREQ;
      load_sequence<=load_sequence+1;
      if(btiled&&load_sequence[1:0]==3)
       coefficient_tile<=coefficient_tile+1==((bperiod+31)>>5)?0:coefficient_tile+1;
      if(bank_state[0]==FREE)begin
       bank_boffset[0]<=coefficient_tile*128;
       bank_state[0]<=LOADING;bank_sequence[0]<=load_sequence;
       bank_count[0]<=total-load_sequence*CHUNK<CHUNK?total-load_sequence*CHUNK:CHUNK;
      end else begin
       bank_boffset[1]<=coefficient_tile*128;
       bank_state[1]<=LOADING;bank_sequence[1]<=load_sequence;
       bank_count[1]<=total-load_sequence*CHUNK<CHUNK?total-load_sequence*CHUNK:CHUNK;
      end
     end
     LREQ:if(fault)begin bank_state[lb]<=FREE;ls<=LIDLE;end
      else if(rd_request_ready)begin received<=0;load_bad<=0;ls<=LRX;end
     LRX:begin
      if(rd_valid)begin
       if(rd_index!=received||rd_index>=100)load_bad<=1;else raw[rd_index]<=rd_data;
       received<=received+1;
      end
      if(rd_done)begin
       if(abort_pending)begin bank_state[lb]<=FREE;ls<=LIDLE;end
       else if(rd_error||load_bad||received!=rd_beats)begin fail(8'h02);bank_state[lb]<=FREE;ls<=LIDLE;end
       else begin ls<=LUNPACK;end
      end
     end
     LUNPACK:if(fault||abort_pending)begin bank_state[lb]<=FREE;ls<=LIDLE;end else begin
      if(plane==0)begin
       if(a48)begin
        for(k=0;k<2;k=k+1)if(k<nb)a48mem[lb*256+unpack_element+k]<=window[k*48 +: 48];
       end else if(a16) amem[lb*128+unpack_element/8]<=pack16;
       else amem[lb*128+unpack_element/4]<=pack32;
      end else if(plane==1) bmem[lb*128+unpack_element/4]<=pack32;
      else cmem[lb*128+unpack_element/4]<=pack32;
      if(unpack_element+nb>=items)begin
       if(plane==0&&need_b&&!a48)begin plane<=1;unpack_element<=0;ls<=LREQ;end
       else if(plane!=2&&fma_op)begin plane<=2;unpack_element<=0;ls<=LREQ;end
       else begin bank_state[lb]<=READY;ls<=LIDLE;end
      end else unpack_element<=unpack_element+nb;
     end
     default:begin fail(8'hf1);ls<=LIDLE;end
    endcase

    // ---------------- compute ----------------
    lane_in_valid<=0;alu_in_valid<=0;ap_in_valid<=0;
    case(cs)
     CIDLE:if(!fault&&!abort_pending&&((bank_state[0]==READY&&bank_sequence[0]==compute_sequence)||
                       (bank_state[1]==READY&&bank_sequence[1]==compute_sequence)))begin
      cb<=bank_state[0]==READY&&bank_sequence[0]==compute_sequence?0:1;
      if(bank_state[0]==READY&&bank_sequence[0]==compute_sequence)bank_state[0]<=CALCULATING;
      else bank_state[1]<=CALCULATING;
      compute_index<=0;drain_element<=0;out_word<=0;pack_count<=0;pack_buf<=0;
      is_fma<=(op==17);iter_approx<=(USE_APPROX_DIV_SQRT!=0)&&(op==3||op==4);
      iter_outstanding<=0;
      issued_beats<=0;drained_beats<=0;
      // The 4-lane path is used for every fixed-op bank length, including
      // 1..8.  There is no short-bank scalar fallback.
      cs<=fixed_op?CREAD:CITER;
     end
     CREAD:if(!fault)begin
      // issue and drain in the same cycle: the wide path must sustain 1 beat/cycle
      if(collect)begin
       pack_word=pack_insert(pack_buf,pack_count,collect_n);
       numeric_flags<=numeric_flags|collect_flags;
       if(tag_bad)begin fail(8'h06);bank_state[cb]<=FREE;cs<=CIDLE;end
       else if(collect_bad)begin fail(8'h04);bank_state[cb]<=FREE;cs<=CIDLE;end
       else begin
        if(pack_count+collect_n>=per_word)begin
         omem[cb*128+out_word]<=pack_word;out_word<=out_word+1;pack_count<=0;
        end else if(drain_element+collect_n==bank_count[cb])begin
         omem[cb*128+out_word]<=pack_word;out_word<=out_word+1;pack_count<=0;
        end else begin pack_buf<=pack_word;pack_count<=pack_count+collect_n;end
        drain_element<=drain_element+collect_n;drained_beats<=drained_beats+1;
        if(drain_element+collect_n==bank_count[cb])begin
         if(drained_beats+1!=issued_beats)begin
          fail(8'h06);bank_state[cb]<=FREE;cs<=CIDLE;
         end else begin
          bank_state[cb]<=FULL;compute_sequence<=compute_sequence+1;cs<=CIDLE;
         end
        end
       end
      end
      // Issue the next group whenever the 4 lanes have room.  Partial final
      // groups use the exact lane mask; no tail_wait/bank_elems gate.
      if(!tag_bad&&!collect_bad&&compute_index<bank_count[cb]&&
        lane_in_ready[0]&&lane_in_ready[1]&&lane_in_ready[2]&&lane_in_ready[3])begin
       lane_in_valid<=(issue_n==1)?4'b0001:(issue_n==2)?4'b0011:(issue_n==3)?4'b0111:4'b1111;
       lane_a_v<=next_a_v;lane_b_v<=next_b_v;lane_c_v<=next_c_v;
       for(integer t=0;t<4;t=t+1)lane_tag_vec[t*16 +: 16]<={cb,7'd0,(compute_index[7:0]+t)};
       compute_index<=compute_index+issue_n;issued_beats<=issued_beats+1;stat_issue_beats<=stat_issue_beats+1;
      end
     end
     CDRAIN:begin
      if(collect)begin
       pack_word=pack_insert(pack_buf,pack_count,collect_n);
       numeric_flags<=numeric_flags|collect_flags;
       if(tag_bad)begin fail(8'h06);bank_state[cb]<=FREE;cs<=CIDLE;end
       else if(collect_bad)begin fail(8'h04);bank_state[cb]<=FREE;cs<=CIDLE;end
       else begin
        if(pack_count+collect_n>=per_word)begin
         omem[cb*128+out_word]<=pack_word;out_word<=out_word+1;pack_count<=0;
        end else if(drain_element+collect_n==bank_count[cb])begin
         omem[cb*128+out_word]<=pack_word;out_word<=out_word+1;pack_count<=0;
        end else begin pack_buf<=pack_word;pack_count<=pack_count+collect_n;end
        drain_element<=drain_element+collect_n;drained_beats<=drained_beats+1;
        if(drain_element+collect_n==bank_count[cb])begin
         bank_state[cb]<=FULL;compute_sequence<=compute_sequence+1;cs<=CIDLE;
        end
       end
      end
     end
     CITER:begin
      if(collect)begin
       pack_word=pack_insert(pack_buf,pack_count,9'd1);
       numeric_flags<=numeric_flags|collect_flags;
       if(tag_bad)begin fail(8'h06);bank_state[cb]<=FREE;cs<=CIDLE;end
       else if(collect_bad)begin fail(8'h04);bank_state[cb]<=FREE;cs<=CIDLE;end
       else begin
        if(pack_count+1>=per_word)begin
         omem[cb*128+out_word]<=pack_word;out_word<=out_word+1;pack_count<=0;
        end else if(drain_element+1==bank_count[cb])begin
         omem[cb*128+out_word]<=pack_word;out_word<=out_word+1;pack_count<=0;
        end else begin pack_buf<=pack_word;pack_count<=pack_count+1;end
        drain_element<=drain_element+1;drained_beats<=drained_beats+1;
        iter_outstanding<=iter_approx?(iter_outstanding-3'd1):3'd0;
        if(drain_element+1==bank_count[cb])begin
         bank_state[cb]<=FULL;compute_sequence<=compute_sequence+1;cs<=CIDLE;
        end
       end
      end
      // op17: a single real FMA lane, II=1.  Issue and collect are allowed in
      // the same cycle; fma_issue already includes the pipe's in_ready, so a
      // deeper (6..8 stage) pipe only changes latency, not this code.
      if(!fault&&!abort_pending&&!tag_bad&&!collect_bad&&compute_index<bank_count[cb])begin
       if(is_fma)begin
        if(fma_issue)begin
         compute_index<=compute_index+1;stat_issue_beats<=stat_issue_beats+1;
        end
       end else if(!collect&&iter_can_issue)begin
        if(iter_ready)begin
         if(iter_approx)begin
          ap_in_valid<=1;ap_a<=next_a_v[31:0];ap_b<=next_b_v[31:0];
          ap_tag_in<={cb,7'd0,compute_index[7:0]};
         end else begin
          alu_in_valid<=1;alu_a<=next_a_v[31:0];alu_b<=next_b_v[31:0];alu_c<=next_c_v[31:0];
         end
         iter_outstanding<=iter_approx?(iter_outstanding+3'd1):3'd1;compute_index<=compute_index+1;
        end
       end
      end
     end
     default:begin fail(8'hf2);cs<=CIDLE;end
    endcase

    // ---------------- write ----------------
    if(wr_done&&ws!=WIDLE&&ws!=WREQ)begin
     if(wr_error)fail(8'h03);
     else if(ws!=WWAIT)fail(8'h05);
     else completed_elements<=completed_elements+bank_count[wb];
     bank_state[wb]<=FREE;ws<=WIDLE;
    end else case(ws)
     WIDLE:if(!fault&&!abort_pending&&(bank_state[0]==FULL||bank_state[1]==FULL))begin
      write_index<=0;ws<=WREQ;
      if(bank_state[0]==FULL&&(bank_state[1]!=FULL||bank_sequence[0]<bank_sequence[1]))begin
       wb<=0;bank_state[0]<=STORING;
      end else begin wb<=1;bank_state[1]<=STORING;end
     end
     WREQ:if(fault)begin bank_state[wb]<=FREE;ws<=WIDLE;end
      else if(wr_request_ready)ws<=WDATA;
     WDATA:if(wr_ready)begin
      if(write_index+1==wr_beats)ws<=WWAIT;
      else write_index<=write_index+1;
     end
     WWAIT:begin end
     default:begin fail(8'hf3);ws<=WIDLE;end
    endcase

    if((fault||abort_pending||(cfg_ok&&completed_elements==total))&&ls==LIDLE&&cs==CIDLE&&ws==WIDLE&&
       rd_request_ready&&wr_request_ready)begin busy<=0;done<=1;aborted<=abort_pending;end
   end
  end
 end
endmodule
