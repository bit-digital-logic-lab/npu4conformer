/* Only transport scheduling changes. Single A53, no threads/interrupt handler.
 * START ACK is transmitted before compute. During compute only bounded READ
 * E400 queries are serviced; never mutating/model/arithmetic requests. */
static volatile uint32_t async_state,async_program,async_ticket;
static int async_error;
static uint32_t async_query_count,async_servicing;
static uint64_t async_query_ticks;
static volatile uint32_t *const async_mb=(void *)0xa4000000ULL;
#define ASYNC_MAGIC 0x2201a501u
static int vm211_dispatch(const struct v10_io *io,const uint8_t *req,size_t n,uint8_t *reply,size_t *received){
 (void)io;
 if(n<14||req[0]!=0xa5||req[1]!=0x5a||req[5]||n!=10u+get16_21(req+6)||v12_crc(req+2,n-4)!=get16_21(req+n-2))return V10_CRC;
 unsigned op=req[4],count=get16_21(req+10);uint32_t words[64];unsigned length=0;
 volatile uint32_t *csr=(void *)0xa8000000ULL;
 if(csr[0]!=0xa51a21c1u||csr[0x88/4]!=0x10102131u)return V10_ID;
 if(op==0x41&&count==1&&n==18){
  if(async_state==1||async_state==2)return V10_BUSY;
  if(async_ticket==0xffffffffu)return V10_ARGUMENT;
  async_program=get32_21(req+12);async_ticket++;async_error=0;async_state=1;
  length=0; /* queued only; no neural execution before ACK */
 }else if(op==0x42&&count==16&&n==14){
  uint32_t all[64];vm211_status(all);for(unsigned i=0;i<16;i++)words[i]=all[32+i];
  words[7]=async_state;words[8]=async_program;words[9]=(uint32_t)async_error;
  words[10]=async_ticket;words[11]=ASYNC_MAGIC;length=64;
 }else if(op==0x42&&count==64&&n==14){
  vm211_status(words);words[49]=ASYNC_MAGIC;words[50]=async_state;words[51]=async_program;
  words[52]=(uint32_t)async_error;words[53]=async_ticket;words[54]=async_query_count;
  words[55]=(uint32_t)async_query_ticks;words[56]=(uint32_t)(async_query_ticks>>32);length=256;
 }else return V10_ARGUMENT;
 reply[0]=0x5a;reply[1]=0xa5;reply[2]=req[2];reply[3]=req[3];reply[4]=(uint8_t)op;reply[5]=0;put16_21(reply+6,length);
 for(unsigned i=0;i<length/4;i++)put32_21(reply+8+4*i,words[i]);
 put16_21(reply+8+length,v12_crc(reply+2,6+length));*received=10+length;return 1;
}
void vm211_service_queries(void){
 if(async_state!=2||async_servicing||!(async_mb[1]&1))return;
 async_servicing=1;uint64_t begin=ticks21();uint32_t reqwords[4],replywords[67];
 uint8_t *req=(void *)reqwords,*reply=(void *)replywords;unsigned n=async_mb[2];size_t got=0;int rc=V10_ARGUMENT;
 /* Never read more than this fixed query frame, nor execute a mutating opcode. */
 if(n==14){for(unsigned i=0;i<4;i++)reqwords[i]=async_mb[0x400+i];
  if(req[4]==0x42&&get16_21(req+8)==0xe400&&(get16_21(req+10)==16||get16_21(req+10)==64))rc=vm211_dispatch(0,req,n,reply,&got);
 }
 if(rc!=1){
  reply[0]=0x5a;reply[1]=0xa5;reply[2]=n==14?req[2]:0;reply[3]=n==14?req[3]:0;
  reply[4]=n==14?req[4]:0;reply[5]=1;put16_21(reply+6,0);put16_21(reply+8,v12_crc(reply+2,6));got=10;
 }
 for(size_t i=got;i<((got+3)&~(size_t)3);i++)reply[i]=0;
 for(size_t i=0;i<(got+3)/4;i++)async_mb[0x800+i]=replywords[i];
 async_mb[4]=(uint32_t)got;fence21();async_mb[5]=1;fence21();
 async_query_count++;async_query_ticks+=ticks21()-begin;async_servicing=0;
}
static void vm211_async_idle(const struct v10_io *io){
 if(async_state!=1)return;
 async_state=2;uint32_t completion[16];int rc=vm211_run(io,async_program,completion);
 async_error=rc;async_state=rc?4:3;
}
