# Plan 056 — Meeting recording from the overlay

## Request
Record any call or meeting (Teams, Zoom, browser, …) from untype itself, started from the always-on overlay, with a transcript that separates the speakers, copes with Greek and English spoken in the same meeting, ends up in English, stops by itself after a long silence, and is stored in one dedicated place. Everything lives in untype: one app, one keys file, one set of permissions.

## What the user sees
- **Start.** Hover the overlay → the tray's top row has a **⏺ Record meeting** button (next to Translate and the gear). One click starts.
- **While recording.** The overlay shows a **red** trace of the meeting audio (both sides of the call) where the blue dictation trace normally is, plus a small elapsed time. It stays visible even with "Keep overlay visible" off. Hovering shows the tray with **⏹ Stop**. Push-to-talk keeps working: while the hotkey is held the trace turns blue, then back to red.
- **Stop.** Click ⏹, or choose "Stop meeting recording" in the menu-bar dropdown, or wait for the auto-stop.
- **Auto-stop.** After **3 minutes** with no speech on either side the recording stops on its own; the overlay shows "Meeting ended after 3 min of silence".
- **Afterwards.** The overlay shows "Meeting saved" for a few seconds; the menu-bar dropdown's **Open folder** (and Settings → Meeting recording → Open) opens the meetings folder.

## Where the result goes
One folder per meeting: `~/Documents/untype Meetings/2026-11-11 14.30/`

| File | Content |
|---|---|
| `transcript.txt` | The transcript **in English** (default), one line per utterance: `[00:12:07] Speaker 2: Yes, let's start with the budget.` |
| `transcript.original.txt` | The same lines as spoken, with the language per line: `[00:12:15] Speaker 3 [el]: Συμφωνώ, έχω τα νούμερα εδώ.` |
| `transcript.jsonl` | Machine-readable segments (time, side, speaker, language, original text, English text) |

Your own microphone is labelled **You**; the people on the call are **Speaker 1, Speaker 2, …** No audio file is kept (only the transcript).

## Decisions
- **Inside untype, not ntakker.** The capture code is carried over from ntakker (`SCKitSystemAudioSource`, Soniox diarization config, token aggregation) and adapted to untype's types. untype keeps its macOS 14 minimum: the ntakker capture code uses no newer API.
- **Two Soniox streams.** One for the microphone (labelled You) and one for the call's sound (system audio, all apps except untype) with speaker diarization. This keeps your lines correct without mixing or echo cancellation. Both use untype's existing `SONIOX_API_KEY` and model, with `language_hints ["el","en"]` and language identification on.
- **Headphones recommended.** Without headphones the microphone also hears the other people through the speakers, so their words can appear twice (once as You). Echo cancellation (ntakker's `SoftwareAECProcessor`) is a later step if needed.
- **English.** When the meeting stops, untype translates the transcript to English with the configured LLM (the same provider and keys as Translate), in chunks, keeping the time and speaker of every line. Lines already in English are left as spoken. The original is always kept.
- **Silence.** Speech is detected from Soniox's final tokens on either stream; 3 minutes without a new final token stops the meeting.
- **Permissions.** Microphone (already granted) and **Screen & System Audio Recording** (the permission untype already asks for the Screenshot operator; macOS calls system-audio capture "screen recording", no picture is taken). No new permission kind.
- **Push-to-talk is untouched.** The meeting uses its own microphone capture and its own Soniox sessions; the hotkey session, audio gate, overlay phases and focused-input delivery keep their current wiring.

## Settings (Settings → General → Meeting recording; stored as `meeting` in `ui-state.json`)
| Setting | Default | Key |
|---|---|---|
| Transcript language | English (`en`); also `original` (as spoken) | `meeting.language` |
| Auto-stop after silence (minutes, 0 = off) | 3 | `meeting.silenceMinutes` |
| Folder | `~/Documents/untype Meetings` | `meeting.folder` |

## Build order
1. **Capture and transcript.** System-audio capture, two Soniox streams with diarization, live writing of `transcript.original.txt` / `.jsonl`; start/stop from the menu-bar dropdown. Proves capture, speakers and languages on a real call.
2. **Overlay.** ⏺/⏹ in the tray, red trace, elapsed time, saved notice.
3. **Auto-stop** after silence.
4. **English transcript** at stop.
5. **Settings**, configuration guide, design docs, tests (aggregation, line format, silence timer, translation chunking, settings round trip).

## Checks
- Unit tests for the pure parts; `swift test` green.
- On device: a real Teams call with Greek and English; speakers separated; auto-stop; English file; push-to-talk during a meeting and `focused_input.ok=true` afterwards.
