#include "vm211.h"
/* V21 PS: transport, parameter CRC/read-back, DDR->PL SRAM copies and queue control.
 * No CPU neural arithmetic, PS initialization, reset, storage or network reconfiguration.
 * Requires bare-metal ownership of the documented DDR/OCM reservations. */
#include "resident.h"
#include "macro.h"
#define V21_BASE 0x03000000u
#define V21_END 0x08000000u
#define PARAM_BASE 0x10000000u
#define PARAM_END 0x40000000u
static uint32_t cursor21=V21_BASE,stats21[64],verified21,crc21,expected21,loading21;
static uint32_t crc_table21[256],crc_init21;
static uint32_t copy_arena21[280],copy_reply21[345];
static unsigned copy_seq21;
static unsigned get16_21(const uint8_t *p){return p[0]|((unsigned)p[1]<<8);}
static uint32_t get32_21(const uint8_t *p){return get16_21(p)|((uint32_t)get16_21(p+2)<<16);}
static void put16_21(uint8_t *p,unsigned v){p[0]=(uint8_t)v;p[1]=(uint8_t)(v>>8);}
static void put32_21(uint8_t *p,uint32_t v){put16_21(p,v);put16_21(p+2,v>>16);}
static void fence21(void){__asm__ volatile("dsb sy":::"memory");}
static uint64_t ticks21(void){uint64_t v;__asm__ volatile("isb; mrs %0,cntpct_el0":"=r"(v));return v;}
static int mutable21(uint32_t a,unsigned n){return !(a&3)&&a>=V21_BASE&&a<V21_END&&n&&n<=V21_END-a;}
static int param21(volatile uint32_t *csr,uint32_t a,unsigned n){uint32_t size=csr[0x9c/4];return !(a&3)&&a>=PARAM_BASE&&a<PARAM_END&&size&&n&&a-PARAM_BASE<size&&n<=size-(a-PARAM_BASE);}
static void crc_prepare21(void){if(crc_init21)return;for(unsigned i=0;i<256;i++){uint32_t c=i;for(unsigned j=0;j<8;j++)c=(c>>1)^((c&1)?0xedb88320u:0);crc_table21[i]=c;}crc_init21=1;}
static void verify_words21(volatile uint32_t *mem,unsigned words){
 uint64_t begin=ticks21();crc_prepare21();
 for(unsigned i=0;i<words;i++){uint32_t value=mem[i];for(unsigned b=0;b<4;b++){crc21=crc_table21[(crc21^value)&255]^(crc21>>8);value>>=8;}}
 verified21+=words*4;uint64_t t=stats21[42]+((uint64_t)stats21[43]<<32)+ticks21()-begin;stats21[42]=(uint32_t)t;stats21[43]=(uint32_t)(t>>32);stats21[45]=verified21;
}
static int param_copy21(const struct v10_io *io,uint32_t src,unsigned dst,unsigned words,unsigned span){
 volatile uint32_t *csr=(void *)0xa8000000ULL;
 if(csr[0x90/4]!=1||!words||words>32768||dst>=32768||words>32768-dst||!span||span>words||!param21(csr,src,span*4))return V10_ARGUMENT;
 volatile uint32_t *mem=(void *)(uintptr_t)src;uint8_t *frame=(void *)(copy_arena21+4);
 for(unsigned at=0;at<words;at+=255){
  unsigned count=words-at;if(count>255)count=255;unsigned seq=++copy_seq21&65535;
  frame[0]=0xa5;frame[1]=0x5a;put16_21(frame+2,seq);frame[4]=0x41;frame[5]=0;put16_21(frame+6,4+count*4);
  put16_21(frame+8,dst+at);put16_21(frame+10,count);
  for(unsigned i=0;i<count;i++)put32_21(frame+12+i*4,mem[(at+i)%span]);
  put16_21(frame+12+count*4,v12_crc(frame+2,10+count*4));
  copy_arena21[0]=16;copy_arena21[1]=14+count*4;copy_arena21[2]=8192;copy_arena21[3]=1378;
  uint32_t cycles=0;size_t got=0;int rc=v10_upload(io,(const uint8_t *)copy_arena21,(16+copy_arena21[1]+3)&~3u,0,1);
  if(!rc)rc=v10_start(io,0,1);
  if(!rc)rc=v10_wait(io,100000000,&cycles);
  if(!rc)rc=v10_read_reply(io,8192,(uint8_t *)copy_reply21,1378,&got);
  if(rc)return rc;
  const uint8_t *r=(const uint8_t *)copy_reply21;
  if(got!=10||r[0]!=0x5a||r[1]!=0xa5||get16_21(r+2)!=seq||r[4]!=0x41||r[5]||get16_21(r+6)||v12_crc(r+2,6)!=get16_21(r+8))return V10_FAULT;
  stats21[40]+=count*4;stats21[41]++;stats21[46]+=cycles;
 }
 return 0;
}
static void refresh21(volatile uint32_t *csr){
 stats21[0]=0xa51a2202;stats21[2]=csr[0x28/4];stats21[22]=csr[0x88/4];stats21[31]=21;
 for(unsigned i=0;i<6;i++)stats21[32+i]=csr[(0x90+4*i)/4];
}
#include "async_dispatch.inc.c"
static int v21_dispatch(const struct v10_io *io,const uint8_t *req,size_t n,uint8_t *reply,size_t *received){
 if(n<14)return v12_virtual(io,req,n,reply,received);
 unsigned base=get16_21(req+8),count=get16_21(req+10),op=req[4];
 if(base==0xe400)return vm211_dispatch(io,req,n,reply,received);
 if((*(volatile uint32_t *)(uintptr_t)0xa9000004u)&1u)return V10_BUSY; /* no mutation while an accepted PL plan drains */
 if(base!=0xe000&&base!=0xe100&&base!=0xe200&&base!=0xe210&&base!=0xe300)return v12_virtual(io,req,n,reply,received);
 if((op!=0x41&&op!=0x42)||req[0]!=0xa5||req[1]!=0x5a||req[5]||n!=10u+get16_21(req+6)||v12_crc(req+2,n-4)!=get16_21(req+n-2))return V10_CRC;
 volatile uint32_t *csr=(void *)0xa8000000ULL;
 if(csr[0]!=0xa51a21c1u||(csr[1]&1)||csr[0x88/4]!=0x10102131u)return V10_FAULT;
 unsigned len=0;
 if(op==0x41&&base==0xe210&&n==14+count*4&&count){
  unsigned command=get32_21(req+12);
  if(command==1&&count==5){
   uint32_t size=get32_21(req+24);if(!size||(size&255)||size>PARAM_END-PARAM_BASE||!(get32_21(req+16)|get32_21(req+20)))return V10_ARGUMENT;
   csr[0x90/4]=1;fence21();if(csr[0x90/4]!=2)return V10_FAULT;
   csr[0x94/4]=get32_21(req+16);csr[0x98/4]=get32_21(req+20);csr[0x9c/4]=size;csr[0xa0/4]=get32_21(req+28);fence21();
   loading21=1;verified21=0;crc21=0xffffffff;expected21=get32_21(req+28);stats21[45]=0;stats21[44]++;cursor21=PARAM_BASE;
  }else if(command==3&&count==3&&loading21&&csr[0x90/4]==2){
   uint32_t offset=get32_21(req+16),bytes=get32_21(req+20);
   if(offset!=verified21||!bytes||(bytes&3)||bytes>65536||!param21(csr,PARAM_BASE+offset,bytes))return V10_ARGUMENT;
   verify_words21((void *)(uintptr_t)(PARAM_BASE+offset),bytes/4);cursor21=PARAM_BASE+verified21;
  }else if(command==2&&count==1&&loading21&&csr[0x90/4]==2){
   volatile uint32_t *header=(void *)(uintptr_t)PARAM_BASE;
   if(verified21!=csr[0x9c/4]||(crc21^0xffffffff)!=expected21||header[0]!=0x41503231||header[1]!=21||header[2]!=csr[0x94/4]||header[3]!=csr[0x98/4]||header[4]!=verified21||!header[5]||!header[6]||!header[7])return V10_CRC;
   csr[0x90/4]=2;fence21();if(csr[0x90/4]!=1)return V10_FAULT;loading21=0;
  }else return V10_ARGUMENT;
 }else if(op==0x41&&base==0xe000&&count==1&&n==18){
  uint32_t address=get32_21(req+12);if(!mutable21(address,4)&&!param21(csr,address,4))return V10_ARGUMENT;cursor21=address;
 }else if(base==0xe100&&count&&count<=255&&((op==0x41&&n==14+4*count)||(op==0x42&&n==14))){
  unsigned bytes=count*4;int isparam=param21(csr,cursor21,bytes);int ismutable=mutable21(cursor21,bytes);
  if(!isparam&&!ismutable)return V10_ARGUMENT;
  if(op==0x41&&((isparam&&(!loading21||csr[0x90/4]!=2||cursor21!=PARAM_BASE+verified21))||(ismutable&&csr[0x90/4]!=1)))return V10_ARGUMENT;
  volatile uint32_t *mem=(void *)(uintptr_t)cursor21;
  for(unsigned i=0;i<count;i++){if(op==0x41)mem[i]=get32_21(req+12+i*4);else put32_21(reply+8+i*4,mem[i]);}
  fence21();if(op==0x41){if(isparam){verify_words21(mem,count);stats21[38]+=bytes;}else stats21[39]+=bytes;}
  cursor21+=bytes;if(op==0x42)len=bytes;
 }else if(op==0x41&&base==0xe300&&count==4&&n==30){
  int rc=param_copy21(io,get32_21(req+12),get32_21(req+16),get32_21(req+20),get32_21(req+24));if(rc)return rc;
 }else if(op==0x41&&base==0xe200&&count==2&&n==22){
  if(csr[1]&4)return V10_FAULT; /* Do not start from a stale undiagnosed PL fault. */
  uint32_t address=get32_21(req+12),tasks=get32_21(req+16);
  if(csr[0x90/4]!=1||(address&63)||!tasks||tasks>4096||!mutable21(address,tasks*64))return V10_ARGUMENT;
  uint32_t rb=csr[0x40/4],wb=csr[0x44/4],rburst=csr[0x48/4],wburst=csr[0x4c/4];
  csr[0x08/4]=address;csr[0x0c/4]=tasks;fence21();csr[0x10/4]=1;fence21();uint64_t begin=ticks21();
  while(!(csr[1]&6)){if(ticks21()-begin>33333000ULL*30)return V10_TIMEOUT;}
  fence21();if((csr[1]&5)||!(csr[1]&2)||csr[0x1c/4]||csr[0x14/4]!=tasks)return V10_FAULT;
  stats21[1]++;stats21[3]=csr[0x14/4];stats21[4]=csr[0x20/4];stats21[5]=csr[0x24/4];stats21[6]=csr[0x50/4];stats21[7]=csr[0x54/4];
  stats21[8]=csr[0x40/4]-rb;stats21[9]=csr[0x44/4]-wb;stats21[10]=csr[0x48/4]-rburst;stats21[11]=csr[0x4c/4]-wburst;
  stats21[12]=csr[0x34/4];stats21[13]=csr[0x38/4];stats21[14]=csr[0x68/4];stats21[15]=csr[0x58/4];stats21[16]=csr[0x5c/4];stats21[17]=csr[0x60/4];stats21[18]=csr[0x64/4];
  stats21[19]=csr[0x18/4];stats21[20]=csr[0x2c/4];stats21[21]=csr[0x1c/4];stats21[23]=csr[0x28/4];
  for(unsigned i=0;i<6;i++){stats21[24+i]=csr[(0x70+4*i)/4];}
  stats21[30]=3;
 }else if(op==0x42&&base==0xe200&&count==64&&n==14){refresh21(csr);for(unsigned i=0;i<64;i++)put32_21(reply+8+i*4,stats21[i]);len=256;
 }else return V10_ARGUMENT;
 reply[0]=0x5a;reply[1]=0xa5;reply[2]=req[2];reply[3]=req[3];reply[4]=(uint8_t)op;reply[5]=0;put16_21(reply+6,len);put16_21(reply+8+len,v12_crc(reply+2,6+len));*received=len+10;return 1;
}
#define v12_virtual v21_dispatch
#include "gateway_main_async.c"
