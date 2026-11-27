import SwiftUI
import UntypeCore

/// Full screen while a meeting is recorded: how long, whether sound comes
/// in, the transcript switch, the live transcript and Stop.
struct MeetingRecordingView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var session: MeetingSession
    @State private var follow = true

    var body: some View {
        VStack(spacing: 0) {
            header
            if let problem = session.problem {
                ProblemBanner(problem: problem) { session.problem = nil }
            }
            transcriptArea
            stopBar
        }
        .background(Color(.systemBackground))
    }

    private var header: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Circle()
                    .fill(session.interrupted ? Color.orange : Color.red)
                    .frame(width: 10, height: 10)
                    .opacity(session.phase == .recording && !session.interrupted ? 1 : 0.5)
                Text(statusText)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(session.interrupted ? .orange : .red)
            }
            Text(Self.clock(session.elapsed))
                .font(.system(size: 52, weight: .light, design: .rounded).monospacedDigit())
            LevelBar(level: session.level)
                .frame(height: 6)
                .padding(.horizontal, 60)
            Toggle(isOn: Binding(
                get: { session.transcribing },
                set: { on in
                    settings.meetingTranscript = on
                    Task { await session.setTranscript(on, settings: settings) }
                }
            )) {
                Label("Live transcript", systemImage: "text.bubble")
            }
            .disabled(session.phase != .recording || session.transcriptBusy)
            .padding(.horizontal, 24)
            .padding(.top, 4)
        }
        .padding(.top, 24)
        .padding(.bottom, 12)
    }

    @ViewBuilder
    private var transcriptArea: some View {
        if session.segments.isEmpty, session.inProgress.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: session.transcribing ? "waveform" : "mic")
                    .font(.largeTitle)
                    .foregroundStyle(.tertiary)
                Text(session.transcribing
                     ? (session.transcriptBusy ? "Connecting…" : "Listening. The words appear here.")
                     : "Recording audio only. Switch on the live transcript to read along.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(32)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            MeetingTranscriptView(
                segments: session.segments,
                inProgress: session.inProgress,
                live: true,
                follow: $follow
            )
            .frame(maxHeight: .infinity)
        }
    }

    private var stopBar: some View {
        Button {
            Task { await session.stop() }
        } label: {
            HStack(spacing: 10) {
                if session.phase == .saving {
                    ProgressView().tint(.white)
                    Text("Saving…")
                } else {
                    Image(systemName: "stop.fill")
                    Text("Stop and save")
                }
            }
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .foregroundStyle(.white)
            .background(Color.red, in: RoundedRectangle(cornerRadius: 16))
        }
        .disabled(session.phase != .recording)
        .padding(16)
        .background(.bar)
    }

    private var statusText: String {
        switch session.phase {
        case .starting: return "Starting…"
        case .saving: return "Saving…"
        case .idle, .recording:
            return session.interrupted ? "Paused by a call" : "Recording"
        }
    }

    static func clock(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        return total >= 3600
            ? String(format: "%d:%02d:%02d", total / 3600, total / 60 % 60, total % 60)
            : String(format: "%02d:%02d", total / 60, total % 60)
    }
}

/// How loud the microphone is, as a bar.
private struct LevelBar: View {
    let level: Double

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.secondary.opacity(0.2))
                Capsule()
                    .fill(Color.green)
                    .frame(width: geometry.size.width * CGFloat(min(1, sqrt(level))))
                    .animation(.linear(duration: 0.1), value: level)
            }
        }
        .accessibilityHidden(true)
    }
}

struct ProblemBanner: View {
    let problem: String
    let dismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(problem)
                .font(.footnote)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: dismiss) {
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
}
