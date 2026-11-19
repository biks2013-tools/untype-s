#include "untype_aec.h"

#include <new>

#include "api/audio/audio_processing.h"
#include "api/scoped_refptr.h"

struct UntypeAEC {
  rtc::scoped_refptr<webrtc::AudioProcessing> apm;
  webrtc::StreamConfig config;
  int frame_samples;
};

extern "C" {

UntypeAEC *untype_aec_create(int sample_rate) {
  if (sample_rate != 8000 && sample_rate != 16000 && sample_rate != 32000 && sample_rate != 48000) {
    return nullptr;
  }
  rtc::scoped_refptr<webrtc::AudioProcessing> apm = webrtc::AudioProcessingBuilder().Create();
  if (!apm) {
    return nullptr;
  }
  webrtc::AudioProcessing::Config config;
  config.echo_canceller.enabled = true;
  config.echo_canceller.mobile_mode = false;
  config.noise_suppression.enabled = false;
  config.gain_controller1.enabled = false;
  config.gain_controller2.enabled = false;
  config.high_pass_filter.enabled = false;
  apm->ApplyConfig(config);

  UntypeAEC *aec = new (std::nothrow) UntypeAEC{apm, webrtc::StreamConfig(sample_rate, 1), sample_rate / 100};
  if (!aec) {
    return nullptr;
  }
  if (apm->Initialize() != webrtc::AudioProcessing::kNoError) {
    delete aec;
    return nullptr;
  }
  return aec;
}

void untype_aec_destroy(UntypeAEC *aec) {
  delete aec;
}

int untype_aec_frame_samples(const UntypeAEC *aec) {
  return aec ? aec->frame_samples : 0;
}

int untype_aec_process_reverse(UntypeAEC *aec, const int16_t *frame) {
  if (!aec || !frame) {
    return -1;
  }
  // The reference is only analysed; its output is not used.
  int16_t discarded[480];
  return aec->apm->ProcessReverseStream(frame, aec->config, aec->config, discarded);
}

int untype_aec_process(UntypeAEC *aec, const int16_t *input, int16_t *output) {
  if (!aec || !input || !output) {
    return -1;
  }
  aec->apm->set_stream_delay_ms(0);
  return aec->apm->ProcessStream(input, aec->config, aec->config, output);
}

const char *untype_aec_library(void) {
  return "webrtc-audio-processing 2.1";
}

}  // extern "C"
