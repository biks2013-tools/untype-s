import Foundation
import Testing
@testable import UntypeCore

@Test func focusedInputDeliveryParsesHelperSuccessResult() throws {
    let result = try FocusedInputDelivery.parseHelperResult(
        #"{"ok":true,"method":"paste-keycode","clipboard_restored":true}"# + "\n"
    )

    #expect(result == FocusedInputDeliveryResult(
        ok: true,
        method: "paste-keycode",
        clipboardRestored: true
    ))
}

@Test func focusedInputDeliveryRejectsMalformedHelperOutput() throws {
    #expect(throws: FocusedInputDeliveryError.self) {
        _ = try FocusedInputDelivery.parseHelperResult(
            #"{"ok":true,"method":"argv-leak"}"# + "\n"
        )
    }
    #expect(throws: FocusedInputDeliveryError.self) {
        _ = try FocusedInputDelivery.parseHelperResult(
            #"{"ok":true}"# + "\n" + #"{"ok":true}"# + "\n"
        )
    }
}

@Test func focusedInputDeliverySendsTextOverStdinNotArguments() async throws {
    actor Capture {
        var helperPath: String?
        var args: [String] = []
        var stdinText: String?

        func record(helperPath: String, args: [String], stdinText: String) {
            self.helperPath = helperPath
            self.args = args
            self.stdinText = stdinText
        }

        func snapshot() -> (String?, [String], String?) {
            (helperPath, args, stdinText)
        }
    }

    let capture = Capture()
    let delivery = FocusedInputDelivery(
        helperPath: "/tmp/untype-input-helper",
        method: .auto,
        runner: { helperPath, args, stdinText, _ in
            await capture.record(helperPath: helperPath, args: args, stdinText: stdinText)
            return FocusedInputHelperProcessResult(
                exitCode: 0,
                stdout: #"{"ok":true,"method":"ax-value"}"# + "\n"
            )
        }
    )

    try await delivery.send("secret focused text")

    let snapshot = await capture.snapshot()
    #expect(snapshot.0 == "/tmp/untype-input-helper")
    #expect(snapshot.1 == ["send", "--method", "auto"])
    #expect(!snapshot.1.contains("secret focused text"))
    #expect(snapshot.2 == "secret focused text")
}

@Test func focusedInputDeliveryReturnsExpectedHelperFailuresAndSendThrows() async throws {
    let delivery = FocusedInputDelivery(
        helperPath: "/tmp/untype-input-helper",
        runner: { _, _, _, _ in
            FocusedInputHelperProcessResult(
                exitCode: 2,
                stdout: #"{"ok":false,"code":"accessibility_not_trusted","message":"Grant Accessibility permission to untype-input-helper."}"# + "\n"
            )
        }
    )

    let result = try await delivery.deliver("text")
    #expect(result.ok == false)
    #expect(result.code == "accessibility_not_trusted")

    await #expect(throws: FocusedInputDeliveryError.self) {
        try await delivery.send("text")
    }
}

@Test func focusedInputHelperParsesCommandsAndReturnsExpectedFailures() throws {
    let parsed = try FocusedInputHelperMain.parseCommand(["send", "--method", "paste-keycode"])
    #expect(parsed == FocusedInputHelperCommand(command: "send", method: .pasteKeycode))

    let failure = FocusedInputHelperMain.run(
        arguments: ["send", "--method", "bogus"],
        inputData: Data("should stay on stdin".utf8)
    )
    #expect(failure.exitCode == .expectedFailure)
    #expect(failure.result.ok == false)
    #expect(failure.result.code == "invalid_method")
}

@Test func macOSClipboardWriterUsesInjectedWriterWithoutReadingArguments() async throws {
    final class Capture: @unchecked Sendable {
        var text: String?
    }

    let capture = Capture()
    let writer = MacOSClipboardWriter(writeString: { text in
        capture.text = text
    })

    try await writer.copy("copy me")

    #expect(capture.text == "copy me")
}
