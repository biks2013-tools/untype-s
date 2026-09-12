import Foundation
import Testing
@testable import UntypeCore

private final class EditorTemporaryDirectory {
    let url: URL
    init() {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("untype-dotenv-editor-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }
    deinit { try? FileManager.default.removeItem(at: url) }
}

@Test func dotenvEditorActivatesCommentedTemplateLineInPlace() {
    let template = """
    # Soniox API key. Required when UNTYPE_STT_PROVIDER is soniox (the default).
    # SONIOX_API_KEY=

    # ElevenLabs API key.
    # ELEVENLABS_API_KEY=

    """
    let result = DotenvEditor.apply(["SONIOX_API_KEY": "sk_live_123"], to: template)
    #expect(result == """
    # Soniox API key. Required when UNTYPE_STT_PROVIDER is soniox (the default).
    SONIOX_API_KEY=sk_live_123

    # ElevenLabs API key.
    # ELEVENLABS_API_KEY=

    """)
}

@Test func dotenvEditorReplacesActiveLineAndDropsDuplicates() {
    let contents = """
    # header
    AZURE_OPENAI_DEPLOYMENT=gpt-5.1
    OTHER=keep me
    export AZURE_OPENAI_DEPLOYMENT=gpt-4.1-mini
    """
    let result = DotenvEditor.apply(["AZURE_OPENAI_DEPLOYMENT": "gpt-5.4"], to: contents)
    #expect(result == """
    # header
    AZURE_OPENAI_DEPLOYMENT=gpt-5.4
    OTHER=keep me
    """)
}

@Test func dotenvEditorAppendsUnknownKeyAndUnsetsByCommenting() {
    let contents = "SONIOX_API_KEY=abc\n"
    let appended = DotenvEditor.apply(["GOOGLE_API_KEY": "g-1"], to: contents)
    #expect(appended == "SONIOX_API_KEY=abc\n\nGOOGLE_API_KEY=g-1\n")

    let unset = DotenvEditor.apply(["SONIOX_API_KEY": "   "], to: appended)
    #expect(unset == "# SONIOX_API_KEY=\n\nGOOGLE_API_KEY=g-1\n")

    // Unsetting a key that is not active leaves the file untouched.
    #expect(DotenvEditor.apply(["ELEVENLABS_API_KEY": ""], to: unset) == unset)
}

@Test func dotenvEditorQuotesValuesTheParserWouldMangle() throws {
    let result = DotenvEditor.apply(
        ["AZURE_OPENAI_ENDPOINT": "https://x.openai.azure.com/#frag", "GOOGLE_API_KEY": " padded "],
        to: ""
    )
    let parsed = try Dotenv.parse(result, path: "test")
    #expect(parsed["AZURE_OPENAI_ENDPOINT"] == "https://x.openai.azure.com/#frag")
    #expect(parsed["GOOGLE_API_KEY"] == "padded")
}

@Test func dotenvEditorUpsertCreatesFileFromTemplateWithPrivatePermissions() throws {
    let temp = EditorTemporaryDirectory()
    let url = DotenvEditor.userEnvURL(home: temp.url)
    #expect(!FileManager.default.fileExists(atPath: url.path))

    try DotenvEditor.upsert(["SONIOX_API_KEY": "sk_test"], into: url)

    let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
    #expect((attributes[.posixPermissions] as? Int) == 0o600)
    let folderAttributes = try FileManager.default.attributesOfItem(atPath: url.deletingLastPathComponent().path)
    #expect((folderAttributes[.posixPermissions] as? Int) == 0o700)

    let written = try String(contentsOf: url, encoding: .utf8)
    #expect(written.contains("\nSONIOX_API_KEY=sk_test\n"))
    #expect(written.contains("# ELEVENLABS_API_KEY="))
    #expect(written.hasPrefix("# untype configuration"))
    #expect(try DotenvEditor.read(url) == ["SONIOX_API_KEY": "sk_test"])

    // The resolver picks the value up from the user-level file.
    let resolver = ConfigResolver(cwd: temp.url, home: temp.url, shell: [:])
    let config = try resolver.resolve(argv: ["--no-refine"])
    #expect(config.apiKey == "sk_test")
}

@Test func dotenvEditorUpsertPreservesUnrelatedContentOfExistingFile() throws {
    let temp = EditorTemporaryDirectory()
    let url = DotenvEditor.userEnvURL(home: temp.url)
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try "# my notes\nUNTYPE_LANGUAGES=el,en\nSONIOX_API_KEY=old\n".write(to: url, atomically: true, encoding: .utf8)

    try DotenvEditor.upsert(["SONIOX_API_KEY": "new", "ELEVENLABS_API_KEY": "xi"], into: url)

    #expect(try String(contentsOf: url, encoding: .utf8) == "# my notes\nUNTYPE_LANGUAGES=el,en\nSONIOX_API_KEY=new\n\nELEVENLABS_API_KEY=xi\n")
}
