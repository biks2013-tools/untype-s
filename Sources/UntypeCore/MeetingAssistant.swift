#if os(macOS)
import AppKit
import Foundation
import PDFKit
import SwiftUI

// plan-078: the meeting assistant. An agent (pi-durable, TypeScript) runs
// as a helper process of untype.app on the bundled Node.js; it reads the
// meeting folder (the transcript written live, the attachments) and answers
// the user's questions. This file is its Swift side: the process, the
// model of the conversation, and the window.

/// One message of the conversation with the assistant.
public struct AssistantMessage: Identifiable, Equatable, Sendable {
    public enum Role: String, Sendable, Equatable {
        case user
        case assistant
        /// Something untype says (a failed answer).
        case note
    }

    public let id: Int
    public let role: Role
    public let text: String

    public init(id: Int, role: Role, text: String) {
        self.id = id
        self.role = role
        self.text = text
    }
}

/// What the helper process says, one JSON object per line of its output.
public enum MeetingAssistantEvent: Equatable, Sendable {
    case ready(provider: String, model: String)
    case opened(key: String, history: [AssistantMessage])
    case runStart
    case tool(String)
    /// More of the answer; with `reset` it replaces what was shown.
    case text(delta: String, reset: Bool)
    case runEnd(failure: String?)
    case error(String)
    case fatal(String)
    /// The helper asks untype for the text of a document (a PDF, an old
    /// Word or rich text file); answered with an `extracted` request.
    case extract(id: String, path: String)

    public static func parse(_ line: String) -> MeetingAssistantEvent? {
        guard let data = line.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = object["type"] as? String else {
            return nil
        }
        switch type {
        case "ready":
            return .ready(provider: object["provider"] as? String ?? "", model: object["model"] as? String ?? "")
        case "opened":
            let items = object["history"] as? [[String: Any]] ?? []
            let history = items.enumerated().compactMap { index, item -> AssistantMessage? in
                guard let role = (item["role"] as? String).flatMap(AssistantMessage.Role.init(rawValue:)),
                      let text = item["text"] as? String else {
                    return nil
                }
                return AssistantMessage(id: index, role: role, text: text)
            }
            return .opened(key: object["key"] as? String ?? "", history: history)
        case "run_start":
            return .runStart
        case "tool":
            return .tool(object["name"] as? String ?? "")
        case "text":
            return .text(delta: object["delta"] as? String ?? "", reset: object["reset"] as? Bool ?? false)
        case "run_end":
            return .runEnd(failure: object["failure"] as? String)
        case "error":
            return .error(object["message"] as? String ?? "")
        case "fatal":
            return .fatal(object["message"] as? String ?? "")
        case "extract":
            guard let id = object["id"] as? String, let path = object["path"] as? String else {
                return nil
            }
            return .extract(id: id, path: path)
        default:
            return nil
        }
    }
}

/// The text of the documents the assistant's helper cannot read itself:
/// PDF (PDFKit) and old Word / rich text files (the system's reader).
public enum MeetingDocumentText {
    public struct Failure: LocalizedError, Sendable {
        public let errorDescription: String?

        public init(errorDescription: String?) {
            self.errorDescription = errorDescription
        }
    }

    /// The document's text; a PDF's pages are marked ("--- Page 3 ---").
    /// Empty when the document has none (scanned pages).
    public static func extract(_ url: URL) throws -> String {
        switch url.pathExtension.lowercased() {
        case "pdf":
            guard let document = PDFDocument(url: url) else {
                throw Failure(errorDescription: "the PDF cannot be opened")
            }
            guard !document.isLocked else {
                throw Failure(errorDescription: "the PDF is protected with a password")
            }
            var parts: [String] = []
            for index in 0..<document.pageCount {
                let text = document.page(at: index)?.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if !text.isEmpty {
                    parts.append("--- Page \(index + 1) of \(document.pageCount) ---\n\(text)")
                }
            }
            return parts.joined(separator: "\n\n")
        case "doc", "rtf":
            let type: NSAttributedString.DocumentType = url.pathExtension.lowercased() == "rtf" ? .rtf : .docFormat
            return try NSAttributedString(url: url, options: [.documentType: type], documentAttributes: nil).string
        default:
            throw Failure(errorDescription: "files of type .\(url.pathExtension) cannot be read")
        }
    }
}

