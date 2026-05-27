import Foundation

public struct ReleaseLatencyLoggingConfig: Equatable, Sendable {
    public let enabled: Bool
    public let path: String
    public let resetOnStart: Bool

    public init(enabled: Bool, path: String, resetOnStart: Bool) {
        self.enabled = enabled
        self.path = path
        self.resetOnStart = resetOnStart
    }
}

public protocol ReleaseLatencyLogWriting: AnyObject, Sendable {
    func append(_ record: ReleaseLatencyLogRecord) throws
}

public struct ReleaseLatencyReleaseMarker: Equatable, Sendable {
    public let releaseTimestamp: String
    public let detectedNanoseconds: UInt64

    public init(
        releaseTimestamp: String = releaseLatencyTimestamp(),
        detectedNanoseconds: UInt64 = DispatchTime.now().uptimeNanoseconds
    ) {
        self.releaseTimestamp = releaseTimestamp
        self.detectedNanoseconds = detectedNanoseconds
    }
}

public final class ReleaseLatencyJsonlLogger: ReleaseLatencyLogWriting, @unchecked Sendable {
    private static let resetRegistry = ReleaseLatencyResetRegistry()

    private let url: URL
    private let fileManager: FileManager
    private let lock = NSLock()

    public init(path: String, fileManager: FileManager = .default) {
        self.url = URL(fileURLWithPath: path)
        self.fileManager = fileManager
    }

    public static func resetOnStartIfNeeded(path: String, fileManager: FileManager = .default) throws {
        let url = URL(fileURLWithPath: path).standardizedFileURL
        let pathKey = url.path

        guard resetRegistry.claim(pathKey) else {
            return
        }

        do {
            let directory = url.deletingLastPathComponent()
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
            try Data().write(to: url, options: .atomic)
            try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        } catch {
            resetRegistry.release(pathKey)
            throw error
        }
    }

    public func append(_ record: ReleaseLatencyLogRecord) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(record) + Data("\n".utf8)

        lock.lock()
        defer { lock.unlock() }

        let directory = url.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        if !fileManager.fileExists(atPath: url.path) {
            fileManager.createFile(atPath: url.path, contents: nil)
            try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        }
        let handle = try FileHandle(forWritingTo: url)
        defer {
            try? handle.close()
        }
        try handle.seekToEnd()
        try handle.write(contentsOf: data)
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}

private final class ReleaseLatencyResetRegistry: @unchecked Sendable {
    private let lock = NSLock()
    private var paths: Set<String> = []

    func claim(_ path: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !paths.contains(path) else {
            return false
        }
        paths.insert(path)
        return true
    }

    func release(_ path: String) {
        lock.lock()
        paths.remove(path)
        lock.unlock()
    }
}

public struct ReleaseLatencyLogRecord: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let turnId: String
    public let releaseTimestamp: String
    public let trigger: String
    public let sttProvider: String
    public let quickClose: Bool
    public let textSource: String
    public let outcome: String
    public let totalMs: Double
    public let durationsMs: ReleaseLatencyDurations
    public let sectionsProcessed: Int
    public let focusedInput: ReleaseLatencyFocusedInput
    public let errorCode: String?
    public let errorMessage: String?

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case turnId = "turn_id"
        case releaseTimestamp = "release_timestamp"
        case trigger
        case sttProvider = "stt_provider"
        case quickClose = "quick_close"
        case textSource = "text_source"
        case outcome
        case totalMs = "total_ms"
        case durationsMs = "durations_ms"
        case sectionsProcessed = "sections_processed"
        case focusedInput = "focused_input"
        case errorCode = "error_code"
        case errorMessage = "error_message"
    }

    public init(
        schemaVersion: Int = 1,
        turnId: String,
        releaseTimestamp: String,
        trigger: String,
        sttProvider: String,
        quickClose: Bool,
        textSource: String,
        outcome: String,
        totalMs: Double,
        durationsMs: ReleaseLatencyDurations,
        sectionsProcessed: Int,
        focusedInput: ReleaseLatencyFocusedInput,
        errorCode: String? = nil,
        errorMessage: String? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.turnId = turnId
        self.releaseTimestamp = releaseTimestamp
        self.trigger = trigger
        self.sttProvider = sttProvider
        self.quickClose = quickClose
        self.textSource = textSource
        self.outcome = outcome
        self.totalMs = totalMs
        self.durationsMs = durationsMs
        self.sectionsProcessed = sectionsProcessed
        self.focusedInput = focusedInput
        self.errorCode = errorCode
        self.errorMessage = errorMessage
    }
}

public struct ReleaseLatencyDurations: Codable, Equatable, Sendable {
    public var providerCommitRequestMs: Double?
    public var providerFinalWaitMs: Double?
    public var runtimeSchedulingMs: Double?
    public var protocolSubmissionMs: Double?
    public var protocolOperatorProcessingMs: Double?
    public var refineMs: Double?
    public var translateMs: Double?
    public var clipboardMs: Double?
    public var focusedInputMs: Double?

    enum CodingKeys: String, CodingKey {
        case providerCommitRequestMs = "provider_commit_request_ms"
        case providerFinalWaitMs = "provider_final_wait_ms"
        case runtimeSchedulingMs = "runtime_scheduling_ms"
        case protocolSubmissionMs = "protocol_submission_ms"
        case protocolOperatorProcessingMs = "protocol_operator_processing_ms"
        case refineMs = "refine_ms"
        case translateMs = "translate_ms"
        case clipboardMs = "clipboard_ms"
        case focusedInputMs = "focused_input_ms"
    }

