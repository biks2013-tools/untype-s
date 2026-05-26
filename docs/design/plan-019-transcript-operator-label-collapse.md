# Plan 019: Transcript Operator Label Collapse

## Provenance
- User screenshot request: hide the `Refine`, `Translate`, `Clipboard`, and `Input` labels in the transcript action row when the central monitor area collapses below the width shown as the minimum acceptable labeled layout.
- Refined request: skipped because this is a localized UI layout correction with concrete screenshots and acceptance criteria.
- Investigation/research: skipped because no new approach, technology, library, or external behavior is introduced.
- Codebase scan: focused local scan only; the implementation is localized to `Sources/UntypeCore/NativeUntypeUILauncher.swift` and `Sources/UntypeCore/UntypeDesignSystem.swift`.

## Objective
Prevent transcript operator chip labels from wrapping when the usable center monitor column becomes narrow because the leading sidebar and/or trailing inspector consume window width.

## Implementation
1. Add a reusable `showsLabel` option to `UntypeOperatorChip`.
2. Measure the transcript action row's available width with a `GeometryReader` inside the center content column.
3. Keep operator labels visible at and above the minimum center width represented by the wide screenshot.
4. Hide only the operator labels below that width, leaving each chip as the status dot plus `R`, `T`, `C`, or `I`.
5. Preserve accessibility labels and operator toggle behavior regardless of visible label state.

## Files Modified
- `Sources/UntypeCore/NativeUntypeUILauncher.swift`
- `Sources/UntypeCore/UntypeDesignSystem.swift`
- `docs/design/project-design.md`
- `docs/design/project-functions.md`
- `Issues - Pending Items.md`

## Acceptance Criteria
- At the wide central monitor width, transcript operator chips still show `Refine`, `Translate`, `Clipboard`, and `Input`.
- Below that central monitor width, the same chips show only the red/accent status dot and letter.
- The breakpoint is based on the center content row width after sidebars/inspector are accounted for, not on total app window width.
- Operator clicks and keyboard behavior are unchanged.
- `swift build` succeeds.
- `swift test` passes.

## Verification
- `swift build` passed on 2026-05-26.
- `swift test` passed on 2026-05-26 with 130 tests passing.
- Live screenshot verification remains manual because the change is in the native macOS window.
