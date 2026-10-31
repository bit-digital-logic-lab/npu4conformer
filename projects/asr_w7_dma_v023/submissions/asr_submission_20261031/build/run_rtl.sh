#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root/src/unified"
bash scripts/sim/run_export.sh
mkdir -p "$root/sim/unified_run"
cp -r logs/. "$root/sim/unified_run/"
