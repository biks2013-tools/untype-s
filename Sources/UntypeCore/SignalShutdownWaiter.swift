import Darwin
import Dispatch

public enum SignalShutdownWaiter {
    public static func waitForTerminationSignal() async -> String {
        signal(SIGINT, SIG_IGN)
        signal(SIGTERM, SIG_IGN)

        return await withCheckedContinuation { continuation in
            final class SignalState {
                var didResume = false
            }

            let state = SignalState()
            let queue = DispatchQueue(label: "untype.signal-shutdown")
            let interrupt = DispatchSource.makeSignalSource(signal: SIGINT, queue: queue)
            let terminate = DispatchSource.makeSignalSource(signal: SIGTERM, queue: queue)

            func resumeOnce(_ reason: String) {
                guard !state.didResume else {
                    return
                }
                state.didResume = true
                interrupt.cancel()
                terminate.cancel()
                continuation.resume(returning: reason)
            }

            interrupt.setEventHandler {
                resumeOnce("signal-int")
            }
            terminate.setEventHandler {
                resumeOnce("signal-term")
            }
            interrupt.resume()
            terminate.resume()
        }
    }
}
