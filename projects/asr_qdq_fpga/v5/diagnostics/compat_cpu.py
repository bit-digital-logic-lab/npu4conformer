"""OFFLINE ONLY: proposed arithmetic simulation, never deploy this CPU backend."""
import numpy as np
from numba import njit,vectorize,float32,prange,set_num_threads
from host.onnx_executor import SoftwareBackend
from compat_algorithms import CompatAlgorithms
set_num_threads(4)

@vectorize([float32(float32,float32,float32)],nopython=True,fastmath={'contract'})
def fma32(a,b,c):return a*b+c

@njit(parallel=True,fastmath={'contract'})
def gemm_fma(a,bt,block):
    m,k=a.shape;n=bt.shape[0];out=np.empty((m,n),np.float32)
    for ij in prange(m*n):
        i=ij//n;j=ij%n;total=np.float32(0)
        for start in range(0,k,block):
            acc=np.float32(0)
            for depth in range(start,min(start+block,k)):
                acc=acc+a[i,depth]*bt[j,depth]
            total=total+acc
        out[i,j]=total
    return out

@njit(parallel=True)
def gemm_m1(a,bt):
    k=a.shape[1];n=bt.shape[0];out=np.empty((1,n),np.float32)
    for j in prange(n):
        total=np.float32(0);start=0
        while start<k:
            width=4 if k-start>=4 else 2 if k-start>=2 else 1
            part=np.float32(a[0,start]*bt[j,start])
            for depth in range(start+1,start+width):part=np.float32(part+np.float32(a[0,depth]*bt[j,depth]))
            total=np.float32(part+total);start+=width
        out[0,j]=total
    return out

class CompatCpuBackend(CompatAlgorithms,SoftwareBackend):
    name='OFFLINE-compat-diagnostic';hardware_executed=False
    def fma(self,a,b,c):return np.asarray(fma32(np.asarray(a,np.float32),np.asarray(b,np.float32),np.asarray(c,np.float32)),np.float32)
    def unary(self,op,x):
        if op=='Sigmoid':return self.sigmoid_compat(x)
        return super().unary(op,x)
    def matmul_f32(self,a,b):
        a=np.asarray(a,np.float32);b=np.asarray(b,np.float32)
        av=a.ndim==1;bv=b.ndim==1
        if av:a=a[None,:]
        if bv:b=b[:,None]
        batch=np.broadcast_shapes(a.shape[:-2],b.shape[:-2]);m,k=a.shape[-2:];n=b.shape[-1]
        aa=np.broadcast_to(a,batch+(m,k));bb=np.broadcast_to(b,batch+(k,n));out=np.empty(batch+(m,n),np.float32)
        block=128;stride_n=128
        if n<k:
            while stride_n>16 and stride_n//2>=n:stride_n//=2;block*=2
        for index in np.ndindex(batch):
            left=np.ascontiguousarray(aa[index]);right=np.ascontiguousarray(bb[index].T)
            out[index]=gemm_m1(left,right) if m==1 else gemm_fma(left,right,block)
        if av:out=np.squeeze(out,-2)
        if bv:out=np.squeeze(out,-1)
        return out
    def mean_qdq(self,x,axis):
        return np.mean(x,axis=tuple(range(axis,x.ndim)),keepdims=True,dtype=np.float64).astype(np.float32)
    def sum_squares8(self,x,axis):
        rows=x.reshape(-1,int(np.prod(x.shape[axis:])));s=np.zeros((len(rows),8),np.float32)
        for i in range(0,rows.shape[1],8):s=fma32(rows[:,i:i+8],rows[:,i:i+8],s)
        r=s[:,:4]+s[:,4:]
        total=(r[:,0]+r[:,2])+(r[:,1]+r[:,3])
        return total.reshape(x.shape[:axis]+(1,)*(x.ndim-axis))
    def lane_sum16(self,x,axis):
        axis%=x.ndim;moved=np.moveaxis(x,axis,-1);rows=moved.reshape(-1,moved.shape[-1]);s=np.zeros((len(rows),16),np.float32)
        for i in range(0,rows.shape[1],16):
            count=min(16,rows.shape[1]-i);s[:,:count]+=rows[:,i:i+count]
        r=s[:,:8]+s[:,8:]
        total=((r[:,0]+r[:,1])+(r[:,2]+r[:,3]))+((r[:,4]+r[:,5])+(r[:,6]+r[:,7]))
        return np.moveaxis(total.reshape(moved.shape[:-1]+(1,)),-1,axis)
    def scale_power_two(self,p,m):
        return np.ldexp(p,m.astype(np.int32)).astype(np.float32)