/// Where the assistant's program is: the Node.js binary and the agent's
/// script, both inside untype.app.
public struct MeetingAssistantInstallation: Sendable, Equatable {
    public let node: URL
    public let script: URL

    public init(node: URL, script: URL) {
        self.node = node
        self.script = script
    }

    /// The copy inside the running app (nil when this build has none, as
    /// when untype runs outside its packaged app).
    public static func bundled(_ bundle: Bundle = .main) -> MeetingAssistantInstallation? {
        guard let resources = bundle.resourceURL, let executable = bundle.executableURL else {
            return nil
        }
        let node = executable.deletingLastPathComponent().appendingPathComponent("untype-node")
        let script = resources.appendingPathComponent("agent/dist/src/main.js")
        guard FileManager.default.isExecutableFile(atPath: node.path),
              FileManager.default.fileExists(atPath: script.path) else {
            return nil
        }
        return MeetingAssistantInstallation(node: node, script: script)
    }

    func process(_ command: String, environment: [String: String]) -> Process {
        let process = Process()
        process.executableURL = node
        process.arguments = ["--disable-warning=ExperimentalWarning", script.path, command]
        process.environment = environment
        process.currentDirectoryURL = script.deletingLastPathComponent()
        return process
    }
}

/// The assistant's own settings: its model, apart from the models of
/// Refine and Translate. Kept in `~/.tool-agents/untype/.env`; neither has
/// a default.
public enum MeetingAssistantSettings {
    public static let providerKey = "UNTYPE_AGENT_LLM_PROVIDER"
    public static let modelKey = "UNTYPE_AGENT_LLM_MODEL"
    public static let homeKey = "UNTYPE_AGENT_HOME"

    public struct Choice: Equatable, Sendable {
        public var provider: String
        public var model: String
    }

    /// What the helper process runs with: the app's environment, over it
    /// the values of the user's .env (API keys, the assistant's model), and
    /// where the conversations are kept.
    public static func environment(
        shell: [String: String] = ProcessInfo.processInfo.environment,
        home: URL = FileManager.default.untypeHomeDirectory
    ) throws -> [String: String] {
        var environment = shell
        for (key, value) in try DotenvEditor.read(DotenvEditor.userEnvURL(home: home)) {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                environment[key] = trimmed
            }
        }
        environment[homeKey] = home
            .appendingPathComponent(".tool-agents")
            .appendingPathComponent("untype")
            .appendingPathComponent("agent")
            .path
        return environment
    }

    /// The chosen model (nil until the user chooses one).
    public static func choice(in environment: [String: String]) -> Choice? {
        guard let provider = environment[providerKey], !provider.isEmpty,
              let model = environment[modelKey], !model.isEmpty else {
            return nil
        }
        return Choice(provider: provider, model: model)
    }

    public static func save(_ choice: Choice, home: URL = FileManager.default.untypeHomeDirectory) throws {
        try DotenvEditor.upsert(
            [providerKey: choice.provider, modelKey: choice.model],
            into: DotenvEditor.userEnvURL(home: home)
        )
    }

    /// The conversation of a meeting is found again by this: the
    /// recording's stem (`recording-yyyy-MM-dd-HH-mm`) and the " (2)" of a
    /// second folder of the same minute. It survives naming the meeting.
    public static func key(for folder: URL) -> String {
        let name = folder.lastPathComponent
        guard let stem = MeetingNaming.stem(of: name) else {
            return name
        }
        let counter = name.range(of: #" \(\d+\)$"#, options: .regularExpression).map { String(name[$0]) } ?? ""
        return stem + counter
    }
}

/// The model providers the assistant can use and their models, as the
/// helper lists them (`main.js catalog`).
public struct MeetingAssistantCatalog: Decodable, Sendable, Equatable {
    public struct Model: Decodable, Sendable, Equatable, Identifiable {
        public let id: String
        public let name: String
    }

    public struct Provider: Decodable, Sendable, Equatable, Identifiable {
        public let id: String
        public let name: String
        /// An API key for it is set.
        public let configured: Bool
        public let models: [Model]
    }

    public let providers: [Provider]

