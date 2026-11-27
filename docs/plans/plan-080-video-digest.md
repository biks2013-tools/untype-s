# plan-080 — Video digest (αποδελτίωση βίντεο)

Status: **in progress** (2026-11-27): the shared core and the Mac command line work end to end; the Mac window, the iCloud path and the iPhone are next.

## Request (user, 2026-11-27)

Give a YouTube video (later: other video content) and get, quickly, what it says without watching it:

- use the video's own transcript when it has one; otherwise transcribe it with the speech model untype uses (Soniox);
- a summary with the key points, **what is said and how it is said**;
- **screenshots** of the moments that can serve as reference points in presentations, embedded in the digest;
- **HTML** by default, **DOCX** when the user asks for it;
- the digest in **the video's language by default**, changeable by the user (per request, with a setting for the default);
- the video's material (audio, transcript in the meeting format, so **untype studio** opens it as a recording) and everything the tool produces (HTML, DOCX, screenshots, analysis) **in one folder per video**;
- runnable **on the iPhone itself** (the app kept in the foreground while it works) **or on the Mac via iCloud**: the user chooses per request, so it works when the Mac is off.

Reference: the agent-daily-pi skills `youtube-deep-dive` and `agent-daily-publishing-conventions` (`~/coding-agents/agent-daily-pi/skills/`). Rules taken from them:

