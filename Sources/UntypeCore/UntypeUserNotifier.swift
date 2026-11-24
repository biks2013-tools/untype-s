#if os(macOS)
import Foundation
@preconcurrency import UserNotifications

/// Posts macOS notifications (Notification Center banners). untype runs as a
/// menu-bar app, so a banner is the one place the user sees a problem with
/// the main window closed. macOS asks for permission the first time; if the
/// user declines, posting does nothing and the overlay notice and the
/// Transcript row still tell them.
final class UntypeUserNotifier: @unchecked Sendable {
    static let shared = UntypeUserNotifier()

    private let lock = NSLock()
    private var authorizationRequested = false

    /// UNUserNotificationCenter needs an app bundle; `swift run` and the
    /// tests have none, and touching the center there raises an exception.
    private var isAvailable: Bool {
        Bundle.main.bundleIdentifier != nil && Bundle.main.bundleURL.pathExtension == "app"
    }

    func post(title: String, body: String, identifier: String) {
        guard isAvailable else {
            return
        }
        let center = UNUserNotificationCenter.current()
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        // The same identifier replaces the banner still in Notification
        // Center instead of stacking copies of it.
        let request = UNNotificationRequest(identifier: "untype.\(identifier)", content: content, trigger: nil)
        lock.lock()
        let needsAuthorization = !authorizationRequested
        authorizationRequested = true
        lock.unlock()
        if needsAuthorization {
            center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
                if granted {
                    center.add(request)
                }
            }
        } else {
            center.add(request)
        }
    }
}
#endif
