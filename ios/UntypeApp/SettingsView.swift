import SwiftUI
import UntypeCore

struct SettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.dismiss) private var dismiss
    @State private var newWord = ""
    @State private var wordProblem: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    KeyField(title: "Soniox key", name: AppSettings.sonioxKeyName)
                    TextField("Languages (for example: el, en)", text: $settings.languages)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("Speech")
                } footer: {
                    Text("Soniox writes what you say. The languages are the ones you speak, as two-letter codes separated by commas.")
                }

                Section {
                    Picker("Provider", selection: $settings.providerRaw) {
                        Text("None").tag("")
                        ForEach(ModelProvider.allCases) { provider in
                            Text(provider.title).tag(provider.rawValue)
                        }
                    }
                    if let provider = settings.provider {
                        KeyField(title: "\(provider.title) key", name: provider.keyName)
                            .id(provider.keyName)
                        TextField(provider == .azureOpenAI ? "Deployment" : "Model", text: $settings.modelName)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        if provider.needsEndpoint {
                            TextField("\(provider.endpointLabel) (\(provider.endpointExample))", text: $settings.endpoint)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .keyboardType(.URL)
                        }
                        if provider == .azureOpenAI {
                            TextField("API version", text: $settings.azureAPIVersion)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                        }
                    }
                } header: {
                    Text("Refine and Translate")
                } footer: {
                    Text("Needed only for Refine and Translate. Dictation works without it.")
                }

                Section {
                    HStack {
                        TextField("New word", text: $newWord)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .onSubmit(addWord)
                        Button("Add", action: addWord)
                            .disabled(newWord.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    if let problem = wordProblem ?? settings.dictionaryProblem {
                        Text(problem)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                    ForEach(settings.dictionary.entries) { entry in
                        Text(entry.term)
                    }
                    .onDelete { offsets in
                        for index in offsets {
                            settings.removeWord(settings.dictionary.entries[index].term)
                        }
                    }
                } header: {
                    Text("Dictionary")
                } footer: {
                    Text("Names, abbreviations and terms that are not heard right, written the way they must be written. Swipe a word to remove it.")
                }

                Section {
                    LabeledContent("Version", value: Self.version)
                } footer: {
                    Text("Keys are kept in this device's Keychain.")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func addWord() {
        wordProblem = settings.addWord(newWord)
        if wordProblem == nil {
            newWord = ""
        }
    }

    private static var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(short) · build \(build)"
    }
}

/// A key of a provider: shown as dots, stored in the Keychain when the
/// field is left or submitted.
private struct KeyField: View {
    let title: String
    let name: String
    @State private var value = ""
    @State private var stored = false
    @State private var problem: String?
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                SecureField(stored ? "\(title) (stored)" : title, text: $value)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($focused)
                    .onSubmit(save)
                if stored {
                    Button(role: .destructive) {
                        value = ""
                        store("")
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Remove the \(title)")
                }
            }
            if let problem {
                Text(problem)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
        .onAppear {
            stored = KeychainStore.read(name) != nil
        }
        .onChange(of: focused) { _, isFocused in
            if !isFocused {
                save()
            }
        }
        .onDisappear(perform: save)
    }

    private func save() {
        guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }
        store(value)
        value = ""
    }

    private func store(_ newValue: String) {
        do {
            try KeychainStore.write(name, newValue)
            stored = KeychainStore.read(name) != nil
            problem = nil
        } catch {
            problem = error.localizedDescription
        }
    }
}