- Captions are read only for a video the user asked for, never in bulk: YouTube rate-limits caption access per IP and then blocks every caption route at once for hours. The audio download is not blocked, so the fallback is local / Soniox transcription.
- Machine transcripts (YouTube's auto-captions included) garble proper nouns, CLI names and numbers: say in the digest which transcript was used.
- Timestamps are links and never exceed the video's duration.
- Images are content: compressed and embedded so the HTML stands alone.
- Links from the description are kept, without sponsor / affiliate / tracking links.

## Shape

**An app feature in Swift, not a TypeScript tool.** Processing on the iPhone means the pipeline runs in Swift, so the core goes in `UntypeCore` (cross-platform) and both apps use it. A TypeScript CLI would be a second implementation; if a command-line entry is wanted, it can be a subcommand of the `untype` binary. (The user had picked "CLI tool + untype"; this replaces the CLI part.)

```
VideoSource (protocol)         Mac: yt-dlp + ffmpeg (paths are settings)      iOS: YouTubeKit (.local only) + AVFoundation
  metadata, chapters, description
  captions (if any)
  audio file
  frame at time t
            │
            ▼
VideoDigestPipeline (UntypeCore, shared), every stage saved in the folder so a killed run resumes:
  1. metadata.json          2. transcript (captions → segments; else Soniox file API with diarization)
  3. analysis.json (LLM, chunked: key points, how it is said, sections, quotes, reference moments)
  4. screenshots/*.png (a few candidates per moment, the sharpest kept)
  5. digest.html (default), digest.docx (on request)
```

Folder per video, in the recording layout untype studio reads: `<stem>.m4a`, `<stem>.segments.jsonl`, `<stem>.system.transcript.jsonl`, `<stem>.studio.json` (with `audioStart`, and the sidecar listed in `exactTimingTranscripts` because caption times are audio positions), plus `<stem>.video.json`, `<stem>.digest.json`, `<stem>.digest.html`, `<stem>.digest.docx`, `screenshots/`.

Requests through iCloud: a request file written atomically into an inbox folder, claimed by the Mac with a marker, never processed twice; the result folder in the same iCloud location.

## Spikes (before anything is built)

1. iOS frames: `AVAssetImageGenerator` on a YouTubeKit stream URL, else a short progressive download.
2. iOS extraction: YouTubeKit `methods: [.local]` (never `.remote`: it relays the device's requests through a third-party server) returns an audio stream that downloads.
3. iOS captions: YouTubeKit has no caption API; does a direct caption fetch work, or is iPhone-local always Soniox?
4. Soniox file API: one real file with diarization; model name from the docs/API; whether the tokens carry `<end>` markers (else segments are cut at sentence ends or pauses); the uploaded file and the transcription deleted afterwards.

## Spike results (2026-11-27, throwaway code in the session scratchpad)

| # | What | Result |
|---|---|---|
| 4 | Soniox file API (`POST /v1/files`, `POST /v1/transcriptions`, poll, `GET …/transcript`, `DELETE` both; Bearer key) | **Works.** Model `stt-async-v6` (`stt-async-v5` is removed on 2026-12-15). A 19 s file: done in 1.8 s; tokens carry `start_ms`, `end_ms`, `speaker`, `language`; **no `<end>` markers**, so segments are cut at sentence ends and speaker changes. File and transcription deleted. |
| 3 | Captions without yt-dlp (`POST youtubei/v1/player`, ANDROID client → `captionTracks` → timedtext XML) | **Works**, in Python and in Swift on the iOS simulator: manual and ASR tracks listed, lines with start and duration. |
| 2 | Audio on iOS | **Fails.** YouTubeKit 0.4.10 `.local`: `jsonDecodingFailed` today. Our own player call (IOS / ANDROID clients) gives direct URLs, but a full download is refused: the first MB comes back (206), the next range gets **403** (a long video; YouTube wants a PO token). A short video worked. |
| 1 | Frames on iOS | **Fails for real screenshots.** Video ranges after the first MB: 403. Storyboards (no download): at most **160×90**, every 10 s — not usable in a presentation. |
| Mac | yt-dlp (2026.10.26, with `deno` for YouTube's challenges) + ffmpeg | **Works.** A 40 min video: audio 37 MB in 6 s; a 3 s section at 10:00 in 9 s, a clean 1920×1080 frame of the slide. |

So, on the iPhone alone: captions, the analysis, HTML and DOCX work; audio of a long video and screenshots do not, without a helper (YouTubeKit's remote server, which relays the phone's requests through a third party, or ReplayKit capture of the video playing in the app — not tried).

## Constraints

- yt-dlp needs a JavaScript runtime (`deno`) for YouTube's challenges, otherwise formats go missing. yt-dlp, deno and ffmpeg are not part of untype and not on the PATH of an app launched from Finder: explicit path settings, a clear error when missing, nothing bundled under Resources (the packaging script refuses Mach-O there).
- YouTubeKit (MIT) goes through dependency vetting and the "Dependency vetting log" first.
- Long videos: the transcript is analysed in chunks (the iOS model timeout is 30 s per call).
- Every timestamp from the model is checked against the transcript and the duration before a frame is taken.
- The Mac job and the inbox watcher stay off the push-to-talk session path; logs carry counts and durations only.
- A share extension plus an App Group hands a shared URL to the iOS app; the extension does not do the work.
- No configuration has a default (output folder, inbox folder, tool paths, analysis model): missing ones are reported.

## Decisions (user, 2026-11-27)

- iPhone-local mode: **captions only, no screenshots** (links to the moments instead); a video without captions goes to the Mac. The Mac can add screenshots later to a digest made on the iPhone.
- Library: **iCloud Drive/untype/Videos** (`UNTYPE_VIDEO_LIBRARY` on the Mac). untype studio's library has to include it (a change in untype studio).
- Analysis model on the Mac: the model of Refine (`config.llm`); on the iPhone: the model of the app's Settings.
- An app feature in Swift; the command line is `untype video-digest` (no separate TypeScript tool).

## Progress

- Done (2026-11-27): `YouTubeVideo` (player API, metadata, captions, the original audio's language — a dubbed video's first automatic track was Arabic and produced an Arabic digest before the fix), `SonioxFileTranscriber`, `VideoDigestAnalyzer` (parts of 60 000 characters, times checked), `VideoDigestDocument` (HTML, DOCX with a stored-zip writer), `VideoDigestPipeline` (resumable stages, `VideoMediaSource`), `YtDlpMediaSource` + `VideoDigestMacSettings` (macOS), `untype video-digest <url> --llm-provider … --llm-model … [--language …] [--docx] | --resume <folder>`. Tests: `VideoDigestTests` (7), 582/582. iOS app builds with the core.
- Verified: Karpathy, "Software Is Changing (Again)" (39:31, dubbed into 19 languages): English automatic captions, 12 key points, 13 sections, 8 moments with 1080p screenshots, HTML and DOCX (opened with `textutil`), in 2.5 min with Claude Opus 5.5 on Azure.
- Found: 2 of 8 screenshots missed the slide (the speaker describes it before it is shown; a wide shot). Fixed (step 1): about 24 s around each moment (4 s before, 20 after), a frame every 3 s, put on a numbered contact sheet; the analysis model, looking at it, picks the frame for the moment (the sharpest when it cannot). Rerun on the same digest with `--resume`: 6 of 8 full-frame slides, the other 2 a stage shot with the slide legible (the video never shows those slides full-frame). 583/583.

## Next

1. ~~Better screenshots~~ done. 2–4 done (Mac build 96; iPhone build 5 with the share extension). 2. Mac: "Digest a video…" window (address, language, DOCX, progress, open the result) and the iCloud request inbox. 3. iPhone: a Videos tab (address or paste, language, DOCX, "on this iPhone" / "on my Mac"), the library folder chosen once (iCloud Drive/untype/Videos, kept as a bookmark), captions-only processing kept in the foreground. 4. Share extension. 5. untype studio: the iCloud library. 6. Docs: FR, design, configuration guide (`UNTYPE_VIDEO_LIBRARY`, `UNTYPE_YTDLP_PATH`, `UNTYPE_FFMPEG_PATH`, `UNTYPE_DENO_PATH`), issues.

## Open questions (answered above)

- Where the video library lives: iCloud Drive (seen by the iPhone), `~/Recordings` (untype studio's library), or untype studio's library moved to iCloud.
- The analysis model on the Mac: Refine's, the meeting assistant's, or its own setting.
- If a spike fails: whether a reduced iPhone-local mode is acceptable.

## Build order

1. Shared core with `VideoSource`. 2. Mac source, end to end, into a folder untype studio opens. 3. iOS source. 4. iCloud request path. 5. Share extension.
