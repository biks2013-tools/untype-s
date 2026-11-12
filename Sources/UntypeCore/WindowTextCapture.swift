import AppKit
import ApplicationServices
import Foundation

/// The text of the active app's window (the Window text operator),
/// including what is scrolled out of view.
public struct WindowText: Sendable, Equatable {
    public let text: String
    /// The app the window belongs to, named in the prompt.
    public let appName: String
    /// Whether the window held more text than `WindowTextCollector.maxCharacters`.
    public let truncated: Bool

    public init(text: String, appName: String, truncated: Bool = false) {
        self.text = text
        self.appName = appName
        self.truncated = truncated
    }
}

/// One element of a window's Accessibility tree, as far as the text
/// collection needs it.
public struct WindowTextNode: Sendable, Equatable {
    public var role: String
    public var subrole: String?
    public var value: String?
    public var children: [WindowTextNode]

    public init(role: String, subrole: String? = nil, value: String? = nil, children: [WindowTextNode] = []) {
        self.role = role
        self.subrole = subrole
        self.value = value
        self.children = children
    }
}

/// Turns a window's Accessibility tree into its text: the values of its
/// text elements in reading order, one per line. Pure.
public enum WindowTextCollector {
    /// Longest text sent (characters); the rest of the window is dropped.
    public static let maxCharacters = 30_000

    /// Roles whose value is text shown in the window.
    static let textRoles: Set<String> = ["AXStaticText", "AXTextArea", "AXTextField", "AXComboBox", "AXHeading"]
    /// Subtrees that are chrome, not content.
    static let skippedRoles: Set<String> = ["AXMenuBar", "AXMenu", "AXToolbar", "AXScrollBar"]

    public static func text(of root: WindowTextNode, maxCharacters: Int = maxCharacters) -> (text: String, truncated: Bool) {
        var lines: [String] = []
        var count = 0
        var truncated = false
        collect(root, into: &lines, count: &count, truncated: &truncated, limit: maxCharacters)
        return (lines.joined(separator: "\n"), truncated)
    }

    /// Whether the collection goes into `role`'s children.
    static func descends(role: String, subrole: String?, hasText: Bool) -> Bool {
        if skippedRoles.contains(role) || subrole == "AXSecureTextField" {
            return false
        }
        // A text element's children repeat its value (web views).
        return !(hasText && textRoles.contains(role))
    }

    /// The text `role` contributes itself, cleaned; nil for none.
    static func ownText(role: String, subrole: String?, value: String?) -> String? {
        guard textRoles.contains(role), subrole != "AXSecureTextField", let value else {
            return nil
        }
        let cleaned = value
            .replacingOccurrences(of: "\u{FFFC}", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? nil : cleaned
    }

    /// Adds `piece` unless it repeats the previous line; false once the
    /// limit is reached.
    static func append(_ piece: String, to lines: inout [String], count: inout Int, truncated: inout Bool, limit: Int) -> Bool {
        if lines.last == piece {
            return true
        }
        let room = limit - count
        guard room > 0 else {
            truncated = true
            return false
        }
        if piece.count > room {
            lines.append(String(piece.prefix(room)))
            count = limit
            truncated = true
            return false
        }
        lines.append(piece)
        count += piece.count + 1
        return true
    }

    private static func collect(_ node: WindowTextNode, into lines: inout [String], count: inout Int, truncated: inout Bool, limit: Int) {
        guard !truncated else {
            return
        }
        let own = ownText(role: node.role, subrole: node.subrole, value: node.value)
        if let own, !append(own, to: &lines, count: &count, truncated: &truncated, limit: limit) {
            return
        }
        guard descends(role: node.role, subrole: node.subrole, hasText: own != nil) else {
            return
        }
        for child in node.children {
            collect(child, into: &lines, count: &count, truncated: &truncated, limit: limit)
        }
    }
}

public struct WindowTextError: Error, Sendable, Equatable, LocalizedError {
    public let message: String

    public init(_ message: String) {
        self.message = message
    }

    public var errorDescription: String? {
        message
    }
}

/// Reads the text of an app's front window through Accessibility. Read
/// only; safe off the main thread. Needs the Accessibility permission.
public enum WindowTextCapture {
    /// Elements visited at most, and seconds spent at most, in one window.
    static let maxElements = 20_000
    static let timeBudget: TimeInterval = 2.0
    static let maxDepth = 80

    public static func capture(pid: pid_t, appName: String) throws -> WindowText {
        guard AXIsProcessTrusted() else {
            throw WindowTextError("Accessibility permission is missing: allow untype in System Settings → Privacy & Security → Accessibility.")
        }
        let application = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(application, 0.5)
        guard let window = frontWindow(of: application) else {
            throw WindowTextError("\(appName) has no window to read.")
        }
        var lines: [String] = []
        var count = 0
        var truncated = false
        var visited = 0
        let deadline = Date().addingTimeInterval(timeBudget)
        walk(window, depth: 0, lines: &lines, count: &count, truncated: &truncated, visited: &visited, deadline: deadline)
        let text = lines.joined(separator: "\n")
        guard !text.isEmpty else {
            throw WindowTextError("The window of \(appName) reports no text through Accessibility.")
        }
        return WindowText(text: text, appName: appName, truncated: truncated)
    }

    private static func frontWindow(of application: AXUIElement) -> AXUIElement? {
        for name in [kAXFocusedWindowAttribute, kAXMainWindowAttribute] {
            if let value = attribute(application, name as String), CFGetTypeID(value) == AXUIElementGetTypeID() {
                return (value as! AXUIElement)
            }
        }
        return (attribute(application, kAXWindowsAttribute as String) as? [AXUIElement])?.first
    }

    private static func walk(
        _ element: AXUIElement,
        depth: Int,
        lines: inout [String],
        count: inout Int,
        truncated: inout Bool,
        visited: inout Int,
        deadline: Date
    ) {
        guard !truncated else {
            return
        }
        visited += 1
        guard visited <= maxElements, depth <= maxDepth, Date() < deadline else {
            truncated = true
            return
        }
        let role = attribute(element, kAXRoleAttribute as String) as? String ?? ""
        let subrole = attribute(element, kAXSubroleAttribute as String) as? String
        let value = WindowTextCollector.textRoles.contains(role)
            ? attribute(element, kAXValueAttribute as String) as? String
            : nil
        let own = WindowTextCollector.ownText(role: role, subrole: subrole, value: value)
        if let own, !WindowTextCollector.append(own, to: &lines, count: &count, truncated: &truncated, limit: WindowTextCollector.maxCharacters) {
            return
        }
        guard WindowTextCollector.descends(role: role, subrole: subrole, hasText: own != nil),
              let children = attribute(element, kAXChildrenAttribute as String) as? [AXUIElement]
        else {
            return
        }
        for child in children {
            walk(child, depth: depth + 1, lines: &lines, count: &count, truncated: &truncated, visited: &visited, deadline: deadline)
        }
    }

    private static func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value : nil
    }
}