    public static func load(_ installation: MeetingAssistantInstallation, environment: [String: String]) async throws -> MeetingAssistantCatalog {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let process = installation.process("catalog", environment: environment)
                    let output = Pipe()
                    process.standardOutput = output
                    process.standardError = FileHandle.nullDevice
                    try process.run()
                    let data = output.fileHandleForReading.readDataToEndOfFile()
                    process.waitUntilExit()
                    continuation.resume(returning: try JSONDecoder().decode(MeetingAssistantCatalog.self, from: data))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}

/// The helper process: requests go in as JSON lines, events come out.
final class MeetingAssistantProcess: @unchecked Sendable {
    private let process: Process
    private let input = Pipe()
    private let output = Pipe()
    private let errors = Pipe()
    private let lock = NSLock()
    private var buffer = Data()
    private var errorTail = ""

    init(
        installation: MeetingAssistantInstallation,
        environment: [String: String],
        onEvent: @escaping @Sendable (MeetingAssistantEvent) -> Void,
        onExit: @escaping @Sendable (_ status: Int32, _ lastError: String) -> Void
    ) throws {
        process = installation.process("serve", environment: environment)
        process.standardInput = input
        process.standardOutput = output
        process.standardError = errors
        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard let self, !data.isEmpty else {
                return
            }
            for line in self.lines(adding: data) {
                if let event = MeetingAssistantEvent.parse(line) {
                    onEvent(event)
                }
            }
        }
        errors.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard let self, !data.isEmpty else {
                return
            }
            self.lock.lock()
            self.errorTail = String((self.errorTail + String(decoding: data, as: UTF8.self)).suffix(600))
            self.lock.unlock()
        }
        process.terminationHandler = { [weak self] process in
            guard let self else {
                return
            }
            self.output.fileHandleForReading.readabilityHandler = nil
            self.errors.fileHandleForReading.readabilityHandler = nil
            self.lock.lock()
            let tail = self.errorTail
            self.lock.unlock()
            onExit(process.terminationStatus, tail)
        }
        try process.run()
    }

    private func lines(adding data: Data) -> [String] {
        lock.lock()
        defer { lock.unlock() }
        buffer.append(data)
        var lines: [String] = []
        while let newline = buffer.firstIndex(of: 0x0A) {
            lines.append(String(decoding: buffer[buffer.startIndex..<newline], as: UTF8.self))
            buffer.removeSubrange(buffer.startIndex...newline)
        }
        return lines
    }

    func send(_ request: [String: Any]) {
        guard process.isRunning, var data = try? JSONSerialization.data(withJSONObject: request) else {
            return
        }
        data.append(0x0A)
        try? input.fileHandleForWriting.write(contentsOf: data)
    }

    /// Closes the pipe: the helper stores what it has and exits.
    func stop() {
        try? input.fileHandleForWriting.close()
    }
}

/// The conversation with the assistant about one meeting, for the
/// assistant window.
@MainActor
public final class MeetingAssistantModel: ObservableObject {
    @Published public private(set) var messages: [AssistantMessage] = []
    /// The answer being written.
    @Published public private(set) var streaming = ""
    @Published public private(set) var isBusy = false
    /// What the assistant is doing before it answers ("Reading the transcript…").
    @Published public private(set) var activity: String?
    /// Why the assistant cannot answer now (no model chosen, a failed start).
    @Published public private(set) var problem: String?
    @Published public private(set) var meetingName = ""
    @Published public private(set) var isRecording = false
    @Published public private(set) var hasMeeting = false
    /// The model it runs with ("azure / gpt-5.1"), once it runs.
    @Published public private(set) var modelLabel = ""
    @Published public private(set) var choice: MeetingAssistantSettings.Choice?
    @Published public private(set) var catalog: MeetingAssistantCatalog?
    @Published public private(set) var catalogProblem: String?

    /// Log lines (`diagnostic.info: …`): counts and times only, never text.
    public var onEvent: (String) -> Void = { _ in }
    /// Called before a question goes to the assistant: the owner of the
    /// recorder puts what was said so far into the transcript.
    public var beforeAsk: () -> Void = {}

