`timescale 1ns/1ps
// V0.23 Layout engine, candidate B: incremental stepping + burst aggregation.
// PL bit-copy/layout only. No floating arithmetic or quantization.
// COPY (0), rowmajor->A16tile (1), conv im2col->A16tile (2),
// tiled->rowmajor (3), tiled->NCHWcompact (4).
//
// Stage A (rtl/ddr_layout_engine_v023.sv) proved the incremental stepping is
// bit-identical to work/rtl/ddr_layout_engine.sv.  This stage adds:
//  * a 16-beat posted write buffer.  Consecutive destination lines are merged
//    into one <=16-beat burst; a burst is cut at 4 KiB, on any line
//    discontinuity, and at end-of-descriptor (tail strobes preserved).
//  * a bounded sequential read prefetch.  On a cache miss the engine fetches
//    the contiguous line run that the traversal is about to consume, capped by
//    (a) the current source segment end, (b) the 4 KiB page boundary and
//    (c) the declared source extent.  No two non-contiguous lines are ever
//    merged, and mode 4 (row-inner tiled source) never prefetches across the
//    32-element stride.
//  * no per-row/per-tile u16_divmod; the divider is used only once per
//    descriptor to decompose k_offset in mode 2.
// All element addressing is delta-stepped; multipliers exist only in the
// one-time INIT/PREP and on the miss-time run-end path.
module ddr_layout_engine #(
 // 16 = merge the contiguous run; 1 = no multi-line prefetch (one line per
 // miss).  Parameterised so integration can trade bandwidth for latency.
 parameter integer MAX_PREFETCH = 16
)(
 input wire clk,rst_n,start,input wire [1023:0] descriptor,input wire [31:0] param_end,
 output wire ready,output reg busy,done,fault,output reg [7:0] error_code,
 output reg [31:0] processed_elements,rejected_starts,cache_hits,cache_misses,
 output reg [63:0] cycles,
 output wire rd_request_valid,input wire rd_request_ready,output wire [31:0] rd_address,
 output wire [15:0] rd_beats,input wire rd_valid,output wire rd_ready,
 input wire [127:0] rd_data,input wire [15:0] rd_index,input wire rd_done,rd_error,
 output wire wr_request_valid,input wire wr_request_ready,output wire [31:0] wr_address,
 output wire [15:0] wr_beats,output wire wr_valid,input wire wr_ready,
 output wire [127:0] wr_data,output wire [15:0] wr_strobe,input wire wr_done,wr_error);
 localparam [5:0] IDLE=0,VALIDATE=1,EXTENT1=2,EXTENT2=3,INIT=4,
  INIT_DIV_REQ=5,INIT_DIV_WAIT=6,INIT_DIV2_REQ=7,INIT_DIV2_WAIT=8,
  START=9,PREP0=10,PREP1=11,PREP2=12,
  LOOKUP=13,RREQ=14,RDATA=15,CACHE_READ=16,CACHE_CAPTURE=17,
  VALUE=18,PACK=19,WREQ=20,WDATA=21,WWAIT=22,NEXT=23,COMPLETE=24,DRAIN=25,
  CACHE_SELECT=26,PF_CALC=27,TAIL_PUSH=28;
 reg [5:0] state,after_write;
 reg [1023:0] cfg;
 wire [31:0] mode=cfg[63:32],src=cfg[95:64],dst=cfg[127:96],total=cfg[159:128],bytes=cfg[191:160];
 wire [31:0] m=cfg[223:192],n=cfg[255:224],full_n=cfg[287:256],col_start=cfg[319:288];
 wire [31:0] channels=cfg[351:320],ih=cfg[383:352],iw=cfg[415:384],kh=cfg[447:416],kw=cfg[479:448];
 wire [31:0] oh=cfg[511:480],ow=cfg[543:512],sh=cfg[575:544],sw=cfg[607:576],dh=cfg[639:608],dw=cfg[671:640];
 wire [31:0] ph=cfg[703:672],pw=cfg[735:704],k_offset=cfg[767:736];
 wire [31:0] mt=(m+31)>>5,nt=(n+31)>>5;
 wire [31:0] khkw=kh*kw;
 reg [63:0] source_elements,destination_elements,source_bytes,destination_bytes;
 reg [15:0] tile_row,tile_col,row,col;
 reg [15:0] kernel_channel,kernel_y,kernel_x;
 reg [15:0] tile_kc,tile_ky,tile_kx;      // kernel position at tile column start
 reg [15:0] kc0,ky0,kx0;                  // k_offset decomposition (constant)
 reg [31:0] linear_index;
 reg [31:0] source_address,destination_address,row_src_address,row_dst_address;
 reg [31:0] col_src_address,col_dst_address;
 reg [31:0] line_address;
 reg source_part,read_got,read_bad;
 (* ram_style="block" *) reg [127:0] cache[0:63];
 reg [63:0] cache_valid,cache_match;reg [27:0] cache_tag[0:63];reg [127:0] cache_q,read_q;
 reg [5:0] cache_slot,cache_replace;
 reg [127:0] value_lo,value_hi;
 wire [31:0] source_line=(source_address&32'hfffffff0)+(source_part?16:0);
 wire [27:0] wanted_tag=source_line[31:4];
 wire [63:0] cache_matches;
 for(genvar entry=0;entry<64;entry=entry+1)assign cache_matches[entry]=cache_valid[entry]&&cache_tag[entry]==wanted_tag;
 function automatic [5:0] cache_encoder(input [63:0] mask);
  begin cache_encoder=0;for(integer j=0;j<64;j=j+1)cache_encoder=cache_encoder|(mask[j]?j[5:0]:6'd0);end
 endfunction
 wire [255:0] source_window={value_hi,value_lo}>>(source_address[3:0]*8);
 reg [47:0] fragment_data;reg [31:0] fragment_address;
 reg [3:0] fragment_bytes;
 reg output_valid;reg [127:0] output_data;reg [15:0] output_mask;
 wire [31:0] fragment_line=fragment_address&32'hfffffff0;
 wire [4:0] space=16-{1'b0,fragment_address[3:0]};
 wire [3:0] take=fragment_bytes<=space?fragment_bytes:space[3:0];
 wire [16:0] fragment_mask=((17'd1<<take)-1)<<fragment_address[3:0];
 wire [127:0] fragment_bits={80'd0,fragment_data}<<(fragment_address[3:0]*8);
 wire [127:0] fragment_byte_mask;
 for(genvar lane=0;lane<16;lane=lane+1)assign fragment_byte_mask[lane*8+:8]={8{fragment_mask[lane]}};
 wire [127:0] frag_masked=fragment_bits&fragment_byte_mask;
 wire [127:0] pack_data=((output_valid?output_data:128'd0)&~fragment_byte_mask)|frag_masked;
 wire [15:0] pack_mask=(output_valid?output_mask:16'd0)|fragment_mask[15:0];
 
 // ---- mode-2 im2col coordinate state (incremental) -----------------------
 reg signed [31:0] iy,ix,row_iy,row_ix,base_iy,base_ix;
 reg [15:0] tile_oy,tile_ox;              // output coords at row 0 of this tile row
 reg [15:0] out_y,out_x;                  // output coords of current row
 reg signed [31:0] ky_dh0,kx_dw0;
 // precomputed byte strides (multipliers only at INIT)
 reg [31:0] b_lin;
 reg [31:0] b_row1;                       // mode 1: rr -> rr+1
 reg signed [31:0] b_kx,b_ky,b_kc;        // mode 2 kernel advance
 reg signed [31:0] b_rowx,b_rowy;         // mode 2 out_x ++ / wrap
 reg [31:0] b_c3,b_c3w,b_r3,b_r3w,b_d3;   // mode 3
 reg [31:0] b_c4,b_c4w,b_r4,b_r4w,b_d4;   // mode 4
 reg [31:0] src_end_addr;                 // exclusive end of source extent
 reg [31:0] row_end_addr;                 // mode 1: exclusive end of this row's source run
 reg [31:0] krow_addr;                    // mode 2: src + (kc*ih+iy)*iw*bytes
 reg signed [31:0] b_krow_ky,b_krow_kc;   // mode 2 kernel-row base deltas
 reg signed [31:0] b_krow_row;            // mode 2 out_y++ delta for kernel-row base
 reg [31:0] row_krow_addr;                // mode 2: tile-start kernel-row base of this row
 reg [31:0] b_ixend;                      // mode 2 ((kw-1)*dw+1)*bytes

 // ---- read prefetch ------------------------------------------------------
 reg [4:0] pf_count;                      // lines fetched by the current burst (1..16)
 reg [15:0] rd_count;

 // ---- posted 16-beat write buffer ---------------------------------------
 reg [127:0] wb_data[0:15];
 reg [15:0] wb_strb[0:15];
 reg [4:0] wb_count;
 reg [31:0] wb_base;
 reg [4:0] wb_send;
 reg [127:0] tail_data;
 reg [15:0] tail_mask;
 reg [31:0] tail_addr;
 wire wb_push_full=(wb_count==5'd15);
 wire wb_page_end=(line_address[11:0]==32'hFF0);
 wire wb_disc=(fragment_line!=(line_address+32'd16));
 wire [5:0] pf_slot=source_line[9:4]+rd_index[5:0];
 wire [27:0] pf_tag=wanted_tag+{12'd0,rd_index};

 // one-shot divider for k_offset decomposition (mode 2 only)
 reg [15:0] divide_numerator,divide_denominator;
 wire divider_ready,divide_done,divide_error;wire [15:0] divide_q,divide_r;
 wire divide_start=state==INIT_DIV_REQ||state==INIT_DIV2_REQ;
 u16_divmod indices(.clk(clk),.rst_n(rst_n),.start(divide_start),.numerator(divide_numerator),
  .denominator(divide_denominator),.ready(divider_ready),.done(divide_done),.error(divide_error),.quotient(divide_q),.remainder(divide_r));

 assign ready=!busy&&rd_request_ready&&wr_request_ready;
 assign rd_request_valid=state==RREQ;assign rd_address=source_line;assign rd_beats={11'd0,pf_count};
 assign rd_ready=state==RDATA;
 assign wr_request_valid=state==WREQ;assign wr_address=wb_base;assign wr_beats={11'd0,wb_count};
 assign wr_valid=state==WDATA;assign wr_data=wb_data[wb_send];assign wr_strobe=wb_strb[wb_send];
 wire basic_bad=cfg[31:0]!=32'h224c4159||cfg[1023:768]!=0||mode>4||total==0||total>16777216||
  !(bytes==2||bytes==4||bytes==6)||(src&(bytes==4?3:1))!=0||(dst&(bytes==4?3:1))!=0||
  (mode!=0&&(m==0||m>4096||n==0||n>4096))||
  (mode==1&&(bytes!=2||full_n==0||full_n>8192||k_offset>full_n||k_offset+n>full_n))||
  (mode==2&&(bytes!=2||channels==0||channels>1024||ih==0||ih>8192||iw==0||iw>8192||
    kh==0||kh>31||kw==0||kw>31||oh==0||oh>4096||ow==0||ow>8192||sh==0||sh>64||sw==0||sw>64||
    dh==0||dh>64||dw==0||dw>64||ph>255||pw>255||oh*ow!=m||channels*kh*kw>8192||k_offset>8192||k_offset+n>channels*kh*kw))||
  ((mode==3||mode==4)&&(full_n<n||full_n>4096||col_start>full_n||col_start+n>full_n));
 wire [63:0] source_end={32'd0,src}+((source_bytes+15)&~64'd15);
 wire [63:0] destination_end={32'd0,dst}+((destination_bytes+15)&~64'd15);
 wire extent_bad=source_bytes==0||destination_bytes==0||
  !((src>=32'h03000000&&source_end<=32'h08000000)||
    (src>=32'h10000000&&source_end<=param_end&&param_end<=32'h40000000))||
  dst<32'h03000000||destination_end>32'h08000000||
  ({32'd0,src}<destination_end&&{32'd0,dst}<source_end)||
  ((mode==1||mode==2)&&total!={32'd0,mt}*nt*1024)||((mode==3||mode==4)&&total!={32'd0,m}*n);

 wire [31:0] rr=(tile_row<<5)+row;
 wire [31:0] cc=(tile_col<<5)+col;
 wire [31:0] cc_seg_excl=({16'd0,tile_col}+32'd1)<<5;
 wire [31:0] cc_seg_end=(cc_seg_excl>n)?n:cc_seg_excl;
 reg source_zero;
 always @* begin
  source_zero=0;
  if(mode==1)source_zero=(rr>=m)||(cc>=n);
  else if(mode==2)source_zero=(rr>=m)||(cc>=n)||(kernel_channel>=channels)||
    (iy<0)||(ix<0)||($unsigned(iy)>=ih)||($unsigned(ix)>=iw);
 end

 // ---- prefetch run-end (miss path only) ----------------------------------
 wire [31:0] ix_span=(kw-1)*dw;
 wire signed [31:0] ix_end_p1=row_ix+$signed(ix_span)+32'sd1;
 wire [31:0] ix_run_end=(ix_end_p1<=0)?0:((ix_end_p1>$signed(iw))?iw:ix_end_p1[31:0]);
 wire [31:0] m3_rem_a=32-{27'd0,col[4:0]};
 wire [31:0] m3_rem_b=n-col;
 wire [31:0] m3_rem=(m3_rem_a<m3_rem_b)?m3_rem_a:m3_rem_b;
 wire [31:0] m2_kx_end_far=krow_addr+ix_run_end*bytes;
 wire [31:0] mode2_end_parent=(kernel_x+1>=kw)||(dw*bytes>16)||(ix_run_end<=0)?(source_address+bytes):m2_kx_end_far;
 wire [31:0] mode3_end=source_address+m3_rem*bytes;
 wire [31:0] run_end=(mode==0)?src_end_addr:
                      (mode==1)?row_end_addr:
                      (mode==2)?mode2_end_parent:
                      (mode==3)?mode3_end:
                                (source_address+bytes);
 wire [31:0] pf_end=(run_end>src_end_addr)?src_end_addr:run_end;
 wire [31:0] pf_first=source_line>>4;
 wire [31:0] pf_last=(pf_end<=source_line)?pf_first:((pf_end-1)>>4);
 wire [31:0] pf_run_lines=pf_last-pf_first+1;
 wire [31:0] pf_page_lines=(32'd4096-{20'd0,source_line[11:0]})>>4;
 wire [31:0] pf_ext_lines=(((src_end_addr+15)>>4)-pf_first);
 wire [31:0] pf_min1=(pf_run_lines<pf_page_lines)?pf_run_lines:pf_page_lines;
 wire [31:0] pf_min2=(pf_min1<pf_ext_lines)?pf_min1:pf_ext_lines;
 wire [31:0] pf_choose=(pf_min2==0)?32'd1:((pf_min2>16)?32'd16:pf_min2);
 task fail(input [7:0] code);begin fault<=1;error_code<=code;state<=DRAIN;end endtask

 always @(posedge clk)begin
  if(!rst_n)begin
   state<=IDLE;after_write<=IDLE;cfg<=0;busy<=0;done<=0;fault<=0;error_code<=0;processed_elements<=0;rejected_starts<=0;
   cache_hits<=0;cache_misses<=0;cycles<=0;cache_valid<=0;cache_match<=0;cache_slot<=0;cache_replace<=0;tile_row<=0;tile_col<=0;row<=0;col<=0;linear_index<=0;
   source_elements<=0;destination_elements<=0;source_bytes<=0;destination_bytes<=0;
   source_address<=0;destination_address<=0;row_src_address<=0;row_dst_address<=0;col_src_address<=0;col_dst_address<=0;line_address<=0;
   source_part<=0;read_got<=0;read_bad<=0;
   output_valid<=0;output_data<=0;output_mask<=0;fragment_data<=0;fragment_address<=0;fragment_bytes<=0;
   divide_numerator<=0;divide_denominator<=0;tile_kc<=0;tile_ky<=0;tile_kx<=0;kc0<=0;ky0<=0;kx0<=0;
   kernel_channel<=0;kernel_y<=0;kernel_x<=0;tile_oy<=0;tile_ox<=0;out_y<=0;out_x<=0;
   iy<=0;ix<=0;row_iy<=0;row_ix<=0;base_iy<=0;base_ix<=0;ky_dh0<=0;kx_dw0<=0;
   b_lin<=0;b_row1<=0;b_kx<=0;b_ky<=0;b_kc<=0;b_rowx<=0;b_rowy<=0;
   b_c3<=0;b_c3w<=0;b_r3<=0;b_r3w<=0;b_d3<=0;b_c4<=0;b_c4w<=0;b_r4<=0;b_r4w<=0;b_d4<=0;
   src_end_addr<=0;row_end_addr<=0;krow_addr<=0;row_krow_addr<=0;b_krow_ky<=0;b_krow_kc<=0;b_krow_row<=0;b_ixend<=0;
   pf_count<=1;rd_count<=0;wb_count<=0;wb_base<=0;wb_send<=0;tail_data<=0;tail_mask<=0;tail_addr<=0;
   value_lo<=0;value_hi<=0;
  end else begin
   done<=0;if(start&&!ready)rejected_starts<=rejected_starts+1;
   if(start&&ready)begin
    cfg<=descriptor;state<=VALIDATE;busy<=1;fault<=0;error_code<=0;processed_elements<=0;cycles<=0;cache_hits<=0;cache_misses<=0;
    cache_valid<=0;cache_replace<=0;output_valid<=0;output_data<=0;output_mask<=0;tile_row<=0;tile_col<=0;row<=0;col<=0;linear_index<=0;
    source_part<=0;value_hi<=0;value_lo<=0;wb_count<=0;wb_base<=0;wb_send<=0;pf_count<=1;rd_count<=0;
   end else if(busy)begin
    cycles<=cycles+1;
    case(state)
     VALIDATE:if(basic_bad)fail(8'h01);else begin
      if(mode==0)begin source_elements<=total;destination_elements<=total;end
      else if(mode==1)begin source_elements<={32'd0,m}*full_n;destination_elements<=total;end
      else if(mode==2)begin source_elements<={32'd0,channels}*ih;destination_elements<=total;end
      else begin source_elements<={32'd0,mt}*nt*1024;destination_elements<=mode==3?{32'd0,m-32'd1}*full_n+col_start+n:{32'd0,col_start+n}*m;end
      state<=EXTENT1;
     end
     EXTENT1:begin source_bytes<=source_elements*(mode==2?iw*2:bytes);destination_bytes<=destination_elements*bytes;state<=EXTENT2;end
     EXTENT2:if(extent_bad)fail(8'h01);else state<=INIT;
     INIT:begin
      // One-time stride precomputation.  These are the only multipliers used
      // by the element loop; they are evaluated once per descriptor.
      b_lin<=bytes;
      b_row1<=full_n*bytes;
      b_kx<=dw*bytes;
      b_ky<=(dh*iw-(kw-1)*dw)*bytes;
      b_kc<=((ih-(kh-1)*dh)*iw-(kw-1)*dw)*bytes;
      b_rowx<=sw*bytes;
      b_rowy<=(sh*iw-(ow-1)*sw)*bytes;
      b_c3<=bytes; b_c3w<=993*bytes;
      b_r3<=32*bytes; b_r3w<=(nt*1024-992)*bytes;
      b_d3<=full_n*bytes;
      b_c4<=bytes; b_c4w<=993*bytes;
      b_r4<=32*bytes; b_r4w<=(nt*1024-992)*bytes;
      b_d4<=m*bytes;
      src_end_addr<=src+source_bytes;
      b_krow_ky<=(dh*iw)*bytes;
      b_krow_kc<=((ih-(kh-1)*dh)*iw)*bytes;
      b_krow_row<=(sh*iw)*bytes;
      b_ixend<=((kw-1)*dw+1)*bytes;
      tile_row<=0;tile_col<=0;row<=0;col<=0;linear_index<=0;
      if(mode==2)begin divide_numerator<=k_offset[15:0];divide_denominator<=khkw[15:0];state<=INIT_DIV_REQ;end
      else state<=START;
     end
     INIT_DIV_REQ:if(divider_ready)state<=INIT_DIV_WAIT;
     INIT_DIV_WAIT:if(divide_done)begin
      if(divide_error)fail(8'h01);else begin
       kc0<=divide_q;divide_numerator<=divide_r;divide_denominator<=kw[15:0];state<=INIT_DIV2_REQ;
      end
     end
     INIT_DIV2_REQ:if(divider_ready)state<=INIT_DIV2_WAIT;
     INIT_DIV2_WAIT:if(divide_done)begin
      if(divide_error)fail(8'h01);else begin ky0<=divide_q;kx0<=divide_r;state<=START;end
     end
     START:begin
      if(mode==0)begin
       source_address<=src;destination_address<=dst;state<=LOOKUP;
      end else if(mode==1)begin
       destination_address<=dst;state<=PREP0;
      end else if(mode==2)begin
       tile_oy<=0;tile_ox<=0;tile_kc<=kc0;tile_ky<=ky0;tile_kx<=kx0;destination_address<=dst;
       state<=PREP0;
      end else if(mode==3)begin
       row_src_address<=src;source_address<=src;
       row_dst_address<=dst+col_start*bytes;destination_address<=dst+col_start*bytes;
       state<=LOOKUP;
      end else begin
       col_src_address<=src;source_address<=src;
       col_dst_address<=dst+col_start*m*bytes;destination_address<=dst+col_start*m*bytes;
       state<=LOOKUP;
      end
     end
     PREP0:begin
      // staged (multi-cycle, once per tile) address recomputation
      base_iy<=$signed({16'd0,tile_oy})*$signed(sh)-$signed(ph);
      base_ix<=$signed({16'd0,tile_ox})*$signed(sw)-$signed(pw);
      ky_dh0<=$signed({16'd0,tile_ky})*$signed(dh);
      kx_dw0<=$signed({16'd0,tile_kx})*$signed(dw);
      state<=PREP1;
     end
     PREP1:begin
      kernel_channel<=tile_kc;kernel_y<=tile_ky;kernel_x<=tile_kx;
      out_y<=tile_oy;out_x<=tile_ox;
      row_iy<=base_iy;row_ix<=base_ix;
      iy<=base_iy+ky_dh0;ix<=base_ix+kx_dw0;
      state<=PREP2;
     end
     PREP2:begin
      if(mode==1)begin
       row_src_address<=src+(({16'd0,tile_row}<<5)*full_n+(tile_col<<5)+k_offset)*bytes;
       source_address<=src+(({16'd0,tile_row}<<5)*full_n+(tile_col<<5)+k_offset)*bytes;
       row_end_addr<=src+(({16'd0,tile_row}<<5)*full_n+cc_seg_end+k_offset)*bytes;
      end else begin
       row_src_address<=src+(({16'd0,tile_kc}*ih+base_iy+ky_dh0)*iw+(base_ix+kx_dw0))*bytes;
       source_address<=src+(({16'd0,tile_kc}*ih+base_iy+ky_dh0)*iw+(base_ix+kx_dw0))*bytes;
       row_krow_addr<=src+(({16'd0,tile_kc}*ih+base_iy+ky_dh0)*iw)*bytes;
       krow_addr<=src+(({16'd0,tile_kc}*ih+base_iy+ky_dh0)*iw)*bytes;
      end
      state<=LOOKUP;
     end
     LOOKUP:begin
      if(source_zero)begin
       fragment_data<=0;fragment_address<=destination_address;fragment_bytes<=bytes[3:0];state<=PACK;
      end else if(mode==4)begin cache_match<=cache_matches;state<=CACHE_SELECT;end
      else begin
       cache_slot<=source_line[9:4];
       if(cache_valid[source_line[9:4]]&&cache_tag[source_line[9:4]]==wanted_tag)begin cache_hits<=cache_hits+1;state<=CACHE_READ;end
       else begin cache_misses<=cache_misses+1;state<=PF_CALC;end
      end
     end
     CACHE_SELECT:if(|cache_match)begin cache_slot<=cache_encoder(cache_match);cache_hits<=cache_hits+1;state<=CACHE_READ;end
      else begin cache_slot<=cache_replace;cache_replace<=cache_replace+1;cache_misses<=cache_misses+1;state<=PF_CALC;end
     PF_CALC:begin
      // pf_choose is the bounded contiguous line run computed from the
      // current source segment, page and declared source extent.
      pf_count<=(mode==4||MAX_PREFETCH<=1)?5'd1:
                ((pf_choose>MAX_PREFETCH)?MAX_PREFETCH[4:0]:pf_choose[4:0]);
      rd_count<=0;read_bad<=0;
      state<=RREQ;
     end
     RREQ:if(rd_request_ready)begin rd_count<=0;read_bad<=0;state<=RDATA;end
     RDATA:begin
      if(rd_valid)begin
       if(mode==4)begin
        cache[cache_slot]<=rd_data;cache_tag[cache_slot]<=wanted_tag;cache_valid[cache_slot]<=1;
       end else begin
        cache[pf_slot]<=rd_data;cache_tag[pf_slot]<=pf_tag;cache_valid[pf_slot]<=1;
       end
       if(rd_index!=rd_count)read_bad<=1;
       rd_count<=rd_count+1;
      end
      if(rd_done)begin
       if(rd_error||read_bad||((rd_count+(rd_valid?16'd1:16'd0))!=pf_count))fail(8'h02);
       else state<=CACHE_READ;
      end
     end
     CACHE_READ:begin cache_q<=cache[cache_slot];state<=CACHE_CAPTURE;end
     CACHE_CAPTURE:if(!source_part)begin
      value_lo<=cache_q;
      if({1'b0,source_address[3:0]}+bytes>16)begin source_part<=1;state<=LOOKUP;end
      else begin value_hi<=0;state<=VALUE;end
     end else begin value_hi<=cache_q;state<=VALUE;end
     VALUE:begin fragment_data<=source_window[47:0];fragment_address<=destination_address;fragment_bytes<=bytes[3:0];state<=PACK;end
     PACK:begin
      if(output_valid&&line_address!=fragment_line)begin
       // Current destination line is complete: post it to the burst buffer.
       wb_data[wb_count]<=output_data;wb_strb[wb_count]<=output_mask;
       if(wb_count==0)wb_base<=line_address;
       wb_count<=wb_count+1;
       if(wb_push_full||wb_page_end||wb_disc)begin
        // 16-beat full, 4 KiB cut, or non-contiguous next line: flush.
        output_valid<=0;after_write<=PACK;state<=WREQ;
       end else begin
        line_address<=fragment_line;output_valid<=1;
        output_data<=frag_masked;output_mask<=fragment_mask[15:0];
        if(fragment_bytes>take)begin
         fragment_data<=fragment_data>>(take*8);fragment_address<=fragment_address+take;fragment_bytes<=fragment_bytes-take;
        end else begin
         processed_elements<=processed_elements+1;linear_index<=linear_index+1;
         if(linear_index+1==total)begin
          // The just-started line is the last one and the previous line was
          // also posted this cycle: defer its push by one cycle.
          tail_data<=frag_masked;tail_mask<=fragment_mask[15:0];tail_addr<=fragment_line;
          after_write<=COMPLETE;state<=TAIL_PUSH;
         end else state<=NEXT;
        end
       end
      end else begin
       line_address<=fragment_line;output_valid<=1;
       output_data<=pack_data;output_mask<=pack_mask;
       if(fragment_bytes>take)begin
        fragment_data<=fragment_data>>(take*8);fragment_address<=fragment_address+take;fragment_bytes<=fragment_bytes-take;
       end else begin
        processed_elements<=processed_elements+1;linear_index<=linear_index+1;
        if(linear_index+1==total)begin
         wb_data[wb_count]<=pack_data;wb_strb[wb_count]<=pack_mask;
         if(wb_count==0)wb_base<=fragment_line;
         wb_count<=wb_count+1;output_valid<=0;after_write<=COMPLETE;state<=WREQ;
        end else state<=NEXT;
       end
      end
     end
     TAIL_PUSH:begin
      wb_data[wb_count]<=tail_data;wb_strb[wb_count]<=tail_mask;
      if(wb_count==0)wb_base<=tail_addr;
      wb_count<=wb_count+1;output_valid<=0;after_write<=COMPLETE;state<=WREQ;
     end
     NEXT:begin
      state<=LOOKUP;
      source_part<=0;value_hi<=0;
      destination_address<=destination_address+b_lin;
      if(mode==0)begin
       source_address<=source_address+b_lin;
      end else if(mode==1)begin
       if(col!=31)begin
        col<=col+1;source_address<=source_address+b_lin;
       end else begin
        col<=0;
        if(row!=31)begin
         row<=row+1;row_src_address<=row_src_address+b_row1;row_end_addr<=row_end_addr+b_row1;source_address<=row_src_address+b_row1;
        end else begin
         row<=0;
         if(tile_col+1<nt)tile_col<=tile_col+1;else begin tile_col<=0;tile_row<=tile_row+1;end
         state<=PREP0;
        end
       end
      end else if(mode==2)begin
       if(col!=31)begin
        col<=col+1;
        if(kernel_x+1<kw)begin
         kernel_x<=kernel_x+1;ix<=ix+$signed(dw);source_address<=source_address+b_kx;
        end else if(kernel_y+1<kh)begin
         kernel_x<=0;kernel_y<=kernel_y+1;ix<=ix-(kw-1)*$signed(dw);iy<=iy+$signed(dh);source_address<=source_address+b_ky;krow_addr<=krow_addr+b_krow_ky;
        end else begin
         kernel_x<=0;kernel_y<=0;kernel_channel<=kernel_channel+1;
         ix<=ix-(kw-1)*$signed(dw);iy<=iy-(kh-1)*$signed(dh);source_address<=source_address+b_kc;krow_addr<=krow_addr+b_krow_kc;
        end
       end else begin
        col<=0;
        if(row!=31)begin
         row<=row+1;
         if(out_x+1<ow)begin
          out_x<=out_x+1;row_ix<=row_ix+$signed(sw);
          source_address<=row_src_address+b_rowx;ix<=row_ix+$signed(sw)+kx_dw0;iy<=row_iy+ky_dh0;krow_addr<=row_krow_addr;
         end else begin
          out_x<=0;out_y<=out_y+1;row_ix<=row_ix-(ow-1)*$signed(sw);row_iy<=row_iy+$signed(sh);
          source_address<=row_src_address+b_rowy;ix<=row_ix-(ow-1)*$signed(sw)+kx_dw0;
          iy<=row_iy+$signed(sh)+ky_dh0;row_krow_addr<=row_krow_addr+b_krow_row;krow_addr<=row_krow_addr+b_krow_row;
         end
         if(out_x+1<ow)row_src_address<=row_src_address+b_rowx;
         else row_src_address<=row_src_address+b_rowy;
         kernel_channel<=tile_kc;kernel_y<=tile_ky;kernel_x<=tile_kx;
        end else begin
         row<=0;
         if(tile_col+1<nt)begin
          tile_col<=tile_col+1;
          if(kernel_x+1<kw)begin tile_kx<=kernel_x+1;tile_ky<=kernel_y;tile_kc<=kernel_channel;end
          else if(kernel_y+1<kh)begin tile_kx<=0;tile_ky<=kernel_y+1;tile_kc<=kernel_channel;end
          else begin tile_kx<=0;tile_ky<=0;tile_kc<=kernel_channel+1;end
         end else begin
          tile_col<=0;tile_row<=tile_row+1;
          if(out_x+1<ow)begin tile_ox<=out_x+1;tile_oy<=out_y;end
          else begin tile_ox<=0;tile_oy<=out_y+1;end
          tile_kc<=kc0;tile_ky<=ky0;tile_kx<=kx0;
         end
         state<=PREP0;
        end
       end
      end else if(mode==3)begin
       if(col+1<n)begin
        col<=col+1;
        if(col[4:0]==5'd31)source_address<=source_address+b_c3w;
        else source_address<=source_address+b_c3;
       end else begin
        col<=0;row<=row+1;
        if(row[4:0]==5'd31)row_src_address<=row_src_address+b_r3w;
        else row_src_address<=row_src_address+b_r3;
        row_dst_address<=row_dst_address+b_d3;
        source_address<=(row[4:0]==5'd31)?row_src_address+b_r3w:row_src_address+b_r3;
        destination_address<=row_dst_address+b_d3;
       end
      end else begin // mode 4
       if(row+1<m)begin
        row<=row+1;
        if(row[4:0]==5'd31)source_address<=source_address+b_r4w;
        else source_address<=source_address+b_r4;
       end else begin
        row<=0;col<=col+1;
        if(col[4:0]==5'd31)col_src_address<=col_src_address+b_c4w;
        else col_src_address<=col_src_address+b_c4;
        col_dst_address<=col_dst_address+b_d4;
        source_address<=(col[4:0]==5'd31)?col_src_address+b_c4w:col_src_address+b_c4;
        destination_address<=col_dst_address+b_d4;
       end
      end
     end
     WREQ:if(wr_request_ready)begin wb_send<=0;state<=WDATA;end
     WDATA:if(wr_ready)begin
      if(wb_send+1==wb_count)state<=WWAIT;else wb_send<=wb_send+1;
     end
     WWAIT:if(wr_done)begin
      if(wr_error)fail(8'h03);else begin wb_count<=0;wb_send<=0;output_valid<=0;output_data<=0;output_mask<=0;state<=after_write;end
     end
     COMPLETE:begin busy<=0;done<=1;state<=IDLE;end
     DRAIN:if(rd_request_ready&&wr_request_ready)begin busy<=0;done<=1;state<=IDLE;end
     default:fail(8'hff);
    endcase
   end
  end
 end
endmodule
