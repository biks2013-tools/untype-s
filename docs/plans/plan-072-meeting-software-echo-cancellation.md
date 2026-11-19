# Plan 072 - Meeting: echo cancellation in software, the microphone left alone

Date: 2026-11-19. FR-71 changed (same requirement, new implementation). Replaces the mechanism of plan-065.
Status: implemented, steps 1 to 7 done (2026-11-19) on branch `meeting-software-echo-cancellation`; not yet tried in
the installed app and not released (see Verification and "Not in this plan / open").

## Why
With "Remove speaker sound from the microphone" on (plan-065, Apple voice processing), the call application stops
getting the user's voice. Reproduced in a live Teams meeting on 2026-11-19 (build 73): the transcription window had
the user's words, Teams' microphone indicator showed nothing and the other side heard nothing. The macOS audio log
shows that when untype's voice processing starts, Teams' microphone input is stopped and restarted (and again when it
stops) and other apps' output is ducked; with the switch off Teams' input is never touched (details
in `Issues - Pending Items.md`, P1 of 2026-11-19). No setting of Apple voice processing was found that avoids this:
it changes the shared microphone device, not a private capture.

## Measurement (offline, 2026-11-19)
WebRTC's echo canceller (AEC3, `webrtc-audio-processing` 2.1) run over saved recordings without headphones, echo
cancellation off, the saved system audio as the reference (16 kHz, decoded from the 32 kbit/s AAC files; scripts in
`test_scripts/aec-eval/`).

| Recording | Content | Result |
|---|---|---|
| `recording-2026-11-19-13-30`, 478 s | almost only the call | call's sound in the microphone −20.0 dB → −45.7 dB; median reduction 41 dB |
| `recording-2026-11-19-16-11`, 337 s | the call and the user | median reduction 32 dB while the call talks; the user's own speech changes by about 2.6 dB |

`recording-2026-11-19-16-11` transcribed with `test_scripts/voice-filter/probe.ts` (Soniox):

| Microphone audio | Words | Also in the call's transcript within 6 s |
|---|---|---|
| original | 838 | 658 |
| after AEC3 | 120 | 0 |

The 120 words are the user's own sentences (read against the original). Apple voice processing measured −58 to
−60 dB in plan-065.

Found on the way: the two streams are not in step. In `recording-2026-11-19-13-30` the echo is 23 ms after the system
audio; in `recording-2026-11-19-16-11` the system audio is 1.96 s **late** for the whole recording (ScreenCaptureKit
delivered it late; untype places it by arrival time). The test needed the microphone delayed by 2 s by hand.

## Options considered
1. WebRTC AEC3 with the system audio as the reference (chosen; the only one measured).
2. SpeexDSP's echo canceller: small C code, easy to vendor; quality not measured. Fallback if step 1 fails.
3. Our own adaptive filter in Swift (Accelerate): no dependency; not measured, the most work for the least certainty.
4. Apple voice processing on another input device than the call's: needs a second microphone. Rejected.
5. Removing echo cancellation and relying on "only my voice" (plan-070): works for the transcript, the saved
   microphone audio keeps the echo, people in the room are dropped. Stays available next to this plan.

## Design

### The canceller
- `MeetingEchoCanceller` (new file, `UntypeCore`): takes the system audio (reference) and the microphone audio, both
  mono PCM16 at `MeetingRecorder.sampleRate`, each chunk with its capture time; gives back the cleaned microphone
  audio with the capture time of each chunk. Works in 10 ms frames. One serial queue; no audio thread blocks on it.
- The echo canceller itself behind a small C interface (`create`, `process_reverse(frame)`, `process(frame)`,
  `destroy`): a C++ shim over `webrtc::AudioProcessing` with echo cancellation only (no noise suppression, no gain
  control), so Swift sees plain C. A protocol `EchoCancelling` in Swift with the WebRTC implementation and a
  pass-through, so the alignment code is tested without the library.

