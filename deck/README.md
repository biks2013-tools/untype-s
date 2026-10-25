# untype technical deck

A 59-slide HTML presentation about untype build 28 (what it is, how it works, the menu-bar interface, installation, configuration, operation), built with the `nbg-design` skill on its **BikS2013 theme** (ink and copper on warm paper, Avenir Next, the BikS2013 wheel lockups) and decorated with photorealistic images generated for this purpose in the same palette and with real screenshots of the untype interface.

**Live deck (HTML):** https://biks2013-tools.github.io/untype-s/ — published automatically by GitHub Pages, see [Publishing](#publishing-github-pages).

## Deliverables

| File | Purpose |
|---|---|
| `untype-deck.html` | The self-contained deck (all images embedded). Open in any browser; arrow keys or the on-screen buttons navigate. Right-click for the in-deck menu (edit text, resize shapes, export to PDF, save an edited copy). |
| `untype-deck.pdf` | One page per slide, exported from the HTML with the skill's exporter. |
| `untype-deck.rebuild.mjs` | Re-embeds the newest version of the in-deck editing tools after the nbg-design skill is updated (`node untype-deck.rebuild.mjs --check` reports, without `--check` it rebuilds and re-exports the PDF). |

## Sources and how to rebuild

- `src/shell-head.html`, `src/slides.html`, `src/shell-tail.html`: the deck source, authored with `{{TOKEN}}` image placeholders.
- `images/generate-images.sh`: generates the photo set with `image-tool` (Azure OpenAI `gpt-image-2`) in the BikS2013 palette (charcoal ink, copper and amber accents, cream and paper surfaces; nothing teal). Existing PNGs are skipped, so delete a file to regenerate it. Prompts live in the script.
- `images/make-datauris.sh`: converts every PNG to a 1600 px JPEG and writes `assets/<name>.datauri.txt`, the form the embedder consumes. `assets/logo-*.datauri.txt` are the BikS2013 lockups, copied from the skill's `BikS2013-Design/assets/`.
- `screens/`: real screenshots of the running app (menu-bar dropdown, Transcript window, Settings General and Prompts), captured with `screencapture -x -o -l <window-id>`. `screens/make-datauris.sh` turns them into `assets/ui-*.datauri.txt`. A screenshot must never show transcript text, keys or other personal content: the Transcript-window shot has its transcript body blurred. The overlay on the overlay slide is drawn in HTML, because capturing it would mean recording live.
- `build.sh`: concatenates the sources, embeds the assets, inlines the deck menu with `--theme biks2013` (copper toolbars, the assistant briefed on the BikS2013 system), runs the strict verifier, writes the rebuild script and exports the PDF. Uses the newest installed `nbg-design` plugin, 1.26.0 at the last build (path overridable with `NBG_DESIGN_SKILL`) and Chrome for the PDF.

```
./images/generate-images.sh   # only when images must be (re)generated
./images/make-datauris.sh
./screens/make-datauris.sh   # after replacing a screenshot
./build.sh                    # or ./build.sh --no-pdf
```

`untype-deck.src.html` is an intermediate file produced by the build.

## Publishing (GitHub Pages)

The HTML deck is published at **https://biks2013-tools.github.io/untype-s/** by the workflow `.github/workflows/deploy-deck.yml` (on the `deck` branch). Every push to `deck` that touches anything under `deck/` (or the workflow itself) rebuilds `untype-deck.html` from the sources (`./build.sh --no-pdf`) and deploys it as the site's `index.html`; the workflow can also be started by hand from the Actions tab (*Run workflow*). The PDF is not rebuilt by the workflow.

The workflow does not have the `nbg-design` plugin, so it builds with `tools/nbg-design/`, a vendored copy of the plugin's `scripts/` folder (`tools/nbg-design/plugin.json` records the version). After updating the plugin locally, run `tools/sync-nbg-design.sh` and commit the result so the published deck carries the newer editing tools.

Repository settings the workflow relies on (already applied): Pages source = *GitHub Actions*; the `github-pages` environment allows deployments from the `deck` branch in addition to `main`.
