"""Smoke-report safety tests with fake links/backends only; no sockets or FPGA."""
import contextlib
import importlib.util
import io
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import numpy as np

SCRIPT = Path(__file__).resolve().parents[1] / 'scripts' / 'smoke_ethernet.py'
spec = importlib.util.spec_from_file_location('v4_smoke_report_safety', SCRIPT)
smoke = importlib.util.module_from_spec(spec)
spec.loader.exec_module(smoke)


class FakeLink:
    def __init__(self, close_confirmed=True, poisoned=False, close_error=False,
                 mismatch=False, backend_report_error=False, link_report_error=False):
        self.confirm = close_confirmed
        self.poisoned = poisoned
        self.close_error = close_error
        self.mismatch = mismatch
        self.backend_report_error = backend_report_error
        self.link_report_error = link_report_error
        self.closed = False
        self.close_calls = 0

    def close(self):
        self.close_calls += 1
        if self.close_error:
            raise OSError('simulated CLOSE transport failure')
        self.closed = True

    def report(self):
        if self.link_report_error:
            raise RuntimeError('simulated link report failure')
        return dict(closed=self.closed, close_confirmed=self.closed and self.confirm,
                    active=not self.closed, poisoned=self.poisoned)


class FakeBackend:
    def __init__(self, link):
        self.link = link
        self.memory = np.zeros(32768, dtype=np.uint32)

    def write_words(self, base, values):
        self.memory[base:base+len(values)] = values

    def read_words(self, base, count):
        output = self.memory[base:base+count].copy()
        if self.link.mismatch:
            output[0] ^= 1
        return output

    def binary(self, op, a, b):
        assert op == 'Add'
        return np.array([3, -1, .75, -4], np.float32)

    def matmul_i16(self, a, b):
        return np.array([[-44, 8], [83, 10]], np.int64)

    def report(self):
        if self.link.backend_report_error:
            raise RuntimeError('simulated backend report failure')
        return dict(backend='test-only fake, not physical')

    def close(self):
        self.link.close()


class SmokeReportSafetyTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix='asr_v4_smoke_unit_')
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.out = self.root / 'reports' / 'fresh.json'

    def run_fake(self, link=None, open_error=None, backend_class=FakeBackend):
        link = link or FakeLink()
        with patch.object(smoke, 'ROOT', self.root), \
             patch.object(smoke, 'open_link', side_effect=open_error, return_value=link) as opened, \
             patch.object(smoke, 'EthernetBackend', backend_class), \
             contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
            code = smoke.main(['--allow-hardware', '--words', '32768', '--rounds', '4', '--out', str(self.out)])
        self.assertEqual(opened.call_count, 1, 'Never blindly reopen a failed session')
        return code, json.loads(self.out.read_text()), link

    def test_success_requires_data_and_confirmed_clean_close(self):
        code, report, link = self.run_fake()
        self.assertEqual(code, 0)
        self.assertTrue(report['hardware_access_attempted'])
        self.assertTrue(report['hardware_accessed'])
        self.assertTrue(report['handshake_complete'])
        self.assertTrue(report['data_arithmetic_pass'])
        self.assertTrue(report['cleanup_confirmed'])
        self.assertTrue(report['safe_for_followup_job'])
        self.assertTrue(report['pass_test'])
        self.assertEqual(link.close_calls, 1)

    def test_hello_timeout_is_attempted_not_claimed_unaccessed(self):
        code, report, link = self.run_fake(open_error=TimeoutError('HELLO response missing'))
        self.assertEqual(code, 1)
        self.assertTrue(report['hardware_access_attempted'])
        self.assertIsNone(report['hardware_accessed'])
        self.assertFalse(report['handshake_complete'])
        self.assertFalse(report['pass_test'])
        self.assertFalse(report['cleanup_confirmed'])
        self.assertFalse(report['automatic_reopen_attempted'])
        self.assertEqual(link.close_calls, 0)
        self.assertIn('HELLO may have reached FPGA', report['cleanup_note'])

    def test_session_rejection_is_not_reopened(self):
        code, report, _ = self.run_fake(open_error=RuntimeError('session mismatch after HELLO/PING'))
        self.assertEqual(code, 1)
        self.assertTrue(report['hardware_access_attempted'])
        self.assertFalse(report['automatic_reopen_attempted'])

    def test_lost_close_cannot_report_pass(self):
        code, report, link = self.run_fake(FakeLink(close_confirmed=False))
        self.assertEqual(code, 1)
        self.assertTrue(report['data_arithmetic_pass'])
        self.assertFalse(report['pass_test'])
        self.assertFalse(report['safe_for_followup_job'])
        self.assertIn('CLOSE is unconfirmed', report['error'])
        self.assertEqual(link.close_calls, 1)

    def test_poisoned_session_even_with_close_flag_cannot_pass(self):
        code, report, _ = self.run_fake(FakeLink(poisoned=True))
        self.assertEqual(code, 1)
        self.assertFalse(report['cleanup_confirmed'])
        self.assertFalse(report['pass_test'])

    def test_close_exception_still_saves_failed_report(self):
        code, report, link = self.run_fake(FakeLink(close_error=True))
        self.assertEqual(code, 1)
        self.assertTrue(report['data_arithmetic_pass'])
        self.assertIn('cleanup_error', report)
        self.assertFalse(report['pass_test'])
        self.assertEqual(link.close_calls, 1)

    def test_backend_report_exception_does_not_skip_close(self):
        code, report, link = self.run_fake(FakeLink(backend_report_error=True))
        self.assertEqual(code, 1)
        self.assertEqual(link.close_calls, 1)
        self.assertTrue(report['cleanup_confirmed'])
        self.assertIn('report_error', report)

    def test_close_report_exception_preserves_all_other_evidence(self):
        code, report, link = self.run_fake(FakeLink(link_report_error=True))
        self.assertEqual(code, 1)
        self.assertEqual(link.close_calls, 1)
        self.assertTrue(report['data_arithmetic_pass'])
        self.assertIn('roundtrip', report)
        self.assertIn('cleanup_error', report)

    def test_data_mismatch_cannot_pass_even_if_close_succeeds(self):
        code, report, _ = self.run_fake(FakeLink(mismatch=True))
        self.assertEqual(code, 1)
        self.assertFalse(report['data_arithmetic_pass'])
        self.assertTrue(report['cleanup_confirmed'])
        self.assertFalse(report['pass_test'])

    def test_backend_initialization_failure_closes_returned_link_once(self):
        def fail_backend(link):
            raise RuntimeError('INFO mismatch')
        code, report, link = self.run_fake(backend_class=fail_backend)
        self.assertEqual(code, 1)
        self.assertTrue(report['hardware_accessed'])
        self.assertEqual(link.close_calls, 1)

    def test_old_report_never_overwritten_or_device_opened(self):
        self.out.parent.mkdir()
        self.out.write_text('old evidence', encoding='utf-8')
        with patch.object(smoke, 'ROOT', self.root), patch.object(smoke, 'open_link') as opened, \
             contextlib.redirect_stderr(io.StringIO()):
            with self.assertRaises(SystemExit):
                smoke.main(['--allow-hardware', '--out', str(self.out)])
        self.assertEqual(self.out.read_text(), 'old evidence')
        opened.assert_not_called()

    def test_validate_only_never_opens_device_or_writes_report(self):
        with patch.object(smoke, 'ROOT', self.root), patch.object(smoke, 'open_link') as opened, \
             contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(smoke.main(['--validate-only']), 0)
        opened.assert_not_called()
        self.assertFalse(self.out.parent.exists())

    def test_invalid_timeout_rejected_before_device_access(self):
        with patch.object(smoke, 'ROOT', self.root), patch.object(smoke, 'open_link') as opened, \
             contextlib.redirect_stderr(io.StringIO()):
            with self.assertRaises(SystemExit):
                smoke.main(['--allow-hardware', '--timeout', '0', '--out', str(self.out)])
        opened.assert_not_called()


if __name__ == '__main__':
    unittest.main()
