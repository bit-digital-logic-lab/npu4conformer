`timescale 1ns/1ps
// W7/S6/J54/M30-safe control-only whole-plan scheduler (V023 candidate).
//
// One START reads an immutable header + node descriptors from parameter DDR.
// Nodes are dispatched only after all predecessors in their 128-bit mask have
// completed.  Four engine classes (SEQ/MAT/VEC/LAY) may run concurrently.
// This module performs no arithmetic and never writes parameter DDR.
//
// Node descriptor (64 B, little endian words):
//  0 MAGIC 0x57434e44 ('WCND')   1 type {1 MAT,2 VEC,3 LAY,4 SEQ}
//  2 node_id                      3 dep_mask[31:0]
//  4 dep_mask[63:32]              5 dep_mask[95:64]
//  6 dep_mask[127:96]             7 base / payload address
//  8 count / (0 for VEC/LAY)      9 reserved (0)
// 10 reserved (0)                11 reserved (0)
// 12 flags (0)                   13 epoch (informational)
// 14 reserved (0)                15 reserved (0)
//
// Header (64 B):
//  0 MAGIC 0x5743504c ('WCPL')    1 version 0x00010001
//  2 node_count (1..128)          3 flags (bit0 param RO, bit1 generation check)
//  4 param_end                    5 plan_bytes (64 + 64*node_count)
//  6 generation (0 = ignore)      7 FNV-1a plan hash
//  8..15 reserved (0)
//
// The hash is an integrity check, not a signature.  It covers header words
// 0..6 and 8..15 plus all 16 words of every node descriptor.
module wc_superplan_ctrl #(
 parameter [31:0] PARAM_BASE=32'h10000000,
 parameter [31:0] PARAM_LIMIT=32'h40000000,
 parameter [31:0] ARENA_BASE=32'h03000000,
 parameter [31:0] ARENA_LIMIT=32'h08000000,
 parameter integer MAX_NODES=128,
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
 output reg [127:0] done_mask,
 output reg [63:0] cycles,
 output reg [63:0] fetch_cycles,
 output reg [63:0] operator_cycles,
 output reg [63:0] drain_cycles,
 output reg drain_timeout,
 output reg irq,
 // superplan fetch DMA (single outstanding, 128-bit)
 output wire fetch_req_valid,
 input wire fetch_req_ready,
 output wire [31:0] fetch_address,
 output wire [15:0] fetch_beats,
 input wire fetch_read_valid,
 output wire fetch_read_ready,
 input wire [127:0] fetch_read_data,
 input wire [15:0] fetch_read_index,
 input wire fetch_done,
 input wire fetch_error,
 // sequential-program engine (existing V022 linear plan executor)
 output wire seq_valid,
 input wire seq_ready,
 output wire [31:0] seq_base,
 output wire [31:0] seq_count,
 input wire seq_done,
 input wire seq_fault,
 input wire [7:0] seq_error,
 // matrix queue engine
 output wire mat_valid,
 input wire mat_ready,
 output wire [31:0] mat_base,
 output wire [31:0] mat_count,
 input wire mat_done,
 input wire mat_fault,
 input wire [7:0] mat_error,
 // vector engine
 output wire vec_valid,
 input wire vec_ready,
 output wire [511:0] vec_descriptor,
 input wire vec_done,
 input wire vec_fault,
 input wire [7:0] vec_error,
 // layout engine
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
 localparam T_MAT=1,T_VEC=2,T_LAY=3,T_SEQ=4;
 localparam N_PENDING=0,N_PAYLOAD=1,N_DISPATCHED=2,N_DONE=3;
 localparam MAGIC_H=32'h5743504c,MAGIC_N=32'h57434e44;
 localparam VERSION=32'h00010001;
 localparam HASH_SEED=32'h811c9dc5;

 reg [3:0] state;
 reg [511:0] header;
 reg [511:0] nd[0:MAX_NODES-1];
 reg [1:0] nstate[0:MAX_NODES-1];
 reg [31:0] nfetch_index;
 reg [31:0] gen_latched;
 reg [511:0] node_buf;
 reg [1023:0] payload_buf;
 reg [31:0] payload_addr;
 reg [7:0] payload_beats;
 reg [6:0] payload_node;
 reg [2:0] payload_type;
 reg [31:0] hash;
 reg [31:0] target;
 reg [7:0] hgot,ngot,pgot;
 reg hbad,nbad,pbad;
 reg fault_latched;
 reg [31:0] drain_wait;
 reg [3:0] e_active;
 reg [6:0] e_node[0:3];

 assign fetch_req_valid=(state==HREQ)||(state==NREQ)||(state==PREQ);
 assign fetch_address=(state==HREQ)?plan_base:
  (state==NREQ)?(plan_base+32'd64+(nfetch_index<<6)):payload_addr;
 assign fetch_beats=(state==HREQ||state==NREQ)?16'd4:
  (payload_beats==8?16'd8:16'd4);
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
 function [31:0] hash_node(input [31:0] h,input [511:0] d);
  integer j;reg [31:0] t;
  begin t=h;for(j=0;j<16;j=j+1)t=fnv(t,d[j*32+:32]);hash_node=t;end
 endfunction
 function [127:0] dep_prefix(input [31:0] id);
  begin dep_prefix=(128'd1<<id)-128'd1;end
 endfunction
 function readable(input [31:0] p,input [63:0] n,input [31:0] pe);
  reg [63:0] e;begin e={32'd0,p}+n;
   readable=n!=0&&((p>=PARAM_BASE&&e<={32'd0,pe}&&pe<=PARAM_LIMIT)||
    (p>=ARENA_BASE&&e<={32'd0,ARENA_LIMIT}));
  end
 endfunction
 function overlap(input [31:0] p,input [63:0] pn,input [31:0] q,input [63:0] qn);
  begin overlap=({32'd0,p}<({32'd0,q}+qn))&&({32'd0,q}<({32'd0,p}+pn));end
 endfunction
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
    ((src>=PARAM_BASE&&se<={32'd0,pe}&&pe<=PARAM_LIMIT)||
     (src>=ARENA_BASE&&se<={32'd0,ARENA_LIMIT}));
  end
 endfunction
 task set_fault(input [7:0] code);begin
`ifdef WC_DEBUG_CTRL
  $display("SETFAULT code=%h state=%0d nfetch=%0d hash=%h hh=%h",code,state,nfetch_index,hash,header[255:224]);