    private let installation: MeetingAssistantInstallation?
    private var process: MeetingAssistantProcess?
    private var generation = 0
    private var isReady = false
    private var folder: URL?
    private var openedKey: String?
    private var pendingQuestion: (id: String, text: String)?
    private var askedAt: Date?
    private var nextID = 0

    public init(installation: MeetingAssistantInstallation? = .bundled()) {
        self.installation = installation
        choice = (try? MeetingAssistantSettings.environment()).flatMap(MeetingAssistantSettings.choice(in:))
    }

    public var isAvailable: Bool {
        installation != nil
    }

    // MARK: - The meeting

    /// The meeting the assistant looks at: the one being recorded, or the
    /// last one. Its conversation is opened when the assistant runs.
    public func setMeeting(folder: URL?, recording: Bool) {
        let changed = folder.map(MeetingAssistantSettings.key(for:)) != self.folder.map(MeetingAssistantSettings.key(for:))
        self.folder = folder
        isRecording = recording
        hasMeeting = folder != nil
        meetingName = folder?.lastPathComponent ?? ""
        guard let folder else {
            return
        }
        if changed {
            messages = []
            streaming = ""
            openedKey = nil
            openMeetingIfReady()
        } else {
            process?.send(["type": "meeting", "folder": folder.path, "recording": recording])
        }
    }

    /// The meeting was named: its folder moved.
    public func folderRenamed(from old: URL, to new: URL) {
        if folder?.standardizedFileURL == old.standardizedFileURL {
            setMeeting(folder: new, recording: isRecording)
        }
    }

    private func openMeetingIfReady() {
        guard isReady, let folder else {
            return
        }
        let key = MeetingAssistantSettings.key(for: folder)
        guard openedKey != key else {
            return
        }
        process?.send(["type": "open", "folder": folder.path, "key": key, "recording": isRecording])
    }

    // MARK: - Asking

    public func ask(_ raw: String) {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, hasMeeting else {
            return
        }
        beforeAsk()
        append(.user, text)
        isBusy = true
        activity = "Thinking…"
        streaming = ""
        askedAt = Date()
        let question = (id: UUID().uuidString, text: text)
        onEvent("diagnostic.info: [untype] assistant asked (\(text.count) characters)")
        if isReady, openedKey != nil {
            process?.send(["type": "ask", "id": question.id, "text": question.text])
        } else {
            pendingQuestion = question
            start()
        }
    }

    public func stop() {
        process?.send(["type": "abort"])
    }

    /// Starts the helper when it does not run (the window opened, or a
    /// question was asked).
    public func start() {
        guard process == nil else {
            openMeetingIfReady()
            return
        }
        guard let installation else {
            fail("The assistant is not part of this build of untype.")
            return
        }
        let environment: [String: String]
        do {
            environment = try MeetingAssistantSettings.environment()
        } catch {
            fail("The assistant's settings cannot be read: \(error.localizedDescription)")
            return
        }
        choice = MeetingAssistantSettings.choice(in: environment)
        guard choice != nil else {
            fail("Choose the assistant's model first.")
            return
        }
        problem = nil
        generation += 1
        let generation = generation
        do {
            process = try MeetingAssistantProcess(
                installation: installation,
                environment: environment,
                onEvent: { [weak self] event in
                    Task { @MainActor in self?.handle(event, generation: generation) }
                },
                onExit: { [weak self] status, lastError in
                    Task { @MainActor in self?.exited(status: status, lastError: lastError, generation: generation) }
                }
            )
        } catch {
            fail("The assistant could not be started: \(error.localizedDescription)")
        }
    }

    /// Stops the helper (the app quits, or the model was changed).
    public func shutDown() {
        generation += 1
        process?.stop()
        process = nil
        isReady = false
        openedKey = nil
        isBusy = false
        activity = nil
    }

    // MARK: - Settings

    public func loadCatalog() {
        guard catalog == nil, let installation else {
            return
        }
        Task {
            do {
                let loaded = try await MeetingAssistantCatalog.load(installation, environment: MeetingAssistantSettings.environment())
                catalog = loaded
                catalogProblem = nil
            } catch {
                catalogProblem = "The list of models could not be read: \(error.localizedDescription)"
            }
        }
    }

