import AppKit
import SwiftUI

/// Which side of the meeting the transcription window shows.
public enum TranscriptionChannel: String, CaseIterable, Sendable {
    case both
    case microphone
    case system

    public var title: String {
        switch self {
        case .both: return "Both"
        case .microphone: return "Microphone"
        case .system: return "System"
        }
    }

    public func includes(_ side: MeetingSide) -> Bool {
        switch self {
        case .both: return true
        case .microphone: return side == .you
        case .system: return side == .call
        }
    }
}

/// One line of the transcription window.
public struct TranscriptionLine: Identifiable, Equatable, Sendable {
    public let id: Int
    public let segment: MeetingSegment
}

/// The live transcript of the meeting being recorded (kept after it ends,
/// until the next one starts), for the transcription window. Finished
/// segments are only ever added at the end; the words still being spoken
/// are held per side and replaced as they change.
@MainActor
public final class MeetingTranscriptFeed: ObservableObject {
    @Published public private(set) var lines: [TranscriptionLine] = []
    /// The words of the sentence being spoken on each side.
    @Published public private(set) var inProgress: [MeetingSide: String] = [:]
    @Published public private(set) var isRecording = false
    /// The name of the meeting folder (empty before the first recording).
    @Published public private(set) var meetingName = ""
    /// Lines before this id were cleared from the window (they are still in
    /// the meeting's files).
    @Published public private(set) var clearedBefore = 0

    public init() {}

    /// Empties the window: the lines shown so far are no longer shown. The
    /// recording and its files are not touched; new text keeps coming.
    public func clear() {
        clearedBefore = lines.count
    }

    /// A new recording: the previous transcript goes.
    public func begin(meetingName: String) {
        lines = []
        clearedBefore = 0
        inProgress = [:]
        self.meetingName = meetingName
        isRecording = true
    }

    /// The meeting folder's name, known once the recording runs.
    public func setMeetingName(_ name: String) {
        meetingName = name
    }

    public func add(_ segment: MeetingSegment) {
        lines.append(TranscriptionLine(id: lines.count, segment: segment))
        // The sentence is finished: its words are in the line now.
        inProgress[segment.side] = nil
    }

    public func setInProgress(_ text: String, side: MeetingSide) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let next = trimmed.isEmpty ? nil : trimmed
        if inProgress[side] != next {
            inProgress[side] = next
        }
    }

    public func end() {
        inProgress = [:]
        isRecording = false
    }

    /// The finished lines of `channel` that the window shows (those added
    /// since the last clear), in the order they arrived.
    public func lines(for channel: TranscriptionChannel) -> [TranscriptionLine] {
        let shown = lines.dropFirst(clearedBefore)
        return channel == .both ? Array(shown) : shown.filter { channel.includes($0.segment.side) }
    }

    /// What has been transcribed so far on `channel`, one finished sentence
    /// per line (`[00:00:07] Speaker 1: text`), for copying.
    public func text(for channel: TranscriptionChannel) -> String {
        lines(for: channel)
            .map { MeetingTranscriptFormat.englishLine($0.segment) }
            .joined(separator: "\n")
    }

    /// The sides of `channel` that have words in progress, microphone first.
    public func inProgressSides(for channel: TranscriptionChannel) -> [MeetingSide] {
        [MeetingSide.you, .call].filter { channel.includes($0) && inProgress[$0] != nil }
    }
}

/// The transcription window: the transcript of the meeting being recorded,
/// live. Opened from the menu-bar dropdown ("Transcription window", ⌘3).
@MainActor
final class UntypeTranscriptionWindowController: NSObject {
    private static let frameAutosaveName = "untype.transcriptionWindow.v1"
    private let feed: MeetingTranscriptFeed
    private var window: NSWindow?

    init(feed: MeetingTranscriptFeed) {
        self.feed = feed
    }

    func show() {
        let window = self.window ?? makeWindow()
        self.window = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 540, height: 620),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Transcription"
        window.contentMinSize = NSSize(width: 500, height: 260)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: UntypeTranscriptionView(feed: feed))
        if !window.setFrameUsingName(Self.frameAutosaveName) {
            window.center()
        }
        window.setFrameAutosaveName(Self.frameAutosaveName)
        return window
    }
}

struct UntypeTranscriptionView: View {
    private static let bottomID = "transcription-bottom"

    @ObservedObject var feed: MeetingTranscriptFeed
    /// `TranscriptionChannel` raw value.
    @AppStorage("untype.transcriptionWindow.channel") private var channelValue = TranscriptionChannel.both.rawValue
    /// In sync: the window follows the recording, the newest text in view.
    /// Out of sync: it stays where the user scrolled, text is still added
    /// at the end.
    @AppStorage("untype.transcriptionWindow.follow") private var follow = true
    /// Just copied: the button says so for a moment.
    @State private var copied = false

