import Foundation
import Testing
@testable import UntypeCore

private let rule = String(repeating: "─", count: 40)

private func screen(_ prompt: [String]) -> String {
    ([
        "⏺ Done.",
        "",
        "✻ Cooked for 8s",
        "",
        rule
    ] + prompt + [
        rule,
        "  Opus 5.5 · effort medium │ ██░░ 9%",
        "  ⏵⏵ bypass permissions on (shift+tab to cycle)"
    ]).joined(separator: "\n")
}

@Test func terminalPromptIsReadFromTheClaudeCodeBox() {
    #expect(TerminalPromptParser.prompt(in: screen(["❯ κάνε commit και push το yazi"])) == "κάνε commit και push το yazi")
}

@Test func emptyTerminalPromptOrNoBoxIsNil() {
    #expect(TerminalPromptParser.prompt(in: screen(["❯ "])) == nil)
    #expect(TerminalPromptParser.prompt(in: "$ ls\nfile.txt\n$ ") == nil)
}

@Test func wrappedTerminalPromptLinesAreJoinedWithASpace() {
    // Width 40: 38 columns for text after "❯ " / "  ".
    let prompt = TerminalPromptParser.prompt(in: screen([
        "❯ please rewrite this paragraph so that",
        "  it reads better",
        "  second line typed by the user"
    ]))
    #expect(prompt == "please rewrite this paragraph so that it reads better\nsecond line typed by the user")
}

@Test func terminalPromptBoxMayHaveALabelInItsTopRule() {
    let labeled = String(repeating: "─", count: 30) + " .biks-configurations ─"
    let text = ["⏺ Done.", labeled, "❯\u{00A0}κάνε commit και push το yazi", rule, "  status"].joined(separator: "\n")
    #expect(TerminalPromptParser.prompt(in: text) == "κάνε commit και push το yazi")
}

@Test func onlyTheLastPromptBoxCounts() {
    let text = screen(["❯ old"]) + "\n" + screen(["❯ new text"])
    #expect(TerminalPromptParser.prompt(in: text) == "new text")
}
