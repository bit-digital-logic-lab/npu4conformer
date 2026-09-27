"""Fail-closed scheduler for unmodified Model A W16A16 ONNX graphs.

The host schedules nodes and stores/indexes tensors. Dynamic neural arithmetic
uses the selected backend. MatMul, Gemm and Conv require signed INT16 QDQ
provenance and signed48 accumulation. Static-only subgraphs are prepared in
software; they are explicitly excluded from hardware-execution claims.
"""
from __future__ import annotations
from collections import Counter
from dataclasses import dataclass
from itertools import product
import numpy as np
import onnx
from onnx import numpy_helper


class ExecutionError(RuntimeError):
    pass


class SoftwareBackend:
    """Software reference, never evidence of RTL correctness."""
    name = "software"
    hardware_executed = False

    def binary(self, op, a, b):
        fn = {"Add": np.add, "Sub": np.subtract, "Mul": np.multiply,
              "Div": np.divide, "Max": np.maximum, "Min": np.minimum}.get(op)
        if fn is None: raise ExecutionError(f"unsupported binary {op}")
        with np.errstate(over="raise", invalid="raise", divide="raise"):
            return np.asarray(fn(np.asarray(a, np.float32), np.asarray(b, np.float32)), np.float32)

    def unary(self, op, a):
        a = np.asarray(a, np.float32)
        with np.errstate(over="ignore", under="ignore", invalid="raise", divide="raise"):
            if op == "Sigmoid":
                e = np.exp(-np.abs(a), dtype=np.float32)
                return np.where(a >= 0, 1 / (1 + e), e / (1 + e)).astype(np.float32)
            if op == "Relu": return np.maximum(a, np.float32(0))
            fn = {"Sqrt": np.sqrt, "Exp": np.exp, "Log": np.log,
                  "Abs": np.abs, "Neg": np.negative}.get(op)
            if fn is None: raise ExecutionError(f"unsupported unary {op}")
            return np.asarray(fn(a), np.float32)

    @staticmethod
    def _check48(value):
        value = np.asarray(value, np.int64)
        if np.any(value < -(1 << 47)) or np.any(value >= (1 << 47)):
            raise ExecutionError("signed48 accumulator overflow")
        return value

    def dot_i16(self, a, b):
        a, b = np.asarray(a), np.asarray(b)
        if a.dtype != np.int16 or b.dtype != np.int16 or a.shape != b.shape:
            raise ExecutionError("dot_i16 requires equally shaped int16 operands")
        partial = np.cumsum(a.astype(np.int64).ravel() * b.astype(np.int64).ravel(), dtype=np.int64)
        self._check48(partial)
        return int(partial[-1]) if partial.size else 0

    def matmul_i16(self, a, b):
        # Bound guarantees every partial sum fits, not merely the final sum.
        if a.shape[-1] * (1 << 30) >= (1 << 47):
            raise ExecutionError("dot length exceeds conservative signed48 bound")
        return self._check48(np.matmul(a.astype(np.int64), b.astype(np.int64)))

    def int48_to_float(self, value):
        return self._check48(value).astype(np.float32)

    def quantize(self, x, scale):
        scale = np.asarray(scale, np.float32)
        if np.any(scale <= 0) or not np.all(np.isfinite(scale)):
            raise ExecutionError("quantization scale must be finite and positive")
        with np.errstate(over="ignore"):
            divided = np.asarray(x, np.float32) / scale
        if np.any(np.isnan(divided)): raise ExecutionError("NaN quantization is undefined")
        return np.clip(np.rint(divided), -32768, 32767).astype(np.int16)

    def dequantize(self, q, scale):
        return np.asarray(q, np.float32) * np.asarray(scale, np.float32)

    def reduce_sum(self, x, axes, keepdims):
        return np.sum(x, axis=tuple(axes), keepdims=keepdims, dtype=np.float32)

    def reduce_max(self, x, axes, keepdims):
        return np.max(x, axis=tuple(axes), keepdims=keepdims)


@dataclass
class Tensor:
    data: np.ndarray
    q: np.ndarray | None = None
    scale: np.ndarray | None = None

    def scale_view(self):
        if self.scale is None: raise ExecutionError("missing QDQ scale provenance")
        return np.broadcast_to(self.scale, self.data.shape)


