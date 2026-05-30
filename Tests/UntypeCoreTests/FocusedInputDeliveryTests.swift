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

@Test func focusedInputDeliveryResolvesBundledHelperBesideExecutable() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("untype-focused-input-\(UUID().uuidString)")
    let macOS = root
        .appendingPathComponent("untype.app")
        .appendingPathComponent("Contents")
        .appendingPathComponent("MacOS")
    defer {
        try? FileManager.default.removeItem(at: root)
    }
    try FileManager.default.createDirectory(at: macOS, withIntermediateDirectories: true)
    let helper = macOS.appendingPathComponent("untype-input-helper")
    FileManager.default.createFile(atPath: helper.path, contents: Data("#!/bin/sh\n".utf8))
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: helper.path)

    let resolved = try FocusedInputDelivery.resolveHelperPath(
        executablePath: macOS.appendingPathComponent("untype").path
    )

    #expect(resolved == helper.path)
}

@Test func focusedInputDeliveryRunsInProcessWhenBundledAppUsesAppIdentity() async throws {
    final class Capture {
        var args: [String] = []
        var stdinData: Data?
    }

    let capture = Capture()
    let delivery = FocusedInputDelivery(
        method: .auto,
        bundleURL: URL(fileURLWithPath: "/Applications/untype.app"),
        runner: { _, _, _, _ in
            throw FocusedInputDeliveryError(
                message: "Bundled app delivery should not spawn the helper process."
            )
        },
        inProcessRunner: { args, stdinData in
            capture.args = args
            capture.stdinData = stdinData
            return FocusedInputHelperRunResult(
                result: FocusedInputDeliveryResult.success(method: "ax-value"),
                exitCode: .success
            )
        }
    )

    let result = try await delivery.deliver("processed bundled text")

    #expect(result.ok)
    #expect(result.method == "ax-value")
    #expect(capture.args == ["send", "--method", "auto"])
    #expect(!capture.args.contains("processed bundled text"))
    #expect(capture.stdinData == Data("processed bundled text".utf8))
}

@Test func focusedInputDeliveryDetectsBundledAppFromExecutablePath() async throws {
    final class Capture {
        var inProcessText: String?
    }

    let capture = Capture()
    let delivery = FocusedInputDelivery(
        method: .auto,
        bundleURL: URL(fileURLWithPath: "/Applications/untype.app/Contents/MacOS"),
        executablePath: "/Applications/untype.app/Contents/MacOS/untype",
        runner: { _, _, _, _ in
            throw FocusedInputDeliveryError(
                message: "Bundled app executable path should force in-process delivery."
            )
        },
        inProcessRunner: { _, stdinData in
            capture.inProcessText = String(decoding: stdinData, as: UTF8.self)
            return FocusedInputHelperRunResult(
                result: FocusedInputDeliveryResult.success(method: "ax-value"),
                exitCode: .success
            )
        }
    )

    let result = try await delivery.deliver("processed app text")

    #expect(result.ok)
    #expect(capture.inProcessText == "processed app text")
    #expect(FocusedInputDelivery.isBundledApp(
        bundleURL: URL(fileURLWithPath: "/Applications/untype.app/Contents/MacOS"),
        executablePath: "/Applications/untype.app/Contents/MacOS/untype"
    ))
}

@Test func focusedInputDeliveryCanForceInProcessForUIRuns() async throws {
    final class Capture {
        var helperCalled = false
        var inProcessText: String?
    }

    let capture = Capture()
    let delivery = FocusedInputDelivery(
        method: .auto,
        bundleURL: URL(fileURLWithPath: "/tmp/untype"),
        executablePath: "/tmp/untype",
        forceInProcess: true,
        runner: { _, _, _, _ in
            capture.helperCalled = true
            return FocusedInputHelperProcessResult(
                exitCode: 0,
                stdout: #"{"ok":true,"method":"paste-keycode"}"# + "\n"
            )
        },
        inProcessRunner: { _, stdinData in
            capture.inProcessText = String(decoding: stdinData, as: UTF8.self)
            return FocusedInputHelperRunResult(
                result: FocusedInputDeliveryResult.success(method: "paste-keycode"),
                exitCode: .success
            )
        }
    )

    let result = try await delivery.deliver("processed ui text")

    #expect(result.ok)
    #expect(result.method == "paste-keycode")
    #expect(!capture.helperCalled)
    #expect(capture.inProcessText == "processed ui text")
}

@Test func focusedInputDeliveryKeepsHelperProcessForUnbundledRuns() async throws {
    final class Capture {
        var helperPath: String?
        var args: [String] = []
        var stdinText: String?
        var inProcessCalled = false
    }

    let capture = Capture()
    let delivery = FocusedInputDelivery(
        helperPath: "/tmp/untype-input-helper",
        method: .pasteKeycode,
        bundleURL: URL(fileURLWithPath: "/tmp/untype"),
        runner: { helperPath, args, stdinText, _ in
            capture.helperPath = helperPath
            capture.args = args
            capture.stdinText = stdinText
            return FocusedInputHelperProcessResult(
                exitCode: 0,
                stdout: #"{"ok":true,"method":"paste-keycode"}"# + "\n"
            )
        },
        inProcessRunner: { _, _ in
            capture.inProcessCalled = true
            return FocusedInputHelperRunResult(
                result: .failure(code: "wrong_path", message: "Unexpected in-process delivery."),
                exitCode: .expectedFailure
            )
        }
    )

    let result = try await delivery.deliver("unbundled text")

    #expect(result.ok)
    #expect(result.method == "paste-keycode")
    #expect(capture.helperPath == "/tmp/untype-input-helper")
    #expect(capture.args == ["send", "--method", "paste-keycode"])
    #expect(capture.stdinText == "unbundled text")
    #expect(!capture.inProcessCalled)
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

@Test func focusedInputHelperDetectsBrowserBundleIdentifiers() {
    #expect(FocusedInputHelperMain.isBrowserBundleIdentifier("com.google.Chrome"))
    #expect(FocusedInputHelperMain.isBrowserBundleIdentifier("com.apple.Safari"))
    #expect(FocusedInputHelperMain.isBrowserBundleIdentifier("org.mozilla.firefox"))
    #expect(FocusedInputHelperMain.isBrowserBundleIdentifier("company.thebrowser.Browser"))
    #expect(!FocusedInputHelperMain.isBrowserBundleIdentifier("com.apple.Terminal"))
    #expect(!FocusedInputHelperMain.isBrowserBundleIdentifier("com.apple.TextEdit"))
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
