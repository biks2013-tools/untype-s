public protocol TranscriptRendering {
    func partial(_ text: String)
    func final(_ text: String)
    func turnBoundary()
    func refined(_ text: String)
    func dispose()
}

public final class TranscriptRenderer: TranscriptRendering {
    private let output: TextOutput
    private let isTTY: Bool
    private let terminalColumns: Int
    public let effectiveMode: OutputMode

    private var previousLength = 0
    private var previousRows = 0
    private var lastPartialText: String?
    private var disposed = false

    public init(
        output: TextOutput,
        mode: OutputMode,
        isTTY: Bool,
        terminalColumns: Int = 80
    ) {
        self.output = output
        self.isTTY = isTTY
        self.terminalColumns = max(1, terminalColumns)
        self.effectiveMode = mode == .overwrite && !isTTY ? .append : mode
    }

    public func partial(_ text: String) {
        guard !disposed else {
            return
        }
        let filtered = filterMarkerTokens(text)
        guard !filtered.isEmpty, filtered != lastPartialText else {
            return
        }
        lastPartialText = filtered

        switch effectiveMode {
        case .overwrite:
            let safe = sanitizeForOverwrite(filtered)
            let prefix = overwritePrefix()
            let padding = previousRows <= 1 ? max(0, previousLength - safe.count) : 0
            output.write(prefix + safe + String(repeating: " ", count: padding))
            previousLength = safe.count
            previousRows = rows(for: safe)
        case .append:
            output.write(filtered + "\n")
        case .finalOnly:
            return
        }
    }

    public func final(_ text: String) {
        guard !disposed else {
            return
        }
        lastPartialText = nil
        let filtered = filterMarkerTokens(text)

        switch effectiveMode {
        case .overwrite:
            let safe = sanitizeForOverwrite(filtered)
            let prefix = overwritePrefix()
            let padding = previousRows <= 1 ? max(0, previousLength - safe.count) : 0
            output.write(prefix + safe + String(repeating: " ", count: padding) + "\n")
            previousLength = 0
            previousRows = 0
        case .append, .finalOnly:
            output.write(filtered + "\n")
        }
    }

    public func turnBoundary() {
        guard !disposed else {
            return
        }
        lastPartialText = nil
        output.write("\n")
    }

    public func refined(_ text: String) {
        guard !disposed else {
            return
        }
        let filtered = filterMarkerTokens(text)
        guard !filtered.isEmpty else {
            return
        }
        lastPartialText = nil
        if effectiveMode == .overwrite && previousLength > 0 {
            output.write("\n")
            previousLength = 0
            previousRows = 0
        }
        output.write(filtered + "\n\n")
    }

    public func dispose() {
        guard !disposed else {
            return
        }
        disposed = true
        lastPartialText = nil
        if effectiveMode == .overwrite {
            if previousLength > 0 {
                output.write("\n")
                previousLength = 0
                previousRows = 0
            }
            if isTTY {
                output.write("\u{001B}[2K\r")
            }
        }
    }

    private func overwritePrefix() -> String {
        guard previousRows > 1 else {
            return "\r"
        }

        let linesUp = previousRows - 1
        var sequence = "\u{001B}[\(linesUp)A\r"
        for row in 0..<previousRows {
            sequence += "\u{001B}[2K"
            if row < previousRows - 1 {
                sequence += "\u{001B}[1B\r"
            }
        }
        return sequence + "\u{001B}[\(linesUp)A\r"
    }

    private func rows(for text: String) -> Int {
        max(1, Int((Double(text.count) / Double(terminalColumns)).rounded(.up)))
    }
}

private func sanitizeForOverwrite(_ text: String) -> String {
    text.replacingOccurrences(of: #"\r\n|\r|\n"#, with: " ", options: .regularExpression)
}

private func filterMarkerTokens(_ text: String) -> String {
    text
        .replacingOccurrences(of: "<end>", with: "")
        .replacingOccurrences(of: "<fin>", with: "")
        .trimmingCharacters(in: .whitespacesAndNewlines)
}
