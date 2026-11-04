#include "profile.h"
#include <math.h>
#include "native_ps.h"

void ps_layernorm(const float *x, float *y, unsigned rows, unsigned channels,
                  const float *gain, const float *bias) {
    uint64_t phase=perf_now();
    for(unsigned t=0;t<rows;++t) {
        const float *row=x+t*channels;
        float sum=0.f, var=0.f;
        for(unsigned c=0;c<channels;++c) sum+=row[c];
        float mean=sum/(float)channels;
        for(unsigned c=0;c<channels;++c) { float d=row[c]-mean; var+=d*d; }
        float inv=1.f/sqrtf(var/(float)channels+1e-12f);
        for(unsigned c=0;c<channels;++c) y[t*channels+c]=(row[c]-mean)*inv*gain[c]+bias[c];
    }
    perf_end(PS_LN,phase);
}
static float sigmoid(float x) {
    float e=expf(-fabsf(x));
    return x>=0.f ? 1.f/(1.f+e) : e/(1.f+e);
}
void ps_swish(float *x,unsigned count) {
    uint64_t phase=perf_now();
    for(unsigned i=0;i<count;++i) x[i]*=sigmoid(x[i]);
    perf_end(PS_SWISH,phase);
}
void ps_glu(const float *x,float *y,unsigned rows,unsigned channels) {
    uint64_t phase=perf_now();
    for(unsigned r=0;r<rows;++r) {
        const float *row=x+r*2*channels;
        for(unsigned c=0;c<channels;++c) y[r*channels+c]=row[c]*sigmoid(row[channels+c]);
    }
    perf_end(PS_GLU,phase);
}
void ps_softmax(float *x,unsigned rows,unsigned cols) {
    uint64_t phase=perf_now();
    for(unsigned r=0;r<rows;++r) {
        float *row=x+r*cols, peak=row[0], sum=0.f;
        for(unsigned j=1;j<cols;++j) if(row[j]>peak) peak=row[j];
        for(unsigned j=0;j<cols;++j) { row[j]=expf(row[j]-peak);sum+=row[j]; }
        float inv=1.f/sum;
        for(unsigned j=0;j<cols;++j) row[j]*=inv;
    }
    perf_end(PS_SOFTMAX,phase);
}
void ps_depthwise(const float *x,float *y,unsigned rows,unsigned channels,
                  const float *w,const float *bias,unsigned kernel) {
    uint64_t phase=perf_now();
    for(unsigned t=0;t<rows;++t) {
        float *out=y+t*channels;
        for(unsigned c=0;c<channels;++c) out[c]=bias[c];
        for(unsigned j=0;j<kernel;++j) {
            int pos=(int)t+(int)j-(int)(kernel/2);
            if(pos<0 || pos>=(int)rows) continue;
            for(unsigned c=0;c<channels;++c) out[c]+=x[(unsigned)pos*channels+c]*w[c*kernel+j];
        }
    }
    perf_end(PS_DEPTHWISE,phase);
}
