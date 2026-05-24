# Focused Input Live Smoke Test

## Purpose
Verify the Swift `untype-input-helper` can deliver stdin-fed text into the currently focused macOS control without placing processed text in process arguments.

## Prerequisites
- Build the project with `swift build`.
- Open a plain text editor field and place the cursor where text should be inserted.
- Grant Accessibility permission to the terminal app running the helper if macOS prompts. If macOS lists `untype-input-helper` separately, enable it too under System Settings > Privacy & Security > Accessibility.

## Diagnostic Check
Run:

```sh
.build/debug/untype-input-helper diagnose
```

Expected result:
- stdout contains one JSON object with `"ok":true`.
- If `"accessibility_trusted":false`, grant Accessibility permission and retry.
- stderr must not contain transcript or processed text.

## Send Check
With the text editor field focused, run:

```sh
printf 'focused input smoke' | .build/debug/untype-input-helper send --method auto
```

Expected result:
- The focused control receives `focused input smoke`.
- stdout contains one JSON object with `"ok":true` and a method of `ax-value`, `unicode-events`, or `paste-keycode`.
- The command arguments do not contain the delivered text; the text is supplied only on stdin.
- If the method is `paste-keycode`, the prior clipboard contents are restored and the JSON result includes `"clipboard_restored":true`.

## Failure Cases
- Without Accessibility permission, the helper should exit `2` and return JSON containing `"ok":false` and `"code":"accessibility_not_trusted"`.
- If no compatible focused element is available, the helper should exit `2` with an actionable JSON error.
- Diagnostics belong on stderr; stdout should remain one parseable JSON line.