    /// Saves the assistant's model; the helper restarts with it on the
    /// next question.
    public func choose(provider: String, model: String) {
        let chosen = MeetingAssistantSettings.Choice(provider: provider, model: model)
        do {
            try MeetingAssistantSettings.save(chosen)
            choice = chosen
            problem = nil
            onEvent("config.saved: assistant model \(provider) / \(model)")
            let hadProcess = process != nil
            shutDown()
            if hadProcess {
                start()
            }
        } catch {
            problem = "The assistant's model could not be saved: \(error.localizedDescription)"
        }
    }

    // MARK: - Events

    private func handle(_ event: MeetingAssistantEvent, generation: Int) {
        guard generation == self.generation else {
            return
        }
        switch event {
        case .ready(let provider, let model):
            isReady = true
            modelLabel = "\(provider) / \(model)"
            onEvent("diagnostic.info: [untype] assistant started (\(provider) / \(model))")
            openMeetingIfReady()
        case .opened(let key, let history):
            openedKey = key
            if let pendingQuestion {
                // The question asked before the helper ran is already shown.
                self.pendingQuestion = nil
                let shown = messages
                messages = history.enumerated().map { AssistantMessage(id: $0.offset, role: $0.element.role, text: $0.element.text) }
                nextID = messages.count
                for message in shown where message.role == .user && message.text == pendingQuestion.text {
                    append(.user, message.text)
                    break
                }
                process?.send(["type": "ask", "id": pendingQuestion.id, "text": pendingQuestion.text])
            } else {
                messages = history
                nextID = history.count
            }
        case .runStart:
            isBusy = true
            streaming = ""
            activity = activity ?? "Thinking…"
        case .tool(let name):
            activity = Self.activity(forTool: name)
        case .text(let delta, let reset):
            streaming = reset ? delta : streaming + delta
            activity = nil
        case .runEnd(let failure):
            let answer = streaming.trimmingCharacters(in: .whitespacesAndNewlines)
            if !answer.isEmpty {
                append(.assistant, answer)
            }
            if let failure {
                append(.note, failure == "aborted" ? "Stopped." : "The assistant could not answer: \(failure)")
            }
            let seconds = askedAt.map { String(format: "%.1f", Date().timeIntervalSince($0)) } ?? "?"
            onEvent(failure == nil
                ? "diagnostic.info: [untype] assistant answered (\(answer.count) characters, \(seconds) s)"
                : "diagnostic.warning: [untype] assistant did not answer after \(seconds) s: \(failure ?? "")")
            streaming = ""
            isBusy = false
            activity = nil
            askedAt = nil
        case .error(let message):
            append(.note, message)
            isBusy = false
            activity = nil
            onEvent("diagnostic.warning: [untype] assistant: \(message)")
        case .fatal(let message):
            fail(message)
        case .extract(let id, let path):
            extract(id: id, path: path)
        }
    }

    /// The helper asked for a document's text: only files of the meeting
    /// it looks at are read, off the main thread.
    private func extract(id: String, path: String) {
        let url = URL(fileURLWithPath: path).standardizedFileURL
        guard let folder = folder?.standardizedFileURL, url.path.hasPrefix(folder.path + "/") else {
            process?.send(["type": "extracted", "id": id, "error": "the file is not in the meeting folder"])
            return
        }
        let kind = url.pathExtension.lowercased()
        let generation = generation
        Task { [weak self] in
            let result = await Task.detached(priority: .userInitiated) { () -> Result<String, MeetingDocumentText.Failure> in
                do {
                    return .success(try MeetingDocumentText.extract(url))
                } catch {
                    return .failure(.init(errorDescription: error.localizedDescription))
                }
            }.value
            guard let self, generation == self.generation else {
                return
            }
            switch result {
            case .success(let text):
                self.process?.send(["type": "extracted", "id": id, "text": text])
                self.onEvent("diagnostic.info: [untype] assistant: a .\(kind) attachment was read (\(text.count) characters)")
            case .failure(let failure):
                let message = failure.errorDescription ?? "the document cannot be read"
                self.process?.send(["type": "extracted", "id": id, "error": message])
                self.onEvent("diagnostic.warning: [untype] assistant: a .\(kind) attachment could not be read: \(message)")
            }
        }
    }

