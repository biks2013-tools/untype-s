import SwiftUI
import UIKit

/// The main screen: the text, the microphone button, Refine / Translate,
/// and what to do with the text (copy, share, clear).
struct DictateView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var engine: DictationEngine
    @State private var showSettings = false
    @State private var copied = false
    @FocusState private var editing: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                textArea
                if let problem = engine.problem {
                    problemBanner(problem)
                }
                controls
            }
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
            .navigationTitle("untype")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Settings")
                    .disabled(engine.isBusy)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { editing = false }
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
                    .environmentObject(settings)
            }
        }
    }

    private var textArea: some View {
        ZStack(alignment: .topLeading) {
            TextEditor(text: $engine.text)
                .focused($editing)
                .font(.body)
                .scrollContentBackground(.hidden)
                .disabled(engine.isBusy)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            if engine.text.isEmpty {
                Text(settings.hasSonioxKey
                     ? "Tap the microphone and speak. Your words appear here."
                     : "Enter your Soniox key in Settings, then tap the microphone and speak.")
                    .font(.body)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 17)
                    .padding(.vertical, 16)
                    .allowsHitTesting(false)
            }
        }
        .frame(maxHeight: .infinity)
    }

    private func problemBanner(_ problem: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(problem)
                .font(.footnote)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                engine.problem = nil
            } label: {
                Image(systemName: "xmark")
                    .font(.footnote.weight(.semibold))
            }
            .accessibilityLabel("Dismiss")
        }
        .padding(12)
        .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    private var controls: some View {
        VStack(spacing: 14) {
            HStack(spacing: 10) {
                Toggle("Refine", isOn: $settings.refine)
                    .toggleStyle(.button)
                Toggle("Translate", isOn: $settings.translate)
                    .toggleStyle(.button)
                if settings.translate {
                    Picker("Translate to", selection: $settings.targetRaw) {
                        ForEach(TargetLanguage.allCases) { language in
                            Text("to \(language.rawValue)").tag(language.rawValue)
                        }
                    }
                    .pickerStyle(.menu)
                }
                Spacer(minLength: 0)
            }
            .disabled(engine.isBusy)

            Text(status)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
                .accessibilityAddTraits(.updatesFrequently)

            HStack {
                actionButton("Clear", systemImage: "trash") {
                    engine.clear()
                }
                .disabled(engine.isBusy || engine.text.isEmpty)
                Spacer()
                microphoneButton
                Spacer()
                if engine.beforeProcessing != nil {
                    actionButton("Undo", systemImage: "arrow.uturn.backward") {
                        engine.undoProcessing()
                    }
                    .disabled(engine.isBusy)
                } else {
                    ShareLink(item: engine.text) {
                        actionLabel("Share", systemImage: "square.and.arrow.up")
                    }
                    .disabled(engine.isBusy || engine.text.isEmpty)
                }
            }

            Button {
                UIPasteboard.general.string = engine.text
                copied = true
                Task {
                    try? await Task.sleep(nanoseconds: 1_500_000_000)
                    copied = false
                }
            } label: {
                Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(engine.isBusy || engine.text.isEmpty)
        }
        .padding(16)
        .background(.bar)
    }

    private var status: String {
        switch engine.phase {
        case .idle:
            return engine.text.isEmpty ? " " : "\(engine.text.count) characters"
        case .starting:
            return "Starting…"
        case .listening:
            return "Listening. Tap to finish."
        case .finishing:
            return "Finishing…"
        case .processing(let what):
            return what
        }
    }

    private var microphoneButton: some View {
        let listening = engine.phase == .listening
        let waiting = engine.isBusy && !listening
        return Button {
            editing = false
            engine.toggle(settings: settings)
        } label: {
            ZStack {
                Circle()
                    .fill(listening ? Color.red : Color.accentColor)
                    .frame(width: 76, height: 76)
                if waiting {
                    ProgressView()
                        .tint(.white)
                } else {
                    Image(systemName: listening ? "stop.fill" : "mic.fill")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }
        }
        .disabled(waiting)
        .accessibilityLabel(listening ? "Finish dictation" : "Start dictation")
    }

    private func actionButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            actionLabel(title, systemImage: systemImage)
        }
    }

    private func actionLabel(_ title: String, systemImage: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: systemImage)
                .font(.title3)
            Text(title)
                .font(.caption)
        }
        .frame(width: 64, height: 52)
    }
}
