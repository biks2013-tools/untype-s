// A plain C interface over WebRTC's audio processing module, with echo
// cancellation (AEC3) only: no noise suppression, no gain control.
//
// Audio is mono PCM16 in frames of 10 ms (`untype_aec_frame_samples`).
// For every 10 ms: first the reference frame (what the loudspeakers play),
// then the microphone frame. Not thread-safe: one caller at a time.
#ifndef UNTYPE_AEC_H
#define UNTYPE_AEC_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct UntypeAEC UntypeAEC;

/// NULL when the rate is not 8000, 16000, 32000 or 48000 or the canceller
/// could not be made.
UntypeAEC *untype_aec_create(int sample_rate);
void untype_aec_destroy(UntypeAEC *aec);

/// Samples in one frame (the rate divided by 100).
int untype_aec_frame_samples(const UntypeAEC *aec);

/// The loudspeakers' audio for the next 10 ms. 0 on success.
int untype_aec_process_reverse(UntypeAEC *aec, const int16_t *frame);

/// The microphone's audio for the same 10 ms; `output` gets the cleaned
/// frame (it may be the same buffer as `input`). 0 on success.
int untype_aec_process(UntypeAEC *aec, const int16_t *input, int16_t *output);

/// The library behind this interface, e.g. "webrtc-audio-processing 2.1".
const char *untype_aec_library(void);

#ifdef __cplusplus
}
#endif

#endif
