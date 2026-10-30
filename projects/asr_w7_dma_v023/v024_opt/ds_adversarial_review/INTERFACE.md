# INTERFACE — ds_adversarial_review (独立只读审查)

Status: **in progress**. This directory is the only place this task writes.
`v023_repair/`, `work/`, the ZIP and every other v024 worker directory are
read-only inputs. This task never edits a tested worker's RTL/TB.

## 1. What this task produces

| artifact | purpose |
|---|---|
| `INTERFACE.md` | this contract, published before results |
| `progress.json` | stage progress (S0..S8) |
| `FINDINGS.md` | defects/risks for module owners; each finding has a reproducer |
| `gold/` | implementation-independent reference models (Python), written from the spec, not from RTL |
| `tb/` | my own testbenches; drive the frozen DUT only through its published ports |
| `scripts/` | rerunnable, `-j1`, `timeout`-wrapped, nonzero-on-failure scripts |
| `reports/` | machine-readable per-run results and SHA manifests |
| `REPORT.md`, `result.json`, `filelist.txt` | final delivery |

## 2. Acceptance rule used here

A worker candidate is **ACCEPT** only when all of the following hold:

1. the exact candidate files are frozen by SHA-256 (recorded in
   `reports/frozen_shas.json`) before the run;
2. my independent gold, generated without importing or executing the worker's
   RTL/golden script, agrees bit-exactly (or within the explicitly documented
   approximate contract where applicable);
3. negative controls (wrong tail mask, scalar-only parameter, unmerged 96 B
   writes, early done, stale epoch, etc.) fail with a nonzero rc on the same
   test;
4. normal completion is after the last B response (`b_after_done=0`,
   `last_b < done`) and no old-epoch output is observable;
5. a rerun from the recorded filelist reproduces the result.

Module PASS alone is **not** integration PASS. Integration is only claimed after
the `ds_unified_graph` delivery is exercised as one real graph.

## 3. How an owner consumes a finding

`FINDINGS.md` entries are appended as `AR-00N`. Each contains: item, frozen
SHA, test, observed vs expected, minimal reproducer command, and severity.
Owners should fix in their own tree; this task will re-freeze the new SHA and
rerun the same test. Do not send patches into this directory expecting them to
be applied.

## 4. Test entry points (stable names)

```bash
bash scripts/run_fma.sh        <filelist-or-dut-dir>
bash scripts/run_epilogue.sh   <filelist-or-dut-dir>
bash scripts/run_vector_tail.sh <filelist-or-dut-dir>
bash scripts/run_write.sh      <filelist-or-dut-dir>
bash scripts/run_doneb.sh      <filelist-or-dut-dir>
bash scripts/run_graph_epoch.sh <filelist-or-dut-dir>
bash scripts/run_all.sh
```

Each returns 0 only on PASS. Logs and rc are written under `logs/<test>/`.

## 5. Explicit non-claims

No synthesis/Vivado/STA/board/VNC/push. No frequency or whole-model second
claim. Cycle counts are logic simulation of the named fixture only.
