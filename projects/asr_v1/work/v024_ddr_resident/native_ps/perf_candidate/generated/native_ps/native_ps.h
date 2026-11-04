#ifndef NATIVE_PS_H
#define NATIVE_PS_H
#include <stdint.h>
#define ASR_MAILBOX_ADDR 0x08000000u
#define ASR_INPUT_ADDR   0x08010000u
#define ASR_OUTPUT_ADDR  0x08100000u
#define ASR_SCRATCH_BASE 0x08200000u
#define ASR_SCRATCH_END  0x0f000000u
#define ASR_MAX_FEATURE_FRAMES 1876u
#define ASR_READY 1u
#define ASR_BUSY 2u
#define ASR_DONE 3u
#define ASR_FAILED 4u
#define ASR_SELFTEST 1u
#define ASR_ENCODE 2u
/* Sole host publishes command, frames and input first, then request_seq.
 * A53 publishes data, metadata and terminal state before response_seq. */
struct asr_mailbox {
    uint32_t magic, abi, state, capabilities;
    uint32_t request_seq, response_seq, command, feature_frames;
    int32_t result;
    uint32_t encoder_frames, pl_calls, stage;
    uint64_t elapsed_ticks;
    uint32_t timer_hz, selftest_mask;
};
void ps_layernorm(const float *x, float *y, unsigned rows, unsigned channels,
                  const float *gain, const float *bias);
void ps_swish(float *x, unsigned count);
void ps_softmax(float *x, unsigned rows, unsigned cols);
void ps_glu(const float *x, float *y, unsigned rows, unsigned channels);
void ps_depthwise(const float *x,float *y,unsigned rows,unsigned channels,
                  const float *w,const float *bias,unsigned kernel);
int ps_selftest(void);
#ifdef ASR_ENCODER_ENABLED
int encode_features(const float *features,unsigned frames,float *output,volatile struct asr_mailbox *box);
#endif
#endif
