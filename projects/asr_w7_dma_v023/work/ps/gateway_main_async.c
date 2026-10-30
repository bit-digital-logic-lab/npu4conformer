#include "resident.h"
#include "macro.h"
extern uint32_t v13_profile[16];
static volatile uint32_t *const box=(void *)0xfffe0000ULL;
static volatile uint32_t *const mb=(void *)0xa4000000ULL;
static uint32_t read32(void *ctx,uint32_t off){(void)ctx;return *(volatile uint32_t *)(0xa0000000ULL+off);}
static void write32(void *ctx,uint32_t off,uint32_t v){(void)ctx;*(volatile uint32_t *)(0xa0000000ULL+off)=v;}
static void barrier(void *ctx){(void)ctx;__asm__ volatile("dsb sy":::"memory");}
static uint64_t ticks(void){uint64_t v;__asm__ volatile("isb; mrs %0,cntpct_el0":"=r"(v));return v;}
static uint64_t control(void){uint64_t v;__asm__ volatile("mrs %0,sctlr_el3":"=r"(v));return v;}
static void put64(unsigned n,uint64_t v){box[n]=(uint32_t)v;box[n+1]=(uint32_t)(v>>32);}
static void profile64(unsigned n,uint64_t v){v13_profile[n]=(uint32_t)v;v13_profile[n+1]=(uint32_t)(v>>32);}
void ram_probe_main(void){
 box[0]=0xa51a1301;for(unsigned i=1;i<64;i++)box[i]=0;
 uint64_t saved=control();put64(26,saved);
 if(saved&0x1005){box[1]=0xeb;return;}
 __asm__ volatile("dsb sy; ic iallu; dsb sy; isb":::"memory");
 uint64_t enabled=saved|0x1000;
 __asm__ volatile("msr sctlr_el3,%0; isb"::"r"(enabled):"memory");
 put64(28,control());box[25]=1;
 struct v10_io io={0,read32,write32,barrier};
 uint32_t request[259],reply_words[345];
 uint8_t *reply=(uint8_t *)reply_words;
 uint64_t fast_cycles=0,copy_ticks=0,fast_ticks=0,reply_ticks=0,in_bytes=0,out_bytes=0,macro_ticks=0;
 uint64_t fast_in=0,fast_out=0;uint32_t fast_commands=0;
 if(mb[0]!=0xa51a1310||mb[13]!=128||read32(0,0)!=0xa51a1001){box[1]=0xe5;goto finish;}
 box[1]=1;barrier(0);
 for(;;){
  uint32_t s=mb[1];
  if(s&2){box[1]=0xe6;break;}
  if(!(s&1)){if(box[2]==1&&!(s&12))break;if(!(s&12))vm211_async_idle(&io);continue;}
  uint64_t start=ticks();uint32_t n=mb[2],h=mb[9];
  if(n<10||n>1034){box[1]=0xe7;break;}
  box[5]=h&255;box[6]=n;size_t received=0;
  if(((h&255)!=0x41&&(h&255)!=0x42)||!(h&0x80000000u)){
   /* Data never traverses A53: one guarded doorbell selects the PL RAM path. */
   uint32_t expected=mb[10]+1;mb[8]=1;barrier(0);
   uint32_t polls=100000000;
   while(mb[10]!=expected){if((mb[1]&2)||!polls--){box[4]=mb[12];box[1]=0xed;goto finish;}}
   barrier(0);if(mb[12]){box[4]=mb[12];box[1]=0xee;goto finish;}
   received=mb[15];fast_cycles+=mb[11];fast_ticks+=ticks()-start;
   fast_commands++;fast_in+=n;fast_out+=received;
  }else{
   int observing=(h&255)==0x42 && (h>>16)==0xff00;
   for(uint32_t j=0;j<(n+3)/4;j++)request[j]=mb[0x400+j];
   barrier(0);if(!observing)copy_ticks+=ticks()-start;start=ticks();
   int rc=v12_virtual(&io,(uint8_t *)request,n,reply,&received);
   if(!observing)macro_ticks+=ticks()-start;
   if(rc!=1){box[4]=(uint32_t)rc;box[1]=0xec;break;}
   start=ticks();
   for(size_t j=received;j<((received+3)&~(size_t)3);j++)reply[j]=0;
   for(size_t j=0;j<(received+3)/4;j++)mb[0x800+j]=reply_words[j];
   mb[4]=(uint32_t)received;barrier(0);mb[5]=1;barrier(0);if(!observing)reply_ticks+=ticks()-start;
  }
  in_bytes+=n;out_bytes+=received;box[3]++;
  put64(12,fast_cycles);put64(14,copy_ticks);put64(16,fast_ticks);put64(18,reply_ticks);
  put64(20,in_bytes);put64(22,out_bytes);box[24]=33333000;
  put64(32,macro_ticks);put64(34,v12_micro_calls);put64(36,v12_micro_cycles);put64(38,v12_queue_cycles);
  box[40]=v12_macros;box[41]=v12_queue_runs;put64(42,v12_layout_words);box[44]=v12_flags;
  box[45]=fast_commands;put64(46,fast_in);put64(48,fast_out);
  profile64(0,fast_ticks);profile64(2,copy_ticks);profile64(4,reply_ticks);profile64(6,macro_ticks);
  profile64(8,fast_cycles);profile64(10,fast_in);profile64(12,fast_out);
  v13_profile[14]=fast_commands;v13_profile[15]=33333000;barrier(0);
 }
finish:
 __asm__ volatile("dsb sy; msr sctlr_el3,%0; isb; ic iallu; dsb sy; isb"::"r"(saved):"memory");
 put64(30,control());barrier(0);if(box[1]==1){box[1]=2;barrier(0);}
}
