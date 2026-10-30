# Reproduce

From this directory:

```bash
bash scripts/run_all.sh
```

The script writes every compile/run/lint log under `logs/`, the pass/fail
summary to `reports/RUN_SUMMARY.txt`, and hashes to
`reports/SOURCE_SHA256.txt` / `reports/TEST_SHA256.txt`.
It exits 0 only if all expected before-bug and after-fix patterns are found.

Individual canonical runs (after `run_all.sh` has built the `.vvp` files):

```bash
vvp -n build/csr_orig.vvp     # expected PA001_INTERLEAVED_BUG / PA001_FAIL
vvp -n build/csr_v023.vvp     # expected PA001_PASS
vvp -n build/plan_before.vvp  # expected PA002_FETCH/ERROR_DRAIN_UNBOUNDED_CONFIRMED
vvp -n build/plan_v023.vvp    # expected PA002_PASS
vvp -n build/dma_before.vvp   # expected PA003/PA004 bug confirmations
vvp -n build/dma_v023.vvp     # expected PA003_PA004_PASS
vvp -n build/dma_bounded.vvp  # expected BOUNDED_PASS
vvp -n build/ready_scan.vvp   # expected READY_SCAN_PASS
vvp -n build/block_address.vvp# expected BLOCK_ADDRESS_PASS
vvp -n build/storage_handshake.vvp # expected STORAGE_HANDSHAKE_PASS
```

No network, synthesis, Vivado, board, VNC, or push is used.
