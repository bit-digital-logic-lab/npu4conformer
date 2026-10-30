`timescale 1ns/1ps
// WCPG v2 whole-graph controller (V023 candidate, logic only).
//
// One START, one DONE/IRQ.  The controller PL-fetches the header and every
// 192-byte node descriptor from DDR, verifies an FNV-1a integrity hash, then
// schedules nodes whose 1024-bit predecessor mask is fully complete.  Four
// engine classes (SEQ/MAT/VEC/LAY) plus an IN provenance node are supported.
//
// What this block proves: plan bounds/identity, root input provenance, global
// tensor ids, dependency completion, single completion/error exit, and that
// output storage is retained after DONE.  It performs no arithmetic.  Timing
// is structural only; the scan is one node per cycle, not a 600 MHz claim.
//
// Header 64 B (16 words):
//   0 'WCPG' 0x57435047   1 version 0x00020001   2 node_count 1..1024
//   3 flags: bit0 param-RO, bit1 generation, bit2 root provenance required,
//            bit3 at least one output required
//   4 param_end           5 plan_bytes = 64 + 192*node_count
//   6 generation (0=ignore) 7 FNV-1a hash
//   8 input window base   9 input window limit  10..15 zero
//
// Node 192 B (48 words):
//   0 'WCGN' 1 type {1 MAT,2 VEC,3 LAY,4 SEQ,5 IN} 2 id
//   3 flags {bit0 root, bit1 output, bit2 external, bit3 retained,
//            bit4 synthetic-order edge}  4 base  5 count
//   6 input_tid  7 output_tid  8 input_base  9 input_bytes
//  10 output_base 11 output_bytes 12 version 13 epoch 14..15 zero
//  16..47 predecessor mask, bit i = node i   (lower-numbered only)
module wc_graph_ctrl #(
 parameter [31:0] PARAM_BASE=32'h10000000,
 parameter [31:0] PARAM_LIMIT=32'h40000000,
 parameter [31:0] ARENA_BASE=32'h03000000,
 parameter [31:0] ARENA_LIMIT=32'h08000000,
 parameter [31:0] EXTERNAL_BASE=32'h08000000,
 parameter [31:0] EXTERNAL_LIMIT=32'h10000000,
 parameter integer MAX_NODES=1024,
 parameter [63:0] DRAIN_WATCHDOG=64'd200000000
)(
 input wire clk,rst_n,
 input wire start,
 input wire [31:0] plan_base,
 input wire [31:0] param_end,
 input wire parameter_ready,
 input wire [31:0] generation,
 output reg busy,
 output reg done,
 output reg fault,
 output reg [7:0] error_code,
 output reg [31:0] completed,
 output reg [31:0] node_count,
 output reg [31:0] rejected_starts,
 output reg [31:0] last_node,
 output reg [MAX_NODES-1:0] done_mask,
 output reg [63:0] cycles,
 output reg [63:0] fetch_cycles,
 output reg [63:0] operator_cycles,
 output reg [63:0] drain_cycles,
 output reg drain_timeout,
 output reg irq,
 // retained output status (never cleared by DONE)
 output reg output_retained,
 output reg [31:0] output_count,
 output reg [31:0] last_output_tid,
 output reg [31:0] last_output_base,
 output reg [31:0] last_output_bytes,
 // superplan fetch DMA (single outstanding 128-bit reads)
 output wire fetch_req_valid,
 input wire fetch_req_ready,
 output wire [31:0] fetch_address,
 output wire [7:0] fetch_beats,
 input wire fetch_read_valid,
 output wire fetch_read_ready,
 input wire [127:0] fetch_read_data,
 input wire [7:0] fetch_read_index,
 input wire fetch_done,
 input wire fetch_error,
 // engines
 output wire seq_valid,
 input wire seq_ready,
 output wire [31:0] seq_base,
 output wire [31:0] seq_count,
 input wire seq_done,
 input wire seq_fault,
 input wire [7:0] seq_error,
 output wire mat_valid,
 input wire mat_ready,
 output wire [31:0] mat_base,
 output wire [31:0] mat_count,
 input wire mat_done,
 input wire mat_fault,
 input wire [7:0] mat_error,
 output wire vec_valid,
 input wire vec_ready,
 output wire [511:0] vec_descriptor,
 input wire vec_done,
 input wire vec_fault,
 input wire [7:0] vec_error,
 output wire lay_valid,
 input wire lay_ready,
 output wire [1023:0] lay_descriptor,
 input wire lay_done,
 input wire lay_fault,
 input wire [7:0] lay_error,
 output wire direct_idle
);
 localparam IDLE=0,HREQ=1,HFETCH=2,NREQ=3,NFETCH=4,PREQ=5,PFETCH=6,
  SCAN=7,DISPATCH=8,FINISH=9;
 localparam T_MAT=1,T_VEC=2,T_LAY=3,T_SEQ=4,T_IN=5;
 localparam N_PENDING=0,N_PAYLOAD=1,N_DISPATCHED=2,N_DONE=3;
 localparam MAGIC_H=32'h57435047,MAGIC_N=32'h5743474e;
 localparam VERSION=32'h00020001,HASH_SEED=32'h811c9dc5;
 localparam HDR_BYTES=64,NODE_BYTES=192,NODE_BEATS=12;

 reg [3:0] state;
 reg [511:0] header;
 reg [1535:0] node_buf;
 reg [511:0] nd_meta[0:MAX_NODES-1];
 reg [1023:0] nd_dep[0:MAX_NODES-1];
 reg [1:0] nstate[0:MAX_NODES-1];
 reg [31:0] nfetch_index,scan_idx;
 reg [31:0] gen_latched;
 reg [1023:0] payload_buf;
 reg [31:0] payload_addr;
 reg [7:0] payload_beats;
 reg [9:0] payload_node;
 reg [2:0] payload_type;
 reg [31:0] hash;
 reg [31:0] target;
 reg [7:0] hgot,ngot,pgot;
 reg hbad,nbad,pbad;
 reg fault_latched;
 reg [31:0] drain_wait;
 reg [3:0] e_active;
 reg [9:0] e_node[0:3];
 reg [31:0] root_count;

 assign fetch_req_valid=(state==HREQ)||(state==NREQ)||(state==PREQ);
 assign fetch_address=(state==HREQ)?plan_base:
  (state==NREQ)?(plan_base+32'd64+nfetch_index*32'd192):payload_addr;
 assign fetch_beats=(state==HREQ)?8'd4:(state==NREQ)?NODE_BEATS:
  ((payload_beats==8)?8'd8:8'd4);
 assign fetch_read_ready=(state==HFETCH)||(state==NFETCH)||(state==PFETCH);
 assign direct_idle=~|e_active[2:0];

 function [31:0] fnv(input [31:0] h,input [31:0] w);
  begin fnv=(h^w)*32'h01000193;end
 endfunction
 function [31:0] hash_header(input [511:0] h);
  integer j;reg [31:0] t;
  begin t=HASH_SEED;
   for(j=0;j<16;j=j+1)if(j!=7)t=fnv(t,h[j*32+:32]);
   hash_header=t;
  end
 endfunction
 function [31:0] hash_node(input [31:0] h,input [1535:0] d);
  integer j;reg [31:0] t;
  begin t=h;
   for(j=0;j<48;j=j+1)t=fnv(t,d[j*32+:32]);
   hash_node=t;
  end
 endfunction
 function readable(input [31:0] p,input [63:0] n,input [31:0] pe);
  reg [63:0] e;
  begin e={32'd0,p}+n;
   readable=n!=0&&((p>=PARAM_BASE&&e<={32'd0,pe}&&pe<=PARAM_LIMIT)||
    (p>=ARENA_BASE&&e<={32'd0,ARENA_LIMIT})||
    (p>=EXTERNAL_BASE&&e<={32'd0,EXTERNAL_LIMIT}));
  end
 endfunction
 function writable_arena(input [31:0] p,input [63:0] n);
  reg [63:0] e;
  begin e={32'd0,p}+n;
   writable_arena=n!=0&&p>=ARENA_BASE&&e<={32'd0,ARENA_LIMIT};
  end
 endfunction
 function overlap(input [31:0] p,input [63:0] pn,input [31:0] q,input [63:0] qn);
  begin overlap=({32'd0,p}<({32'd0,q}+qn))&&({32'd0,q}<({32'd0,p}+pn));end
 endfunction
 // Real V022 vector/layout descriptor ACLs, with the external boundary window
 // admitted as a read-only source.  Destination remains the owned arena.
 function vec_ok(input [511:0] d,input [31:0] pe);
  reg [7:0] op;reg a16,o16,bs,as_,cs,a48,tiled;
  reg [31:0] a,b,c,dd,total,period;
  reg [63:0] an,bn,cn,dn;
  begin
   op=d[39:32];a16=d[40];o16=d[41];bs=d[42];as_=d[43];cs=d[44];a48=d[45];tiled=d[46];
   a=d[95:64];b=d[127:96];c=d[159:128];dd=d[191:160];total=d[223:192];period=d[255:224];
   an=(as_?64'd1:{32'd0,total})*(a48?64'd6:a16?64'd2:64'd4);
   if(bs)bn=64'd4;
   else if(tiled)bn=({32'd0,period}+64'd31)&~64'd31;
   else if(period!=0)bn={32'd0,period};
   else bn={32'd0,total};
   bn=bn*4;
   cn=({32'd0,total}*4);if(cs)cn=4;
   dn={32'd0,total}*(o16?64'd2:64'd4);
   vec_ok=d[31:0]==32'h22564543&&d[63:47]==0&&d[511:256]==0&&
    total!=0&&total<=32'd16777216&&(op<=8'h0f||op==8'h11)&&
    (period==0||((!bs)&&(op<=3||op==9||op==10||op==11||op==14||op==17)&&
      (!a48)&&period<=4096&&(tiled||(period&(period-1))==0)))&&
    (tiled==0||(period!=0&&total[9:0]==0))&&!(a16&&a48)&&
    !(a48&&(op!=14||as_||bs))&&!(o16&&op!=15)&&
    dd[3:0]==0&&dd>=ARENA_BASE&&({32'd0,dd}+((dn+64'd15)&~64'd15))<={32'd0,ARENA_LIMIT}&&
    (a&((a48||a16)?32'd1:32'd3))==0&&readable(a,an,pe)&&!overlap(a,an,dd,dn)&&
    (!(op<=3||op==9||op==10||op==11||op==14||op==17)||
      ((!a48)&&b[1:0]==0&&readable(b,bn,pe)&&!overlap(b,bn,dd,dn)))&&
    (op!=17||(c[1:0]==0&&readable(c,cn,pe)&&!overlap(c,cn,dd,dn)));
  end
 endfunction
 function lay_ok(input [1023:0] d,input [31:0] pe);
  reg [31:0] mode,src,dst,total,nb,m,n,fn,cs_,ch,ih,iw,kh,kw,oh,ow,sh,sw,dh,dw,ph,pw,ko;
  reg [63:0] sb,db,se,de;reg [31:0] delem,tilesv;
  begin
   mode=d[63:32];src=d[95:64];dst=d[127:96];total=d[159:128];nb=d[191:160];
   m=d[223:192];n=d[255:224];fn=d[287:256];cs_=d[319:288];
   ch=d[351:320];ih=d[383:352];iw=d[415:384];kh=d[447:416];kw=d[479:448];
   oh=d[511:480];ow=d[543:512];sh=d[575:544];sw=d[607:576];
   dh=d[639:608];dw=d[671:640];ph=d[703:672];pw=d[735:704];ko=d[767:736];
   delem=0;tilesv=((m+31)/32)*((n+31)/32)*1024;
   if(mode==0)begin sb={32'd0,total}*{32'd0,nb};delem=total;end
   else if(mode==1)begin sb={32'd0,m}*{32'd0,fn}*{32'd0,nb};delem=total;end
   else if(mode==2)begin sb={32'd0,ch}*{32'd0,ih}*{32'd0,iw}*64'd2;delem=total;end
   else if(mode==3)begin sb={32'd0,tilesv}*{32'd0,nb};delem=(m-1)*fn+cs_+n;end
   else if(mode==4)begin sb={32'd0,tilesv}*{32'd0,nb};delem=(cs_+n)*m;end
   else begin sb=0;delem=0;end
   db={32'd0,delem}*{32'd0,nb};
   if(db<{32'd0,total}*{32'd0,nb})db={32'd0,total}*{32'd0,nb};
   se={32'd0,src}+((sb+64'd15)&~64'd15);de={32'd0,dst}+((db+64'd15)&~64'd15);
   lay_ok=d[31:0]==32'h224c4159&&d[1023:768]==0&&mode<=4&&total!=0&&
    total<=32'd16777216&&(nb==2||nb==4||nb==6)&&
    (src&((nb==4)?32'd3:32'd1))==0&&(dst&((nb==4)?32'd3:32'd1))==0&&
    (mode==0||(m!=0&&m<=4096&&n!=0&&n<=4096))&&
    (mode!=1||(nb==2&&fn!=0&&fn<=8192&&ko<=fn&&ko+n<=fn))&&
    (mode!=2||(nb==2&&ch!=0&&ch<=1024&&ih!=0&&ih<=8192&&iw!=0&&iw<=8192&&
      kh!=0&&kh<=31&&kw!=0&&kw<=31&&oh!=0&&oh<=4096&&ow!=0&&ow<=8192&&
      sh!=0&&sh<=64&&sw!=0&&sw<=64&&dh!=0&&dh<=64&&dw!=0&&dw<=64&&
      ph<=255&&pw<=255&&oh*ow==m&&ch*kh*kw<=8192&&ko<=8192&&ko+n<=ch*kh*kw))&&
    ((mode!=3&&mode!=4)||(fn>=n&&fn<=4096&&cs_<=fn&&cs_+n<=fn))&&
    dst>=ARENA_BASE&&de<={32'd0,ARENA_LIMIT}&&!overlap(src,sb,dst,db)&&
    readable(src,sb,pe);
  end
 endfunction

 task set_fault(input [7:0] code);
  begin
`ifdef WC_DEBUG_CTRL
   $display("GRAPHFAULT code=%h state=%0d nfetch=%0d dep0=%h meta0=%h flags=%h id=%0d type=%0d hash=%h hh=%h",
    code,state,nfetch_index,node_buf[512+:32],node_buf[31:0],node_buf[127:96],
    node_buf[95:64],node_buf[63:32],hash,header[255:224]);
