#!/usr/bin/env bash
# Produce the integration patch against the read-only integrated snapshot.
# The snapshot under snapshot/integrated is never modified.
set -eu
cd "$(dirname "$0")/.."
mkdir -p patch
OUT=patch/closeout_numeric.patch
: > "$OUT"
add() { cat "$1" >> "$OUT"; }

for f in rtl/*.sv; do
  b="snapshot/integrated/$f"
  if [ -f "$b" ]; then
    diff -u --label "a/$f" --label "b/$f" "$b" "$f" >> "$OUT" || true
  else
    diff -u --label "/dev/null" --label "b/$f" /dev/null "$f" >> "$OUT" || true
  fi
done

# the forbidden compile-only stub is deleted by this patch
diff -u --label "a/rtl/fma_forbidden_stub.sv" --label "/dev/null" \
  snapshot/integrated/rtl/fma_forbidden_stub.sv /dev/null >> "$OUT" || true

# intended replacement of the integrated unique filelist
diff -u --label "a/filelist_integrated.f" --label "b/filelist_integrated.f" \
  snapshot/integrated/filelist_integrated.f filelist_closeout_numeric.f >> "$OUT" || true

echo "wrote $OUT ($(wc -l < "$OUT") lines)"
