---
status: completed
mode: write-and-run
scope_slug: llm-streaming-toggle-controller-cd
language: Swift
framework: Swift Testing (import Testing, @Test, #expect)
test_command_full: swift test
test_command_scope: swift test --filter ProtocolCoreTests && swift test --filter ProtocolControllerTests
test_dir: Tests/UntypeCoreTests
target_path: ~/aiwork/coding-platform/untype-s
test_files_owned:
  - Tests/UntypeCoreTests/ProtocolCoreTests.swift
  - Tests/UntypeCoreTests/ProtocolControllerTests.swift
tests_added: 13
tests_updated: 0
tests_run: 33
tests_passed: 33
tests_failed: 0
implementation_gaps: 0
built_at: 2026-06-20T10:43:00Z
last_built_commit: e70d4fb37cd9222b8bb1db2f6680d66e4e4c4320
---

# Test Build — Phase-6 Unit C and Unit D Deferred Streaming Tests

## 1. Summary

Status: **completed**. Swift Testing framework confirmed from all existing test files (`import Testing`, `@Test`, `#expect`). 13 new tests were added across two owned files — 3 serialization tests in `ProtocolCoreTests.swift` and 10 controller-wiring tests in `ProtocolControllerTests.swift`. All 33 tests in scope pass (20 in ProtocolControllerTests, 13 in ProtocolCoreTests), including all pre-existing tests that were left untouched. Unit D (`UntypeRuntimeFactory.makeForUI` streaming forwarding) was assessed and skipped — see "Manual Review Needed" section. Zero implementation gaps.

## 2. Scope Resolved

**Source files tested:**
- `Sources/UntypeCore/ProtocolJsonlWriter.swift`
  - `ProtocolEvent.streamingProgress(sectionId:accumulatedText:)` — new enum case with `jsonObject` arm
- `Sources/UntypeCore/VoiceAgentProtocolController.swift`
  - `VoiceAgentProtocolController.init(... streamingProgress:)` — new last parameter (default nil)
  - `makeStreamingProgressHandler(sectionId:)` — private closure factory
  - `refine(_:using:onProgress:)` — private helper dispatching `StreamingTextRefining` vs one-shot
  - `processSection(sectionId:rawText:operators:)` — threading `onProgress` into composite/refine/translate paths
- `Sources/UntypeCore/LLMRefiners.swift` (read-only; consumed via protocol)
  - `StreamingTextRefining` protocol
  - `CompositeRefineTranslating.refineAndTranslate(_:onProgress:)` overload

## 3. Existing Coverage

Before this build:

| Symbol | Existing test files |
|---|---|
| `ProtocolEvent.sectionProcessed` (jsonObject) | `Tests/UntypeCoreTests/ProtocolCoreTests.swift` (via `jsonlProtocolWriterEmitsMonotonicSeqValues`) |
| `ProtocolEvent.streamingProgress` (jsonObject) | None |
| `VoiceAgentProtocolController.init(streamingProgress:)` | None |
| `makeStreamingProgressHandler` | None |
| `refine(_:using:onProgress:)` | None |
| `processSection` composite/refine/translate streaming path | None |

## 4. Plan

| target_symbol | category | test_file | test_name | intent |
|---|---|---|---|---|
| `ProtocolEvent.streamingProgress.jsonObject` | unit | ProtocolCoreTests.swift | `streamingProgressEventSerializesToExpectedJsonlShape` | Asserts the event serializes to `{"type":"streaming.progress","section_id":…,"accumulated_text":…,"seq":…}` with exactly the right keys and values |
| `ProtocolEvent.streamingProgress.jsonObject` | unit | ProtocolCoreTests.swift | `streamingProgressEventSerializesEmptyAccumulatedText` | Asserts `accumulated_text` can be an empty string without error |
| `ProtocolEvent.streamingProgress.jsonObject` | regression | ProtocolCoreTests.swift | `streamingProgressEventDoesNotAffectSectionProcessedShape` | Verifies that emitting a `streamingProgress` event before a `sectionProcessed` event leaves the latter's shape unchanged and seq numbers are monotonically increasing |
| `processSection` / `refine(_:using:onProgress:)` | unit | ProtocolControllerTests.swift | `streamingProgressSinkReceivesAccumulatedChunksOnRefineOnlyPath` | Sink receives each accumulated chunk; streaming overload (not one-shot) is dispatched |
| `processSection` | unit | ProtocolControllerTests.swift | `sectionProcessedContainsFinalResultNotPartialTextOnRefineOnlyPath` | `output_text` in `sectionProcessed` is the strict final result, not any partial progress string |
| `makeStreamingProgressHandler` | unit | ProtocolControllerTests.swift | `streamingProgressEventsAreEmittedToProtocolWriterOnRefineOnlyPath` | One `streaming.progress` protocol event is emitted per progress callback; all carry the correct `section_id`; `sectionProcessed` fires once after |
| `processSection` / `refine(_:using:onProgress:)` | unit | ProtocolControllerTests.swift | `streamingProgressSinkReceivesAccumulatedChunksOnTranslateOnlyPath` | Same as refine-only path but for translate-only operator |
| `processSection` | unit | ProtocolControllerTests.swift | `sectionProcessedContainsFinalTranslatedTextNotPartialOnTranslateOnlyPath` | `output_text` is the strict final translation |
| `processSection` (composite) | unit | ProtocolControllerTests.swift | `streamingProgressSinkReceivesPartialDisplayTextOnCompositePath` | Sink receives partial display-only text from composite's `onProgress` overload |
| `processSection` (composite) | regression | ProtocolControllerTests.swift | `compositePathNeverCommitsPartialTextAsOutputText` | Risk #1 guard — partial/incomplete JSON fragments from `onProgress` never appear as `output_text` in `sectionProcessed`; only the strict final `CompositeRefineTranslateResult` is committed |
| `refine(_:using:onProgress:)` | unit | ProtocolControllerTests.swift | `streamingProgressSinkIsNeverInvokedWhenRefinerDoesNotConformToStreamingTextRefining` | Silently-inert path: plain `MockRefiner` (TextRefining only) → sink is never called, no `streaming.progress` events emitted, normal `sectionProcessed` still fires |
| `VoiceAgentProtocolController.init(streamingProgress:)` | regression | ProtocolControllerTests.swift | `constructingControllerWithNilStreamingProgressLeavesExistingBehaviorUnchanged` | Default `nil` parameter — protocol events and committed output unchanged; streaming protocol events still emitted when a streaming refiner is used, nil sink simply not called |
| `processSection` (composite, default extension) | unit | ProtocolControllerTests.swift | `streamingProgressSinkIsNeverInvokedWhenNoStreamingProgressParamAndCompositeIsPlain` | `MockCompositeRefineTranslator` (implements only base method, not streaming overload) → default extension routes to base → no `onProgress` called → sink empty, no `streaming.progress` events |

## 5. Files Owned

| File | Reason |
|---|---|
| `Tests/UntypeCoreTests/ProtocolCoreTests.swift` | Updated — 3 new tests added for `ProtocolEvent.streamingProgress` serialization |
| `Tests/UntypeCoreTests/ProtocolControllerTests.swift` | Updated — 10 new tests added plus `SinkAccumulator<T>` and `MockStreamingRefiner` / `MockStreamingComposite` helper classes |

**Not created:** `Tests/UntypeCoreTests/UntypeRuntimeFactoryTests.swift` — see "Manual Review Needed".

## 6. Test Run Results

### ProtocolCoreTests (13 tests, all pass)

| Test | Result |
|---|---|
| `markerMatcherNormalizesCaseAccentsAndPunctuation` (pre-existing) | PASS |
| `markerMatcherPrefersLongerMarkerAtSameStart` (pre-existing) | PASS |
| `markerMatcherStripsMarkersAndStateCommandArgumentsForDisplay` (pre-existing) | PASS |
| `stateMachineUpdatesOperatorsAndReportsStatus` (pre-existing) | PASS |
| `stateMachineSubmitsSectionsAndKeepsSectionIdsStableAcrossSegments` (pre-existing) | PASS |
| `stateMachineMatchesGreekSectionEndAcrossFinalSegments` (pre-existing) | PASS |
| `stateMachineCancelsOrSubmitsPendingSectionOnShutdown` (pre-existing) | PASS |
| `jsonlProtocolWriterEmitsMonotonicSeqValues` (pre-existing) | PASS |
| `protocolSettingsStoreSavesLoadsAndAppliesNonSecretState` (pre-existing) | PASS |
| `protocolSettingsStoreLoadsOldStateWithoutInputAsOff` (pre-existing) | PASS |
| `streamingProgressEventSerializesToExpectedJsonlShape` **NEW** | PASS |
| `streamingProgressEventSerializesEmptyAccumulatedText` **NEW** | PASS |
| `streamingProgressEventDoesNotAffectSectionProcessedShape` **NEW** | PASS |

### ProtocolControllerTests (20 tests, all pass)

| Test | Result |
|---|---|
| `protocolControllerAgentModeEmitsJsonlWithoutRenderingTranscript` (pre-existing) | PASS |
| `protocolControllerVisibleModeRendersStatusReport` (pre-existing) | PASS |
| `protocolControllerProcessesSectionBeforeClipboardAndInputDelivery` (pre-existing) | PASS |
| `protocolControllerUsesCompositeRefineTranslateWhenBothOperatorsAreEnabled` (pre-existing) | PASS |
| `protocolControllerCompositeFailureIsFailOpenWithoutSequentialFallback` (pre-existing) | PASS |
| `protocolControllerUsesConfiguredTranslationUserPromptTemplate` (pre-existing) | PASS |
| `protocolControllerWarningsAreFailOpenWhenRefinerIsMissing` (pre-existing) | PASS |
| `protocolControllerVisibleOperatorDiagnosticsReportClipboardFailureWithoutVerbose` (pre-existing) | PASS |
| `protocolControllerTreatsFocusedInputOkFalseAsFailure` (pre-existing) | PASS |
| `protocolControllerPersistsLatestOperatorSettingsSnapshot` (pre-existing) | PASS |
| `streamingProgressSinkReceivesAccumulatedChunksOnRefineOnlyPath` **NEW** | PASS |
| `sectionProcessedContainsFinalResultNotPartialTextOnRefineOnlyPath` **NEW** | PASS |
| `streamingProgressEventsAreEmittedToProtocolWriterOnRefineOnlyPath` **NEW** | PASS |
| `streamingProgressSinkReceivesAccumulatedChunksOnTranslateOnlyPath` **NEW** | PASS |
| `sectionProcessedContainsFinalTranslatedTextNotPartialOnTranslateOnlyPath` **NEW** | PASS |
| `streamingProgressSinkReceivesPartialDisplayTextOnCompositePath` **NEW** | PASS |
| `compositePathNeverCommitsPartialTextAsOutputText` **NEW** | PASS |
| `streamingProgressSinkIsNeverInvokedWhenRefinerDoesNotConformToStreamingTextRefining` **NEW** | PASS |
| `constructingControllerWithNilStreamingProgressLeavesExistingBehaviorUnchanged` **NEW** | PASS |
| `streamingProgressSinkIsNeverInvokedWhenNoStreamingProgressParamAndCompositeIsPlain` **NEW** | PASS |

## 7. Implementation Gaps

None. All 33 tests pass. No production behavior diverges from design contracts C4 and C5.

## 8. Manual Review Needed

### Unit D — `UntypeRuntimeFactory.makeForUI` streaming forwarding (skipped, not unit-testable)

**What was needed:** A test asserting that `makeForUI(... streamingProgress: sink)` passes `streamingProgress` straight through to `VoiceAgentProtocolController.init(... streamingProgress:)`.

**Why it was skipped:** `makeForUI` internally constructs `AVFoundationAudioSource`, `SonioxTranscriber` / `ElevenLabsTranscriber`, `FocusedInputDelivery`, and `MacOSClipboardWriter`. All of these require hardware (audio device), real macOS entitlements (Accessibility, Microphone), or live network credentials. There is no injectable seam in `makeForUI` that allows substituting these collaborators without modifying the production source — which is out of this agent's ownership. The passing of `streamingProgress` into the controller is a two-line mechanical wiring (line 158 of `UntypeRuntimeFactory.swift`): `streamingProgress: streamingProgress` is passed verbatim from the factory parameter into the controller's `init`. The design (C6) and the implementation both clearly show this wiring. The contract is fully covered at the controller level by the new `ProtocolControllerTests.swift` tests.

**What the human should do:** The Unit D coder's own step-15 smoke-check (perform a push-to-talk release into a focused field and confirm `focused_input.ok=true` in `~/.tool-agents/untype/release-latency.jsonl`) is the appropriate integration verification. No separate unit test is needed and none can be safely written without either modifying production source or introducing a factory-level DI seam — both out of scope for this agent.

**Note on `MockCompositeRefineTranslator` compatibility:** The existing `MockCompositeRefineTranslator` in `ProtocolControllerTests.swift` implements only the base `refineAndTranslate(_:)` method. The `CompositeRefineTranslating` default extension routes the streaming overload back to the base method (by design per C3). This means existing tests using `MockCompositeRefineTranslator` continue to pass unchanged — verified in test run above.

## 9. Commands Run

```
swift test --filter ProtocolCoreTests
# exit 0 — 13 tests passed (3 new, 10 pre-existing)

swift test --filter ProtocolControllerTests
# exit 0 — 20 tests passed (10 new, 10 pre-existing)
```

Total tests in scope run: 33. Passed: 33. Failed: 0.
