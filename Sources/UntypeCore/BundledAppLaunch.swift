import Foundation

public enum BundledAppLaunch {
    public static func shouldLaunchUI(arguments: [String], bundleURL: URL?) -> Bool {
        if arguments.first == "ui" {
            return true
        }
        guard bundleURL?.pathExtension == "app" else {
            return false
        }
        if arguments.isEmpty {
            return true
        }
        return arguments.allSatisfy { $0.hasPrefix("-psn_") }
    }
}
