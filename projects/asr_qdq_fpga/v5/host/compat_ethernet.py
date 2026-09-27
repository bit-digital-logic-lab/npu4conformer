"""V5 physical FPGA backend. NO CPU/ORT dynamic arithmetic fallback.

NumPy here performs representation, indexing and tensor layout only. All
dynamic add/multiply/FMA/divide/reduction operations use board commands.
"""
import struct
import numpy as np
from compat_algorithms import CompatAlgorithms
from ethernet_transport import EthernetBackend,ProtocolError,v1,v2

words=v2.float_words

class CompatEthernetBackend(CompatAlgorithms,EthernetBackend):
    name='hardware-v5-onnx-compatible'
    def __init__(self,link):
        super().__init__(link)
        if link.request(0x4f)!=struct.pack('<4sII',b'ASR5',5,32768):
            raise ProtocolError('V5 numerical capability required; never run on old RTL')

    def _many_execute(self,commands):
        for first in range(0,len(commands),60):
            batch=commands[first:first+60]
            for command,reply in zip(batch,self.link.request_many(batch)):
                if len(reply)!=5:raise ProtocolError('V5 execution response size')
                flags,cycles=struct.unpack('<BI',reply);op=command[0]
                self.arithmetic_flags[flags]+=1;self.execution_calls[op]+=1;self.execution_cycles[op]+=cycles
                if flags&7:raise ArithmeticError(f'FPGA command {op:x}: flags={flags:x}')

    @staticmethod
    def _vc(op,a,b,d,n,mode=0):
        return (0x43,struct.pack('<BBHHHH',v1.SCALAR[op] if isinstance(op,str) else op,mode,a,b,d,n))

    def fma_words(self,a,b,c,d,count,mode=0):
        if not 0<=mode<8 or count<1:raise ValueError('FMA count/mode')
        self._range(d,count)
        for i,base in enumerate((a,b,c)):
            broadcast=(mode>>i)&1;extent=1 if broadcast else count;self._range(base,extent)
            if d<base+extent and base<d+count and (broadcast or d!=base):raise ValueError('FMA partial/broadcast alias')
        return self._execution(0x47,struct.pack('<5HB',a,b,c,d,count,mode))

    def fma(self,a,b,c):
        arrays=np.broadcast_arrays(np.asarray(a,np.float32),np.asarray(b,np.float32),np.asarray(c,np.float32))
        flat=[words(x) for x in arrays];scalars=[np.size(x)==1 for x in (a,b,c)]
        output=np.empty(flat[0].size,np.uint32)
        for start in range(0,len(output),8192):
            count=min(8192,len(output)-start)
            for i in range(3):self.write_words(i*count,flat[i][start:start+(1 if scalars[i] else count)])
            self.fma_words(0,count,2*count,3*count,count,sum(int(s)<<i for i,s in enumerate(scalars)))
            output[start:start+count]=self.read_words(3*count,count)
        return output.view(np.float32).reshape(arrays[0].shape)

    def binary(self,op,a,b):
        if op=='Min':
            return self.unary('Neg',super().binary('Max',self.unary('Neg',a),self.unary('Neg',b)))
        return super().binary(op,a,b)

    def unary(self,op,x):
        if op=='Sigmoid':return self.sigmoid_compat(x)
        return super().unary(op,x)

    def mm_f32_tile(self,a,bt,c,m,n,k,accumulate=False):
        for base,count in ((a,m*k),(bt,n*k),(c,m*n)):self._range(base,count)
        if min(m,n,k)<1:raise ValueError('FMA GEMM dimensions')
        for base,count in ((a,m*k),(bt,n*k)):
            if c<base+count and base<c+m*n:raise ValueError('FMA GEMM overlap')
        return self._execution(0x46,struct.pack('<7H',a,bt,c,m,n,k,int(accumulate)))

    def _matmul_m1(self,a,b):
        # MLAS M=1 uses separate MUL then ADD in groups of 4, 2, 1.
        # All weights/activations and group sums remain in SRAM for each tile.
        k=a.shape[-1];n=b.shape[-1];out=np.empty((1,n),np.uint32)
        tile=min(128,(32768-k)//(k+3))
        if tile<1:raise ValueError('M1 contraction exceeds resident implementation capacity')
        for col in range(0,n,tile):
            nc=min(tile,n-col);baseb=k;partial=k+k*nc;term=partial+nc;total=term+nc
            self.write_words(0,words(a));self.write_words(baseb,words(b[:,col:col+nc]))
            self.write_words(total,np.zeros(nc,np.uint32));cmds=[];start=0
            while start<k:
                width=4 if k-start>=4 else 2 if k-start>=2 else 1
                cmds.append(self._vc('Mul',start,baseb+start*nc,partial,nc,1))
                for d in range(start+1,start+width):
                    cmds.extend([self._vc('Mul',d,baseb+d*nc,term,nc,1),self._vc('Add',partial,term,partial,nc)])
                cmds.append(self._vc('Add',partial,total,total,nc));start+=width
            self._many_execute(cmds);out[0,col:col+nc]=self.read_words(total,nc)
        return out.view(np.float32)

    def matmul_f32(self,a,b):
        a=np.asarray(a,np.float32);b=np.asarray(b,np.float32);av=a.ndim==1;bv=b.ndim==1
        if av:a=a[None,:]
        if bv:b=b[:,None]
        m,k=a.shape[-2:];n=b.shape[-1]
        if k!=b.shape[-2] or min(m,n,k)<1:raise ValueError('V5 matrix shape')
        batch=np.broadcast_shapes(a.shape[:-2],b.shape[:-2]);aa=np.broadcast_to(a,batch+(m,k));bb=np.broadcast_to(b,batch+(k,n))
        out=np.empty(batch+(m,n),np.float32)
        block=128;stride_n=128
        if n<k:
            while stride_n>16 and stride_n//2>=n:stride_n//=2;block*=2
        tk=min(block,k);tm=min(31,m,max(1,8192//tk));tn=min(64,n,max(1,(32768-tm*tk)//(tk+tm)))
        for index in np.ndindex(batch):
            if m==1:out[index]=self._matmul_m1(aa[index],bb[index]);continue
            for row in range(0,m,tm):
                mr=min(tm,m-row)
                for col in range(0,n,tn):
                    nc=min(tn,n-col);baseb=mr*tk;based=baseb+nc*tk
                    for depth in range(0,k,block):
                        kc=min(block,k-depth)
                        self.write_words(0,words(aa[index+(slice(row,row+mr),slice(depth,depth+kc))]))
                        self.write_words(baseb,words(bb[index+(slice(depth,depth+kc),slice(col,col+nc))].T))
                        self.mm_f32_tile(0,baseb,based,mr,nc,kc,depth!=0)
                    out[index+(slice(row,row+mr),slice(col,col+nc))]=self.read_words(based,mr*nc).view(np.float32).reshape(mr,nc)
        if av:out=np.squeeze(out,-2)
        if bv:out=np.squeeze(out,-1)
        return out

    def mean_qdq(self,x,axis):
        count=int(np.prod(x.shape[axis:]));rows=x.reshape(-1,count);out=np.empty(len(rows),np.uint32)
        if count!=512:raise ValueError('V5 exact QDQ mean requires 512')
        # Group rows in SRAM, preserving exact hardware range checks per row.
        for start in range(0,len(rows),60):
            group=rows[start:start+60];dest=group.size;self.write_words(0,words(group))
            self._many_execute([(0x48,struct.pack('<3H',i*count,dest+i,count)) for i in range(len(group))])
            out[start:start+len(group)]=self.read_words(dest,len(group))
        return out.view(np.float32).reshape(x.shape[:axis]+(1,)*(x.ndim-axis))

    def sum_squares8(self,x,axis):
        count=int(np.prod(x.shape[axis:]));rows=x.reshape(-1,count);out=np.empty((len(rows),8),np.uint32)
        if count%8:raise ValueError('FMA8 requires divisible extent')
        depth=count//8
        for i,row in enumerate(rows):
            # Independent dot products for the 8 original SIMD lanes.
            self.write_words(0,words(row.reshape(-1,8).T));dest=count
            self._many_execute([(0x46,struct.pack('<7H',lane*depth,lane*depth,dest+lane,1,1,depth,0)) for lane in range(8)])
            out[i]=self.read_words(dest,8)
        s=out.view(np.float32);r=self.binary('Add',s[:,:4],s[:,4:])
        total=self.binary('Add',self.binary('Add',r[:,0],r[:,2]),self.binary('Add',r[:,1],r[:,3]))
        return total.reshape(x.shape[:axis]+(1,)*(x.ndim-axis))

    def lane_sum16(self,x,axis):
        axis%=x.ndim;moved=np.moveaxis(x,axis,-1);rows=moved.reshape(-1,moved.shape[-1]);out=np.zeros((len(rows),16),np.uint32)
        count=rows.shape[1];depth=(count+15)//16
        for i,row in enumerate(rows):
            layout=np.zeros((depth,16),np.float32);layout.reshape(-1)[:count]=row
            self.write_words(0,words(layout.T));dest=depth*16
            self._many_execute([(0x44,struct.pack('<BBHHH',0,0,lane*depth,dest+lane,depth)) for lane in range(16)])
            out[i]=self.read_words(dest,16)
        s=out.view(np.float32);r=self.binary('Add',s[:,:8],s[:,8:])
        a=self.binary('Add',r[:,0::2],r[:,1::2]);b=self.binary('Add',a[:,0::2],a[:,1::2]);total=self.binary('Add',b[:,0],b[:,1])
        return np.moveaxis(total.reshape(moved.shape[:-1]+(1,)),-1,axis)

    def scale_power_two(self,p,m):
        pp,mm=np.broadcast_arrays(p,m);pv=words(pp);mv=words(mm);out=np.empty(pv.size,np.uint32)
        for start in range(0,len(out),8192):
            count=min(8192,len(out)-start);self.write_words(0,pv[start:start+count]);self.write_words(count,mv[start:start+count])
            self.vec('ToI32',count,count,count,count)
            self._execution(0x43,struct.pack('<BBHHHH',16,0,0,count,0,count))
            out[start:start+count]=self.read_words(0,count)
        return out.view(np.float32).reshape(pp.shape)

    def report(self):
        result=super().report();result.update(numerical_backend='V5 physical FMA/MLAS sequences; original INT16 QDQ graph',compat_onnx=True,cpu_numeric_fallback=False)
        return result
