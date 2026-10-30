/* V022 phase1: PS starts a whole PL plan, receives completion, handles error.
 * No numerical operators, im2col, per-matrix descriptors, SRAM frames or neural
 * data copies here. The immutable index is generated from the parameter image.
 */
#include "vm211.h"
#include "macro.h"
#include "plan_index.h"
static uint32_t stats[64];
static volatile uint32_t *const matrix=(void *)0xa8000000ULL;
static volatile uint32_t *const plan=(void *)0xa9000000ULL;
extern void vm211_service_queries(void);
static uint64_t ticks_vm(void){uint64_t v;__asm__ volatile("isb; mrs %0,cntpct_el0":"=r"(v));return v;}
static void fence_vm(void){__asm__ volatile("dsb sy":::"memory");}
static void add64(unsigned at,uint64_t n){uint64_t v=stats[at]+((uint64_t)stats[at+1]<<32)+n;stats[at]=(uint32_t)v;stats[at+1]=(uint32_t)(v>>32);}
static uint64_t read64(unsigned offset){uint32_t lo=plan[offset/4],hi=plan[offset/4+1];return lo+((uint64_t)hi<<32);}
int vm211_run(const struct v10_io *io,uint32_t address,uint32_t reply[16]){
 (void)io;const struct plan_entry *p=0;
 for(unsigned i=0;i<sizeof(plan_index)/sizeof(plan_index[0]);i++)if(plan_index[i].program==address){p=&plan_index[i];break;}
 if(!p||plan[0]!=0xa51a22d0u||plan[0x9c/4]!=0x10102201u||matrix[0x90/4]!=1||matrix[0x9c/4]!=V022_IMAGE_BYTES||matrix[0xa0/4]!=V022_IMAGE_CRC||matrix[0x94/4]!=V022_MODEL_LO||matrix[0x98/4]!=V022_MODEL_HI)return V10_ID;
 if((plan[1]&1)||(matrix[1]&5))return V10_BUSY;
 uint32_t generation=matrix[0xa4/4],cookie=matrix[0x28/4];
 if(cookie>0xffffffffu-p->matrix_tasks)return V10_ARGUMENT;
 uint64_t begin=ticks_vm();plan[2]=p->plan;plan[3]=p->count;fence_vm();plan[4]=1;fence_vm();
 while(!(plan[1]&6)){
  vm211_service_queries();
  // Timeout does NOT cancel/replay an accepted plan. Gateway keeps writes locked
  // by hardware BUSY; diagnosis must wait for all outstanding DMA to drain.
  if(ticks_vm()-begin>33333000ULL*300){stats[27]=(uint32_t)V10_TIMEOUT;return V10_TIMEOUT;}
 }
 fence_vm();
 if((plan[1]&5)||plan[7]||plan[5]!=p->count||plan[0x78/4]&7||matrix[0xa4/4]!=generation||matrix[0x90/4]!=1||matrix[0x28/4]!=cookie+p->matrix_tasks){stats[27]=(uint32_t)V10_FAULT;return V10_FAULT;}
 stats[0]=0x2111ff01u;stats[1]++;stats[p->kind==1?2:3]++;stats[4]+=p->ops;
 stats[6]+=p->matrix_queues;stats[7]+=p->matrix_tasks;
 add64(8,read64(0xa0));add64(10,read64(0xa8));
 stats[12]+=plan[0x50/4]+plan[0x58/4];stats[13]+=plan[0x54/4]+plan[0x5c/4];
 stats[15]+=p->count;add64(16,read64(0x40));add64(18,read64(0x48));
 add64(20,read64(0x30));add64(22,read64(0x20));add64(24,ticks_vm()-begin);
 stats[26]=matrix[0x28/4];stats[27]=0;stats[28]=generation;stats[29]=address;stats[30]=2201;
 stats[57]+=plan[0x70/4];stats[58]+=plan[0x74/4];stats[59]+=plan[0x80/4];stats[60]+=plan[0x84/4];stats[61]|=plan[0x78/4];
 for(unsigned i=0;i<16;i++)reply[i]=0;
 uint64_t elapsed=ticks_vm()-begin;
 reply[0]=0x2111ff01u;reply[1]=stats[26];reply[2]=generation;reply[3]=p->ops;reply[4]=p->output_elements;reply[5]=(uint32_t)elapsed;reply[6]=(uint32_t)(elapsed>>32);
 reply[12]=plan[0x1c/4];reply[13]=plan[0x7c/4];reply[14]=p->count;reply[15]=plan[0x78/4];
 for(unsigned i=0;i<16;i++){stats[32+i]=reply[i];}
 return 0;
}
void vm211_status(uint32_t reply[64]){
 stats[0]=0x2111ff01u;stats[30]=2201;
 for(unsigned i=0;i<64;i++)reply[i]=stats[i];
}
