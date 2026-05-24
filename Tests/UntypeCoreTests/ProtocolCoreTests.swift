import Foundation
import Testing
@testable import UntypeCore

private let markers = MarkerConfig(
    commandPhrase: "command",
    sectionEndPhrase: "command send",
    sectionEndAliases: ["τέλος εντολής"],
    sectionCancelPhrase: "command cancel",
    literalNextPhrase: "literal phrase"
)

private let operatorsOff = OperatorState(
    refine: false,
    translate: false,
    clipboard: false,
    input: false
)

@Test func markerMatcherNormalizesCaseAccentsAndPunctuation() {
    let definitions = markerDefinitions(for: markers)

    #expect(normalizeOrdinaryMarker("Τέλος,   Εντολής!") == "τελοσ εντολησ")
    #expect(findFirstMarker(in: "κείμενο ΤΕΛΟΣ ΕΝΤΟΛΗΣ.", definitions: definitions)?.kind == .sectionEnd)
}

@Test func markerMatcherPrefersLongerMarkerAtSameStart() {
    let definitions = markerDefinitions(for: markers)

    #expect(findFirstMarker(in: "command refine", definitions: definitions)?.kind == .stateCommand)
    #expect(findFirstMarker(in: "this commandment is text", definitions: definitions) == nil)
    #expect(findFirstMarker(in: "please command send", definitions: definitions)?.kind == .sectionEnd)
}

@Test func markerMatcherStripsMarkersAndStateCommandArgumentsForDisplay() {
    let definitions = markerDefinitions(for: markers)

    let visible = stripMarkersForDisplay(
        "hello command refine world command send",
        definitions: definitions
    )

    #expect(visible == "hello world")
}

@Test func stateMachineUpdatesOperatorsAndReportsStatus() {
    let stateMachine = VoiceCommandStateMachine(
        markers: markers,
        initialOperators: operatorsOff,
        translationPolicy: .toEnglish
    )

    let refine = stateMachine.processFinal("command refine")
    _ = stateMachine.processFinal("command translate")
    _ = stateMachine.processFinal("command clipboard")
    _ = stateMachine.processFinal("command input")
    let status = stateMachine.processFinal("command status")

    #expect(refine.actions.contains(.stateChanged(key: .refine, value: true, targetPolicy: nil)))
    #expect(stateMachine.state == OperatorState(refine: true, translate: true, clipboard: true, input: true))
    #expect(status.actions.contains(.statusReported(ProtocolStatusReport(
        operators: OperatorState(refine: true, translate: true, clipboard: true, input: true),
        translationPolicy: .toEnglish,
        pendingSection: false
    ))))
}

@Test func stateMachineSubmitsSectionsAndKeepsSectionIdsStableAcrossSegments() {
    let stateMachine = VoiceCommandStateMachine(
        markers: markers,
        initialOperators: OperatorState(refine: true, translate: false, clipboard: false, input: false),
        translationPolicy: .opposite
    )

    #expect(stateMachine.processFinal("Open the").actions.isEmpty)
    let result = stateMachine.processFinal("design docs. command send")

    #expect(result.actions.contains(.sectionSubmitted(
        sectionId: "sec_000001",
        rawText: "Open the design docs.",
        operators: [.refine]
    )))
}

@Test func stateMachineMatchesGreekSectionEndAcrossFinalSegments() {
    let stateMachine = VoiceCommandStateMachine(
        markers: markers,
        initialOperators: operatorsOff,
        translationPolicy: .opposite
    )

    #expect(stateMachine.processFinal("γράψε αυτό τέλος").actions.isEmpty)
    let result = stateMachine.processFinal("εντολής")

    #expect(result.actions.contains(.sectionSubmitted(
        sectionId: "sec_000001",
        rawText: "γράψε αυτό",
        operators: []
    )))
}

