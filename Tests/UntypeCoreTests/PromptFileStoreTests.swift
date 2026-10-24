import Foundation
import Testing
@testable import UntypeCore

@Test func promptStoreDescribesEveryPromptFileWithItsDefault() {
    let described = Dictionary(uniqueKeysWithValues: PromptFileStore.descriptors.map { ($0.name, $0) })
    #expect(described.count == UntypePromptDefaults.promptFiles.count)
    for file in UntypePromptDefaults.promptFiles {
        #expect(described[file.name]?.defaultContent == file.defaultContent)
        #expect(described[file.name]?.required == file.required)
    }
}

@Test func promptStoreRejectsWhatSessionStartWouldReject() throws {
    let template = try #require(PromptFileStore.descriptor(named: "003-translation-user-template.txt"))
    #expect(PromptFileStore.validationError("Translate {text}", for: template)?.contains("{target_language}") == true)
    #expect(PromptFileStore.validationError("To {target_language}: {text}", for: template) == nil)

    let system = try #require(PromptFileStore.descriptor(named: "001-refinement-system.txt"))
    #expect(PromptFileStore.validationError("  \n", for: system) != nil)

    let context = try #require(PromptFileStore.descriptor(named: "004-soniox-transcription-context.txt"))
    #expect(PromptFileStore.validationError("", for: context) == nil)

    let keyterms = try #require(PromptFileStore.descriptor(named: "006-elevenlabs-keyterms.txt"))
    #expect(PromptFileStore.validationError("untype\nSoniox", for: keyterms) == nil)
    #expect(PromptFileStore.validationError("a keyterm that is far too long", for: keyterms) != nil)
}

@Test func promptStoreWritesPrivateFilesThatSessionStartLoads() throws {
    let temp = TemporaryDirectory()
    let store = PromptFileStore(directory: PromptFileStore.userDirectory(home: temp.url))
    try store.provisionMissing()
    let refinement = try #require(PromptFileStore.descriptor(named: "001-refinement-system.txt"))

    try store.write("Clean the transcript. Reply with the text only.", for: refinement)

    let attributes = try FileManager.default.attributesOfItem(atPath: store.url(for: refinement).path)
    #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
    let config = try ConfigResolver(cwd: temp.url, home: temp.url, shell: [:])
        .resolve(argv: ["--api-key", "test-key", "--no-refine"])
    #expect(config.prompts.refinementSystemPrompt == "Clean the transcript. Reply with the text only.")

    let template = try #require(PromptFileStore.descriptor(named: "003-translation-user-template.txt"))
    #expect(throws: UntypeError.self) {
        try store.write("missing placeholders", for: template)
    }
    #expect(try store.read(template) == template.defaultContent)
}

@MainActor
@Test func promptWatcherReportsChangedFiles() throws {
    let temp = TemporaryDirectory()
    let store = PromptFileStore(directory: PromptFileStore.userDirectory(home: temp.url))
    try store.provisionMissing()
    var reported: [[String]] = []
    let watcher = PromptFileWatcher(store: store) { reported.append($0) }

    watcher.check()
    #expect(reported.isEmpty)

    let translation = try #require(PromptFileStore.descriptor(named: "002-translation-system.txt"))
    try store.write("Translate. Reply with the translation only, nothing else at all.", for: translation)
    watcher.check()
    #expect(reported == [["002-translation-system.txt"]])

    watcher.check()
    #expect(reported.count == 1)
}

private final class TemporaryDirectory {
    let url: URL

    init() {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("untype-s-tests")
            .appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }
}
