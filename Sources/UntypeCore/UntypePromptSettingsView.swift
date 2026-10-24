import AppKit
import SwiftUI

/// Settings → Prompts: the prompt files in `~/.tool-agents/untype/prompts/`,
/// editable in place. A save is hot-reloaded: the model's `PromptFileWatcher`
/// sees the change and restarts an idle warm push-to-talk session, so the next
/// turn uses the new prompt. Files changed outside untype refresh the editor
/// unless it holds unsaved edits.
@MainActor
struct UntypePromptSettingsView: View {
    @ObservedObject var model: UntypeUIModel
    @State private var selection = PromptFileStore.descriptors[0].name
    /// Contents on disk, as last read.
    @State private var saved: [String: String] = [:]
    /// Editor contents; differs from `saved` while there are unsaved edits.
    @State private var drafts: [String: String] = [:]
    @State private var loadError: String?
    @State private var saveError: String?
    @State private var lastSavedName: String?

    var body: some View {
        HStack(spacing: 0) {
            fileList
                .frame(width: 230)
            Divider()
            editor
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear(perform: loadAll)
        .onChange(of: model.promptRevision) { _, _ in
            reloadFromDisk()
        }
    }

    private var store: PromptFileStore { model.promptStore }

    private var descriptor: PromptFileDescriptor {
        PromptFileStore.descriptor(named: selection) ?? PromptFileStore.descriptors[0]
    }

    // MARK: File list

    private var fileList: some View {
        List(selection: $selection) {
            ForEach(PromptFileDescriptor.Group.allCases, id: \.self) { group in
                Section(group.rawValue) {
                    ForEach(PromptFileStore.descriptors.filter { $0.group == group }) { file in
                        HStack(spacing: 6) {
                            Text(shortTitle(file))
                                .font(.system(size: 12))
                                .lineLimit(1)
                            Spacer(minLength: 4)
                            if isDirty(file.name) {
                                Circle()
                                    .fill(UntypeDesignTokens.accentAmber)
                                    .frame(width: 6, height: 6)
                                    .help("Unsaved changes")
                            }
                        }
                        .tag(file.name)
                    }
                }
            }
        }
        .listStyle(.sidebar)
    }

    private func shortTitle(_ file: PromptFileDescriptor) -> String {
        file.title.components(separatedBy: " — ").last ?? file.title
    }

    // MARK: Editor

    private var editor: some View {
        let file = descriptor
        let draft = drafts[file.name] ?? ""
        let problem = PromptFileStore.validationError(draft, for: file)
        return VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(file.title)
                    .font(.system(size: 15, weight: .semibold))
                Text(file.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    Text(store.url(for: file).path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Button {
                        NSWorkspace.shared.activateFileViewerSelecting([store.url(for: file)])
                    } label: {
                        Image(systemName: "folder")
                    }
                    .buttonStyle(.borderless)
                    .help("Reveal in Finder")
                }
            }

            if !file.placeholders.isEmpty || !file.required || file.maxCharacters != nil || file.maxLines != nil {
                HStack(spacing: 6) {
                    ForEach(file.placeholders, id: \.self) { placeholder in
                        UntypeKbd(placeholder)
                            .opacity(draft.contains(placeholder) ? 1 : 0.45)
                    }
                    Text(constraintNote(file))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            TextEditor(text: draftBinding(file.name))
                .font(.system(size: 12.5, design: .monospaced))
                .scrollContentBackground(.hidden)
                .padding(6)
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(problem == nil ? Color.primary.opacity(0.1) : UntypeDesignTokens.warnGold.opacity(0.8))
                )

            HStack(spacing: 8) {
                statusText(file: file, problem: problem)
                Spacer(minLength: 8)
                Button("Reset to Default") {
                    drafts[file.name] = file.defaultContent
                    saveError = nil
                }
                .disabled(draft == file.defaultContent)
                .help("Put the built-in prompt in the editor; Save to apply it")
                Button("Revert") {
                    drafts[file.name] = saved[file.name] ?? ""
                    saveError = nil
                }
                .disabled(!isDirty(file.name))
                Button("Save") {
                    save(file)
                }
                .keyboardShortcut("s", modifiers: [.command])
                .buttonStyle(.borderedProminent)
                .tint(UntypeDesignTokens.accentAmber)
                .disabled(!isDirty(file.name) || problem != nil)
            }
            .controlSize(.small)
        }
        .padding(16)
    }

    @ViewBuilder
    private func statusText(file: PromptFileDescriptor, problem: String?) -> some View {
        if let loadError {
            Label(loadError, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(UntypeDesignTokens.warnGold)
                .font(.caption)
        } else if let saveError {
            Label(saveError, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(UntypeDesignTokens.warnGold)
                .font(.caption)
        } else if let problem {
            Label(problem, systemImage: "exclamationmark.triangle")
                .foregroundStyle(UntypeDesignTokens.warnGold)
                .font(.caption)
        } else if isDirty(file.name) {
            Text("Unsaved changes · \(drafts[file.name]?.count ?? 0) characters")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else if lastSavedName == file.name {
            Label("Saved — the next push-to-talk turn uses it", systemImage: "checkmark.circle.fill")
                .foregroundStyle(UntypeDesignTokens.successGreen)
                .font(.caption)
        } else {
            Text("\(drafts[file.name]?.count ?? 0) characters · hot-reloaded on save")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func constraintNote(_ file: PromptFileDescriptor) -> String {
        var parts: [String] = []
        if !file.placeholders.isEmpty {
            parts.append("required placeholders")
        }
        if !file.required {
            parts.append("optional — leave empty to send nothing")
        }
        if let maxCharacters = file.maxCharacters {
            parts.append("max \(maxCharacters) characters")
        }
        if let maxLines = file.maxLines, let maxLineCharacters = file.maxLineCharacters {
            parts.append("max \(maxLines) lines of \(maxLineCharacters) characters")
        }
        return parts.joined(separator: " · ")
    }

    // MARK: State

    private func draftBinding(_ name: String) -> Binding<String> {
        Binding(
            get: { drafts[name] ?? "" },
            set: { value in
                drafts[name] = value
                saveError = nil
                if lastSavedName == name {
                    lastSavedName = nil
                }
            }
        )
    }

    private func isDirty(_ name: String) -> Bool {
        (drafts[name] ?? "") != (saved[name] ?? "")
    }

    private func loadAll() {
        do {
            try store.provisionMissing()
            loadError = nil
        } catch {
            loadError = error.localizedDescription
        }
        var nextSaved: [String: String] = [:]
        for file in PromptFileStore.descriptors {
            nextSaved[file.name] = (try? store.read(file)) ?? ""
        }
        // Keep unsaved edits from an earlier visit to the tab.
        for file in PromptFileStore.descriptors where drafts[file.name] == nil || drafts[file.name] == saved[file.name] {
            drafts[file.name] = nextSaved[file.name]
        }
        saved = nextSaved
    }

    /// A file changed on disk: take the new contents, except where the editor
    /// holds unsaved edits.
    private func reloadFromDisk() {
        var nextSaved: [String: String] = [:]
        for file in PromptFileStore.descriptors {
            nextSaved[file.name] = (try? store.read(file)) ?? ""
        }
        for file in PromptFileStore.descriptors where !isDirty(file.name) {
            drafts[file.name] = nextSaved[file.name]
        }
        saved = nextSaved
    }

    private func save(_ file: PromptFileDescriptor) {
        let content = drafts[file.name] ?? ""
        do {
            try store.write(content, for: file)
            saved[file.name] = content
            saveError = nil
            lastSavedName = file.name
        } catch {
            saveError = error.localizedDescription
        }
    }
}
