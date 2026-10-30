# Integration status of this export

## 1. What was selected

The only integrated RTL in `rtl/` is the `ds_unified_graph` V0.24 stage:
`rtl/graph/v024_unified_top.sv` plus its unique filelist. The stage's own
`result.json` reported six simulations rc=0 (fused, fallback, multi-consumer,
bad flag, hold-B, directed FMA), a passing independent judge, and a focused
five-case base smoke.

## 2. Independent review history (not hidden)

`ds_adversarial_review` ended with `integration_accepted=false` and AR-012
"integration not deliverable at the review deadline". That review snapshot
predates the unified stage's final freeze: at review cutoff the fallback was
`rc=143` and no `result.json` existed; the reviewer itself listed "independent
integration rerun when ds_unified_graph publishes result.json" as unfinished.

After the final freeze, `ds_unified_graph/result.json` was published with
fallback rc=0 and all six simulations rc=0. This export does **not** relabel
the old rejection as a pass. Instead it:

1. copies the frozen unified sources byte-for-byte (with path-only changes to
   the generator/judge);
2. reruns the complete export entry in this directory;
3. records the observed rc in `logs/rc.tsv` and
   `docs/verification/RESULTS.md`.

The module findings AR-006/AR-008 and the deferred candidates remain deferred;
they are not in the integrated tree. See
`assets_manifest/UNSELECTED.md` and
`docs/verification/ADVERSARIAL_FINDINGS.md`.

## 3. What this proves / does not prove

Proves, if the export entry is PASS:

- the named small graph runs end-to-end in a single-clock RTL logic model;
- the fused path writes no C48 to DDR and produces 512/512 A16 words matching
  independent gold;
- explicit fallback to legacy C48 still works and matches 512/512 I16;
- bad `MATF` without `FUSION_ALLOW` terminates with `0x04`;
- a held A16 B response ends in isolation, not a false drain;
- directed single-rounding FMA differs from `mul`+`add` on 64/64 vectors;
- the default `FUSION_ALLOW`-clear baseline path still passes a focused smoke.

Does not prove:

- the full 512-dim ASR / 591-tensor DAG / CASE0000;
- sealed payload re-lowering or a complete host executor;
- synthesis, STA, Fmax, CDC, board DDR, VNC;
- whole-model seconds or WER/CER;
- that deferred module optimisations are integrated.

## 4. Acceptance

The main agent performs final acceptance. A zero process exit in this
directory is **not** acceptance by itself.
