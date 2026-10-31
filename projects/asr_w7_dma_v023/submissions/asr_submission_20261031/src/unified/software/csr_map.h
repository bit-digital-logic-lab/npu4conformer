/* V0.24 export CSR constants — documentation only, not a driver. */
#ifndef V024_CSR_MAP_H
#define V024_CSR_MAP_H

#define V024_CSR_STATUS          0x04u
#define V024_CSR_PLAN_BASE       0x08u
#define V024_CSR_PLAN_COUNT      0x0Cu
#define V024_CSR_START           0x10u
#define V024_CSR_COMPLETED       0x14u
#define V024_CSR_LAST_NODE       0x18u
#define V024_CSR_ERROR_CODE      0x1Cu
#define V024_CSR_CYCLES_LO       0x20u
#define V024_CSR_CYCLES_HI       0x24u
#define V024_CSR_FETCH_LO        0x30u
#define V024_CSR_FETCH_HI        0x34u
#define V024_CSR_OPERATOR_LO     0x38u
#define V024_CSR_OPERATOR_HI     0x3Cu
#define V024_CSR_VECTOR_TOTAL_LO 0x40u
#define V024_CSR_VECTOR_TOTAL_HI 0x44u
#define V024_CSR_LAYOUT_TOTAL_LO 0x48u
#define V024_CSR_LAYOUT_TOTAL_HI 0x4Cu
#define V024_CSR_MATRIX_TOTAL_LO 0xA0u
#define V024_CSR_MATRIX_TOTAL_HI 0xA4u
#define V024_CSR_MATRIX_PE_LO    0xA8u
#define V024_CSR_MATRIX_PE_HI    0xACu
#define V024_CSR_ISO_STATE       0xB0u
#define V024_CSR_RD_PENDING      0xB4u
#define V024_CSR_WR_PENDING      0xB8u
#define V024_CSR_B_PENDING       0xBCu
#define V024_CSR_ISO_BLOCKED     0xC0u
#define V024_CSR_QUIESCED        0xC4u
#define V024_CSR_LOCKOUT_REJECTS 0xC8u

#define V024_STATUS_BUSY         (1u << 0)
#define V024_STATUS_DONE_LATCHED (1u << 1)
#define V024_STATUS_FAULT        (1u << 2)

#define V024_ERR_WATCHDOG        0x0Eu
#define V024_ERR_PLAN            0x04u
#define V024_ERR_PAYLOAD         0x07u

#endif /* V024_CSR_MAP_H */