    private func exited(status: Int32, lastError: String, generation: Int) {
        guard generation == self.generation else {
            return
        }
        process = nil
        isReady = false
        openedKey = nil
        isBusy = false
        activity = nil
        if problem == nil, status != 0 {
            fail("The assistant stopped (status \(status)). Ask again to restart it.")
        }
        if status != 0 {
            let lastLine = lastError.split(separator: "\n").last.map(String.init) ?? ""
            onEvent("diagnostic.warning: [untype] assistant process ended with status \(status): \(lastLine)")
        }
    }

    private func fail(_ message: String) {
        problem = message
        isBusy = false
        activity = nil
        pendingQuestion = nil
        onEvent("diagnostic.warning: [untype] assistant: \(message)")
    }

    private func append(_ role: AssistantMessage.Role, _ text: String) {
        messages.append(AssistantMessage(id: nextID, role: role, text: text))
        nextID += 1
    }

    static func activity(forTool name: String) -> String {
        switch name {
        case "read_transcript": return "Reading the transcript…"
        case "search_transcript": return "Searching the transcript…"
        case "read_attachment": return "Looking at an attachment…"
        case "meeting_overview": return "Looking at the meeting…"
        default: return "Working…"
        }
    }
}

/// The assistant window. Opened from the menu-bar dropdown ("Meeting
/// assistant", ⌘4) and from the transcription window.
@MainActor
final class UntypeAssistantWindowController: NSObject {
    private static let frameAutosaveName = "untype.assistantWindow.v1"
    private let model: MeetingAssistantModel
    private var window: NSWindow?

    init(model: MeetingAssistantModel) {
        self.model = model
    }

    /// The user types in this window now.
    var isKey: Bool {
        NSApp.isActive && window?.isKeyWindow == true
    }

    func show() {
        let window = self.window ?? makeWindow()
        self.window = window
        model.start()
        window.showOnActiveDesktop()
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 620),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Meeting assistant"
        window.contentMinSize = NSSize(width: 380, height: 300)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: UntypeAssistantView(model: model))
        if !window.setFrameUsingName(Self.frameAutosaveName) {
            window.center()
        }
        window.setFrameAutosaveName(Self.frameAutosaveName)
        return window
    }
}

