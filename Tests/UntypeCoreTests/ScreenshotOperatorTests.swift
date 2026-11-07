import Foundation
import Testing
@testable import UntypeCore

private let markers = MarkerConfig(
    commandPhrase: "command",
    sectionEndPhrase: "command send",
    sectionEndAliases: [],
    sectionCancelPhrase: "command cancel",
    literalNextPhrase: "literal phrase"
)

private let shot = WindowScreenshot(
    image: LLMImageAttachment(data: Data([1, 2, 3]), mediaType: "image/png", pixelWidth: 3, pixelHeight: 1),
    appName: "Mail"
)

/// Records each call and the image sent with it.
private final class ImageRecordingRefiner: TextRefining, ImageInputRefining, @unchecked Sendable {
    private(set) var calls: [(text: String, image: LLMImageAttachment?)] = []

    func refine(_ text: String) async throws -> String {
        calls.append((text, nil))
        return "out: \(text)"
    }

    func refine(_ text: String, image: LLMImageAttachment, onProgress: ((String) -> Void)?) async throws -> String {
        calls.append((text, image))
        return "out: \(text)"
    }
}

private func controller(
    operators: OperatorState,
    output: MemoryOutput,
    refiner: TextRefining? = nil,
    asker: TextRefining? = nil,
    turnContext: UntypeTurnContext
) -> VoiceAgentProtocolController {
    VoiceAgentProtocolController(
        mode: .hybrid,
        renderer: TranscriptRenderer(output: MemoryOutput(), mode: .append, isTTY: false),
        writer: JsonlProtocolWriter(output: output),
        markers: markers,
        initialOperators: operators,
        translationPolicy: .toEnglish,
        refiner: refiner,
        asker: asker,
        askUserPromptTemplate: "Request: {text}",
        turnContext: turnContext,
        screenshotContextTemplate: "SHOT[{app}]",
        askScreenshotTemplate: "ASKSHOT[{app}]"
    )
}

private func warnings(_ output: MemoryOutput) throws -> [String] {
    try output.text.split(separator: "\n").compactMap {
        let event = try JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any]
        return event?["type"] as? String == "protocol.warning" ? event?["message"] as? String : nil
    }
}

@Test func screenshotGoesWithRefineAndThePromptSaysSo() async throws {
    let refiner = ImageRecordingRefiner()
    let sut = controller(
        operators: OperatorState(refine: true, translate: false, clipboard: false, input: false, screenshot: true),
        output: MemoryOutput(), refiner: refiner,
        turnContext: UntypeTurnContext(screenshot: shot)
    )
    try sut.startSession()
    try await sut.final("reply to this command send")
    #expect(refiner.calls.count == 1)
    #expect(refiner.calls.first?.text == "reply to this\n\nSHOT[Mail]")
    #expect(refiner.calls.first?.image == shot.image)
}

@Test func askWithTheScreenshotNamesTheAppBeforeTheRequest() async throws {
    let asker = ImageRecordingRefiner()
    let sut = controller(
        operators: OperatorState(refine: false, translate: false, clipboard: false, input: false, ask: true, screenshot: true),
        output: MemoryOutput(), asker: asker,
        turnContext: UntypeTurnContext(screenshot: shot)
    )
    try sut.startSession()
    try await sut.final("what does this error mean command send")
    #expect(asker.calls.first?.text == "ASKSHOT[Mail]\n\nRequest: what does this error mean")
    #expect(asker.calls.first?.image == shot.image)
}

@Test func askAboutTheScreenshotWorksWithoutDictation() async throws {
    let asker = ImageRecordingRefiner()
    let sut = controller(
        operators: OperatorState(refine: false, translate: false, clipboard: false, input: false, ask: true, screenshot: true),
        output: MemoryOutput(), asker: asker,
        turnContext: UntypeTurnContext(screenshot: shot)
    )
    try sut.startSession()
    #expect(try await sut.submitWithoutDictation() != nil)
    #expect(asker.calls.first?.text.contains("respond to what the screenshot shows") == true)
}

@Test func screenshotOperatorWithoutACaptureSkipsTheLLM() async throws {
    let refiner = ImageRecordingRefiner()
    let output = MemoryOutput()
    let sut = controller(
        operators: OperatorState(refine: true, translate: false, clipboard: false, input: false, screenshot: true),
        output: output, refiner: refiner,
        turnContext: UntypeTurnContext()
    )
    try sut.startSession()
    try await sut.final("hello command send")
    #expect(refiner.calls.isEmpty)
    #expect(try warnings(output).contains { $0.contains("no screenshot") })
}

@Test func pendingCaptureIsAwaitedBeforeTheLLMCall() async throws {
    let refiner = ImageRecordingRefiner()
    let context = UntypeTurnContext()
    context.setScreenshotCapture(Task {
        try? await Task.sleep(for: .milliseconds(30))
        return shot
    })
    #expect(context.hasScreenshot)
    let sut = controller(
        operators: OperatorState(refine: true, translate: false, clipboard: false, input: false, screenshot: true),
        output: MemoryOutput(), refiner: refiner, turnContext: context
    )
    try sut.startSession()
    try await sut.final("hello command send")
    #expect(refiner.calls.first?.image == shot.image)
}

@Test func screenshotOperatorSettingsRoundTrip() throws {
    let state = OperatorState(refine: false, translate: false, clipboard: false, input: false, screenshot: true)
    let decoded = try JSONDecoder().decode(OperatorState.self, from: JSONEncoder().encode(state))
    #expect(decoded.screenshot)
    let legacy = try JSONDecoder().decode(
        OperatorState.self,
        from: Data(#"{"refine":true,"translate":false,"clipboard":false}"#.utf8)
    )
    #expect(!legacy.screenshot)

    let settings = try UntypeUISettings.default.merged(UntypeUISettings.operatorPatch(.screenshot, true))
    #expect(settings.screenshot)
    #expect(try settings.sessionArguments().contains("--screenshot-default"))
}

@Test func pushToActRemembersTheScreenshotChoice() throws {
    var choice = PushToActChoice(settings: UntypeUISettings.default, alternativeAvailable: false)
    choice.refine = true
    #expect(!choice.screenshot)
    let toggled = choice.toggle(key: "w")
    #expect(toggled)
    #expect(choice.operators?.screenshot == true)
    #expect(choice.preferences.screenshot)

    // Choices saved before the Screenshot option open with it off.
    let saved = #"{"refine":true,"translate":false,"ask":false,"followup":false,"clipboard":false,"model":"primary","translationPolicy":"opposite"}"#
    let legacy = try JSONDecoder().decode(PushToActPreferences.self, from: Data(saved.utf8))
    #expect(!legacy.screenshot)
}
