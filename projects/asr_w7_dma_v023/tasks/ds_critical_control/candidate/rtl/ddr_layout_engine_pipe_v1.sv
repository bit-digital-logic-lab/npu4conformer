`timescale 1ns/1ps
// PL bit-copy/layout only. No floating arithmetic or approximate quantization.
// COPY, rowmajor->A16tile, conv im2col->A16tile, tiled->rowmajor/NCHWcompact.
module ddr_layout_engine(
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
 localparam IDLE=0,VALIDATE=1,EXTENT1=2,EXTENT2=3,INIT=4,
  TILE_DIV_REQ=5,TILE_DIV_WAIT=6,KERNEL_DIV_REQ=7,KERNEL_DIV_WAIT=8,
  ROW_DIV_REQ=9,ROW_DIV_WAIT=10,CALC=11,ADDR1=27,ADDRESS=12,LOOKUP=13,
  RREQ=14,RDATA=15,CACHE_READ=16,CACHE_CAPTURE=17,VALUE=18,
  PACK=19,WREQ=20,WDATA=21,WWAIT=22,NEXT=23,COMPLETE=24,DRAIN=25,CACHE_SELECT=26;
 reg [4:0] state,after_write;
 reg [1023:0] cfg;
 wire [31:0] mode=cfg[63:32],src=cfg[95:64],dst=cfg[127:96],total=cfg[159:128],bytes=cfg[191:160];
 wire [31:0] m=cfg[223:192],n=cfg[255:224],full_n=cfg[287:256],col_start=cfg[319:288];
 wire [31:0] channels=cfg[351:320],ih=cfg[383:352],iw=cfg[415:384],kh=cfg[447:416],kw=cfg[479:448];
 wire [31:0] oh=cfg[511:480],ow=cfg[543:512],sh=cfg[575:544],sw=cfg[607:576],dh=cfg[639:608],dw=cfg[671:640];
 wire [31:0] ph=cfg[703:672],pw=cfg[735:704],k_offset=cfg[767:736];
 wire [31:0] mt=(m+31)>>5,nt=(n+31)>>5;
 reg [63:0] source_elements,destination_elements,source_bytes,destination_bytes;
 reg [15:0] tile_row,tile_col,row,col;
 reg [15:0] kernel_channel_start,kernel_y_start,kernel_x_start,kernel_remainder;
 reg [15:0] kernel_channel,kernel_y,kernel_x,out_y,out_x;
 reg [31:0] linear_index;
 reg [63:0] source_index,destination_index;
 reg source_zero;
 reg [31:0] source_address,destination_address,line_address;
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
 reg [15:0] divide_numerator,divide_denominator;
 wire divider_ready,divide_done,divide_error;wire [15:0] divide_q,divide_r;
 wire divide_start=state==TILE_DIV_REQ||state==KERNEL_DIV_REQ||state==ROW_DIV_REQ;
 u16_divmod indices(.clk(clk),.rst_n(rst_n),.start(divide_start),.numerator(divide_numerator),
  .denominator(divide_denominator),.ready(divider_ready),.done(divide_done),.error(divide_error),.quotient(divide_q),.remainder(divide_r));
 assign ready=!busy&&rd_request_ready&&wr_request_ready;
 assign rd_request_valid=state==RREQ;assign rd_address=source_line;assign rd_beats=1;
 assign rd_ready=state==RDATA;
 assign wr_request_valid=state==WREQ;assign wr_address=line_address;assign wr_beats=1;
 assign wr_valid=state==WDATA;assign wr_data=output_data;assign wr_strobe=output_mask;
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
 wire [31:0] rr=tile_row*32+row,cc=tile_col*32+col;
 reg signed [31:0] iy,ix;
 // Staged address formation.  CALC registers the channel*ih product; ADDR1
 // forms the multidimensional index (one multiplier level); ADDRESS applies
 // the byte size.  Index and byte-offset multiplies are never in one cone.
 reg [63:0] kc_ih;
 wire signed [31:0] input_y=$signed({16'd0,out_y})*$signed(sh)+$signed({16'd0,kernel_y})*$signed(dh)-$signed(ph);
 wire signed [31:0] input_x=$signed({16'd0,out_x})*$signed(sw)+$signed({16'd0,kernel_x})*$signed(dw)-$signed(pw);
 task fail(input [7:0] code);begin fault<=1;error_code<=code;state<=DRAIN;end endtask
 always @(posedge clk)begin
  if(!rst_n)begin
   state<=IDLE;after_write<=IDLE;cfg<=0;busy<=0;done<=0;fault<=0;error_code<=0;processed_elements<=0;rejected_starts<=0;
   cache_hits<=0;cache_misses<=0;cycles<=0;cache_valid<=0;cache_match<=0;cache_slot<=0;cache_replace<=0;tile_row<=0;tile_col<=0;row<=0;col<=0;linear_index<=0;
   source_elements<=0;destination_elements<=0;source_bytes<=0;destination_bytes<=0;source_index<=0;destination_index<=0;source_zero<=0;
   source_address<=0;destination_address<=0;line_address<=0;source_part<=0;read_got<=0;read_bad<=0;
   output_valid<=0;output_data<=0;output_mask<=0;fragment_data<=0;fragment_address<=0;fragment_bytes<=0;
   divide_numerator<=0;divide_denominator<=0;kernel_channel_start<=0;kernel_y_start<=0;kernel_x_start<=0;
   kernel_remainder<=0;kernel_channel<=0;kernel_y<=0;kernel_x<=0;out_y<=0;out_x<=0;value_lo<=0;value_hi<=0;iy<=0;ix<=0;
   kc_ih<=0;
  end else begin
   done<=0;if(start&&!ready)rejected_starts<=rejected_starts+1;
   if(start&&ready)begin
    cfg<=descriptor;state<=VALIDATE;busy<=1;fault<=0;error_code<=0;processed_elements<=0;cycles<=0;cache_hits<=0;cache_misses<=0;
    cache_valid<=0;cache_replace<=0;output_valid<=0;output_data<=0;output_mask<=0;tile_row<=0;tile_col<=0;row<=0;col<=0;linear_index<=0;
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
     INIT:if(mode==2)begin divide_numerator<=k_offset[15:0];divide_denominator<=kh*kw;state<=TILE_DIV_REQ;end
      else state<=CALC;
     TILE_DIV_REQ:if(divider_ready)state<=TILE_DIV_WAIT;
     TILE_DIV_WAIT:if(divide_done)begin
      if(divide_error)fail(8'h01);else begin
       kernel_channel_start<=divide_q;kernel_remainder<=divide_r;
       divide_numerator<=divide_r;divide_denominator<=kw[15:0];state<=KERNEL_DIV_REQ;
      end
     end
     KERNEL_DIV_REQ:if(divider_ready)state<=KERNEL_DIV_WAIT;
     KERNEL_DIV_WAIT:if(divide_done)begin
      if(divide_error)fail(8'h01);else begin
       kernel_y_start<=divide_q;kernel_x_start<=divide_r;
       divide_numerator<=rr[15:0];divide_denominator<=ow[15:0];state<=ROW_DIV_REQ;
      end
     end
     ROW_DIV_REQ:if(divider_ready)state<=ROW_DIV_WAIT;
     ROW_DIV_WAIT:if(divide_done)begin
      if(divide_error)fail(8'h01);else begin
       out_y<=divide_q;out_x<=divide_r;kernel_channel<=kernel_channel_start;
       kernel_y<=kernel_y_start;kernel_x<=kernel_x_start;state<=CALC;
      end
     end
     CALC:begin
      // Coordinate formation and predicates.  kc*ih is the only product
      // registered here; the (kc*ih+iy)*iw index multiply is isolated in ADDR1.
      source_zero<=0;
      if(mode==1)source_zero<=rr>=m||cc>=n;
      else if(mode==2)begin
       iy<=input_y;ix<=input_x;
       kc_ih<={48'd0,kernel_channel}*ih;
       source_zero<=rr>=m||cc>=n||kernel_channel>=channels||input_y<0||input_x<0||$unsigned(input_y)>=ih||$unsigned(input_x)>=iw;
      end
      state<=ADDR1;
     end
     ADDR1:begin
      if(mode==0)begin source_index<=linear_index;destination_index<=linear_index;end
      else if(mode==1)begin source_index<={32'd0,rr}*full_n+cc+k_offset;destination_index<=linear_index;end
      else if(mode==2)begin
       source_index<=(kc_ih+{32'd0,iy})*iw+$unsigned(ix);
       destination_index<=linear_index;
      end else begin
       source_index<=(({48'd0,row[15:5]}*nt+col[15:5])<<10)+({48'd0,row[4:0]}<<5)+col[4:0];
       destination_index<=mode==3?({48'd0,row}*full_n+col_start+col):({32'd0,col_start+col}*m+row);
      end
      state<=ADDRESS;
     end
     ADDRESS:begin
      source_address<=src+source_index*bytes;destination_address<=dst+destination_index*bytes;
      source_part<=0;value_hi<=0;
      if(source_zero)begin fragment_data<=0;fragment_address<=dst+destination_index*bytes;fragment_bytes<=bytes[3:0];state<=PACK;end
      else state<=LOOKUP;
     end
     // Register parallel tag comparison before the encoder/RAM address path.
     // Full associativity avoids row-stride conflicts without more payload RAM.
     LOOKUP:if(mode==4)begin cache_match<=cache_matches;state<=CACHE_SELECT;end
      else begin
       cache_slot<=source_line[9:4];
       if(cache_valid[source_line[9:4]]&&cache_tag[source_line[9:4]]==wanted_tag)begin cache_hits<=cache_hits+1;state<=CACHE_READ;end
       else begin cache_misses<=cache_misses+1;state<=RREQ;end
      end
     CACHE_SELECT:if(|cache_match)begin cache_slot<=cache_encoder(cache_match);cache_hits<=cache_hits+1;state<=CACHE_READ;end
      else begin cache_slot<=cache_replace;cache_replace<=cache_replace+1;cache_misses<=cache_misses+1;state<=RREQ;end
     RREQ:if(rd_request_ready)begin read_got<=0;read_bad<=0;state<=RDATA;end
     RDATA:begin
      if(rd_valid)begin read_q<=rd_data;read_got<=1;if(rd_index!=0||read_got)read_bad<=1;end
      if(rd_done)begin
       if(rd_error||read_bad||!read_got)fail(8'h02);
       else begin cache[cache_slot]<=read_q;cache_tag[cache_slot]<=wanted_tag;cache_valid[cache_slot]<=1;state<=CACHE_READ;end
      end
     end
     CACHE_READ:begin cache_q<=cache[cache_slot];state<=CACHE_CAPTURE;end
     CACHE_CAPTURE:if(!source_part)begin
      value_lo<=cache_q;
      if({1'b0,source_address[3:0]}+bytes>16)begin source_part<=1;state<=LOOKUP;end
      else begin value_hi<=0;state<=VALUE;end
     end else begin value_hi<=cache_q;state<=VALUE;end
     VALUE:begin fragment_data<=source_window[47:0];fragment_address<=destination_address;fragment_bytes<=bytes[3:0];state<=PACK;end
     PACK:if(output_valid&&line_address!=fragment_line)begin after_write<=PACK;state<=WREQ;end
      else begin
       line_address<=fragment_line;output_valid<=1;
       output_data<=((output_valid?output_data:128'd0)&~fragment_byte_mask)|(fragment_bits&fragment_byte_mask);
       output_mask<=(output_valid?output_mask:16'd0)|fragment_mask[15:0];
       if(fragment_bytes>take)begin
        fragment_data<=fragment_data>>(take*8);fragment_address<=fragment_address+take;fragment_bytes<=fragment_bytes-take;
       end else begin
        processed_elements<=processed_elements+1;linear_index<=linear_index+1;
        if(linear_index+1==total)begin after_write<=COMPLETE;state<=WREQ;end else state<=NEXT;
       end
      end
     NEXT:begin
      state<=CALC;
      if(mode==1||mode==2)begin
       if(col!=31)begin
        col<=col+1;
        if(mode==2)begin
         if(kernel_x+1<kw)kernel_x<=kernel_x+1;
         else begin kernel_x<=0;if(kernel_y+1<kh)kernel_y<=kernel_y+1;else begin kernel_y<=0;kernel_channel<=kernel_channel+1;end end
        end
       end else begin
        col<=0;
        if(row!=31)begin
         row<=row+1;
         if(mode==2)begin divide_numerator<=tile_row*32+row+1;divide_denominator<=ow[15:0];state<=ROW_DIV_REQ;end
        end else begin
         row<=0;
         if(tile_col+1<nt)begin
          tile_col<=tile_col+1;
          if(mode==2)begin divide_numerator<=(tile_col+1)*32+k_offset;divide_denominator<=kh*kw;state<=TILE_DIV_REQ;end
         end else begin
          tile_col<=0;tile_row<=tile_row+1;
          if(mode==2)begin divide_numerator<=k_offset[15:0];divide_denominator<=kh*kw;state<=TILE_DIV_REQ;end
         end
        end
       end
      end else if(mode==3)begin if(col+1<n)col<=col+1;else begin col<=0;row<=row+1;end end
      else if(mode==4)begin if(row+1<m)row<=row+1;else begin row<=0;col<=col+1;end end
     end
     WREQ:if(wr_request_ready)state<=WDATA;
     WDATA:if(wr_ready)state<=WWAIT;
     WWAIT:if(wr_done)begin
      if(wr_error)fail(8'h03);else begin output_valid<=0;output_data<=0;output_mask<=0;state<=after_write;end
     end
     COMPLETE:begin busy<=0;done<=1;state<=IDLE;end
     DRAIN:if(rd_request_ready&&wr_request_ready)begin busy<=0;done<=1;state<=IDLE;end
     default:fail(8'hff);
    endcase
   end
  end
 end
endmodule
