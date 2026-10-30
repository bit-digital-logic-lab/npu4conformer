#!/bin/bash
# ==============================================================================
# gemini_stream_round2: Reproducible verification entry point for STREAM-1..4
# ==============================================================================
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"

echo "========================================================================"
echo "Starting gemini_stream_round2 verification suite for STREAM-1..4"
echo "Workdir: ${SCRIPT_DIR}"
echo "========================================================================"

# Run verification suite (compilation -j1, watchdog per test, SHA computation)
python3 scripts/run_stream_suite.py

RC=$?
if [ $RC -eq 0 ]; then
    echo "========================================================================"
    echo "STREAM ENGINE REPAIR SUITE: ALL TESTS PASSED (rc=0)"
    echo "========================================================================"
else
    echo "========================================================================"
    echo "STREAM ENGINE REPAIR SUITE: FAILURES DETECTED (rc=${RC})"
    echo "========================================================================"
fi

exit $RC
