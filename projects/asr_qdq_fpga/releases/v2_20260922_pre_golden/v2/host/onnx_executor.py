"""V2 scheduler extension; V1 scheduler/model files remain unmodified."""
import numpy as np
import onnx
from host.onnx_executor import OnnxExecutor as V1Executor, SoftwareBackend, Tensor, ExecutionError


class OnnxExecutor(V1Executor):
    def _eval(self, node, args, backend):
        if getattr(backend, "resident_operators", False):
            attr = {a.name: onnx.helper.get_attribute_value(a) for a in node.attribute}
            if node.op_type in ("Softmax", "LogSoftmax"):
                return Tensor(backend.softmax(args[0].data, attr.get("axis", -1), node.op_type == "LogSoftmax"))
            if node.op_type == "LayerNormalization":
                if attr.get("stash_type", 1) != 1:
                    raise ExecutionError("LayerNorm stash_type must be FP32")
                beta = args[2].data if len(args) > 2 and args[2] is not None else None
                values = backend.layer_norm(args[0].data, args[1].data, beta, attr.get("axis", -1), attr.get("epsilon", 1e-5))
                return [Tensor(value) for value in values[:len(node.output)]]
        return super()._eval(node, args, backend)

    @staticmethod
    def _matmul(a, b, backend):
        if not getattr(backend, "hardware_matmul_i16", False):
            return V1Executor._matmul(a, b, backend)
        if a.q is None or b.q is None or a.q.dtype != np.int16 or b.q.dtype != np.int16:
            raise ExecutionError("weighted operation requires INT16 DQ provenance on both operands")
        avector, bvector = a.q.ndim == 1, b.q.ndim == 1
        qa = a.q[np.newaxis, :] if avector else a.q
        qb = b.q[:, np.newaxis] if bvector else b.q
        sa = a.scale_view()[np.newaxis, :] if avector else a.scale_view()
        sb = b.scale_view()[:, np.newaxis] if bvector else b.scale_view()
        if qa.shape[-1] != qb.shape[-2] or qa.shape[-1] == 0:
            raise ExecutionError("invalid MatMul contraction")
        if not np.all(sa == sa[..., :1]) or not np.all(sb == sb[..., :1, :]):
            raise ExecutionError("scale varies on contraction axis")
        acc = backend.matmul_i16(qa, qb)
        scale = backend.binary("Mul", sa[..., :, :1], sb[..., :1, :])
        data = backend.binary("Mul", backend.int48_to_float(acc), scale)
        if avector:
            data = np.squeeze(data, axis=-2)
        if bvector:
            data = np.squeeze(data, axis=-1)
        return Tensor(np.asarray(data, np.float32))