### Alignment (the part the measurement showed is needed)
- Capture times instead of arrival times: the microphone tap's `AVAudioTime.hostTime` (today dropped in
  `AVFoundationAudioSource.handleInputBuffer`) and the system audio's `CMSampleBuffer` presentation time (today
  dropped in `MeetingSystemAudioCapture`). Both become seconds on the uptime clock next to the PCM.
- The reference is kept in a buffer indexed by capture time (silence where nothing was delivered). A microphone
  frame is processed as soon as the reference for its time has arrived, and after 3 s with the reference there is
  (counted, logged once in step 4). (As built in step 3; the first version of this plan had a fixed hold of the
  observed delivery delay plus a margin, which waits longer than needed.)
- The reference given to the canceller with a microphone frame of time t is the system audio of time t **plus**
  40 ms (`referenceAdvance`), so the canceller always sees the echo after its reference, also when the two streams'
  positions are each off by the tolerance of 15 ms; AEC3's own delay estimation covers the rest (loudspeaker and
  room delay). (The first version of this plan said "minus about 20 ms": the sign was wrong, see step 3.)
- Step 1 measures whether ScreenCaptureKit's presentation times are right when delivery is late. If they are not,
  the offset is estimated by cross-correlation of the two streams (as `test_scripts/aec-eval/lagscan.py` does) at
  the start and checked every few seconds; the plan is then updated before step 3.

### In the recorder
- `MeetingRecorder`: with `options.echoCancellation` the microphone is an ordinary `AVFoundationAudioSource`
  (no `voiceProcessing`), exactly as with the switch off. Order for a microphone chunk: dictation mute
  (`MeetingMicrophoneGate`, at capture, as today) → canceller → waveform, Soniox stream, audio file. The system
  audio goes to the canceller and, unchanged, to its own stream and file.
- Times: the microphone's audio reaches Soniox late by the hold. The microphone stream's segment times are shifted
  back by it (as `MeetingUserVoiceFilter` shifts by the sample's length), so the transcript's order is as spoken.
  The live text of the user's side is late by the hold (up to about 2 s when ScreenCaptureKit is late).
- Saved audio: `MeetingAudioRecorder.push(_:side:at:)` gets the capture time for both sides instead of the arrival
  time. This also puts `.mic.m4a` and `.system.m4a` (and the mixed file) in step, with the switch on or off.
- Failure: if the canceller cannot be created or fails, the recording continues without it and says so once
  (`diagnostic.warning`); it never stops a meeting.
- At the end one log line: seconds processed, the hold's range, the level of the microphone before and after while
  the call was talking.

### What goes away
- `AVFoundationAudioSourceOptions.voiceProcessing` and `PCM16MonoConverter(firstChannelOnly:)`.
- The shared microphone of plan-065: `MeetingSharedMicrophone.swift`, `SharedMicrophoneAudioSource`,
  `MeetingRecorder.sharedMicrophone` / `onSharedMicrophoneChanged`, and in `NativeUntypeUILauncher`
  `sessionUsesSharedMicrophone`, `alignSessionMicrophone`, `sharedMicrophoneChanged`, and the refusal to start a
  recording during a dictation. Push-to-talk then always has its own microphone, as it has today with the switch
  off. This is a change to push-to-talk's wiring and is verified as such (see Verification).

### Setting
- Unchanged: `meeting.echoCancellation` in `ui-state.json`, Settings → Meetings → Audio → **Remove speaker sound from
  the microphone**, off by default. Who has it on gets the new mechanism. It can be on together with "Only my voice".

### The library
- `webrtc-audio-processing` 2.1 (BSD-3-Clause; abseil, Apache-2.0, inside it), built as a static library for arm64
  with the C shim, as an XCFramework used by `Package.swift` as a binary target; `scripts/build-webrtc-apm.sh`
  rebuilds it from a pinned source archive (checksum checked). Static, so nothing new to embed or sign in the app;
  `scripts/package-macos-app.sh` and `scripts/install-local-build.sh` stay as they are unless step 1 shows otherwise.
- Licence texts of both in `Vendor/UntypeAEC/licenses/`. The app shows no third-party notices anywhere (checked in
  step 1); where it should is the maintainer's call.
- Decided in step 1: the built XCFramework (6.4 MB) is committed, so a fresh clone builds without meson.

## Steps
1. Spike: build the static library and the C shim; a command-line check that the Swift target links and cancels a
   synthetic echo; log ScreenCaptureKit's presentation time against arrival in a real recording. Stop here and
   report if the library cannot be built or linked cleanly (then option 2).
2. Capture times through `AVFoundationAudioSource` and `MeetingSystemAudioCapture` (no behaviour change yet), then
   the audio files placed by capture time.
3. `MeetingEchoCanceller` with the alignment, and its tests.
4. Recorder wiring, the time shift of the microphone's segments, the log line.
5. Removal of voice processing and of the shared microphone.
6. A replay command for saved recordings through the app's own canceller (extension of `test_scripts/aec-eval/`,
   documented in `docs/tools/`), run on the recordings above and scored like the measurement.
