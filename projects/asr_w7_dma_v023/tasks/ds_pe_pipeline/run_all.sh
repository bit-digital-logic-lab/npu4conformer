#!/usr/bin/env bash
# Reproduce all logic-only tests.  No synthesis, implementation, Vivado or board.
set -euo pipefail
cd "$(dirname "$0")"
make -j2
