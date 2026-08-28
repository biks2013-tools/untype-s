<structure-and-conventions>
## Structure & Conventions — Documentation Map

<!-- Maintained automatically. The master copy lives at
     ~/.claude/structure-and-conventions.md (claude-workdocs repo) and the SessionStart
     hook ~/.claude/scripts/sync-claude-md.sh keeps this copy of the block up to date —
     edit the master, never this block. The block is committed with the repository on
     purpose: it tells anyone (human or agent) working with this repo where the
     project's documentation lives and how to read and maintain it. -->

### Where the documentation lives

- `docs/design/` — all planning and design documents:
  - `plan-NNN-<indicative-description>.md` — one file per plan.
  - `project-design.md` — the complete, always-current project design; update it with every new design or design change.
  - `project-functions.md` — the registry of all functional requirements and feature descriptions.
  - `configuration-guide.md` — the project's configuration guide, when one exists (structure below).
- `docs/reference/` — all reference material collected for the project.
- `docs/tools/<tool-name>.md` — one dedicated documentation file per project tool.
- `test_scripts/` — every test script goes here; create the folder if it doesn't exist.
- `prompts/` — every prompt created while working on the project (create the folder if missing); each file name has a sequential number prefix and describes the prompt's use and purpose.
- `Issues - Pending Items.md` (project root) — the register of every issue, pending item, inconsistency, or discrepancy detected while working on the project. Pending items come first (most critical and important on top), completed items after. Whenever a defect or issue is fixed, check this file for an item to remove.

### How to use the documentation

- Every time an issue is solved, it must be resolved AND both the issue and the solution must be thoroughly documented.
- This file's "Tools" section (when present) lists each project tool with a one-or-two-sentence description of what it is capable of and the relative path to its dedicated documentation file under `docs/tools/` — retrieve the full documentation from there whenever it is needed. Full tool documentation must never be inlined into this file.
- Before writing any code script, consult the "Tools" section and the documentation under `docs/tools/` to check whether the planned code fits the scope of an existing tool. If so, implement it as an extension of that tool; otherwise build a generic, abstract version of the code as a new tool in the project's toolset, document it under `docs/tools/`, and reference it in the "Tools" section. The goal is to progressively grow the tools needed to test, evaluate, generate data, collect information, etc., and reuse them consistently.

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
- Replacing the ad-hoc-signed `untype.app` bundle silently revokes the macOS **Accessibility** grant (symptom: `focused_input_failed` / `accessibility_not_trusted` in the latency log). After every redeploy, proactively warn the user to re-grant Accessibility (`tccutil reset Accessibility com.local.untype`, relaunch, re-add in System Settings → Privacy & Security → Accessibility). Never reset Input Monitoring when only Accessibility is broken — that breaks push-to-talk. Permanent fix tracked in "Issues - Pending Items.md": package with a stable self-signed code-signing identity.
</project-guardrails>
