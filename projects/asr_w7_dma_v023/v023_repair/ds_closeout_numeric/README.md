# ds_closeout_numeric

Isolated V0.23 numeric-closeout integration: the real `gemini_fma_round2`
FMA core and `gemini_approx_round2` DIV/SQRT core are wired into the system
vector path and exercised through the WCPG graph + shared AXI128 path.

Read first:

- `REPORT.md` — results, cycle/error tables, abort/reset evidence, limits.
- `INTERFACE.md` — RTL changes, unique build, descriptor/address contract.
- `result.json` — machine-readable result and SHA evidence.
- `patch/closeout_numeric.patch` — integration patch against the read-only
  `integrated` snapshot.
- `filelist_closeout_numeric.f` — unique build filelist.
- `logs/rc.txt`, `logs/*.log` — run return codes and simulation logs.

Reproduce (local logic simulation only):

```bash
bash run_all.sh
```

This is not a full-model, synthesis, STA, board or VNC result. The running
`v023_repair/integrated` directory was not modified.
