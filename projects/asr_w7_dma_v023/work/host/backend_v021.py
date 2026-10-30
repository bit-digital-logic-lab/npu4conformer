"""Static matrix B=committed DRAM address; exact dynamic INT16 path unchanged."""
import hashlib,struct,time
from collections import Counter
import numpy as np
from base_v021 import V021Base,dynamic_pack_task,BASE,END,align,tiles
from layout import block_bytes
from parameters import ParameterTransport

def resident_pack_task(a,view,positions,clip,first_cookie):
    if not isinstance(view,dict):return dynamic_pack_task(a,view,positions,clip,first_cookie)
    if a.dtype!=np.int16 or a.ndim!=2:raise ValueError('A16 matrix required')
    m,k=a.shape;n=view['n'];chunks=(k+4095)//4096
    if k!=view['k'] or not 1<=m<=4096 or not 1<=n<=4096 or not 1<=chunks<=4096 or first_cookie<1 or first_cookie+chunks>0xffffffff:raise ValueError('Resident dimensions/cookie')
    if tuple(positions)!=tuple(view['positions_lsb']) or not clip:raise ValueError('Resident W7 encoding provenance')
    descriptor=bytearray(chunks*64);cursor=BASE+align(len(descriptor));segments=[];addresses=[]
    for start in range(0,k,4096):
        blob=block_bytes(a[:,start:start+4096]);abase=cursor;segments.append((cursor,blob));cursor+=len(blob)
        bbase=view['address']+(start//32)*view['nt']*1024
        depth=min(4096,k-start)
        if bbase+tiles(depth)*view['nt']*1024>view['address']+view['bytes']:raise ValueError('Static B slice bounds')
        addresses.append((abase,bbase,depth))
    cbase=cursor;cbytes=tiles(m)*tiles(n)*6144
    if cbase+cbytes>END:raise ValueError('Resident A/C mutable arena capacity')
    table=sum(int(p)<<(4*i) for i,p in enumerate(positions))|(1<<16)
    for index,(abase,bbase,depth) in enumerate(addresses):
        cookie=first_cookie+index
        words=(0x51415352,(21<<16)|1,cookie,0xffffffff if index==0 else index-1,abase,bbase,cbase,m,n,depth,cookie,(view['id']<<16)|7,(3<<16)|2,table,1<<16,0 if index==0 else (1<<16)|1)
        struct.pack_into('<16I',descriptor,index*64,*words)
    layout=dict(m=m,k=k,n=n,mt=tiles(m),nt=tiles(n),kt=tiles(k),cbase=cbase,cbytes=cbytes,queue_base=BASE,queue_count=chunks,last_cookie=first_cookie+chunks-1,
        uploaded_bytes=len(descriptor)+sum(len(b) for _,b in segments),extent_bytes=cbase+cbytes-BASE,alignment_gap_not_uploaded=align(len(descriptor))-len(descriptor),
        expected_compute_cycles=tiles(m)*tiles(n)*tiles(k)*264,expected_read_bytes=64*chunks+tiles(m)*tiles(n)*tiles(k)*3072+(chunks-1)*cbytes,expected_write_bytes=chunks*cbytes,
        static_parameter_upload_bytes=0,param_B_address=view['address'],param_id=view['id'])
    return [(BASE,bytes(descriptor)),*segments],layout

class V021Backend(V021Base):
    pack_task=staticmethod(resident_pack_task)
    name='V21 DRAM-resident W7 + autonomous queues + unchanged V13 PL nonmatrix'
    def __init__(self,link,image):
        self.image=image;self.transport21=ParameterTransport(link,image);self.param_state21=self.transport21.require_ready()
        self.context21=None;self.matrix_index21=0;self.resident_stats=Counter();self.fp32_refs={}
        for r in image.meta['directory']:
            if r['kind'].startswith('static_') and r['dtype']=='<f4':self.fp32_refs.setdefault((r['bytes'],r['sha256']),r)
        self.repeat_lengths=sorted({size//4 for size,_ in self.fp32_refs if 0<size<=2048},reverse=True)
        super().__init__(link)
    def set_context(self,name):self.context21=name;self.matrix_index21=0
    def require_resident(self):
        s=self.transport21.require_ready()
        if s[37]!=self.param_state21[37]:raise RuntimeError('Parameter generation changed during run')
        return s
    def matmul_special(self,a,b,positions=None):
        if positions is None:return super().matmul_special(a,b,positions)
        self.require_resident();started=time.perf_counter();a=np.asarray(a);b=np.asarray(b)
        if a.dtype!=np.int16 or b.dtype!=np.int16:raise ValueError('Static QDQ INT16 required')
        context=self.image.meta['contexts'].get(self.context21)
        if context is None:raise RuntimeError('No resident B context: '+str(self.context21))
        m,k=a.shape[-2:];n=b.shape[-1];batch=np.broadcast_shapes(a.shape[:-2],b.shape[:-2]);aa=np.broadcast_to(a,batch+(m,k));output=np.empty(batch+(m,n),np.int64)
        for ix in np.ndindex(batch):
            ref=context['matrices'][self.matrix_index21%len(context['matrices'])];self.matrix_index21+=1
            if (ref['k'],ref['n'])!=(k,n) or tuple(ref['positions_lsb'])!=tuple(positions):raise RuntimeError('Wrong resident B shape/table')
            for view in ref['views']:
                # Fixed precompiled column window; shrink M only, never change B stride.
                fixed=align(((k+4095)//4096)*64);per_row_tile=tiles(k)*2048+tiles(view['n'])*6144
                row_step=min(4096,max(0,(END-BASE-fixed)//per_row_tile)*32,m)
                if row_step<1:raise ValueError('Resident column window cannot fit A/C')
                for row in range(0,m,row_step):
                    c=view['start_col'];result=self.native21(np.ascontiguousarray(aa[ix][row:row+row_step]),view,positions,True)
                    output[ix][row:row+result.shape[0],c:c+view['n']]=result
        self.resident_stats['static_matrix_dispatches']+=1;self.resident_stats['static_weight_runtime_encoding_calls']+=0
        self.resident_stats['parameter_upload_bytes_during_run']+=0;self.lowbit_stats['matmul_wall_seconds']+=time.perf_counter()-started
        return output
    def write_words(self,address,values):
        v=np.asarray(values,dtype='<u4').ravel();blob=v.tobytes();r=self.fp32_refs.get((len(blob),hashlib.sha256(blob).hexdigest()))
        span=v.size
        if r is None and v.size:
            for length in self.repeat_lengths:
                if length>=v.size:continue
                candidate=self.fp32_refs.get((length*4,hashlib.sha256(blob[:length*4]).hexdigest()))
                if candidate is not None and np.array_equal(v,np.resize(v[:length],v.size)):
                    r=candidate;span=length;break
        if r is not None and 0<=address<32768 and v.size and v.size<=32768-address:
            self.link.request(0x41,struct.pack('<HH4I',0xe300,4,r['address'],address,v.size,span));self.resident_stats['ddr_to_sram_copy_bytes']+=len(blob);self.resident_stats['avoided_host_parameter_bytes']+=len(blob);return
        return super().write_words(address,values)
    def report(self):
        r=super().report();r['resident_parameters']=dict(self.resident_stats);r['parameter_image_bytes']=self.image.meta['image_bytes'];r['parameter_generation']=self.param_state21[37]
        r['resident_scope']='All canonical parameters in PS DDR. Matrix B uses HP0 DMA; nonmatrix matching FP32 operands use PS DDR-to-PL SRAM copy. Host DAG/activation transport remains; not a TPU graph scheduler.'
        return r
