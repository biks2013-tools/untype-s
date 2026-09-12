#!/usr/bin/env bash
# Writes Casks/untype.rb in the BikS2013/homebrew-untype tap for a published
# GitHub release, optionally committing and pushing the tap.
set -euo pipefail

VERSION=""
BUILD=""
SHA256=""
TAP_DIR=""
DO_COMMIT=0
DO_PUSH=0

usage() {
  cat <<'USAGE'
Usage:
  scripts/update-homebrew-cask.sh \
    --version 0.1.0 --build 10 \
    --sha256 <sha256 of untype-<version>.dmg> \
    --tap-dir ../homebrew-untype \
    [--commit] [--push]

Rewrites <tap-dir>/Casks/untype.rb so that it points at the GitHub release
tag v<version>-b<build> and its untype-<version>.dmg asset. --commit stages
and commits the cask in the tap; --push also pushes the tap's current branch.
USAGE
}

fail() { printf 'error: %s\n' "$*" >&2; exit 1; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --version) VERSION="${2:-}"; shift 2 ;;
    --build) BUILD="${2:-}"; shift 2 ;;
    --sha256) SHA256="${2:-}"; shift 2 ;;
    --tap-dir) TAP_DIR="${2:-}"; shift 2 ;;
    --commit) DO_COMMIT=1; shift ;;
    --push) DO_COMMIT=1; DO_PUSH=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) fail "unknown argument: $1" ;;
  esac
done

[[ -n "$VERSION" ]] || fail "--version is required"
[[ -n "$BUILD" ]] || fail "--build is required"
[[ "$SHA256" =~ ^[0-9a-f]{64}$ ]] || fail "--sha256 must be a 64-character hex digest"
[[ -n "$TAP_DIR" ]] || fail "--tap-dir is required"
[[ -d "$TAP_DIR/.git" ]] || fail "tap directory is not a git checkout: $TAP_DIR"

CASK="$TAP_DIR/Casks/untype.rb"
mkdir -p "$TAP_DIR/Casks"

cat > "$CASK" <<CASK
cask "untype" do
  version "${VERSION},${BUILD}"
  sha256 "${SHA256}"

  url "https://github.com/BikS2013/untype-s/releases/download/v#{version.csv.first}-b#{version.csv.second}/untype-#{version.csv.first}.dmg"
  name "untype"
  desc "Push-to-talk voice dictation with optional LLM refinement and translation"
  homepage "https://github.com/BikS2013/untype-s"

  livecheck do
    url :url
    regex(/^v?(\\d+(?:\\.\\d+)+)-b(\\d+)$/i)
    strategy :github_latest do |json, regex|
      match = json["tag_name"]&.match(regex)
      next if match.blank?

      "#{match[1]},#{match[2]}"
    end
  end

  depends_on macos: :sonoma

  app "untype.app"

  uninstall quit: "com.local.untype"

  zap trash: [
    "~/.tool-agents/untype/prompts",
    "~/.tool-agents/untype/release-latency.jsonl",
    "~/.tool-agents/untype/ui-state.json",
  ]

  caveats <<~EOS
    First launch:
      1. Click "Set keys..." on the welcome screen and enter at least one
         speech-to-text key (Soniox or ElevenLabs). Keys are stored in
         ~/.tool-agents/untype/.env, readable only by you.
      2. Click Start Listening once and allow the Microphone when macOS asks.
      3. System Settings > Privacy & Security > Accessibility > enable untype
         (needed for the push-to-talk hotkey and for inserting text into the
         focused field). Add untype under Input Monitoring too if the hotkey
         does not fire while another app is in front. Quit and relaunch after
         changing permissions.

    Technical deck: https://biks2013.github.io/untype-s/
    ~/.tool-agents/untype/.env is kept on uninstall and on zap.
  EOS
end
CASK

printf '==> wrote %s (version %s, build %s)\n' "$CASK" "$VERSION" "$BUILD"

if [[ "$DO_COMMIT" -eq 1 ]]; then
  git -C "$TAP_DIR" add Casks/untype.rb
  if git -C "$TAP_DIR" diff --cached --quiet; then
    printf '==> tap already up to date, nothing to commit\n'
  else
    git -C "$TAP_DIR" commit -q -m "untype ${VERSION} build ${BUILD}"
    printf '==> committed in %s\n' "$TAP_DIR"
  fi
fi

if [[ "$DO_PUSH" -eq 1 ]]; then
  git -C "$TAP_DIR" push -q origin HEAD
  printf '==> pushed\n'
fi

cat <<NEXT

Next:
  brew update && brew upgrade --cask untype          # existing users
  brew tap BikS2013/untype && brew install --cask untype   # new users
NEXT
