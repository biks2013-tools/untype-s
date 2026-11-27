import SwiftUI
import UIKit
import UniformTypeIdentifiers
import UntypeCore
import WebKit

/// Video digests on the iPhone (plan-080). The library is the folder the
/// user picks once (iCloud Drive/untype/Videos, shared with the Mac). A
/// digest is made here from the video's captions (no screenshots: YouTube
/// refuses video downloads on the phone), or asked of the Mac through the
/// library's `Requests` folder.
@MainActor
final class VideoDigestPhone: ObservableObject {
    enum Place: String, CaseIterable, Identifiable {
        case phone, mac
        var id: String { rawValue }
        var title: String { self == .phone ? "This iPhone" : "My Mac" }
    }

    @AppStorage("videos.libraryBookmark") private var bookmark = Data()
    @AppStorage("videos.place") var placeRaw = Place.phone.rawValue
    @Published var address = ""
    /// "" = the language spoken in the video.
    @Published var language = ""
    @Published var docx = false
    @Published private(set) var running: String?
    @Published private(set) var progress = ""
    @Published var problem: String?
    @Published private(set) var entries: [VideoDigestEntry] = []
    @Published private(set) var requests: [VideoDigestInboxRequest] = []

    var place: Place { Place(rawValue: placeRaw) ?? .phone }

    var libraryName: String? { library?.lastPathComponent }

    /// The chosen folder, with access for this app (a security-scoped bookmark).
    var library: URL? {
        guard !bookmark.isEmpty else { return nil }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: bookmark, bookmarkDataIsStale: &stale) else { return nil }
        if stale, let fresh = try? url.bookmarkData() {
            bookmark = fresh
        }
        return url
    }

    func choose(_ url: URL) {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        do {
            bookmark = try url.bookmarkData()
            problem = nil
            refresh()
        } catch {
            problem = "The folder could not be kept: \(error.localizedDescription)"
        }
    }

    private func withLibrary<T>(_ work: (URL) throws -> T) rethrows -> T? {
        guard let library else { return nil }
        let access = library.startAccessingSecurityScopedResource()
        defer { if access { library.stopAccessingSecurityScopedResource() } }
        return try work(library)
    }

    func refresh() {
        withLibrary { library in
            entries = VideoDigestEntry.all(in: library)
            let inbox = VideoDigestInbox.folder(library)
            var found: [VideoDigestInboxRequest] = []
            for sub in ["", "claimed", "done", "failed"] {
                let folder = sub.isEmpty ? inbox : inbox.appendingPathComponent(sub)
                for name in (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? [] where name.hasSuffix(".json") && !name.hasPrefix(".") {
                    guard let data = try? Data(contentsOf: folder.appendingPathComponent(name)),
                          var request = try? VideoDigestInbox.decoder.decode(VideoDigestInboxRequest.self, from: data),
                          request.from == "iphone" else { continue }
                    if sub == "claimed" { request.error = nil; request.folder = "…" }
                    found.append(request)
                }
            }
            requests = found.sorted { $0.requestedAt > $1.requestedAt }.prefix(10).map { $0 }
        }
    }

    var canStart: Bool { YouTubeVideo.videoID(from: address) != nil && running == nil && library != nil }

    func start(settings: AppSettings) {
        guard let id = YouTubeVideo.videoID(from: address) else {
            problem = "This is not a YouTube address."
            return
        }
        problem = nil
        let request = VideoDigestRequest(url: YouTubeVideo.watchURL(id), language: language.isEmpty ? nil : language, docx: docx)
        address = ""
        switch place {
        case .mac:
            do {
                try withLibrary { library in
                    try VideoDigestInbox.send(VideoDigestInboxRequest(url: request.url, language: request.language, docx: request.docx, from: "iphone"), library: library)
                }
                refresh()
            } catch {
                problem = "The request could not be written to iCloud: \(error.localizedDescription)"
            }
        case .phone:
            Task { await runHere(request, settings: settings) }
        }
    }

    func resume(_ entry: VideoDigestEntry, settings: AppSettings) {
        Task { await runHere(nil, resume: entry.folder, settings: settings) }
    }

    /// Here, from the captions; the app is kept awake and in front meanwhile.
    private func runHere(_ request: VideoDigestRequest?, resume: URL? = nil, settings: AppSettings) async {
        guard let library else {
            problem = "Choose the videos folder first."
            return
        }
        let llm: LLMConfig
        do {
            llm = try settings.modelConfig(systemPrompt: "")
        } catch {
            problem = "The digest uses the model of Refine and Translate: \(error.localizedDescription)"
            return
        }
        running = request?.url ?? resume?.lastPathComponent ?? ""
        progress = "Starting"
        UIApplication.shared.isIdleTimerDisabled = true
        let background = UIApplication.shared.beginBackgroundTask(withName: "video digest")
        let access = library.startAccessingSecurityScopedResource()
        defer {
            if access { library.stopAccessingSecurityScopedResource() }
            UIApplication.shared.endBackgroundTask(background)
            UIApplication.shared.isIdleTimerDisabled = false
            running = nil
            progress = ""
            refresh()
        }
        let pipeline = VideoDigestPipeline(
            media: CaptionsOnlyMediaSource(),
            analyzer: VideoDigestAnalyzer(llm: llm),
            transcriber: nil,
            device: "iphone",
            onEvent: { line in DictationEngine.log.info("\(line, privacy: .public)") }
        )
        let report: @Sendable (String) -> Void = { [weak self] line in
            Task { @MainActor in self?.progress = line }
        }
        do {
            if let resume {
                _ = try await pipeline.resume(VideoDigestFolder(url: resume), progress: report)
            } else if let request {
                _ = try await pipeline.run(request, library: library, progress: report)
            }
        } catch {
            problem = error.localizedDescription
        }
    }
}

