import Foundation
import Testing
@testable import UntypeCore

private let selectionMarkers = MarkerConfig(
    commandPhrase: "command",
    sectionEndPhrase: "command send",
    sectionEndAliases: [],
    sectionCancelPhrase: "command cancel",
    literalNextPhrase: "literal phrase"
)

private final class SelectionMockLLM: TextRefining, @unchecked Sendable {
    private let reply: String
    private(set) var calls: [String] = []

    init(_ reply: String) {
        self.reply = reply
    }

    func refine(_ text: String) async throws -> String {
        calls.append(text)
        return reply
    }
}

private final class DeliveredTexts: @unchecked Sendable {
    private(set) var texts: [String] = []

    func append(_ text: String) {
        texts.append(text)
    }
}

private struct SelectionTemporaryDirectory {
    let url: URL

    init() {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("untype-selection-hotkey-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }
}

private func selectionController(
    operators: OperatorState,
    selectedText: String,
    primary: ProtocolLLMClients,
    alternative: ProtocolLLMClients? = nil,
    delivered: DeliveredTexts
) -> VoiceAgentProtocolController {
    VoiceAgentProtocolController(
        mode: .hybrid,
        renderer: TranscriptRenderer(output: MemoryOutput(), mode: .append, isTTY: false),
        writer: JsonlProtocolWriter(output: MemoryOutput()),
        markers: selectionMarkers,
        initialOperators: operators,
        translationPolicy: .opposite,
        refiner: primary.refiner,
        translator: primary.translator,
        compositeRefineTranslator: primary.compositeRefineTranslator,
        asker: primary.asker,
        alternativeLLM: alternative,
        askUserPromptTemplate: "Request: {text}",
        turnContext: SelectionHotkeyPlan.turnContext(selectedText: selectedText),
        askSelectionTemplate: "Selected: {selection}",
        focusedInputWriter: { text in
            delivered.append(text)
            return FocusedInputDeliveryResult.success(method: "test")
        }
    )
}

@Test func selectionHotkeyNeedsRefineTranslateOrAsk() throws {
    #expect(SelectionHotkeyPlan.operators(for: .default) == nil)
    let clipboardOnly = try UntypeUISettings.default.merged(UntypeUISettingsPatch(clipboard: true, selection: true))
    #expect(SelectionHotkeyPlan.operators(for: clipboardOnly) == nil)
}

@Test func selectionHotkeyOperatorsKeepTheActiveOnesAndReplaceTheSelection() throws {
    let settings = try UntypeUISettings.default.merged(UntypeUISettingsPatch(
        refine: true,
        translate: true,
        focusedInput: false,
        alternative: true,
        selectionRole: SelectionRole.context.rawValue
    ))
    let operators = try #require(SelectionHotkeyPlan.operators(for: settings))

    #expect(operators.refine)
    #expect(operators.translate)
    #expect(operators.alternative)
    #expect(!operators.ask)
    #expect(operators.selection)
    #expect(operators.input)
    #expect(SelectionHotkeyPlan.turnContext(selectedText: "x").selectionRole == .material)
}

@Test func selectionHotkeyRefinesTheSelectionAndDeliversTheResult() async throws {
    let settings = try UntypeUISettings.default.merged(UntypeUISettingsPatch(refine: true))
    let refiner = SelectionMockLLM("Polished text.")
    let delivered = DeliveredTexts()
    let controller = selectionController(
        operators: try #require(SelectionHotkeyPlan.operators(for: settings)),
        selectedText: "ehm the the polished text",
        primary: ProtocolLLMClients(refiner: refiner, translator: nil, compositeRefineTranslator: nil, asker: nil),
        delivered: delivered
    )

    try controller.startSession()
    let summary = try #require(try await controller.submitWithoutDictation())

    #expect(refiner.calls == ["ehm the the polished text"])
    #expect(delivered.texts == ["Polished text."])
    #expect(summary.focusedInput?.ok == true)
}

@Test func selectionHotkeyAsksAboutTheSelectionWithTheAlternativeLLM() async throws {
    let settings = try UntypeUISettings.default.merged(UntypeUISettingsPatch(ask: true, alternative: true))
    let primary = SelectionMockLLM("primary")
    let alternative = SelectionMockLLM("alternative answer")
    let delivered = DeliveredTexts()
    let controller = selectionController(
        operators: try #require(SelectionHotkeyPlan.operators(for: settings)),
        selectedText: "summarise me",
        primary: ProtocolLLMClients(refiner: nil, translator: nil, compositeRefineTranslator: nil, asker: primary),
        alternative: ProtocolLLMClients(refiner: nil, translator: nil, compositeRefineTranslator: nil, asker: alternative),
        delivered: delivered
    )

    try controller.startSession()
    _ = try await controller.submitWithoutDictation()

    #expect(primary.calls.isEmpty)
    #expect(alternative.calls.count == 1)
    #expect(alternative.calls.first?.contains("Selected: summarise me") == true)
    #expect(delivered.texts == ["alternative answer"])
}

@Test func selectionHotkeySettingsDefaultOnAndRoundTrip() throws {
    #expect(UntypeUISettings.default.selectionHotkeyEnabled)
    #expect(UntypeUISettings.default.selectionHotkey == "Control+Option+`")

    let temp = SelectionTemporaryDirectory()
    let changed = try UntypeUISettings.default.merged(UntypeUISettingsPatch(
        selectionHotkeyEnabled: false,
        selectionHotkey: "ctrl+shift+space"
    ))
    #expect(changed.selectionHotkey == "Control+Shift+Space")
    try UntypeUISettingsStore.save(changed, home: temp.url)
    let loaded = try UntypeUISettingsStore.load(home: temp.url)
    #expect(loaded.selectionHotkeyEnabled == false)
    #expect(loaded.selectionHotkey == "Control+Shift+Space")

    let path = UntypeUISettingsStore.path(home: temp.url)
    var root = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: path)) as? [String: Any])
    var settings = try #require(root["settings"] as? [String: Any])
    settings.removeValue(forKey: "selectionHotkeyEnabled")
    settings.removeValue(forKey: "selectionHotkey")
    root["settings"] = settings
    try JSONSerialization.data(withJSONObject: root).write(to: path)
    let older = try UntypeUISettingsStore.load(home: temp.url)
    #expect(older.selectionHotkeyEnabled)
    #expect(older.selectionHotkey == UntypeUISettings.defaultSelectionHotkey)
}

