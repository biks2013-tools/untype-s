#!/usr/bin/env bash
# Writes Casks/untype.rb for a published GitHub release into the Homebrew tap.
#
# The tap (github.com/biks2013-tools/homebrew-untype) is maintained in this
# repository at homebrew-tap/ (the default --tap-dir; originally added with git
# subtree). In that mode --commit commits the cask on the current branch of this
# repository and --push publishes homebrew-tap/ to the tap repository (remote
# "homebrew-tap"), which is what `brew tap biks2013-tools/untype` clones.
#
# Publishing does NOT use `git subtree push`: this repository's history has two
# subtree trailers naming the same mainline commit (a6d3c5e, from the 2026
# folder rename), and `git subtree split` aborts on them ("cache for ... already
# exists") on every run; fixing that would mean rewriting published history.
# Instead the committed tree of homebrew-tap/ is published as one fast-forward
# commit on top of the tap's current head (git commit-tree), so the tap always
# equals homebrew-tap/ at HEAD. A standalone clone of the tap can still be
# targeted with --tap-dir <clone>.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"

VERSION=""
BUILD=""
SHA256=""
TAP_DIR="$PROJECT_ROOT/homebrew-tap"
TAP_REMOTE="homebrew-tap"
TAP_BRANCH="main"
DO_COMMIT=0
DO_PUSH=0
PUSH_ONLY=0

usage() {
  cat <<'USAGE'
Usage:
  scripts/update-homebrew-cask.sh \
    --version 0.1.0 --build 10 \
    --sha256 <sha256 of untype-<version>.dmg> \
    [--tap-dir homebrew-tap] [--tap-remote homebrew-tap] [--tap-branch main] \
    [--commit] [--push]
  scripts/update-homebrew-cask.sh --push-only

Rewrites <tap-dir>/Casks/untype.rb so that it points at the GitHub release
tag v<version>-b<build> and its untype-<version>.dmg asset.

In-repository mode (default, --tap-dir is homebrew-tap/ in this repo):
  --commit     commits homebrew-tap/Casks/untype.rb on the current branch here
  --push       also publishes the committed homebrew-tap/ to <remote> <branch>
               as one fast-forward commit on top of the tap's head, so the tap
               repository (what `brew tap biks2013-tools/untype` clones) equals
               homebrew-tap/ at HEAD. Refuses when the tap holds content that
               homebrew-tap/ never had (e.g. a direct commit in the tap).
               Push this repository's branch separately.
  --push-only  publishes the committed homebrew-tap/ without touching the cask
               (e.g. after editing homebrew-tap/README.md and committing it).

Standalone mode (--tap-dir points at a clone of the tap, i.e. has .git):
  --commit  commits in that clone; --push pushes its current branch.
USAGE
}

fail() { printf 'error: %s\n' "$*" >&2; exit 1; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --version) VERSION="${2:-}"; shift 2 ;;
    --build) BUILD="${2:-}"; shift 2 ;;
    --sha256) SHA256="${2:-}"; shift 2 ;;
    --tap-dir) TAP_DIR="${2:-}"; shift 2 ;;
    --tap-remote) TAP_REMOTE="${2:-}"; shift 2 ;;
    --tap-branch) TAP_BRANCH="${2:-}"; shift 2 ;;
    --commit) DO_COMMIT=1; shift ;;
    --push) DO_COMMIT=1; DO_PUSH=1; shift ;;
    --push-only) PUSH_ONLY=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) fail "unknown argument: $1" ;;
  esac
done

if [[ "$PUSH_ONLY" -eq 0 ]]; then
  [[ -n "$VERSION" ]] || fail "--version is required"
  [[ -n "$BUILD" ]] || fail "--build is required"
  [[ "$SHA256" =~ ^[0-9a-f]{64}$ ]] || fail "--sha256 must be a 64-character hex digest"
fi
[[ -n "$TAP_DIR" ]] || fail "--tap-dir is required"
[[ -d "$TAP_DIR" ]] || fail "tap directory does not exist: $TAP_DIR"

if [[ -d "$TAP_DIR/.git" ]]; then
  MODE="standalone"
else
  MODE="subtree"
  TAP_DIR="$(cd -- "$TAP_DIR" && pwd)"
  [[ "$TAP_DIR" == "$PROJECT_ROOT/"* ]] || fail "subtree mode expects --tap-dir inside this repository: $TAP_DIR"
  git -C "$PROJECT_ROOT" remote get-url "$TAP_REMOTE" >/dev/null 2>&1 \
    || fail "git remote '$TAP_REMOTE' is missing; add it with: git remote add $TAP_REMOTE https://github.com/biks2013-tools/homebrew-untype.git"
fi
SUBTREE_PREFIX="${TAP_DIR#"$PROJECT_ROOT"/}"

