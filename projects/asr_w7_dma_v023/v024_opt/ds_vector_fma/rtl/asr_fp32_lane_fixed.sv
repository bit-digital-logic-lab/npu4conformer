`timescale 1ns/1ps
// Fixed-latency FP32 lane for the v023 vector engine.
// Binary32 FTZ/RNE, identical function bodies to the frozen asr_fp32_alu.sv.
// Pipeline: S0 latch, S1 prepare/product/quick, S2 finish, S3 output register.
// Latency = 3 clock edges from accept to out_valid (4 sampling edges); II = 1.
// DIV/SQRT/EXP/LOG/FMA are deliberately NOT implemented here.
module asr_fp32_lane_fixed (
 input wire clk,rst_n,
 input wire in_valid,
 output wire in_ready,
 input wire [7:0] op,
 input wire [31:0] a,b,
 input wire [15:0] tag,
 output wire out_valid,
 input wire out_ready,
 output wire [31:0] result,
 output wire [7:0] flags,
 output wire [15:0] tag_out
);
 localparam [7:0] ADD=0,SUB=1,MUL=2,I32_F32=7,F32_I32=8,MAXIMUM=9,
   LT=10,EQ=11,ABS=12,NEG=13,I48_F32=14,F32_I16=15;

 function automatic is_nan(input [31:0] x);is_nan=(&x[30:23])&&(|x[22:0]);endfunction
 function automatic is_inf(input [31:0] x);is_inf=(x[30:0]==31'h7f800000);endfunction
 function automatic is_zero(input [31:0] x);is_zero=(x[30:0]==0);endfunction
 function automatic is_sub(input [31:0] x);is_sub=(x[30:23]==0)&&(|x[22:0]);endfunction
 function automatic [31:0] ftz(input [31:0] x);ftz=(x[30:23]==0)?{x[31],31'b0}:x;endfunction
 function automatic [26:0] jam27(input [26:0] x,input [8:0] n);
  reg sticky;integer i;
  begin
   sticky=0;
   if(n>=9'd27)jam27={26'b0,|x};
   else if(n==0)jam27=x;
   else begin
    for(i=0;i<27;i=i+1)if(i<n)sticky=sticky|x[i];
    jam27=(x>>n)|{26'b0,sticky};
   end
  end
 endfunction
 function automatic [31:0] pack_rne(input sign,input signed [10:0] expn,input [26:0] sig);
  reg [24:0] rounded;reg signed [10:0] e;
  begin
   e=expn;
   rounded={1'b0,sig[26:3]}+(sig[2]&&(sig[1]||sig[0]||sig[3]));
   if(rounded[24])begin rounded=rounded>>1;e=e+11'sd1;end
   if(sig==0||e<=11'sd0)pack_rne={sign,31'b0};
   else if(e>=11'sd255)pack_rne={sign,8'hff,23'b0};
   else pack_rne={sign,e[7:0],rounded[22:0]};
  end
 endfunction
 function automatic [99:0] fp_add_prepare(input [31:0] aa,input [31:0] bb);
  reg [31:0] x,y,swap;reg [26:0] mx,my;reg [8:0] d;
  begin
   x=ftz(aa);y=ftz(bb);
   if(is_nan(x)||is_nan(y))fp_add_prepare={1'b1,32'h7fc00000,67'b0};
   else if(is_inf(x)&&is_inf(y)&&x[31]!=y[31])fp_add_prepare={1'b1,32'h7fc00000,67'b0};
   else if(is_inf(x))fp_add_prepare={1'b1,x,67'b0};
   else if(is_inf(y))fp_add_prepare={1'b1,y,67'b0};
   else if(is_zero(x)&&is_zero(y))fp_add_prepare={1'b1,(x[31]&y[31]),31'b0,67'b0};
   else if(is_zero(x))fp_add_prepare={1'b1,y,67'b0};
   else if(is_zero(y))fp_add_prepare={1'b1,x,67'b0};
   else begin
    if(x[30:0]<y[30:0])begin swap=x;x=y;y=swap;end
    d={1'b0,x[30:23]}-{1'b0,y[30:23]};
    mx={1'b1,x[22:0],3'b0};my=jam27({1'b1,y[22:0],3'b0},d);
    fp_add_prepare={1'b0,32'b0,x[31],(x[31]==y[31]),3'b0,x[30:23],mx,my};
   end
  end
 endfunction
 function automatic [31:0] fp_add_finish(input [99:0] prepared);
  reg [26:0] mx,my,m;reg [27:0] wide;reg signed [10:0] e;reg [4:0] shift_n;
  begin
   mx=prepared[53:27];my=prepared[26:0];e=$signed(prepared[64:54]);
   if(prepared[99])fp_add_finish=prepared[98:67];
   else begin
    if(prepared[65])begin
     wide={1'b0,mx}+{1'b0,my};
     if(wide[27])begin m=wide[27:1];m[0]=m[0]|wide[0];e=e+11'sd1;end
     else m=wide[26:0];
    end else begin
     m=mx-my;shift_n=0;
     if(m[26:11]==0)begin m=m<<16;shift_n[4]=1;end
     if(m[26:19]==0)begin m=m<<8;shift_n[3]=1;end
     if(m[26:23]==0)begin m=m<<4;shift_n[2]=1;end
     if(m[26:25]==0)begin m=m<<2;shift_n[1]=1;end
     if(!m[26])begin m=m<<1;shift_n[0]=1;end
     e=e-$signed({6'b0,shift_n});
    end
    if(m==0)fp_add_finish=0;
    else fp_add_finish=pack_rne(prepared[66],e,m);
   end
  end
 endfunction
 function automatic [31:0] fp_mul(input [31:0] aa,input [31:0] bb);
  reg [31:0] x,y;reg [47:0] p;reg [26:0] m;reg signed [10:0] e;
  begin
   x=ftz(aa);y=ftz(bb);
   if(is_nan(x)||is_nan(y)||(is_inf(x)&&is_zero(y))||(is_inf(y)&&is_zero(x)))fp_mul=32'h7fc00000;
   else if(is_inf(x)||is_inf(y))fp_mul={x[31]^y[31],8'hff,23'b0};
   else if(is_zero(x)||is_zero(y))fp_mul={x[31]^y[31],31'b0};
   else begin
    p={1'b1,x[22:0]}*{1'b1,y[22:0]};
    e=$signed({3'b0,x[30:23]})+$signed({3'b0,y[30:23]})-11'sd127;
    if(p[47])begin m=p[47:21];m[0]=m[0]|(|p[20:0]);e=e+11'sd1;end
    else begin m=p[46:20];m[0]=m[0]|(|p[19:0]);end
    fp_mul=pack_rne(x[31]^y[31],e,m);
   end
  end
 endfunction
 function automatic [31:0] int48_float(input [47:0] value);
  reg sign;reg [47:0] mag;reg [26:0] sig;reg sticky;reg [5:0] top,sh;integer i;
  begin
   sign=value[47];mag=sign?(~value+48'd1):value;top=0;
   for(i=0;i<48;i=i+1)if(mag[i])top=i[5:0];
   sig=0;sticky=0;sh=top-6'd26;
   if(top>6'd26)begin
    sig=mag>>sh;
    for(i=0;i<48;i=i+1)if(i<sh)sticky=sticky|mag[i];
    sig[0]=sig[0]|sticky;
   end else sig=mag<<(6'd26-top);
   if(mag==0)int48_float=0;
   else int48_float=pack_rne(sign,11'sd127+$signed({5'b0,top}),sig);
  end
 endfunction
 function automatic [31:0] float_int32(input [31:0] x);
  reg signed [10:0] e;reg [5:0] shift;reg [31:0] mag,discard,halfway;reg [23:0] mant;
  begin
   e=$signed({3'b0,x[30:23]})-11'sd127;mant={1'b1,x[22:0]};mag=0;discard=0;halfway=0;shift=0;
   if(is_nan(x))float_int32=0;
   else if(e>=11'sd31)float_int32=x[31]?32'h80000000:32'h7fffffff;
   else if(e< -11'sd1||x[30:23]==0)float_int32=0;
   else begin
    if(e>=11'sd23)mag={8'b0,mant}<<(e-11'sd23);
    else begin
     shift=11'sd23-e;mag={8'b0,mant}>>shift;
     discard={8'b0,mant}-(mag<<shift);halfway=32'd1<<(shift-6'd1);
     if(discard>halfway||(discard==halfway&&mag[0]))mag=mag+32'd1;
    end
    float_int32=x[31]?(~mag[31:0]+32'd1):mag[31:0];
   end
  end
 endfunction
 function automatic less_than(input [31:0] x,input [31:0] y);
  begin
   if(is_nan(x)||is_nan(y)||(is_zero(x)&&is_zero(y)))less_than=0;
   else if(x[31]!=y[31])less_than=x[31];
   else less_than=x[31]?(x[30:0]>y[30:0]):(x[30:0]<y[30:0]);
  end
 endfunction
 function automatic [31:0] quick_result(input [7:0] o,input [31:0] x,input [31:0] y);
  reg [31:0] ti;
  begin
   ti=float_int32(x);
   case(o)
    I32_F32:quick_result=int48_float({{16{x[31]}},x});
    I48_F32:quick_result=int48_float({y[15:0],x});
    F32_I32:quick_result=ti;
    F32_I16:if(is_nan(x))quick_result=0;
      else if($signed(ti)>32767)quick_result=32'h00007fff;
      else if($signed(ti)<-32768)quick_result=32'hffff8000;
      else quick_result=ti;
    MAXIMUM:begin
      if(is_nan(x)&&is_nan(y))quick_result=32'h7fc00000;
      else if(is_nan(x))quick_result=y;
      else if(is_nan(y))quick_result=x;
      else if(is_zero(x)&&is_zero(y))quick_result={x[31]&y[31],31'b0};
      else quick_result=less_than(x,y)?y:x;
    end
    LT:quick_result={31'b0,less_than(x,y)};
    EQ:quick_result={31'b0,(!is_nan(x)&&!is_nan(y)&&((x==y)||(is_zero(x)&&is_zero(y))))};
    ABS:quick_result={1'b0,x[30:0]};
    NEG:quick_result={~x[31],x[30:0]};
    default:quick_result=32'h7fc00000;
   endcase
  end
 endfunction
 function automatic [7:0] quick_flags(input [7:0] o,input [31:0] x,input [31:0] y);
  reg [31:0] ti;
  begin
   ti=float_int32(x);
   case(o)
    F32_I32:quick_flags=(is_nan(x)||x[30:0]>31'h4f000000||x==32'h4f000000)?8'h01:0;
    F32_I16:quick_flags=is_nan(x)?8'h01:0;
    MAXIMUM:quick_flags=(is_nan(x)&&is_nan(y))?8'h01:0;
    LT:quick_flags=(is_nan(x)||is_nan(y))?8'h01:0;
    default:quick_flags=0;
   endcase
  end
 endfunction
 function automatic [7:0] arith_flags(input [7:0] o,input [31:0] x,input [31:0] y,input [31:0] r);
  begin
   if(o==ADD||o==SUB)
    arith_flags=is_nan(r)?8'h01:(is_inf(r)&&!is_inf(x)&&!is_inf(y))?8'h04:
      (is_zero(r)&&!is_zero(x)&&!is_zero(y)&&x[30:0]!=y[30:0])?8'h08:0;
   else
    arith_flags=is_nan(r)?8'h01:(is_inf(r)&&!is_inf(x)&&!is_inf(y))?8'h04:
      (is_zero(r)&&!is_zero(x)&&!is_zero(y))?8'h08:0;
  end
 endfunction

 wire addsub=(op==ADD)||(op==SUB);
 wire mul=(op==MUL);
 wire special=(op==I32_F32)||(op==F32_I32)||(op==MAXIMUM)||(op==LT)||(op==EQ)||
   (op==ABS)||(op==NEG)||(op==I48_F32)||(op==F32_I16);
 wire [7:0] input_flags=(((op!=I32_F32)&&(op!=I48_F32)&&is_sub(a))||
   ((op<=3||op==MAXIMUM||op==LT||op==EQ)&&is_sub(b)))?8'h08:0;
 wire [31:0] a_norm=((op==I32_F32)||(op==I48_F32))?a:ftz(a);
 wire [31:0] b_norm=(op==I48_F32)?b:ftz(b);

 reg s0_valid,s1_valid,s2_valid;
 reg [7:0] s0_op,s1_op,s2_op;
 reg [31:0] s0_a,s0_b,s1_a,s1_b,s2_result;
 reg [7:0] s0_flags,s1_flags,s2_flags;
 reg [15:0] s0_tag,s1_tag,s2_tag;
 reg [99:0] s1_prep;
 reg [31:0] s1_prod,s1_quick;
 reg [7:0] s1_quick_flags;
 reg [31:0] s2_arith;
 reg [7:0] s2_arith_flags;

 wire advance=!out_valid||out_ready;
 assign in_ready=advance;
 assign out_valid=s2_valid;
 assign result=s2_result;
 assign flags=s2_flags;
 assign tag_out=s2_tag;

 always @(posedge clk) begin
  if(!rst_n) begin
   s0_valid<=0;s1_valid<=0;s2_valid<=0;
   s0_op<=0;s1_op<=0;s2_op<=0;s0_a<=0;s0_b<=0;s1_a<=0;s1_b<=0;s2_result<=0;
   s0_flags<=0;s1_flags<=0;s2_flags<=0;s0_tag<=0;s1_tag<=0;s2_tag<=0;
   s1_prep<=0;s1_prod<=0;s1_quick<=0;s1_quick_flags<=0;s2_arith<=0;s2_arith_flags<=0;
  end else if(advance) begin
   s0_valid<=in_valid;
   if(in_valid) begin
    s0_op<=op;s0_a<=a_norm;s0_b<=b_norm;s0_flags<=input_flags;s0_tag<=tag;
   end
   s1_valid<=s0_valid;
   if(s0_valid) begin
    s1_op<=s0_op;s1_a<=s0_a;s1_b<=s0_b;s1_flags<=s0_flags;s1_tag<=s0_tag;
    s1_prep<=fp_add_prepare(s0_a,(s0_op==SUB)?{~s0_b[31],s0_b[30:0]}:s0_b);
    s1_prod<=fp_mul(s0_a,s0_b);
    s1_quick<=quick_result(s0_op,s0_a,s0_b);
    s1_quick_flags<=quick_flags(s0_op,s0_a,s0_b);
   end
   s2_valid<=s1_valid;
   if(s1_valid) begin
    s2_op<=s1_op;s2_tag<=s1_tag;s2_flags<=s1_flags;
    s2_arith<= (s1_op==MUL)?s1_prod:fp_add_finish(s1_prep);
    s2_arith_flags<=arith_flags(s1_op,s1_a,s1_b,
      (s1_op==MUL)?s1_prod:fp_add_finish(s1_prep));
    if((s1_op==ADD)||(s1_op==SUB)||(s1_op==MUL)) begin
     s2_result<= (s1_op==MUL)?s1_prod:fp_add_finish(s1_prep);
     s2_flags<=s1_flags|arith_flags(s1_op,s1_a,s1_b,
       (s1_op==MUL)?s1_prod:fp_add_finish(s1_prep));
    end else begin
     s2_result<=s1_quick;s2_flags<=s1_flags|s1_quick_flags;
    end
   end
  end
 end
endmodule
