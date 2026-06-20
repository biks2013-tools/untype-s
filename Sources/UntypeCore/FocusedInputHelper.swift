import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

public enum FocusedInputHelperExitCode: Int32, Sendable {
    case success = 0
    case internalFailure = 1
    case expectedFailure = 2
}

public struct FocusedInputHelperRunResult: Equatable, Sendable {
    public let result: FocusedInputDeliveryResult
    public let exitCode: FocusedInputHelperExitCode

    public init(result: FocusedInputDeliveryResult, exitCode: FocusedInputHelperExitCode) {
        self.result = result
        self.exitCode = exitCode
    }
}

public struct FocusedInputHelperCommand: Equatable, Sendable {
    public let command: String
    public let method: FocusedInputDeliveryMethod

    public init(command: String, method: FocusedInputDeliveryMethod) {
        self.command = command
        self.method = method
    }
}

public enum FocusedInputHelperMain {
    public static let helperName = "untype-input-helper"
    private static let unicodeAutoThreshold = 500
    private static let hotkeySettleDelaySeconds: TimeInterval = 0.10
    private static let unicodeInterCharacterDelaySeconds: TimeInterval = 0.006
    private static let unicodePostDeliveryDelaySeconds: TimeInterval = 0.20
    private static let pasteboardRestoreDelaySeconds: TimeInterval = 0.80

    public static func run(arguments: [String], inputData: Data) -> FocusedInputHelperRunResult {
        do {
            let parsed = try parseCommand(arguments)
            switch parsed.command {
            case "diagnose":
                return FocusedInputHelperRunResult(result: diagnose(), exitCode: .success)
            case "send":
                let text = String(data: inputData, encoding: .utf8) ?? ""
                let result = try deliver(text: text, method: parsed.method)
                return FocusedInputHelperRunResult(result: result, exitCode: .success)
            default:
                throw FocusedInputDeliveryError(
                    message: "Usage: \(helperName) diagnose | send --method auto|ax-value|unicode-events|paste-keycode",
                    code: "invalid_command"
                )
            }
        } catch let error as FocusedInputDeliveryError {
            return FocusedInputHelperRunResult(
                result: .failure(code: error.code ?? "focused_input_helper_failed", message: error.message),
                exitCode: .expectedFailure
            )
        } catch {
            return FocusedInputHelperRunResult(
                result: .failure(code: "internal_error", message: "Unexpected focused input helper failure."),
                exitCode: .internalFailure
            )
        }
    }

    public static func parseCommand(_ args: [String]) throws -> FocusedInputHelperCommand {
        guard let command = args.first else {
            throw FocusedInputDeliveryError(
                message: "Usage: \(helperName) diagnose | send --method auto|ax-value|unicode-events|paste-keycode",
                code: "invalid_command"
            )
        }
        if command == "diagnose" {
            guard args.count == 1 else {
                throw FocusedInputDeliveryError(message: "diagnose does not accept arguments.", code: "invalid_command")
            }
            return FocusedInputHelperCommand(command: command, method: .auto)
        }
        guard command == "send" else {
            throw FocusedInputDeliveryError(message: "Unknown helper command: \(command).", code: "invalid_command")
        }

        var method = FocusedInputDeliveryMethod.auto
        var index = 1
        while index < args.count {
            let arg = args[index]
            if arg == "--method" {
                guard index + 1 < args.count else {
                    throw FocusedInputDeliveryError(message: "--method requires a value.", code: "invalid_method")
                }
                guard let parsedMethod = FocusedInputDeliveryMethod(rawValue: args[index + 1]) else {
                    throw FocusedInputDeliveryError(
                        message: "Unsupported focused input method: \(args[index + 1]).",
                        code: "invalid_method"
                    )
                }
                method = parsedMethod
                index += 2
            } else {
                throw FocusedInputDeliveryError(message: "Unknown send argument: \(arg).", code: "invalid_command")
            }
        }
        return FocusedInputHelperCommand(command: command, method: method)
    }

