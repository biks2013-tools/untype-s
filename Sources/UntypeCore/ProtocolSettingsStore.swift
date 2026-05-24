import Foundation

public struct ProtocolSettingsStoreOptions: Sendable, Equatable {
    public let toolName: String
    public let home: URL

    public init(toolName: String = "untype", home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.toolName = toolName
        self.home = home
    }
}

public func protocolSettingsPath(options: ProtocolSettingsStoreOptions = ProtocolSettingsStoreOptions()) -> URL {
    options.home
        .appendingPathComponent(".tool-agents")
        .appendingPathComponent(options.toolName)
        .appendingPathComponent("state.json")
}

public func loadPersistedProtocolSettings(
    options: ProtocolSettingsStoreOptions = ProtocolSettingsStoreOptions()
) throws -> ProtocolSettingsSnapshot? {
    let path = protocolSettingsPath(options: options)
    guard FileManager.default.fileExists(atPath: path.path) else {
        return nil
    }

    do {
        let data = try Data(contentsOf: path)
        return try JSONDecoder().decode(PersistedProtocolStateFile.self, from: data).protocol
    } catch let error as DecodingError {
        throw UntypeError.invalidConfiguration(
            "Invalid protocol settings state at \(path.path): \(error.shortDescription). Delete or fix \(path.path)."
        )
    } catch let error as UntypeError {
        throw error
    } catch {
        throw UntypeError.invalidConfiguration(
            "Failed to read protocol settings state at \(path.path): \(error.localizedDescription)"
        )
    }
}

public func savePersistedProtocolSettings(
    _ settings: ProtocolSettingsSnapshot,
    options: ProtocolSettingsStoreOptions = ProtocolSettingsStoreOptions()
) throws {
    let path = protocolSettingsPath(options: options)
    let directory = path.deletingLastPathComponent()
    do {
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)

        let file = PersistedProtocolStateFile(
            savedAt: ISO8601DateFormatter().string(from: Date()),
            protocol: settings
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(file)
        var output = String(data: data, encoding: .utf8) ?? ""
        output.append("\n")
        try output.write(to: path, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path.path)
    } catch let error as UntypeError {
        throw error
    } catch {
        throw UntypeError.invalidConfiguration(
            "Failed to write protocol settings state at \(path.path): \(error.localizedDescription)"
        )
    }
}

public func applyPersistedProtocolSettings(
    _ protocolConfig: ProtocolRuntimeConfig,
    persisted: ProtocolSettingsSnapshot?
) -> ProtocolRuntimeConfig {
    guard let persisted else {
        return protocolConfig
    }

    let operators = OperatorState(
        refine: protocolConfig.settingSources.refine == .default
            ? persisted.operators.refine
            : protocolConfig.initialOperators.refine,
        translate: protocolConfig.settingSources.translate == .default
            ? persisted.operators.translate
            : protocolConfig.initialOperators.translate,
        clipboard: protocolConfig.settingSources.clipboard == .default
            ? persisted.operators.clipboard
            : protocolConfig.initialOperators.clipboard,
        input: protocolConfig.settingSources.input == .default
            ? persisted.operators.input
            : protocolConfig.initialOperators.input
    )

    let translationPolicy = protocolConfig.settingSources.translationPolicy == .default
        ? persisted.translationPolicy
        : protocolConfig.translationPolicy

    return ProtocolRuntimeConfig(
        interactionMode: protocolConfig.interactionMode,
        markers: protocolConfig.markers,
        initialOperators: operators,
        translationPolicy: translationPolicy,
        protocolOutput: protocolConfig.protocolOutput,
        settingSources: protocolConfig.settingSources
    )
}

private struct PersistedProtocolStateFile: Codable {
    let version: Int
    let savedAt: String
    let `protocol`: ProtocolSettingsSnapshot

    enum CodingKeys: String, CodingKey {
        case version
        case savedAt = "saved_at"
        case `protocol`
    }

    init(savedAt: String, protocol: ProtocolSettingsSnapshot) {
        self.version = 1
        self.savedAt = savedAt
        self.protocol = `protocol`
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let version = try container.decode(Int.self, forKey: .version)
        guard version == 1 else {
            throw DecodingError.dataCorruptedError(
                forKey: .version,
                in: container,
                debugDescription: "version must be 1"
            )
        }
        let savedAt = try container.decode(String.self, forKey: .savedAt)
        guard !savedAt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw DecodingError.dataCorruptedError(
                forKey: .savedAt,
                in: container,
                debugDescription: "saved_at must be a non-empty string"
            )
        }
        let protocolSnapshot = try container.decode(ProtocolSettingsSnapshot.self, forKey: .protocol)
        self.version = version
        self.savedAt = savedAt
        self.protocol = protocolSnapshot
    }
}

private extension DecodingError {
    var shortDescription: String {
        switch self {
        case .typeMismatch(_, let context),
             .valueNotFound(_, let context),
             .keyNotFound(_, let context),
             .dataCorrupted(let context):
            return context.debugDescription
        @unknown default:
            return localizedDescription
        }
    }
}
