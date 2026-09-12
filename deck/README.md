# Deck pointer

The untype technical presentation (50 slides, generated photography, build sources, PDF, rebuild script) and its verification screenshots live on the orphan branch **`deck`**, at their original paths (`deck/`, `test_scripts/screenshots/`). The branch shares no history with `main`: changes on `main` never reach the deck and deck commits never reach the application.

**Published deck (HTML):** https://biks2013.github.io/untype-s/ — rebuilt and deployed to GitHub Pages by the branch's `.github/workflows/deploy-deck.yml` on every push to `deck` that changes the deck.

Work on the deck in its own linked worktree, never by switching branches here:

```
git worktree add ../untype-deck deck     # once; the folder sits next to this checkout
cd ../untype-deck/deck
./build.sh                               # edit src/, then rebuild, then commit on the deck branch
```

Read files without a worktree:

```
git show deck:deck/README.md
git show deck:deck/untype-deck.pdf > untype-deck.pdf
git ls-tree -r deck --name-only
```

Rules: never merge or cherry-pick between `deck` and `main` in either direction; push both branches if the repository is pushed to a remote. Initial commit on the branch: `0dd55e5` (2026-09-12).
