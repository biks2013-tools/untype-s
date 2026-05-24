import Foundation

public protocol TextOutput {
    func write(_ text: String)
}

public struct StandardStreamWriter: TextOutput {
    private let file: UnsafeMutablePointer<FILE>

    public init(file: UnsafeMutablePointer<FILE>) {
        self.file = file
    }

    public func write(_ text: String) {
        fputs(text, file)
        fflush(file)
    }
}

public final class FileTextOutput: TextOutput {
    private let handle: FileHandle

    public init(path: String) throws {
        let url = URL(fileURLWithPath: path.expandingTildeInPath)
        let directory = url.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            FileManager.default.createFile(atPath: url.path, contents: Data())
            handle = try FileHandle(forWritingTo: url)
            try handle.truncate(atOffset: 0)
        } catch {
            throw UntypeError.invalidConfiguration(
                "Failed to open protocol output file at \(url.path): \(error.localizedDescription)"
            )
        }
    }

    deinit {
        try? handle.close()
    }

    public func write(_ text: String) {
        guard let data = text.data(using: .utf8) else {
            return
        }
        try? handle.write(contentsOf: data)
    }
}

public final class MemoryOutput: TextOutput {
    private var storage = ""

    public init() {}

    public func write(_ text: String) {
        storage += text
    }

    public var text: String {
        storage
    }
}

private extension String {
    var expandingTildeInPath: String {
        if self == "~" {
            return FileManager.default.homeDirectoryForCurrentUser.path
        }
        if hasPrefix("~/") {
            return FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(String(dropFirst(2)))
                .path
        }
        return self
    }
}
