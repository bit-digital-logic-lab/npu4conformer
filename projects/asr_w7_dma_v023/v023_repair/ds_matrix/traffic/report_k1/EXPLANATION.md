# Ledger explanation

`axi_r` and `axi_w` have exact per-master reconciliation:
`ledger_minus_interval_valid_bytes = 0`.

`ddr_bfm` is the shared AXI128 BFM data-channel observation lane. Its payload
bytes are the union of the read and write masters, not a separate tensor
transfer ledger; therefore it has no transfer rows and its
`ledger_minus_interval_valid_bytes` is intentionally `-9216`. This is not
missing traffic and is not added to the per-master byte totals.

`c_cache_rd`, `c_cache_wr` and `packer` are on-chip activity lanes. They show
occupancy/state only; their `bytes` are 0 because this task does not claim
on-chip C48 movement as off-chip DDR traffic.
