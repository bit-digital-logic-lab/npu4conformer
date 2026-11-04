#include "../native_ps/profile.h"
#include "native_pl.h"
#include <stddef.h>
#include <string.h>

/* Do not overlap the cold-graph qualification, static model or A53 mailbox. */
#define PLAN_ADDR   0x10010000u
#define QUEUE_ADDR  0x04010000u
#define A_ADDR      0x04100000u
#define C_ADDR      0x04300000u
#define BPACK_ADDR  0x04400000u
#define DYN_ADDR    0x07f00000u
#define ARENA_END   0x08000000u
#define PARAM_END   0x20000000u
#define MAX_CUBES_PER_DESC 128u
#define PTR(type, addr) ((type *)(uintptr_t)(addr))

struct native_pl_profile native_pl_profile;
static uint32_t epoch;
static float dynamic_scales[4096];

static unsigned tiles(unsigned n) { return (n+31u)/32u; }
static unsigned smaller(unsigned x, unsigned y) { return x<y?x:y; }
static void barrier(void) { __asm__ volatile ("dsb sy" ::: "memory"); }
static uint32_t csr_read(unsigned offset) { return *PTR(volatile uint32_t,0xa0000000u+offset); }
static void csr_write(unsigned offset,uint32_t word) { *PTR(volatile uint32_t,0xa0000000u+offset)=word; }
static uint64_t counter(void) {
    uint64_t t;
    __asm__ volatile ("mrs %0, cntpct_el0":"=r"(t));
    return t;
}
static uint64_t frequency(void) {
    uint64_t f;
    __asm__ volatile ("mrs %0, cntfrq_el0":"=r"(f));
    return f;
}
static uint32_t new_epoch(void) {
    if (!epoch) epoch=(uint32_t)counter()|1u;
    if (++epoch == 0) ++epoch;
    return epoch;
}

static int submit(unsigned desc_count, unsigned input_bytes, unsigned output_bytes) {
    uint32_t *plan=PTR(uint32_t,PLAN_ADDR);
    memset(plan,0,256);
    plan[0]=0x57435047; plan[1]=0x00020001; plan[2]=1; plan[3]=15;
    plan[4]=PARAM_END; plan[5]=256;
    plan[8]=0x08000000; plan[9]=0x10000000;
    uint32_t *node=plan+16;
    node[0]=0x5743474e; node[1]=1; node[3]=3;
    node[4]=QUEUE_ADDR; node[5]=desc_count; node[6]=1; node[7]=2;
    node[8]=A_ADDR; node[9]=input_bytes; node[10]=C_ADDR; node[11]=output_bytes;
    uint32_t h=0x811c9dc5;
    for (unsigned i=0;i<64;i++) if (i!=7) h=(h^plan[i])*0x01000193u;
    plan[7]=h;
    if ((csr_read(4)&5u) || csr_read(0xb0)) return -3;
    barrier();
    csr_write(8,PLAN_ADDR); csr_write(12,1); csr_write(16,1);
    barrier();
    uint64_t start=counter(), limit=frequency()*3;
    for (;;) {
        uint32_t state=csr_read(4);
        if (state&4u) { native_pl_profile.error_csr=csr_read(0x1c); return -4; }
        if ((state&3u)==2u) break;
        if (counter()-start>limit) return -5;
    }
    barrier();
    native_pl_profile.error_csr=csr_read(0x1c);
    if (native_pl_profile.error_csr || csr_read(0x14)!=1 || csr_read(0xb0)) return -6;
    native_pl_profile.graphs++;
    native_pl_profile.descriptors+=desc_count;
    uint32_t lo=csr_read(0x20);
    uint32_t hi=csr_read(0x24);
    native_pl_profile.cycles+=((uint64_t)hi<<32)|lo;
    return 0;
}

static void queue_desc(uint32_t *d,unsigned part, unsigned a,unsigned b,
                       unsigned m,unsigned k,unsigned n) {
    uint32_t id=new_epoch();
    d[0]=0x51415352; d[1]=0x00150001; d[2]=id; d[3]=part?part-1:0xffffffff;
    d[4]=a; d[5]=b; d[6]=C_ADDR; d[7]=m; d[8]=n; d[9]=k;
    d[10]=id; d[11]=0x00010007; d[12]=0x00030002; d[13]=0x3210;
    d[14]=0x00010000; d[15]=part?0x00010001:0;
}

