#include <stddef.h>
#include "native_ps.h"
#ifdef ASR_PL_ENABLED
#include "native_pl.h"
#endif

static inline void sync_mem(void) { __asm__ volatile("dsb sy" ::: "memory"); }
static inline uint64_t ticks(void) {
    uint64_t t;
    __asm__ volatile("isb; mrs %0,cntpct_el0" : "=r"(t));
    return t;
}
_Static_assert(sizeof(struct asr_mailbox)==64,"mailbox ABI");
_Static_assert(offsetof(struct asr_mailbox,elapsed_ticks)==48,"timer alignment");

void run_benchmark(void) {
    volatile struct asr_mailbox *box=(volatile struct asr_mailbox *)(uintptr_t)ASR_MAILBOX_ADDR;
    box->magic=0; box->abi=1; box->state=ASR_READY;
#ifdef ASR_ENCODER_ENABLED
    box->capabilities=7;
#elif defined(ASR_PL_ENABLED)
    box->capabilities=5;
#else
    box->capabilities=1;
#endif
    box->request_seq=0; box->response_seq=0; box->command=0; box->feature_frames=0;
    box->result=0; box->encoder_frames=0; box->pl_calls=0; box->stage=0;
    box->elapsed_ticks=0; box->timer_hz=V024_EXPECTED_CNTFRQ; box->selftest_mask=0;
    sync_mem(); box->magic=0x50533234; sync_mem();
    for(;;) {
        uint32_t seq=box->request_seq;
        if(seq==box->response_seq) { __asm__ volatile("yield"); continue; }
        sync_mem();
        uint32_t cmd=box->command, frames=box->feature_frames;
        box->state=ASR_BUSY; box->encoder_frames=0; box->pl_calls=0; box->stage=0;
        sync_mem();
        uint64_t begin=ticks();
        int result=-1;
        if(cmd==ASR_SELFTEST) {
            box->selftest_mask=(uint32_t)ps_selftest();
            result=box->selftest_mask==31 ? 0 : -2;
        }
#ifdef ASR_PL_ENABLED
        else if(cmd==3) {
            result=native_pl_selftest();
            box->pl_calls=native_pl_profile.graphs;
            box->stage=native_pl_profile.error_csr;
        }
#endif
        else if(cmd==ASR_ENCODE) {
#ifdef ASR_ENCODER_ENABLED
            if(frames>=7 && frames<=ASR_MAX_FEATURE_FRAMES) {
                result=encode_features((const float *)(uintptr_t)ASR_INPUT_ADDR,frames,
                                       (float *)(uintptr_t)ASR_OUTPUT_ADDR,box);
                if(result==0) box->encoder_frames=((frames-1)/2-1)/2;
            } else result=-3;
#else
            (void)frames; result=-4;
#endif
        }
        box->result=result; box->elapsed_ticks=ticks()-begin;
        box->state=result==0 ? ASR_DONE : ASR_FAILED;
        sync_mem(); box->response_seq=seq; sync_mem();
    }
}