7. Documents: `project-design.md`, `project-functions.md` (FR-71), `configuration-guide.md`,
   `Issues - Pending Items.md`.

## Step 1 - results (2026-11-19)
- The library builds: `scripts/build-webrtc-apm.sh` (docs: `docs/tools/build-webrtc-apm.md`) makes
  `Vendor/UntypeAEC/UntypeAEC.xcframework` (arm64, static, 6.4 MB) from the pinned source archive, with the C interface
  of `Vendor/UntypeAEC/shim/`. `Package.swift`: binary target `UntypeAEC`, `UntypeCore` depends on it and links `c++`.
- Swift side: `EchoCancelling` and `WebRTCEchoCanceller` (`MeetingEchoCanceller.swift`); nothing uses them yet, so the
  app behaves as before.
- Tests (`MeetingEchoCancellerTests.swift`): the library is linked; a synthetic echo (the reference 40 ms later
  through a short room response) is reduced by more than 20 dB after 4 s and a second voice is kept within 3 dB; a
  frame of the wrong length goes through. `swift build`, `swift build -c release` (no new dynamic library in
  `otool -L`), 466/466 tests.
- Decided: the built framework is committed (a fresh clone builds without meson).
- ScreenCaptureKit's timestamps (`test_scripts/aec-eval/system-audio-timing.swift`, the app's own stream settings):
  buffers of 20 ms arrive continuously, also when nothing plays; the presentation time is on the uptime clock
  (`ProcessInfo.systemUptime`); arrival is 42 to 70 ms after it (four runs). With the delivery queue blocked for 2 s
  the waiting buffers arrive 2029 ms late and catch up within a second (47 ms at the end), their timestamps still
  those of the audio; 760 ms of audio were dropped and the timestamps show the gap. So the timestamps are right
  when delivery is late, and alignment by timestamps stands; the cross-correlation fallback is not needed (it stays
  as a check in the replay of step 6).
- This also explains the 1.96 s of `recording-2026-11-19-16-11`: the first system audio arrived late (2.3 s after
  the start), the file was started at its arrival and everything after it appended, so the offset stayed.
- Third-party notices: the app shows none anywhere and the README's licence section says "Not yet declared"; the
  two licence texts are in `Vendor/UntypeAEC/licenses/`. Where the app should show them is the maintainer's call.
- Not measured yet: the microphone tap's `AVAudioTime.hostTime` against the same clock (step 2), and the size the
  library adds to the app (nothing calls it yet, so the linker drops it; known after step 4).

## Step 2 - results (2026-11-19)
- Microphone timing measured (`test_scripts/aec-eval/microphone-timing.swift`, the app's tap without voice
  processing, two runs): every buffer has a valid host time; the host-time clock and `systemUptime` differ by 3 µs;
  buffers are 100 ms (4,800 frames at 48 kHz, although the tap asks for 1,024) and arrive 102 to 112 ms after their
  host time, i.e. the host time is the capture time of the first sample; the times are continuous.
- `AudioSourceEventHandlers.timedAudio` (optional, default nil): `AVFoundationAudioSource` calls it with the buffer's
  capture time (`captureTime(of:frames:sampleRate:)`: the host time, or arrival minus length without one) when set,
  else `audio` as before. Dictation sets no `timedAudio`, so push-to-talk's audio path is unchanged.
