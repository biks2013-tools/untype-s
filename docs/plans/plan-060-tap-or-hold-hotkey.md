# Plan 060 — One hotkey: hold to talk, tap for hands-free

## Request
The user wants one dictation mode on one hotkey. Holding the hotkey records while it is held (push-to-talk). A quick tap keeps recording hands-free for long dictation, and the turn ends with a key: Enter when the text should also be sent (Claude Code in a terminal, Teams, SMS), something else when it should only be typed. untype must not need to know which app is in front.

## What the user sees
- **Hold** the hotkey (0.4 s or longer), talk, release: the text is typed into the focused field. Unchanged.
- **Tap** the hotkey (released in under 0.4 s): recording goes on. The overlay shows over the trace: `Enter send · tap again type · Esc cancel`.
  - **Enter**: recording stops, the text is typed, then untype presses Return in the same field. Each app does what Return does there: a terminal submits the prompt, a chat app sends the message, an email body or a document gets a new line.
  - **The hotkey again**: recording stops and the text is typed only.
  - **Esc**: recording stops, nothing is delivered, and the text typed live into the field is removed. The overlay says "Discarded".
- Enter and Esc with a modifier (Shift+Enter, etc.) pass through to the app. Every other key passes through untouched.
- The hold/press-to-toggle choice is gone from Settings, the menu-bar dropdown and the main window's top bar.

## Decisions
- **The key chosen at the end decides send or not**, so there is no per-app list. A list of auto-send apps can be added later if one turns out to be wanted.
- **Recording starts on press**, so the first words are never lost while untype waits to tell a tap from a hold. Only the release decides.
- **Threshold 0.4 s** (`HotkeyTapOrHold.tapThreshold`): nobody says anything useful in less.
- **Return only after a successful delivery**, and only when the app the turn started in is in front. If delivery fails, no Return is pressed and the log says so. With focused-input delivery off, Enter just ends the turn.
- **Enter and Esc are caught by the existing Return/Esc key tap** (`UntypeReturnEscapeKeyTap`, shared with meeting naming), active only during a hands-free turn. If macOS refuses the tap, the hint reads `Tap again to finish` and the hotkey still ends the turn.
- **Operator keys** (R, T, A, …) apply only while the hotkey is held. During a hands-free turn the overlay chips switch operators.
- `hotkeyHoldToTalk` is no longer a setting. A `ui-state.json` that still holds it loads normally and the key is ignored.

## Code
- `HotkeyTapOrHold.swift`: `HotkeyTapOrHold.isTap(heldFor:)` and `HotkeyTurnFinish` (`type-and-send`, `type-only`, `discard`).
- `UntypeUIModel`: `handleHotkeyPress` / `handleHotkeyRelease` (press time; a tap begins a hands-free turn), `beginHandsFreeTurn`, `finishHandsFreeTurn`, `endHandsFree`, `discardHotkeySession` (stop with `submitPending: false`, live text reconciled to empty), `sendAfterDelivery`, `finishFocusedInputDelivery(delivered:)` presses Return through `LiveKeyboardPoster.postReturn()` (marked synthetic, so untype's own taps let it through).
- `UntypeRuntimeFactory`: `focusedInputCompletion` receives whether the delivery succeeded.
- Overlay: `setHandsFreeHint(_:)`, a caption over the recording trace.

## Checks
- `HotkeyTapOrHoldTests` (threshold, finish names); `uiSettingsStoreLoadsAStateFileWrittenWithTheRetiredHotkeyModeKey`; full suite.
- On device: see `Issues - Pending Items.md`.
