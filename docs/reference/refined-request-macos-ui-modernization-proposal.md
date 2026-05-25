# Refined Request: macOS UI Modernization Proposal

## Category
Design / Documentation / Technical Research

## Objective
Discover the current `untype ui` design from the SwiftUI/AppKit source code and propose a modern macOS-oriented UI design that preserves existing behavior while aligning more closely with current Apple Human Interface Guidelines.

## Scope
- In scope:
  - Read the current native UI source, especially `Sources/UntypeCore/NativeUntypeUILauncher.swift` and `Sources/UntypeCore/UntypeUISettings.swift`.
  - Summarize the existing UI structure, user-facing controls, and workflows.
  - Research current official Apple guidance relevant to macOS windows, toolbars, sidebars, panels, controls, and accessibility.
  - Produce a durable design proposal under `docs/design/`.
  - Update project-level design/functional documentation to register the proposed design direction.
- Out of scope:
  - Implementing UI code changes.
  - Capturing live screenshots.
  - Changing persisted settings, credentials, provider configuration, runtime behavior, or hotkey behavior.
  - Version-control operations.

## Requirements
- The proposal must preserve the existing runtime capabilities: manual listening, push-to-talk, provider configuration, protocol operators, LLM settings, transcript/history/events monitoring, export actions, and overlay status.
- The proposal must be grounded in the current source code and include file/line references for the existing implementation.
- The proposal must use current official Apple design guidance as reference material.
- The proposal must describe layout, navigation, toolbar/header behavior, inspector/settings behavior, monitoring surfaces, status/permission presentation, overlay behavior, and accessibility expectations.
- The proposal must identify implementation phases and acceptance criteria for future code work.

## Constraints
- Do not perform version-control operations.
- Do not add dependencies.
- Do not expose secrets.
- Do not create fallback configuration behavior.
- Keep reference/design artifacts under the project documentation folders.

## Acceptance Criteria
- A technical research note exists under `docs/reference/` or `docs/research/` with current Apple guidance and sources.
- A design proposal file exists under `docs/design/plan-xxx-<description>.md`.
- `docs/design/project-design.md` references the proposal.
- `docs/design/project-functions.md` registers the proposed UI modernization requirement.
- The final response summarizes the proposed design and links the created files.

## Assumptions
- The requested deliverable is a proposal, not an implementation patch.
- The modernized UI should remain a native macOS SwiftUI/AppKit experience.
- The current single-window monitor plus optional overlay model remains appropriate, but its layout can be reorganized to better match macOS conventions.

## Open Questions
- Whether the user wants a visual mockup/image after reviewing the written proposal.
- Whether implementation should prioritize structural navigation changes, visual polish, or overlay redesign first.

## Original Request
> can you discover the ui design from the source code and propose 
> a modern ui design close to MACOS visual guidelines ?