`endif
  fault<=1;fault_latched<=1;error_code<=code;end endtask
 task mark_done(input [6:0] n);begin nstate[n]<=N_DONE;done_mask[n]<=1;last_node<={25'd0,n};end endtask

 assign seq_valid=(state==DISPATCH)&&(nd[target][63:32]==T_SEQ)&&!fault_latched;
 assign mat_valid=(state==DISPATCH)&&(nd[target][63:32]==T_MAT)&&!fault_latched;
 assign vec_valid=(state==DISPATCH)&&(nd[target][63:32]==T_VEC)&&!fault_latched;
 assign lay_valid=(state==DISPATCH)&&(nd[target][63:32]==T_LAY)&&!fault_latched;
 assign seq_base=nd[target][255:224];assign seq_count=nd[target][287:256];
 assign mat_base=nd[target][255:224];assign mat_count=nd[target][287:256];
 assign vec_descriptor=payload_buf[511:0];assign lay_descriptor=payload_buf;
 integer i;reg found;reg [31:0] cand;
 wire [2:0] nsucc=(e_active[0]&&seq_done&&!seq_fault)+(e_active[1]&&mat_done&&!mat_fault)+
  (e_active[2]&&vec_done&&!vec_fault)+(e_active[3]&&lay_done&&!lay_fault);
 always @(posedge clk)begin
  if(!rst_n)begin
   state<=IDLE;busy<=0;done<=0;fault<=0;error_code<=0;completed<=0;node_count<=0;
   rejected_starts<=0;last_node<=0;done_mask<=0;cycles<=0;fetch_cycles<=0;operator_cycles<=0;
   drain_cycles<=0;drain_timeout<=0;irq<=0;header<=0;nfetch_index<=0;
   gen_latched<=0;node_buf<=0;payload_buf<=0;payload_addr<=0;payload_beats<=0;payload_node<=0;
   payload_type<=0;hash<=HASH_SEED;target<=0;hgot<=0;ngot<=0;pgot<=0;hbad<=0;nbad<=0;pbad<=0;
   fault_latched<=0;drain_wait<=0;e_active<=0;

   for(i=0;i<MAX_NODES;i=i+1)begin nstate[i]<=0;nd[i]<=0;end
   for(i=0;i<4;i=i+1)e_node[i]<=0;
  end else begin
   done<=0;
   if(start&&busy)rejected_starts<=rejected_starts+1;
   if(busy)cycles<=cycles+1;
   if(state==HFETCH||state==NFETCH||state==PFETCH)fetch_cycles<=fetch_cycles+1;
   if(|e_active)operator_cycles<=operator_cycles+1;
   // Engine completion is independent of the fetch FSM.
   if(e_active[0]&&seq_done)begin
    e_active[0]<=0;mark_done(e_node[0]);
    if(seq_fault)set_fault(seq_error==0?8'h05:seq_error);
   end
   if(e_active[1]&&mat_done)begin
    e_active[1]<=0;mark_done(e_node[1]);
    if(mat_fault)set_fault(mat_error==0?8'h05:mat_error);
   end
   if(e_active[2]&&vec_done)begin
    e_active[2]<=0;mark_done(e_node[2]);
    if(vec_fault)set_fault(vec_error==0?8'h05:vec_error);
   end
   if(e_active[3]&&lay_done)begin
    e_active[3]<=0;mark_done(e_node[3]);
    if(lay_fault)set_fault(lay_error==0?8'h05:lay_error);
   end
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
     for(i=0;i<MAX_NODES;i=i+1)begin nstate[i]<=0;nd[i]<=0;end
     for(i=0;i<4;i=i+1)e_active[i]<=0;
     if(plan_base[5:0]!=0||plan_base<PARAM_BASE||param_end>PARAM_LIMIT||
        param_end<PARAM_BASE+32'd64||plan_base>(param_end-32'd64)||!parameter_ready)begin
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
        header[191:160]!=32'd64+({32'd0,header[95:64]}<<6)||
        header[511:256]!=0||
        (header[223:192]!=0&&header[223:192]!=generation))begin
       set_fault(8'h04);state<=FINISH;
      end else begin
       node_count<=header[95:64];hash<=hash_header(header);nfetch_index<=0;ngot<=0;nbad<=0;
       state<=NREQ;
      end
     end
    end
    NREQ:if(fetch_req_ready)begin ngot<=0;nbad<=0;state<=NFETCH;end
    NFETCH:begin
     if(fetch_read_valid)begin
      if(fetch_read_index!=ngot||ngot>=4)nbad<=1;
      else node_buf[ngot*128+:128]<=fetch_read_data;
      ngot<=ngot+1;
     end
     if(fetch_done)begin
      if(fetch_error||nbad||ngot!=4)begin set_fault(8'h03);state<=FINISH;end
      else if(node_buf[31:0]!=MAGIC_N||node_buf[63:32]<T_MAT||node_buf[63:32]>T_SEQ||
          node_buf[95:64]!=nfetch_index||node_buf[511:480]!=0||
          node_buf[479:448]!=0||node_buf[415:384]!=0||node_buf[383:288]!=0||
          ((node_buf[127:96]|node_buf[159:128]|node_buf[191:160]|node_buf[223:192])&
            ~dep_prefix(nfetch_index))!=0)begin
       set_fault(8'h04);state<=FINISH;
      end else if(node_buf[63:32]==T_SEQ)begin
       if(node_buf[255:224]<PARAM_BASE||node_buf[255:224]>=param_end||
          node_buf[287:256]==0||
          ({32'd0,node_buf[255:224]}+({32'd0,node_buf[287:256]}<<6))>{32'd0,param_end})begin
        set_fault(8'h07);state<=FINISH;
       end else begin
        nd[nfetch_index]<=node_buf;nstate[nfetch_index]<=N_PENDING;
        hash<=hash_node(hash,node_buf);
        if(nfetch_index+1==header[95:64])begin
         if(hash_node(hash,node_buf)!=header[255:224])begin set_fault(8'h04);state<=FINISH;end
         else state<=SCAN;
        end else begin nfetch_index<=nfetch_index+1;state<=NREQ;end
       end
      end else if(node_buf[63:32]==T_MAT)begin
       if(node_buf[255:224]<ARENA_BASE||node_buf[255:224]>=ARENA_LIMIT||
          node_buf[287:256]==0)begin
        set_fault(8'h07);state<=FINISH;
       end else begin
        nd[nfetch_index]<=node_buf;nstate[nfetch_index]<=N_PENDING;
        hash<=hash_node(hash,node_buf);
        if(nfetch_index+1==header[95:64])begin
         if(hash_node(hash,node_buf)!=header[255:224])begin set_fault(8'h04);state<=FINISH;end
         else state<=SCAN;
        end else begin nfetch_index<=nfetch_index+1;state<=NREQ;end
       end
      end else begin
       if(node_buf[255:224]<PARAM_BASE||node_buf[255:224]>=param_end||
          ({32'd0,node_buf[255:224]}+((node_buf[63:32]==T_LAY)?64'd128:64'd64))>{32'd0,param_end})begin
        set_fault(8'h07);state<=FINISH;
       end else begin
        nd[nfetch_index]<=node_buf;nstate[nfetch_index]<=N_PENDING;
        hash<=hash_node(hash,node_buf);
        if(nfetch_index+1==header[95:64])begin
         if(hash_node(hash,node_buf)!=header[255:224])begin set_fault(8'h04);state<=FINISH;end
         else state<=SCAN;
        end else begin nfetch_index<=nfetch_index+1;state<=NREQ;end
       end
      end
     end
    end
    SCAN:begin
     if(fault_latched)begin
      if(!(|e_active))state<=FINISH;
     end else if(completed==node_count)state<=FINISH;
     else if(!parameter_ready||generation!=gen_latched)begin
      set_fault(8'h02);
     end else begin
      found=0;cand=0;
      for(i=0;i<MAX_NODES;i=i+1)begin
       if(!found&&i<node_count&&nstate[i]==N_PENDING&&
          ((nd[i][127:96]&~done_mask)==0)&&
          ((nd[i][159:128]&~done_mask)==0)&&
          ((nd[i][191:160]&~done_mask)==0)&&
          ((nd[i][223:192]&~done_mask)==0))begin
        if(nd[i][63:32]==T_SEQ)begin
         if(!e_active[0]&&direct_idle)begin found=1;cand=i;end
        end else if(nd[i][63:32]==T_MAT)begin
         if(!e_active[1])begin found=1;cand=i;end
        end else if(nd[i][63:32]==T_VEC)begin
         if(!e_active[2])begin found=1;cand=i;end
        end else begin
         if(!e_active[3])begin found=1;cand=i;end
        end
       end
      end
      if(found)begin
       target<=cand;
       if(nd[cand][63:32]==T_VEC||nd[cand][63:32]==T_LAY)begin
        nstate[cand]<=N_PAYLOAD;payload_node<=cand[6:0];
        payload_type<=nd[cand][34:32];payload_addr<=nd[cand][255:224];
        payload_beats<=(nd[cand][63:32]==T_LAY)?8'd8:8'd4;pgot<=0;pbad<=0;state<=PREQ;
       end else state<=DISPATCH;
      end
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
      else if((payload_type==T_VEC&&!vec_ok(payload_buf[511:0],param_end))||
              (payload_type==T_LAY&&!lay_ok(payload_buf,param_end)))begin
       set_fault(8'h07);state<=FINISH;
      end else state<=DISPATCH;
     end
    end
    DISPATCH:begin
     if(fault_latched)state<=SCAN;
     else if(nd[target][63:32]==T_SEQ)begin
      if(seq_ready)begin
       e_active[0]<=1;e_node[0]<=target[6:0];
       nstate[target]<=N_DISPATCHED;last_node<=target;state<=SCAN;
      end
     end else if(nd[target][63:32]==T_MAT)begin
      if(mat_ready)begin
       e_active[1]<=1;e_node[1]<=target[6:0];
       nstate[target]<=N_DISPATCHED;last_node<=target;state<=SCAN;
      end
     end else if(nd[target][63:32]==T_VEC)begin
      if(vec_ready)begin
       e_active[2]<=1;e_node[2]<=target[6:0];
       nstate[target]<=N_DISPATCHED;last_node<=target;state<=SCAN;
      end
     end else begin
      if(lay_ready)begin
       e_active[3]<=1;e_node[3]<=target[6:0];
       nstate[target]<=N_DISPATCHED;last_node<=target;state<=SCAN;
      end
     end
    end
    FINISH:begin busy<=0;done<=1;irq<=1;state<=IDLE;end
    default:begin set_fault(8'hff);state<=FINISH;end
   endcase
  end
 end
endmodule
