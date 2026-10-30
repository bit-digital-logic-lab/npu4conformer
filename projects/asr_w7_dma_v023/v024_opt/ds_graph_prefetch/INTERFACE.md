# INTERFACE — v024 graph/prefetch candidate (early, live)

Status: **local logic candidate, reproducible; full V0.24 acceptance is not
claimed.** This file was written early and is kept as the interface contract;
`REPORT.md` and `result.json` contain the final measured evidence.

Scope: `ds_closeout_safety` graph controller + shared AXI interconnect only.
Single clock. Logic simulation only. No synthesis/Vivado/STA/board/VNC/push.
No frequency or whole-model seconds claim.

## 1. Unique build entry

`filelist_graph_prefetch.f` is the only build list. It contains exactly one
definition of each module. The default `LOOKAHEAD_EN=0` preserves the v023
behaviour; `LOOKAHEAD_EN=1` is the opt-in prefetch candidate. The frozen v023
RTL is in `baseline_rtl/` and is compiled only through
`filelist_baseline_graph.f` for the same-input/same-BFM baseline comparison.

## 2. `wc_graph_ctrl` additions (opt-in)

New parameters:

```systemverilog
parameter integer LOOKAHEAD_EN = 0,      // 0 = v023 datapath, 1 = payload lookahead
parameter integer LOOKAHEAD_WINDOW = 8   // bounded forward search for next VEC/LAY
```

New states: `LREQ`, `LFETCH` (speculative payload fetch). The plan header and
all 192-byte node descriptors are still fetched and FNV-validated **before any
node dispatch**; lookahead never bypasses plan integrity. Because all node
descriptors are already cached, the lookahead target is the per-dispatch VEC
64-byte / LAY 128-byte payload descriptor, not a second node-descriptor fetch.
MAT's 64-byte queue descriptors remain inside the matrix child.

New telemetry outputs (also routed through `wc_graph_top_v023` and
`v023_integrated_top`):

| output | meaning |
|---|---|
| `lookahead_valid` | a validated payload is cached for `lu_node` |
| `lookahead_hits` | dispatches that consumed a cached lookahead payload |
| `lookahead_misses` | VEC/LAY dispatches that had to fetch payload JIT |
| `lookahead_fetches` | speculative payload fetches completed and validated |
| `lookahead_aborts` | speculative fetches discarded (ACL/dependency/epoch/error) |
| `lookahead_epoch[31:0]` | epoch cleared/incremented on START, fault, isolation, abort |
| `t_fetch/t_dispatch/t_engine/t_idle` | non-exclusive category counters (64-bit) |
| `t_fetch_only/t_engine_only/t_dispatch_only` | exclusive-union categories |
| `t_fetch_engine/t_dispatch_engine/t_fetch_dispatch/t_all` | overlap categories |
| `t_header_fetch/t_node_fetch/t_payload_fetch/t_lookahead_fetch` | fetch breakdown |

The exclusive-union invariant is `sum(all eight exclusive categories) == cycles`
for a completed graph run. This is the replacement for the rejected
`total - last-op counters = 59.8% control` arithmetic.

## 3. Lookahead safety contract

A payload is prefetched only when **all** hold:

1. **Address ACL**: the payload byte range passes `readable()` and lies in the
   read-only parameter or external window. Arena payloads are not prefetched.
2. **Dependency**: the candidate's predecessor mask is covered by
   `done_mask | active engine nodes`; we never run ahead of the dependency
   frontier.
3. **Self-modification prohibition**: the candidate payload range must not
   overlap the declared output range of the previous/active node (or any active
   engine). In this ABI VEC/LAY destinations are arena-only and payloads are
   param/external, so the check is defense-in-depth, not an assumption.
4. **Parameter read-only**: the BFM refuses any write to the param window
   (`PROTECT_PARAM=1`); the graph already rejects VEC/LAY payload bases outside
   the param window.
5. **SEQ exclusion**: if the plan contains any SEQ node, lookahead is disabled
   (`has_seq`). SEQ is not proven to be param-read-only, so it must not race a
   speculative descriptor read.
6. **Epoch**: every speculative fetch is tagged with `lu_start_epoch`; a
   START/fault/isolation/abort increments the epoch and invalidates the cache.
   A stale speculative beat can never be dispatched.

Existing SEQ vs MAT/VEC/LAY wait and in-flight mutual exclusion is unchanged:
`direct_idle=~|e_active`, `seq_active` covers dispatch-wait and in-flight, and
MAT/VEC/LAY dispatch still requires `!e_active[0]`.

## 4. Shared AXI stress contract

The interconnect is still one AXI4 128-bit slave port. The stress test drives
real multiple outstanding AR/AW (per-master credit 8, global queue 32), checks
owner/tag routing of every R beat, checks B routing with random B latency while
`b_pending>1`, and checks that `isolate=1` blocks all new AR/AW/W while accepted
R/B still drain to `quiesced=1`. It does **not** model DDR PHY, multiple HP
ports, or additive multi-port bandwidth.

## 5. Final measured results (same fixture/BFM/seed)

| item | result |
|---|---|
| total cycles v023 baseline / lookahead off / on | 23774 / 23774 / 23660 |
| real saved cycles | 114 (0.48%) |
| lookahead hits / misses / fetches / aborts | 6 / 1 / 6 / 0 |
| exclusive union (off) | fetch 383 + dispatch 8 + engine 23339 + idle 44 = 23774 |
| legacy last-op residual | 14218 = 59.805% (reproduced artifact, not control overhead) |
| per-op CSR residual | 463 = 1.95% |
| header prefetch saved cycles | 0 (header/node fetch must precede hash validation and dispatch) |
| payload fetch cycles off -> on | 115 -> 20, plus 243 overlapped lookahead cycles |
| final I16 / C48 vs independent gold | 0 / 0 mismatch, all three runs |
| AXI on rburst / rbeats | 130 / 1828 (unchanged; no extra DDR traffic) |
| multi-outstanding stress max rd/wr/b pending | 32 / 16 / 4, tag=0, data=0, quiesced=1 |
| lookahead safety | normal/multitask gold; SEQ overlap 0; hang 0x0E; bad queue 0x03; bad vec/lay 0x07; hold R/B pending; restart BRESP=2 |

Epoch behavior: normal run epoch=2; fault/isolation runs end with `valid=0` and
epoch 3 or 4. A plan containing SEQ has `has_seq=1` and `fetches=0`.

## 6. Reproduction

```bash
cd /home/yang/Desktop/项目/v024_opt/ds_graph_prefetch
bash scripts/run_all.sh
```

Every simulation has an external `timeout` and an in-TB cycle watchdog. Any
failed reference hash, output/gold mismatch, drain failure, tag error, or
watchdog exit makes the script exit non-zero. Old v023 PASS JSON is not used.
