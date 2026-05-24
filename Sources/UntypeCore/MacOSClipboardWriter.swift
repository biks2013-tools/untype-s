import AppKit
import Foundation

public struct MacOSClipboardWriter {
    private let writeString: (String) throws -> Void

    public init(writeString: @escaping (String) throws -> Void = MacOSClipboardWriter.writeToSystemPasteboard) {
        self.writeString = writeString
    }

    public func copy(_ text: String) async throws {
        try writeString(text)
    }

    public static func writeToSystemPasteboard(_ text: String) throws {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        guard pasteboard.setString(text, forType: .string) else {
            throw FocusedInputDeliveryError(
                message: "Could not write text to the macOS pasteboard.",
                code: "clipboard_unavailable"
            )
        }
    }
}