@Test func selectionHotkeyMustDifferFromThePushToTalkHotkey() throws {
    #expect(throws: UntypeError.self) {
        _ = try UntypeUISettings.default.merged(UntypeUISettingsPatch(selectionHotkey: "Control+`"))
    }
    #expect(throws: UntypeError.self) {
        _ = try UntypeUISettings.default.merged(UntypeUISettingsPatch(hotkey: "Option+Control+`"))
    }
    #expect(throws: UntypeError.self) {
        _ = try UntypeUISettings.default.merged(UntypeUISettingsPatch(selectionHotkey: "Control+Option"))
    }
    let disabled = try UntypeUISettings.default.merged(UntypeUISettingsPatch(
        selectionHotkeyEnabled: false,
        selectionHotkey: "Control+`"
    ))
    #expect(disabled.selectionHotkeyEnabled == false)
}

@Test func selectionHotkeyChangesReconfigureTheHotkeyMonitor() throws {
    let base = UntypeUISettings.default
    let toggled = try base.merged(UntypeUISettingsPatch(selectionHotkeyEnabled: false))
    let rebound = try base.merged(UntypeUISettingsPatch(selectionHotkey: "Control+Shift+`"))
    #expect(UntypeUISettings.hotkeyMonitorConfigurationChanged(previous: base, next: toggled))
    #expect(UntypeUISettings.hotkeyMonitorConfigurationChanged(previous: base, next: rebound))
}

