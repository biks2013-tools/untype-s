import Foundation

public enum FocusedInputDeliveryMethod: String, CaseIterable, Sendable {
    case auto
    case axValue = "ax-value"
    case unicodeEvents = "unicode-events"
    case pasteKeycode = "paste-keycode"
}

public struct FocusedInputDeliveryResult: Codable, Equatable, Sendable {
    public let ok: Bool
    public let method: String?
    public let code: String?
    public let message: String?
    public let targetRole: String?
    public let targetSubrole: String?
    public let clipboardRestored: Bool?
    public let accessibilityTrusted: Bool?
    public let focusedElementAvailable: Bool?
    public let axValueReadable: Bool?
    public let axValueSettable: Bool?
    public let axSelectedTextRangeReadable: Bool?
    public let axSelectedTextRangeSettable: Bool?
    public let pasteboardAvailable: Bool?

    enum CodingKeys: String, CodingKey {
        case ok
        case method
        case code
        case message
        case targetRole = "target_role"
        case targetSubrole = "target_subrole"
        case clipboardRestored = "clipboard_restored"
        case accessibilityTrusted = "accessibility_trusted"
        case focusedElementAvailable = "focused_element_available"
        case axValueReadable = "ax_value_readable"
        case axValueSettable = "ax_value_settable"
        case axSelectedTextRangeReadable = "ax_selected_text_range_readable"
        case axSelectedTextRangeSettable = "ax_selected_text_range_settable"
        case pasteboardAvailable = "pasteboard_available"
    }

    public init(
        ok: Bool,
        method: String? = nil,
        code: String? = nil,
        message: String? = nil,
        targetRole: String? = nil,
        targetSubrole: String? = nil,
        clipboardRestored: Bool? = nil,
        accessibilityTrusted: Bool? = nil,
        focusedElementAvailable: Bool? = nil,
        axValueReadable: Bool? = nil,
        axValueSettable: Bool? = nil,
        axSelectedTextRangeReadable: Bool? = nil,
        axSelectedTextRangeSettable: Bool? = nil,
        pasteboardAvailable: Bool? = nil
    ) {
        self.ok = ok
        self.method = method
        self.code = code
        self.message = message
        self.targetRole = targetRole
        self.targetSubrole = targetSubrole
        self.clipboardRestored = clipboardRestored
        self.accessibilityTrusted = accessibilityTrusted
        self.focusedElementAvailable = focusedElementAvailable
        self.axValueReadable = axValueReadable
        self.axValueSettable = axValueSettable
        self.axSelectedTextRangeReadable = axSelectedTextRangeReadable
        self.axSelectedTextRangeSettable = axSelectedTextRangeSettable
        self.pasteboardAvailable = pasteboardAvailable
    }

    public static func success(
        method: String,
        targetRole: String? = nil,
        targetSubrole: String? = nil,
        clipboardRestored: Bool? = nil
    ) -> FocusedInputDeliveryResult {
        FocusedInputDeliveryResult(
            ok: true,
            method: method,
            targetRole: targetRole,
            targetSubrole: targetSubrole,
            clipboardRestored: clipboardRestored
        )
    }

    public static func failure(code: String, message: String) -> FocusedInputDeliveryResult {
        FocusedInputDeliveryResult(ok: false, code: code, message: message)
    }
}

public struct FocusedInputDeliveryError: Error, Equatable, LocalizedError, Sendable {
    public let message: String
    public let code: String?
    public let helperExitCode: Int32?
    public let diagnostics: String?

    public init(
        message: String,
        code: String? = nil,
        helperExitCode: Int32? = nil,
        diagnostics: String? = nil
    ) {
        self.message = message
        self.code = code
        self.helperExitCode = helperExitCode
        self.diagnostics = diagnostics
    }

    public var errorDescription: String? {
        message
    }
}

public struct FocusedInputHelperProcessResult: Equatable, Sendable {
    public let exitCode: Int32?
    public let stdout: String
    public let stderr: String

    public init(exitCode: Int32?, stdout: String, stderr: String = "") {
        self.exitCode = exitCode
        self.stdout = stdout
        self.stderr = stderr
    }
}

public typealias FocusedInputHelperRunner = (
    _ helperPath: String,
    _ args: [String],
    _ stdinText: String,
    _ timeoutSeconds: TimeInterval
) async throws -> FocusedInputHelperProcessResult

public final class FocusedInputDelivery {
    public static let defaultTimeoutSeconds: TimeInterval = 10

    private let helperPath: String?
    private let method: FocusedInputDeliveryMethod
    private let timeoutSeconds: TimeInterval
    private let runner: FocusedInputHelperRunner

    public init(
        helperPath: String? = nil,
        method: FocusedInputDeliveryMethod = .auto,
        timeoutSeconds: TimeInterval = FocusedInputDelivery.defaultTimeoutSeconds,
        runner: @escaping FocusedInputHelperRunner = runFocusedInputHelperProcess
    ) {
        self.helperPath = helperPath
        self.method = method
        self.timeoutSeconds = timeoutSeconds
        self.runner = runner
    }

