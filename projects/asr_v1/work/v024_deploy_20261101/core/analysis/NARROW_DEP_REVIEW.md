# Internal dependency-storage narrowing: backup only

This is a prepared two-line optimization, not selected or compiled. The active iterative-hash source and current OOC run are unchanged.

Change only `nd_dep` storage width from 1024 to MAX_NODES and its validated write slice to MAX_NODES. Keep `node_buf` at 1536 bits, the complete 1024-bit dependency legality check, all 48 hashed words, the WCPG v2 record layout, and MAX_NODES=128 capacity unchanged.

Proof for supported MAX_NODES<=1024:

1. The header must pass `0 < node_count <= MAX_NODES` before any node is admitted.
2. `nfetch_index` begins at zero, advances by one, and stops at `node_count-1`; descriptor node id must equal this index.
3. Before any `nd_dep` write, the unchanged validation rejects any bit outside `(1024'd1 << nfetch_index)-1`. Thus only predecessor indices strictly less than the current node can be set.
4. Consequently every admitted dependency bit at index MAX_NODES or above is zero. The other writes (reset and START) also store all zero.
5. Scheduling tests dependencies against `done_mask[MAX_NODES-1:0]`. Removing the proved-zero upper dependency region preserves readiness for every accepted plan. There is no writeback/export of `nd_dep` that exposes a changed layout.
6. Invalid high-bit dependencies still fail the full original 1024-bit check before the narrowed write. Full checksum input is untouched, including all zero or nonzero high-mask words in the fetched record.

For MAX_NODES=128, the logical storage reduction is 128*(1024-128)=114688 bits. Actual LUT/FF/BRAM savings require a new synthesis report; this is not a measured resource saving. The two-line patch is `wc_graph_ctrl_iterhash_narrowdep.patch`, and fingerprints are in `NARROW_DEP_NOT_APPLIED.json`.

If the current candidate does not fit, validate this candidate using the original eleven tests, graph capacity/dependency boundaries, checksum corruption rejection, and generation invalidation cases before its own synthesis. Do not silently substitute its DCP or retain the earlier candidate fingerprint.
