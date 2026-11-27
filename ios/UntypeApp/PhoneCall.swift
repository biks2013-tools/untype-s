import CallKit

/// Whether a call is in progress on this device: a phone call, FaceTime or a
/// VoIP app that reports its calls to CallKit.
///
/// While a call is in progress, iOS gives the microphone to the call. Other
/// apps can neither record the call nor use the microphone. untype checks for
/// a call before it starts, so it can explain what happened instead of failing
/// or leaving an empty recording. A speakerphone call is no different.
@MainActor
enum PhoneCall {
    /// Kept alive for the life of the app, so `calls` stays current.
    private static let observer = CXCallObserver()

    static var isActive: Bool {
        observer.calls.contains { !$0.hasEnded }
    }

    /// Shown when a meeting recording is started during a call.
    static let meetingBlocked = """
        A call is in progress, and iOS lets only the call use the microphone, \
        even on speaker. untype cannot record it. To record the call, use the \
        record button at the top of the call screen (iOS 18.1 or later), or \
        record it with untype on the Mac with the iPhone on speaker next to it.
        """

    /// Shown when dictation is started during a call.
    static let dictationBlocked = """
        A call is in progress, and iOS lets only the call use the microphone. \
        Dictate again when the call has ended.
        """

    /// Shown while a meeting recording is paused by a call.
    static let meetingPaused = """
        Paused: a call has the microphone. Recording goes on in the same file \
        when the call ends. The call itself is not recorded.
        """
}
