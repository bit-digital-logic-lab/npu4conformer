#ifndef NATIVE_PL_H
#define NATIVE_PL_H
#include <stdint.h>

/* Single-owner A53 driver for the 2493 PS-DDR image. Shared DDR is mapped
 * Normal Non-cacheable; the AXI-Lite window is mapped Device. x and y must
 * be distinct. weights is resident W7p8 [Ktile,Ntile,32,32], little endian,
 * scales and optional bias each contain n float32 values. */
int native_pl_linear(const float *x, unsigned m, unsigned k, unsigned n,
                     const uint8_t *weights, const float *scales,
                     const float *bias, float *y);
/* Dense B is row-major [k,n]; PS packs dynamic W7; PL performs every MAC. */
int native_pl_dynamic(const float *x, unsigned m, unsigned k, unsigned n,
                      const float *b, float *y);

struct native_pl_profile {
    uint64_t cycles;
    uint32_t graphs, descriptors, error_csr;
};
extern struct native_pl_profile native_pl_profile;
/* Commissioning only: return 0 after independently checking every output.
 * On success float32 row-major results for the 35x1057x129 static test
 * remain at 0x07c40000 (35*129 little-endian words). */
int native_pl_selftest(void);
#endif
