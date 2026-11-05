import Foundation

/// Push-to-Act (the selection hotkey): the text selected in the active app is
/// processed by the refine/translate/Ask operators chosen in the Push-to-Act
/// pop-up and the result replaces it. No recording, no STT.
public enum SelectionHotkeyPlan {
    /// The operators of a run: the active ones, with the selection as
    /// material (Selection on) and focused-input delivery on, so the result
    /// replaces the selection. nil when none of refine, translate or Ask is
    /// on (there would be nothing to do).
    public static func operators(for settings: UntypeUISettings) -> OperatorState? {
        PushToActChoice(settings: settings, alternativeAvailable: true).operators
    }

    /// The turn context of a run: the selection as material.
    public static func turnContext(selectedText: String) -> UntypeTurnContext {
        UntypeTurnContext(selectedText: selectedText, selectionRole: .material)
    }
}

/// What one Push-to-Act run does, edited in the pop-up. It starts from the
/// saved settings and is never written back: changes apply to this run only.
public struct PushToActChoice: Equatable, Sendable {
    public var refine: Bool
    public var translate: Bool
    public var ask: Bool
    public var followup: Bool
    public var clipboard: Bool
    /// true: the Alternative LLM runs the action; false: the primary LLM.
    public var alternative: Bool
    public var translationPolicy: TranslationPolicy
    /// false when no Alternative LLM is configured; `alternative` then stays off.
    public let alternativeAvailable: Bool

    public init(settings: UntypeUISettings, alternativeAvailable: Bool) {
        refine = settings.refine
        translate = settings.translate
        ask = settings.ask
        followup = settings.followup
        clipboard = settings.clipboard
        self.alternativeAvailable = alternativeAvailable
        alternative = alternativeAvailable && settings.alternative
        translationPolicy = TranslationPolicy(rawValue: settings.translationPolicy) ?? .opposite
    }

    /// Whether the run has something to do (refine, translate or Ask on).
    public var canRun: Bool {
        refine || translate || ask
    }

    /// The operators of the run; nil when `canRun` is false.
    public var operators: OperatorState? {
        guard canRun else {
            return nil
        }
        return OperatorState(
            refine: refine,
            translate: translate,
            clipboard: clipboard,
            input: true,
            ask: ask,
            followup: followup,
            selection: true,
            alternative: alternative && alternativeAvailable
        )
    }

    /// Single-key toggles of the pop-up: r, t, a, f, c and l (model).
    /// Returns false for any other key.
    @discardableResult
    public mutating func toggle(key: Character) -> Bool {
        switch key.lowercased() {
        case "r": refine.toggle()
        case "t": translate.toggle()
        case "a": ask.toggle()
        case "f": followup.toggle()
        case "c": clipboard.toggle()
        case "l":
            guard alternativeAvailable else {
                return false
            }
            alternative.toggle()
        default:
            return false
        }
        return true
    }

    /// Picks the translation direction. Picking a language means "translate
    /// to it", so Translate is turned on too (otherwise the choice would
    /// silently do nothing).
    public mutating func selectTranslation(_ policy: TranslationPolicy) {
        translationPolicy = policy
        translate = true
    }

    /// Next translation direction (opposite → to English → to Greek → …);
    /// turns Translate on like `selectTranslation`.
    public mutating func cycleTranslationPolicy() {
        let all = TranslationPolicy.allCases
        let index = all.firstIndex(of: translationPolicy) ?? 0
        selectTranslation(all[(index + 1) % all.count])
    }
}