`endif
   fault<=1;fault_latched<=1;error_code<=code;
  end
 endtask
 task mark_done(input [9:0] n);
  begin
   nstate[n]<=N_DONE;done_mask[n]<=1;last_node<={22'd0,n};
   if(nd_meta[n][127:96]&2)begin
    output_retained<=1;last_output_tid<=nd_meta[n][255:224];
    last_output_base<=nd_meta[n][351:320];
    last_output_bytes<=nd_meta[n][383:352];
   end
  end
 endtask

 assign seq_valid=(state==DISPATCH)&&(nd_meta[target][63:32]==T_SEQ)&&!fault_latched;
 assign mat_valid=(state==DISPATCH)&&(nd_meta[target][63:32]==T_MAT)&&!fault_latched;
 assign vec_valid=(state==DISPATCH)&&(nd_meta[target][63:32]==T_VEC)&&!fault_latched;
 assign lay_valid=(state==DISPATCH)&&(nd_meta[target][63:32]==T_LAY)&&!fault_latched;
 assign seq_base=nd_meta[target][159:128];assign seq_count=nd_meta[target][191:160];
 assign mat_base=nd_meta[target][159:128];assign mat_count=nd_meta[target][191:160];
 assign vec_descriptor=payload_buf[511:0];assign lay_descriptor=payload_buf;

 integer i;reg found;reg [31:0] cand;reg [9:0] ci;
 wire [2:0] nsucc=(e_active[0]&&seq_done&&!seq_fault)+(e_active[1]&&mat_done&&!mat_fault)+
  (e_active[2]&&vec_done&&!vec_fault)+(e_active[3]&&lay_done&&!lay_fault);
 wire node_ready = (state==SCAN)&&(scan_idx<node_count)&&
  (nstate[scan_idx]==N_PENDING)&&((nd_dep[scan_idx]&~done_mask)==0);
 wire [2:0] ntype = nd_meta[scan_idx][66:64];
 wire node_root = nd_meta[scan_idx][96];
 wire [31:0] nflags = nd_meta[scan_idx][127:96];

 always @(posedge clk)begin
  if(!rst_n)begin
   state<=IDLE;busy<=0;done<=0;fault<=0;error_code<=0;completed<=0;node_count<=0;
   rejected_starts<=0;last_node<=0;done_mask<=0;cycles<=0;fetch_cycles<=0;operator_cycles<=0;
   drain_cycles<=0;drain_timeout<=0;irq<=0;output_retained<=0;output_count<=0;
   last_output_tid<=0;last_output_base<=0;last_output_bytes<=0;root_count<=0;
   header<=0;nfetch_index<=0;scan_idx<=0;gen_latched<=0;node_buf<=0;payload_buf<=0;
   payload_addr<=0;payload_beats<=0;payload_node<=0;payload_type<=0;hash<=HASH_SEED;
   target<=0;hgot<=0;ngot<=0;pgot<=0;hbad<=0;nbad<=0;pbad<=0;fault_latched<=0;
   drain_wait<=0;e_active<=0;
   for(i=0;i<MAX_NODES;i=i+1)begin nstate[i]<=0;nd_meta[i]<=0;nd_dep[i]<=0;end
   for(i=0;i<4;i=i+1)e_node[i]<=0;
  end else begin
   done<=0;
   if(start&&busy)rejected_starts<=rejected_starts+1;
   if(busy)cycles<=cycles+1;
   if(state==HFETCH||state==NFETCH||state==PFETCH)fetch_cycles<=fetch_cycles+1;
   if(|e_active)operator_cycles<=operator_cycles+1;

   // engine completion is independent of the fetch FSM
   if(e_active[0]&&seq_done)begin e_active[0]<=0;mark_done(e_node[0]);
    if(seq_fault)set_fault(seq_error==0?8'h05:seq_error); end
   if(e_active[1]&&mat_done)begin e_active[1]<=0;mark_done(e_node[1]);
    if(mat_fault)set_fault(mat_error==0?8'h05:mat_error); end
   if(e_active[2]&&vec_done)begin e_active[2]<=0;mark_done(e_node[2]);
    if(vec_fault)set_fault(vec_error==0?8'h05:vec_error); end
   if(e_active[3]&&lay_done)begin e_active[3]<=0;mark_done(e_node[3]);
    if(lay_fault)set_fault(lay_error==0?8'h05:lay_error); end
   if(nsucc!=0)completed<=completed+nsucc;

   if(fault_latched&&state!=FINISH)begin
    drain_cycles<=drain_cycles+1;
    if(|e_active)begin
     if(drain_wait>=DRAIN_WATCHDOG)drain_timeout<=1;else drain_wait<=drain_wait+1;
    end
   end
   if(busy&&!fault_latched&&state!=FINISH&&(!parameter_ready||generation!=gen_latched))
    set_fault(8'h02);

   case(state)
    IDLE:if(start)begin
     busy<=1;fault<=0;fault_latched<=0;error_code<=0;completed<=0;done_mask<=0;
     cycles<=0;fetch_cycles<=0;operator_cycles<=0;drain_cycles<=0;drain_timeout<=0;
     drain_wait<=0;hash<=HASH_SEED;gen_latched<=generation;irq<=0;
     output_retained<=0;output_count<=0;last_output_tid<=0;last_output_base<=0;
     last_output_bytes<=0;root_count<=0;
     for(i=0;i<MAX_NODES;i=i+1)begin nstate[i]<=0;nd_meta[i]<=0;nd_dep[i]<=0;end
     for(i=0;i<4;i=i+1)e_active[i]<=0;
     if(plan_base[5:0]!=0||param_end>PARAM_LIMIT||param_end<PARAM_BASE+32'd64||
        !parameter_ready||
        !((plan_base>=PARAM_BASE&&plan_base+32'd64<=param_end)||
          (plan_base>=EXTERNAL_BASE&&plan_base+32'd64<=EXTERNAL_LIMIT)))begin
      set_fault(8'h01);state<=FINISH;
     end else begin hgot<=0;hbad<=0;state<=HREQ;end
    end
    HREQ:if(fetch_req_ready)state<=HFETCH;
    HFETCH:begin
     if(fetch_read_valid)begin
      if(fetch_read_index!=hgot||hgot>=4)hbad<=1;
      else header[hgot*128+:128]<=fetch_read_data;
      hgot<=hgot+1;
     end
     if(fetch_done)begin
      if(fetch_error||hbad||hgot!=4)begin set_fault(8'h03);state<=FINISH;end
      else if(header[31:0]!=MAGIC_H||header[63:32]!=VERSION||
        header[95:64]==0||header[95:64]>MAX_NODES||
        header[191:160]!=32'd64+({32'd0,header[95:64]}*32'd192)||
        header[511:320]!=0||
        (header[223:192]!=0&&header[223:192]!=generation)||
        header[287:256]<EXTERNAL_BASE||header[319:288]>EXTERNAL_LIMIT)begin
       set_fault(8'h04);state<=FINISH;
      end else begin
       node_count<=header[95:64];hash<=hash_header(header);nfetch_index<=0;
       ngot<=0;nbad<=0;state<=NREQ;
      end
     end
    end
    NREQ:if(fetch_req_ready)begin ngot<=0;nbad<=0;state<=NFETCH;end
    NFETCH:begin
     if(fetch_read_valid)begin
      if(fetch_read_index!=ngot||ngot>=NODE_BEATS)nbad<=1;
      else node_buf[ngot*128+:128]<=fetch_read_data;
      ngot<=ngot+1;
     end
     if(fetch_done)begin
      if(fetch_error||nbad||ngot!=NODE_BEATS)begin set_fault(8'h03);state<=FINISH;end
      else if(node_buf[31:0]!=MAGIC_N||node_buf[63:32]<T_MAT||
        node_buf[63:32]>T_IN||node_buf[95:64]!=nfetch_index||
        node_buf[511:448]!=0||
        (node_buf[16*32+:1024]&~((1024'd1<<nfetch_index)-1024'd1))!=0)begin
       set_fault(8'h04);state<=FINISH;
      end else if(((node_buf[127:96]&1)&&node_buf[16*32+:1024]!=0)||
        ((node_buf[127:96]&1)&&!readable(node_buf[287:256],node_buf[319:288],header[159:128]))||
        ((node_buf[127:96]&2)&&(!readable(node_buf[351:320],node_buf[383:352],header[159:128])||
          node_buf[255:224]==0))||
        (node_buf[63:32]==T_IN&&(!(node_buf[127:96]&1)||
          !readable(node_buf[351:320],node_buf[383:352],header[159:128]))))begin
       set_fault(8'h08);state<=FINISH;
      end else if((node_buf[63:32]==T_SEQ&&(node_buf[159:128]<PARAM_BASE||
        node_buf[159:128]>=header[159:128]||node_buf[191:160]==0||
        ({32'd0,node_buf[159:128]}+({32'd0,node_buf[191:160]}<<6))>{32'd0,header[159:128]}))||
        (node_buf[63:32]==T_MAT&&(node_buf[159:128]<ARENA_BASE||
        node_buf[159:128]>=ARENA_LIMIT||node_buf[191:160]==0))||
        ((node_buf[63:32]==T_VEC||node_buf[63:32]==T_LAY)&&
        (node_buf[159:128]<PARAM_BASE||node_buf[159:128]>=header[159:128])))begin
       set_fault(8'h07);state<=FINISH;
      end else begin
       nd_meta[nfetch_index]<=node_buf[511:0];
       nd_dep[nfetch_index]<=node_buf[16*32+:1024];
       nstate[nfetch_index]<=N_PENDING;
       if(node_buf[127:96]&1)root_count<=root_count+1;
       if(node_buf[127:96]&2)output_count<=output_count+1;
       hash<=hash_node(hash,node_buf);
       if(nfetch_index+1==header[95:64])begin
        if(hash_node(hash,node_buf)!=header[255:224])begin set_fault(8'h04);state<=FINISH;end
        else begin
         nfetch_index<=0;scan_idx<=0;state<=SCAN;
        end
       end else begin nfetch_index<=nfetch_index+1;state<=NREQ;end
      end
     end
    end
    SCAN:begin
     if(fault_latched)begin
      if(!(|e_active))state<=FINISH;
     end else if(completed==node_count)begin
      if((header[127:96]&8)!=0&&output_count==0)set_fault(8'h0a);
      if((header[127:96]&8)!=0&&!output_retained)set_fault(8'h0a);
      state<=FINISH;
     end else if(!parameter_ready||generation!=gen_latched)begin
      set_fault(8'h02);
     end else begin
      if(scan_idx>=node_count)scan_idx<=0;
      else if(nstate[scan_idx]==N_PENDING&&(nd_dep[scan_idx]&~done_mask)==0)begin
       ci=scan_idx[9:0];
       if(nd_meta[scan_idx][63:32]==T_IN)begin
        mark_done(ci);completed<=completed+1;scan_idx<=scan_idx+1;
       end else if(nd_meta[scan_idx][63:32]==T_SEQ)begin
        if(!e_active[0]&&direct_idle)begin
         target<=scan_idx;state<=DISPATCH;
        end else scan_idx<=scan_idx+1;
       end else if(nd_meta[scan_idx][63:32]==T_MAT)begin
        if(!e_active[1])begin target<=scan_idx;state<=DISPATCH;end
        else scan_idx<=scan_idx+1;
       end else if(nd_meta[scan_idx][63:32]==T_VEC)begin
        if(!e_active[2])begin
         target<=scan_idx;nstate[scan_idx]<=N_PAYLOAD;
         payload_node<=ci;payload_type<=3'd2;
         payload_addr<=nd_meta[scan_idx][159:128];
         payload_beats<=8'd4;pgot<=0;pbad<=0;state<=PREQ;
        end else scan_idx<=scan_idx+1;
       end else begin
        if(!e_active[3])begin
         target<=scan_idx;nstate[scan_idx]<=N_PAYLOAD;
         payload_node<=ci;payload_type<=3'd3;
         payload_addr<=nd_meta[scan_idx][159:128];
         payload_beats<=8'd8;pgot<=0;pbad<=0;state<=PREQ;
        end else scan_idx<=scan_idx+1;
       end
      end else scan_idx<=scan_idx+1;
     end
    end
    PREQ:if(fetch_req_ready)state<=PFETCH;
    PFETCH:begin
     if(fetch_read_valid)begin
      if(fetch_read_index!=pgot||pgot>=payload_beats)pbad<=1;
      else payload_buf[pgot*128+:128]<=fetch_read_data;
      pgot<=pgot+1;
     end
     if(fetch_done)begin
      if(fetch_error||pbad||pgot!=payload_beats)begin set_fault(8'h03);state<=FINISH;end
      else if((payload_type==3'd2&&!vec_ok(payload_buf[511:0],header[159:128]))||
              (payload_type==3'd3&&!lay_ok(payload_buf,header[159:128])))begin
       set_fault(8'h07);state<=FINISH;
      end else state<=DISPATCH;
     end
    end
    DISPATCH:begin
     if(fault_latched)state<=SCAN;
     else if(nd_meta[target][63:32]==T_SEQ)begin
      if(seq_ready)begin e_active[0]<=1;e_node[0]<=target[9:0];
       nstate[target]<=N_DISPATCHED;last_node<=target;state<=SCAN;end
     end else if(nd_meta[target][63:32]==T_MAT)begin
      if(mat_ready)begin e_active[1]<=1;e_node[1]<=target[9:0];
       nstate[target]<=N_DISPATCHED;last_node<=target;state<=SCAN;end
     end else if(nd_meta[target][63:32]==T_VEC)begin
      if(vec_ready)begin e_active[2]<=1;e_node[2]<=target[9:0];
       nstate[target]<=N_DISPATCHED;last_node<=target;state<=SCAN;end
     end else begin
      if(lay_ready)begin e_active[3]<=1;e_node[3]<=target[9:0];
       nstate[target]<=N_DISPATCHED;last_node<=target;state<=SCAN;end
     end
    end
    FINISH:begin
     if(!fault_latched&&(header[127:96]&4)!=0&&root_count==0)set_fault(8'h08);
     busy<=0;done<=1;irq<=1;state<=IDLE;
    end
    default:begin set_fault(8'hff);state<=FINISH;end
   endcase
  end
 end
endmodule
