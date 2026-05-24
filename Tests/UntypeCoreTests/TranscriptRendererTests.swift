import Testing
@testable import UntypeCore

@Test func overwritePartialUsesCarriageReturnWithoutNewline() {
    let output = MemoryOutput()
    let renderer = TranscriptRenderer(output: output, mode: .overwrite, isTTY: true)

    renderer.partial("hello")

    #expect(renderer.effectiveMode == .overwrite)
    #expect(output.text == "\rhello")
}

@Test func overwriteShorterPartialPadsPreviousText() {
    let output = MemoryOutput()
    let renderer = TranscriptRenderer(output: output, mode: .overwrite, isTTY: true)

    renderer.partial("hello")
    renderer.partial("hi")

    #expect(output.text == "\rhello\rhi   ")
}

@Test func overwriteClearsWrappedRowsBeforeNextPaint() {
    let output = MemoryOutput()
    let renderer = TranscriptRenderer(output: output, mode: .overwrite, isTTY: true, terminalColumns: 10)

    renderer.partial("abcdefghijklmnop")
    renderer.partial("short")

    #expect(output.text == "\rabcdefghijklmnop\u{001B}[1A\r\u{001B}[2K\u{001B}[1B\r\u{001B}[2K\u{001B}[1A\rshort")
}

@Test func overwriteFinalClearsPartialAndTerminatesLine() {
    let output = MemoryOutput()
    let renderer = TranscriptRenderer(output: output, mode: .overwrite, isTTY: true)

    renderer.partial("hello")
    renderer.final("hi")

    #expect(output.text == "\rhello\rhi   \n")
}

@Test func overwriteDuplicatePartialsAreSuppressed() {
    let output = MemoryOutput()
    let renderer = TranscriptRenderer(output: output, mode: .overwrite, isTTY: true)

    renderer.partial("same partial")
    renderer.partial("same partial")
    renderer.partial("same partial")

    #expect(output.text == "\rsame partial")
}

@Test func overwriteSanitizesEmbeddedNewlines() {
    let output = MemoryOutput()
    let renderer = TranscriptRenderer(output: output, mode: .overwrite, isTTY: true)

    renderer.partial("line1\nline2")

    #expect(output.text == "\rline1 line2")
}

@Test func overwriteDowngradesToAppendWhenNotTty() {
    let output = MemoryOutput()
    let renderer = TranscriptRenderer(output: output, mode: .overwrite, isTTY: false)

    renderer.partial("hello")
    renderer.partial("hi")
    renderer.final("hi there")

    #expect(renderer.effectiveMode == .append)
    #expect(output.text == "hello\nhi\nhi there\n")
}

@Test func appendWritesEachNonDuplicatePartialAndFinalAsLine() {
    let output = MemoryOutput()
    let renderer = TranscriptRenderer(output: output, mode: .append, isTTY: true)

    renderer.partial("hello")
    renderer.partial("hello")
    renderer.partial("hi")
    renderer.final("hi there")

    #expect(output.text == "hello\nhi\nhi there\n")
}

@Test func finalOnlySuppressesPartials() {
    let output = MemoryOutput()
    let renderer = TranscriptRenderer(output: output, mode: .finalOnly, isTTY: true)

    renderer.partial("hello")
    renderer.partial("hi")
    renderer.final("hi there")

    #expect(renderer.effectiveMode == .finalOnly)
    #expect(output.text == "hi there\n")
}

@Test func markerTokensAreFilteredBeforeRendering() {
    let output = MemoryOutput()
    let renderer = TranscriptRenderer(output: output, mode: .append, isTTY: true)

    renderer.partial("hello <end>")
    renderer.final("done <fin>")

    #expect(output.text == "hello\ndone\n")
}

@Test func refinedCommitsDanglingOverwritePartialFirst() {
    let output = MemoryOutput()
    let renderer = TranscriptRenderer(output: output, mode: .overwrite, isTTY: true)

    renderer.partial("next utt")
    renderer.refined("clean output")

    #expect(output.text == "\rnext utt\nclean output\n\n")
}

@Test func disposeAfterDanglingOverwritePartialTerminatesAndClearsLine() {
    let output = MemoryOutput()
    let renderer = TranscriptRenderer(output: output, mode: .overwrite, isTTY: true)

    renderer.partial("hello")
    renderer.dispose()
    renderer.partial("ignored")

    #expect(output.text == "\rhello\n\u{001B}[2K\r")
}
