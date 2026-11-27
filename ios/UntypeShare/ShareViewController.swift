import SwiftUI
import UIKit
import UniformTypeIdentifiers
import UntypeCore

/// Share → untype on a YouTube video (plan-080 step 4). "My Mac" writes the
/// request into the videos folder in iCloud at once; "This iPhone" queues it
/// for the app, which starts the digest when it is opened (an extension may
/// not do the work, nor open the app).
final class ShareViewController: UIViewController {
    private let state = ShareState()

    override func viewDidLoad() {
        super.viewDidLoad()
        let host = UIHostingController(rootView: ShareView(state: state, close: { [weak self] in self?.finish() }))
        addChild(host)
        host.view.frame = view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(host.view)
        host.didMove(toParent: self)
        Task { await findAddress() }
    }

    private func finish() {
        extensionContext?.completeRequest(returningItems: nil)
    }

    /// The first YouTube address among the shared items (a URL, or text holding one).
    private func findAddress() async {
        let providers = (extensionContext?.inputItems as? [NSExtensionItem] ?? []).flatMap { $0.attachments ?? [] }
        for provider in providers {
            for type in [UTType.url, UTType.plainText] where provider.hasItemConformingToTypeIdentifier(type.identifier) {
                guard let item = try? await provider.loadItem(forTypeIdentifier: type.identifier) else { continue }
                let text = (item as? URL)?.absoluteString ?? (item as? String) ?? ""
                for word in text.split(whereSeparator: \.isWhitespace) {
                    if let id = YouTubeVideo.videoID(from: String(word)) {
                        await MainActor.run { state.videoID = id }
                        return
                    }
                }
            }
        }
        await MainActor.run { state.message = "This is not a YouTube video." }
    }
}

@MainActor
final class ShareState: ObservableObject {
    @Published var videoID: String?
    @Published var language = ""
    @Published var docx = false
    @Published var place = SharedVideoQueue.defaults?.string(forKey: "videos.place") ?? "phone"
    @Published var message: String?
    @Published var sent = false
}

private struct ShareView: View {
    @ObservedObject var state: ShareState
    let close: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                if let id = state.videoID {
                    Section {
                        Label(YouTubeVideo.watchURL(id), systemImage: "play.rectangle")
                            .font(.footnote)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Picker("Language", selection: $state.language) {
                            Text("As spoken in the video").tag("")
                            ForEach(["English", "Greek", "French", "German", "Spanish", "Italian"], id: \.self) { Text($0).tag($0) }
                        }
                        Toggle("Also a Word document", isOn: $state.docx)
                        Picker("Make it on", selection: $state.place) {
                            Text("This iPhone").tag("phone")
                            Text("My Mac").tag("mac")
                        }
                        .pickerStyle(.segmented)
                    } footer: {
                        Text(state.place == "phone"
                             ? "Open untype: the digest starts there, from the video's captions (no screenshots)."
                             : "untype on your Mac makes it, with screenshots; it appears in untype → Videos.")
                    }
                }
                if let message = state.message {
                    Section { Text(message).font(.footnote) }
                }
            }
            .navigationTitle("Video digest")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(state.sent ? "Done" : "Cancel", action: close)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(state.place == "phone" ? "Queue" : "Send") { send() }
                        .disabled(state.videoID == nil || state.sent)
                }
            }
        }
    }

    private func send() {
        guard let id = state.videoID else { return }
        let url = YouTubeVideo.watchURL(id)
        let language = state.language.isEmpty ? nil : state.language
        SharedVideoQueue.defaults?.set(state.place, forKey: "videos.place")
        do {
            if state.place == "mac" {
                do {
                    try SharedVideoQueue.sendToMac(url: url, language: language, docx: state.docx)
                    state.message = "Sent to your Mac."
                } catch {
                    // The folder could not be reached from here: the app sends it when opened.
                    try SharedVideoQueue.add(.init(url: url, language: language, docx: state.docx, place: .mac))
                    state.message = "untype sends it to your Mac when you open it (\(error.localizedDescription))."
                }
            } else {
                try SharedVideoQueue.add(.init(url: url, language: language, docx: state.docx, place: .phone))
                state.message = "Queued. Open untype: the digest starts in Videos."
            }
            state.sent = true
            Task {
                try? await Task.sleep(nanoseconds: 1_400_000_000)
                close()
            }
        } catch {
            state.message = error.localizedDescription
        }
    }
}