- `MeetingSystemAudioCapture` hands each chunk over with its presentation time (`captureTime(presentation:...)`).
- `MeetingAudioRecorder.push(_:side:capturedAt:)` (was `at:` = arrival): the chunk's end for the timeline is its
  capture time plus its length. The recorder passes capture times for both sides; the waveforms and the Soniox streams
  are unchanged (they still use arrival).
- Tests: the existing audio tests moved to capture times; new: a side delivered late in one burst is placed where it
  was captured; both capture-time helpers with and without a valid time; 470/470.
- Live (`MeetingAudioLiveTests.swift`, `UNTYPE_LIVE_AUDIO=1 swift test --filter MeetingAudioLive`; the real
  ScreenCaptureKit and microphone paths, a sentence spoken with `say` through the built-in loudspeakers, the call side
  held back 2.5 s and delivered in one burst): the microphone's echo is **28 ms** after the system audio in the saved
  files (correlation 0.48). The same run with the call side placed by arrival (the old behaviour): **−1456 ms**, and
  the test fails.
- For step 3: `AVFoundationAudioSource` hands every buffer to its own `Task`, so two buffers can in principle reach the
  handler out of order. The canceller must order the microphone's chunks by capture time (or the source must deliver
  through one serial path); not changed here because dictation shares that source.

## Step 3 - results (2026-11-19)
- `MeetingEchoAligner` (`MeetingEchoCanceller.swift`), a value without threads or clocks (every call is given the
  time): `pushReference`, `pushMicrophone`, `finish` give back the cleaned microphone audio in chunks of about
  100 ms with the capture time of their first sample. `MeetingEchoCanceller` puts it on a serial queue (both
  streams from their own threads; `finish()` returns `MeetingEchoStatistics`; `make(sampleRate:onOutput:)` with
  WebRTC's canceller, nil for a rate the library does not take).
- Both streams are kept by capture time on one sample grid. A chunk whose capture time is within 15 ms
  (`tolerance`) of where the samples counted so far put it is appended; beyond that the stream is set right. The
  reference: silence for missing audio, a chunk that is early goes where its time puts it. The microphone: silence
  for a gap up to 2 s (`maximumFill`; a longer gap ends the audio so far and starts again at its own time, nothing
  made up); audio that is early is kept and the times of what is held move back; no microphone sample is dropped,
  except a chunk that arrives after its place was taken (counted).
- Microphone chunks are sorted by capture time before use and wait up to 30 ms for one captured before them
  (`reorderWindow`): the point noted in step 2. In normal running this costs nothing, the reference is not there
  sooner.
- A frame goes on when the reference reaches 40 ms past it, when it lies before the first reference sample ever, or
  after 3 s (`maximumHold`).
- The canceller's own delay: WebRTC gives the microphone's audio back late, 128 samples (8 ms) at 16 kHz (88, 128,
  260, 430 samples at 8, 16, 32, 48 kHz; `WebRTCEchoCanceller.delays`, measured again by a test). The aligner takes
  it out: the output is the samples that came in, each at its capture time, also the last ones (silence pushes them
  out of the canceller at the end and before a long gap).
- Why the advance, measured (synthetic echo, how much of it is left by correlation): with 40 ms an echo that is
  40 ms after, at, or 20 ms **before** its reference is 56 dB down; with no advance the echo 10, 20 or 30 ms before
  its reference stays (2 dB down). So the reference must be given ahead, not behind.
- Level against what is left: in the synthetic tests the level over the call falls only by 20.6 dB whatever the
  delay, because WebRTC puts soft noise where it removed sound (about -48 dBFS there). The tests therefore measure
  how much of the echo is left (more than 30 dB down asked, 56 measured) and the user's voice (less than 3 dB down,
  at its own time).