static float absval(float a) { return a<0?-a:a; }
static int16_t quant_a(float a) {
    /* AArch64 FCVTNS rounds to nearest with ties to even independent of FPCR. */
    int32_t i;
    __asm__ ("fcvtns %w0,%s1":"=r"(i):"w"(a));
    return (int16_t)i;
}
static int64_t read_c48(const uint8_t *p) {
    uint64_t u=(uint64_t)p[0]|(uint64_t)p[1]<<8|(uint64_t)p[2]<<16|
               (uint64_t)p[3]<<24|(uint64_t)p[4]<<32|(uint64_t)p[5]<<40;
    return (int64_t)(u^((uint64_t)1<<47))-((int64_t)1<<47);
}

int native_pl_linear(const float *x,unsigned m,unsigned k,unsigned n,const uint8_t *weights,
                     const float *scales,const float *bias,float *y) {
    if (!x || !y || x==y || !weights || !scales || !m || !n || !k || m>65535 || k>32768 || n>8192) return -1;
    unsigned kt=tiles(k), nt=tiles(n);
    uintptr_t wp=(uintptr_t)weights;
    uint64_t end=(uint64_t)wp+(uint64_t)kt*nt*1024;
    if ((wp&63u) || !((wp>=0x10100000u && end<=PARAM_END) || (wp==DYN_ADDR && end<=ARENA_END))) return -2;
    uint64_t whole=perf_now(), phase=whole;
    float peak=0;
    for (size_t i=0;i<(size_t)m*k;i++) {
        float v=absval(x[i]);
        if (!__builtin_isfinite(v)) return -1;
        if(v>peak) peak=v;
    }
    float scale_a=peak ? peak/2047.0f : 1.0f;
    if (scale_a==0) return -1;
    perf_end(A_SCAN,phase);
    for (unsigned row=0;row<m;row+=32) {
        phase=perf_now();
        unsigned mr=smaller(32,m-row);
        int16_t *act=PTR(int16_t,A_ADDR);
        memset(act,0,kt*2048u);
        for (unsigned r=0;r<mr;r++)
            for (unsigned d=0;d<k;d++)
                act[(d/32)*1024+r*32+d%32]=quant_a(x[(size_t)(row+r)*k+d]/scale_a);
        perf_end(A_PACK,phase);
        for (unsigned col=0;col<n;col+=4096) {
            unsigned nc=smaller(4096,n-col), nct=tiles(nc);
            unsigned depth_tiles=smaller(128u,MAX_CUBES_PER_DESC/nct);
            unsigned parts=(kt+depth_tiles-1)/depth_tiles;
            if (parts>4096 || (!depth_tiles)) return -2;
            unsigned bbase=(unsigned)wp;
            if(nct!=nt) {
                phase=perf_now();
                if ((uint64_t)kt*nct*1024>DYN_ADDR-BPACK_ADDR) return -2;
                bbase=BPACK_ADDR;
                for(unsigned t=0;t<kt;t++)
                    memcpy(PTR(uint8_t,bbase)+(size_t)t*nct*1024,
                           weights+((size_t)t*nt+col/32)*1024,nct*1024);
                perf_end(B_REPACK,phase);
            }
            uint32_t *queue=PTR(uint32_t,QUEUE_ADDR);
            for(unsigned part=0;part<parts;part++) {
                unsigned tile=part*depth_tiles;
                queue_desc(queue+16*part,part,A_ADDR+tile*2048,bbase+tile*nct*1024,
                           mr,smaller(k-tile*32,depth_tiles*32),nc);
            }
            phase=perf_now();
            int rc=submit(parts,kt*2048,nct*6144);
            perf_end(WAIT_SUBMIT,phase);
            if(rc) return rc;
            phase=perf_now();
            const uint8_t *out=PTR(uint8_t,C_ADDR);
            for(unsigned r=0;r<mr;r++) for(unsigned c=0;c<nc;c++) {
                int64_t acc=read_c48(out+((c/32)*1024+r*32+c%32)*6);
                y[(size_t)(row+r)*n+col+c]=(float)((double)acc*scale_a*scales[col+c])+(bias?bias[col+c]:0);
            }
            perf_end(C_UNPACK,phase);
        }
    }
    perf_end(LINEAR_TOTAL,whole);
    return 0;
}

