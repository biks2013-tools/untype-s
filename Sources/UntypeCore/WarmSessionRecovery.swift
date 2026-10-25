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
        guard let untypeError = error as? UntypeError else {
            return true
        }
        return untypeError.exitCode != .configuration && untypeError.exitCode != .providerAuth
    }
}
