import ApplicationServices
import AVFoundation

public struct UntypePermissionStatus: Equatable, Sendable {
    public let microphone: String
    public let accessibility: String

    public init(microphone: String, accessibility: String) {
        self.microphone = microphone
        self.accessibility = accessibility
    }

    public static func current() -> UntypePermissionStatus {
        UntypePermissionStatus(
            microphone: microphoneLabel(AVCaptureDevice.authorizationStatus(for: .audio)),
            accessibility: AXIsProcessTrusted() ? "trusted" : "not trusted"
        )
    }

    private static func microphoneLabel(_ status: AVAuthorizationStatus) -> String {
        switch status {
        case .authorized:
            return "authorized"
        case .notDetermined:
            return "not determined"
        case .denied:
            return "denied"
        case .restricted:
            return "restricted"
        @unknown default:
            return "unknown"
        }
    }
}
