import Foundation

extension FileManager {
    /// The folder untype keeps its files under (`.tool-agents/untype/…`):
    /// the user's home folder on macOS; on iOS, where an app has no home
    /// folder of the user, the app's Application Support folder.
    public var untypeHomeDirectory: URL {
        #if os(macOS)
        return homeDirectoryForCurrentUser
        #else
        return URL.applicationSupportDirectory
        #endif
    }
}
