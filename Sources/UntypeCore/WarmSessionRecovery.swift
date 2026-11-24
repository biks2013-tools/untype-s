import Foundation

/// Decisions for re-warming the push-to-talk session after its runtime ended
/// on its own (the provider closed the socket, a network or microphone
/// error). Pure, so the policy is testable apart from the UI model.
public enum WarmSessionRecovery {
    /// A session that lived this long counts as healthy and resets the backoff.
    public static let healthyLifetime: TimeInterval = 30
    public static let maxDelaySeconds = 60

    /// UI stops use `ui-*` reasons and startup failures `startup-*` (reported
    /// by the start call); any other stop reason means the runtime stopped itself.
    public static func isRuntimeInitiatedStop(_ reason: String?) -> Bool {
        guard let reason else {
            return false
        }
        return !reason.hasPrefix("ui-") && !reason.hasPrefix("startup-")
    }

    public static func attemptsAfterUnexpectedStop(previous: Int, lived: TimeInterval) -> Int {
        lived >= healthyLifetime ? 0 : previous + 1
    }

    /// 1 s for the first retry, then 2, 4, … capped at 60 s.
    public static func delaySeconds(attempts: Int) -> Int {
        attempts <= 0 ? 1 : min(maxDelaySeconds, 1 << min(attempts, 6))
    }

    /// Configuration and authentication errors need the user; retrying them
    /// would only repeat the failure.
    public static func shouldRetryStartup(after error: Error) -> Bool {
        !needsUser(error)
    }

    /// The same rule for a session that was already running: a provider that
    /// rejects the key or the account's balance mid-session (Soniox sends the
    /// error on the open socket) would reject every re-warm as well, which
    /// used to loop once a minute for as long as the app ran.
    public static func shouldRewarm(afterFailure failure: Error?) -> Bool {
        guard let failure else {
            return true
        }
        return !needsUser(failure)
    }

    /// What to tell the user when a failure stops the re-warming.
    public static func userActionMessage(for failure: Error) -> String {
        let detail = (failure as? UntypeError)?.message ?? failure.localizedDescription
        if let error = failure as? UntypeError, error.code.hasSuffix("_billing") {
            return "Push-to-talk is paused: \(detail) Add funds in the provider's console (or pick another provider in Settings), then toggle the hotkey off and on."
        }
        return "Push-to-talk is paused: \(detail) Fix the key or configuration in Settings, then toggle the hotkey off and on."
    }

    private static func needsUser(_ error: Error) -> Bool {
        guard let untypeError = error as? UntypeError else {
            return false
        }
        return untypeError.exitCode == .configuration || untypeError.exitCode == .providerAuth
    }
}