    public static func encodeResult(_ result: FocusedInputDeliveryResult) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard
            let data = try? encoder.encode(result),
            let json = String(data: data, encoding: .utf8)
        else {
            return "{\"code\":\"internal_error\",\"message\":\"Could not encode helper result.\",\"ok\":false}"
        }
        return json
    }

    private static func deliver(text: String, method: FocusedInputDeliveryMethod) throws -> FocusedInputDeliveryResult {
        switch method {
        case .auto:
            return try deliverAuto(text)
        case .axValue:
            return try axInsert(text)
        case .unicodeEvents:
            return try unicodeType(text)
        case .pasteKeycode:
            return try pasteWithKeyCode(text)
        }
    }

    private static func deliverAuto(_ text: String) throws -> FocusedInputDeliveryResult {
        Thread.sleep(forTimeInterval: hotkeySettleDelaySeconds)
        try requireAccessibility()

        if let element = try? focusedElement(), isBrowserTarget(element) {
            fputs("browser focused element detected; trying paste-keycode.\n", stderr)
            do {
                return try pasteWithKeyCode(text)
            } catch {
                fputs("paste-keycode unavailable; trying unicode-events.\n", stderr)
            }

            if text.utf16.count <= unicodeAutoThreshold {
                return try unicodeType(text)
            }

            throw FocusedInputDeliveryError(
                message: "paste-keycode failed and unicode-events was skipped for long browser text.",
                code: "focused_input_delivery_failed"
            )
        }

        do {
            return try axInsert(text)
        } catch let error as FocusedInputDeliveryError where error.code == "accessibility_not_trusted" {
            throw error
        } catch {
            fputs("ax-value unavailable; trying paste-keycode.\n", stderr)
        }

        do {
            return try pasteWithKeyCode(text)
        } catch {
            fputs("paste-keycode unavailable; trying unicode-events.\n", stderr)
        }

        if text.utf16.count <= unicodeAutoThreshold {
            return try unicodeType(text)
        }

        throw FocusedInputDeliveryError(
            message: "paste-keycode failed and unicode-events was skipped for long text.",
            code: "focused_input_delivery_failed"
        )
    }

    private static func accessibilityTrusted(prompt: Bool = false) -> Bool {
        let options = ["AXTrustedCheckOptionPrompt": prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    private static func requireAccessibility() throws {
        guard accessibilityTrusted() else {
            throw FocusedInputDeliveryError(
                message: "Grant Accessibility permission to \(accessibilityPermissionTargetName()).",
                code: "accessibility_not_trusted"
            )
        }
    }

    private static func accessibilityPermissionTargetName() -> String {
        let bundleURL = Bundle.main.bundleURL.standardizedFileURL
        if bundleURL.pathExtension == "app" {
            return bundleURL.deletingPathExtension().lastPathComponent
        }
        if let executable = Bundle.main.executableURL?.lastPathComponent, !executable.isEmpty {
            return executable
        }
        if let command = CommandLine.arguments.first {
            let name = URL(fileURLWithPath: command).lastPathComponent
            if !name.isEmpty {
                return name
            }
        }
        return helperName
    }

    private static func diagnose() -> FocusedInputDeliveryResult {
        let trusted = accessibilityTrusted()
        let pasteboardAvailable = true

        guard trusted else {
            return FocusedInputDeliveryResult(
                ok: true,
                accessibilityTrusted: false,
                pasteboardAvailable: pasteboardAvailable
            )
        }

        do {
            let element = try focusedElement()
            return FocusedInputDeliveryResult(
                ok: true,
                targetRole: attributeString(element, kAXRoleAttribute),
                targetSubrole: attributeString(element, kAXSubroleAttribute),
                accessibilityTrusted: true,
                focusedElementAvailable: true,
                axValueReadable: attributeString(element, kAXValueAttribute) != nil,
                axValueSettable: isSettable(element, kAXValueAttribute),
                axSelectedTextRangeReadable: selectedRange(element) != nil,
                axSelectedTextRangeSettable: isSettable(element, kAXSelectedTextRangeAttribute),
                axSelectedTextSettable: isSettable(element, kAXSelectedTextAttribute),
                pasteboardAvailable: pasteboardAvailable
            )
        } catch {
            return FocusedInputDeliveryResult(
                ok: true,
                accessibilityTrusted: true,
                focusedElementAvailable: false,
                pasteboardAvailable: pasteboardAvailable
            )
        }
    }

    private static func focusedElement() throws -> AXUIElement {
        let system = AXUIElementCreateSystemWide()
        var raw: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &raw)
        guard error == .success, let element = raw else {
            throw FocusedInputDeliveryError(
                message: "Could not read the focused UI element.",
                code: "focused_element_unavailable"
            )
        }
        return element as! AXUIElement
    }

    private static func axInsert(_ text: String) throws -> FocusedInputDeliveryResult {
        try requireAccessibility()
        let element = try focusedElement()
        let role = attributeString(element, kAXRoleAttribute)
        let subrole = attributeString(element, kAXSubroleAttribute)

        // Formatting-safe caret insertion via AXSelectedText. This replaces the current
        // selection (or inserts at the caret when the selection is empty) by routing
        // through the control's insertText: implementation, so the inserted run adopts the
        // surrounding typing attributes and the rest of the document is left untouched.
        //
        // We deliberately DO NOT fall back to rewriting the whole kAXValueAttribute: for a
        // rich-text field that exposes a settable AXValue (e.g. the Outlook email compose
        // body, which reports AXTextArea), writing the entire value back as a plain String
        // flattens the whole message to plain text and wipes all formatting — fonts,
        // bold/italic, colors, signatures. Instead, when AXSelectedText is unavailable we
        // throw so auto-delivery falls through to paste-keycode / unicode typing, both of
        // which insert at the caret without destroying surrounding formatting.
        // See "Issues - Pending Items.md".
        guard isSettable(element, kAXSelectedTextAttribute) else {
            throw FocusedInputDeliveryError(
                message: "Focused element does not support caret-safe AXSelectedText insertion.",
                code: "selected_text_not_settable"
            )
        }

        // Capture the value length before the insertion so we can confirm it actually
        // took effect. Some web/Electron-backed editors (notably the current Outlook
        // compose body) ACCEPT the AXSelectedText write and return success while
        // performing no insertion at all — leaving the message untouched.
        let beforeCount = attributeString(element, kAXValueAttribute)?.utf16.count

        let setSelectedError = AXUIElementSetAttributeValue(
            element,
            kAXSelectedTextAttribute as CFString,
            text as CFString
        )
        guard setSelectedError == .success else {
            throw FocusedInputDeliveryError(
                message: "Could not set AXSelectedText on the focused element.",
                code: "selected_text_not_settable"
            )
        }

        // Detect the silent no-op: when the value length is readable before and after
        // and an empty caret insertion left it unchanged, the control ignored the write.
        // Throw so auto-delivery falls through to a working method (paste-keycode /
        // unicode typing) instead of reporting a success that never happened. We only
        // treat an UNCHANGED length as a no-op; any length change means real text landed
        // (a replaced selection legitimately changes the length), so we never re-insert
        // and risk duplicating text.
        if !text.isEmpty,
           let before = beforeCount,
           let after = attributeString(element, kAXValueAttribute)?.utf16.count,
           after == before {
            throw FocusedInputDeliveryError(
                message: "AXSelectedText insertion was accepted but did not change the field.",
                code: "selected_text_noop"
            )
        }

        return .success(method: "ax-value", targetRole: role, targetSubrole: subrole)
    }

    private static func unicodeType(_ text: String) throws -> FocusedInputDeliveryResult {
        try requireAccessibility()
        guard let source = CGEventSource(stateID: .combinedSessionState) else {
            throw FocusedInputDeliveryError(
                message: "Could not create a keyboard event source.",
                code: "unicode_events_failed"
            )
        }

        for character in text {
            var units = Array(String(character).utf16)
            guard
                let down = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
                let up = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false)
            else {
                throw FocusedInputDeliveryError(
                    message: "Could not create Unicode keyboard events.",
                    code: "unicode_events_failed"
                )
            }
            down.flags = []
            up.flags = []
            down.keyboardSetUnicodeString(stringLength: units.count, unicodeString: &units)
            up.keyboardSetUnicodeString(stringLength: units.count, unicodeString: &units)
            down.post(tap: .cghidEventTap)
            up.post(tap: .cghidEventTap)
            Thread.sleep(forTimeInterval: unicodeInterCharacterDelaySeconds)
        }

        Thread.sleep(forTimeInterval: unicodePostDeliveryDelaySeconds)
        return .success(method: "unicode-events")
    }

    private static func pasteWithKeyCode(_ text: String) throws -> FocusedInputDeliveryResult {
        try requireAccessibility()
        let pasteboard = NSPasteboard.general
        let snapshot = PasteboardSnapshot(pasteboard)

        pasteboard.clearContents()
        guard pasteboard.setString(text, forType: .string) else {
            throw FocusedInputDeliveryError(
                message: "Could not write focused input text to pasteboard.",
                code: "pasteboard_unavailable"
            )
        }

        guard let source = CGEventSource(stateID: .combinedSessionState),
              let down = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false)
        else {
            _ = snapshot.restore(to: pasteboard)
            throw FocusedInputDeliveryError(
                message: "Could not create Command-V keyboard events.",
                code: "paste_keycode_failed"
            )
        }

        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)

        Thread.sleep(forTimeInterval: pasteboardRestoreDelaySeconds)
        let restored = snapshot.restore(to: pasteboard)
        return .success(method: "paste-keycode", clipboardRestored: restored)
    }

    private static func attributeString(_ element: AXUIElement, _ attribute: String) -> String? {
        var raw: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &raw) == .success else {
            return nil
        }
        return raw as? String
    }

    private static func isBrowserTarget(_ element: AXUIElement) -> Bool {
        var pid = pid_t()
        guard AXUIElementGetPid(element, &pid) == .success,
              let bundleIdentifier = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier
        else {
            return false
        }
        return isBrowserBundleIdentifier(bundleIdentifier)
    }

    public static func isBrowserBundleIdentifier(_ bundleIdentifier: String) -> Bool {
        let normalized = bundleIdentifier.lowercased()
        let exact: Set<String> = [
            "com.apple.safari",
            "com.apple.safaritechnologypreview",
            "com.google.chrome",
            "com.google.chrome.canary",
            "com.microsoft.edgemac",
            "com.microsoft.edgemac.canary",
            "org.mozilla.firefox",
            "org.mozilla.firefoxdeveloperedition",
            "com.brave.browser",
            "com.vivaldi.vivaldi",
            "com.operasoftware.opera",
            "com.operasoftware.operagx",
            "company.thebrowser.browser"
        ]
        if exact.contains(normalized) {
            return true
        }
        return normalized.contains("chromium")
            || normalized.contains("firefox")
            || normalized.contains("edgemac")
            || normalized.contains("brave")
            || normalized.contains("vivaldi")
    }

    private static func isSettable(_ element: AXUIElement, _ attribute: String) -> Bool {
        var settable = DarwinBoolean(false)
        let error = AXUIElementIsAttributeSettable(element, attribute as CFString, &settable)
        return error == .success && settable.boolValue
    }

    private static func selectedRange(_ element: AXUIElement) -> CFRange? {
        var raw: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &raw)
        guard error == .success, let value = raw, CFGetTypeID(value) == AXValueGetTypeID() else {
            return nil
        }
        let axValue = value as! AXValue
        var range = CFRange()
        guard AXValueGetType(axValue) == .cfRange, AXValueGetValue(axValue, .cfRange, &range) else {
            return nil
        }
        return range
    }
}

private final class PasteboardSnapshot {
    private let items: [[NSPasteboard.PasteboardType: Data]]

    init(_ pasteboard: NSPasteboard) {
        items = (pasteboard.pasteboardItems ?? []).map { item in
            var values: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) {
                    values[type] = data
                }
            }
            return values
        }
    }

    func restore(to pasteboard: NSPasteboard) -> Bool {
        pasteboard.clearContents()
        guard !items.isEmpty else {
            return true
        }
        let restoredItems = items.map { values in
            let item = NSPasteboardItem()
            for (type, data) in values {
                item.setData(data, forType: type)
            }
            return item
        }
        return pasteboard.writeObjects(restoredItems)
    }
}
