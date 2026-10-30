`timescale 1ns/1ps
// DDR -> ping-pong operands -> unchanged FP32/FMA -> ping-pong output -> DDR.
// A53 never sees payload. Separate read/write DMA channels permit real overlap.
module ddr_vector_engine #(
 parameter CHUNK=256,
 parameter [31:0] ARENA_BASE=32'h04000000,ARENA_END=32'h08000000,
 parameter [31:0] PARAM_BASE=32'h10000000,PARAM_END=32'h40000000
)(input wire clk,rst_n,start,input wire [511:0] descriptor,input wire [31:0] param_end,
 output wire ready,output reg busy,done,fault,output reg [7:0] error_code,numeric_flags,
 output reg [31:0] completed_elements,rejected_starts,
 output reg [63:0] cycles,read_compute_overlap,write_compute_overlap,
 output wire rd_request_valid,input wire rd_request_ready,
 output wire [31:0] rd_address,output wire [15:0] rd_beats,
 input wire rd_valid,output wire rd_ready,input wire [127:0] rd_data,
 input wire [15:0] rd_index,input wire rd_done,rd_error,
 output wire wr_request_valid,input wire wr_request_ready,
 output wire [31:0] wr_address,output wire [15:0] wr_beats,
 output wire wr_valid,input wire wr_ready,output reg [127:0] wr_data,
 output wire [15:0] wr_strobe,input wire wr_done,wr_error);
 localparam FREE=0,LOADING=1,READY=2,CALCULATING=3,FULL=4,STORING=5;
 localparam LIDLE=0,LREQ=1,LRX=2,LPRE=3,LUNPACK=4;
 localparam CIDLE=0,CREAD=1,CSEND=2,CWAIT=3;
 localparam WIDLE=0,WREQ=1,WPRE0=2,WPRE1=3,WPRE2=4,WPRE3=5,WDATA=6,WWAIT=7;
 reg [2:0] bank_state[0:1];reg [31:0] bank_sequence[0:1];reg [8:0] bank_count[0:1];
 reg [511:0] cfg;reg [31:0] load_sequence,compute_sequence;
 reg [31:0] bank_boffset[0:1];reg [7:0] coefficient_tile;
 reg [2:0] ls,cs;reg [3:0] ws;reg lb,cb,wb;
 reg [1:0] plane;reg [8:0] unpack_index,compute_index;
 reg [15:0] received,write_index;
 reg load_bad;
 (* ram_style="block" *) reg [127:0] raw[0:97];
 reg [127:0] raw_lo,raw_hi;
 (* ram_style="block" *) reg [31:0] amem[0:511],bmem[0:511],cmem[0:511];
 (* ram_style="block" *) reg [31:0] o0[0:127],o1[0:127],o2[0:127],o3[0:127];
 reg [31:0] aq,bq,cq,oq0,oq1,oq2,oq3;reg [63:0] write_low;
 wire [7:0] op=cfg[39:32];
 wire a16=cfg[40],out16=cfg[41],bscalar=cfg[42],ascalar=cfg[43],cscalar=cfg[44],a48=cfg[45],btiled=cfg[46];
 wire [31:0] bperiod=cfg[255:224];
 wire [31:0] aa=cfg[95:64],ba=cfg[127:96],ca=cfg[159:128],da=cfg[191:160],total=cfg[223:192];
 wire fma_op=op==17;
 wire need_b=op<=3||op==9||op==10||op==11||op==14||fma_op;
 wire plane_scalar=plane==0?ascalar:plane==1?bscalar:cscalar;
 wire [3:0] item_bytes=plane==0?(a48?6:a16?2:4):4;
 wire [8:0] items=plane_scalar?9'd1:plane==1&&btiled?9'd32:
  plane==1&&bperiod!=0&&bperiod<bank_count[lb]?bperiod[8:0]:bank_count[lb];
 wire [31:0] source=plane==0?aa:plane==1?ba:ca;
 wire [31:0] source_offset=plane_scalar?0:plane==1&&btiled?bank_boffset[lb]:
  plane==1&&bperiod!=0?((bank_sequence[lb]*CHUNK)&(bperiod-1))*4:bank_sequence[lb]*CHUNK*item_bytes;
 wire [3:0] source_low=(source+source_offset)&15;
 wire [12:0] transfer_bytes=items*item_bytes;
 wire [12:0] unpack_byte=unpack_index*item_bytes+source_low;
 wire [255:0] aligned_raw={raw_hi,raw_lo}>>(unpack_byte[3:0]*8);
 wire [8:0] unpack_address={lb,8'd0}+unpack_index;
 wire [8:0] calc_address={cb,8'd0}+compute_index;
 wire [6:0] output_group={cb,6'd0}+compute_index[7:2];
 wire [3:0] output_items=out16?8:4;
 wire [12:0] output_bytes=bank_count[wb]*(out16?2:4);
 wire [12:0] written_bytes=write_index*16;
 wire [12:0] valid_bytes=output_bytes-written_bytes;
 wire [6:0] write_group={wb,6'd0}+write_index*(out16?2:1);
 wire [16:0] tail_mask=(17'd1<<valid_bytes[4:0])-1;
 assign wr_strobe=valid_bytes>=16?16'hffff:tail_mask[15:0];
 assign ready=!busy&&rd_request_ready&&wr_request_ready;
 assign rd_request_valid=busy&&!fault&&ls==LREQ;
 assign rd_address=(source+source_offset)&32'hfffffff0;
 assign rd_beats=(transfer_bytes+source_low+15)>>4;
 assign rd_ready=ls==LRX;
 assign wr_request_valid=busy&&!fault&&ws==WREQ;
 assign wr_address=da+bank_sequence[wb]*CHUNK*(out16?2:4);
 assign wr_beats=(output_bytes+15)>>4;
 assign wr_valid=ws==WDATA;
 wire fp_ready,fp_valid;wire [31:0] fp_result;wire [7:0] fp_flags;
 wire fma_valid;wire [31:0] fma_result;
 asr_fp32_alu numeric_core(.clk(clk),.rst_n(rst_n),.in_valid(cs==CSEND&&!fma_op),
  .in_ready(fp_ready),.op(op),.a(aq),.b(bq),.out_valid(fp_valid),
  .out_ready(cs==CWAIT&&!fma_op),.result(fp_result),.flags(fp_flags));
 asr_fma_ip fused(.aclk(clk),.aresetn(rst_n),
  .s_axis_a_tvalid(cs==CSEND&&fma_op),.s_axis_a_tdata(aq),
  .s_axis_b_tvalid(cs==CSEND&&fma_op),.s_axis_b_tdata(bq),
  .s_axis_c_tvalid(cs==CSEND&&fma_op),.s_axis_c_tdata(cq),
  .m_axis_result_tvalid(fma_valid),.m_axis_result_tdata(fma_result));
 wire result_valid=fma_op?fma_valid:fp_valid;
 wire [31:0] result=fma_op?fma_result:fp_result;
 wire [7:0] result_flags=fma_op?8'd0:fp_flags;
 function automatic readable(input [31:0] p,input [63:0] bytes);
  reg [63:0] e;begin e=({32'd0,p}&~64'd15)+((bytes+{60'd0,p[3:0]}+15)&~64'd15);
   readable=bytes!=0&&((p>=32'h03000000&&e<=ARENA_END)||(p>=PARAM_BASE&&e<=param_end&&param_end<=PARAM_END));
  end
 endfunction
 function automatic overlap(input [31:0] p,input [63:0] bytes,input [31:0] d,input [63:0] dn);
  begin overlap={32'd0,p}<({32'd0,d}+dn)&&{32'd0,d}<({32'd0,p}+bytes);end
 endfunction
 wire [7:0] start_op=descriptor[39:32];
 wire [31:0] start_count=descriptor[223:192];
 wire [31:0] sa=descriptor[95:64],sb=descriptor[127:96],sc=descriptor[159:128],sd=descriptor[191:160];
 wire start_b=start_op<=3||start_op==9||start_op==10||start_op==11||start_op==14||start_op==17;
 wire [63:0] an=(descriptor[43]?64'd1:{32'd0,start_count})*(descriptor[45]?6:descriptor[40]?2:4);
 wire [31:0] start_period=descriptor[255:224];
 wire [63:0] bn=(descriptor[42]?64'd1:descriptor[46]?(({32'd0,start_period}+31)&~64'd31):
  start_period!=0?{32'd0,start_period}:{32'd0,start_count})*4;
 wire [63:0] cn=(descriptor[44]?64'd1:{32'd0,start_count})*4;
 wire [63:0] dn={32'd0,start_count}*(descriptor[41]?2:4);
 wire invalid_descriptor=descriptor[31:0]!=32'h22564543||descriptor[63:47]!=0||descriptor[511:256]!=0||
  start_count==0||start_count>16777216||!(start_op<=15||start_op==17)||
  (start_period!=0&&(descriptor[42]||!start_b||descriptor[45]||start_period>4096||
   (!descriptor[46]&&(start_period&(start_period-1))!=0)))||
  (descriptor[46]&&(start_period==0||start_count[9:0]!=0))||
  (descriptor[40]&&descriptor[45])||(descriptor[45]&&(start_op!=14||descriptor[43]||descriptor[42]))||
  (descriptor[41]&&start_op!=15)||sd[3:0]!=0||sd<ARENA_BASE||{32'd0,sd}+((dn+15)&~64'd15)>ARENA_END||
  (sa&(descriptor[40]||descriptor[45]?1:3))!=0||!readable(sa,an)||overlap(sa,an,sd,dn)||
  (start_b&&!descriptor[45]&&(sb[1:0]!=0||!readable(sb,bn)||overlap(sb,bn,sd,dn)))||
  (start_op==17&&(sc[1:0]!=0||!readable(sc,cn)||overlap(sc,cn,sd,dn)))||CHUNK!=256;
 task fail(input [7:0] code);begin fault<=1;error_code<=code;end endtask
 always @(posedge clk)begin
  if(!rst_n)begin
   busy<=0;done<=0;fault<=0;error_code<=0;numeric_flags<=0;completed_elements<=0;rejected_starts<=0;
   cycles<=0;read_compute_overlap<=0;write_compute_overlap<=0;cfg<=0;load_sequence<=0;compute_sequence<=0;
   ls<=LIDLE;cs<=CIDLE;ws<=WIDLE;lb<=0;cb<=0;wb<=0;plane<=0;unpack_index<=0;compute_index<=0;coefficient_tile<=0;
   received<=0;write_index<=0;load_bad<=0;wr_data<=0;write_low<=0;
   for(integer bank=0;bank<2;bank=bank+1)begin bank_state[bank]<=FREE;bank_sequence[bank]<=0;bank_count[bank]<=0;bank_boffset[bank]<=0;end
  end else begin
   done<=0;
   if(start&&!ready)rejected_starts<=rejected_starts+1;
   if(start&&ready)begin
    busy<=1;fault<=0;error_code<=0;numeric_flags<=0;completed_elements<=0;cycles<=0;
    read_compute_overlap<=0;write_compute_overlap<=0;cfg<=descriptor;load_sequence<=0;compute_sequence<=0;
    ls<=LIDLE;cs<=CIDLE;ws<=WIDLE;coefficient_tile<=0;
    for(integer bank=0;bank<2;bank=bank+1)bank_state[bank]<=FREE;
    if(invalid_descriptor)begin fault<=1;error_code<=8'h01;end
   end else if(busy)begin
    cycles<=cycles+1;
    if(ls==LRX&&cs!=CIDLE)read_compute_overlap<=read_compute_overlap+1;
    if(ws>=WPRE0&&cs!=CIDLE)write_compute_overlap<=write_compute_overlap+1;
    case(ls)
     LIDLE:if(!fault&&load_sequence*CHUNK<total&&(bank_state[0]==FREE||bank_state[1]==FREE))begin
      lb<=bank_state[0]==FREE?0:1;plane<=0;ls<=LREQ;load_sequence<=load_sequence+1;
      if(btiled&&load_sequence[1:0]==3)coefficient_tile<=coefficient_tile+1==((bperiod+31)>>5)?0:coefficient_tile+1;
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
       if(rd_index!=received||rd_index>=97)load_bad<=1;
       else raw[rd_index]<=rd_data;
       received<=received+1;
      end
      if(rd_done)begin
       if(rd_error||load_bad||received!=rd_beats)begin fail(8'h02);bank_state[lb]<=FREE;ls<=LIDLE;end
       else if(fault)begin bank_state[lb]<=FREE;ls<=LIDLE;end
       else begin unpack_index<=0;ls<=LPRE;end
      end
     end
     LPRE:begin raw_lo<=raw[unpack_byte>>4];raw_hi<=raw[(unpack_byte>>4)+1];ls<=LUNPACK;end
     LUNPACK:if(fault)begin bank_state[lb]<=FREE;ls<=LIDLE;end else begin
      if(plane==0)begin
       amem[unpack_address]<=a16?{{16{aligned_raw[15]}},aligned_raw[15:0]}:aligned_raw[31:0];
       if(a48)bmem[unpack_address]<={16'd0,aligned_raw[47:32]};
      end else if(plane==1)bmem[unpack_address]<=aligned_raw[31:0];
      else cmem[unpack_address]<=aligned_raw[31:0];
      if(unpack_index+1<items)begin unpack_index<=unpack_index+1;ls<=LPRE;end
      else if(plane==0&&need_b&&!a48)begin plane<=1;ls<=LREQ;end
      else if(plane!=2&&fma_op)begin plane<=2;ls<=LREQ;end
      else begin bank_state[lb]<=READY;ls<=LIDLE;end
     end
     default:begin fail(8'hf1);ls<=LIDLE;end
    endcase
    case(cs)
     CIDLE:if(!fault&&((bank_state[0]==READY&&bank_sequence[0]==compute_sequence)||
                       (bank_state[1]==READY&&bank_sequence[1]==compute_sequence)))begin
      cb<=bank_state[0]==READY&&bank_sequence[0]==compute_sequence?0:1;
      if(bank_state[0]==READY&&bank_sequence[0]==compute_sequence)bank_state[0]<=CALCULATING;
      else bank_state[1]<=CALCULATING;
      compute_index<=0;cs<=CREAD;
     end
     CREAD:begin
      aq<=amem[{cb,8'd0}+(ascalar?9'd0:compute_index)];
      bq<=bmem[{cb,8'd0}+(bscalar?9'd0:btiled?{4'd0,compute_index[4:0]}:
        bperiod!=0&&bperiod<CHUNK?(compute_index&(bperiod-1)):compute_index)];
      cq<=cmem[{cb,8'd0}+(cscalar?9'd0:compute_index)];cs<=CSEND;
     end
     CSEND:if(fma_op||fp_ready)cs<=CWAIT;
     CWAIT:if(result_valid)begin
      numeric_flags<=numeric_flags|result_flags;
      if(fault||(result_flags&7)!=0)begin
       if((result_flags&7)!=0)fail(8'h04);bank_state[cb]<=FREE;cs<=CIDLE;
      end else begin
       case(compute_index[1:0])
        0:o0[output_group]<=result;1:o1[output_group]<=result;
        2:o2[output_group]<=result;3:o3[output_group]<=result;
       endcase
       if(compute_index+1==bank_count[cb])begin bank_state[cb]<=FULL;compute_sequence<=compute_sequence+1;cs<=CIDLE;end
       else begin compute_index<=compute_index+1;cs<=CREAD;end
      end
     end
     default:begin fail(8'hf2);cs<=CIDLE;end
    endcase
    if(wr_done&&ws!=WIDLE&&ws!=WREQ)begin
     // BRESP errors can terminate a multi-burst DMA before all planned beats.
     // The accepted burst has drained; never wait for beats never issued.
     if(wr_error)fail(8'h03);
     else if(ws!=WWAIT)fail(8'h05);
     else completed_elements<=completed_elements+bank_count[wb];
     bank_state[wb]<=FREE;ws<=WIDLE;
    end else case(ws)
     WIDLE:if(!fault&&(bank_state[0]==FULL||bank_state[1]==FULL))begin
      write_index<=0;ws<=WREQ;
      if(bank_state[0]==FULL&&(bank_state[1]!=FULL||bank_sequence[0]<bank_sequence[1]))begin wb<=0;bank_state[0]<=STORING;end
      else begin wb<=1;bank_state[1]<=STORING;end
     end
     WREQ:if(fault)begin bank_state[wb]<=FREE;ws<=WIDLE;end
      else if(wr_request_ready)ws<=WPRE0;
     WPRE0:begin oq0<=o0[write_group];oq1<=o1[write_group];oq2<=o2[write_group];oq3<=o3[write_group];ws<=WPRE1;end
     WPRE1:if(out16)begin write_low<={oq3[15:0],oq2[15:0],oq1[15:0],oq0[15:0]};ws<=WPRE2;end
      else begin wr_data<={oq3,oq2,oq1,oq0};ws<=WDATA;end
     WPRE2:begin oq0<=o0[write_group+1];oq1<=o1[write_group+1];oq2<=o2[write_group+1];oq3<=o3[write_group+1];ws<=WPRE3;end
     WPRE3:begin wr_data<={oq3[15:0],oq2[15:0],oq1[15:0],oq0[15:0],write_low};ws<=WDATA;end
     WDATA:if(wr_ready)begin
      if(write_index+1==wr_beats)ws<=WWAIT;
      else begin write_index<=write_index+1;ws<=WPRE0;end
     end
     WWAIT:begin end
     default:begin fail(8'hf3);ws<=WIDLE;end
    endcase
    if((fault||completed_elements==total)&&ls==LIDLE&&cs==CIDLE&&ws==WIDLE&&rd_request_ready&&wr_request_ready)begin busy<=0;done<=1;end
   end
  end
 end
endmodule
