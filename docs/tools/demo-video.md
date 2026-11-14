# demo-video — the untype demo video

Folder: `video/`. A 2–3 minute video that shows untype in use, built as an animation that is a pure function of time, so its timing can follow a recorded voice in any language.

## What the video shows (storyboard)

| Beats | Scene | What is shown |
|---|---|---|
| `intro` | Logo | App icon and name. |
| `hold-press`, `hold-release` | Notes | Hold the hotkey (⌃ `): the overlay listens at once, the words are typed at the cursor while spoken; release finishes the text. |
| `tap-start`, `tap-speak` | Notes | A tap instead of a hold: hands-free listening, with the overlay's hint (Enter send · tap again type · Esc cancel). |
| `edit-insert`, `edit-fix`, `edit-finish` | Notes | Editing while it listens: click elsewhere and the next words are written there; select a wrong word and type over it; jump to the end, finish, tap to close. |
| `retry-bad`, `retry-esc`, `retry-send` | Messages | A sentence goes wrong: Esc removes the turn's text; tap, say it again, Enter types and sends. |
| `meet-start`, `meet-live`, `meet-channels` | Call | Start a meeting recording from the overlay; the transcription window shows both sides live (words in progress, finished lines); Both / Microphone / System. |
| `mute-switch`, `mute-dictate`, `mute-back` | Call | Settings → Meetings → "Mute the microphone while dictating"; during a held dictation the meeting gets silence from the microphone (the call's side is still transcribed, the note is not in the transcript); after release the user's words belong to the meeting again. |
| `outro` | Logo | |

The picture carries no captions or narration text, so one script serves every language. What is dictated on screen exists per language (`content.en`, `content.el`).

## What is real and what is drawn

- Real pixels (`video/assets/real/`): the overlay at rest (window capture, the reference for the drawn overlay), the transcription window's control bar and status bar in its three channel states, the Meetings settings pane (the "Dictation during a meeting" section is shown), the app icon. The window and the pane were rendered from the app's own SwiftUI views (`UntypeTranscriptionView`, `UntypeSettingsView`) with a temporary snapshot test; switches render grey off screen, so an "on" switch is drawn over them.
- Drawn to match the source: the overlay (trace colour, chips, hint text, meeting card from `UntypeOverlayView`), the transcript rows (fonts and colours of `UntypeTranscriptionView.row`).
- Generic: the desktop, the Notes / Messages / Call windows, the key caps, the microphone-to-meeting line.

## Files

| Path | Purpose |
|---|---|
| `video/src/timeline.js` | The script: beats with their minimum duration, on-screen content per language, narration per language. |
| `video/src/untype-demo.html` | The animation. Open it in a browser: `?lang=el&timing=el`, Space pauses, ←/→ step, `&t=42` starts paused at a time, `&debug=1` shows time and beat. |
| `video/src/timing.<profile>.js` | Beat durations per profile (`el`, `en`, `neutral`), written by `fit`. |
| `video/tools/video.ts` | The build tool (below). `video/tools/stills.ts <lang> <profile> <t…>` writes stills to `video/out/stills/`. |
| `video/narration/<lang>/` | Recorded narration, one clip per beat: `<beat id>.wav` (or mp3, m4a, aiff). `…/<lang>-scratch/` holds the placeholder system voice. |
| `video/out/` | Results: videos, `narration-<lang>-<profile>.md` (what to read, per beat, with times), `subtitles-<lang>-<profile>.srt`. |

## Commands (in `video/`, Node 22.18 or later, ffmpeg on the PATH)

```
npm install && npx playwright install chromium     # once
node tools/video.ts sheets                          # narration sheets + subtitles
node tools/video.ts scratch-voice --lang el         # placeholder narration with the macOS voice
node tools/video.ts fit --lang el [--voice narration/el]   # beat durations from the clips -> src/timing.el.js
node tools/video.ts fit --neutral                   # the longer of el / en per beat -> src/timing.neutral.js
node tools/video.ts render --lang el --timing el    # out/untype-demo-el-el.mp4 (1920x1080, 30 fps, no sound)
node tools/video.ts mux --lang el [--voice narration/el]   # out/untype-demo-el-voiced.mp4
```

## Adding the real voice

1. Read `out/narration-<lang>-<lang>.md`: one text per beat. Record each beat as its own clip and save it as `video/narration/<lang>/<beat id>.wav`. Change the wording freely in `src/timeline.js` first if needed.
2. `node tools/video.ts fit --lang <lang>`: every beat becomes at least as long as its clip (0.35 s before the voice, 0.55 s after); a beat never gets shorter than its minimum, so the action always has time to play. The action stretches with the beat.
3. `node tools/video.ts render --lang <lang> --timing <lang>`, then `node tools/video.ts mux --lang <lang>`. `sheets` rewrites the subtitles for the new timing.

## Adding a language

Add `content.<lang>` (the dictated sentences; `insertAfter` and `tapWrong` must occur in `hold` and `tap`) and `narration.<lang>` in `src/timeline.js`, create `src/timing.<lang>.js` as a copy of an existing one with the profile name changed, add its `<script>` line to `untype-demo.html` and the profile name to the list in `tools/video.ts` (`load`), and a system voice in `SCRATCH_VOICES` if a placeholder is wanted.

## Configuration

None: no environment variables, no keys. Every option is a command-line flag; a missing required flag (`--lang`) stops the command with an error.
