"""Small independent checks of integer provenance, operator semantics and routing."""
import unittest
import numpy as np
import onnx
from onnx import helper as h, numpy_helper as nh, TensorProto as T
from host.onnx_executor import OnnxExecutor, SoftwareBackend, Tensor, ExecutionError


def graph(nodes, inputs, outputs, constants=()):
    return h.make_model(h.make_graph(nodes, "test", inputs, outputs, constants),
                        opset_imports=[h.make_opsetid("", 21)], ir_version=8)


class SpyBackend:
    """Arithmetic test double, explicitly not hardware evidence."""
    name = "test-double"
    hardware_executed = False
    def __init__(self):
        self.reference, self.calls = SoftwareBackend(), []
    def __getattr__(self, name):
        target = getattr(self.reference, name)
        def wrapped(*args, **kwargs):
            self.calls.append(name)
            return target(*args, **kwargs)
        return wrapped


class ExecutorTests(unittest.TestCase):
    def setUp(self):
        self.backend = SoftwareBackend()
        self.executor = OnnxExecutor(graph([], [], []), self.backend)

    def evaluate(self, op, arrays, attributes=None, outputs=1, backend=None):
        node = h.make_node(op, [f"x{i}" for i in range(len(arrays))], [f"y{i}" for i in range(outputs)], **(attributes or {}))
        return self.executor._eval(node, [x if isinstance(x, Tensor) else Tensor(np.asarray(x)) for x in arrays], backend or self.backend)

    def qt(self, q, scale):
        q = np.asarray(q, np.int16)
        scale = np.asarray(scale, np.float32)
        return Tensor(self.backend.dequantize(q, scale), q, scale)

    def test_quantize_ties_even_and_saturation(self):
        x = np.array([-50000, -2.5, -1.5, -.5, .5, 1.5, 2.5, 50000], np.float32)
        np.testing.assert_array_equal(self.backend.quantize(x, np.float32(1)), [-32768, -2, -2, 0, 0, 2, 2, 32767])

    def test_dot_exceeds_int32_but_fits_signed48(self):
        q = np.full(512, -32768, np.int16)
        self.assertEqual(self.backend.dot_i16(q, q), 512 * (1 << 30))

    def test_signed48_overflow_rejected(self):
        with self.assertRaises(ExecutionError): self.backend.int48_to_float(np.int64(1 << 47))
        np.testing.assert_array_equal(self.backend.int48_to_float(np.array([-(1 << 47), (1 << 47) - 1])), np.array([-(1 << 47), (1 << 47) - 1], np.float32))

    def test_matmul_per_channel_scale_and_backend_routing(self):
        a = self.qt([[1, 2, -3], [5, -4, 2]], .5)
        b = self.qt([[1, 2], [3, 4], [5, 6]], [[.25, .125]])
        spy = SpyBackend()
        result = self.executor._matmul(a, b, spy).data
        expected = (a.q.astype(np.int64) @ b.q.astype(np.int64)).astype(np.float32) * np.array([[.125, .0625]], np.float32)
        np.testing.assert_array_equal(result, expected)
        self.assertEqual(spy.calls.count("dot_i16"), 4)
        self.assertIn("int48_to_float", spy.calls)
        self.assertNotIn("matmul_i16", spy.calls)

    def test_batched_matmul_broadcast(self):
        a = self.qt(np.arange(12).reshape(2, 2, 3), .125)
        b = self.qt(np.arange(6).reshape(3, 2), .25)
        out = self.executor._matmul(a, b, self.backend).data
        np.testing.assert_array_equal(out, np.matmul(a.data, b.data))

    def test_vector_matmul(self):
        a, b = self.qt([1, 2, 3], .5), self.qt([3, 2, 1], .25)
        self.assertEqual(self.executor._matmul(a, b, self.backend).data.shape, ())
        self.assertEqual(self.executor._matmul(a, b, self.backend).data.item(), 1.25)

    def test_missing_qdq_provenance_fails_closed(self):
        with self.assertRaisesRegex(ExecutionError, "provenance"):
            self.executor._matmul(Tensor(np.ones((2, 2), np.float32)), self.qt([[1, 2], [3, 4]], 1), self.backend)

    def test_varying_contracted_scale_rejected(self):
        a, b = self.qt([[1, 2]], [[1, 2]]), self.qt([[1], [2]], 1)
        with self.assertRaisesRegex(ExecutionError, "contraction axis"):
            self.executor._matmul(a, b, self.backend)

    def test_conv2d_stride_and_per_output_scale(self):
        x = self.qt(np.arange(25).reshape(1, 1, 5, 5), .5)
        w = self.qt([[[[1, 2], [3, 4]]], [[[-1, 0], [0, 1]]]], np.array([.25, .125]).reshape(2, 1, 1, 1))
        out = self.evaluate("Conv", [x, w], {"strides": [2, 2]}).data
        expected = np.empty((1, 2, 2, 2), np.float32)
        for c in range(2):
            for i in range(2):
                for j in range(2): expected[0, c, i, j] = np.sum(x.data[0, 0, 2*i:2*i+2, 2*j:2*j+2] * w.data[c, 0])
        np.testing.assert_array_equal(out, expected)

    def test_grouped_conv1d_padding_dilation_bias(self):
        x = self.qt([[[1, 2, 3, 4, 5], [6, 7, 8, 9, 10]]], .5)
        w = self.qt([[[1, 2]], [[3, -1]]], np.array([.25, .5]).reshape(2, 1, 1))
        out = self.evaluate("Conv", [x, w, np.array([1, -2], np.float32)], {"group": 2, "pads": [1, 1], "dilations": [2]}).data
        padded = np.pad(x.data, [(0, 0), (0, 0), (1, 1)])
        expected = np.empty_like(out)
        for c in range(2):
            for i in range(5): expected[0, c, i] = np.sum(padded[0, c, i:i+3:2] * w.data[c, 0]) + [1, -2][c]
        np.testing.assert_array_equal(out, expected)

    def test_gemm_transpose_alpha_beta(self):
        a, b = self.qt([[1, 2]], .5), self.qt([[3, 4], [5, 6], [7, 8]], .25)
        bias = np.array([1, 2, 3], np.float32)
        out = self.evaluate("Gemm", [a, b, bias], {"transB": 1, "alpha": 2.0, "beta": .5}).data
        np.testing.assert_array_equal(out, 2 * (a.data @ b.data.T) + .5 * bias)

    def test_layernorm_epsilon_and_backend_reductions(self):
        x = np.array([[1, 2, 3], [2, 2, 2]], np.float32)
        spy = SpyBackend()
        outputs = self.evaluate("LayerNormalization", [x, np.ones(3, np.float32), np.zeros(3, np.float32)], {"axis": -1, "epsilon": 1e-12}, 3, spy)
        expected = (x - x.mean(-1, keepdims=True)) / np.sqrt(x.var(-1, keepdims=True) + 1e-12)
        np.testing.assert_allclose(outputs[0].data, expected, atol=1e-6)
        self.assertEqual(spy.calls.count("reduce_sum"), 2)
        self.assertIn("unary", spy.calls)

    def test_batchnorm_inference(self):
        x = np.arange(12, dtype=np.float32).reshape(1, 3, 4)
        scale, bias = np.array([1, 2, 3], np.float32), np.array([0, 1, -1], np.float32)
        mean, var = np.array([1, 2, 3], np.float32), np.array([4, 9, 16], np.float32)
        out = self.evaluate("BatchNormalization", [x, scale, bias, mean, var], {"epsilon": 0.0}).data
        expected = ((x - mean[None, :, None]) / np.sqrt(var[None, :, None])) * scale[None, :, None] + bias[None, :, None]
        np.testing.assert_allclose(out, expected)

    def test_stable_softmax_and_logsoftmax(self):
        x = np.array([[1000, 999, -1000], [-10, -11, -12]], np.float32)
        soft = self.evaluate("Softmax", [x], {"axis": -1}).data
        log = self.evaluate("LogSoftmax", [x], {"axis": -1}).data
        np.testing.assert_allclose(soft.sum(-1), [1, 1], atol=1e-7)
        np.testing.assert_allclose(np.exp(log), soft, atol=1e-7)
        self.assertTrue(np.all(np.isfinite(log)))

    def test_negative_slice_onnx_sentinel(self):
        out = self.evaluate("Slice", [np.arange(5), np.array([-1]), np.array([-(1 << 63)]), np.array([0]), np.array([-1])]).data
        np.testing.assert_array_equal(out, [4, 3, 2, 1, 0])

    def test_backend_failure_never_falls_back(self):
        class Broken(SpyBackend):
            def binary(self, *args): raise RuntimeError("hardware link unavailable")
        model = graph([h.make_node("Add", ["x", "x"], ["y"])],
                      [h.make_tensor_value_info("x", T.FLOAT, [2])], [h.make_tensor_value_info("y", T.FLOAT, [2])])
        with self.assertRaisesRegex(ExecutionError, "hardware link unavailable"):
            OnnxExecutor(model, Broken()).run({"x": np.array([1, 2], np.float32)})

    def test_static_fold_does_not_use_dynamic_backend(self):
        bias = nh.from_array(np.array([1, 2], np.float32), name="bias")
        model = graph([h.make_node("Add", ["bias", "bias"], ["doubled"]), h.make_node("Add", ["x", "doubled"], ["y"])],
                      [h.make_tensor_value_info("x", T.FLOAT, [2])], [h.make_tensor_value_info("y", T.FLOAT, [2])], [bias])
        spy = SpyBackend()
        executor = OnnxExecutor(model, spy)
        np.testing.assert_array_equal(executor.run({"x": np.array([1, 2], np.float32)})["y"], [3, 6])
        self.assertEqual(executor.folded_nodes, 1)
        self.assertEqual(spy.calls, ["binary"])
        self.assertFalse(executor.last_stats["hardware_executed"])

    def test_unknown_op_and_domain_rejected(self):
        for node in [h.make_node("Unknown", [], ["y"]), h.make_node("Identity", [], ["y"], domain="vendor")]:
            with self.assertRaises(ExecutionError): OnnxExecutor(graph([node], [], []), self.backend)

    def test_nonsymmetric_qdq_rejected(self):
        with self.assertRaises(ExecutionError):
            self.evaluate("QuantizeLinear", [np.array([1], np.float32), np.float32(.1), np.int16(1)])

    def test_bad_input_dtype_and_shape_rejected(self):
        model = graph([h.make_node("Identity", ["x"], ["y"])],
                      [h.make_tensor_value_info("x", T.FLOAT, [2])], [h.make_tensor_value_info("y", T.FLOAT, [2])])
        executor = OnnxExecutor(model, self.backend)
        for bad in (np.array([1, 2], np.float64), np.ones((2, 1), np.float32), np.ones(3, np.float32)):
            with self.assertRaises(ExecutionError): executor.run({"x": bad})

    def test_invalid_scale_rejected_before_backend(self):
        for scale in (0, -1, np.nan, np.inf):
            with self.assertRaises(ExecutionError):
                self.evaluate("DequantizeLinear", [np.array([1], np.int16), np.float32(scale), np.int16(0)])

    def test_old_opset_rejected(self):
        model = graph([], [], [])
        model.opset_import[0].version = 11
        with self.assertRaises(ExecutionError): OnnxExecutor(model, self.backend)

    def test_int16_neural_add_not_executed_by_host(self):
        with self.assertRaises(ExecutionError): self.evaluate("Add", [np.array([1], np.int16), np.array([2], np.int16)])


if __name__ == "__main__": unittest.main()
