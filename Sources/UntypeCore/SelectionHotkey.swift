import Foundation

/// Selection hotkey: the text selected in the active app is processed by the
/// active refine/translate/Ask operators (Alternative and Follow-up apply as
/// for dictation) and the result replaces it. No recording, no STT.
public enum SelectionHotkeyPlan {
    /// The operators of a selection-hotkey run: the active ones, with the
    /// selection as material (Selection on) and focused-input delivery on, so
    /// the result replaces the selection. nil when none of refine, translate
    /// or Ask is on (there would be nothing to do).
    public static func operators(for settings: UntypeUISettings) -> OperatorState? {
        guard settings.refine || settings.translate || settings.ask else {
            return nil
        }
        return OperatorState(
            refine: settings.refine,
            translate: settings.translate,
            clipboard: settings.clipboard,
            input: true,
            ask: settings.ask,
            followup: settings.followup,
            selection: true,
            alternative: settings.alternative
        )
    }

    /// The turn context of a run: the selection as material.
    public static func turnContext(selectedText: String) -> UntypeTurnContext {
        UntypeTurnContext(selectedText: selectedText, selectionRole: .material)
    }
}