# Publishes the committed tree of $SUBTREE_PREFIX as a fast-forward commit on
# top of $TAP_REMOTE/$TAP_BRANCH (see the header for why not `git subtree push`).
publish_tap() {
  local repo="$PROJECT_ROOT"
  if [[ -n "$(git -C "$repo" status --porcelain -- "$SUBTREE_PREFIX")" ]]; then
    fail "$SUBTREE_PREFIX/ has uncommitted changes; commit them first (only committed content is published)"
  fi
  git -C "$repo" fetch -q "$TAP_REMOTE" "$TAP_BRANCH"
  local remote_head remote_tree local_tree
  remote_head="$(git -C "$repo" rev-parse FETCH_HEAD)"
  remote_tree="$(git -C "$repo" rev-parse "${remote_head}^{tree}")"
  local_tree="$(git -C "$repo" rev-parse "HEAD:$SUBTREE_PREFIX")"
  if [[ "$remote_tree" == "$local_tree" ]]; then
    printf '==> tap %s %s already equals %s/ at HEAD, nothing to publish\n' "$TAP_REMOTE" "$TAP_BRANCH" "$SUBTREE_PREFIX"
    return
  fi
  # Overwriting is safe only if nothing in the tap would be lost: every file
  # there must equal homebrew-tap/ at HEAD or a version homebrew-tap/ once had
  # (otherwise someone committed in the tap directly).
  local mode type blob path commit seen unknown=""
  while read -r mode type blob path; do
    [[ "$(git -C "$repo" rev-parse --verify -q "HEAD:$SUBTREE_PREFIX/$path" || true)" == "$blob" ]] && continue
    seen=0
    while read -r commit; do
      if [[ "$(git -C "$repo" rev-parse --verify -q "$commit:$SUBTREE_PREFIX/$path" || true)" == "$blob" ]]; then
        seen=1
        break
      fi
    done < <(git -C "$repo" rev-list HEAD -- "$SUBTREE_PREFIX/$path")
    [[ "$seen" -eq 1 ]] || unknown="$unknown $path"
  done < <(git -C "$repo" ls-tree -r "$remote_head")
  if [[ -n "$unknown" ]]; then
    fail "tap $TAP_REMOTE/$TAP_BRANCH (${remote_head:0:7}) has content that $SUBTREE_PREFIX/ never had:$unknown (a direct commit in the tap?). Bring it here first, e.g.: git fetch $TAP_REMOTE $TAP_BRANCH && git archive FETCH_HEAD | tar -x -C $SUBTREE_PREFIX, review, commit, then publish again."
  fi
  local message new_commit
  message="$(git -C "$repo" log -1 --format=%s HEAD -- "$SUBTREE_PREFIX")"
  new_commit="$(git -C "$repo" commit-tree "$local_tree" -p "$remote_head" -m "$message")"
  printf '==> publishing %s/ to %s %s as %s (on top of %s)\n' "$SUBTREE_PREFIX" "$TAP_REMOTE" "$TAP_BRANCH" "${new_commit:0:7}" "${remote_head:0:7}"
  git -C "$repo" push -q "$TAP_REMOTE" "${new_commit}:refs/heads/${TAP_BRANCH}"
  git -C "$repo" fetch -q "$TAP_REMOTE" "$TAP_BRANCH"
  [[ "$(git -C "$repo" rev-parse 'FETCH_HEAD^{tree}')" == "$local_tree" ]] \
    || fail "tap was pushed but its tree does not equal $SUBTREE_PREFIX/ at HEAD"
  printf '==> tap published (remember to push this repository too: git push origin %s)\n' "$(git -C "$repo" branch --show-current)"
}

if [[ "$PUSH_ONLY" -eq 1 ]]; then
  [[ "$MODE" == "subtree" ]] || fail "--push-only applies to the in-repository tap (homebrew-tap/)"
  publish_tap
  exit 0
fi

CASK="$TAP_DIR/Casks/untype.rb"
mkdir -p "$TAP_DIR/Casks"

cat > "$CASK" <<CASK
cask "untype" do
  version "${VERSION},${BUILD}"
  sha256 "${SHA256}"

  url "https://github.com/biks2013-tools/untype-s/releases/download/v#{version.csv.first}-b#{version.csv.second}/untype-#{version.csv.first}.dmg"
  name "untype"
  desc "Push-to-talk voice dictation with optional LLM refinement and translation"
  homepage "https://github.com/biks2013-tools/untype-s"

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

    Technical deck: https://biks2013-tools.github.io/untype-s/
    ~/.tool-agents/untype/.env is kept on uninstall and on zap.
  EOS
end
CASK

printf '==> wrote %s (version %s, build %s)\n' "$CASK" "$VERSION" "$BUILD"

if [[ "$MODE" == "standalone" ]]; then
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
else
  if [[ "$DO_COMMIT" -eq 1 ]]; then
    git -C "$PROJECT_ROOT" add "$SUBTREE_PREFIX/Casks/untype.rb"
    if git -C "$PROJECT_ROOT" diff --cached --quiet -- "$SUBTREE_PREFIX/Casks/untype.rb"; then
      printf '==> cask already up to date, nothing to commit\n'
    else
      git -C "$PROJECT_ROOT" commit -q -m "homebrew: untype ${VERSION} build ${BUILD}" -- "$SUBTREE_PREFIX/Casks/untype.rb"
      printf '==> committed %s/Casks/untype.rb on %s\n' "$SUBTREE_PREFIX" "$(git -C "$PROJECT_ROOT" branch --show-current)"
    fi
  fi
  if [[ "$DO_PUSH" -eq 1 ]]; then
    publish_tap
  fi
fi

cat <<NEXT

Next:
  brew update && brew upgrade --cask untype          # existing users
  brew tap biks2013-tools/untype && brew install --cask untype   # new users
NEXT
