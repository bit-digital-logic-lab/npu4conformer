# Export run results

Run log: `docs/verification/logs/run_export_console.log`; per-run rc: `docs/verification/logs/rc.tsv`.

## Per-run status

| run | rc | cycles |
|---|---:|---:|
| v024_fused | 0 | 18724 |
| v024_fallback | 0 | 16973 |
| v024_multicons | 0 | 19749 |
| v024_badflag | 0 | 383 |
| v024_hold | 0 | 30720 |
| v024_lane | 0 | — |
| base_normal | 0 | — |
| base_multitask | 0 | — |
| base_bad_queue_magic | 0 | — |
| base_bad_vec_op | 0 | — |
| base_hold_b_c | 0 | — |

## Judge output

```
INFO DIV worst_rel=9.102e-04 bad=0
INFO SQRT worst_rel=5.089e-06 bad=0
INFO FMA vs mul+add differing vectors: 64/64
V024_CHECK PASS
```

## Key terminal lines

```
V024_FUSION used=1 c48_ddr_bytes=0 a16_bytes=2048
V024_DRAIN rd_pending=0 wr_pending=0 b_pending=0 quiesced=1 iso_blocked=0 held_b=0 returned_b=60
V024_END done=1 fault=0 error=00 iso=0 requires_reset=0 fetch_to=0 drain_timeout=0 cycles=18724
V024_RESULT PASS
V024_FUSION used=0 c48_ddr_bytes=0 a16_bytes=0
V024_DRAIN rd_pending=0 wr_pending=0 b_pending=0 quiesced=1 iso_blocked=0 held_b=0 returned_b=166
V024_END done=1 fault=0 error=00 iso=0 requires_reset=0 fetch_to=0 drain_timeout=0 cycles=16973
V024_RESULT PASS
V024_FUSION used=1 c48_ddr_bytes=0 a16_bytes=0
V024_DRAIN rd_pending=0 wr_pending=0 b_pending=8 quiesced=0 iso_blocked=0 held_b=8 returned_b=44
V024_END done=1 fault=1 error=0e iso=1 requires_reset=1 fetch_to=0 drain_timeout=0 cycles=30720
V024_RESULT PASS
```

No synthesis, STA, board, VNC or push. No frequency or
whole-model-seconds claim.
