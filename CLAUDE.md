<structure-and-conventions>
## Structure & Conventions — Documentation Map

<!-- Maintained automatically. The master copy lives at
     ~/.claude/structure-and-conventions.md (claude-workdocs repo) and the SessionStart
     hook ~/.claude/scripts/sync-claude-md.sh keeps this copy of the block up to date —
     edit the master, never this block. The block is committed with the repository on
     purpose: it tells anyone (human or agent) working with this repo where the
     project's documentation lives and how to read and maintain it. -->

### Where the documentation lives

- `docs/plans/` — every plan, one file per plan, named `plan-NNN-<indicative-description>.md`.
- `docs/design/` — all other planning and design documents:
  - `project-design.md` — the complete, always-current project design; update it with every new design or design change.
  - `project-functions.md` — the registry of all functional requirements and feature descriptions.
  - `configuration-guide.md` — the project's configuration guide, when one exists (structure below).
- `docs/reference/` — all reference material collected for the project.
- `docs/refined_requests/` — every refined request specification (create the folder if missing), one file per request named `refined-request-NNN-<slug>.md`. `NNN` is a zero-padded three-digit sequential number: the next number is the highest `NNN` already present in the folder plus one, starting at `001` — and when the category has an archive history branch, the archive's numbering counts too (see "Archiving historical documents" below). `<slug>` is the request slug reused by all downstream artifacts of the same request.
- `docs/prompts/` — every prompt created while working on the project (create the folder if missing), one file per prompt named `NNN-<indicative-description>.md`. `NNN` is a zero-padded three-digit sequential number: the next number is the highest `NNN` already present in the folder plus one, starting at `001` — and when the category has an archive history branch, the archive's numbering counts too (see "Archiving historical documents" below). The description states the prompt's use and purpose.
- `docs/tools/<tool-name>.md` — one dedicated documentation file per project tool.
- `test_scripts/` — every test script goes here; create the folder if it doesn't exist.
- `Issues - Pending Items.md` (project root) — the register of every issue, pending item, inconsistency, or discrepancy detected while working on the project. Pending items come first (most critical and important on top), completed items after. Whenever a defect or issue is fixed, check this file for an item to remove.

### How to use the documentation

- Every time an issue is solved, it must be resolved AND both the issue and the solution must be thoroughly documented.
- This file's "Tools" section (when present) lists each project tool with a one-or-two-sentence description of what it is capable of and the relative path to its dedicated documentation file under `docs/tools/` — retrieve the full documentation from there whenever it is needed. Full tool documentation must never be inlined into this file.
- Before writing any code script, consult the "Tools" section and the documentation under `docs/tools/` to check whether the planned code fits the scope of an existing tool. If so, implement it as an extension of that tool; otherwise build a generic, abstract version of the code as a new tool in the project's toolset, document it under `docs/tools/`, and reference it in the "Tools" section. The goal is to progressively grow the tools needed to test, evaluate, generate data, collect information, etc., and reuse them consistently.

### Archiving historical documents (history branches)

