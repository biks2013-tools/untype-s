import Foundation

/// What to tell the user when the speech provider refuses to work until they
/// act (empty balance, rejected key, missing configuration). Shown as a macOS
/// notification, a notice on the overlay and a row in the Transcript tab, so
/// the user learns it even with the untype window closed. Pure, so the text
/// and the rules are testable apart from the UI.
public struct ProviderAccountAlert: Equatable, Sendable {
    public let title: String
    public let body: String
    /// The few words the push-to-talk overlay has room for (two lines).
    public let short: String
    /// Groups repeats of the same problem, for `AlertThrottle`.
    public let key: String

    /// Nil for failures that clear up on their own (network, protocol):
    /// those keep the silent re-warm with backoff.
    public static func make(for failure: Error) -> ProviderAccountAlert? {
        guard let error = failure as? UntypeError else {
            return nil
        }
        let provider = providerName(code: error.code)
        switch error.exitCode {
        case .providerAuth where error.code.hasSuffix("_billing"):
            return billing(provider: provider)
        case .providerAuth:
            return ProviderAccountAlert(
                title: "untype can't transcribe",
                body: "\(provider) rejected the API key. Update it in Settings → Permissions & Keys, then press the hotkey again.",
                short: "\(provider) API key rejected",
                key: "\(error.code)"
            )
        case .configuration:
            return ProviderAccountAlert(
                title: "untype can't transcribe",
                body: "\(error.message) Fix it in Settings, then press the hotkey again.",
                short: "Setup needed in Settings",
                key: "\(error.code)"
            )
        default:
            return nil
        }
    }

    /// Meeting streams report Soniox errors as plain text; only a billing
    /// failure is recognised there.
    public static func make(forMeetingFailure message: String) -> ProviderAccountAlert? {
        guard isSonioxBillingMessage(message) else {
            return nil
        }
        return ProviderAccountAlert(
            title: "Meeting recording stopped",
            body: "Your Soniox balance is used up, so nothing could be transcribed. Add funds at console.soniox.com or switch provider in Settings.",
            short: "Soniox balance used up",
            key: "soniox_billing_meeting"
        )
    }

    private static func billing(provider: String) -> ProviderAccountAlert {
        ProviderAccountAlert(
            title: "untype can't transcribe",
            body: provider == "Soniox"
                ? "Your Soniox balance is used up. Add funds at console.soniox.com or switch provider in Settings, then press the hotkey again."
                : "Your \(provider) balance is used up. Add funds or switch provider in Settings, then press the hotkey again.",
            short: "\(provider) balance used up",
            key: "\(provider.lowercased())_billing"
        )
    }

    private static func providerName(code: String) -> String {
        if code.hasPrefix("soniox") { return "Soniox" }
        if code.hasPrefix("elevenlabs") { return "ElevenLabs" }
        if code.hasPrefix("google") { return "Google" }
        return "The speech provider"
    }
}

/// At most one alert per key in `interval`, so a user pressing the hotkey
/// several times in a row is told once, not once per press.
public struct AlertThrottle: Sendable {
    public let interval: TimeInterval
    private var lastShown: [String: Date] = [:]

    public init(interval: TimeInterval = 30) {
        self.interval = interval
    }

    public mutating func shouldShow(_ key: String, now: Date = Date()) -> Bool {
        if let last = lastShown[key], now.timeIntervalSince(last) < interval {
            return false
        }
        lastShown[key] = now
        return true
    }
}
