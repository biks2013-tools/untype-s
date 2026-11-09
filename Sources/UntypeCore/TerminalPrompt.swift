import AppKit
import ApplicationServices
import Foundation

/// The prompt box of a terminal coding agent such as Claude Code: the lines
/// starting with `❯` between two horizontal rules (`────`) near the bottom of
/// the screen. Terminals expose only the screen text through Accessibility,
/// so Push-to-Act reads the prompt from it when nothing is selected.
public enum TerminalPromptParser {
    /// The text in the last prompt box of `screen`, or nil when there is no
    /// prompt box or it is empty. Lines the terminal wrapped are joined with
    /// a space, lines the user broke with a newline.
    public static func prompt(in screen: String) -> String? {
        let lines = screen.components(separatedBy: "\n")
        var bottom = lines.count - 1
        while bottom > 0 {
            guard isRule(lines[bottom]) else {
                bottom -= 1
                continue
            }
            var top = bottom - 1
            while top >= 0, !isRule(lines[top]) {
                top -= 1
            }
            guard top >= 0 else {
                return nil
            }
            let content = Array(lines[(top + 1)..<bottom])
            if let first = content.first, first.hasPrefix("❯") {
                return text(content, width: lines[top].count)
            }
            bottom = top
        }
        return nil
    }

    /// A horizontal rule, possibly with a label in it
    /// (`──────── project-name ─`).
    private static func isRule(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return trimmed.count >= 10
            && trimmed.hasPrefix(String(repeating: "─", count: 10))
            && trimmed.hasSuffix("─")
    }

    private static func text(_ content: [String], width: Int) -> String? {
        let available = width - 2
        var pieces: [String] = []
        for (index, raw) in content.enumerated() {
            var line = Substring(raw)
            if index == 0 {
                line = line.dropFirst() // ❯
                // Claude Code puts a no-break space after the ❯.
                if line.first == " " || line.first == "\u{00A0}" {
                    line = line.dropFirst()
                }
            } else {
                var dropped = 0
                while dropped < 2, line.first == " " {
                    line = line.dropFirst()
                    dropped += 1
                }
            }
            pieces.append(String(line).replacingOccurrences(of: "\\s+$", with: "", options: .regularExpression))
        }
        var result = pieces.first ?? ""
        for index in pieces.indices.dropFirst() {
            let previous = pieces[index - 1]
            let next = pieces[index]
            let firstWord = next.split(separator: " ", maxSplits: 1).first.map(String.init) ?? ""
            // The terminal wraps a line when the next word does not fit.
            let wrapped = !previous.isEmpty && !firstWord.isEmpty
                && previous.count + 1 + firstWord.count > available
            result += (wrapped ? " " : "\n") + next
        }
        let trimmed = result.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

/// A terminal prompt read by Push-to-Act: the terminal's text area (to check
/// the prompt again) and the prompt text.
final class TerminalPromptAnchor: @unchecked Sendable {
    private let element: AXUIElement
    let text: String

    init(element: AXUIElement, text: String) {
        self.element = element
        self.text = text
    }

    /// The prompt now on screen; nil when the prompt box is empty or gone.
    func currentPrompt() -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &value) == .success,
              let screen = value as? String
        else {
            return nil
        }
        return TerminalPromptParser.prompt(in: screen)
    }
}
