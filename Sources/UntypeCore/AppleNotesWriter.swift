#if os(macOS)
import AppKit
import Carbon
import Foundation

/// Writes a note in Apple Notes (plan-076): the Notes app is asked through
/// Apple Events, which macOS lets untype do after the user allows it once
/// (System Settings → Privacy & Security → Automation → untype → Notes).
public enum AppleNotesWriter {
    /// The folder of Notes the meeting notes go to.
    public static let folderName = "untype"

    public struct Failure: LocalizedError, Equatable {
        public let message: String

        public var errorDescription: String? { message }
    }

    private static let source = """
    on makeNote(theFolder, theBody)
        tell application "Notes"
            if not (exists folder theFolder) then
                make new folder with properties {name:theFolder}
            end if
            make new note at folder theFolder with properties {body:theBody}
        end tell
    end makeNote
    """

    private static let queue = DispatchQueue(label: "untype.apple-notes")
    private static let lock = NSLock()

    /// Creates a note with `html` as its body in the folder `folderName`
    /// (made when missing). Off the main thread: Notes may have to start,
    /// and the first time macOS asks the user for permission.
    public static func createNote(html: String, folder: String = folderName) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async {
                continuation.resume(with: Result { _ = try call(source: source, handler: "makeNote", parameters: [folder, html]) })
            }
        }
    }

    /// Calls `handler` of the AppleScript `source` with text parameters and
    /// returns what it returns as text (nil when it is not text).
    @discardableResult
    static func call(source: String, handler: String, parameters: [String]) throws -> String? {
        // AppleScript is not made for two threads at once.
        lock.lock()
        defer { lock.unlock() }
        guard let script = NSAppleScript(source: source) else {
            throw Failure(message: "The script for Apple Notes could not be made.")
        }
        var error: NSDictionary?
        script.compileAndReturnError(&error)
        if let error {
            throw failure(error)
        }
        let list = NSAppleEventDescriptor.list()
        for (index, parameter) in parameters.enumerated() {
            list.insert(NSAppleEventDescriptor(string: parameter), at: index + 1)
        }
        let event = NSAppleEventDescriptor(
            eventClass: AEEventClass(kASAppleScriptSuite),
            eventID: AEEventID(kASSubroutineEvent),
            targetDescriptor: nil,
            returnID: AEReturnID(kAutoGenerateReturnID),
            transactionID: AETransactionID(kAnyTransactionID)
        )
        event.setParam(NSAppleEventDescriptor(string: handler.lowercased()), forKeyword: AEKeyword(keyASSubroutineName))
        event.setParam(list, forKeyword: keyDirectObject)
        let result = script.executeAppleEvent(event, error: &error)
        if let error {
            throw failure(error)
        }
        return result.stringValue
    }

    private static func failure(_ error: NSDictionary) -> Failure {
        let number = error[NSAppleScript.errorNumber] as? Int
        // errAEEventNotPermitted: the user said no, or has not been asked.
        if number == -1743 {
            return Failure(message: "untype is not allowed to use Notes. Allow it in System Settings → Privacy & Security → Automation → untype → Notes.")
        }
        let message = error[NSAppleScript.errorMessage] as? String ?? "unknown error"
        return Failure(message: "Apple Notes: \(message)\(number.map { " (\($0))" } ?? "")")
    }
}
#endif