    public func send(_ text: String) async throws {
        let result = try await deliver(text)
        guard result.ok else {
            throw FocusedInputDeliveryError(
                message: "\(result.code ?? "focused_input_failed"): \(result.message ?? "Focused input delivery failed.")",
                code: result.code
            )
        }
    }

    public func deliver(_ text: String) async throws -> FocusedInputDeliveryResult {
        let path = try helperPath ?? Self.resolveHelperPath()
        let process = try await runner(path, ["send", "--method", method.rawValue], text, timeoutSeconds)
        do {
            let parsed = try Self.parseHelperResult(process.stdout)
            if parsed.ok, process.exitCode == 0 {
                return parsed
            }
            if !parsed.ok, process.exitCode == 2 {
                return parsed
            }
            throw FocusedInputDeliveryError(
                message: "\(parsed.code ?? "focused_input_helper_failed"): \(parsed.message ?? "Focused input helper failed.")",
                code: parsed.code,
                helperExitCode: process.exitCode,
                diagnostics: Self.trimForDiagnostics(process.stderr)
            )
        } catch let error as FocusedInputDeliveryError {
            throw error
        } catch {
            throw FocusedInputDeliveryError(
                message: "Focused input helper returned invalid JSON.",
                helperExitCode: process.exitCode,
                diagnostics: Self.trimForDiagnostics(process.stderr)
            )
        }
    }

    public static func parseHelperResult(_ stdout: String) throws -> FocusedInputDeliveryResult {
        let lines = stdout
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard lines.count == 1 else {
            throw FocusedInputDeliveryError(
                message: "Expected one helper JSON line, received \(lines.count).",
                code: "invalid_helper_output"
            )
        }

        let data = Data(lines[0].utf8)
        let result = try JSONDecoder().decode(FocusedInputDeliveryResult.self, from: data)
        if let method = result.method,
           method != FocusedInputDeliveryMethod.axValue.rawValue,
           method != FocusedInputDeliveryMethod.unicodeEvents.rawValue,
           method != FocusedInputDeliveryMethod.pasteKeycode.rawValue {
            throw FocusedInputDeliveryError(
                message: "Unsupported helper method in result: \(method).",
                code: "invalid_helper_output"
            )
        }
        return result
    }

    public static func resolveHelperPath(
        executablePath: String? = nil,
        fileManager: FileManager = .default
    ) throws -> String {
        let baseExecutablePath = executablePath
            ?? Bundle.main.executableURL?.path
            ?? CommandLine.arguments.first
            ?? "untype"
        let executableURL: URL
        if baseExecutablePath.contains("/") {
            executableURL = absoluteURL(forPath: baseExecutablePath)
        } else if let bundleExecutable = Bundle.main.executableURL {
            executableURL = bundleExecutable
        } else {
            executableURL = absoluteURL(forPath: baseExecutablePath)
        }
        let helperURL = executableURL.deletingLastPathComponent().appendingPathComponent("untype-input-helper")
        guard fileManager.isExecutableFile(atPath: helperURL.path) else {
            throw FocusedInputDeliveryError(
                message: "Focused input helper is not installed or executable at \(helperURL.path). Rebuild untype so the native helper is bundled.",
                code: "helper_unavailable"
            )
        }
        return helperURL.path
    }

    static func trimForDiagnostics(_ stderr: String) -> String? {
        let trimmed = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }
        return String(trimmed.prefix(4_000))
    }

    private static func absoluteURL(forPath path: String) -> URL {
        let url = URL(fileURLWithPath: path)
        if url.path.hasPrefix("/") {
            return url
        }
        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(path)
    }
}

public func runFocusedInputHelperProcess(
    helperPath: String,
    args: [String],
    stdinText: String,
    timeoutSeconds: TimeInterval
) async throws -> FocusedInputHelperProcessResult {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: helperPath)
    process.arguments = args

    let stdinPipe = Pipe()
    let stdoutPipe = Pipe()
    let stderrPipe = Pipe()
    process.standardInput = stdinPipe
    process.standardOutput = stdoutPipe
    process.standardError = stderrPipe

    do {
        try process.run()
    } catch {
        throw FocusedInputDeliveryError(message: "Could not start focused input helper.")
    }

    if let data = stdinText.data(using: .utf8) {
        try stdinPipe.fileHandleForWriting.write(contentsOf: data)
    }
    try? stdinPipe.fileHandleForWriting.close()

    let deadline = Date().addingTimeInterval(timeoutSeconds)
    while process.isRunning, Date() < deadline {
        try await Task.sleep(nanoseconds: 20_000_000)
    }
    if process.isRunning {
        process.terminate()
        throw FocusedInputDeliveryError(
            message: "Focused input helper timed out.",
            code: "delivery_timeout",
            diagnostics: readPipeString(stderrPipe)
        )
    }

    return FocusedInputHelperProcessResult(
        exitCode: process.terminationStatus,
        stdout: readPipeString(stdoutPipe) ?? "",
        stderr: readPipeString(stderrPipe) ?? ""
    )
}

private func readPipeString(_ pipe: Pipe) -> String? {
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    guard !data.isEmpty else {
        return nil
    }
    return String(data: data, encoding: .utf8)
}
