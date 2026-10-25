#!/usr/bin/env bash
# Builds deck/untype-deck.html from deck/src/*.html, embeds the images (deck/assets/*.datauri.txt),
# inlines the right-click deck menu (BikS2013 theme), verifies the deck, writes its rebuild script and exports the PDF.
# Usage: ./build.sh [--no-pdf]
set -euo pipefail
cd "$(dirname "$0")"
SK="${NBG_DESIGN_SKILL:-$(ls -d "$HOME"/.claude/plugins/cache/nbg-design/nbg-design/*/skills/nbg-design 2>/dev/null | sort -V | tail -1)}"
[ -d "$SK/scripts" ] || { echo "nbg-design skill not found at $SK (set NBG_DESIGN_SKILL)"; exit 1; }

cat src/shell-head.html src/slides.html src/shell-tail.html > untype-deck.src.html
node "$SK/scripts/embed-assets.mjs" untype-deck.src.html -o untype-deck.html --theme biks2013 --assets assets
node "$SK/scripts/add-deck-menu.mjs" untype-deck.html --theme biks2013
node "$SK/scripts/verify-deck.mjs" untype-deck.html --strict
if [ "${1:-}" = "--no-pdf" ]; then
  node "$SK/scripts/write-rebuild-script.mjs" untype-deck.html --no-pdf
else
  node "$SK/scripts/write-rebuild-script.mjs" untype-deck.html
  node "$SK/scripts/export-pdf.mjs" untype-deck.html -o untype-deck.pdf
fi