    public init(
        providerCommitRequestMs: Double? = nil,
        providerFinalWaitMs: Double? = nil,
        runtimeSchedulingMs: Double? = nil,
        protocolSubmissionMs: Double? = nil,
        protocolOperatorProcessingMs: Double? = nil,
        refineMs: Double? = nil,
        translateMs: Double? = nil,
        clipboardMs: Double? = nil,
        focusedInputMs: Double? = nil
    ) {
        self.providerCommitRequestMs = providerCommitRequestMs
        self.providerFinalWaitMs = providerFinalWaitMs
        self.runtimeSchedulingMs = runtimeSchedulingMs
        self.protocolSubmissionMs = protocolSubmissionMs
        self.protocolOperatorProcessingMs = protocolOperatorProcessingMs
        self.refineMs = refineMs
        self.translateMs = translateMs
        self.clipboardMs = clipboardMs
        self.focusedInputMs = focusedInputMs
    }
}

public struct ReleaseLatencyFocusedInput: Codable, Equatable, Sendable {
    public let attempted: Bool
    public let ok: Bool?
    public let method: String?
    public let code: String?
    public let accessibilityTrusted: Bool?
    public let focusedElementAvailable: Bool?
    public let targetRole: String?
    public let targetSubrole: String?

    enum CodingKeys: String, CodingKey {
        case attempted
        case ok
        case method
        case code
        case accessibilityTrusted = "accessibility_trusted"
        case focusedElementAvailable = "focused_element_available"
        case targetRole = "target_role"
        case targetSubrole = "target_subrole"
    }

    public init(
        attempted: Bool,
        ok: Bool? = nil,
        method: String? = nil,
        code: String? = nil,
        accessibilityTrusted: Bool? = nil,
        focusedElementAvailable: Bool? = nil,
        targetRole: String? = nil,
        targetSubrole: String? = nil
    ) {
        self.attempted = attempted
        self.ok = ok
        self.method = method
        self.code = code
        self.accessibilityTrusted = accessibilityTrusted
        self.focusedElementAvailable = focusedElementAvailable
        self.targetRole = targetRole
        self.targetSubrole = targetSubrole
    }

    public static func notAttempted() -> ReleaseLatencyFocusedInput {
        ReleaseLatencyFocusedInput(attempted: false)
    }

    public static func from(_ result: FocusedInputDeliveryResult) -> ReleaseLatencyFocusedInput {
        ReleaseLatencyFocusedInput(
            attempted: true,
            ok: result.ok,
            method: result.method,
            code: result.code,
            accessibilityTrusted: result.accessibilityTrusted,
            focusedElementAvailable: result.focusedElementAvailable,
            targetRole: result.targetRole,
            targetSubrole: result.targetSubrole
        )
    }

    public static func failure(error: Error) -> ReleaseLatencyFocusedInput {
        if let error = error as? FocusedInputDeliveryError {
            return ReleaseLatencyFocusedInput(
                attempted: true,
                ok: false,
                code: error.code ?? "focused_input_failed"
            )
        }
        return ReleaseLatencyFocusedInput(
            attempted: true,
            ok: false,
            code: "focused_input_failed"
        )
    }
}

public struct ProtocolSubmissionSummary: Equatable, Sendable {
    public var sectionsProcessed: Int
    public var operatorProcessingMs: Double?
    public var refineMs: Double?
    public var translateMs: Double?
    public var clipboardMs: Double?
    public var focusedInputMs: Double?
    public var focusedInput: ReleaseLatencyFocusedInput?

    public init(
        sectionsProcessed: Int = 0,
        operatorProcessingMs: Double? = nil,
        refineMs: Double? = nil,
        translateMs: Double? = nil,
        clipboardMs: Double? = nil,
        focusedInputMs: Double? = nil,
        focusedInput: ReleaseLatencyFocusedInput? = nil
    ) {
        self.sectionsProcessed = sectionsProcessed
        self.operatorProcessingMs = operatorProcessingMs
        self.refineMs = refineMs
        self.translateMs = translateMs
        self.clipboardMs = clipboardMs
        self.focusedInputMs = focusedInputMs
        self.focusedInput = focusedInput
    }

    public mutating func merge(_ other: ProtocolSubmissionSummary) {
        sectionsProcessed += other.sectionsProcessed
        operatorProcessingMs = sum(operatorProcessingMs, other.operatorProcessingMs)
        refineMs = sum(refineMs, other.refineMs)
        translateMs = sum(translateMs, other.translateMs)
        clipboardMs = sum(clipboardMs, other.clipboardMs)
        focusedInputMs = sum(focusedInputMs, other.focusedInputMs)
        if let focusedInput = other.focusedInput {
            self.focusedInput = focusedInput
        }
    }
}

private func sum(_ lhs: Double?, _ rhs: Double?) -> Double? {
    switch (lhs, rhs) {
    case (.some(let lhs), .some(let rhs)):
        return lhs + rhs
    case (.some(let lhs), .none):
        return lhs
    case (.none, .some(let rhs)):
        return rhs
    case (.none, .none):
        return nil
    }
}

public func releaseLatencyMilliseconds(from start: UInt64, to end: UInt64 = DispatchTime.now().uptimeNanoseconds) -> Double {
    Double(end - start) / 1_000_000
}

public func releaseLatencyTimestamp(_ date: Date = Date()) -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.string(from: date)
}
