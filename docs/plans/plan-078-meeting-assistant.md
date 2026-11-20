# Plan 078 - The meeting assistant

Date: 2026-11-20. Status: implemented on macOS; the agent answered on a recorded meeting from the terminal; not installed, the window was not yet seen in use.

## Request

An agent inside untype, built on the PiDurable framework, that sees the transcript of the meeting being recorded and the attachments put on it, and answers the user's questions about it while the recording goes on. Its own user interface, in Swift.

Decided with the user (2026-11-20): Node.js is part of untype.app (nothing else to install); the assistant only reads; its model is its own setting, apart from Refine and Translate.

## What the user gets

- **Meeting assistant** window: the menu-bar dropdown (⌘4), **Ask** in the transcription window, Settings → Meetings → Assistant → Open. A conversation: the question, the answer as it is written, what the assistant is doing meanwhile ("Reading the transcript…"), Stop.
- It answers about the meeting being recorded, and goes on answering about it after it ends (until the next recording starts). Each meeting has its own conversation, kept across restarts and found again after the meeting is named.
- The model: a provider and a model chosen in the window (the model button) or in Settings → Meetings → Assistant, from the list the agent itself gives. No default: until one is chosen the window asks for it. The API key is the provider's own, from Settings → API keys.

## How

Two parts.

