"""Small operator fixtures through actual RTL + host scheduler, not a reduced ASR model."""
from pathlib import Path
import json
import struct
import unittest
import numpy as np
from onnx import helper
from host.rtl_sim import RtlSimulationBackend, compile_bridge, ROOT
from host.onnx_executor import SoftwareBackend, OnnxExecutor, Tensor

class RtlIntegrationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.backend = RtlSimulationBackend(compile_bridge())
        cls.reference = SoftwareBackend()
        cls.executor = OnnxExecutor(helper.make_model(helper.make_graph([], 'operator-fixtures', [], []),
                                    opset_imports=[helper.make_opsetid('', 21)]), cls.backend)

    @classmethod
    def tearDownClass(cls):
        report = cls.backend.report()
        report.update(scope='small operator fixtures only; original whole-model RTL not verified')
        path = ROOT / 'build' / 'tests' / 'rtl_integration.json'
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(report, indent=2), encoding='utf-8')
        cls.backend.close()

    def check_op(self, op, arrays, **attributes):
        node = helper.make_node(op, ['x'+str(i) for i in range(len(arrays))], ['y'], **attributes)
        tensors = [x if isinstance(x, Tensor) else Tensor(np.asarray(x)) for x in arrays]
        actual = self.executor._eval(node, tensors, self.backend)
        expected = self.executor._eval(node, tensors, self.reference)
        if isinstance(actual, list):
            actual, expected = actual[0], expected[0]
        np.testing.assert_allclose(actual.data, expected.data, rtol=2e-5, atol=2e-6)
        return actual

    def qt(self, q, scale):
        q = np.asarray(q, np.int16)
        scale = np.asarray(scale, np.float32)
        return Tensor(self.backend.dequantize(q, scale), q, scale)

    def test_long_dot_and_signed48_conversion(self):
        a = np.full(9728, -32768, np.int16)
        total = self.backend.dot_i16(a, a)
        self.assertEqual(total, 9728 * (1 << 30))
        actual = self.backend.int48_to_float([total, -total])
        np.testing.assert_array_equal(actual, np.asarray([total, -total], np.float32))

    def test_qdq_rounding_broadcast_and_saturation(self):
        data = np.array([[-2.5, -1.5, -.5, .5, 1.5, 2.5, 32768, -32769]], np.float32)
        scale = np.array([[1], [.5]], np.float32)
        actual = self.backend.quantize(data, scale)
        np.testing.assert_array_equal(actual, self.reference.quantize(data, scale))
        np.testing.assert_array_equal(self.backend.dequantize(actual, scale), actual.astype(np.float32) * scale)

    def test_matmul_per_channel_and_gemm(self):
        a = self.qt([[1, -2, 3], [32767, -32768, 17]], .015625)
        b = self.qt([[4, 6], [-5, 2], [7, -8]], [[.125, .0625]])
        self.check_op('MatMul', [a, b])
        self.check_op('Gemm', [a, b, np.array([.25, -.75], np.float32)], alpha=.5, beta=2.)

    def test_grouped_conv_and_conv2d(self):
        x = self.qt(np.arange(14).reshape(1, 2, 7)-7, .125)
        w = self.qt(np.array([[[1, -2, 3]], [[-1, 0, 2]]]), np.array([.25, .5]).reshape(2, 1, 1))
        self.check_op('Conv', [x, w, np.array([.125, -.25], np.float32)],
                      group=2, pads=[2, 2], strides=[1], dilations=[2])
        self.check_op('Conv', [self.qt(np.arange(25).reshape(1, 1, 5, 5)-12, .0625),
                              self.qt(np.arange(18).reshape(2, 1, 3, 3)-9,
                                      np.array([.125, .25]).reshape(2, 1, 1, 1))], strides=[2, 2])

    def test_layernorm_real_width_and_small_variance(self):
        rng = np.random.default_rng(512)
        x = rng.normal(0, 1, (1, 512)).astype(np.float32)
        self.check_op('LayerNormalization', [x, np.ones(512, np.float32), np.zeros(512, np.float32)],
                      axis=-1, epsilon=1e-12)
        self.check_op('LayerNormalization', [np.ones((1, 8), np.float32), np.ones(8, np.float32), np.zeros(8, np.float32)],
                      axis=-1, epsilon=1e-12)

    def test_batchnorm_swish_softmax_logsoftmax(self):
        x = np.array([[[-1., .5, 2.], [-2., .75, 3.]]], np.float32)
        self.check_op('BatchNormalization', [x, np.array([1.2, .9], np.float32), np.array([.2, -.3], np.float32),
                                            np.array([-.1, .5], np.float32), np.array([.25, 2.], np.float32)], epsilon=1e-5)
        z = np.array([-1000, -10, -1, 0, 1, 10, 1000], np.float32)
        sigmoid = self.check_op('Sigmoid', [z])
        self.check_op('Mul', [z, sigmoid])
        values = np.array([[-1000, -3, -2, -1], [100, 100, 100, 100]], np.float32)
        self.check_op('Softmax', [values], axis=-1)
        self.check_op('LogSoftmax', [values], axis=-1)

    def test_attention_fragment(self):
        # QK^T -> scale -> softmax -> INT16 QDQ -> weights*V, same kernels as E/D.
        q = self.qt(np.array([[[[1, 2, -3, 4], [-2, 1, 2, 3]]]]), .125)
        k = self.qt(np.array([[[[3, 1], [2, -1], [-1, 2], [4, 2]]]]), .125)
        scores = self.check_op('MatMul', [q, k])
        scores = self.check_op('Mul', [scores, np.float32(.5)])
        probs = self.check_op('Softmax', [scores], axis=-1)
        scale = np.float32(1 / 32767)
        pq = self.backend.quantize(probs.data, scale)
        p = Tensor(self.backend.dequantize(pq, scale), pq, scale)
        v = self.qt(np.array([[[[2, 4, 1, -1], [-3, 2, -2, 1]]]]), .125)
        self.check_op('MatMul', [p, v])

if __name__ == '__main__':
    unittest.main()
