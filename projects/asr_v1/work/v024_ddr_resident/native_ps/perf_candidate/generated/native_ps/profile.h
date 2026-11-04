#ifndef ASR_TIMING_H
#define ASR_TIMING_H
#include <stdint.h>
enum perf_slot {LINEAR_TOTAL, DYNAMIC_PACK, A_SCAN, A_PACK, B_REPACK, WAIT_SUBMIT,
                 C_UNPACK, PS_LN, PS_SWISH, PS_GLU, PS_SOFTMAX, PS_DEPTHWISE, PERF_COUNT};
extern uint64_t perf_acc[PERF_COUNT];
static inline uint64_t perf_now(void) {
    uint64_t val;
    __asm__ volatile("isb; mrs %0,cntpct_el0" : "=r"(val) :: "memory");
    return val;
}
static inline void perf_end(enum perf_slot slot,uint64_t begin) {
    perf_acc[slot]+=perf_now()-begin;
}
#endif
