# CSR map (V0.24 export)

Base: AXI4-Lite, 24-bit byte address. Read low word then high word for 64-bit
banks. This mirrors `docs/design/ABI.md`; the RTL is authoritative.

| Offset | Name | Access | Notes |
|---:|---|---|---|
| 0x04 | STATUS | R | `{29'd0, fault, done_latched, busy}` |
| 0x08 | PLAN_BASE | R/W | WCPG plan base |
| 0x0C | PLAN_COUNT | R/W | 1 for this candidate |
| 0x10 | START | W | write 1; rejected if `requires_reset=1` |
| 0x14 | COMPLETED | R | completed node count |
| 0x18 | LAST_NODE | R | last completed node id |
| 0x1C | ERROR_CODE | R | see error table |
| 0x20/0x24 | CYCLES | R | total cycles low/high |
| 0x30/0x34 | FETCH_CYCLES | R | fetch low/high |
| 0x38/0x3C | OPERATOR_CYCLES | R | operator low/high |
| 0x40/0x44 | VECTOR_TOTAL | R | sum over ops |
| 0x48/0x4C | LAYOUT_TOTAL | R | sum over ops |
| 0x50..0x5C | VEC/LAY BYTES | R | read/write bytes |
| 0x60..0x6C | R/W OVERLAP | R | overlap counters |
| 0x70/0x74 | VEC/LAY ELEMS | R | element counters |
| 0x78/0x7C | NUM FLAGS/ERR | R | numeric flags and error |
| 0x80/0x84 | LAYOUT HIT/MISS | R | layout cache |
| 0x90..0x9C | PARAM/GEN/MAGIC | R | parameter window state |
| 0xA0/0xA4 | MATRIX_TOTAL | R | sum over tasks |
| 0xA8/0xAC | MATRIX_PE | R | PE cycles |
| 0xB0 | ISO STATE | R | `{30'd0, requires_reset, isolation}` |
| 0xB4 | RD_PENDING | R | outstanding AR |
| 0xB8 | WR_PENDING | R | outstanding AW |
| 0xBC | B_PENDING | R | outstanding B |
| 0xC0 | ISO_BLOCKED | R | new requests blocked while isolated |
| 0xC4 | QUIESCED | R | `{31'd0, port_quiesced}` |
| 0xC8 | LOCKOUT_REJECTS | R | START rejected while lockout |
