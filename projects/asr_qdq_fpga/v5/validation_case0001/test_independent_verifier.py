"""Offline comparator checks only; these synthetic arrays are NOT goldens."""
import importlib.util
from pathlib import Path
import unittest
import numpy as np

spec = importlib.util.spec_from_file_location('independent', Path(__file__).with_name('verify_two_cases.py'))
verification = importlib.util.module_from_spec(spec)
spec.loader.exec_module(verification)


class ComparatorChecks(unittest.TestCase):
    def test_equal_float(self):
        x = np.zeros((1, 31, 512), np.float32)
        report = verification.compare('encoder_memory', x, x.copy())
        self.assertTrue(report['passed'])
        self.assertTrue(report['bit_exact'])

    def test_inside_then_outside_tolerance(self):
        golden = np.ones((1, 5000), np.float32)
        actual = golden.copy()
        actual[0, 4] = 1.0019
        self.assertTrue(verification.compare('decoder_log_probs', actual, golden)['passed'])
        actual[0, 4] = 1.0021
        report = verification.compare('decoder_log_probs', actual, golden)
        self.assertFalse(report['passed'])
        self.assertEqual(report['failed_elements'], 1)

    def test_nonfinite(self):
        golden = np.ones((1, 5000), np.float32)
        for value in (np.nan, np.inf, -np.inf):
            actual = golden.copy()
            actual[0, 0] = value
            report = verification.compare('decoder_log_probs', actual, golden)
            self.assertFalse(report['passed'])
            self.assertFalse(report['all_finite'])

    def test_integer_exact(self):
        golden = np.array([31], dtype=np.int64)
        self.assertTrue(verification.compare('encoder_memory_lengths', golden.copy(), golden)['passed'])
        self.assertFalse(verification.compare('encoder_memory_lengths', golden - 1, golden)['passed'])

    def test_shape_and_dtype(self):
        golden = np.ones((1, 5000), np.float32)
        self.assertFalse(verification.compare('decoder_log_probs', golden.astype(np.float64), golden)['passed'])
        self.assertFalse(verification.compare('decoder_log_probs', golden.ravel(), golden)['passed'])

    def test_prior_case_verifies(self):
        report = verification.verify_case('case_0000', verification.CASES['case_0000'])
        self.assertTrue(report['pass_all'])
        self.assertTrue(report['comparisons']['encoder_memory']['bit_exact'])

    def test_original_input_arrays_differ(self):
        report = verification.inspect_input_difference()
        self.assertTrue(any(row['differing_elements'] > 0 for row in report.values()))


if __name__ == '__main__':
    unittest.main(verbosity=2)
