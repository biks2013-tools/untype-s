# AVFoundation / AVAudioEngine Audio Capture for `untype`

## Overview
This note covers the macOS microphone-permission path, `AVAudioEngine` input capture, conversion to mono PCM at configurable sample rates, shutdown behavior, failure diagnostics, and testability for the Swift `untype` replacement. The core implementation pattern is: check and request microphone permission first, start an `AVAudioEngine`, tap the input node, convert the tapped PCM into a fixed wire format with `AVAudioConverter`, and keep the real-time tap callback free of blocking work. Apple’s docs support that overall shape: microphone capture on macOS requires explicit permission and a purpose string in `Info.plist`, the input node is the engine’s capture source, taps are the mechanism for recording/observation, and `AVAudioConverter` is the supported route for sample-rate and PCM-format conversion. citeturn0search3turn0search8turn0search11turn0search6turn1search10turn6search4

## Key Concepts

### 1. Permission is app-centric, not just API-centric
For macOS apps, Apple documents two requirements for microphone access: a static `NSMicrophoneUsageDescription` string in the app’s `Info.plist`, and the `com.apple.security.device.audio-input` entitlement when the app uses hardened runtime / sandboxed audio input. Apple also provides permission APIs: `AVAudioApplication.requestRecordPermission` / `recordPermission` on modern macOS, and `AVCaptureDevice.authorizationStatus(for: .audio)` plus `requestAccess(for:completionHandler:)` for the capture-device flow. The system prompts the user the first time the app attempts to record or when permission is explicitly requested. citeturn0search11turn2search3turn0search5turn0search12turn0search3turn0search8

### 2. `AVAudioEngine.inputNode` is the capture source
Apple documents `AVAudioEngine.inputNode` as the singleton input audio node for the engine. You either connect downstream nodes or install a recording tap on it to receive captured audio. The input node reflects hardware sample rate and channel count when connected to hardware, and in manual rendering mode it can supply input synchronously to the engine. Apple also notes that when rendering from an audio device, the input node does not support format conversion, which is the key reason to perform downstream conversion rather than trying to coerce the node itself. citeturn0search6turn4search13turn6search5

### 3. `AVAudioConverter` is the format bridge
`AVAudioConverter` is the supported API for PCM bit-depth conversion, sample-rate conversion, and interleaving/deinterleaving. Apple’s sample-rate technote explicitly uses `convert(to:error:withInputFrom:)` for sample-rate conversion, and the simpler `convert(to:from:)` is only for conversions that do not involve sample-rate changes. The converter also exposes `downmix` and `channelMap`, which matter when converting multichannel input to a mono speech stream. citeturn1search10turn8search8turn12search1turn12search2turn12search9

### 4. `AVAudioPCMBuffer` is the handoff format
Apple documents `AVAudioPCMBuffer` as the PCM buffer type for audio processing, and its `frameLength` must be set before use. That matters because the output buffer passed to a converter must have a valid length and capacity relationship, or the conversion path will fail or produce incomplete output. citeturn1search5turn1search6

## macOS Microphone Permission Behavior

### App bundles
For a macOS app bundle, the documented path is straightforward: add `NSMicrophoneUsageDescription`, request permission before starting capture, and include the audio-input entitlement when the target is hardened/sandboxed. Apple’s docs also say that if the user has not yet granted or denied permission, the status is `notDetermined` and the app should call the relevant request API to trigger the system prompt. citeturn0search8turn0search11turn0search5turn2search3

### CLI tools
Apple’s documentation is app-oriented, not command-line-tool-oriented, but the same privacy gate still applies when a CLI uses microphone APIs. The practical implication for `untype` is that a bare executable should not rely on accidental behavior; it should be packaged with stable identity, purpose strings, and a tested permission path. Forum reports from Apple’s developer forums suggest that command-line permission prompts can be sensitive to how the executable is packaged and launched, including path changes across updates. Treat that as a warning sign rather than a documented guarantee. citeturn0search11turn0search3turn2search1

### Recommended permission flow
Use the modern permission API when available, fall back to the capture-device authorization API if you need older OS coverage, and fail fast with an explicit diagnostic when permission is denied. The permission check should happen before engine startup so the user sees an actionable prompt or error instead of a silent failure path. citeturn0search12turn0search3turn2search3

