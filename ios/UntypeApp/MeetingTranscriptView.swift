import SwiftUI
import UntypeCore

/// The lines of a meeting. While it is being recorded (`live`), the view
/// follows the newest line; scrolling by hand stops following so the text
/// can be read freely, and "Follow live" goes back to the newest line.
struct MeetingTranscriptView: View {
    let segments: [MeetingSegment]
    var inProgress: String = ""
    var live = false
    @Binding var follow: Bool

    private static let bottom = "bottom"

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                        MeetingLineView(segment: segment)
                    }
                    if live, !inProgress.isEmpty {
                        Text(inProgress)
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    Color.clear
                        .frame(height: 1)
                        .id(Self.bottom)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            // A drag by the user means reading: stop following.
            .simultaneousGesture(DragGesture(minimumDistance: 8).onChanged { _ in
                if live, follow {
                    follow = false
                }
            })
            .onChange(of: segments.count) { _, _ in
                scrollIfFollowing(proxy)
            }
            .onChange(of: inProgress) { _, _ in
                scrollIfFollowing(proxy)
            }
            .onChange(of: follow) { _, following in
                if following {
                    withAnimation(.easeOut(duration: 0.25)) {
                        proxy.scrollTo(Self.bottom, anchor: .bottom)
                    }
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if live, !follow {
                    Button {
                        follow = true
                    } label: {
                        Label("Follow live", systemImage: "arrow.down.to.line")
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(.thinMaterial, in: Capsule())
                    }
                    .padding(16)
                    .transition(.opacity)
                }
            }
        }
    }

    private func scrollIfFollowing(_ proxy: ScrollViewProxy) {
        guard live, follow else {
            return
        }
        proxy.scrollTo(Self.bottom, anchor: .bottom)
    }
}

/// One line: time and speaker above, the words below.
struct MeetingLineView: View {
    let segment: MeetingSegment

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(MeetingTranscriptFormat.speakerLabel(segment))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Self.color(for: segment.speaker))
                Text(MeetingTranscriptFormat.timestamp(segment.startMs))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.tertiary)
                if let language = segment.language {
                    Text(language)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            Text(segment.text)
                .font(.body)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private static let palette: [Color] = [.blue, .orange, .green, .purple, .pink, .teal, .indigo, .brown]

    static func color(for speaker: String?) -> Color {
        guard let speaker else {
            return .secondary
        }
        let digits = speaker.filter(\.isNumber)
        let number = Int(digits) ?? abs(speaker.hashValue)
        return palette[(max(1, number) - 1) % palette.count]
    }
}
