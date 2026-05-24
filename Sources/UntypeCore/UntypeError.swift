public struct UntypeError: Error, Equatable, Sendable {
    public let code: String
    public let message: String
    public let exitCode: ExitCode

    public init(code: String, message: String, exitCode: ExitCode) {
        self.code = code
        self.message = message
        self.exitCode = exitCode
    }

    public var diagnosticLine: String {
        "\(code): \(message)"
    }

    public static func missingConfiguration(_ message: String) -> UntypeError {
        UntypeError(code: "missing_configuration", message: message, exitCode: .configuration)
    }

    public static func invalidConfiguration(_ message: String) -> UntypeError {
        UntypeError(code: "invalid_configuration", message: message, exitCode: .configuration)
    }

    public static func notImplemented(_ message: String) -> UntypeError {
        UntypeError(code: "not_implemented", message: message, exitCode: .unknown)
    }

    public static func sonioxAuth(_ message: String) -> UntypeError {
        UntypeError(code: "soniox_auth", message: message, exitCode: .providerAuth)
    }

    public static func sonioxNetwork(_ message: String) -> UntypeError {
        UntypeError(code: "soniox_network", message: message, exitCode: .providerNetwork)
    }

    public static func sonioxProtocol(_ message: String) -> UntypeError {
        UntypeError(code: "soniox_protocol", message: message, exitCode: .providerProtocol)
    }

    public static func elevenLabsAuth(_ message: String) -> UntypeError {
        UntypeError(code: "elevenlabs_auth", message: message, exitCode: .providerAuth)
    }

    public static func elevenLabsNetwork(_ message: String) -> UntypeError {
        UntypeError(code: "elevenlabs_network", message: message, exitCode: .providerNetwork)
    }

    public static func elevenLabsProtocol(_ message: String) -> UntypeError {
        UntypeError(code: "elevenlabs_protocol", message: message, exitCode: .providerProtocol)
    }

    public static func microphonePermission(_ message: String) -> UntypeError {
        UntypeError(code: "microphone_permission", message: message, exitCode: .microphone)
    }

    public static func microphoneCapture(_ message: String) -> UntypeError {
        UntypeError(code: "microphone_capture", message: message, exitCode: .microphone)
    }
}