```swift
import AVFAudio
import AVFoundation

enum MicPermission {
    static func current() -> Bool {
        if #available(macOS 14.0, *) {
            return AVAudioApplication.shared.recordPermission == .granted
        } else {
            return AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        }
    }

    static func request(_ completion: @escaping (Bool) -> Void) {
        if #available(macOS 14.0, *) {
            AVAudioApplication.requestRecordPermission(completionHandler: completion)
        } else {
            AVCaptureDevice.requestAccess(for: .audio, completionHandler: completion)
        }
    }
}
```

## Input Capture Pipeline

### Recommended sequence
1. Check permission.
2. Read the hardware input format from the engine’s input node.
3. Start the engine.
4. Install a tap on bus `0`.
5. Convert tap buffers into the final wire format on a worker queue.
6. Drain, remove the tap, and stop the engine during shutdown.  
This sequence follows Apple’s capture model: input arrives through the input node, taps observe node output, and `AVAudioConverter` performs the format transform. citeturn0search6turn4search18turn1search10

### Tap configuration
Apple documents `installTap(onBus:bufferSize:format:block:)` as the mechanism for recording and observing node output. The tap block receives copies of the node output, which makes it a good boundary for handing audio into your own pipeline without holding the engine hostage. Keep the block short and non-blocking. The buffer size should be a tuning knob, not a correctness requirement. citeturn0search5turn4search3turn0search6

### Target format for speech
For the wire format, create an `AVAudioFormat` with `commonFormat: .pcmFormatInt16`, `channels: 1`, and the configured sample rate. Apple documents `pcmFormatInt16` as signed 16-bit native-endian integers, and `AVAudioFormat` provides the initializer used to define sample rate, channel count, and interleaving. If a consumer requires byte-exact little-endian semantics, serialize explicitly at the byte boundary rather than rely on any unstated assumptions beyond the documented format. citeturn8search4turn8search3turn8search0

```swift
let targetFormat = AVAudioFormat(
    commonFormat: .pcmFormatInt16,
    sampleRate: configuredSampleRate,
    channels: 1,
    interleaved: true
)!
```

### Downmixing and sample-rate conversion
If the hardware input is multichannel, `AVAudioConverter.downmix = true` lets the framework mix channels when remapping is necessary, and `channelMap` lets you choose exact channel routing. Use `convert(to:error:withInputFrom:)` when the sample rate changes. If the input is already at the requested sample rate and only the PCM representation changes, the simpler `convert(to:from:)` is acceptable. citeturn12search1turn12search2turn12search9turn8search8

```swift
let converter = AVAudioConverter(from: sourceFormat, to: targetFormat)!
converter.downmix = true

let outputCapacity = AVAudioFrameCount(ceil(sourceBuffer.frameLength * targetFormat.sampleRate / sourceFormat.sampleRate))
let outputBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: outputCapacity)!

var error: NSError?
let status = converter.convert(to: outputBuffer, error: &error) { _, inputStatus in
    inputStatus.pointee = .haveData
    return sourceBuffer
}
```

## Failure Modes and Diagnostics

### Permission denied or not yet determined
If permission is `denied`, exit with a clear remediation message that names System Settings and the microphone privacy pane. If it is `notDetermined`, request permission once and re-enter the capture setup only after the user responds. The code should never proceed to engine start before this branch resolves. citeturn0search12turn0search3turn2search3

### Missing `NSMicrophoneUsageDescription` or entitlement
Apple’s docs are explicit that microphone-using apps need `NSMicrophoneUsageDescription`, and the macOS entitlement is the documented capability gate for audio input under hardened runtime. If either is missing, expect either a hard failure or a denied-access state, not a recoverable runtime prompt. Diagnostics should name the missing artifact, not just report “permission failed.” citeturn0search11turn0search8turn1search7

### Hardware format or route change
Apple documents `AVAudioEngineConfigurationChangeNotification` as the notification posted when the engine’s I/O unit observes a hardware channel-count or sample-rate change. In that case the engine stops, uninitializes itself, and the app must reestablish any connections whose formats need to change. Treat this as a normal operational event, not an exceptional crash. citeturn6search1turn6search3

### No input device or invalid input format
If `inputNode` reports an unusable hardware format or the engine refuses to start, log the current authorization state, input-node format, available input devices, and the exact `AVError` / `NSError` domain and code. `AVAudioNode.inputFormat(forBus:)` and `AVCaptureDevice.devices(for: .audio)` are the first two diagnostic probes I would use in a Swift implementation. citeturn4search18turn2search8turn2search9

