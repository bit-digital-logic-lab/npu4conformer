// 中文说明：Model A 第 1 层第 1 个 head 的完整片上推理。
// 输入流为原始 FP32 位模式。量化、偏置、相对位置、Softmax、反量化和 FP32 打包均在 FPGA。
// 使用 HLS 生成 RTL，无处理器、无主机中间运算。权重按列流入，满足片上容量限制。
#include <ap_int.h>
#include <hls_stream.h>
#include "tables.h"
typedef ap_int<64> fix;
typedef ap_uint<64> ufix;
typedef ap_int<16> q16;
typedef ap_uint<32> word;
static const int MT=8, D=512, H=64, MP=15;

static ufix mag(fix a) {
#pragma HLS INLINE
    return a<0 ? ufix(-a) : ufix(a);
}
static fix shr(fix a,int s) {
#pragma HLS INLINE off
    if(s<=0) return a<<(-s);
    if(s>=64) return 0;
    ufix v=mag(a), b=v>>s, mask=(ufix(1)<<s)-1;
    ufix tail=v&mask, half=ufix(1)<<(s-1);
    if(tail>half || (tail==half && b[0])) ++b;
    return a<0 ? fix(-fix(b)) : fix(b);
}
static int shift_for(ufix m) {
#pragma HLS INLINE off
    int top=0;
    for(int b=0;b<63;b++) if(m[b])top=b;
    int s=top>14 ? top-14 : 0;
    if(shr(fix(m),s)>32767)++s;
    return s;
}
static fix from_float(word w, int limit, unsigned &errors) {
#pragma HLS INLINE off
    int e=int(w.range(30,23));
    if(e==255) {++errors;return 0;}
    if(e==0)return 0;
    // Q20 内部工作格式；所有常规矩阵操作数随后动态量化为 INT16。
    ufix mant=(ufix(1)<<23)|ufix(w.range(22,0));
    int s=e-130;
    fix a;
    if(s>32) {++errors;return 0;}
    if(s>=0)a=fix(mant<<s);
    else a=shr(fix(mant),-s);
    if(a>(fix(limit)<<20)) {++errors;a=fix(limit)<<20;}
    return w[31] ? fix(-a) : a;
}
static word to_float(fix a,int fractional=20) {
#pragma HLS INLINE off
    if(a==0)return 0;
    ufix v=mag(a);int top=0;
    for(int b=0;b<63;b++)if(v[b])top=b;
    ufix m;
    if(top>23)m=ufix(shr(fix(v),top-23)); else m=v<<(23-top);
    int e=top-fractional+127;
    if(m[24]) {m>>=1;++e;}
    word result=0;result[31]=(a<0);result.range(30,23)=e;
    result.range(22,0)=m.range(22,0);
    return result;
}
static ap_uint<64> div_round(ap_uint<64> num,ap_uint<64> den) {
#pragma HLS INLINE off
    if(den==0)return 0;
    ap_uint<64> rem=0,q=0;
    // 逐位恢复除法，明确复用一个减法器，避免组合式大除法器。
    for(int i=63;i>=0;i--) {
#pragma HLS PIPELINE II=1
        rem=(rem<<1)|ap_uint<64>(num[i]);
        if(rem>=den){rem-=den;q[i]=1;}
    }
    ap_uint<65> twice=ap_uint<65>(rem)<<1;
    if(twice>den || (twice==den && q[0]))++q;
    return q;
}
static word exponential(ufix delta) {
#pragma HLS INLINE off
    if(delta>=(ufix(16)<<20))return 0;
    int index=int(delta>>12);
    ap_uint<12> fraction=delta.range(11,0);
    word hi=EXP_LUT[index],lo=EXP_LUT[index+1];
    ap_uint<44> correction=ap_uint<44>(hi-lo)*fraction;
    return hi-word((correction+2048)>>12);
}

