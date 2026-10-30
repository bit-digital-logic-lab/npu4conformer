"""Actual board subgraphs: boundary transfers only, no host neural arithmetic."""
import struct,time
from collections import Counter
import numpy as np
from backend_v021 import V021Backend
from lowbit_executor import Tensor
from vm_abi import MAGIC,PARAM_BASE
from plan_metrics import delta_plan
class FusionBoard(V021Backend):
    name='V0.22 phase1 PL plans, direct DDR CONV/FFN and layout'
    def __init__(self,link,image):
        super().__init__(link,image);self.fusion_stats=Counter();self.fusion_calls=[]
        status=struct.unpack('<64I',link.request(0x42,struct.pack('<HH',0xe400,64)))
        if status[0]!=MAGIC or status[49]!=0x2201a501:raise RuntimeError('Async211 board capability required')
        if status[30]!=2201:raise RuntimeError('V022 plan ABI required')
        self.initial_vm_status=list(status)
    def fuse_plan(self,image,key,feed):
        self.require_resident();p=image.meta['v211_programs'][key];iv=p['values'][p['input_id']]['words'];ov=p['values'][p['output_id']]['words']
        shape=tuple(iv[6:6+iv[5]])
        if feed.q is None or feed.q.dtype!=np.int16 or feed.q.shape!=shape:raise ValueError('Fixed CASE input QDQ shape')
        expected=np.frombuffer(image.data,'<f4',count=1,offset=iv[2]-PARAM_BASE)[0]
        if not np.all(feed.scale_view()==expected):raise ValueError('Compiled input scale differs from graph')
        started=time.perf_counter();blob=np.ascontiguousarray(feed.q,dtype='<i2').tobytes();padding=(-len(blob))%4
        begin=time.perf_counter();self.upload21(iv[1],blob+b'\0'*padding);uploaded=time.perf_counter()-begin
        begin=time.perf_counter();saved_timeout=self.link.timeout
        try:
            self.link.timeout=5
            acknowledgement=self.link.request(0x41,struct.pack('<HHI',0xe400,1,p['address']))
            if acknowledgement:raise RuntimeError('VM START acknowledgement must be empty')
            polls=0;deadline=time.perf_counter()+180;ticket=None
            while True:
                reply=self.link.request(0x42,struct.pack('<HH',0xe400,16));polls+=1
                if len(reply)!=64:raise RuntimeError('Async reply length')
                state=struct.unpack('<16I',reply)
                if state[11]!=0x2201a501 or state[8]!=p['address']:raise RuntimeError('Async task identity')
                if ticket is None:ticket=state[10]
                if state[10]!=ticket:raise RuntimeError('Async ticket changed')
                if state[7]==4:raise RuntimeError('Deferred VM error '+str(state[9]-0x100000000 if state[9]&0x80000000 else state[9]))
                if state[7]==3:break
                if state[7] not in (1,2) or time.perf_counter()>deadline:raise RuntimeError('Async task deadline/state; NEVER replay START')
                time.sleep(.05)
        finally:self.link.timeout=saved_timeout
        board_wait=time.perf_counter()-begin
        if len(reply)!=64:raise RuntimeError('Board VM completion length')
        w=struct.unpack('<16I',reply)
        if w[0]!=MAGIC or w[2]!=self.param_state21[37] or w[3]!=len(p['ops']) or w[4]!=ov[3] or w[1]<=self.cookie21:raise RuntimeError('Stale/incomplete VM completion')
        self.cookie21=w[1]
        begin=time.perf_counter();shape=tuple(ov[6:6+ov[5]]);data=np.frombuffer(self.read21(ov[0],ov[3]*4),'<f4').reshape(shape).copy();q=scale=None
        if ov[1]:
            qbytes=ov[3]*2;raw=self.read21(ov[1],(qbytes+3)&~3);q=np.frombuffer(raw[:qbytes],'<i2').reshape(shape).copy();scale=np.frombuffer(image.data,'<f4',count=ov[11],offset=ov[2]-PARAM_BASE).copy()
            if scale.size==1:scale=scale.reshape(())
        downloaded=time.perf_counter()-begin
        entry=dict(async_polls=polls,async_ticket=ticket,key=key,kind=p['kind'],original_nodes=len(p['members']),input_bytes=len(blob),output_bytes=data.nbytes+(q.nbytes if q is not None else 0),upload_seconds=uploaded,board_wait_seconds=board_wait,read_seconds=downloaded,wall_seconds=time.perf_counter()-started,board_ticks=w[5]+(w[6]<<32),last_cookie=w[1],generation=w[2])
        self.fusion_calls.append(entry);self.fusion_stats[p['kind']]+=1
        for field in ('original_nodes','input_bytes','output_bytes','upload_seconds','board_wait_seconds','read_seconds','wall_seconds','board_ticks'):self.fusion_stats[field]+=entry[field]
        return Tensor(data,q,scale)
    def report(self):
        final=list(struct.unpack('<64I',self.link.request(0x42,struct.pack('<HH',0xe400,64))))
        r=super().report();r.update(fused_subgraphs=dict(self.fusion_stats),fusion_calls=self.fusion_calls,initial_vm_status=self.initial_vm_status,
            final_vm_status=final,plan_counter_delta=delta_plan(self.initial_vm_status,final),core_hz=125000000,
            cpu_numeric_fallback=False,conv_ffn_numeric_location='PL plan + direct DDR, PS start/completion/error only',
            matrix_statistics_scope='v021 inherited counters cover un-fused queues and all boundary DDR transfer bytes; VM stats separately cover fused queues. Do not add overlapping wall times.')
        return r