### Conversion issues
If `AVAudioConverter` cannot be created or returns an error, log both formats, the requested sample rate, and whether `downmix` or `channelMap` were set. Apple’s technote makes clear that sample-rate conversion must use the closure-based conversion API, so a failing `convert(to:error:withInputFrom:)` call usually points to a format mismatch, not an engine problem. citeturn1search10turn12search1turn12search2turn8search8

### Buffer bookkeeping mistakes
If the converted output is silent, truncated, or crashes, inspect `AVAudioPCMBuffer.frameLength` and `frameCapacity`. Apple explicitly says `frameLength` has no useful value on creation and must be set before use, and the length must not exceed capacity. citeturn1search5turn1search6

## Graceful Shutdown
On shutdown, stop new capture first, remove the tap, then stop or tear down the engine. Because the engine may reconfigure itself on hardware changes, shutdown should be idempotent and should tolerate a partially stopped graph. The shutdown path should also wait for any queued converter/network work to finish before the process exits so that the last transcript chunk is not lost. Apple’s docs support treating the engine as a real-time audio graph and support removing taps explicitly; manual rendering docs also show that the engine can be detached from hardware and driven by the app when that is the right mode. citeturn0search5turn6search1turn6search2turn6search4

```swift
func shutdown(engine: AVAudioEngine, inputNode: AVAudioInputNode) {
    inputNode.removeTap(onBus: 0)
    engine.stop()
}
```

## Testability

### Split the pipeline into testable seams
The most testable design is to keep the engine/tap code thin and move the following into pure Swift components:
- permission policy
- format selection
- PCM conversion
- byte serialization
- shutdown sequencing
- diagnostics mapping  
That decomposition is not an Apple requirement; it is the cleanest way to make the capture path testable without depending on a live microphone. The docs support this split because `AVAudioEngine` owns hardware access, `AVAudioConverter` owns conversion, and `AVAudioPCMBuffer` is the exchange format between them. citeturn0search6turn1search10turn1search5turn6search4

### Use manual rendering for deterministic audio tests
Apple documents manual rendering mode as a way to disconnect the engine from audio devices and let the app drive rendering. That is useful for deterministic tests of post-capture logic, buffer handling, and format conversion. For example, you can feed synthetic PCM into the conversion layer and validate the exact byte output without opening the microphone. citeturn6search2turn6search3turn6search4turn6search5

### Recommended test layers
- Unit tests: permission-state mapping, format construction, converter configuration, downmix/channel-map policy, and shutdown idempotence.
- Integration tests: engine startup with a real or virtual input device on macOS.
- Manual smoke tests: user-granted microphone prompts, denial flow, and live speech capture on target hardware.  
The separation is a recommendation derived from the Apple APIs, not a documented framework constraint. citeturn0search3turn0search12turn6search4

## Implementation Guidance
For the Swift `untype` replacement, I would implement the capture side as a small service with these boundaries:

1. `MicPermissionService`
2. `AudioEngineCaptureSource`
3. `PCMConverter`
4. `AudioByteSink`
5. `CaptureDiagnostics`

That gives the app/CLI one place to own `AVAudioEngine`, one place to own conversion policy, and a pure data path that can be unit-tested with synthetic buffers. The service should emit typed errors for permission denial, missing input, engine startup failure, converter failure, and shutdown interruption. This is the most direct mapping of Apple’s documented engine/converter model to a resilient CLI/app implementation. citeturn0search6turn1search10turn6search1turn6search4

## Assumptions & Scope

- I assumed the target Swift implementation will support current macOS releases where `AVAudioApplication` is available, with `AVCaptureDevice` kept as the compatibility fallback for older systems. Confidence: medium. If the minimum OS is lower than expected, permission handling changes. citeturn0search12turn2search3
- I assumed the project wants a single fixed wire format for speech transport: mono PCM at a configurable sample rate, serialized as 16-bit native-endian samples. Confidence: high for the PCM format, medium for the exact endianness wording because Apple documents `pcmFormatInt16` as native-endian. citeturn8search4turn8search0
- I assumed the CLI build may need the same microphone permission behavior as the eventual app bundle, even though Apple’s docs describe the permission flow in app terms. Confidence: medium-low. The forum evidence is useful but not a substitute for framework documentation. citeturn0search3turn2search1
- I excluded Soniox/ElevenLabs transport details here. This note is only about audio capture, permissioning, conversion, diagnostics, shutdown, and testability. 

## References