- A project MAY move accumulated historical, write-once process artifacts — deployment reports, codebase scans, refined requests, plans, session handoffs, and similar — off the default branch to keep its documentation lean. Living, authoritative documents (`project-design.md`, `project-functions.md`, the guides, tool docs, the issue register) are never archived.
- Each archived category gets a dedicated **orphan, docs-only branch** named `<category>-history`, whose tree contains ONLY that category's files at their original repository paths — so retrieval paths never change: `git show <category>-history:<original-path>`, no branch switching required. A pointer note/README stays in the category's folder on the default branch stating the branch name, the retrieval command, and (for numbered categories) the next number. Archive branches are append-only: never rebase, rewrite, delete, or merge them.
- **Numbering across the archive**: for every `NNN`-numbered folder, the next number is `max(highest NNN in the folder, highest NNN on the category's archive branch) + 1`. Before creating the FIRST document of a numbered category, check whether an archive branch exists for it (the folder's README/pointer note, or `git branch --list --all '*-history'`) and continue from the archive's highest number — never restart at `001`, never reuse an archived number. The archive branch is authoritative over the pointer note's recorded "next number" if they disagree.
- **Migration** runs in a temporary linked worktree so the main checkout — and any uncommitted changes in it — is never disturbed: `git worktree add <tmp> <category>-history` (first-time archiving: `git worktree add --detach <tmp> <default-branch>`, then inside it `git switch --orphan <category>-history` and `git checkout <default-branch> -- <category-paths>`); bring the new artifacts over at their original paths and commit ONLY the category's files; then on the default branch `git rm` the migrated files, update the pointer note, and commit referencing the archive commit. Verify with `git ls-tree -r <category>-history --name-only` and a `git show` spot-check.
- The project's concrete category → branch registry (which categories are archived, under which branch names) is project-specific and lives OUTSIDE this synced block — typically a "Document Archiving Strategy" section in the project's CLAUDE.md.

<configuration-guide>
- A configuration guide, when requested, is created at `docs/design/configuration-guide.md` and explains:
  - When multiple configuration options exist (config file, env variables, CLI params, etc.), what the options are and the priority of each one.
  - The purpose and use of each configuration variable.
  - How the user can obtain such a configuration variable.
  - The recommended approach for storing or managing the variable.
  - Which options exist for the variable and what each option means for the project.
  - Any default value the parameter has.
  - For configuration parameters that expire (e.g., PAT keys, tokens), propose adding a parameter that captures the expiration date, so the app or service can proactively warn users to renew.
</configuration-guide>

</structure-and-conventions>

<project-guardrails>
## Project-Specific Guardrails

- **Do not break push-to-talk.** Any change to the native UI, session controls, hotkey configuration, permission flow, overlay, runtime startup/stop logic, or available protocol features must preserve the full push-to-talk wiring: configured hotkey listening must remain active when enabled, press and release events must reach the hotkey-owned runtime session, the audio gate must open on press and close on release, the recording/finalizing overlay must be shown and hidden correctly, and processed output delivery must still run after release.
- Before finishing UI or feature changes that can affect push-to-talk, verify the relevant wiring in `NativeUntypeUILauncher`, `UntypeHotkeyMonitor`, `HotkeySessionControl`, and `TranscriptionSessionRuntime`. Prefer running `swift build`, focused hotkey/push-to-talk tests when available, and a manual smoke check when macOS permissions or overlay behavior cannot be automated.
- **Do not break focused-input delivery.** Returning processed output to the active (focused) input control is a fundamental feature on par with push-to-talk; no change or deploy may regress it. Any change touching `FocusedInputDelivery`, `FocusedInputHelper`, `VoiceAgentProtocolController`, the packaging script, or any redeploy of `untype.app` must be followed by a delivery verification: perform (or ask the user to perform) a push-to-talk release into a focused text field and confirm the newest record in `~/.tool-agents/untype/release-latency.jsonl` shows `focused_input.ok=true`.
- Since build 7 (2026-09-12) `untype.app` MUST be packaged with `scripts/package-macos-app.sh --sign-identity "Developer ID Application: GEORGIOS MARINOS (9F9H8NCAUB)" --notary-profile untype-notary` (see `docs/design/deployment-guide.md`, "production procedure"); never redeploy an `--unsigned` (ad-hoc) bundle, because an ad-hoc signature changes the TCC designated requirement on every build and silently revokes the macOS **Accessibility** grant (symptom: `focused_input_failed` / `accessibility_not_trusted` in the latency log). If a grant is lost anyway (e.g. after the certificate is renewed), the recovery is `tccutil reset Accessibility com.local.untype`, relaunch, re-add in System Settings → Privacy & Security → Accessibility. Never reset Input Monitoring when only Accessibility is broken — that breaks push-to-talk. After every redeploy, ask the user to verify `focused_input.ok=true` in the latency log.
</project-guardrails>

## Document Archiving Strategy

| Category | Archive branch | Pointer note | Contents |
|---|---|---|---|
| Presentation deck | `deck` (orphan **working** branch, not an archive: edit it in a linked worktree at `../untype-deck`, commit there, never merge with `main`) | `deck/README.md` | `deck/` (HTML, PDF, rebuild script, sources, generated images, assets, build scripts) and `test_scripts/screenshots/`. The HTML deck is published at https://biks2013.github.io/untype-s/ by the branch's `.github/workflows/deploy-deck.yml` on every push to `deck`. |