@Test func stateMachineCancelsOrSubmitsPendingSectionOnShutdown() {
    let cancelMachine = VoiceCommandStateMachine(
        markers: markers,
        initialOperators: operatorsOff,
        translationPolicy: .opposite
    )
    _ = cancelMachine.processFinal("unsubmitted text")

    let submitMachine = VoiceCommandStateMachine(
        markers: markers,
        initialOperators: OperatorState(refine: true, translate: false, clipboard: false, input: false),
        translationPolicy: .opposite
    )
    _ = submitMachine.processFinal("hotkey dictated text")

    #expect(cancelMachine.drainForShutdown() == [
        .sectionCancelled(sectionId: "sec_000001", reason: .shutdown)
    ])
    #expect(submitMachine.drainForShutdown(options: DrainForShutdownOptions(submitPending: true)) == [
        .sectionSubmitted(sectionId: "sec_000001", rawText: "hotkey dictated text", operators: [.refine])
    ])
}

@Test func jsonlProtocolWriterEmitsMonotonicSeqValues() throws {
    let output = MemoryOutput()
    let writer = JsonlProtocolWriter(output: output)

    try writer.write(.sessionStarted)
    try writer.write(.stateChanged(key: .clipboard, value: true, targetPolicy: nil))
    try writer.write(.sessionEnded(reason: "test"))

    let lines = output.text.split(separator: "\n").map(String.init)
    let events = try lines.map(jsonObject)

    #expect(events.count == 3)
    #expect(events[0]["type"] as? String == "session.started")
    #expect(events[0]["seq"] as? Int == 1)
    #expect(events[1]["type"] as? String == "state.changed")
    #expect(events[1]["key"] as? String == "clipboard")
    #expect(events[1]["value"] as? Bool == true)
    #expect(events[1]["seq"] as? Int == 2)
    #expect(events[2]["type"] as? String == "session.ended")
    #expect(events[2]["seq"] as? Int == 3)
}

@Test func protocolSettingsStoreSavesLoadsAndAppliesNonSecretState() throws {
    let temp = TemporaryDirectory()
    let options = ProtocolSettingsStoreOptions(toolName: "untype", home: temp.url)
    let snapshot = ProtocolSettingsSnapshot(
        operators: OperatorState(refine: true, translate: false, clipboard: true, input: true),
        translationPolicy: .toEnglish
    )

    try savePersistedProtocolSettings(snapshot, options: options)

    let path = protocolSettingsPath(options: options)
    let raw = try String(contentsOf: path, encoding: .utf8)
    #expect(raw.contains(#""version" : 1"#))
    #expect(raw.contains(#""translation_policy" : "to-en""#))
    #expect(!raw.contains("API_KEY"))
    #expect(try loadPersistedProtocolSettings(options: options) == snapshot)

    let config = ProtocolRuntimeConfig(
        interactionMode: .dictation,
        markers: markers,
        initialOperators: operatorsOff,
        translationPolicy: .opposite,
        protocolOutput: nil,
        settingSources: ProtocolSettingSources(
            refine: .default,
            translate: .configured,
            clipboard: .default,
            input: .default,
            translationPolicy: .configured
        )
    )
    let applied = applyPersistedProtocolSettings(config, persisted: snapshot)

    #expect(applied.initialOperators == OperatorState(
        refine: true,
        translate: false,
        clipboard: true,
        input: true
    ))
    #expect(applied.translationPolicy == .opposite)
}

@Test func protocolSettingsStoreLoadsOldStateWithoutInputAsOff() throws {
    let temp = TemporaryDirectory()
    let options = ProtocolSettingsStoreOptions(toolName: "untype", home: temp.url)
    let path = protocolSettingsPath(options: options)
    try FileManager.default.createDirectory(
        at: path.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    try """
    {
      "version": 1,
      "saved_at": "2026-05-16T00:00:00.000Z",
      "protocol": {
        "operators": {
          "refine": true,
          "translate": false,
          "clipboard": true
        },
        "translation_policy": "opposite"
      }
    }
    """.write(to: path, atomically: true, encoding: .utf8)

    #expect(try loadPersistedProtocolSettings(options: options) == ProtocolSettingsSnapshot(
        operators: OperatorState(refine: true, translate: false, clipboard: true, input: false),
        translationPolicy: .opposite
    ))
}

private func jsonObject(_ line: String) throws -> [String: Any] {
    let data = Data(line.utf8)
    let object = try JSONSerialization.jsonObject(with: data)
    return object as? [String: Any] ?? [:]
}

private final class TemporaryDirectory {
    let url: URL

    init() {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("untype-s-protocol-tests")
            .appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }
}
