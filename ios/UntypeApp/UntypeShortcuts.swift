import AppIntents

/// The phrases of the "Record meeting" shortcut (app only).
struct UntypeShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: RecordMeetingIntent(),
            phrases: [
                "Record a meeting with \(.applicationName)",
                "Start a meeting in \(.applicationName)",
                "\(.applicationName) record meeting"
            ],
            shortTitle: "Record meeting",
            systemImageName: "record.circle"
        )
    }
}
