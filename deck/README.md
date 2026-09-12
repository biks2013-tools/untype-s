# Deck archive pointer

The untype technical presentation (50 slides, generated photography, build sources, PDF, rebuild script) and its verification screenshots are archived on the orphan, docs-only branch **`deck-history`** at their original paths. Nothing else lives on that branch.

Retrieve without switching branches:

```
git show deck-history:deck/README.md                       # how the deck is built
git show deck-history:deck/untype-deck.html > untype-deck.html
git show deck-history:deck/untype-deck.pdf  > untype-deck.pdf
git ls-tree -r deck-history --name-only                    # everything archived
```

To work on the deck, check the branch out in a linked worktree and rebuild there:

```
git worktree add ../untype-deck deck-history
```

The branch is append-only: never rebase, rewrite, delete or merge it. Archive commit: `0dd55e5` (2026-09-12).
