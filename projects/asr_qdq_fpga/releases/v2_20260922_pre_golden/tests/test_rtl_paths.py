"""Path regression for user-selected relative simulator build directories."""
from pathlib import Path
from unittest import TestCase
from unittest.mock import patch
from host.rtl_sim import compile_bridge

class RtlPathTests(TestCase):
    def test_relative_build_output_resolves_before_changing_cwd(self):
        with patch('host.rtl_sim.subprocess.run') as command:
            output = compile_bridge(Path('build') / 'relative_path_test')
        self.assertTrue(output.is_absolute())
        args, kwargs = command.call_args
        self.assertEqual(Path(args[0][args[0].index('-o') + 1]), output)
        self.assertEqual(kwargs['cwd'], output.parent)