@Test func pushToActChoiceStartsFromTheSettingsAndChangesOnlyTheRun() throws {
    let settings = try UntypeUISettings.default.merged(UntypeUISettingsPatch(
        refine: true,
        alternative: true,
        translationPolicy: TranslationPolicy.toEnglish.rawValue
    ))
    var choice = PushToActChoice(settings: settings, alternativeAvailable: true)
    #expect(choice.refine && !choice.translate && !choice.ask)
    #expect(choice.alternative)
    #expect(choice.translationPolicy == TranslationPolicy.toEnglish)

    let toggled = [choice.toggle(key: "T"), choice.toggle(key: "l"), choice.toggle(key: "r"), choice.toggle(key: "x")]
    #expect(toggled == [true, true, true, false])
    choice.cycleTranslationPolicy()
    let operators = try #require(choice.operators)
    #expect(!operators.refine && operators.translate && !operators.alternative)
    #expect(operators.selection && operators.input)
    #expect(choice.translationPolicy == TranslationPolicy.toGreek)
    // The saved settings are untouched.
    #expect(settings.refine && !settings.translate && settings.alternative)

    let translateOff = choice.toggle(key: "t")
    #expect(translateOff)
    #expect(!choice.canRun)
    #expect(choice.operators == nil)

    // Picking a language turns Translate on.
    choice.selectTranslation(.toGreek)
    #expect(choice.translate && choice.canRun)
    #expect(choice.operators?.translate == true)
}

@Test func pushToActChoiceKeepsTheAlternativeOffWhenNoneIsConfigured() throws {
    let settings = try UntypeUISettings.default.merged(UntypeUISettingsPatch(refine: true, alternative: true))
    var choice = PushToActChoice(settings: settings, alternativeAvailable: false)
    #expect(!choice.alternative)
    let alternativeToggled = choice.toggle(key: "l")
    #expect(!alternativeToggled)
    #expect(choice.operators?.alternative == false)
}

@Test func pushToActChoicePicksAmongTheConfiguredModels() throws {
    let settings = try UntypeUISettings.default.merged(UntypeUISettingsPatch(refine: true))
    var choice = PushToActChoice(settings: settings, alternativeAvailable: true, alternative2Available: true)
    #expect(choice.model == .primary)
    #expect(choice.availableModels == [.primary, .alternative, .alternative2])

    // L cycles primary → alternative → alternative 2 → primary.
    var seen: [PushToActModel] = []
    for _ in 0..<3 {
        choice.toggle(key: "l")
        seen.append(choice.model)
    }
    #expect(seen == [.alternative, .alternative2, .primary])

    let pickedSecond = choice.select(.alternative2)
    #expect(pickedSecond)
    #expect(choice.operators?.alternative == true)

    // Only the second alternative configured: L goes straight to it.
    var onlySecond = PushToActChoice(settings: settings, alternativeAvailable: false, alternative2Available: true)
    let cycled = onlySecond.toggle(key: "l")
    #expect(cycled)
    #expect(onlySecond.model == .alternative2)
    let pickedMissing = onlySecond.select(.alternative)
    #expect(!pickedMissing)
}

@Test func pushToActRemembersItsOwnChoicesSeparatelyFromPushToTalk() throws {
    let temp = SelectionTemporaryDirectory()
    // Push-to-talk: refine on, opposite translation.
    let settings = try UntypeUISettings.default.merged(UntypeUISettingsPatch(refine: true))
    var choice = PushToActChoice(settings: settings, alternativeAvailable: true, alternative2Available: true)
    #expect(choice.refine && !choice.translate)

    // The user picks translate → Greek with the second alternative.
    choice.toggle(key: "r")
    choice.selectTranslation(.toGreek)
    choice.select(.alternative2)
    let remembered = try settings.merged(UntypeUISettingsPatch(pushToAct: choice.preferences))
    try UntypeUISettingsStore.save(remembered, home: temp.url)
    let loaded = try UntypeUISettingsStore.load(home: temp.url)

    // Next time the pop-up opens with those choices…
    let next = PushToActChoice(settings: loaded, alternativeAvailable: true, alternative2Available: true)
    #expect(!next.refine && next.translate)
    #expect(next.translationPolicy == .toGreek)
    #expect(next.model == .alternative2)
    // …while the push-to-talk operators are untouched.
    #expect(loaded.refine && !loaded.translate)
    #expect(loaded.translationPolicy == TranslationPolicy.opposite.rawValue)

    // A remembered model that is no longer configured opens as the primary.
    let withoutSecond = PushToActChoice(settings: loaded, alternativeAvailable: true, alternative2Available: false)
    #expect(withoutSecond.model == .primary)
    #expect(withoutSecond.translate && withoutSecond.translationPolicy == .toGreek)
}
