#if os(macOS)
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

/// Something attached during the meeting, where the window shows it: after
/// the lines that were there when it was attached (plan-077).
public struct TranscriptionAttachment: Identifiable, Equatable, Sendable {
    public let attachment: MeetingAttachment
    /// How many lines the transcript had when it was attached.
    public let position: Int

    public var id: Int { attachment.id }
}

/// One row of the transcription window, in the order shown.
public enum TranscriptionRow: Identifiable, Equatable, Sendable {
    case line(TranscriptionLine)
    case attachment(TranscriptionAttachment)

    public var id: String {
        switch self {
        case .line(let line): return "line-\(line.id)"
        case .attachment(let attachment): return "attachment-\(attachment.id)"
        }
    }
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
    /// The sides whose capture the user has paused.
    @Published public private(set) var paused: Set<MeetingSide> = []
    /// Asks the recorder to pause or resume a side (set by the owner of
    /// the recorder); it answers with `setPaused`.
    public var onPauseRequest: ((_ side: MeetingSide, _ paused: Bool) -> Void)?
    /// What was attached to this meeting, in order (plan-077).
    @Published public private(set) var attachments: [TranscriptionAttachment] = []
    /// The meeting folder (it changes when the meeting is named).
    @Published public private(set) var meetingFolder: URL?
    public var attachmentCount: Int { attachments.count - removedAttachments.count }
    /// Attachments before this one were cleared from the window.
    @Published private var clearedAttachments = 0
    /// What the last attach action did, shown for a moment.
    @Published public private(set) var attachNote: String?
    /// Asks the owner of the recorder to attach what the clipboard holds.
    public var onAttachRequest: (() -> Void)?
    /// Asks the owner of the recorder to attach these files or folders
    /// (dropped on the window, or chosen with "Attach a file").
    public var onAttachFilesRequest: (([URL]) -> Void)?
    /// Asks the owner of the recorder to take a line or an attachment out
    /// of the meeting; it answers with `removed`.
    public var onDeleteRequest: ((TranscriptionRow) -> Void)?
    /// Lines and attachments taken out of the meeting.
    @Published private var removedLines: Set<Int> = []
    @Published private var removedAttachments: Set<Int> = []
    /// Asks the owner of the recorder to end the lines being spoken at
    /// their last full stop.
    public var onCutRequest: (() -> Void)?
    private var attachNoteNumber = 0

    public init() {}

    /// A row's Delete: take it out of the meeting (only while it is
    /// recorded: afterwards the files are final).
    public func delete(_ row: TranscriptionRow) {
        guard isRecording else {
            return
        }
        onDeleteRequest?(row)
    }

    /// The answer: the row is out of the meeting.
    public func removed(_ row: TranscriptionRow) {
        switch row {
        case .line(let line): removedLines.insert(line.id)
        case .attachment(let attachment): removedAttachments.insert(attachment.id)
        }
    }

    /// The window's button: what was said so far goes into the transcript.
    public func cutAtLastSentenceEnd() {
        guard isRecording else {
            return
        }
        onCutRequest?()
    }

    /// The window's button: attach the clipboard to this moment.
    public func attachClipboard() {
        guard isRecording else {
            return
        }
        onAttachRequest?()
    }

    /// Files dropped on the window or chosen in the file dialog: attach
    /// them to this moment. False when nothing was asked (not recording,
    /// or no file among them).
    @discardableResult
    public func attachFiles(_ urls: [URL]) -> Bool {
        let files = urls.filter(\.isFileURL)
        guard isRecording, !files.isEmpty else {
            return false
        }
        onAttachFilesRequest?(files)
        return true
    }

    /// Where the meeting's files are.
    public func setMeetingFolder(_ folder: URL?) {
        meetingFolder = folder
        meetingName = folder?.lastPathComponent ?? meetingName
    }

    /// The meeting was named: its folder moved.
    public func folderRenamed(from old: URL, to new: URL) {
        if meetingFolder?.standardizedFileURL == old.standardizedFileURL {
            setMeetingFolder(new)
        }
    }

    /// The file of an attachment (nil before the folder is known).
    public func url(of attachment: MeetingAttachment) -> URL? {
        meetingFolder?.appendingPathComponent(attachment.file)
    }

