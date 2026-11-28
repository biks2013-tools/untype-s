# Issues - Pending Items

Register of issues, pending items and discrepancies of the untype deck. Pending items first (most critical on top), completed items after.

## Pending

_None._

## Completed

### Deck rewritten as a user guide for build 87 (2026-11-20)

- **Issue:** the deck described build 28 and was written for a technical audience: the pipeline, hotkey detection layers, audio capture, provider protocols, the composite LLM call, the latency record, the code layout, building, packaging, signing, the configuration resolution chain, state files, the command line and the contributor guardrails. Builds 29 to 87 added most of what a user sees today, and none of it was in the deck.
- **Solution:** 48 slides for users, in six parts: what untype is, dictation, meetings, install and set up, settings, everyday use. All technical-design and developer slides were removed. New material: the single hold-or-tap hotkey with hands-free turns, delivery to the app the turn started in, whole-sentence refine and edits kept, the clickable overlay with its tray, pinned chips and dragging, the Alternative LLM and the four experimental operators, Push-to-Act, the dictionary and Only my voice, the three speech providers, meeting recording with the transcription window, pause, attachments, saved files, Apple Notes, the Outlook calendar and the meeting assistant, the fourth permission (Screen & System Audio Recording) and the macOS 27 name of Accessibility, the provider keys per feature, and the nine Settings panes. Seven Settings screenshots were taken from build 87; two photos (`meeting-call`, `meeting-notes`) were generated in the BikS2013 palette. The old screenshots of builds 27 and 28 were removed.
- **Left as it is:** the README on `main` still calls the deck a "Technical presentation (59 slides)"; `main` is outside the deck's publishing scope. The photos `module-layout`, `signing-seal`, `guardrails-bridge`, `streaming-audio`, `prompt-writing`, `troubleshoot-logs` and `cover-portrait` are no longer used by any slide and stay in `deck/images/` and `deck/assets/`.

### Deck updated to build 28: voice-commands switch; plan-037 now released (2026-10-25)

- **Issue:** build 28 added Settings › General › Protocol › *Voice commands* (`--[no-]voice-commands`, `UNTYPE_VOICE_COMMANDS`, default on; off means no spoken marker is recognised). The deck also still said that Follow-up and Selection were uncommitted and that build 24 was the latest release, while builds 27 and 28 had been committed and released.
- **Solution:** the protocol, operators, Settings, protocol-settings, daily-workflow and symptoms slides cover the switch, and the Settings screenshot was recaptured from build 28 to show it. The cover, numbers (281 tests), install, packaging and closing slides now say build 28 is the released version. The earlier pending item "Deck describes build 27, whose Follow-up and Selection work is not committed yet" is closed by this.

### Deck updated to build 27: menu-bar interface, new operators, Claude provider, moved repository (2026-10-25)

- **Issue:** the deck described build 13 (September 2026): a three-column window with an inspector, an overlay that showed transcript text, four operators, nine prompt files, two LLM providers and the `BikS2013/homebrew-untype` tap. Builds 14 to 27 replaced all of that.
- **Solution:** 59 slides now cover the menu-bar dropdown, the Transcript window and the Settings window (General and Prompts) with real screenshots of build 27; live typing at the caret; the text-free oscilloscope overlay (drawn in HTML); the seven operators with "This turn / Until changed"; Ask, Follow-up and Selection with recipes and their own symptoms; Claude through `anthropic` and `azure-anthropic` and the Ask limits; the fifteen prompt files with the hot-reloading editor; `events.log` and warm-session recovery; Soniox `stt-rt-v5`; and the move to the `biks2013-tools` organization (tap `biks2013-tools/untype`, Pages at `https://biks2013-tools.github.io/untype-s/`). The Transcript-window screenshot has its transcript body blurred because it showed the author's dictation.

### Build pinned to the design plugin 1.20.0, which is no longer installed (2026-10-25)

- **Issue:** `build.sh` hard-coded the design plugin's version path (1.20.0), so the build failed once the plugin updated to 1.26.0.
- **Solution:** `build.sh` picked the newest installed version and the vendored scripts used by GitHub Actions were refreshed to 1.26.0. (Since 2026-11-28 the build runs `tools/deck-kit/` only, see below.) A CI-style build with the vendored copy passes the strict verifier.

### Other brands' text removed from the deck tools (2026-11-28)

- **Issue:** the vendored copy of the design skill's scripts and the menu inlined in the published deck carried the skill's other themes, with their brand names in the assistant's briefings, usage texts, comments and the code's class names.
- **Solution:** `deck/tools/deck-kit/` holds only the nine scripts the build runs, with only the BikS2013 theme and neutral code names (`dk-…`). It is refreshed from the skill by a maintainer script kept out of the repository (it carries the list of brand texts to remove and fails if one is left). `build.sh` and the Pages workflow run `deck-kit` only; `build.sh` is the way to rebuild. The deck passes the strict verifier and the PDF was re-exported.

### Section-divider label collided with its caption under the BikS2013 theme (2026-09-12)

- **Issue:** after switching the deck from the skill's default theme (Aptos) to the BikS2013 theme (Avenir Next), the 64 px divider label of the sections "Configuration and moving parts" and "Operating and troubleshooting" wrapped to two lines, because Avenir Next runs wider than Aptos, and its second line overlapped the caption fixed at `top: 700px` (visible on slides 34 and 45).
- **Solution:** in `deck/src/shell-head.html` the `.divider .label` is now anchored by its bottom edge (`bottom: 390px`, `line-height: 1.05`, `text-wrap: balance`) so a two-line label grows upwards; the numeral moved from `top: 360px` to `top: 330px` to leave room, and the caption sits at `top: 712px`. The closing slide (slide 50), which positions its label with an inline `top`, sets `bottom: auto` so it keeps its custom layout. Verified on all six dividers at 1440×900.

### Deck photography was teal-toned, off the BikS2013 palette (2026-09-12)

- **Issue:** the 18 generated photos were prompted with the default theme's "muted teal and cream" palette; on the ink-and-copper deck they clashed, and the theme forbids teal or cyan anywhere.
- **Solution:** `deck/images/generate-images.sh` now prompts for charcoal ink, warm copper and amber accents, cream and paper surfaces ("no teal, no blue"); the whole set was regenerated with `image-tool` (Azure OpenAI `gpt-image-2`, high quality, about 100 s per image, three in parallel) and re-encoded with `make-datauris.sh`.