void conformer_head(hls::stream<word> &in_words,hls::stream<word> &out_words) {
#pragma HLS INTERFACE ap_fifo port=in_words
#pragma HLS INTERFACE ap_fifo port=out_words
#pragma HLS INTERFACE ap_ctrl_hs port=return
#pragma HLS ALLOCATION operation instances=mul limit=3
#pragma HLS ALLOCATION function instances=shr limit=1
#pragma HLS ALLOCATION function instances=from_float limit=1
#pragma HLS ALLOCATION function instances=to_float limit=1
    // 按行或按 head 存储；没有装下整套权重的需求。
    q16 x[MT][D],qu[MT][H],qv[MT][H],k[MT][H],v[MT][H],p[MP][H],c[MT][H];
#pragma HLS BIND_STORAGE variable=x type=ram_2p impl=bram
#pragma HLS BIND_STORAGE variable=qu type=ram_2p impl=bram
#pragma HLS BIND_STORAGE variable=qv type=ram_2p impl=bram
#pragma HLS BIND_STORAGE variable=k type=ram_2p impl=bram
#pragma HLS BIND_STORAGE variable=v type=ram_2p impl=bram
#pragma HLS BIND_STORAGE variable=p type=ram_2p impl=bram
#pragma HLS BIND_STORAGE variable=c type=ram_2p impl=bram
    fix tmp[D],work[MP][H],bu[H],bv[H];
#pragma HLS BIND_STORAGE variable=tmp type=ram_2p impl=bram
#pragma HLS BIND_STORAGE variable=work type=ram_2p impl=bram
#pragma HLS BIND_STORAGE variable=bu type=ram_2p impl=bram
#pragma HLS BIND_STORAGE variable=bv type=ram_2p impl=bram
    q16 wq[D];
#pragma HLS BIND_STORAGE variable=wq type=ram_2p impl=bram
    int sx[MT],su[MT],sqv[MT],sk[MT],sv[MT],sp[MP],sc[MT];
    ap_uint<8> masks[MT];
    fix scores[MT][MT];
    q16 probq[MT][MT];
    word result_context[MT][H],result_output[MT][D],result_biased[MT][D],result_prob[MT][MT];
#pragma HLS BIND_STORAGE variable=result_context type=ram_2p impl=bram
#pragma HLS BIND_STORAGE variable=result_output type=ram_2p impl=bram
#pragma HLS BIND_STORAGE variable=result_biased type=ram_2p impl=bram
    unsigned errors=0;
    word magic=in_words.read();int t=int(in_words.read());
    if(magic!=0x48454144 || t<1 || t>MT){
        out_words.write(0x46504741);out_words.write(1);out_words.write(0);return;
    }
    for(int i=0;i<MT;i++)masks[i]=in_words.read();
    // 原始输入 FP32 -> Q20 -> 逐 token INT16，全在片上处理。
    for(int r=0;r<t;r++) {
        ufix maximum=0;
        for(int d=0;d<D;d++){
            fix value=from_float(in_words.read(),64,errors);tmp[d]=value;
            if(mag(value)>maximum)maximum=mag(value);
        }
        sx[r]=shift_for(maximum);
        for(int d=0;d<D;d++)x[r][d]=q16(shr(tmp[d],sx[r]));
    }
    // 阶段0..3为 Q/K/V/P；阶段4先执行注意力，再接收输出投影权重。
    for(int stage=0;stage<5;stage++) {
        if(stage==4) {
            // 相对位置索引直接选 P[T-1-i+j]，等价于原始 rel_shift。
            for(int i=0;i<t;i++)for(int j=0;j<t;j++) {
                fix ac=0,bd=0;int rp=t-1-i+j;
                for(int d=0;d<H;d++) {
#pragma HLS PIPELINE II=2
                    ap_int<32> a=qu[i][d]*k[j][d];
                    ap_int<32> b=qv[i][d]*p[rp][d];
                    ac+=fix(a);bd+=fix(b);
                }
                // 两项都包含 1/sqrt(64)=1/8，保持 Q20 分数。
                scores[i][j]=shr(ac,23-su[i]-sk[j])+shr(bd,23-sqv[i]-sp[rp]);
            }
            // 稳定 Softmax：屏蔽 -> 减最大值 -> 指数表插值 -> 真正归一化除法。
            for(int i=0;i<t;i++) {
                fix maximum=-(fix(1)<<62);
                for(int j=0;j<t;j++)if(masks[i][j] && scores[i][j]>maximum)maximum=scores[i][j];
                word ex[MT];ufix sum=0;
                for(int j=0;j<t;j++){
                    ex[j]=masks[i][j] ? exponential(ufix(maximum)-ufix(scores[i][j])) : word(0);
                    sum+=ex[j];
                }
                for(int j=0;j<t;j++){
                    word q30=word(div_round(ufix(ex[j])<<30,sum));
                    fix a=shr(fix(q30),15);
                    if(a>32767)a=32767;
                    probq[i][j]=q16(a);
                    result_prob[i][j]=to_float(fix(q30),30);
                }
            }
            // P 为 Q15 INT16，V 是带逐 token shift 的 INT16。
            for(int i=0;i<t;i++){
                ufix maximum=0;
                for(int d=0;d<H;d++){
                    fix acc=0;
                    for(int j=0;j<t;j++){
                        ap_int<32> prod=probq[i][j]*v[j][d];
                        acc+=shr(fix(prod),15-sv[j]);
                    }
                    work[i][d]=acc;result_context[i][d]=to_float(acc);
                    if(mag(acc)>maximum)maximum=mag(acc);
                }
                sc[i]=shift_for(maximum);
                for(int d=0;d<H;d++)c[i][d]=q16(shr(work[i][d],sc[i]));
            }
        }
        int cols=stage==4?D:H, inner=stage==4?H:D, rows=stage==3?2*t-1:t;
        for(int col=0;col<cols;col++){
            // 每列权重 FP32 流入；FPGA 自行求最大值并量化，无主机 scale。
            ufix maximum=0;
            for(int d=0;d<inner;d++){
                fix value=from_float(in_words.read(),16,errors);tmp[d]=value;
                if(mag(value)>maximum)maximum=mag(value);
            }
            fix bias=from_float(in_words.read(),4096,errors);
            if(stage==0) {
                bu[col]=from_float(in_words.read(),4096,errors);
                bv[col]=from_float(in_words.read(),4096,errors);
            }
            int sw=shift_for(maximum);
            for(int d=0;d<inner;d++)wq[d]=q16(shr(tmp[d],sw));
            for(int r=0;r<rows;r++){
                fix acc=0;
                for(int d=0;d<inner;d++){
#pragma HLS PIPELINE II=2
                    q16 a;
                    if(stage<3)a=x[r][d];
                    else if(stage==3)a=POS_LUT[(MT-t+r)*D+d];
                    else a=c[r][d];
                    ap_int<32> prod=a*wq[d];acc+=fix(prod);
                }
                int sa=stage<3?sx[r]:(stage==3?6:sc[r]);
                fix value=shr(acc,20-sa-sw);
                if(stage<4)work[r][col]=value+bias;
                else {
                    // 同时返回单头贡献和加一次共享 bias 的值，均已经在片上转换为 FP32。
                    result_output[r][col]=to_float(value);
                    result_biased[r][col]=to_float(value+bias);
                }
            }
        }
        // 投影输出重定标到 INT16；Q+u 与 Q+v 独立定标。
        if(stage<4)for(int r=0;r<rows;r++){
            ufix maxa=0,maxb=0;
            for(int d=0;d<H;d++){
                fix a=work[r][d]+(stage==0?bu[d]:fix(0));
                fix b=work[r][d]+(stage==0?bv[d]:fix(0));
                if(mag(a)>maxa)maxa=mag(a);
                if(mag(b)>maxb)maxb=mag(b);
            }
            int sa=shift_for(maxa),sb=shift_for(maxb);
            if(stage==0){su[r]=sa;sqv[r]=sb;}
            else if(stage==1)sk[r]=sa;
            else if(stage==2)sv[r]=sa;
            else sp[r]=sa;
            for(int d=0;d<H;d++){
                q16 a=q16(shr(work[r][d]+(stage==0?bu[d]:fix(0)),sa));
                q16 b=q16(shr(work[r][d]+(stage==0?bv[d]:fix(0)),sb));
                if(stage==0){qu[r][d]=a;qv[r][d]=b;}
                else if(stage==1)k[r][d]=a;
                else if(stage==2)v[r][d]=a;
                else p[r][d]=a;
            }
        }
    }
    out_words.write(0x46504741);out_words.write(errors);
    out_words.write(t*H+t*D*2+t*t);
    for(int i=0;i<t;i++)for(int d=0;d<H;d++)out_words.write(result_context[i][d]);
    for(int i=0;i<t;i++)for(int d=0;d<D;d++)out_words.write(result_output[i][d]);
    for(int i=0;i<t;i++)for(int d=0;d<D;d++)out_words.write(result_biased[i][d]);
    for(int i=0;i<t;i++)for(int j=0;j<t;j++)out_words.write(result_prob[i][j]);
}
