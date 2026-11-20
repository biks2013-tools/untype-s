import Foundation
import Testing
@testable import UntypeCore

// plan-076: the finished transcript of a meeting as a note in Apple Notes.

@Test
func theNoteHasTheTitleFirstAndEveryTranscriptLineOnItsOwnLine() {
    let html = AppleNotesHTML.body(title: "Budget review · Today 10:00", transcript: "[00:01] You: hello\n\n[00:04] Speaker 1: hi there\n")
    #expect(html == "<h1>Budget review · Today 10:00</h1><div>[00:01] You: hello</div><div><br></div><div>[00:04] Speaker 1: hi there</div>")
}

@Test
func textThatLooksLikeMarkupIsWrittenAsText() {
    let html = AppleNotesHTML.body(title: "a < b & c", transcript: "use <div> & </div>\r\nnext")
    #expect(html == "<h1>a &lt; b &amp; c</h1><div>use &lt;div&gt; &amp; &lt;/div&gt;</div><div>next</div>")
}

@Test
func aHandlerOfAScriptGetsItsTextParametersInOrder() throws {
    // The same call the note is made with, on a script that touches no app.
    let source = """
    on joinThem(partOne, partTwo)
        return partOne & "|" & partTwo
    end joinThem
    """
    let long = String(repeating: "λόγια with \"quotes\" and <tags>\n", count: 2_000)
    let result = try AppleNotesWriter.call(source: source, handler: "joinThem", parameters: ["untype", long])
    #expect(result == "untype|" + long)
}

@Test
func aScriptErrorIsReportedWithItsMessage() {
    let source = """
    on failNow(reason)
        error reason number 42
    end failNow
    """
    #expect(throws: AppleNotesWriter.Failure(message: "Apple Notes: the reason (42)")) {
        try AppleNotesWriter.call(source: source, handler: "failNow", parameters: ["the reason"])
    }
}

@Test
func theAppleNotesSwitchIsOffUntilTheUserSetsIt() throws {
    #expect(MeetingPreferences().savesToAppleNotes == false)
    let old = try JSONDecoder().decode(MeetingPreferences.self, from: Data(#"{"language":"en","silenceMinutes":3}"#.utf8))
    #expect(old.savesToAppleNotes == false)
    var on = old
    on.appleNotes = true
    let back = try JSONDecoder().decode(MeetingPreferences.self, from: JSONEncoder().encode(on))
    #expect(back.savesToAppleNotes)
}
