"""Backend-independent FP32 arithmetic sequences, pinned ORT f2c39fe.

Weights and quantization remain original INT16. All operations below delegate
to a numerical backend. Reference source/license recorded in reference/.
"""
import numpy as np

class CompatAlgorithms:
    compat_onnx=True
    def sigmoid_compat(self,x):
        x=self.binary('Min',self.binary('Max',x,np.float32(-18)),np.float32(18))
        xx=self.binary('Mul',x,x)
        alpha=np.asarray([4.37031012579801e-11,1.15627324459942e-7,6.08574864600143e-5,8.51377133304701e-3,2.48287947061529e-1],np.float32)
        beta=np.asarray([6.10247389755681e-13,5.76102136993427e-9,6.29106785017040e-6,1.70198817374094e-3,1.16817656904453e-1,9.93151921023180e-1],np.float32)
        p=alpha[0]
        for c in alpha[1:]:p=self.fma(p,xx,c)
        q=beta[0]
        for c in beta[1:]:q=self.fma(q,xx,c)
        return self.binary('Max',self.binary('Add',self.binary('Div',self.binary('Mul',p,x),q),np.float32(.5)),np.float32(0))

    def exp_softmax(self,x):
        x=self.binary('Max',x,np.float32(-88.3762626647949))
        biased=self.fma(x,np.float32(1.44269504088896341),np.float32(12582912))
        m=self.binary('Sub',biased,np.float32(12582912))
        reduced=self.fma(m,np.float32(-6.93145752e-1),x)
        reduced=self.fma(m,np.float32(-1.42860677e-6),reduced)
        coeff=np.asarray([float.fromhex(t) for t in ['0x1.694000p-10','0x1.125edcp-7','0x1.555b5ap-5','0x1.555450p-3','0x1.fffff6p-2','0x1p0','0x1p0']],np.float32)
        p=coeff[0]
        for c in coeff[1:]:p=self.fma(p,reduced,c)
        return self.scale_power_two(p,m)

    def layer_norm(self,x,gamma,beta=None,axis=-1,epsilon=1e-5):
        axis%=x.ndim;count=int(np.prod(x.shape[axis:]))
        if count!=512:raise ValueError('V5 current model contract requires LayerNorm extent 512')
        mean=self.mean_qdq(x,axis)
        centered=self.binary('Sub',x,mean)
        variance=self.binary('Div',self.sum_squares8(centered,axis),np.float32(count))
        inv=self.binary('Div',np.float32(1),self.unary('Sqrt',self.binary('Add',variance,np.float32(epsilon))))
        norm=self.binary('Mul',centered,inv)
        output=self.binary('Mul',norm,gamma) if beta is None else self.fma(norm,gamma,beta)
        return output,mean,inv

    def batch_norm(self,x,scale,bias,mean,variance,epsilon=1e-5):
        shape=(1,x.shape[1])+(1,)*(x.ndim-2)
        inv=self.binary('Div',np.float32(1),self.unary('Sqrt',self.binary('Add',variance,np.float32(epsilon))))
        new_scale=self.binary('Mul',inv,scale)
        new_bias=self.binary('Sub',bias,self.binary('Mul',mean,new_scale))
        return self.binary('Add',self.binary('Mul',x,new_scale.reshape(shape)),new_bias.reshape(shape))

    def softmax(self,x,axis=-1,logarithmic=False):
        shifted=self.binary('Sub',x,self.reduce_max(x,[axis],True))
        exp=self.exp_softmax(shifted)
        denom=self.lane_sum16(exp,axis)
        if logarithmic:
            return self.binary('Sub',shifted,self.unary('Log',denom))
        scale=self.binary('Div',np.float32(1),denom)
        return self.binary('Mul',exp,scale)
