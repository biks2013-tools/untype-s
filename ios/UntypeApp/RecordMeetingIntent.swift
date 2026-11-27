import AppIntents
import Foundation

/// "Record meeting": opens untype and starts recording at once. Used by
/// Siri, the Shortcuts app, Spotlight, the Action button and the Control
/// Center button (the `UntypeControls` extension). The file is in both
/// targets; it runs in the app (`openAppWhenRun`), where `start` is set.
struct RecordMeetingIntent: AppIntent {
    static let title: LocalizedStringResource = "Record meeting"
    static let description = IntentDescription("Opens untype and starts recording a meeting.")
    static let openAppWhenRun = true

    /// Set by the app at launch; nil in the extension.
    @MainActor static var start: (() -> Void)?

    @MainActor
    func perform() async throws -> some IntentResult {
        Self.start?()
        return .result()
    }
}
