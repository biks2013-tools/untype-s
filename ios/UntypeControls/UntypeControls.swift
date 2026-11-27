import AppIntents
import SwiftUI
import WidgetKit

/// untype's controls for Control Center, the Lock Screen and the Action
/// button (iOS 18+).
@main
struct UntypeControls: WidgetBundle {
    var body: some Widget {
        RecordMeetingControl()
    }
}

/// One tap: untype opens and records a meeting.
struct RecordMeetingControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.biks2013.untype.record-meeting") {
            ControlWidgetButton(action: RecordMeetingIntent()) {
                Label("Record meeting", systemImage: "record.circle")
            }
        }
        .displayName("Record meeting")
        .description("Opens untype and starts recording a meeting.")
    }
}
