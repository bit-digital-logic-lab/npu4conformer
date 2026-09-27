"""Import the numerical V2 baseline without modifying its frozen snapshot."""
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
ASR = ROOT.parent
FROZEN = ASR / 'releases' / 'v2_20260922_pre_golden'


def require_frozen_modules():
    """No device access. Refuse a preloaded non-frozen module of the same name."""
    # Imports must not create or refresh __pycache__ inside the frozen release.
    sys.dont_write_bytecode = True
    frozen = FROZEN.resolve()
    sys.path.insert(0, str(frozen))
    import host.transport as v1_transport
    import host.onnx_executor as v1_executor
    import v2.host.transport as v2_transport
    import v2.host.onnx_executor as v2_executor
    for module in (v1_transport, v1_executor, v2_transport, v2_executor):
        if frozen not in Path(module.__file__).resolve().parents:
            raise RuntimeError(f'Numerical baseline is not frozen: {module.__file__}')
    return v1_transport, v2_transport, v2_executor
