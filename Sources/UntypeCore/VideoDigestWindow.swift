#if os(macOS)
import AppKit
import Foundation
import SwiftUI

/// The video digests on the Mac: the window's requests and the iPhone's
/// (from iCloud), one at a time.
@MainActor
public final class VideoDigestModel: ObservableObject {
    public static let languages = ["English", "Greek", "French", "German", "Spanish", "Italian"]

    @Published public var address = ""
    /// "" = the language spoken in the video.
    @Published public var language = ""
    @Published public var docx = false
    @Published public private(set) var running: String?
    @Published public private(set) var progress = ""
    @Published public private(set) var waiting = 0
    @Published public var problem: String?
    @Published public private(set) var entries: [VideoDigestEntry] = []

    /// The analysis model: the model of Refine, set by the app.
    public var llmConfig: (() throws -> LLMConfig)?
    public var onEvent: (String) -> Void = { _ in }

    private var queue: [(VideoDigestRequest, inbox: (VideoDigestInboxRequest, URL)?, resume: URL?)] = []
    private var timer: Timer?

    public init() {}

    private func settings() throws -> VideoDigestMacSettings {
        try VideoDigestMacSettings.load(MeetingAssistantSettings.environment())
    }

    /// Looks at the library and the iCloud requests now and every 30 s.
    public func start() {
        guard timer == nil else { return }
        refresh()
        let timer = Timer(timeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    public func refresh() {
        guard let settings = try? settings() else { return }
        entries = VideoDigestEntry.all(in: settings.library)
        for file in VideoDigestInbox.waiting(settings.library) {
            guard let claimed = VideoDigestInbox.claim(file) else { continue }
            onEvent("diagnostic.info: [untype] video digest: a request from the \(claimed.0.from) was picked up")
            enqueue(VideoDigestRequest(url: claimed.0.url, language: claimed.0.language, docx: claimed.0.docx), inbox: claimed, resume: nil)
        }
    }

    public var canStart: Bool {
        YouTubeVideo.videoID(from: address) != nil
    }

    public func startFromWindow() {
        guard canStart else {
            problem = "This is not a YouTube address."
            return
        }
        problem = nil
        enqueue(VideoDigestRequest(url: address.trimmingCharacters(in: .whitespacesAndNewlines), language: language.isEmpty ? nil : language, docx: docx), inbox: nil, resume: nil)
        address = ""
    }

    public func resume(_ entry: VideoDigestEntry) {
        guard let job = try? VideoDigestPipeline.job(VideoDigestFolder(url: entry.folder)) else { return }
        enqueue(job.request, inbox: nil, resume: entry.folder)
    }

    private func enqueue(_ request: VideoDigestRequest, inbox: (VideoDigestInboxRequest, URL)?, resume: URL?) {
        queue.append((request, inbox, resume))
        waiting = queue.count
        if running == nil {
            Task { await runNext() }
        }
    }

    private func runNext() async {
        guard !queue.isEmpty else {
            running = nil
            waiting = 0
            return
        }
        let (request, inbox, resume) = queue.removeFirst()
        waiting = queue.count
        running = request.url
        progress = "Starting"
        var made: URL?
        var failure: String?
        do {
            let settings = try settings()
            guard let llmConfig else {
                throw VideoDigestError.configuration("No language model is set for the digest.")
            }
            let environment = try MeetingAssistantSettings.environment()
            let soniox = environment["SONIOX_API_KEY"].flatMap { $0.isEmpty ? nil : SonioxFileTranscriber(apiKey: $0, languageHints: []) }
            let pipeline = VideoDigestPipeline(
                media: YtDlpMediaSource(settings: settings),
                analyzer: VideoDigestAnalyzer(llm: try llmConfig()),
                transcriber: soniox,
                device: "mac",
                onEvent: { [weak self] line in Task { @MainActor in self?.onEvent("diagnostic.info: [untype] \(line)") } }
            )
            let report: @Sendable (String) -> Void = { [weak self] line in
                Task { @MainActor in self?.progress = line }
            }
            try FileManager.default.createDirectory(at: settings.library, withIntermediateDirectories: true)
            let folder: VideoDigestFolder
            if let resume {
                folder = try await pipeline.resume(VideoDigestFolder(url: resume), progress: report)
            } else {
                folder = try await pipeline.run(request, library: settings.library, progress: report)
            }
            made = folder.url
            if inbox == nil {
                NSWorkspace.shared.open(folder.html)
            }
        } catch {
            failure = error.localizedDescription
            if inbox == nil {
                problem = error.localizedDescription
            }
        }
        if let (request, claimed) = inbox {
            VideoDigestInbox.finish(request, claimed: claimed, folder: made, error: failure)
        }
        if let settings = try? settings() {
            entries = VideoDigestEntry.all(in: settings.library)
        }
        running = nil
        progress = ""
        await runNext()
    }
}

struct VideoDigestView: View {
    @ObservedObject var model: VideoDigestModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                TextField("YouTube address", text: $model.address)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(model.startFromWindow)
                Button("Paste") {
                    model.address = NSPasteboard.general.string(forType: .string) ?? ""
                }
            }
            HStack(spacing: 16) {
                Picker("Language", selection: $model.language) {
                    Text("As spoken in the video").tag("")
                    ForEach(VideoDigestModel.languages, id: \.self) { Text($0).tag($0) }
                }
                .frame(maxWidth: 280)
                Toggle("Also a Word document", isOn: $model.docx)
                Spacer()
                Button("Digest") { model.startFromWindow() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!model.canStart)
            }
            if let running = model.running {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(running).font(.callout).lineLimit(1).truncationMode(.middle)
                        Text(model.progress + (model.waiting > 0 ? " · \(model.waiting) waiting" : "")).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            if let problem = model.problem {
                HStack(alignment: .top) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    Text(problem).font(.callout).textSelection(.enabled)
                    Spacer()
                    Button { model.problem = nil } label: { Image(systemName: "xmark") }.buttonStyle(.borderless)
                }
                .padding(8)
                .background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
            }
            Divider()
            Text("Digests").font(.headline)
            List(model.entries) { entry in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.title).lineLimit(2)
                        Text(status(entry)).font(.caption).foregroundStyle(entry.error == nil ? Color.secondary : Color.orange).lineLimit(2)
                    }
                    Spacer()
                    if let html = entry.html {
                        Button("Open") { NSWorkspace.shared.open(html) }
                    }
                    if entry.stage != .done, model.running == nil {
                        Button("Resume") { model.resume(entry) }
                    }
                    Button {
                        NSWorkspace.shared.activateFileViewerSelecting([entry.folder])
                    } label: { Image(systemName: "folder") }
                    .help("Show in Finder")
                }
            }
            .listStyle(.inset)
            Text("Requests sent from the iPhone (untype → Videos → On my Mac) are done here while untype runs.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(minWidth: 560, minHeight: 420)
        .onAppear { model.refresh() }
    }

    private func status(_ entry: VideoDigestEntry) -> String {
        let date = entry.updated.formatted(date: .abbreviated, time: .shortened)
        if let error = entry.error {
            return "Stopped: \(error)"
        }
        return entry.stage == .done ? date : "\(entry.stage.rawValue) · \(date)"
    }
}

final class VideoDigestWindowController: NSObject {
    private static let frameAutosaveName = "untype.videoDigestWindow.v1"
    private let model: VideoDigestModel
    private var window: NSWindow?

    init(model: VideoDigestModel) {
        self.model = model
    }

    @MainActor
    func show() {
        let window = self.window ?? makeWindow()
        self.window = window
        window.showOnActiveDesktop()
    }

    @MainActor
    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 560),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Video digest"
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: VideoDigestView(model: model))
        if !window.setFrameUsingName(Self.frameAutosaveName) {
            window.center()
        }
        window.setFrameAutosaveName(Self.frameAutosaveName)
        return window
    }
}
#endif
