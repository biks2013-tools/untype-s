import SwiftUI

@main
struct UntypeApp: App {
    @StateObject private var settings = AppSettings()
    @StateObject private var engine = DictationEngine()
    @StateObject private var meetings = MeetingSession.shared

    init() {
        // The "Record meeting" action (Siri, Shortcuts, Control Center).
        RecordMeetingIntent.start = {
            MeetingSession.shared.quickStartRequested = true
        }
        #if DEBUG && targetEnvironment(simulator)
        // Simulator runs only: keys given in the launch environment
        // (`SIMCTL_CHILD_SONIOX_API_KEY=… xcrun simctl launch …`) are stored,
        // so a test run needs no typing of keys.
        for provider in ModelProvider.allCases.map(\.keyName) + [AppSettings.sonioxKeyName] {
            if let value = ProcessInfo.processInfo.environment[provider], !value.isEmpty {
                try? KeychainStore.write(provider, value)
            }
        }
        #endif
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(settings)
                .environmentObject(engine)
                .environmentObject(meetings)
                #if DEBUG && targetEnvironment(simulator)
                // Simulator runs only: `UNTYPE_TEST_DICTATE_SECONDS=8` starts
                // a dictation at launch and finishes it after that long;
                // `UNTYPE_TEST_MEETING_SECONDS=20` records a meeting that long
                // (`UNTYPE_TEST_MEETING_TRANSCRIPT=0`: audio only).
                .task {
                    let environment = ProcessInfo.processInfo.environment
                    if let seconds = environment["UNTYPE_TEST_DICTATE_SECONDS"].flatMap(Double.init) {
                        try? await Task.sleep(nanoseconds: 1_000_000_000)
                        engine.toggle(settings: settings)
                        try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                        engine.toggle(settings: settings)
                    }
                    if let seconds = environment["UNTYPE_TEST_MEETING_SECONDS"].flatMap(Double.init) {
                        try? await Task.sleep(nanoseconds: 1_000_000_000)
                        await meetings.start(settings: settings, transcribe: environment["UNTYPE_TEST_MEETING_TRANSCRIPT"] != "0")
                        try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                        await meetings.stop()
                    }
                }
                #endif
        }
    }
}

/// Two tabs: Dictate and Meetings. A meeting being recorded covers the
/// whole screen.
struct RootView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var engine: DictationEngine
    @EnvironmentObject private var meetings: MeetingSession
    @SceneStorage("tab") private var tab = "dictate"

    var body: some View {
        TabView(selection: $tab) {
            DictateView()
                .tabItem { Label("Dictate", systemImage: "mic") }
                .tag("dictate")
            MeetingsView()
                .tabItem { Label("Meetings", systemImage: "person.2.wave.2") }
                .tag("meetings")
            VideosView()
                .tabItem { Label("Videos", systemImage: "play.rectangle") }
                .tag("videos")
        }
        .fullScreenCover(isPresented: Binding(
            get: { meetings.isActive },
            set: { _ in }
        )) {
            MeetingRecordingView()
                .environmentObject(settings)
                .environmentObject(meetings)
        }
        .onChange(of: meetings.lastSaved) { _, saved in
            if saved != nil {
                tab = "meetings"
            }
        }
        .onChange(of: meetings.quickStartRequested, initial: true) { _, requested in
            guard requested else {
                return
            }
            meetings.quickStartRequested = false
            tab = "meetings"
            guard !meetings.isActive, !engine.isBusy else {
                return
            }
            Task { await meetings.start(settings: settings, transcribe: settings.meetingTranscript) }
        }
    }
}