    private var channel: TranscriptionChannel {
        TranscriptionChannel(rawValue: channelValue) ?? .both
    }

    var body: some View {
        VStack(spacing: 0) {
            controls
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            Divider()
            transcript
            Divider()
            status
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
        }
        .frame(minWidth: 500, minHeight: 260)
    }

    private var controls: some View {
        HStack(spacing: 10) {
            Picker("Channel", selection: $channelValue) {
                ForEach(TranscriptionChannel.allCases, id: \.rawValue) { channel in
                    Text(channel.title).tag(channel.rawValue)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .help("Show what the microphone heard, what the system played (the call), or both")
            Spacer(minLength: 8)
            Button {
                copyTranscript()
            } label: {
                Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
            }
            .labelStyle(.iconOnly)
            .controlSize(.small)
            .disabled(feed.lines(for: channel).isEmpty)
            .help("Copy what the window shows of the chosen side (\(channel.title))")
            Button {
                feed.clear()
            } label: {
                Label("Clear", systemImage: "eraser")
            }
            .labelStyle(.iconOnly)
            .controlSize(.small)
            .disabled(feed.lines.count <= feed.clearedBefore)
            .help("Empty this window. The recording goes on and nothing is removed from the meeting's files.")
            Toggle("Follow", isOn: $follow)
                .toggleStyle(.switch)
                .controlSize(.small)
                .fixedSize()
                .help("On: the window stays with the recording, the newest text in view. Off: it stays where you scrolled; new text is still added at the end.")
        }
    }

    private var transcript: some View {
        let lines = feed.lines(for: channel)
        let sides = feed.inProgressSides(for: channel)
        return ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    if lines.isEmpty, sides.isEmpty {
                        Text(emptyText)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.top, 40)
                    }
                    ForEach(lines) { line in
                        row(
                            time: MeetingTranscriptFormat.timestamp(line.segment.startMs),
                            speaker: MeetingTranscriptFormat.speakerLabel(line.segment),
                            side: line.segment.side,
                            text: line.segment.text,
                            pending: false
                        )
                    }
                    ForEach(sides, id: \.rawValue) { side in
                        row(
                            time: "…",
                            speaker: side == .you ? "You" : "Call",
                            side: side,
                            text: feed.inProgress[side] ?? "",
                            pending: true
                        )
                    }
                    Color.clear
                        .frame(height: 1)
                        .id(Self.bottomID)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color(nsColor: .textBackgroundColor))
            .onChange(of: feed.lines.count) { _, _ in
                scrollToBottomIfFollowing(proxy)
            }
            .onChange(of: feed.inProgress) { _, _ in
                scrollToBottomIfFollowing(proxy)
            }
            .onChange(of: channelValue) { _, _ in
                scrollToBottomIfFollowing(proxy)
            }
            .onChange(of: follow) { _, following in
                // Back in sync: jump to the newest text.
                if following {
                    proxy.scrollTo(Self.bottomID, anchor: .bottom)
                }
            }
            .onAppear {
                scrollToBottomIfFollowing(proxy)
            }
        }
    }

    /// Copies the finished sentences of the chosen side to the clipboard.
    private func copyTranscript() {
        let text = feed.text(for: channel)
        guard !text.isEmpty else {
            return
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        copied = true
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            copied = false
        }
    }

    private func scrollToBottomIfFollowing(_ proxy: ScrollViewProxy) {
        guard follow else {
            return
        }
        proxy.scrollTo(Self.bottomID, anchor: .bottom)
    }

    private func row(time: String, speaker: String, side: MeetingSide, text: String, pending: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(speaker)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(side == .you ? UntypeDesignTokens.accentAmber : Color.accentColor)
                Text(time)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
            Text(text)
                .font(.system(size: 13))
                .italic(pending)
                .foregroundStyle(pending ? Color.secondary : Color.primary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var emptyText: String {
        if feed.isRecording {
            if feed.clearedBefore > 0 {
                return "Cleared. New text will appear here; the meeting's files keep everything."
            }
            return channel == .both ? "Listening…" : "Nothing from this side yet."
        }
        return feed.meetingName.isEmpty
            ? "Start a meeting recording to see its transcript here."
            : "Nothing from this side in the last recording."
    }

    private var status: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(feed.isRecording ? Color.red : Color.secondary.opacity(0.5))
                .frame(width: 7, height: 7)
            Text(statusText)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 6)
            Text(follow ? "In sync" : "Out of sync")
                .font(.system(size: 11))
                .foregroundStyle(follow ? Color.secondary : UntypeDesignTokens.accentAmber)
        }
    }

    private var statusText: String {
        if feed.isRecording {
            return "Recording · \(feed.meetingName)"
        }
        return feed.meetingName.isEmpty ? "Not recording" : "Ended · \(feed.meetingName)"
    }
}
