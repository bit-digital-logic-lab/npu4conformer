/* Generated firmware.c includes this file only in the separate timing image. */
#include <string.h>
#include "profile.h"
uint64_t perf_acc[PERF_COUNT];
static struct native_pl_profile perf_initial;
struct perf_record {
    uint32_t magic, abi, sequence, graphs, descriptors, status;
    uint64_t total_ticks, pl_cycles, ticks[PERF_COUNT];
};
_Static_assert(sizeof(struct perf_record)==136,"unexpected profiling ABI size");
static volatile struct perf_record *const perf_box=(void *)(uintptr_t)0x08000040;
static void perf_begin(void) {
    perf_box->magic=0;
    __asm__ volatile("dsb sy":::"memory");
    memset(perf_acc,0,sizeof(perf_acc));
    perf_initial=native_pl_profile;
}
static void perf_publish(uint32_t seq,int status,uint64_t total) {
    perf_box->abi=1; perf_box->sequence=seq; perf_box->status=(uint32_t)status;
    perf_box->graphs=native_pl_profile.graphs-perf_initial.graphs;
    perf_box->descriptors=native_pl_profile.descriptors-perf_initial.descriptors;
    perf_box->pl_cycles=native_pl_profile.cycles-perf_initial.cycles; perf_box->total_ticks=total;
    for(unsigned i=0;i<PERF_COUNT;++i) perf_box->ticks[i]=perf_acc[i];
    __asm__ volatile("dsb sy":::"memory");
    perf_box->magic=0x50465231;
    __asm__ volatile("dsb sy":::"memory");
}