| # | Source | URL | Information gathered |
|---|---|---|---|
| 1 | Requesting authorization to capture and save media | https://developer.apple.com/documentation/avfoundation/requesting-authorization-to-capture-and-save-media | macOS microphone access requires `NSMicrophoneUsageDescription`; the system prompts on first capture or explicit request. |
| 2 | Requesting Authorization for Media Capture on macOS | https://developer.apple.com/documentation/bundleresources/requesting-authorization-for-media-capture-on-macos | macOS capture permissions use the same usage-description model as iOS; `authorizationStatus` / `requestAccess` are the documented capture-device flow. |
| 3 | NSMicrophoneUsageDescription | https://developer.apple.com/documentation/bundleresources/information-property-list/nsmicrophoneusagedescription | Purpose string required for microphone access. |
| 4 | Audio Input Entitlement | https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.device.audio-input | Documented entitlement for microphone / audio-input access under hardened runtime. |
| 5 | AVAudioApplication requestRecordPermission | https://developer.apple.com/documentation/avfaudio/avaudioapplication/requestrecordpermission%28completionhandler%3A%29 | Modern record-permission API; system prompts when the app has not yet been granted or denied access. |
| 6 | AVAudioEngine inputNode | https://developer.apple.com/documentation/avfaudio/avaudioengine/inputnode | Input node is the engine’s capture source; use a tap or downstream connection to receive audio. |
| 7 | AVAudioNode installTap / removeTap | https://developer.apple.com/documentation/avfaudio/avaudionode/installtap%28onbus%3Abuffersize%3Aformat%3Ablock%3A%29 | Tap mechanism for recording and observing node output. |
| 8 | AVAudioConverter | https://developer.apple.com/documentation/avfaudio/avaudioconverter | Converter supports PCM bit-depth and sample-rate conversion plus interleaving/deinterleaving. |
| 9 | TN3136: AVAudioConverter - performing sample rate conversions | https://developer.apple.com/documentation/technotes/tn3136-avaudioconverter-performing-sample-rate-conversions | Use `convert(to:error:withInputFrom:)` for sample-rate conversion. |
| 10 | AVAudioCommonFormat.pcmFormatInt16 | https://developer.apple.com/documentation/avfaudio/avaudiocommonformat/pcmformatint16 | Signed 16-bit native-endian integer PCM format. |
| 11 | AVAudioFormat init(commonFormat:sampleRate:channels:interleaved:) | https://developer.apple.com/documentation/avfaudio/avaudioformat/init%28commonformat%3Asamplerate%3Achannels%3Ainterleaved%3A%29 | Used to define the target mono/sample-rate PCM format. |
| 12 | AVAudioPCMBuffer | https://developer.apple.com/documentation/avfaudio/avaudiopcmbuffer | PCM buffer type used throughout the audio pipeline. |
| 13 | AVAudioPCMBuffer.frameLength | https://developer.apple.com/documentation/avfaudio/avaudiopcmbuffer/framelength | `frameLength` must be set before use and must not exceed capacity. |
| 14 | AVAudioConverter.downmix / channelMap | https://developer.apple.com/documentation/avfaudio/avaudioconverter/downmix | Supports mixing or remapping channels during conversion. |
| 15 | AVAudioEngineConfigurationChangeNotification | https://developer.apple.com/documentation/avfaudio/avaudioengineconfigurationchangenotification | Hardware sample-rate / channel-count changes stop and uninitialize the engine, and the app must reestablish changed connections. |
| 16 | AVAudioEngine manual rendering | https://developer.apple.com/documentation/avfaudio/avaudioengine | Manual rendering detaches the engine from devices and lets the app drive rendering. |
| 17 | Performing offline audio processing | https://developer.apple.com/documentation/avfaudio/performing-offline-audio-processing | Offline/manual rendering is appropriate for deterministic, device-free processing tests. |
| 18 | Apple Developer Forums: command line tool camera permission | https://developer.apple.com/forums/thread/111100 | Forum anecdote: command-line permission behavior can depend on packaging/launch context. |
| 19 | Apple Developer Forums: microphone permission in CI | https://developer.apple.com/forums/thread/767342 | Forum anecdote: path changes can trigger permission prompts again, suggesting stable identity matters. |

### Recommended for deep reading
- `Requesting authorization to capture and save media`: the clearest official source for the macOS permission flow.
- `AVAudioEngine inputNode` and `AVAudioNode installTap`: the core capture API surface.
- `TN3136: AVAudioConverter - performing sample rate conversions`: the clearest conversion guidance.
- `AVAudioEngineConfigurationChangeNotification`: essential for route-change handling and graceful recovery.
