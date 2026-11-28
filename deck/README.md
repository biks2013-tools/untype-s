# untype user guide deck

A 48-slide HTML presentation for the people who use untype, describing build 87: what the app does (dictation, the operators, Push-to-Act, meeting recording with the live transcript, attachments and the meeting assistant), how to install it and how to set it up (permissions, provider keys, the nine Settings panes). It has no technical-design or developer material: that lives in the repository's `docs/` on `main`. Built on the **BikS2013 theme** (ink and copper on warm paper, Avenir Next, the BikS2013 wheel lockups) and decorated with photorealistic images generated for this purpose in the same palette and with real screenshots of the untype interface.

**Live deck (HTML):** https://biks2013-tools.github.io/untype-s/ — published automatically by GitHub Pages, see [Publishing](#publishing-github-pages).

## Deliverables

| File | Purpose |
|---|---|
| `untype-deck.html` | The self-contained deck (all images embedded). Open in any browser; arrow keys or the on-screen buttons navigate. Right-click for the in-deck menu (edit text, resize shapes, export to PDF, save an edited copy). |
| `untype-deck.pdf` | One page per slide, exported from the HTML with the skill's exporter. |

## Sources and how to rebuild

- `src/shell-head.html`, `src/slides.html`, `src/shell-tail.html`: the deck source, authored with `{{TOKEN}}` image placeholders.
- `images/generate-images.sh`: generates the photo set with `image-tool` (Azure OpenAI `gpt-image-2`) in the BikS2013 palette (charcoal ink, copper and amber accents, cream and paper surfaces; nothing teal). Existing PNGs are skipped, so delete a file to regenerate it. Prompts live in the script.
- `images/make-datauris.sh`: converts every PNG to a 1600 px JPEG and writes `assets/<name>.datauri.txt`, the form the embedder consumes. `assets/logo-*.datauri.txt` are the BikS2013 lockups, copied from the design skill's `BikS2013-Design/assets/`.
- `screens/`: real screenshots of the running app (the Settings panes Push-to-Talk, Meetings, Speech, Operators, Language Models, Prompts and Permissions & Keys, build 87), captured with `screencapture -x -o -l <window-id>`. `screens/make-datauris.sh` turns them into `assets/ui-*.datauri.txt`. A screenshot must never show transcript text, keys or other personal content, so the Transcript, History, transcription and assistant windows are described in words, not shown. The overlay and its tray are drawn in HTML (the tray appears only under the mouse), and the menu-bar dropdown is described in words.
- `build.sh`: concatenates the sources, embeds the assets, inlines the deck menu with `--theme biks2013` (copper toolbars, the assistant briefed on the BikS2013 system), runs the strict verifier and exports the PDF. It runs the scripts in `tools/deck-kit/` and needs Chrome for the PDF.

```
./images/generate-images.sh   # only when images must be (re)generated
./images/make-datauris.sh
./screens/make-datauris.sh   # after replacing a screenshot
./build.sh                    # or ./build.sh --no-pdf
```

`untype-deck.src.html` is an intermediate file produced by the build.

## Publishing (GitHub Pages)

The HTML deck is published at **https://biks2013-tools.github.io/untype-s/** by the workflow `.github/workflows/deploy-deck.yml` (on the `deck` branch). Every push to `deck` that touches anything under `deck/` (or the workflow itself) rebuilds `untype-deck.html` from the sources (`./build.sh --no-pdf`) and deploys it as the site's `index.html`; the workflow can also be started by hand from the Actions tab (*Run workflow*). The PDF is not rebuilt by the workflow.

Both the workflow and `build.sh` use `tools/deck-kit/`: the scripts of the design skill that the build needs (embedder, deck menu, verifier, PDF exporter), refreshed from the skill by a maintainer script kept out of the repository, which keeps only the BikS2013 theme and leaves out the skill's other themes and their brands. Commit the refreshed `tools/deck-kit/` so the published deck carries the newer editing tools.

Repository settings the workflow relies on (already applied): Pages source = *GitHub Actions*; the `github-pages` environment allows deployments from the `deck` branch in addition to `main`.