SUPPORTED_OPS = frozenset({
    "Constant", "ConstantOfShape", "Identity", "Shape", "Size", "Gather",
    "GatherElements", "Transpose", "Reshape", "Unsqueeze", "Squeeze", "Concat",
    "Slice", "Split", "Expand", "Tile", "Pad", "Cast", "Range", "Where", "Not",
    "And", "Or", "Equal", "Less", "LessOrEqual", "Greater", "GreaterOrEqual",
    "QuantizeLinear", "DequantizeLinear", "Add", "Sub", "Mul", "Div", "Max", "Min",
    "Relu", "Sigmoid", "Exp", "Log", "Sqrt", "Abs", "Neg", "ReduceSum",
    "ReduceMean", "ReduceMax", "Softmax", "LogSoftmax", "LayerNormalization",
    "BatchNormalization", "MatMul", "Gemm", "Conv",
})


def _attrs(node):
    return {a.name: onnx.helper.get_attribute_value(a) for a in node.attribute}


def _scale_shape(scale, shape, axis=1):
    scale = np.asarray(scale, np.float32)
    if np.any(scale <= 0) or not np.all(np.isfinite(scale)):
        raise ExecutionError("QDQ scale must be finite and positive")
    if scale.ndim == 0 or scale.size == 1: return scale.reshape(())
    if scale.ndim != 1: raise ExecutionError("blocked/multidimensional QDQ unsupported")
    axis %= len(shape)
    if scale.size != shape[axis]: raise ExecutionError("per-axis scale size mismatch")
    broadcast = [1] * len(shape)
    broadcast[axis] = scale.size
    return scale.reshape(broadcast)


def _move(tensor, fn):
    data = fn(tensor.data)
    if tensor.q is None: return Tensor(data)
    return Tensor(data, fn(tensor.q), fn(tensor.scale_view()))


