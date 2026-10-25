# Issues - Pending Items

Register of issues, pending items and discrepancies of the untype deck. Pending items first (most critical on top), completed items after.

## Pending

### Deck describes build 27, whose Follow-up and Selection work is not committed yet (2026-10-25)

- **Issue:** the deck was updated from the build 27 installed on the author's Mac. Ask (builds 25 and 26) is committed on `main`, but Follow-up, Selection, per-turn operators and the processing wave (plan-037, FR-38 to FR-41) were still uncommitted work on `main` at the time. The latest GitHub release and Homebrew cask are build 24, which has none of these operators. The install slide and the closing slide say so.
- **Action:** when plan-037 is committed and build 27 (or later) is released, drop the "ship with the next release" sentence from slide 29 and the "publish builds 25 to 27" open item from the closing slide. If plan-037 changes before it is committed, re-check the operator, Ask/Follow-up/Selection, prompt-file and recipe slides.

## Completed

### Deck updated to build 27: menu-bar interface, new operators, Claude provider, moved repository (2026-10-25)

- **Issue:** the deck described build 13 (September 2026): a three-column window with an inspector, an overlay that showed transcript text, four operators, nine prompt files, two LLM providers and the `BikS2013/homebrew-untype` tap. Builds 14 to 27 replaced all of that.
- **Solution:** 59 slides now cover the menu-bar dropdown, the Transcript window and the Settings window (General and Prompts) with real screenshots of build 27; live typing at the caret; the text-free oscilloscope overlay (drawn in HTML); the seven operators with "This turn / Until changed"; Ask, Follow-up and Selection with recipes and their own symptoms; Claude through `anthropic` and `azure-anthropic` and the Ask limits; the fifteen prompt files with the hot-reloading editor; `events.log` and warm-session recovery; Soniox `stt-rt-v5`; and the move to the `biks2013-tools` organization (tap `biks2013-tools/untype`, Pages at `https://biks2013-tools.github.io/untype-s/`). The Transcript-window screenshot has its transcript body blurred because it showed the author's dictation.

### Build pinned to nbg-design 1.20.0, which is no longer installed (2026-10-25)

- **Issue:** `build.sh` hard-coded the plugin path `nbg-design/1.20.0`, so the build failed once the plugin updated to 1.26.0.
- **Solution:** `build.sh` now picks the newest installed version (still overridable with `NBG_DESIGN_SKILL`), and `tools/sync-nbg-design.sh` refreshed the vendored scripts used by GitHub Actions to 1.26.0. A CI-style build with the vendored copy passes the strict verifier.

### Section-divider label collided with its caption under the BikS2013 theme (2026-09-12)

- **Issue:** after switching the deck from the NBG theme (Aptos) to the BikS2013 theme (Avenir Next), the 64 px divider label of the sections "Configuration and moving parts" and "Operating and troubleshooting" wrapped to two lines, because Avenir Next runs wider than Aptos, and its second line overlapped the caption fixed at `top: 700px` (visible on slides 34 and 45).
- **Solution:** in `deck/src/shell-head.html` the `.divider .label` is now anchored by its bottom edge (`bottom: 390px`, `line-height: 1.05`, `text-wrap: balance`) so a two-line label grows upwards; the numeral moved from `top: 360px` to `top: 330px` to leave room, and the caption sits at `top: 712px`. The closing slide (slide 50), which positions its label with an inline `top`, sets `bottom: auto` so it keeps its custom layout. Verified on all six dividers at 1440×900.

### Deck photography was teal-toned, off the BikS2013 palette (2026-09-12)

- **Issue:** the 18 generated photos were prompted with the NBG "muted teal and cream" palette; on the ink-and-copper deck they clashed, and the theme forbids teal or cyan anywhere.
- **Solution:** `deck/images/generate-images.sh` now prompts for charcoal ink, warm copper and amber accents, cream and paper surfaces ("no teal, no blue"); the whole set was regenerated with `image-tool` (Azure OpenAI `gpt-image-2`, high quality, about 100 s per image, three in parallel) and re-encoded with `make-datauris.sh`. The previous teal set remains in git history (commit `0dd55e5`).