struct VideosView: View {
    @EnvironmentObject private var settings: AppSettings
    @StateObject private var model = VideoDigestPhone()
    @State private var picking = false
    @State private var showing: VideoDigestEntry?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField("YouTube address", text: $model.address)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                    Button {
                        model.address = UIPasteboard.general.string ?? ""
                    } label: {
                        Label("Paste", systemImage: "doc.on.clipboard")
                    }
                    Picker("Language", selection: $model.language) {
                        Text("As spoken in the video").tag("")
                        ForEach(VideoDigestModelLanguages.all, id: \.self) { Text($0).tag($0) }
                    }
                    Toggle("Also a Word document", isOn: $model.docx)
                    Picker("Make it on", selection: $model.placeRaw) {
                        ForEach(VideoDigestPhone.Place.allCases) { Text($0.title).tag($0.rawValue) }
                    }
                    .pickerStyle(.segmented)
                    Button {
                        model.start(settings: settings)
                    } label: {
                        Label(model.place == .phone ? "Digest" : "Send to my Mac", systemImage: model.place == .phone ? "sparkles" : "desktopcomputer")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!model.canStart)
                } footer: {
                    Text(model.place == .phone
                         ? "Made here from the video's captions, without screenshots; keep untype open until it is done. A video without captions needs the Mac."
                         : "untype on your Mac makes it, with screenshots, while it runs; the digest appears below.")
                }

                if let running = model.running {
                    Section {
                        HStack(spacing: 10) {
                            ProgressView()
                            VStack(alignment: .leading) {
                                Text(running).font(.footnote).lineLimit(1).truncationMode(.middle)
                                Text(model.progress).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    } footer: {
                        Text("Keep untype open: iOS stops it in the background.")
                    }
                }
                if let problem = model.problem {
                    Section {
                        Label(problem, systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                    }
                }

                if !model.requests.isEmpty {
                    Section("Sent to the Mac") {
                        ForEach(model.requests, id: \.id) { request in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(request.url).font(.footnote).lineLimit(1).truncationMode(.middle)
                                Text(requestStatus(request)).font(.caption).foregroundStyle(request.error == nil ? Color.secondary : Color.orange)
                            }
                        }
                    }
                }

                Section {
                    if model.library == nil {
                        Button("Choose the videos folder…") { picking = true }
                    }
                    ForEach(model.entries) { entry in
                        Button {
                            if entry.html != nil { showing = entry }
                        } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(entry.title).foregroundStyle(.primary).lineLimit(2)
                                Text(entryStatus(entry)).font(.caption).foregroundStyle(entry.error == nil ? Color.secondary : Color.orange).lineLimit(2)
                            }
                        }
                        .swipeActions {
                            if entry.stage != .done, model.running == nil {
                                Button("Resume") { model.resume(entry, settings: settings) }.tint(.blue)
                            }
                        }
                    }
                } header: {
                    Text("Digests")
                } footer: {
                    if let name = model.libraryName {
                        Text("In the folder \(name) (iCloud Drive, shared with the Mac). ") + Text("Change").foregroundColor(.accentColor)
                    }
                }
            }
            .navigationTitle("Videos")
            .refreshable { model.refresh() }
            .onAppear { model.refresh() }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { picking = true } label: { Image(systemName: "folder") }
                        .accessibilityLabel("Choose the videos folder")
                }
            }
            .fileImporter(isPresented: $picking, allowedContentTypes: [.folder]) { result in
                if case .success(let url) = result {
                    model.choose(url)
                }
            }
            .sheet(item: $showing) { entry in
                DigestReader(entry: entry, library: model.library)
            }
        }
    }

    private func requestStatus(_ request: VideoDigestInboxRequest) -> String {
        if let error = request.error { return "Failed: \(error)" }
        if request.folder == "…" { return "The Mac is making it" }
        if request.folder != nil { return "Done: below" }
        return "Waiting for the Mac (untype must be running there)"
    }

    private func entryStatus(_ entry: VideoDigestEntry) -> String {
        let date = entry.updated.formatted(date: .abbreviated, time: .shortened)
        if let error = entry.error { return "Stopped: \(error) · swipe to resume" }
        return entry.stage == .done ? date : "\(entry.stage.rawValue) · \(date)"
    }
}

enum VideoDigestModelLanguages {
    static let all = ["English", "Greek", "French", "German", "Spanish", "Italian"]
}

/// The digest's HTML, with Share for the HTML and the Word file.
private struct DigestReader: View {
    let entry: VideoDigestEntry
    let library: URL?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if let html = entry.html {
                    WebPage(file: html, root: library)
                } else {
                    Text("Not ready yet.")
                }
            }
            .navigationTitle(entry.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    if let html = entry.html {
                        let docx = html.deletingPathExtension().appendingPathExtension("docx")
                        let items = FileManager.default.fileExists(atPath: docx.path) ? [html, docx] : [html]
                        ShareLink(items: items) { Image(systemName: "square.and.arrow.up") }
                    }
                }
            }
        }
    }
}

private struct WebPage: UIViewRepresentable {
    let file: URL
    let root: URL?

    func makeUIView(context: Context) -> WKWebView {
        let view = WKWebView()
        let access = root?.startAccessingSecurityScopedResource() ?? false
        if let data = try? Data(contentsOf: file), let html = String(data: data, encoding: .utf8) {
            // Images are embedded, so the page needs nothing else from the folder.
            view.loadHTMLString(html, baseURL: nil)
        }
        if access { root?.stopAccessingSecurityScopedResource() }
        return view
    }

    func updateUIView(_ view: WKWebView, context: Context) {}
}
