# Iterative FNV-1a selected OOC candidate

`wc_graph_ctrl_iterhash.sv` and `wc_graph_ctrl_iterhash.patch` preserve a separate source candidate. After 17 strict regression cases and independent review, this source was selected through an explicit OOC source override. The original `rtl/graph/wc_graph_ctrl.sv` remains unchanged. Candidate/base SHA256 values are in `ITERHASH_MANIFEST.json`.

The original controller evaluates 15 chained FNV rounds for its header and 48 chained rounds for each node in one cycle. The preserved original synthesis RTL statistics show 63 constant 25x32 multiplier operations. That original synthesis was intentionally stopped before completion. No final utilization/timing report was obtained, so this structural finding must not be described as a measured timing failure.

The candidate shares exactly one `fnv(hash, word)` datapath and adds two states:

1. HHASH: visits header words 0..15 in 16 cycles; word 7, containing the stored expected hash, is explicitly skipped.
2. NHASH: visits all 48 words of each node in 48 cycles. The result of the final word of the final node is compared against the original expected checksum. Scheduling begins only after equality.

No checksum field is dropped. The FNV seed, recurrence, 32-bit modulo arithmetic, traversal order, plan format, node semantics, prior validation and capture of each DMA beat are unchanged. Node metadata is committed after the original semantic validation, as before; no operator can see it until the whole-plan checksum passes.

The header/node buffers are stable during their hash states because these states assert neither fetch request nor read-ready. They add bounded internal work, not an external wait; the existing fetch-watchdog states are unchanged. `cycles` includes the new work; `fetch_cycles` continues to count only active fetch states. Parameter/generation invalidation during the new states takes the existing fault path and prevents a subsequent fetch.

For seven nodes, the added hash states number 16 + 7*48 = 352. Total testbench/CSR latency must be measured again because the changed schedule can change AXI stalls. No previous cycle count may be reused as a candidate measurement.

A multicycle timing exception on the old chain is not justified: the final DMA beat may update node_buf just before the original one-cycle hash capture. Waiting between descriptors does not guarantee that all input words have been stable for 48 cycles. The candidate introduces the actual sequential stages instead of suppressing timing analysis.

The separate single-thread XSim run checks all original eleven regression cases, three graph-capacity/dependency boundaries, and three corruption cases. The corruption cases independently alter stored checksum, an otherwise valid header flags bit, and an otherwise valid node input-id word without recomputing the checksum. Testbench assertions require stable captured buffers and prohibit DMA/dispatch during hashing. Logs and independent numerical/length/hash results are kept under `iterhash_logs/` and `REGRESSION_ITERHASH.json`.

Selection was made from structural evidence, successful strict regression, and independent review; the original OOC run was then intentionally stopped to avoid parallel core syntheses and memory pressure. The new two-thread OOC run uses the selected source hash. Final synthesis, timing closure and board operation remain unverified until their actual reports/results exist. The original regression and aborted-build evidence remain preserved.

