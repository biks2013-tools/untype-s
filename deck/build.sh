#!/usr/bin/env bash
# Builds deck/untype-deck.html from deck/src/*.html, embeds the images (deck/assets/*.datauri.txt),
# inlines the right-click deck menu (BikS2013 theme), verifies the deck and exports the PDF.
# It runs the scripts in tools/deck-kit/ (refreshed from the design skill by a maintainer script kept out of the repository).
# Usage: ./build.sh [--no-pdf]
set -euo pipefail
cd "$(dirname "$0")"
SK="tools/deck-kit"

cat src/shell-head.html src/slides.html src/shell-tail.html > untype-deck.src.html
node "$SK/embed-assets.mjs" untype-deck.src.html -o untype-deck.html --theme biks2013 --assets assets
node "$SK/add-deck-menu.mjs" untype-deck.html --theme biks2013
node "$SK/verify-deck.mjs" untype-deck.html --strict
if [ "${1:-}" != "--no-pdf" ]; then
  node "$SK/export-pdf.mjs" untype-deck.html -o untype-deck.pdf
fi
