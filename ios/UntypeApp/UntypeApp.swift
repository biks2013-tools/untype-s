import SwiftUI

@main
struct UntypeApp: App {
    @StateObject private var settings = AppSettings()
    @StateObject private var engine = DictationEngine()

    init() {
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
            DictateView()
                .environmentObject(settings)
                .environmentObject(engine)
                #if DEBUG && targetEnvironment(simulator)
                // Simulator runs only: `UNTYPE_TEST_DICTATE_SECONDS=8` starts
                // a dictation at launch and finishes it after that long.
                .task {
                    guard let seconds = ProcessInfo.processInfo.environment["UNTYPE_TEST_DICTATE_SECONDS"].flatMap(Double.init) else {
                        return
                    }
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                    engine.toggle(settings: settings)
                    try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                    engine.toggle(settings: settings)
                }
                #endif
        }
    }
}
