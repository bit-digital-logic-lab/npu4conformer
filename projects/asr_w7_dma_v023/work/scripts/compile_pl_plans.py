"""Lower sealed CONV/FFN schedules to immutable PL plans. No FP calculation here.

All coefficient copies/padding are byte operations; SX*SW, C48 conversion, Q/DQ,
sigmoid (same ordered vendor FMAs), and bias are instructions for the PL.
Original parameter/program addresses remain valid. New image is a distinct file.
"""
import hashlib,json,struct,sys,zlib
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1];BASE=ROOT.parent/'model_a_v0_21_1'
sys.path.insert(0,str(BASE/'host'))
from parameters import ParameterImage
old=ParameterImage(BASE/'assets/parameters003')
tag=sys.argv[1] if len(sys.argv)>1 else 'parameters001'
if not tag.replace('_','').isalnum():raise ValueError('Safe tag')
out=ROOT/'assets'/tag;out.mkdir(parents=True,exist_ok=False)
meta=json.loads(json.dumps(old.meta));image=bytearray(old.data);programs={};records=[]
PB=meta['param_base'];SB=0x03000000;VE=0x08000000
align=lambda n,a=64:(n+a-1)//a*a
tiles=lambda n:(n+31)//32
def append(name,data):
    image.extend(bytes(align(len(image))-len(image)));offset=len(image);image.extend(data)
    r=dict(name='v022/'+name,id=len(meta['directory'])+len(records)+1,offset=offset,address=PB+offset,bytes=len(data),dtype='uint8',shape=[len(data)],sha256=hashlib.sha256(data).hexdigest(),kind='v022_schedule')
    records.append(r);return r['address']