int native_pl_dynamic(const float *x,unsigned m,unsigned k,unsigned n,const float *b,float *y) {
    if(!b || !x || !y || !m || !k || !n || k>4096 || n>4096) return -1;
    unsigned kt=tiles(k),nt=tiles(n),bytes=kt*nt*1024;
    if(bytes>ARENA_END-DYN_ADDR) return -2;
    uint64_t phase=perf_now();
    uint8_t values[64],codes[64],seen[121]={0},first[121]={0};
    unsigned count=0;
    for(unsigned code=0;code<64;code++) {
        unsigned value=(code&15)<<(code>>4);
        if (!seen[value]) {seen[value]=1;first[value]=(uint8_t)code;}
    }
    for(unsigned v=0;v<=120;v++) if(seen[v]) {values[count]=(uint8_t)v;codes[count++]=first[v];}
    uint8_t *packed=PTR(uint8_t,DYN_ADDR);
    memset(packed,0,bytes);
    for(unsigned c=0;c<n;c++) {
        float peak=0;
        for(unsigned d=0;d<k;d++) {
            float v=absval(b[(size_t)d*n+c]);
            if(!__builtin_isfinite(v)) return -1;
            if(v>peak) peak=v;
        }
        float scale=peak?peak/120.f:1.f;
        if(scale==0) return -1;
        dynamic_scales[c]=scale;
        for(unsigned d=0;d<k;d++) {
            float raw=b[(size_t)d*n+c], mag=absval(raw)/scale;
            unsigned lo=0,hi=count-1;
            while(lo<hi) {
                unsigned mid=(lo+hi)/2;
                if(2*mag>values[mid]+values[mid+1]) lo=mid+1; else hi=mid;
            }
            unsigned code=codes[lo]|((raw<0)?64u:0u);
            packed[((d/32)*nt+c/32)*1024+(d%32)*32+c%32]=(uint8_t)(code|(__builtin_parity(code)<<7));
        }
    }
    perf_end(DYNAMIC_PACK,phase);
    return native_pl_linear(x,m,k,n,packed,dynamic_scales,0,y);
}

static int test_x(unsigned r,unsigned d) {
    return (int)((17*r+29*d+(r^d))%3)-1;
}
static int test_w(unsigned d,unsigned c) {
    return (int)((7*d+13*c+((d>>2)^c))%5)-2;
}
int native_pl_selftest(void) {
    enum { M=35, K=1057, N=129, KT=34, NT=5 };
    float *x=PTR(float,0x07c00000u), *y=PTR(float,0x07c40000u);
    float scales[N], bias[N];
    uint8_t *w=PTR(uint8_t,DYN_ADDR);
    memset(w,0,KT*NT*1024);
    for (unsigned r=0;r<M;r++) for (unsigned d=0;d<K;d++)
        x[r*K+d]=(float)test_x(r,d);
    for (unsigned d=0;d<K;d++) for (unsigned c=0;c<N;c++) {
        int v=test_w(d,c);
        unsigned payload=(unsigned)(v<0?-v:v)|(v<0?64u:0u);
        w[((d/32)*NT+c/32)*1024+(d%32)*32+c%32]=(uint8_t)(payload|(__builtin_parity(payload)<<7));
    }
    for(unsigned c=0;c<N;c++) {scales[c]=(c%2)?0.5f:1.f;bias[c]=(float)c/256.f;}
    unsigned graphs=native_pl_profile.graphs, desc=native_pl_profile.descriptors;
    int rc=native_pl_linear(x,M,K,N,w,scales,bias,y);
    if (rc) return rc;
    if (native_pl_profile.graphs-graphs!=2 || native_pl_profile.descriptors-desc!=4) return -7;
    for(unsigned r=0;r<M;r++) for(unsigned c=0;c<N;c++) {
        int gold=0;
        for(unsigned d=0;d<K;d++) gold+=test_x(r,d)*test_w(d,c);
        float target=(float)gold*scales[c]+bias[c];
        if(!__builtin_isfinite(y[r*N+c]) || absval(y[r*N+c]-target)>0.0002f) return -8;
    }
    return 0;
}
