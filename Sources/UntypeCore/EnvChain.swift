import Foundation

public enum EnvSource: String, Sendable, Equatable {
    case flag
    case localEnv = ".env"
    case userEnv = "user"
    case shellEnv = "env"
}

public struct EnvValue: Equatable, Sendable {
    public let value: String
    public let source: EnvSource
}

public struct EnvChain: Sendable {
    private let local: [String: String]
    private let user: [String: String]
    private let shell: [String: String]

    public init(cwd: URL, home: URL, shell: [String: String]) throws {
        self.local = try Dotenv.readIfExists(cwd.appendingPathComponent(".env"))
        self.user = try Dotenv.readIfExists(
            home
                .appendingPathComponent(".tool-agents")
                .appendingPathComponent("untype")
                .appendingPathComponent(".env")
        )
        self.shell = shell
    }

    public func get(_ key: String) -> EnvValue? {
        if let value = nonBlank(local[key]) {
            return EnvValue(value: value, source: .localEnv)
        }
        if let value = nonBlank(user[key]) {
            return EnvValue(value: value, source: .userEnv)
        }
        if let value = nonBlank(shell[key]) {
            return EnvValue(value: value, source: .shellEnv)
        }
        return nil
    }

    private func nonBlank(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }
}