def words_at(address,count):return struct.unpack_from('<'+str(count)+'I',old.data,address-PB)
def packed_words(words):return struct.pack('<'+str(len(words))+'I',*words)
for key,p in meta['v211_programs'].items():
    values=[v['words'] for v in p['values']];ops=p['ops'];instructions=[];matrix_tasks=0;compact_saved=0
    largest=max(v[3]*4 for v in values if not v[10]&1)
    for op in ops:
        if op[0]<=2:
            cfg=words_at(op[5],op[6]);largest=max(largest,tiles(cfg[3])*tiles(cfg[5])*4096)
    width=align(largest);temp_base=align(0x04000000+p['extent_bytes'],4096)
    temps=[temp_base+i*width for i in range(6)]
    if temps[-1]+width>VE:raise ValueError('Temporary liveness arena overflow '+key)
    constants=meta['v211_algorithm_constants_address']
    def emit(kind,data):
        pointer=append(f'{key}/payload{len(instructions):05d}',data)
        instructions.append([0x22504c4e,kind,len(instructions)+1,len(instructions)-1 if instructions else 0xffffffff,pointer,len(data)]+[0]*10)
    def vector(op,a,b,d,n,*,a16=False,out16=False,bs=False,as_=False,c=0,cs=False,a48=False,period=0,tiled=False):
        flags=op|(int(a16)<<8)|(int(out16)<<9)|(int(bs)<<10)|(int(as_)<<11)|(int(cs)<<12)|(int(a48)<<13)|(int(tiled)<<14)
        emit(2,packed_words([0x22564543,flags,a,b,c,d,n,period]+[0]*8))
    def layout(mode,a,d,count,bytes,m=0,n=0,full=0,start=0,conv=None,koff=0):
        w=[0x224c4159,mode,a,d,count,bytes,m,n,full,start]+[0]*22
        if conv:w[10:24]=[conv[7]//conv[21],conv[8],conv[9],conv[11],conv[12],conv[13],conv[14],conv[15],conv[16],conv[17],conv[18],conv[19],conv[20],koff]
        else:w[23]=koff
        emit(3,packed_words(w))
    def move(a,d,n,bytes=4):layout(0,a,d,n,bytes)
    def coefficient(address,count,start,n,label):
        if count==1:return address,True
        if n%32==0:return address+start*4,False
        # Copy exact FP32 bits and zero-pad storage only; never compute the scale.
        data=bytes(old.data[address-PB+start*4:address-PB+(start+n)*4])+bytes((align(n,32)-n)*4)
        return append(f'{key}/{label}_{len(instructions):05d}',data),False
    for opindex,op in enumerate(ops):
        kind,did,aid,bid=op[:4];d=values[did];a=values[aid]
        if kind<=2:
            cfg=words_at(op[5],op[6]);m,k,fulln=cfg[3:6];parts=(k+4095)//4096
            refs=[cfg[29+i*12:41+i*12] for i in range(cfg[28])]
            total=len(refs)*parts;cursor=align(SB+total*64);queue=[];cblocks=[]
            for refindex,r in enumerate(refs):
                n,nt=r[3:5];abytes=sum(tiles(m)*tiles(min(4096,k-part*4096))*2048 for part in range(parts));cbase=cursor+abytes
                if cbase+tiles(m)*nt*6144>0x03d00000:raise ValueError('Matrix arena overflow '+key)
                cblocks.append(cbase)
                for part in range(parts):
                    depth=min(4096,k-part*4096);count=tiles(m)*tiles(depth)*1024;abase=cursor
                    source=a[1]+(r[8]*(cfg[7]//cfg[21])*cfg[8]*cfg[9]*2 if cfg[0] else 0)
                    layout(2 if cfg[0] else 1,source,abase,count,2,m,depth,k,conv=cfg if cfg[0] else None,koff=part*4096)
                    index=refindex*parts+part;epoch=index+1
                    queue.append([0x51415352,(21<<16)|1,epoch,index-1 if part else 0xffffffff,abase,r[0]+(part*4096//32)*nt*1024,cbase,m,n,depth,epoch,(r[1]<<16)|7,(3<<16)|2,r[7]|(1<<16),1<<16,0x10001 if part else 0])
                    cursor+=tiles(m)*tiles(depth)*2048
                cursor=cbase+tiles(m)*nt*6144
            address=append(f'{key}/matrix_queue_{opindex}',b''.join(packed_words(q) for q in queue))
            # Queue DMA currently admits scratch-only descriptors. Copy by PL, not PS.
            move(address,SB,total*16)
            instructions.append([0x22504c4e,1,len(instructions)+1,len(instructions)-1,SB,total]+[0]*10)
            matrix_tasks+=total
            for i,r in enumerate(refs):
                n=r[3];column=r[8]*fulln+r[6];physical=tiles(m)*tiles(n)*1024
                sw,scalar=coefficient(cfg[24],cfg[25],column,n,f'sw{opindex}_{i}')
                vector(2,cfg[22],sw,temps[1],1 if scalar else align(n,32),as_=True,bs=scalar)
                compact=n==1 and cfg[1]>1
                if compact:
                    # Depthwise epilogue touches M valid elements, not padded 32x32.
                    layout(3,cblocks[i],temps[3],m,6,m,1,1)
                    vector(14,temps[3],0,temps[0],m,a48=True)
                    vector(2,temps[0],temps[1],temps[2],m,bs=True)
                    current=temps[2]
                    if cfg[26]:vector(0,current,cfg[26]+column*4,temps[0],m,bs=True);current=temps[0]
                    move(current,d[0]+column*m*4,m)
                    compact_saved+=physical-m
                else:
                    vector(14,cblocks[i],0,temps[0],physical,a48=True)
                    vector(2,temps[0],temps[1],temps[2],physical,bs=scalar,period=0 if scalar else n,tiled=not scalar)
                    current=temps[2]
                    if cfg[26]:
                        bias,bs=coefficient(cfg[26],cfg[27],column,n,f'bias{opindex}_{i}')
                        vector(0,current,bias,temps[0],physical,bs=bs,period=0 if bs else n,tiled=not bs);current=temps[0]
                    layout(4 if cfg[0] else 3,current,d[0],m*n,4,m,n,cfg[1]*fulln if cfg[0] else fulln,column if cfg[0] else r[6])
        elif kind==5:
            b=values[bid];vector(3,a[0],b[0],temps[0],d[3],bs=b[3]==1,period=b[3] if b[3]>1 and b[3]!=d[3] else 0)
            vector(15,temps[0],0,d[0],d[3],out16=True)
        elif kind==6:
            b=values[bid];vector(7,a[0],0,temps[0],d[3],a16=True)
            vector(2,temps[0],b[0],d[0],d[3],bs=b[3]==1,period=b[3] if b[3]>1 and b[3]!=d[3] else 0)
        elif kind in (3,4,8):
            b=values[bid] if kind!=8 else [constants+12,0,0,1]
            # ADD/MUL are commutative for accepted finite operands. Keep the
            # full-sized operand in A so B-period implements the original
            # vm211 modulo broadcast (bias is sometimes the left operand).
            if kind in (3,4) and 1<a[3]<d[3]:
                if b[3]!=d[3]:raise ValueError('Both operands require non-scalar broadcast')
                a,b=b,a
            vector({3:0,4:2,8:9}[kind],a[0],b[0],d[0],d[3],bs=b[3]==1,as_=a[3]==1,period=b[3] if b[3]>1 and b[3]!=d[3] else 0)
        elif kind==7:
            # Exact order from sealed vm211.c, including sign/max clamp and FMAs.
            x,xx,num,den,tmp,spare=temps;n=d[3]
            vector(9,a[0],constants,x,n,bs=True)
            vector(13,x,0,spare,n);vector(13,constants+4,0,tmp,1)
            vector(9,spare,tmp,x,n,bs=True);vector(13,x,0,spare,n);x,spare=spare,x
            vector(2,x,x,xx,n)
            vector(17,constants+16,xx,num,n,as_=True,c=constants+20,cs=True)
            for j in range(6,9):vector(17,num,xx,spare,n,c=constants+j*4,cs=True);num,spare=spare,num
            vector(17,constants+36,xx,den,n,as_=True,c=constants+40,cs=True)
            for j in range(11,15):vector(17,den,xx,spare,n,c=constants+j*4,cs=True);den,spare=spare,den
            vector(2,num,x,tmp,n);vector(3,tmp,den,num,n)
            vector(0,num,constants+8,tmp,n,bs=True);vector(9,tmp,constants+12,d[0],n,bs=True)
        else:raise ValueError('Unknown numeric op '+str(kind))
    if len(instructions)>65535:raise ValueError('Plan length bound')
    address=append(f'{key}/plan',b''.join(packed_words(x) for x in instructions))
    programs[key]=dict(part=p['part'],name=p['name'],kind=p['kind'],original_program_address=p['address'],plan_address=address,plan_count=len(instructions),matrix_tasks=matrix_tasks,input_id=p['input_id'],output_id=p['output_id'],output_address=values[p['output_id']][0],input_q_address=values[p['input_id']][1],temp_base=temp_base,temp_width=width,temp_end=temps[-1]+width,depthwise_padding_elements_avoided=compact_saved)
    print(p['kind'],p['name'],len(instructions),'instructions',matrix_tasks,'matrix descriptors',flush=True)
image.extend(bytes(align(len(image),256)-len(image)));meta['directory'].extend(records)
struct.pack_into('<II',image,16,len(image),len(meta['directory']))
meta.update(version_label='V0.22 PL schedule candidate',image_bytes=len(image),image_crc32=zlib.crc32(image),image_sha256=hashlib.sha256(image).hexdigest(),v022_programs=programs,v022_scope='68 closed CONV/FFN programs only; outer DAG still legacy host. Integer matrix storage not yet pipelined. NOT hardware tested.')
(out/'parameters.bin').write_bytes(image);(out/'manifest.json').write_text(json.dumps(meta,indent=2)+'\n',encoding='utf-8')
result=dict(hardware_accessed=False,original_image_sha256=old.meta['image_sha256'],image_sha256=meta['image_sha256'],image_bytes=len(image),added_bytes=len(image)-old.meta['image_bytes'],programs=len(programs),instructions=sum(p['plan_count'] for p in programs.values()),matrix_descriptors=sum(p['matrix_tasks'] for p in programs.values()),depthwise_padding_elements_avoided=sum(p['depthwise_padding_elements_avoided'] for p in programs.values()),original_payload_unchanged=image[256:len(old.data)]==old.data[256:],source_sha256=hashlib.sha256(Path(__file__).read_bytes()).hexdigest())
(out/'compile_result.json').write_text(json.dumps(result,indent=2)+'\n',encoding='utf-8')
ParameterImage(out)
print('V022_STATIC_PLAN_COMPILE_PASS',json.dumps(result))