**The agent** (`agent/`, TypeScript, Node.js ≥ 22.19): `@earendil-works/pi-durable` 1.5.2 with `pi-ai`, `chord`, `pi-schema` (the versions the user's deck-agent uses; pinned, the API is experimental).

- `src/main.ts`: `catalog` (providers and models as JSON) and `serve` (JSON lines: requests on stdin, events on stdout, logs on stderr). One Harness on SQLite at `UNTYPE_AGENT_HOME/state.sqlite` (`~/.tool-agents/untype/agent/`); a document maps each recording to its conversation.
- Requests: `open {folder, key, recording}`, `meeting {folder?, recording?}`, `ask {id, text}`, `abort`. Events: `ready`, `opened {history}`, `run_start`, `tool {name}`, `text {delta, reset?}`, `run_end {failure?}`, `error`, `fatal`.
- `src/extension.ts`: the instructions and four read-only tools — `meeting_overview`, `read_transcript` (whole or by time), `search_transcript`, `read_attachment` (a picture is shown to the model, prepared to the provider's limits; text and text files as text; other files say they cannot be read yet). Every question carries the last 3 minutes of the transcript, so most answers need no tool.
- `src/meeting.ts`: reads the meeting folder directly — `<stem>.segments.jsonl` (written live by the recorder), `<stem>.attachments.json`, `attachments/`. Nothing goes back to untype for it, so the recorder is not touched.
- Environment: the app's, with the user's `.env` over it. `GOOGLE_API_KEY` is also given as `GEMINI_API_KEY`; `AZURE_OPENAI_API_VERSION` is dropped (untype's is a dated Chat Completions version, pi-ai calls the Responses API, version `v1`).

**untype** (`MeetingAssistant.swift`, macOS only): `MeetingAssistantInstallation` (the bundled `Contents/MacOS/untype-node` and `Contents/Resources/agent/dist/src/main.js`), `MeetingAssistantSettings` (`UNTYPE_AGENT_LLM_PROVIDER`, `UNTYPE_AGENT_LLM_MODEL`, the helper's environment, the meeting's key), `MeetingAssistantProcess`, `MeetingAssistantEvent`, `MeetingAssistantModel`, `UntypeAssistantWindowController` / `UntypeAssistantView`, `MeetingAssistantModelPicker`. The helper starts when the window opens or a question is asked, and stops when untype quits or the model changes. `NativeUntypeUILauncher` tells the model the meeting (start, end, rename).

**Packaging** (`scripts/package-macos-app.sh`): the official Node.js v22.23.5 arm64 build (checksum pinned) as `Contents/MacOS/untype-node`, signed with the Developer ID, hardened runtime and `packaging/macos/node.entitlements` (JIT and unsigned executable memory, which V8 needs); the agent built, tested and copied with its production dependencies to `Contents/Resources/agent`; a native program among the dependencies fails the packaging.

## After the first use (build 84, 2026-11-20)

- **Dictation into the assistant's field did not work.** With a window of untype itself in front, a dictation turn goes to the last other app (untype's windows are not a place to dictate into), so the words went there. Now the assistant window, while it is the window the user types in, counts as a target like any app's field (`isExternalFocusedInputApplication`, `assistantWindowIsKey`); untype is still never remembered as the app to go back to. The other windows of untype behave as before.
- **Cut at the last full stop** (user request): a line reaches the transcript only when its sentence ends for Soniox, so the assistant did not see a long turn still being spoken. `MeetingTokenAggregator.flushThroughLastSentenceEnd()` ends the line being spoken at its last sentence end (`.`, `!`, `?`, `;`, `…`; not inside a number), writes it, and leaves the words after it in progress; never at another point. `MeetingRecorder.cutAtLastSentenceEnd()` does it on both sides. It runs by itself before every question to the assistant (`MeetingAssistantModel.beforeAsk`), and on request from the transcription window (the ↵ button next to Pause / Attach).

## After the second use (build 85, 2026-11-20)

Build 85 in use: dictation into the assistant's field was delivered there (`focused-input target captured: untype`, `focused_input.ok=true`), the assistant answered in the app (4.5 s), the cut worked (user).

- **The sound is lowered while dictating to the assistant** (user request: the call playing from the loudspeakers kept speech recognition from hearing the user). When a dictation turn starts with the assistant window as the window typed in, and the Mac's output volume is above 15 %, it is set to 15 % (`OutputVolumeDuck.quiet`) and put back when the turn ends, unless the user changed it meanwhile; also when untype quits. `SystemOutputVolume` reads and sets the default output device's volume (CoreAudio); an output without a settable volume is reported in Events and left alone. Only for dictation to the assistant, not for dictation elsewhere.
- **Delete a row of the transcript** (user request): while the meeting is recorded, a line or an attachment of the transcription window has a trash button (on hover, and in its context menu), with a confirmation. A line leaves the files written so far (`MeetingLiveFiles.rewrite`) and the files saved at the end (`MeetingRecorder.remove`); an attachment's copy in the meeting folder is deleted and it leaves `<stem>.attachments.json` (`MeetingAttachmentStore.remove`; numbers are not reused). The assistant no longer sees either. The audio is not changed. After the recording ends rows cannot be deleted.

## PDF and Office attachments (2026-11-20, user request, after build 86)

`read_attachment` now also returns the text of:

- **Word, Excel, PowerPoint** (`.docx`, `.dotx`, `.xlsx`, `.xlsm`, `.pptx`, `.potx`): read in the agent from the files' XML parts (`agent/src/lib/ooxml-read.ts`, `zip.ts`, taken as they are from the user's deck-agent; no new dependency). A workbook gives up to 500 rows of each sheet; a presentation its slides with their notes.
- **PDF, old Word (`.doc`) and rich text (`.rtf`)**: read by untype, which has the system's readers. The agent sends an `extract {id, path}` event, `MeetingAssistantModel` reads the file off the main thread (`MeetingDocumentText`: PDFKit, pages marked "--- Page 3 of 12 ---"; `NSAttributedString` for the other two) and answers with the request `extracted {id, text | error}`. Only files inside the meeting folder are read; 60 s at most.
- A long document comes in parts of 40 000 characters (`offset`). A document with no text (a PDF of scanned pages) says so.

Not read: scanned PDFs (no text recognition), protected PDFs, old Excel and PowerPoint (`.xls`, `.ppt`), pictures inside documents.

## Verified

- `swift build`, 536/536 tests (12 new: a PDF and a rich text file give their text, the request for a document, lowering and restoring the sound, deleting a line and an attachment, the window's delete, the cut at the last full stop, the request for it, the events, the meeting's key, the settings with no default, the catalog, the model without its program).
- From the terminal, on a made-up meeting with a Word file and a PDF (the script playing untype's part for the PDF): both read, the three facts asked for answered correctly through Azure in 3.9 s.
- `agent`: `npm test` 6/6 (Word, Excel and PowerPoint files as text, a long document in parts, the transcript in time order, ranges, search without accents, attachments, the context of a question); `npm audit` clean.
- From the terminal, on a recording of 2026-11-20 with Azure `gpt-5.1`: the agent opened the meeting, looked at attachment 1 (a screenshot) and answered in 6.5 s; the answer came in pieces.
- Node.js signed with the Developer ID under the hardened runtime runs the agent's tests.
- Build 84 packaged with Node.js and the agent inside: notarized (`source=Notarized Developer ID`), 184 MB (130 MB before; the zip is 56 MB). The agent run from inside that bundle, with only the user's `.env` as environment, opened a recording, looked at a screenshot and answered through Azure in 9.4 s.

## Not verified

- The window in the installed app: asking during a recording, the stream, Stop, the model picker, the conversation after a restart and after naming.
- Providers other than Azure.

## Limits

- macOS only (a helper process). The app grows by 54 MB (130 → 184 MB).
- Read-only: no notes, no summary file, no actions.
- Scanned or protected PDFs, `.xls` and `.ppt` are not read.
- The words being spoken (not yet a finished line) are not seen; a line appears when its sentence ends.
- Claude on Azure Foundry (`azure-anthropic` in untype) is not among pi-ai's providers; Claude is reachable through `anthropic` (its own key) or `openrouter`.
- What is asked and the parts of the meeting the assistant reads go to the chosen provider.
