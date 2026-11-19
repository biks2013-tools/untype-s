import Foundation
import Testing
@testable import UntypeCore

// plan-073: the user's dictionary of names, abbreviations and terms.

@Test func aWordIsAddedOnceAsTyped() throws {
    var dictionary = UserDictionary()
    try dictionary.add("  BikS2013 ")
    try dictionary.add("Claude   Code")
    #expect(dictionary.terms == ["BikS2013", "Claude Code"])
    #expect(throws: UntypeError.self) { try dictionary.add("biks2013") }
    #expect(throws: UntypeError.self) { try dictionary.add("   ") }
    #expect(throws: UntypeError.self) { try dictionary.add(String(repeating: "a", count: 61)) }
    dictionary.remove("BikS2013")
    #expect(dictionary.terms == ["Claude Code"])
}

@Test func whatAWordIsHeardAsIsStoredOnce() throws {
    var dictionary = UserDictionary()
    try dictionary.add("biks")
    try dictionary.add("cmux")
    #expect(dictionary.noteHeard("Biks.", for: "biks") == .correct)
    #expect(dictionary.noteHeard(" “Bix”. ", for: "biks") == .added("Bix"))
    #expect(dictionary.noteHeard("bix", for: "biks") == .known("bix"))
    #expect(dictionary.noteHeard("bix", for: "cmux") == .takenBy("biks"))
    #expect(dictionary.noteHeard("biks", for: "cmux") == .takenBy("biks"))
    #expect(dictionary.entries[0].heardAs == ["Bix"])
    dictionary.removeHeard("Bix", for: "biks")
    #expect(dictionary.entries[0].heardAs.isEmpty)
}

@Test func recognisedTextIsRewrittenWithWholeWordsOnly() {
    let corrector = DictionaryCorrector(UserDictionary(entries: [
        DictionaryEntry(term: "biks", heardAs: ["bix", "μπικς"]),
        DictionaryEntry(term: "BikS2013", heardAs: ["bix 2013", "biks 2013"]),
        DictionaryEntry(term: "cmux", heardAs: ["see mux"])
    ]))
    #expect(corrector.apply("Το Bix είναι ο λογαριασμός, όχι το bixby.") == "Το biks είναι ο λογαριασμός, όχι το bixby.")
    #expect(corrector.apply("στείλ' το στο μπικς.") == "στείλ' το στο biks.")
    // The longer form wins, and spaces between its words may vary.
    #expect(corrector.apply("user Bix  2013, repo biks 2013") == "user BikS2013, repo BikS2013")
    // The word itself gets its own capitals.
    #expect(corrector.apply("BIKS2013 and CMUX") == "BikS2013 and cmux")
    #expect(corrector.apply("I can See Mux now") == "I can cmux now")
    #expect(corrector.apply("nothing to change") == "nothing to change")
}

@Test func anEmptyDictionaryChangesNothing() {
    let corrector = DictionaryCorrector(.empty)
    #expect(corrector.isEmpty)
    #expect(corrector.apply("as it is") == "as it is")
}

@Test func theDictionaryIsSavedForTheUserOnlyAndReadBack() throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("untype-dictionary-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: folder) }
    let url = folder.appendingPathComponent("dictionary.json")
    #expect(try UserDictionaryStore.load(from: url) == .empty)
    var dictionary = UserDictionary()
    try dictionary.add("BikS2013")
    _ = dictionary.noteHeard("bix 2013", for: "BikS2013")
    try UserDictionaryStore.save(dictionary, to: url)
    #expect(try UserDictionaryStore.load(from: url) == dictionary)
    let mode = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber
    #expect(mode?.intValue == 0o600)
    try Data("not a dictionary".utf8).write(to: url)
    #expect(throws: UntypeError.self) { try UserDictionaryStore.load(from: url) }
}

@Test func elevenLabsGetsTheDictionaryWordsItCanTake() {
    let terms = ElevenLabsTranscriberOptions.keyterms(
        file: ["untype"],
        dictionary: ["BikS2013", "untype", "a term far longer than twenty characters"]
    )
    #expect(terms == ["untype", "BikS2013"])
    let many = ElevenLabsTranscriberOptions.keyterms(file: [], dictionary: (0..<80).map { "word\($0)" })
    #expect(many.count == 50)
}