- Clocks, measured (`microphone-timing.swift` and `system-audio-timing.swift`, ten minutes together): the
  microphone's host times advance 2.26 ms less than its samples counted (-4 ppm: the audio hardware's clock against
  the system's); the system audio's timestamps advance exactly with its samples (0.000 ms) and their smallest
  delivery delay per minute stays at 42.61 to 42.65 ms, so they follow the system clock too. Both streams' capture
  times are on one clock; the microphone's samples drift against it by 15 ms in about an hour, which the tolerance
  takes up in one step (a pause of 15 ms or times moved back by 15 ms). No clock correction is needed.
- Tests (`MeetingEchoCancellerTests.swift`, 25; the whole run: 493 pass, two of them, the live audio check and the
  replay, only do something when asked): exact pairing of microphone and call samples
  (signals that say which sample they are) with the call on time, 2 s late, missing, in bursts of a second, with
  0.76 s dropped; microphone chunks out of order, one too late, a short gap, a long gap, a clock 0.5 % slower and
  faster than the system's; a canceller that answers late (whole recordings, a long gap, recordings of 1 to 320
  samples); with WebRTC: the call removed when its audio is 2 s late, when the echo has no delay, when the streams'
  times are off by 20 ms, and the user kept; a silent call (headphones) leaves the microphone within 1 dB; the
  queued canceller from two threads. Each of five deliberate breakages of the aligner (no advance, the canceller's
  delay not taken out, no reorder window, no wait for the reference, the canceller's last audio not pushed out)
  fails tests.
- Real recordings through the app's own aligner and canceller (`MeetingEchoReplayTests.swift`,
  `UNTYPE_AEC_REPLAY=<base> swift test --filter meetingEchoReplay`, scored with a script that step 6 folded into
  `test_scripts/aec-eval/replay.py`; the replay is step 6's tool, made early):

  | Recording | Offline WebRTC (Measurement above) | The app's aligner and canceller |
  |---|---|---|
  | `recording-2026-11-19-16-11`, call 1.956 s late | median 32.2 dB; own speech 2.6 dB | median 31.6 dB; own speech 2.3 dB; held 2.06 s on average |
  | `recording-2026-11-19-13-30` | -20.0 dB → -45.7 dB; median 41.4 dB | -20.0 dB → -46.2 dB; median 41.3 dB; held 107 ms on average |

  Every sample came back (5,394,393 and 7,643,097), no frame without its reference, about 50 times real time in a
  debug build. The transcripts of these outputs were not made (step 6).
- Not done here: the recorder still uses Apple voice processing with the switch on (step 4 and 5).
- For step 4: the microphone's audio reaches Soniox late by the hold but in one piece and in capture order, with
  silence where the microphone paused; whether the stream's segment times need a shift is to be read from
  `MeetingSonioxStream` (its times count the audio sent, not the clock). An output device with a very long delay
  (AirPlay, about 2 s) is beyond what the canceller's delay search covers (about 0.6 s); to be said in the guide.

## Step 4 - results (2026-11-19)
- `MeetingRecorder.start`: with `options.echoCancellation` a `MeetingEchoCanceller` is made; the system audio goes to
  it as the reference (besides its own stream and file, unchanged); the microphone, after the dictation mute, goes to
  it instead of its stream and file, and its output goes to the microphone's Soniox stream and `.mic.m4a` with the
  capture times. If the canceller cannot be made: a warning and the microphone as it is. The microphone is **never**
  opened with Apple voice processing any more (`voiceProcessing` is no longer passed), with the switch on or off.
- The waveform of the microphone shows the microphone as it is, at once (not the cleaned audio, which comes up to
  seconds later).
- `tearDown`: microphone, system audio, then `finish()` of the canceller (what it holds goes to the stream and the
  file), then the files and the streams. Log line at the end (only when there was microphone audio),
  `MeetingRecorder.describe`: e.g. "meeting echo cancellation: 300 s of microphone; 26 dB quieter while the call had
  sound (240 s); held 107 ms on average, 1172 ms at most", plus seconds without the call's audio, silence put in and
  late chunks when there were any.
- Segment times: not shifted. `MeetingSonioxStream`'s times count the audio it was sent, from the stream's start; the
  canceller sends the microphone's samples whole, in capture order, so the times are the same as without it; only the
  live text is later by the hold.
- Kept for step 5: the shared microphone (dictation during such a recording takes the meeting's microphone, now
  unprocessed), the launcher's refusal to start such a recording during a dictation, `AVFoundationAudioSourceOptions
  .voiceProcessing` (now unused by the recorder).
- Texts: the Settings caption of Meetings → Audio (no longer says the call app can hear the user worse; says the live
  text can lag and AirPlay is not covered), the comment of `MeetingPreferences.echoCancellation`, the guide's row.
- Tests: the log line (`theEchoCancellationsLogLineSaysWhatItDid`); 495 pass. Live
  (`UNTYPE_LIVE_AUDIO=1 swift test --filter MeetingAudioLive`, new test
  `meetingEchoCancellationRemovesTheLoudspeakersInRealTime`: the real microphone and ScreenCaptureKit through
  `MeetingEchoCanceller` in real time, `say` through the built-in loudspeakers, the system audio held back 1.5 s and
  delivered in one burst): the loudspeakers' voice in the microphone **-30.2 dB → -57.6 dB (27.4 dB less)**; the
  canceller's own count 25 dB; held 126 ms on average, 812 ms at most. The alignment test again: 33 ms, correlation
  0.80.
- Not tried: the installed app in a real call (needs a build installed on this Mac; the installed app is the
  maintainer's Developer ID build 73, and a differently signed build loses the Accessibility grant).

## Step 5 - results (2026-11-19)
- Removed: `AVFoundationAudioSourceOptions.voiceProcessing` (and `setVoiceProcessingEnabled`, the ducking setting),
  `PCM16MonoConverter(firstChannelOnly:)`, `MeetingSharedMicrophone.swift` (`MeetingSharedMicrophone`,
  `SharedMicrophoneAudioSource`), `MeetingRecorder.sharedMicrophone` / `onSharedMicrophoneChanged` and the publish of
  the microphone to it; in `NativeUntypeUILauncher`: `sessionUsesSharedMicrophone`, the shared source given to
  `makeForUI`, `alignSessionMicrophone`, `sharedMicrophoneChanged`, and the refusal to start a recording with echo
  cancellation during a dictation turn or a manual session (notice "Finish the dictation, then start the recording").
- Kept: `UntypeRuntimeFactory.makeForUI(audioSource:)` (an optional parameter, now not passed by the app);
  `MeetingPreferences.echoCancellation` / `removesSpeakerSound` and its test (moved to `MeetingEchoCancellerTests`).
- Push-to-talk: the launcher change is removal only; the session is created as with the switch off (its own
  `AVFoundationAudioSource`, the same audio gate); hotkey monitor, press and release handling, overlay and delivery are
  untouched. During every recording dictation now has its own capture next to the meeting's (two unprocessed captures
  in one process, as with the switch off since plan-061); the dictation mute of plan-064 still keeps a turn out of
  the meeting.
- Texts: FR-71 rewritten; the design entry of plan-065 marked replaced; the caption and the guide no longer say that
  dictation uses the meeting's microphone.
- Tests: 490 pass (the five shared-microphone tests went with their code). Live again with the simplified source:
  alignment 33 ms (correlation 0.79); echo -28.1 dB → -57.5 dB (29.4 dB less), held 124 ms on average, 891 ms at most.
- To check in the installed app (needs a build installed; see "Not in this plan"): push-to-talk held and hands-free
  before, during and after a recording with the switch on, `focused_input.ok=true` in `release-latency.jsonl`; a
  recording started while holding push-to-talk; the log no longer shows "push-to-talk session restarts with the
  meeting's microphone".

## Step 6 - results (2026-11-19)
- `test_scripts/aec-eval/replay.py <recording folder>` (docs: `docs/tools/aec-eval.md`, listed in CLAUDE.md's Tools):
  decodes the saved audio, measures how late the system audio is in the files, runs the microphone through the app's
  aligner and canceller (`meetingEchoReplay`), prints the levels, transcribes the original and the cleaned microphone
  with `probe.ts` and counts the words also said by the call. It replaces the separate scoring script of step 3.
- `MeetingEchoReplayTests`: `finish` at the last arrival (it was one second later, which counted as hold).

  | Recording | Call talking: microphone | Call's words on the user's side | The user alone |
  |---|---|---|---|
  | `recording-2026-11-19-16-11` (call 1.955 s late in the files, measured) | -19.3 → -31.4 dB, median 31.8 dB | 658 → **0**; 126 own words kept | -2.3 dB |
  | `recording-2026-11-19-13-30` | -20.0 → -46.2 dB, median 41.3 dB | 791 → **1**; 8 own words kept | -2.7 dB |

  The 126 words left of `recording-2026-11-19-16-11` are the user's own sentences (read: "Αν το ενεργοποιήσω το
  echo cancellation, δεν παίζει …", "Με πιάνει το transcript. Ναι, αλλά δεν σε πιάνει η άλλη …").
- Not measured: words the user said while the call was talking (double talk) and whether they survive; the
  recordings have little of it.

## Step 7 - results (2026-11-19)
- Checked and brought up to date: `project-design.md` (the plan-072 entry, the plan-065 entry marked replaced, the
  saved audio's placement by capture time), `project-functions.md` (FR-71 rewritten, change log),
  `configuration-guide.md` (the Meetings row), the Settings caption, `docs/tools/build-webrtc-apm.md`,
  `docs/tools/aec-eval.md`, CLAUDE.md's Tools, `Issues - Pending Items.md` (the P1 item rewritten as problem, cause,
  fix, verified, to check, limits, workaround; the plan-065 P1 item marked superseded; the plan-070 item points to
  the measured cause). README: nothing about echo cancellation to change.
- `swift build`, `swift build -c release`, 490 tests.

## Verification
Done (2026-11-19):
- `swift build`, all tests (490). Alignment with the reference on time, 2 s late, missing, arriving in bursts;
  microphone chunks out of order, late, with gaps, with a clock 0.5 % off; a synthetic echo removed (what is left of
  it more than 30 dB down, 56 measured) with the second voice kept within 3 dB at its own time; a frame the library
  refuses goes through; capture-time placement of the audio files. The segments' time shift turned out not to be
  needed (step 4). The tests of plan-065 that covered the shared microphone were removed with the code.
- Replay (step 6) on `recording-2026-11-19-13-30` and `recording-2026-11-19-16-11`: call words left on the
  microphone's side 1 and 0, the user's sentences kept.
- Live with the real capture paths (steps 2, 4, 5): files in step; the loudspeakers' voice 27 to 29 dB lower in real
  time.

Not done: everything in the installed app.
- In the installed app, in a real call without headphones, switch on: (1) the other side hears the user the whole
  time and the call application's microphone indicator moves; (2) the call's words are only on the call's side of
  the transcript; (3) `.mic.m4a` does not hold the call and is in step with `.system.m4a`; (4) the call's volume is
  not lowered; (5) push-to-talk held and hands-free during and after the recording, `focused_input.ok=true` in
  `release-latency.jsonl`; Push-to-Act; (6) the dictation mute of plan-064; (7) the macOS audio log shows no
  `VPAUAggregateAudioDevice` and no stop of the call application's microphone input at start or stop.
- Also to check: headphones (nothing to cancel: the microphone must come through unchanged), an output device
  changed during a recording, a meeting of 30+ minutes (drift between the two streams).

## Not in this plan / open
- A release: needs the maintainer's Developer ID signing and notarization.
- Trying the branch in the installed app: the installed app is the maintainer's Developer ID build 73. Any other
  signature loses its Accessibility grant (focused-input delivery; recovery in CLAUDE.md's guardrails).
  `scripts/install-local-build.sh` needs the "untype Local Signing" identity, which this Mac (the contributor's) does
  not have: either its one-time setup (`docs/tools/install-local-build.md`) and re-granting Accessibility, or the
  check is done by the maintainer.
- The transcript's order between the two sides still comes from each stream's own clock; only the audio files and
  the canceller use capture times.
- Intel Macs: the library is built for arm64 only; the packaging script builds for the build machine's architecture
  (`swift build -c release`, no architecture option), which is arm64 here.
