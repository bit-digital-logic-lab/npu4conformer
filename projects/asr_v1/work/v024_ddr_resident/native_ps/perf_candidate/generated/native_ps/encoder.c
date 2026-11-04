/* Board-side, single-utterance pyf98 Conformer. All dense, pointwise,
 * subsampling and attention products go through the 2493 PL matrix driver. */
#include <math.h>
#include <setjmp.h>
#include <string.h>
#include "native_ps.h"
#include "native_pl.h"
#include "model_index.h"

enum { C=512, D=64, H=8, FF=2048, FREQ=80, CONV_BATCH=64 };
static struct {
    uintptr_t cursor;
    volatile struct asr_mailbox *box;
    char prefix[32];
    jmp_buf fail;
} task;

/* Temporary arrays have block lifetimes; a failed call aborts this request,
 * preserves PL error registers, and never returns a partial encoder tensor. */
static float *reserve(unsigned elements) {
    uintptr_t start=(task.cursor+63u)&~(uintptr_t)63u;
    uintptr_t end=start+(uintptr_t)elements*sizeof(float);
    if(end<start || end>ASR_SCRATCH_END) longjmp(task.fail,30);
    task.cursor=end;
    return (float *)start;
}
static const asr_tensor_t *lookup(const char *suffix) {
    char name[112];
    size_t a=strlen(task.prefix),b=strlen(suffix);
    if(a+b>=sizeof(name)) longjmp(task.fail,31);
    memcpy(name,task.prefix,a); memcpy(name+a,suffix,b+1);
    const asr_tensor_t *tensor=asr_lookup(name);
    if(!tensor) longjmp(task.fail,31);
    return tensor;
}
static const float *f32(const char *key,unsigned count) {
    const asr_tensor_t *t=lookup(key);
    if(t->kind!=ASR_TENSOR_F32 || t->elements!=count) longjmp(task.fail,32);
    return (const float *)(uintptr_t)t->phys_addr;
}
static void check_pl(int error) {
    if(error) longjmp(task.fail,100+(error<0?-error:error));
    ++task.box->pl_calls;
}
static void linear(const char *key,const float *x,unsigned m,unsigned k,unsigned n,float *y) {
    const asr_tensor_t *t=lookup(key);
    if(t->kind!=ASR_TENSOR_W7 || t->k!=k || t->n!=n) longjmp(task.fail,33);
    check_pl(native_pl_linear(x,m,k,n,(const uint8_t *)(uintptr_t)t->phys_addr,
             (const float *)(uintptr_t)t->scales_phys,(const float *)(uintptr_t)t->bias_phys,y));
}
static void add(float *x,const float *delta,unsigned count,float scale) {
    for(unsigned i=0;i<count;++i) x[i]+=scale*delta[i];
}
static void conv2d(const char *key,const float *x,unsigned it,unsigned freq,unsigned in_ch,
                   float *y,int frequency_last) {
    unsigned ot=(it-1)/2, of=(freq-1)/2, k=9*in_ch, locations=ot*of;
    uintptr_t mark=task.cursor;
    float *patch=reserve(CONV_BATCH*k), *rows=reserve(CONV_BATCH*C);
    for(unsigned b=0;b<locations;b+=CONV_BATCH) {
        unsigned m=locations-b<CONV_BATCH ? locations-b : CONV_BATCH;
        for(unsigned r=0;r<m;++r) {
            unsigned t=(b+r)/of, f=(b+r)%of;
            for(unsigned c=0;c<in_ch;++c)
                for(unsigned dt=0;dt<3;++dt)
                    for(unsigned df=0;df<3;++df)
                        patch[r*k+c*9+dt*3+df]=x[((2*t+dt)*freq+2*f+df)*in_ch+c];
        }
        linear(key,patch,m,k,C,rows);
        for(unsigned r=0;r<m;++r) {
            unsigned pos=b+r,t=pos/of,f=pos%of;
            for(unsigned c=0;c<C;++c) {
                unsigned index=frequency_last ? (t*C+c)*of+f : pos*C+c;
                float value=rows[r*C+c];
                y[index]=value<0.f?0.f:value;
            }
        }
    }
    task.cursor=mark;
}
static void subsample(const float *input,unsigned frames,float *hidden) {
    unsigned t1=(frames-1)/2, t=(t1-1)/2;
    uintptr_t mark=task.cursor;
    float *normalized=reserve(frames*FREQ), *conv1=reserve(t1*39*C), *flat=reserve(t*19*C);
    const float *mean=f32("normalize.mean",FREQ), *sd=f32("normalize.std",FREQ);
    for(unsigned r=0;r<frames;++r)
        for(unsigned c=0;c<FREQ;++c) normalized[r*FREQ+c]=(input[r*FREQ+c]-mean[c])/sd[c];
    task.box->stage=1;
    conv2d("encoder.embed.conv.0.weight",normalized,frames,FREQ,1,conv1,0);
    task.box->stage=2;
    conv2d("encoder.embed.conv.2.weight",conv1,t1,39,C,flat,1);
    task.box->stage=3;
    linear("encoder.embed.out.0.weight",flat,t,19*C,C,hidden);
    for(unsigned i=0;i<t*C;++i) hidden[i]*=sqrtf((float)C);
    task.cursor=mark;
}
static void position_embedding(float *pos,unsigned frames) {
    for(unsigned d=0;d<C;d+=2) {
        float rate=expf(-(float)d*logf(10000.f)/(float)C);
        for(unsigned j=0;j<2*frames-1;++j) {
            float angle=((float)(frames-1)-(float)j)*rate;
            pos[j*C+d]=sinf(angle); pos[j*C+d+1]=cosf(angle);
        }
    }
}
static void ff(float *x,unsigned t,int macaron) {
    uintptr_t mark=task.cursor;
    float *norm=reserve(t*C), *inner=reserve(t*FF), *delta=reserve(t*C);
    const float *gain=f32(macaron?"norm_ff_macaron.weight":"norm_ff.weight",C);
    const float *bias=f32(macaron?"norm_ff_macaron.bias":"norm_ff.bias",C);
    ps_layernorm(x,norm,t,C,gain,bias);
    linear(macaron?"feed_forward_macaron.w_1.weight":"feed_forward.w_1.weight",norm,t,C,FF,inner);
    ps_swish(inner,t*FF);
    linear(macaron?"feed_forward_macaron.w_2.weight":"feed_forward.w_2.weight",inner,t,FF,C,delta);
    add(x,delta,t*C,0.5f);
    task.cursor=mark;
}
static void attention(float *x,const float *pos,unsigned t) {
    unsigned p=2*t-1;
    uintptr_t mark=task.cursor;
    float *norm=reserve(t*C), *q=reserve(t*C), *k=reserve(t*C), *v=reserve(t*C);
    float *projected=reserve(p*C), *joined=reserve(t*C);
    ps_layernorm(x,norm,t,C,f32("norm_mha.weight",C),f32("norm_mha.bias",C));
    linear("self_attn.linear_q.weight",norm,t,C,C,q);
    linear("self_attn.linear_k.weight",norm,t,C,C,k);
    linear("self_attn.linear_v.weight",norm,t,C,C,v);
    linear("self_attn.linear_pos.weight",pos,p,C,C,projected);
    const float *u=f32("self_attn.pos_bias_u",C), *b=f32("self_attn.pos_bias_v",C);
    float *head=reserve(t*D), *rhs=reserve(D*p), *ac=reserve(t*t), *bd=reserve(t*p);
    for(unsigned h=0;h<H;++h) {
        unsigned off=h*D;
        for(unsigned r=0;r<t;++r)
            for(unsigned d=0;d<D;++d) {head[r*D+d]=q[r*C+off+d]+u[off+d]; rhs[d*t+r]=k[r*C+off+d];}
        check_pl(native_pl_dynamic(head,t,D,t,rhs,ac));
        for(unsigned r=0;r<t;++r)
            for(unsigned d=0;d<D;++d) head[r*D+d]=q[r*C+off+d]+b[off+d];
        for(unsigned j=0;j<p;++j)
            for(unsigned d=0;d<D;++d) rhs[d*p+j]=projected[j*C+off+d];
        check_pl(native_pl_dynamic(head,t,D,p,rhs,bd));
        for(unsigned i=0;i<t;++i)
            for(unsigned j=0;j<t;++j) ac[i*t+j]=(ac[i*t+j]+bd[i*p+(t-1-i)+j])*0.125f;
        ps_softmax(ac,t,t);
        for(unsigned j=0;j<t;++j) memcpy(rhs+j*D,v+j*C+off,D*sizeof(float));
        check_pl(native_pl_dynamic(ac,t,t,D,rhs,head));
        for(unsigned j=0;j<t;++j) memcpy(joined+j*C+off,head+j*D,D*sizeof(float));
    }
    linear("self_attn.linear_out.weight",joined,t,C,C,norm);
    add(x,norm,t*C,1.f);
    task.cursor=mark;
}
static void convolution(float *x,unsigned t) {
    uintptr_t mark=task.cursor;
    float *norm=reserve(t*C),*pair=reserve(t*C*2),*gate=reserve(t*C);
    ps_layernorm(x,norm,t,C,f32("norm_conv.weight",C),f32("norm_conv.bias",C));
    linear("conv_module.pointwise_conv1.weight",norm,t,C,2*C,pair);
    ps_glu(pair,gate,t,C);
    ps_depthwise(gate,norm,t,C,f32("conv_module.depthwise_conv.weight",31*C),
                 f32("conv_module.depthwise_conv.bias",C),31);
    const float *mean=f32("conv_module.norm.running_mean",C),*var=f32("conv_module.norm.running_var",C);
    const float *gain=f32("conv_module.norm.weight",C),*bias=f32("conv_module.norm.bias",C);
    float *factor=reserve(C);
    for(unsigned c=0;c<C;++c) factor[c]=gain[c]/sqrtf(var[c]+1e-5f);
    for(unsigned r=0;r<t;++r)
        for(unsigned c=0;c<C;++c) norm[r*C+c]=(norm[r*C+c]-mean[c])*factor[c]+bias[c];
    ps_swish(norm,t*C);
    linear("conv_module.pointwise_conv2.weight",norm,t,C,C,gate);
    add(x,gate,t*C,1.f);
    task.cursor=mark;
}
int encode_features(const float *features,unsigned frames,float *output,volatile struct asr_mailbox *box) {
    if(frames<7 || frames>ASR_MAX_FEATURE_FRAMES) return -3;
    task.cursor=ASR_SCRATCH_BASE; task.box=box; task.prefix[0]='\0';
    int err=setjmp(task.fail);
    if(err) return -err;
    unsigned t=((frames-1)/2-1)/2;
    float *hidden=reserve(t*C),*pos=reserve((2*t-1)*C);
    subsample(features,frames,hidden);
    position_embedding(pos,t);
    for(unsigned layer=0;layer<12;++layer) {
        char *s=task.prefix;
        const char stem[]="encoder.encoders.";
        memcpy(s,stem,sizeof(stem)-1); s+=sizeof(stem)-1;
        if(layer>=10) *s++='1';
        *s++=(char)('0'+layer%10); *s++='.'; *s='\0';
        box->stage=100+layer*10;
        ff(hidden,t,1); ++box->stage;
        attention(hidden,pos,t); ++box->stage;
        convolution(hidden,t); ++box->stage;
        ff(hidden,t,0); ++box->stage;
        ps_layernorm(hidden,hidden,t,C,f32("norm_final.weight",C),f32("norm_final.bias",C));
    }
    task.prefix[0]='\0'; box->stage=300;
    ps_layernorm(hidden,output,t,C,f32("encoder.after_norm.weight",C),f32("encoder.after_norm.bias",C));
    for(unsigned i=0;i<t*C;++i) if(!isfinite(output[i])) return -34;
    return 0;
}
