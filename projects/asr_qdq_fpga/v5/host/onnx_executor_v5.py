"""V5 QDQ-compatible scheduler. Host only indexes; backend owns arithmetic."""
import numpy as np
import onnx
from frozen_imports import require_frozen_modules
_,_,baseline=require_frozen_modules()
from host.onnx_executor import Tensor,ExecutionError

class OnnxExecutor(baseline.OnnxExecutor):
    @staticmethod
    def _matmul(a,b,backend):
        if not getattr(backend,'compat_onnx',False):
            return baseline.OnnxExecutor._matmul(a,b,backend)
        if a.q is None or b.q is None:
            raise ExecutionError('V5 weighted operation still requires original INT16 QDQ provenance')
        return Tensor(backend.matmul_f32(a.data,b.data))

    def _conv(self,args,attr,backend):
        if not getattr(backend,'compat_onnx',False):
            return super()._conv(args,attr,backend)
        x,w=args[:2]
        if x.q is None or w.q is None:raise ExecutionError('Conv requires QDQ provenance')
        rank=x.data.ndim-2
        if rank not in (1,2) or attr.get('auto_pad',b'NOTSET') not in (b'NOTSET',b''):
            raise ExecutionError('Unsupported V5 Conv layout')
        strides=attr.get('strides',[1]*rank);dilation=attr.get('dilations',[1]*rank)
        pads=attr.get('pads',[0]*(rank*2));groups=attr.get('group',1)
        batch,channels=x.data.shape[:2];outchannels,local=w.data.shape[:2]
        if local*groups!=channels or outchannels%groups:raise ExecutionError('Bad Conv groups')
        kernel=w.data.shape[2:]
        outshape=tuple((x.data.shape[i+2]+pads[i]+pads[i+rank]-dilation[i]*(kernel[i]-1)-1)//strides[i]+1 for i in range(rank))
        padded=np.pad(x.data,[(0,0),(0,0)]+[(pads[i],pads[i+rank]) for i in range(rank)])
        positions=list(np.ndindex(outshape));result=np.empty((batch,outchannels)+outshape,np.float32)
        for bi in range(batch):
            for gi in range(groups):
                patches=np.empty((local*int(np.prod(kernel)),len(positions)),np.float32)
                for pi,position in enumerate(positions):
                    slices=tuple(slice(position[i]*strides[i],position[i]*strides[i]+dilation[i]*(kernel[i]-1)+1,dilation[i]) for i in range(rank))
                    patches[:,pi]=padded[(bi,slice(gi*local,(gi+1)*local))+slices].ravel()
                cs=slice(gi*(outchannels//groups),(gi+1)*(outchannels//groups))
                result[bi,cs]=backend.matmul_f32(w.data[cs].reshape(outchannels//groups,-1),patches).reshape((outchannels//groups,)+outshape)
        if len(args)>2 and args[2] is not None:
            result=backend.binary('Add',result,args[2].data.reshape((1,outchannels)+(1,)*rank))
        return Tensor(result)

    def _eval(self,node,args,backend):
        if not getattr(backend,'compat_onnx',False):return super()._eval(node,args,backend)
        attr={a.name:onnx.helper.get_attribute_value(a) for a in node.attribute}
        if node.op_type=='LayerNormalization':
            vals=backend.layer_norm(args[0].data,args[1].data,args[2].data if len(args)>2 else None,
                                    attr.get('axis',-1),attr.get('epsilon',1e-5))
            return [Tensor(v) for v in vals[:len(node.output)]]
        if node.op_type=='BatchNormalization':
            if attr.get('training_mode',0):raise ExecutionError('Training BN not supported')
            return Tensor(backend.batch_norm(*(a.data for a in args),epsilon=attr.get('epsilon',1e-5)))
        if node.op_type in ('Softmax','LogSoftmax'):
            return Tensor(backend.softmax(args[0].data,attr.get('axis',-1),node.op_type=='LogSoftmax'))
        return super()._eval(node,args,backend)