class OnnxExecutor:
    def __init__(self, model, backend, fold_constants=True):
        self.model = onnx.load(str(model)) if isinstance(model, (str, bytes)) or hasattr(model, "__fspath__") else model
        self.backend = backend
        self.static = {v.name: Tensor(numpy_helper.to_array(v)) for v in self.model.graph.initializer}
        self.nodes, self.folded_nodes, self.last_stats = [], 0, {}
        unsupported = sorted({n.op_type for n in self.model.graph.node if n.op_type not in SUPPORTED_OPS})
        domains = sorted({n.domain for n in self.model.graph.node if n.domain not in ("", "ai.onnx")})
        if unsupported or domains:
            raise ExecutionError(f"unsupported operators={unsupported}, domains={domains}")
        standard_opsets = [o.version for o in self.model.opset_import if o.domain in ("", "ai.onnx")]
        if standard_opsets != [21]:
            raise ExecutionError(f"this audited scheduler supports ONNX opset 21, got {standard_opsets}")
        if not hasattr(backend, "name") or not hasattr(backend, "hardware_executed"):
            raise ExecutionError("backend must identify name and hardware_executed")
        preparation = SoftwareBackend()
        for node in self.model.graph.node:
            if fold_constants and all(not name or name in self.static for name in node.input):
                vals = [self.static[name] if name else None for name in node.input]
                self._store(self.static, node, self._eval(node, vals, preparation))
                self.folded_nodes += 1
            else:
                self.nodes.append(node)
        needed = {n for node in self.nodes for n in node.input}
        needed.update(o.name for o in self.model.graph.output)
        self.static = {k: v for k, v in self.static.items() if k in needed}

    @staticmethod
    def _store(values, node, outputs):
        if not isinstance(outputs, (list, tuple)): outputs = [outputs]
        if len(outputs) != len(node.output): raise ExecutionError(f"{node.name}: output count mismatch")
        for name, output in zip(node.output, outputs):
            if name: values[name] = output if isinstance(output, Tensor) else Tensor(np.asarray(output))

    def run(self, feeds, progress=None, trace=None):
        values = dict(self.static)
        expected = {x.name for x in self.model.graph.input} - set(self.static)
        if set(feeds) != expected: raise ExecutionError(f"feed names: expected {expected}, got {set(feeds)}")
        symbols = {}
        for declared in self.model.graph.input:
            if declared.name not in feeds: continue
            actual = np.asarray(feeds[declared.name])
            dtype = np.dtype(onnx.helper.tensor_dtype_to_np_dtype(declared.type.tensor_type.elem_type))
            dims = declared.type.tensor_type.shape.dim
            if actual.dtype != dtype or actual.ndim != len(dims):
                raise ExecutionError(f"{declared.name}: expected dtype={dtype}, rank={len(dims)}; got {actual.dtype}, {actual.shape}")
            for dim, size in zip(dims, actual.shape):
                if dim.HasField("dim_value") and dim.dim_value != size:
                    raise ExecutionError(f"{declared.name}: fixed dimension {dim.dim_value} does not match {size}")
                if dim.dim_param:
                    if dim.dim_param in symbols and symbols[dim.dim_param] != size:
                        raise ExecutionError(f"symbolic dimension {dim.dim_param} is inconsistent between inputs")
                    symbols[dim.dim_param] = size
        values.update({k: Tensor(np.asarray(v)) for k, v in feeds.items()})
        remaining = Counter(name for node in self.nodes for name in node.input if name)
        outputs = {v.name for v in self.model.graph.output}
        executed = Counter()
        for index, node in enumerate(self.nodes):
            try:
                args = [values[name] if name else None for name in node.input]
                self._store(values, node, self._eval(node, args, self.backend))
                executed[node.op_type] += 1
                if trace: trace(node, {name: values[name].data for name in node.output if name})
                for name in node.input:
                    if name:
                        remaining[name] -= 1
                        if not remaining[name] and name not in outputs and name not in self.static:
                            values.pop(name, None)
                if progress: progress(index + 1, len(self.nodes), node.name, node.op_type)
            except Exception as exc:
                raise ExecutionError(f"node {index} {node.name!r} ({node.op_type}): {exc}") from exc
        self.last_stats = {"backend": self.backend.name, "hardware_executed": bool(self.backend.hardware_executed),
                           "static_folded_nodes": self.folded_nodes, "dynamic_executed_nodes": sum(executed.values()),
                           "operators": dict(executed)}
        return {o.name: values[o.name].data for o in self.model.graph.output}

    @staticmethod
    def _matmul(a, b, backend):
        if a.q is None or b.q is None or a.q.dtype != np.int16 or b.q.dtype != np.int16:
            raise ExecutionError("weighted operation requires INT16 DQ provenance on both operands")
        avector, bvector = a.q.ndim == 1, b.q.ndim == 1
        qa, qb = (a.q[np.newaxis, :] if avector else a.q), (b.q[:, np.newaxis] if bvector else b.q)
        sa = a.scale_view()[np.newaxis, :] if avector else a.scale_view()
        sb = b.scale_view()[:, np.newaxis] if bvector else b.scale_view()
        if qa.shape[-1] != qb.shape[-2] or qa.shape[-1] == 0: raise ExecutionError("invalid MatMul contraction")
        if not np.all(sa == sa[..., :1]) or not np.all(sb == sb[..., :1, :]):
            raise ExecutionError("scale varies on contraction axis")
        shape = np.broadcast_shapes(qa.shape[:-2], qb.shape[:-2])
        m, k, n = qa.shape[-2], qa.shape[-1], qb.shape[-1]
        qa, qb = np.broadcast_to(qa, shape + (m, k)), np.broadcast_to(qb, shape + (k, n))
        # A hardware adapter must never inherit a software fast path by accident.
        if type(backend) is SoftwareBackend:
            acc = backend.matmul_i16(qa, qb)
        else:
            acc = np.empty(shape + (m, n), np.int64)
            for batch in np.ndindex(shape):
                for row, col in product(range(m), range(n)):
                    acc[batch + (row, col)] = backend.dot_i16(qa[batch + (row, slice(None))], qb[batch + (slice(None), col)])
        scale = backend.binary("Mul", sa[..., :, :1], sb[..., :1, :])
        data = backend.binary("Mul", backend.int48_to_float(acc), scale)
        if avector: data = np.squeeze(data, axis=-2)
        if bvector: data = np.squeeze(data, axis=-1)
        return Tensor(np.asarray(data, np.float32))

    def _conv(self, args, attr, backend):
        x, w = args[:2]
        if x.q is None or w.q is None: raise ExecutionError("Conv requires INT16 DQ provenance")
        spatial = x.data.ndim - 2
        if spatial not in (1, 2): raise ExecutionError("only Conv1D/Conv2D supported")
        if attr.get("auto_pad", b"NOTSET") not in (b"NOTSET", b""):
            raise ExecutionError("Conv auto_pad unsupported; use explicit pads")
        strides, dilation = attr.get("strides", [1] * spatial), attr.get("dilations", [1] * spatial)
        pads, group = attr.get("pads", [0] * (2 * spatial)), attr.get("group", 1)
        batch, channels = x.data.shape[:2]
        outchannels, localchannels = w.data.shape[:2]
        if channels != group * localchannels or outchannels % group: raise ExecutionError("invalid Conv groups")
        kernel = w.data.shape[2:]
        outshape = tuple((x.data.shape[i + 2] + pads[i] + pads[i + spatial] - dilation[i] * (kernel[i] - 1) - 1) // strides[i] + 1 for i in range(spatial))
        if any(s <= 0 for s in outshape): raise ExecutionError("empty Conv output")
        scale_x = x.scale_view()
        if not np.all(scale_x == scale_x.flat[0]): raise ExecutionError("Conv requires per-tensor activation scale")
        qpad = np.pad(x.q, [(0, 0), (0, 0)] + [(pads[i], pads[i + spatial]) for i in range(spatial)])
        result = np.empty((batch, outchannels) + outshape, np.float32)
        pergroup, positions = outchannels // group, list(np.ndindex(outshape))
        for bi, gi in product(range(batch), range(group)):
            patches = np.empty((len(positions), localchannels * int(np.prod(kernel))), np.int16)
            for pi, position in enumerate(positions):
                slices = tuple(slice(position[i] * strides[i], position[i] * strides[i] + dilation[i] * (kernel[i] - 1) + 1, dilation[i]) for i in range(spatial))
                patches[pi] = qpad[(bi, slice(gi * localchannels, (gi + 1) * localchannels)) + slices].ravel()
            cs = slice(gi * pergroup, (gi + 1) * pergroup)
            weights, scale_w = w.q[cs].reshape(pergroup, -1).T, w.scale_view()[cs].reshape(pergroup, -1).T
            # data below is only a shape carrier, not float neural arithmetic.
            lhs = Tensor(patches, patches, np.asarray(scale_x.flat[0], np.float32))
            rhs = Tensor(weights, weights, scale_w)
            result[bi, cs] = self._matmul(lhs, rhs, backend).data.T.reshape((pergroup,) + outshape)
        if len(args) > 2 and args[2] is not None:
            result = backend.binary("Add", result, args[2].data.reshape((1, outchannels) + (1,) * spatial))
        return Tensor(result)

    def _eval(self, node, args, backend):
        op, attr = node.op_type, _attrs(node)
        data = [v.data if v is not None else None for v in args]
        if op == "Constant":
            if "value" in attr: return Tensor(numpy_helper.to_array(attr["value"]))
            for key, dtype in (("value_float", np.float32), ("value_floats", np.float32), ("value_int", np.int64), ("value_ints", np.int64)):
                if key in attr: return Tensor(np.asarray(attr[key], dtype=dtype))
            raise ExecutionError("unsupported Constant encoding")
        if op == "ConstantOfShape":
            value = numpy_helper.to_array(attr["value"]) if "value" in attr else np.asarray([0], np.float32)
            return Tensor(np.full(tuple(data[0].astype(int)), value.item(), value.dtype))
        if op == "Identity": return args[0]
        if op == "Shape": return Tensor(np.asarray(data[0].shape[attr.get("start", 0):attr.get("end", data[0].ndim)], np.int64))
        if op == "Size": return Tensor(np.asarray(data[0].size, np.int64))
        if op == "Transpose": return _move(args[0], lambda x: np.transpose(x, attr.get("perm")))
        if op == "Reshape":
            shape = data[1].astype(int).tolist()
            if not attr.get("allowzero", 0): shape = [data[0].shape[i] if s == 0 else s for i, s in enumerate(shape)]
            return _move(args[0], lambda x: np.reshape(x, shape))
        if op in ("Unsqueeze", "Squeeze"):
            axes = tuple(int(v) for v in data[1].ravel()) if len(data) > 1 else tuple(attr.get("axes", []))
            fn = (lambda x: np.expand_dims(x, axes)) if op == "Unsqueeze" else (lambda x: np.squeeze(x, axes or None))
            return _move(args[0], fn)
        if op == "Gather": return _move(args[0], lambda x: np.take(x, data[1], axis=attr.get("axis", 0)))
        if op == "GatherElements": return _move(args[0], lambda x: np.take_along_axis(x, data[1], axis=attr.get("axis", 0)))
        if op == "Slice":
            starts, ends = data[1].ravel(), data[2].ravel()
            axes = data[3].ravel() if len(data) > 3 and data[3] is not None else range(len(starts))
            steps = data[4].ravel() if len(data) > 4 and data[4] is not None else [1] * len(starts)
            slices = [slice(None)] * data[0].ndim
            for axis, start, end, step in zip(axes, starts, ends, steps):
                stop = None if int(step) < 0 and int(end) <= -(1 << 31) else int(end)
                slices[int(axis)] = slice(int(start), stop, int(step))
            return _move(args[0], lambda x: x[tuple(slices)])
        if op == "Split":
            axis = attr.get("axis", 0)
            sizes = data[1].ravel().tolist() if len(data) > 1 else attr.get("split")
            if sizes is None:
                count, size = attr.get("num_outputs", len(node.output)), data[0].shape[axis]
                chunk = (size + count - 1) // count
                sizes = [min(chunk, size - i * chunk) for i in range(count)]
            if sum(sizes) != data[0].shape[axis] or min(sizes) < 0: raise ExecutionError("invalid Split sizes")
            indices = np.cumsum(sizes)[:-1]
            return [_move(args[0], lambda x, i=i: np.split(x, indices, axis=axis)[i]) for i in range(len(sizes))]
        if op == "Concat":
            axis, result = attr["axis"], np.concatenate(data, axis=attr["axis"])
            if all(v.q is not None for v in args):
                return Tensor(result, np.concatenate([v.q for v in args], axis), np.concatenate([v.scale_view() for v in args], axis))
            return Tensor(result)
        if op == "Expand": return _move(args[0], lambda x: np.broadcast_to(x, tuple(data[1].astype(int))))
        if op == "Tile": return _move(args[0], lambda x: np.tile(x, tuple(data[1].astype(int))))
        if op == "Pad":
            if attr.get("mode", b"constant") != b"constant": raise ExecutionError("only constant Pad supported")
            pads = data[1].astype(int)
            return Tensor(np.pad(data[0], list(zip(pads[:data[0].ndim], pads[data[0].ndim:])), constant_values=data[2].item() if len(data) > 2 else 0))
        if op == "Cast":
            dtype = np.dtype(onnx.helper.tensor_dtype_to_np_dtype(attr["to"]))
            if np.issubdtype(data[0].dtype, np.floating) and dtype != data[0].dtype and dtype != np.dtype(bool):
                raise ExecutionError("dynamic neural float Cast has no backend contract")
            return Tensor(data[0].astype(dtype))
        if op == "Range": return Tensor(np.arange(data[0].item(), data[1].item(), data[2].item(), dtype=data[0].dtype))
        if op == "Where": return Tensor(np.where(data[0], data[1], data[2]))
        if op == "Not": return Tensor(np.logical_not(data[0]))
        comparisons = {"Equal": np.equal, "Less": np.less, "LessOrEqual": np.less_equal, "Greater": np.greater, "GreaterOrEqual": np.greater_equal, "And": np.logical_and, "Or": np.logical_or}
        if op in comparisons: return Tensor(comparisons[op](data[0], data[1]))
        if op in ("QuantizeLinear", "DequantizeLinear"):
            if attr.get("block_size", 0): raise ExecutionError("blocked QDQ unsupported")
            if len(data) < 3 or data[2] is None or data[2].dtype != np.int16 or np.any(data[2] != 0):
                raise ExecutionError("only symmetric signed INT16 QDQ supported")
            scale = _scale_shape(data[1], data[0].shape, attr.get("axis", 1))
            if op == "QuantizeLinear": return Tensor(np.asarray(backend.quantize(data[0], scale), np.int16))
            if data[0].dtype != np.int16: raise ExecutionError("DQ input must be INT16")
            return Tensor(np.asarray(backend.dequantize(data[0], scale), np.float32), data[0], scale)
        if op in ("Add", "Sub", "Mul", "Div", "Max", "Min"):
            if all(np.issubdtype(x.dtype, np.integer) for x in data):
                if any(x.dtype.itemsize < 4 for x in data):
                    raise ExecutionError("quantized neural integer arithmetic cannot run on host")
                fn = {"Add": np.add, "Sub": np.subtract, "Mul": np.multiply, "Div": np.floor_divide, "Max": np.maximum, "Min": np.minimum}[op]
                return Tensor(fn(data[0], data[1]))
            return Tensor(backend.binary(op, data[0], data[1]))
        if op in ("Relu", "Sigmoid", "Exp", "Log", "Sqrt", "Abs", "Neg"):
            return Tensor(backend.unary(op, data[0]))
        if op in ("ReduceSum", "ReduceMean", "ReduceMax"):
            axes = data[1].ravel().tolist() if len(data) > 1 else attr.get("axes")
            if axes == [] and attr.get("noop_with_empty_axes", 0): return args[0]
            axes = list(range(data[0].ndim)) if not axes else axes
            keep = bool(attr.get("keepdims", 1))
            if np.issubdtype(data[0].dtype, np.integer):
                if data[0].dtype.itemsize < 4:
                    raise ExecutionError("quantized neural integer reduction cannot run on host")
                if op == "ReduceMean": raise ExecutionError("integer ReduceMean unsupported")
                return Tensor((np.sum if op == "ReduceSum" else np.max)(data[0], axis=tuple(axes), keepdims=keep))
            out = backend.reduce_max(data[0], axes, keep) if op == "ReduceMax" else backend.reduce_sum(data[0], axes, keep)
            if op == "ReduceMean": out = backend.binary("Div", out, np.float32(np.prod([data[0].shape[i] for i in axes])))
            return Tensor(out)
        if op in ("Softmax", "LogSoftmax"):
            axis = attr.get("axis", -1)
            shifted = backend.binary("Sub", data[0], backend.reduce_max(data[0], [axis], True))
            exps = backend.unary("Exp", shifted)
            denom = backend.reduce_sum(exps, [axis], True)
            out = backend.binary("Div", exps, denom) if op == "Softmax" else backend.binary("Sub", shifted, backend.unary("Log", denom))
            return Tensor(out)
        if op == "LayerNormalization":
            if attr.get("stash_type", 1) != 1: raise ExecutionError("LayerNorm stash_type must be FP32")
            axes = list(range(attr.get("axis", -1) % data[0].ndim, data[0].ndim))
            count = np.float32(np.prod([data[0].shape[i] for i in axes]))
            mean = backend.binary("Div", backend.reduce_sum(data[0], axes, True), count)
            centered = backend.binary("Sub", data[0], mean)
            variance = backend.binary("Div", backend.reduce_sum(backend.binary("Mul", centered, centered), axes, True), count)
            denom = backend.unary("Sqrt", backend.binary("Add", variance, np.float32(attr.get("epsilon", 1e-5))))
            inv = backend.binary("Div", np.float32(1), denom)
            out = backend.binary("Mul", backend.binary("Mul", centered, inv), data[1])
            if len(data) > 2 and data[2] is not None: out = backend.binary("Add", out, data[2])
            return [Tensor(x) for x in [out, mean, inv][:len(node.output)]]
        if op == "BatchNormalization":
            if attr.get("training_mode", 0): raise ExecutionError("training BatchNorm unsupported")
            shape = (1, data[0].shape[1]) + (1,) * (data[0].ndim - 2)
            scale, bias, mean, var = [x.reshape(shape) for x in data[1:5]]
            denom = backend.unary("Sqrt", backend.binary("Add", var, np.float32(attr.get("epsilon", 1e-5))))
            out = backend.binary("Add", backend.binary("Mul", backend.binary("Div", backend.binary("Sub", data[0], mean), denom), scale), bias)
            return Tensor(out)
        if op == "MatMul": return self._matmul(args[0], args[1], backend)
        if op == "Gemm":
            a = _move(args[0], lambda x: x.T) if attr.get("transA", 0) else args[0]
            b = _move(args[1], lambda x: x.T) if attr.get("transB", 0) else args[1]
            out = self._matmul(a, b, backend).data
            if attr.get("alpha", 1) != 1: out = backend.binary("Mul", out, np.float32(attr["alpha"]))
            if len(data) > 2 and data[2] is not None:
                bias = data[2] if attr.get("beta", 1) == 1 else backend.binary("Mul", data[2], np.float32(attr["beta"]))
                out = backend.binary("Add", out, bias)
            return Tensor(out)
        if op == "Conv": return self._conv(args, attr, backend)
        raise ExecutionError(f"operator {op} has no implementation")
