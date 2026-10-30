// Shared scalar companion to the W16A16 MAC engine.
// Normal operands: binary32 round-to-nearest/even for +,-,*,/,sqrt and casts.
// Subnormal inputs/outputs are flushed to signed zero (FTZ), not full IEEE754.
// EXP uses range reduction and degree-7 Taylor; LOG uses a reduced atanh series.
// These operations are approximations, not correctly-rounded libm functions.
// flags: [0] invalid, [1] division by zero, [2] overflow,
// [3] FTZ/underflow, [4] approximate transcendental. [7:5] reserved zero.
// Flags describe public inputs/results, not every internal rounding event.
module asr_fp32_alu (
    input wire clk, input wire rst_n,
    input wire in_valid, output wire in_ready,
    input wire [7:0] op, input wire [31:0] a, input wire [31:0] b,
    output reg out_valid, input wire out_ready,
    output reg [31:0] result, output reg [7:0] flags
);
    localparam [7:0] ADD=0,SUB=1,MUL=2,DIV=3,SQRT=4,EXP=5,LOG=6,
        I32_F32=7,F32_I32=8,MAXIMUM=9,LT=10,EQ=11,ABS=12,NEG=13,I48_F32=14,F32_I16=15;
    localparam [5:0] IDLE=0,DISPATCH=1,DIVIDE=2,ROOT=3,
        EX_KMUL=4,EX_KCAST=5,EX_HIMUL=6,EX_HISUB=7,EX_LOMUL=8,EX_LOSUB=9,
        POLY_MUL=10,POLY_ADD=11,EX_SCALE=12,
        LG_MINUS=13,LG_PLUS=14,LG_DIVSTART=15,LG_SQUARE=16,
        LG_PRODUCT=17,LG_DOUBLE=18,LG_EMULLO=19,LG_ADDLO=20,
        LG_EMULHI=21,LG_ADDHI=22;
    reg [5:0] state;
    reg [7:0] op_r, input_flags;
    reg [31:0] a_r,b_r,t0,t1,reduce_r,poly_x,poly_p,exponent_f,log_y;
    // EXP/LOG range-reduction exponents are in [-126,128].
    reg signed [10:0] exponent_i;
    reg [3:0] poly_index;
    reg poly_is_log, div_is_log;
    reg [5:0] count;
    reg [26:0] quotient;
    reg [25:0] remainder, denominator;
    reg signed [11:0] work_exp;
    reg work_sign;
    reg [53:0] radicand;
    reg [55:0] root_rem;
    reg [26:0] root_q;
    reg [31:0] alu_a,alu_b;
    reg [31:0] alu_operand_a,alu_operand_b,alu_sum,alu_product;
    reg [99:0] add_prepared;
    reg [1:0] alu_phase;

    function automatic is_nan(input [31:0] x);
        is_nan=(&x[30:23]) && (|x[22:0]);
    endfunction
    function automatic is_inf(input [31:0] x);
        is_inf=(x[30:0]==31'h7f800000);
    endfunction
    function automatic is_zero(input [31:0] x);
        is_zero=(x[30:0]==0);
    endfunction
    function automatic is_sub(input [31:0] x);
        is_sub=(x[30:23]==0) && (|x[22:0]);
    endfunction
    function automatic [31:0] ftz(input [31:0] x);
        ftz=(x[30:23]==0)?{x[31],31'b0}:x;
    endfunction
    function automatic [26:0] jam27(input [26:0] x,input [8:0] n);
        reg sticky; integer i;
        begin
            sticky=0;
            if(n>=9'd27) jam27={26'b0,|x};
            else if(n==0) jam27=x;
            else begin
                for(i=0;i<27;i=i+1) if(i<n) sticky=sticky|x[i];
                jam27=(x>>n)|{26'b0,sticky};
            end
        end
    endfunction
    function automatic [31:0] pack_rne(input sign,input signed [10:0] expn,input [26:0] sig);
        reg [24:0] rounded; reg signed [10:0] e;
        begin
            e=expn;
            rounded={1'b0,sig[26:3]} + (sig[2] && (sig[1]||sig[0]||sig[3]));
            if(rounded[24]) begin rounded=rounded>>1; e=e+11'sd1; end
            if(sig==0 || e<=11'sd0) pack_rne={sign,31'b0};
            else if(e>=11'sd255) pack_rne={sign,8'hff,23'b0};
            else pack_rne={sign,e[7:0],rounded[22:0]};
        end
    endfunction
    // Registered adder boundary: {bypass, bypass_value, sign, same_sign,
    // signed_exponent[10:0], larger_mantissa[26:0], aligned_mantissa[26:0]}.
    // Sorting, exponent subtraction, barrel alignment and sticky collection
    // precede the register. Actual mantissa arithmetic and rounding follow it.
    function automatic [99:0] fp_add_prepare(input [31:0] aa,input [31:0] bb);
        reg [31:0] x,y,swap;
        reg [26:0] mx,my;
        reg [8:0] d;
        begin
            x=ftz(aa); y=ftz(bb);
            if(is_nan(x)||is_nan(y)) fp_add_prepare={1'b1,32'h7fc00000,67'b0};
            else if(is_inf(x)&&is_inf(y)&&x[31]!=y[31]) fp_add_prepare={1'b1,32'h7fc00000,67'b0};
            else if(is_inf(x)) fp_add_prepare={1'b1,x,67'b0};
            else if(is_inf(y)) fp_add_prepare={1'b1,y,67'b0};
            else if(is_zero(x)&&is_zero(y)) fp_add_prepare={1'b1,(x[31]&y[31]),31'b0,67'b0};
            else if(is_zero(x)) fp_add_prepare={1'b1,y,67'b0};
            else if(is_zero(y)) fp_add_prepare={1'b1,x,67'b0};
            else begin
                if(x[30:0]<y[30:0]) begin swap=x;x=y;y=swap;end
                d={1'b0,x[30:23]}-{1'b0,y[30:23]};
                mx={1'b1,x[22:0],3'b0}; my=jam27({1'b1,y[22:0],3'b0},d);
                fp_add_prepare={1'b0,32'b0,x[31],(x[31]==y[31]),3'b0,x[30:23],mx,my};
            end
        end
    endfunction
    function automatic [31:0] fp_add_finish(input [99:0] prepared);
        reg [26:0] mx,my,m;
        reg [27:0] wide;
        reg signed [10:0] e;
        reg [4:0] shift_n;
        begin
            mx=prepared[53:27];my=prepared[26:0];e=$signed(prepared[64:54]);
            if(prepared[99]) fp_add_finish=prepared[98:67];
            else begin
                if(prepared[65]) begin
                    wide={1'b0,mx}+{1'b0,my};
                    if(wide[27]) begin m=wide[27:1];m[0]=m[0]|wide[0];e=e+11'sd1;end
                    else m=wide[26:0];
                end else begin
                    m=mx-my;
                    // Five-stage leading-zero normalization avoids a 26-deep mux chain.
                    // Collect the shifts then subtract the exponent once, rather
                    // than cascading five conditional integer-width subtractors.
                    shift_n=0;
                    if(m[26:11]==0) begin m=m<<16;shift_n[4]=1;end
                    if(m[26:19]==0) begin m=m<<8;shift_n[3]=1;end
                    if(m[26:23]==0) begin m=m<<4;shift_n[2]=1;end
                    if(m[26:25]==0) begin m=m<<2;shift_n[1]=1;end
                    if(!m[26]) begin m=m<<1;shift_n[0]=1;end
                    e=e-$signed({6'b0,shift_n});
                end
                if(m==0) fp_add_finish=0;
                else fp_add_finish=pack_rne(prepared[66],e,m);
            end
        end
    endfunction
    function automatic [31:0] fp_mul(input [31:0] aa,input [31:0] bb);
        reg [31:0] x,y; reg [47:0] p; reg [26:0] m; reg signed [10:0] e;
        begin
            x=ftz(aa);y=ftz(bb);
            if(is_nan(x)||is_nan(y)||(is_inf(x)&&is_zero(y))||(is_inf(y)&&is_zero(x))) fp_mul=32'h7fc00000;
            else if(is_inf(x)||is_inf(y)) fp_mul={x[31]^y[31],8'hff,23'b0};
            else if(is_zero(x)||is_zero(y)) fp_mul={x[31]^y[31],31'b0};
            else begin
                p={1'b1,x[22:0]}*{1'b1,y[22:0]};
                e=$signed({3'b0,x[30:23]})+$signed({3'b0,y[30:23]})-11'sd127;
                if(p[47]) begin m=p[47:21];m[0]=m[0]|(|p[20:0]);e=e+11'sd1;end
                else begin m=p[46:20];m[0]=m[0]|(|p[19:0]);end
                fp_mul=pack_rne(x[31]^y[31],e,m);
            end
        end
    endfunction
    function automatic [31:0] int48_float(input [47:0] value);
        reg sign;reg [47:0] mag;reg [26:0] sig;reg sticky;
        reg [5:0] top,sh; integer i;
        begin
            sign=value[47]; mag=sign?(~value+48'd1):value;
            top=0;
            for(i=0;i<48;i=i+1) if(mag[i]) top=i[5:0];
            sig=0;sticky=0;sh=top-6'd26;
            if(top>6'd26) begin
                sig=mag>>sh;
                for(i=0;i<48;i=i+1) if(i<sh) sticky=sticky|mag[i];
                sig[0]=sig[0]|sticky;
            end else sig=mag<<(6'd26-top);
            if(mag==0) int48_float=0;
            else int48_float=pack_rne(sign,11'sd127+$signed({5'b0,top}),sig);
        end
    endfunction
    function automatic [31:0] float_int32(input [31:0] x);
        reg signed [10:0] e;
        reg [5:0] shift;reg [31:0] mag,discard,halfway;reg [23:0] mant;
        begin
            e=$signed({3'b0,x[30:23]})-11'sd127;mant={1'b1,x[22:0]};mag=0;discard=0;halfway=0;shift=0;
            if(is_nan(x)) float_int32=0;
            else if(e>=11'sd31) float_int32=x[31]?32'h80000000:32'h7fffffff;
            else if(e< -11'sd1 || x[30:23]==0) float_int32=0;
            else begin
                if(e>=11'sd23) mag={8'b0,mant}<<(e-11'sd23);
                else begin
                    shift=11'sd23-e;mag={8'b0,mant}>>shift;
                    discard={8'b0,mant}-(mag<<shift);halfway=32'd1<<(shift-6'd1);
                    if(discard>halfway || (discard==halfway && mag[0])) mag=mag+32'd1;
                end
                float_int32=x[31]?(~mag[31:0]+32'd1):mag[31:0];
            end
        end
    endfunction
    function automatic less_than(input [31:0] x,input [31:0] y);
        begin
            if(is_nan(x)||is_nan(y)||(is_zero(x)&&is_zero(y))) less_than=0;
            else if(x[31]!=y[31]) less_than=x[31];
            else less_than=x[31]?(x[30:0]>y[30:0]):(x[30:0]<y[30:0]);
        end
    endfunction
    function automatic [31:0] coefficient(input mode,input [3:0] index);
        begin
            if(mode) case(index)
                0:coefficient=32'h3dba2e8c; // 1/11; accumulator starts at 1/13
                1:coefficient=32'h3de38e39;
                2:coefficient=32'h3e124925;
                3:coefficient=32'h3e4ccccd;
                4:coefficient=32'h3eaaaaab;
                default:coefficient=32'h3f800000;
            endcase
            else case(index)
                0:coefficient=32'h3ab60b61; // 1/720; accumulator starts at 1/5040
                1:coefficient=32'h3c088889;
                2:coefficient=32'h3d2aaaab;
                3:coefficient=32'h3e2aaaab;
                4:coefficient=32'h3f000000;
                default:coefficient=32'h3f800000;
            endcase
        end
    endfunction

    // One shared floating adder and one shared multiplier, reused by both polynomials.
    // Each micro-operation takes four real cycles: latch operands; register
    // aligned adder operands (and multiply); add/normalize/round; consume
    // result/status. No timing exceptions are used.
    always @* begin
        alu_a=a_r;alu_b=b_r;
        case(state)
            DISPATCH: if(op_r==SUB) alu_b={~b_r[31],b_r[30:0]};
            EX_KMUL: begin alu_a=a_r;alu_b=32'h3fb8aa3b;end
            EX_HIMUL,LG_EMULHI: begin alu_a=exponent_f;alu_b=32'h3f317200;end
            EX_HISUB: begin alu_a=a_r;alu_b={~t0[31],t0[30:0]};end
            EX_LOMUL,LG_EMULLO: begin alu_a=exponent_f;alu_b=32'h35bfbe8e;end
            EX_LOSUB: begin alu_a=t1;alu_b={~t0[31],t0[30:0]};end
            POLY_MUL: begin alu_a=poly_p;alu_b=poly_x;end
            POLY_ADD: begin alu_a=t0;alu_b=coefficient(poly_is_log,poly_index);end
            LG_MINUS: begin alu_a=reduce_r;alu_b=32'hbf800000;end
            LG_PLUS: begin alu_a=reduce_r;alu_b=32'h3f800000;end
            LG_SQUARE: begin alu_a=log_y;alu_b=log_y;end
            LG_PRODUCT: begin alu_a=poly_p;alu_b=log_y;end
            LG_DOUBLE: begin alu_a=t0;alu_b=t0;end
            LG_ADDLO: begin alu_a=t0;alu_b=t1;end
            LG_ADDHI: begin alu_a=t0;alu_b=t1;end
            default: begin end
        endcase
    end
    wire [31:0] sum_value=alu_sum;
    wire [31:0] product_value=alu_product;
    wire needs_alu=((state==DISPATCH)&&(op_r==ADD||op_r==SUB||op_r==MUL)) ||
        state==EX_KMUL || state==EX_HIMUL || state==EX_HISUB ||
        state==EX_LOMUL || state==EX_LOSUB || state==POLY_MUL || state==POLY_ADD ||
        state==LG_MINUS || state==LG_PLUS || state==LG_SQUARE ||
        state==LG_PRODUCT || state==LG_DOUBLE || state==LG_EMULLO ||
        state==LG_ADDLO || state==LG_EMULHI || state==LG_ADDHI;
    wire [31:0] t0_as_int=float_int32(t0);
    wire [31:0] a_as_int=float_int32(a_r);
    wire [25:0] div_rem_next=(remainder>=denominator)?(remainder-denominator):remainder;
    wire [26:0] div_q_next={quotient[25:0],(remainder>=denominator)};
    wire [55:0] sqrt_rem_shift={root_rem[53:0],radicand[53:52]};
    wire [55:0] sqrt_trial={27'b0,root_q,2'b01};
    wire sqrt_bit=(sqrt_rem_shift>=sqrt_trial);
    wire [55:0] sqrt_rem_next=sqrt_bit?(sqrt_rem_shift-sqrt_trial):sqrt_rem_shift;
    wire [26:0] sqrt_q_next={root_q[25:0],sqrt_bit};
    wire [31:0] div_packed=pack_rne(work_sign,$signed(work_exp),{div_q_next[26:1],div_q_next[0]|(|div_rem_next)});
    wire [31:0] sqrt_packed=pack_rne(1'b0,$signed(work_exp),{sqrt_q_next[26:1],sqrt_q_next[0]|(|sqrt_rem_next)});
    wire [31:0] scaled_exp=pack_rne(1'b0, exponent_i+$signed({3'b0,poly_p[30:23]}), {1'b1,poly_p[22:0],3'b0});
    assign in_ready=(state==IDLE)&&!out_valid;

    task automatic finish(input [31:0] value,input [7:0] status);
        begin result<=value;flags<=status|input_flags;out_valid<=1;state<=IDLE;end
    endtask
    task automatic begin_div(input [31:0] numerator,input [31:0] divisor,input log_mode);
        begin
            denominator<={2'b0,1'b1,divisor[22:0]};quotient<=0;count<=0;
            work_sign<=numerator[31]^divisor[31];div_is_log<=log_mode;
            if({1'b1,numerator[22:0]}<{1'b1,divisor[22:0]}) begin
                remainder<={1'b0,1'b1,numerator[22:0],1'b0};
                work_exp<={4'b0,numerator[30:23]}-{4'b0,divisor[30:23]}+12'd126;
            end else begin
                remainder<={2'b0,1'b1,numerator[22:0]};
                work_exp<={4'b0,numerator[30:23]}-{4'b0,divisor[30:23]}+12'd127;
            end
            state<=DIVIDE;
        end
    endtask
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            state<=IDLE;out_valid<=0;result<=0;flags<=0;input_flags<=0;
            op_r<=0;a_r<=0;b_r<=0;t0<=0;t1<=0;reduce_r<=0;poly_x<=0;poly_p<=0;
            exponent_f<=0;exponent_i<=0;log_y<=0;poly_index<=0;poly_is_log<=0;
            div_is_log<=0;count<=0;quotient<=0;remainder<=0;denominator<=0;
            work_exp<=0;work_sign<=0;radicand<=0;root_rem<=0;root_q<=0;
            alu_operand_a<=0;alu_operand_b<=0;alu_sum<=0;alu_product<=0;alu_phase<=0;
            add_prepared<=0;
        end else begin
            if(out_valid&&out_ready) out_valid<=0;
            if(needs_alu && alu_phase!=3) begin
                if(alu_phase==0) begin
                    alu_operand_a<=alu_a;alu_operand_b<=alu_b;alu_phase<=1;
                end else if(alu_phase==1) begin
                    add_prepared<=fp_add_prepare(alu_operand_a,alu_operand_b);
                    alu_product<=fp_mul(alu_operand_a,alu_operand_b);
                    alu_phase<=2;
                end else begin
                    alu_sum<=fp_add_finish(add_prepared);
                    alu_phase<=3;
                end
            end else begin
            alu_phase<=0;
            case(state)
                IDLE: if(in_valid&&in_ready) begin
                    op_r<=op;state<=DISPATCH;
                    a_r<=((op==I32_F32)||(op==I48_F32))?a:ftz(a);
                    b_r<=(op==I48_F32)?b:ftz(b);
                    input_flags<=(((op!=I32_F32)&&(op!=I48_F32)&&is_sub(a)) ||
                        ((op<=DIV||op==MAXIMUM||op==LT||op==EQ)&&is_sub(b)))?8'h08:0;
                end
                DISPATCH: case(op_r)
                    ADD,SUB: finish(sum_value,is_nan(sum_value)?8'h01:
                        (is_inf(sum_value)&&!is_inf(a_r)&&!is_inf(b_r))?8'h04:
                        (is_zero(sum_value)&&!is_zero(a_r)&&!is_zero(b_r)&&a_r[30:0]!=b_r[30:0])?8'h08:0);
                    MUL: finish(product_value,is_nan(product_value)?8'h01:
                        (is_inf(product_value)&&!is_inf(a_r)&&!is_inf(b_r))?8'h04:
                        (is_zero(product_value)&&!is_zero(a_r)&&!is_zero(b_r))?8'h08:0);
                    DIV: begin
                        if(is_nan(a_r)||is_nan(b_r)||(is_zero(a_r)&&is_zero(b_r))||(is_inf(a_r)&&is_inf(b_r))) finish(32'h7fc00000,8'h01);
                        else if(is_zero(b_r)) finish({a_r[31]^b_r[31],8'hff,23'b0},is_inf(a_r)?0:8'h02);
                        else if(is_inf(a_r)) finish({a_r[31]^b_r[31],8'hff,23'b0},0);
                        else if(is_zero(a_r)||is_inf(b_r)) finish({a_r[31]^b_r[31],31'b0},0);
                        else begin_div(a_r,b_r,0);
                    end
                    SQRT: begin
                        if(is_nan(a_r)||(a_r[31]&&!is_zero(a_r))) finish(32'h7fc00000,8'h01);
                        else if(is_zero(a_r)||is_inf(a_r)) finish(a_r,0);
                        else begin
                            // Odd unbiased exponent iff biased exponent LSB is zero.
                            radicand<=a_r[23]?{2'b01,a_r[22:0],29'b0}:{1'b1,a_r[22:0],30'b0};
                            work_exp<=(($signed({1'b0,a_r[30:23]})-12'sd127)>>>1)+12'sd127;
                            root_q<=0;root_rem<=0;count<=0;state<=ROOT;
                        end
                    end
                    EXP: begin
                        if(is_nan(a_r)) finish(32'h7fc00000,8'h01);
                        else if(is_inf(a_r)) finish(a_r[31]?0:32'h7f800000,0);
                        else if(less_than(32'h42b17218,a_r)) finish(32'h7f800000,8'h14);
                        else if(less_than(a_r,32'hc2aeac50)) finish(0,8'h18);
                        else state<=EX_KMUL;
                    end
                    LOG: begin
                        if(is_nan(a_r)||(a_r[31]&&!is_zero(a_r))) finish(32'h7fc00000,8'h01);
                        else if(is_zero(a_r)) finish(32'hff800000,8'h02);
                        else if(is_inf(a_r)) finish(a_r,0);
                        else begin
                            if(a_r[22:0]>23'h3504f3) begin
                                reduce_r<={1'b0,8'd126,a_r[22:0]};
                                exponent_i<=$signed({3'b0,a_r[30:23]})-11'sd126;
                            end else begin
                                reduce_r<={1'b0,8'd127,a_r[22:0]};
                                exponent_i<=$signed({3'b0,a_r[30:23]})-11'sd127;
                            end
                            state<=LG_MINUS;
                        end
                    end
                    I32_F32: finish(int48_float({{16{a_r[31]}},a_r}),0);
                    I48_F32: finish(int48_float({b_r[15:0],a_r}),0);
                    F32_I32: finish(float_int32(a_r),(is_nan(a_r)||a_r[30:0]>31'h4f000000||a_r==32'h4f000000)?8'h01:0);
                    F32_I16: begin
                        if(is_nan(a_r)) finish(0,8'h01);
                        else if($signed(a_as_int)>32767) finish(32'h00007fff,0);
                        else if($signed(a_as_int)<-32768) finish(32'hffff8000,0);
                        else finish(a_as_int,0);
                    end
                    MAXIMUM: begin
                        if(is_nan(a_r)&&is_nan(b_r)) finish(32'h7fc00000,8'h01);
                        else if(is_nan(a_r)) finish(b_r,0);
                        else if(is_nan(b_r)) finish(a_r,0);
                        else if(is_zero(a_r)&&is_zero(b_r)) finish({a_r[31]&b_r[31],31'b0},0);
                        else finish(less_than(a_r,b_r)?b_r:a_r,0);
                    end
                    LT: finish({31'b0,less_than(a_r,b_r)},(is_nan(a_r)||is_nan(b_r))?8'h01:0);
                    EQ: finish({31'b0,(!is_nan(a_r)&&!is_nan(b_r)&&((a_r==b_r)||(is_zero(a_r)&&is_zero(b_r))))},0);
                    ABS: finish({1'b0,a_r[30:0]},0);
                    NEG: finish({~a_r[31],a_r[30:0]},0);
                    default: finish(32'h7fc00000,8'h01);
                endcase
                DIVIDE: begin
                    quotient<=div_q_next;remainder<=div_rem_next<<1;count<=count+1;
                    if(count==26) begin
                        if(div_is_log) begin log_y<=div_packed;state<=LG_SQUARE;end
                        else finish(div_packed,is_inf(div_packed)?8'h04:is_zero(div_packed)?8'h08:0);
                    end
                end
                ROOT: begin
                    root_q<=sqrt_q_next;root_rem<=sqrt_rem_next;radicand<=radicand<<2;count<=count+1;
                    if(count==26) finish(sqrt_packed,0);
                end
                EX_KMUL: begin t0<=product_value;state<=EX_KCAST;end
                EX_KCAST: begin
                    exponent_i<=$signed(t0_as_int[10:0]);
                    exponent_f<=int48_float({{16{t0_as_int[31]}},t0_as_int});
                    state<=EX_HIMUL;
                end
                EX_HIMUL: begin t0<=product_value;state<=EX_HISUB;end
                EX_HISUB: begin t1<=sum_value;state<=EX_LOMUL;end
                EX_LOMUL: begin t0<=product_value;state<=EX_LOSUB;end
                EX_LOSUB: begin
                    poly_x<=sum_value;poly_p<=32'h39500d01;poly_index<=0;poly_is_log<=0;state<=POLY_MUL;
                end
                POLY_MUL: begin t0<=product_value;state<=POLY_ADD;end
                POLY_ADD: begin
                    poly_p<=sum_value;poly_index<=poly_index+1;
                    if(poly_index==(poly_is_log?5:6)) state<=poly_is_log?LG_PRODUCT:EX_SCALE;
                    else state<=POLY_MUL;
                end
                EX_SCALE: finish(scaled_exp,8'h10|(is_inf(scaled_exp)?8'h04:is_zero(scaled_exp)?8'h08:0));
                LG_MINUS: begin
                    t0<=sum_value;exponent_f<=int48_float({{37{exponent_i[10]}},exponent_i});state<=LG_PLUS;
                end
                LG_PLUS: begin t1<=sum_value;state<=LG_DIVSTART;end
                LG_DIVSTART: begin
                    if(is_zero(t0)) begin log_y<=t0;state<=LG_SQUARE;end
                    else begin_div(t0,t1,1);
                end
                LG_SQUARE: begin
                    poly_x<=product_value;poly_p<=32'h3d9d89d9;poly_index<=0;poly_is_log<=1;state<=POLY_MUL;
                end
                LG_PRODUCT: begin t0<=product_value;state<=LG_DOUBLE;end
                LG_DOUBLE: begin t1<=sum_value;state<=LG_EMULLO;end
                LG_EMULLO: begin t0<=product_value;state<=LG_ADDLO;end
                LG_ADDLO: begin t1<=sum_value;state<=LG_EMULHI;end
                LG_EMULHI: begin t0<=product_value;state<=LG_ADDHI;end
                LG_ADDHI: finish(sum_value,8'h10);
                default: finish(32'h7fc00000,8'h01);
            endcase
            end
        end
    end
endmodule
