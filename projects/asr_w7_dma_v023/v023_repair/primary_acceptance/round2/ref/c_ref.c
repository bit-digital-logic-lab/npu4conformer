/* Independent C reference for the numeric audit.
 * mode 0: 48-bit signed integer -> binary32 bits (C cast, RNE)
 * mode 1: binary32 bits -> signed int16 (lrintf, RNE, saturation)
 * Built with: gcc -O2 -o c_ref c_ref.c -lm
 * This is intentionally NOT the DUT's golden model.
 */
#include <stdio.h>
#include <stdint.h>
#include <string.h>
#include <math.h>
#include <stdlib.h>

int main(int argc, char **argv) {
    int mode = argc > 1 ? atoi(argv[1]) : 0;
    if (mode == 0) {
        unsigned long long v;
        while (scanf("%llx", &v) == 1) {
            int64_t s = (v & (1ULL << 47))
                            ? (int64_t)(v | 0xFFFF000000000000ULL)
                            : (int64_t)v;
            float f = (float)s;
            uint32_t b;
            memcpy(&b, &f, 4);
            printf("%08x\n", b);
        }
    } else {
        unsigned x;
        while (scanf("%x", &x) == 1) {
            float f;
            memcpy(&f, &x, 4);
            int out;
            if (isnan(f)) {
                out = 0;
            } else if (isinf(f)) {
                out = signbit(f) ? -32768 : 32767;
            } else if (f >= 32768.0f) {
                out = 32767;
            } else if (f <= -32769.0f) {
                out = -32768;
            } else {
                long q = lrintf(f);
                if (q > 32767) q = 32767;
                if (q < -32768) q = -32768;
                out = (int)q;
            }
            printf("%04x\n", (unsigned)(out & 0xffff));
        }
    }
    return 0;
}