/// The choice of the assistant's model: provider and model, from the
/// helper's catalog. In the assistant window and in Settings → Meetings.
struct MeetingAssistantModelPicker: View {
    @ObservedObject var model: MeetingAssistantModel
    @State private var provider = ""
    @State private var modelID = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let catalog = model.catalog {
                Picker("Provider", selection: $provider) {
                    Text("Choose…").tag("")
                    ForEach(catalog.providers) { provider in
                        Text(provider.configured ? provider.name : "\(provider.name) (no API key)").tag(provider.id)
                    }
                }
                Picker("Model", selection: $modelID) {
                    Text("Choose…").tag("")
                    ForEach(catalog.providers.first { $0.id == provider }?.models ?? []) { item in
                        Text(item.name == item.id ? item.id : "\(item.name) (\(item.id))").tag(item.id)
                    }
                }
                .disabled(provider.isEmpty)
                HStack {
                    Button("Use this model") {
                        model.choose(provider: provider, model: modelID)
                    }
                    .disabled(provider.isEmpty || modelID.isEmpty || isCurrent)
                    if let choice = model.choice {
                        Text("Now: \(choice.provider) / \(choice.model)")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
            } else if let problem = model.catalogProblem {
                Text(problem)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            } else if model.isAvailable {
                ProgressView()
                    .controlSize(.small)
            } else {
                Text("The assistant is not part of this build of untype.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear {
            model.loadCatalog()
            syncFromChoice()
        }
        .onChange(of: model.choice) { _, _ in
            syncFromChoice()
        }
        .onChange(of: provider) { _, new in
            if model.catalog?.providers.first(where: { $0.id == new })?.models.contains(where: { $0.id == modelID }) != true {
                modelID = ""
            }
        }
    }

    private var isCurrent: Bool {
        model.choice == MeetingAssistantSettings.Choice(provider: provider, model: modelID)
    }

    private func syncFromChoice() {
        if let choice = model.choice {
            provider = choice.provider
            modelID = choice.model
        }
    }
}

struct UntypeAssistantView: View {
    private static let bottomID = "assistant-bottom"

    @ObservedObject var model: MeetingAssistantModel
    @State private var draft = ""
    @State private var showsModel = false
    @FocusState private var inputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            Divider()
            conversation
            Divider()
            input
                .padding(10)
        }
        .frame(minWidth: 380, minHeight: 300)
        .onAppear { inputFocused = true }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(model.isRecording ? Color.red : Color.secondary.opacity(0.5))
                .frame(width: 7, height: 7)
            Text(headerText)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 6)
            Button {
                showsModel.toggle()
            } label: {
                Label(model.choice.map { $0.model } ?? "Choose a model", systemImage: "cpu")
                    .font(.system(size: 11))
            }
            .controlSize(.small)
            .help("The model the assistant answers with")
            .popover(isPresented: $showsModel, arrowEdge: .bottom) {
                MeetingAssistantModelPicker(model: model)
                    .padding(14)
                    .frame(width: 340)
            }
        }
    }

    private var headerText: String {
        guard model.hasMeeting else {
            return "No meeting"
        }
        return (model.isRecording ? "Recording · " : "Ended · ") + model.meetingName
    }

    private var conversation: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    if let problem = model.problem {
                        notice(problem)
                        if model.choice == nil, model.isAvailable {
                            MeetingAssistantModelPicker(model: model)
                                .padding(10)
                                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.secondary.opacity(0.08)))
                        }
                    } else if model.messages.isEmpty, !model.isBusy {
                        Text(emptyText)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.top, 40)
                            .padding(.horizontal, 20)
                    }
                    ForEach(model.messages) { message in
                        bubble(message.role, message.text)
                    }
                    if !model.streaming.isEmpty {
                        bubble(.assistant, model.streaming)
                    }
                    if let activity = model.activity {
                        HStack(spacing: 6) {
                            ProgressView()
                                .controlSize(.small)
                            Text(activity)
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                    }
                    Color.clear
                        .frame(height: 1)
                        .id(Self.bottomID)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color(nsColor: .textBackgroundColor))
            .onChange(of: model.messages.count) { _, _ in proxy.scrollTo(Self.bottomID, anchor: .bottom) }
            .onChange(of: model.streaming) { _, _ in proxy.scrollTo(Self.bottomID, anchor: .bottom) }
            .onChange(of: model.activity) { _, _ in proxy.scrollTo(Self.bottomID, anchor: .bottom) }
        }
    }

    private var emptyText: String {
        if !model.hasMeeting {
            return "Start a meeting recording, then ask about it here."
        }
        return model.isRecording
            ? "Ask about the meeting while it goes on: what was said, what was decided, what an attachment shows."
            : "Ask about this meeting: what was said, what was decided, what an attachment shows."
    }

    private func notice(_ text: String) -> some View {
        Label(text, systemImage: "exclamationmark.triangle")
            .font(.system(size: 12))
            .foregroundStyle(UntypeDesignTokens.accentAmber)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func bubble(_ role: AssistantMessage.Role, _ text: String) -> some View {
        switch role {
        case .user:
            HStack {
                Spacer(minLength: 40)
                Text(text)
                    .font(.system(size: 13))
                    .textSelection(.enabled)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.accentColor.opacity(0.18)))
            }
        case .assistant:
            Text(Self.rendered(text))
                .font(.system(size: 13))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .note:
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// The answer with its inline Markdown (bold, italics, code, links);
    /// lines and lists stay as written.
    static func rendered(_ text: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
    }

    private var input: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField("Ask about the meeting", text: $draft, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .lineLimit(1...6)
                .focused($inputFocused)
                .onSubmit(send)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.secondary.opacity(0.1)))
                .disabled(!model.hasMeeting)
            if model.isBusy {
                Button(action: model.stop) {
                    Image(systemName: "stop.circle.fill")
                        .font(.system(size: 22))
                }
                .buttonStyle(.plain)
                .help("Stop the answer")
            } else {
                Button(action: send) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 22))
                }
                .buttonStyle(.plain)
                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !model.hasMeeting)
                .help("Ask (Return)")
            }
        }
    }

    private func send() {
        let text = draft
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, model.hasMeeting, !model.isBusy else {
            return
        }
        draft = ""
        model.ask(text)
    }
}
#endif