    /// The rows of `channel` the window shows: its lines, and every
    /// attachment at the place of the conversation it was attached.
    public func rows(for channel: TranscriptionChannel) -> [TranscriptionRow] {
        var rows: [TranscriptionRow] = []
        var pending = attachments.dropFirst(clearedAttachments).filter { !removedAttachments.contains($0.id) }[...]
        for line in lines(for: channel) {
            while let next = pending.first, next.position <= line.id {
                rows.append(.attachment(next))
                pending = pending.dropFirst()
            }
            rows.append(.line(line))
        }
        rows.append(contentsOf: pending.map(TranscriptionRow.attachment))
        return rows
    }

    /// The answer: what was attached, and what to tell the user.
    public func noteAttach(added: [MeetingAttachment], note: String) {
        attachments.append(contentsOf: added.map { TranscriptionAttachment(attachment: $0, position: lines.count) })
        attachNote = note
        attachNoteNumber += 1
        let number = attachNoteNumber
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            if self?.attachNoteNumber == number {
                self?.attachNote = nil
            }
        }
    }

    /// The window's button: pause the side, or resume it.
    public func togglePause(_ side: MeetingSide) {
        guard isRecording else {
            return
        }
        onPauseRequest?(side, !paused.contains(side))
    }

    /// The recorder's answer: `side` is paused, or runs.
    public func setPaused(_ isPaused: Bool, side: MeetingSide) {
        if isPaused {
            paused.insert(side)
        } else {
            paused.remove(side)
        }
    }

    /// Empties the window: the lines shown so far are no longer shown. The
    /// recording and its files are not touched; new text keeps coming.
    public func clear() {
        clearedBefore = lines.count
        clearedAttachments = attachments.count
    }

    /// A new recording: the previous transcript goes.
    public func begin(meetingName: String) {
        lines = []
        clearedBefore = 0
        inProgress = [:]
        paused = []
        attachments = []
        removedLines = []
        removedAttachments = []
        clearedAttachments = 0
        meetingFolder = nil
        attachNote = nil
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
        paused = []
        isRecording = false
    }

    /// The finished lines of `channel` that the window shows (those added
    /// since the last clear), in the order they arrived.
    public func lines(for channel: TranscriptionChannel) -> [TranscriptionLine] {
        lines.dropFirst(clearedBefore).filter { !removedLines.contains($0.id) && channel.includes($0.segment.side) }
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
    private let openAssistant: () -> Void
    private var window: NSWindow?

    init(feed: MeetingTranscriptFeed, openAssistant: @escaping () -> Void) {
        self.feed = feed
        self.openAssistant = openAssistant
    }

    func show() {
        let window = self.window ?? makeWindow()
        self.window = window
        window.showOnActiveDesktop()
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
        window.contentView = NSHostingView(rootView: UntypeTranscriptionView(feed: feed, openAssistant: openAssistant))
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
    /// Opens the meeting assistant (plan-078).
    var openAssistant: () -> Void = {}
    /// `TranscriptionChannel` raw value.
    @AppStorage("untype.transcriptionWindow.channel") private var channelValue = TranscriptionChannel.both.rawValue
    /// In sync: the window follows the recording, the newest text in view.
    /// Out of sync: it stays where the user scrolled, text is still added
    /// at the end.
    @AppStorage("untype.transcriptionWindow.follow") private var follow = true
    /// Just copied: the button says so for a moment.
    @State private var copied = false
    /// Files are being dragged over the transcript.
    @State private var dropTargeted = false
    /// The row the user asked to delete, until they confirm.
    @State private var pendingDelete: TranscriptionRow?

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
        .confirmationDialog(
            deleteTitle,
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let row = pendingDelete {
                    feed.delete(row)
                }
                pendingDelete = nil
            }
            Button("Cancel", role: .cancel) {
                pendingDelete = nil
            }
        } message: {
            Text(deleteMessage)
        }
    }

    private var deleteTitle: String {
        if case .attachment = pendingDelete {
            return "Delete this attachment from the meeting?"
        }
        return "Delete this line from the meeting?"
    }

    private var deleteMessage: String {
        if case .attachment = pendingDelete {
            return "Its copy in the meeting folder is deleted and it leaves the list of attachments. The original is not touched."
        }
        return "It leaves the transcript and its files. The audio recording is not changed."
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
            if let side = pausableSide {
                let isPaused = feed.paused.contains(side)
                Button {
                    feed.togglePause(side)
                } label: {
                    Label(isPaused ? "Resume" : "Pause", systemImage: isPaused ? "play.fill" : "pause.fill")
                }
                .controlSize(.small)
                .tint(isPaused ? UntypeDesignTokens.accentAmber : nil)
                .disabled(!feed.isRecording)
                .help(isPaused
                    ? "Resume capturing the \(Self.name(of: side))"
                    : "Pause capturing the \(Self.name(of: side)): nothing of it is transcribed or saved until you resume. The other side goes on.")
            }
            Button {
                feed.cutAtLastSentenceEnd()
            } label: {
                Label("End the line at the last full stop", systemImage: "arrow.turn.down.left")
            }
            .labelStyle(.iconOnly)
            .controlSize(.small)
            .disabled(!feed.isRecording)
            .help("End the lines being spoken at their last full stop: the sentences finished so far go into the transcript now (the assistant can read them), the words after them stay in progress. Asking the assistant does this by itself.")
            Button {
                feed.attachClipboard()
            } label: {
                Label("Attach", systemImage: "paperclip")
            }
            .controlSize(.small)
            .disabled(!feed.isRecording)
            .help("Attach what the clipboard holds (text, a screenshot or other picture, copied files) to this moment of the meeting. It is saved in the meeting folder.")
            Button {
                chooseFiles()
            } label: {
                Label("Attach a file", systemImage: "doc.badge.plus")
            }
            .labelStyle(.iconOnly)
            .controlSize(.small)
            .disabled(!feed.isRecording)
            .help("Choose files to attach to this moment of the meeting. Files can also be dropped on the transcript.")
            Spacer(minLength: 8)
            Button {
                openAssistant()
            } label: {
                Label("Ask", systemImage: "sparkles")
            }
            .controlSize(.small)
            .help("Ask the meeting assistant about this meeting: it reads the transcript and the attachments")
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
            .disabled(feed.rows(for: .both).isEmpty)
            .help("Empty this window. The recording goes on and nothing is removed from the meeting's files.")
            Toggle("Follow", isOn: $follow)
                .toggleStyle(.switch)
                .controlSize(.small)
                .fixedSize()
                .help("On: the window stays with the recording, the newest text in view. Off: it stays where you scrolled; new text is still added at the end.")
        }
    }

    private var transcript: some View {
        let lines = feed.rows(for: channel)
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
                    ForEach(lines) { item in
                        TranscriptionDeletableRow(canDelete: feed.isRecording, delete: { pendingDelete = item }) {
                            switch item {
                            case .line(let line):
                                row(
                                    time: MeetingTranscriptFormat.timestamp(line.segment.startMs),
                                    speaker: MeetingTranscriptFormat.speakerLabel(line.segment),
                                    side: line.segment.side,
                                    text: line.segment.text,
                                    pending: false
                                )
                            case .attachment(let shown):
                                TranscriptionAttachmentRow(attachment: shown.attachment, url: feed.url(of: shown.attachment))
                            }
                        }
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
            .overlay {
                if dropTargeted, feed.isRecording {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                        .background(Color.accentColor.opacity(0.08))
                        .overlay(
                            Label("Drop to attach to this moment of the meeting", systemImage: "paperclip")
                                .font(.system(size: 13, weight: .semibold))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(.regularMaterial, in: Capsule())
                        )
                        .padding(6)
                        .allowsHitTesting(false)
                }
            }
            .dropDestination(for: URL.self) { urls, _ in
                feed.attachFiles(urls)
            } isTargeted: { targeted in
                dropTargeted = targeted
            }
            .onChange(of: feed.lines.count) { _, _ in
                scrollToBottomIfFollowing(proxy)
            }
            .onChange(of: feed.attachments.count) { _, _ in
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

    /// "Attach a file": the file dialog, then the chosen files and folders
    /// are attached to the moment the dialog is confirmed.
    private func chooseFiles() {
        let panel = NSOpenPanel()
        panel.title = "Attach to the meeting"
        panel.prompt = "Attach"
        panel.allowsMultipleSelection = true
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.begin { response in
            guard response == .OK else {
                return
            }
            let urls = panel.urls
            Task { @MainActor in
                feed.attachFiles(urls)
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
            if let side = pausableSide, feed.paused.contains(side) {
                return "The \(Self.name(of: side)) is paused. Press Resume to capture it again."
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
                .fill(feed.isRecording ? (feed.paused.isEmpty ? Color.red : UntypeDesignTokens.accentAmber) : Color.secondary.opacity(0.5))
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

    /// The side the Pause button of the chosen tab acts on; none on Both.
    private var pausableSide: MeetingSide? {
        switch channel {
        case .both: return nil
        case .microphone: return .you
        case .system: return .call
        }
    }

    private static func name(of side: MeetingSide) -> String {
        side == .you ? "microphone" : "system audio"
    }

    private var statusText: String {
        if let note = feed.attachNote {
            return note
        }
        let attached = feed.attachmentCount == 0 ? "" : " · \(feed.attachmentCount) attached"
        if feed.isRecording {
            let paused = [MeetingSide.you, .call].filter { feed.paused.contains($0) }.map { Self.name(of: $0) }
            if !paused.isEmpty {
                return "Recording · \(paused.joined(separator: " and ")) paused\(attached) · \(feed.meetingName)"
            }
            return "Recording\(attached) · \(feed.meetingName)"
        }
        return feed.meetingName.isEmpty ? "Not recording" : "Ended\(attached) · \(feed.meetingName)"
    }
}
/// An attachment in the transcript: a paperclip, when it was attached, and
/// a thumbnail (the picture, the start of the text, the file's icon). A
/// click opens it.
private struct TranscriptionAttachmentRow: View {
    let attachment: MeetingAttachment
    let url: URL?
    @State private var image: NSImage?
    @State private var text: String?
    @State private var hovered = false

    var body: some View {
        Button {
            open()
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: "paperclip")
                        .font(.system(size: 11, weight: .semibold))
                    Text(title)
                        .font(.system(size: 11, weight: .semibold))
                    Text(attachment.time)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
                .foregroundStyle(.secondary)
                thumbnail
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.secondary.opacity(hovered ? 0.16 : 0.08))
            )
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .help("Open the attachment")
        .contextMenu {
            Button("Open") { open() }
            Button("Show in Finder") {
                if let url {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                }
            }
        }
        .task(id: url) {
            load()
        }
    }

    @ViewBuilder private var thumbnail: some View {
        switch attachment.kind {
        case .image:
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: 260, maxHeight: 150, alignment: .leading)
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous).stroke(Color.secondary.opacity(0.3)))
            }
        case .text:
            if let text {
                Text(text)
                    .font(.system(size: 12))
                    .foregroundStyle(.primary)
                    .lineLimit(4)
                    .multilineTextAlignment(.leading)
            }
        case .file, .folder:
            HStack(spacing: 8) {
                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .frame(width: 32, height: 32)
                }
                Text(attachment.originalName ?? "")
                    .font(.system(size: 12))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
    }

    private var title: String {
        switch attachment.kind {
        case .image: return "Picture · \(attachment.width ?? 0)×\(attachment.height ?? 0)"
        case .text: return "Text · \(attachment.characters ?? 0) characters"
        case .file: return "File"
        case .folder: return "Folder"
        }
    }

    private func open() {
        if let url {
            NSWorkspace.shared.open(url)
        }
    }

    private func load() {
        guard let url else {
            return
        }
        switch attachment.kind {
        case .image:
            image = NSImage(contentsOf: url)
        case .text:
            text = (try? String(contentsOf: url, encoding: .utf8)).map { String($0.prefix(400)) }
        case .file, .folder:
            image = NSWorkspace.shared.icon(forFile: url.path)
        }
    }
}
/// A row of the transcript with a Delete button that shows while the
/// pointer is on it (and in its context menu), while the meeting is recorded.
private struct TranscriptionDeletableRow<Content: View>: View {
    let canDelete: Bool
    let delete: () -> Void
    @ViewBuilder let content: () -> Content
    @State private var hovered = false

    var body: some View {
        content()
            .overlay(alignment: .topTrailing) {
                if hovered, canDelete {
                    Button(action: delete) {
                        Image(systemName: "trash")
                            .font(.system(size: 11))
                            .padding(4)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help("Delete from the meeting")
                }
            }
            .onHover { hovered = $0 }
            .contextMenu {
                if canDelete {
                    Button("Delete from the meeting", role: .destructive, action: delete)
                }
            }
    }
}
#endif
