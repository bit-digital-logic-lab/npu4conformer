#!/usr/bin/env bash
# run_all_tests.sh
# Master regression test runner for gemini_fma_round2.
# Strict sequential execution (-j1), watchdog on all sims.
# Reuses ds_numeric_adversarial/ref and vectors as read-only black box.

set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
cd "$DIR"

echo "================================================================="
echo "  GEMINI FMA ROUND 2 REGRESSION TEST (-j1)"
echo "  Timestamp: $(date -Iseconds)"
echo "================================================================="

# Step 1: Ensure random vectors are generated
if [ ! -f "vectors/fma_random.vec" ]; then
    echo "[SETUP] Generating 20,000 random/corner vectors..."
    python3 scripts/gen_random_vectors.py
fi

# Step 2: Run complete regression suite
echo "[RUN] Executing regression test orchestrator..."
python3 scripts/run_regression.py

RC=$?
echo "Regression completed with exit code: $RC"
exit $RC
