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

    /// The turn context of a run: the selection as material, and the
    /// window's screenshot when the Screenshot operator is on.
    public static func turnContext(selectedText: String, screenshot: WindowScreenshot? = nil) -> UntypeTurnContext {
        UntypeTurnContext(selectedText: selectedText, selectionRole: .material, screenshot: screenshot)
    }
}

/// The model of one Push-to-Act run.
public enum PushToActModel: String, Equatable, Sendable {
    case primary
    /// The alternative LLM (`UNTYPE_ALT_LLM_*`), the one the Alternative operator uses.
    case alternative
    /// The second alternative LLM (`UNTYPE_ALT2_LLM_*`).
    case alternative2
}

/// Push-to-Act's own remembered choices, separate from the push-to-talk /
/// push-to-listen operators: saved on every Push-to-Act run and restored
/// the next time the pop-up opens. Stored as `pushToAct` in ui-state.json.
public struct PushToActPreferences: Codable, Equatable, Sendable {
    public var refine: Bool
    public var translate: Bool
    public var ask: Bool
    public var followup: Bool
    public var clipboard: Bool
    /// Send a screenshot of the app's window (absent in choices saved
    /// before build 39: off).
    public var screenshot: Bool
    /// `PushToActModel` raw value; an unknown or no-longer-configured model
    /// opens as the primary.
    public var model: String
    /// `TranslationPolicy` raw value.
    public var translationPolicy: String

    public init(
        refine: Bool,
        translate: Bool,
        ask: Bool,
        followup: Bool,
        clipboard: Bool,
        screenshot: Bool = false,
        model: String,
        translationPolicy: String
    ) {
        self.refine = refine
        self.translate = translate
        self.ask = ask
        self.followup = followup
        self.clipboard = clipboard
        self.screenshot = screenshot
        self.model = model
        self.translationPolicy = translationPolicy
    }

    enum CodingKeys: String, CodingKey {
        case refine, translate, ask, followup, clipboard, screenshot, model, translationPolicy
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            refine: try container.decode(Bool.self, forKey: .refine),
            translate: try container.decode(Bool.self, forKey: .translate),
            ask: try container.decode(Bool.self, forKey: .ask),
            followup: try container.decode(Bool.self, forKey: .followup),
            clipboard: try container.decode(Bool.self, forKey: .clipboard),
            screenshot: try container.decodeIfPresent(Bool.self, forKey: .screenshot) ?? false,
            model: try container.decode(String.self, forKey: .model),
            translationPolicy: try container.decode(String.self, forKey: .translationPolicy)
        )
    }
}

/// What one Push-to-Act run does, edited in the pop-up. It starts from the
/// remembered Push-to-Act choices (`settings.pushToAct`); before the first
/// run, from the push-to-talk operators. The launcher saves it back on Run.
public struct PushToActChoice: Equatable, Sendable {
    public var refine: Bool
    public var translate: Bool
    public var ask: Bool
    public var followup: Bool
    public var clipboard: Bool
    /// Send a screenshot of the app's window with the request.
    public var screenshot: Bool
    /// The LLM that runs the action; only a configured one can be picked.
    public private(set) var model: PushToActModel
    public var translationPolicy: TranslationPolicy
    /// Whether the alternative LLMs are configured.
    public let alternativeAvailable: Bool
    public let alternative2Available: Bool

    public init(settings: UntypeUISettings, alternativeAvailable: Bool, alternative2Available: Bool = false) {
        self.alternativeAvailable = alternativeAvailable
        self.alternative2Available = alternative2Available
        if let saved = settings.pushToAct {
            refine = saved.refine
            translate = saved.translate
            ask = saved.ask
            followup = saved.followup
            clipboard = saved.clipboard
            screenshot = saved.screenshot
            model = .primary
            translationPolicy = TranslationPolicy(rawValue: saved.translationPolicy) ?? .opposite
            if let savedModel = PushToActModel(rawValue: saved.model) {
                select(savedModel)
            }
            return
        }
        refine = settings.refine
        translate = settings.translate
        ask = settings.ask
        followup = settings.followup
        clipboard = settings.clipboard
        screenshot = settings.screenshot
        // The Alternative operator's setting picks the first alternative LLM.
        model = alternativeAvailable && settings.alternative ? .alternative : .primary
        translationPolicy = TranslationPolicy(rawValue: settings.translationPolicy) ?? .opposite
    }

    /// The choices to remember for the next Push-to-Act run.
    public var preferences: PushToActPreferences {
        PushToActPreferences(
            refine: refine,
            translate: translate,
            ask: ask,
            followup: followup,
            clipboard: clipboard,
            screenshot: screenshot,
            model: model.rawValue,
            translationPolicy: translationPolicy.rawValue
        )
    }

    /// true: an alternative LLM runs the action.
    public var alternative: Bool {
        model != .primary
    }

    /// The models that can be picked, in pop-up order.
    public var availableModels: [PushToActModel] {
        [.primary]
            + (alternativeAvailable ? [.alternative] : [])
            + (alternative2Available ? [.alternative2] : [])
    }

    /// Picks `model`; false (unchanged) when it is not configured.
    @discardableResult
    public mutating func select(_ model: PushToActModel) -> Bool {
        guard availableModels.contains(model) else {
            return false
        }
        self.model = model
        return true
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
            alternative: alternative,
            screenshot: screenshot
        )
    }

    /// Single-key toggles of the pop-up: r, t, a, f, c, w, and l (next model:
    /// primary → alternative → alternative 2 → primary, configured ones only).
    /// Returns false for any other key.
    @discardableResult
    public mutating func toggle(key: Character) -> Bool {
        switch key.lowercased() {
        case "r": refine.toggle()
        case "t": translate.toggle()
        case "a": ask.toggle()
        case "f": followup.toggle()
        case "c": clipboard.toggle()
        case "w": screenshot.toggle()
        case "l":
            let models = availableModels
            guard models.count > 1, let index = models.firstIndex(of: model) else {
                return false
            }
            model = models[(index + 1) % models.count]
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
