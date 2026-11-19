# build-webrtc-apm

`scripts/build-webrtc-apm.sh` builds `Vendor/UntypeAEC/UntypeAEC.xcframework`: WebRTC's audio processing module (the echo canceller AEC3) as a static library, behind the small C interface in `Vendor/UntypeAEC/shim/` (`untype_aec.h`, `untype_aec.cc`). `Package.swift` uses the framework as the binary target `UntypeAEC`; `UntypeCore` reaches it through `WebRTCEchoCanceller` (`MeetingEchoCanceller.swift`). Plan-072.

The built framework is committed, so `swift build` and the packaging scripts need nothing extra. Run the script only to rebuild it: a new version of the library, or a change to the C interface.

## Usage

```
scripts/build-webrtc-apm.sh
MESON=/path/to/meson scripts/build-webrtc-apm.sh
```

No options. It builds for the architecture of the Mac it runs on (arm64 on the Macs used so far) with deployment target macOS 14.0, and takes about two minutes.

## What it needs

| Tool | How to get it |
|---|---|
| `meson` | `pip install meson` (any Python environment), or `MESON=` pointing at one |
| `ninja` | `brew install ninja` |
| Xcode command line tools | `clang++`, `libtool`, `xcodebuild`, `lipo` |
| Network | the source archive and abseil are downloaded |

## What it does

1. Downloads `webrtc-audio-processing-2.1.tar.xz` from freedesktop.org and checks its SHA-256 against the value pinned in the script; a mismatch stops the build.
2. Builds it with meson as static libraries, release, with abseil 20240722.0 from the archive's own wrap file (its checksum is pinned there).
3. Compiles the C interface and joins it with all the static libraries into `libUntypeAEC.a`.
4. Makes the XCFramework (the header and a module map that links `c++`) and replaces `Vendor/UntypeAEC/UntypeAEC.xcframework`.
5. Copies the licence texts to `Vendor/UntypeAEC/licenses/` (webrtc-audio-processing: BSD-3-Clause; abseil: Apache-2.0).

Work files are in `.build/untype-aec/` (ignored by git; logs of each stage are there when a stage fails).

## The C interface

Mono PCM16 in frames of 10 ms. For every 10 ms the reference frame (what the loudspeakers play) goes in first, then the microphone frame. Echo cancellation only: no noise suppression, no gain control. Rates: 8, 16, 32, 48 kHz. Not thread-safe.

| Function | Purpose |
|---|---|
| `untype_aec_create(rate)` / `untype_aec_destroy` | make and free a canceller (NULL for another rate) |
| `untype_aec_frame_samples` | samples per frame (rate / 100) |
| `untype_aec_process_reverse(frame)` | the loudspeakers' 10 ms |
| `untype_aec_process(input, output)` | the microphone's 10 ms, cleaned |
| `untype_aec_library` | name and version of the library |

## After a rebuild

`swift build`, `swift test` (the tests in `MeetingEchoCancellerTests.swift` link the library, cancel a synthetic echo and measure the library's own delay per rate against `WebRTCEchoCanceller.delays`; a new library version may change that delay, then the table is updated), then commit the framework together with the change that needed it.
