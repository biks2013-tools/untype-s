# macOS UI Modernization Research for `untype ui`

## Scope
This note captures the external design guidance used for the `untype ui` modernization proposal in `docs/design/plan-016-macos-ui-modernization-proposal.md`.

## Source Quality
Primary sources are Apple Developer Human Interface Guidelines pages and Apple Developer documentation search results. The guidance below is intentionally limited to stable macOS interface patterns that map directly to the current SwiftUI/AppKit implementation.

## Relevant Apple Guidance

### macOS App Character
Apple's macOS guidance emphasizes powerful, flexible, spacious productivity workflows and supports personalization such as customizable toolbars and configurable windows. For `untype ui`, this supports a window model that lets people keep a dense monitoring surface visible while tailoring side panes and toolbar controls to their workflow.

### Window Structure
Apple describes windows as boundaries for app content and as a multitasking unit on macOS. For `untype ui`, the main window should remain the command center for monitoring, configuration, and troubleshooting, with the push-to-talk overlay kept as a supplementary transient surface rather than a replacement for the window.

### Toolbar
Apple describes toolbars as places for frequently used commands, controls, navigation, and search. In `untype ui`, the current header buttons should become a native-style toolbar with the primary session action, refresh, inspector visibility, and optional push-to-talk status/actions.

### Sidebar
Apple describes sidebars as leading-side navigation between sections and a broad view of an app's information hierarchy. The current `Transcript`, `History`, and `Events` tab view can become a sidebar/source-list navigation pattern, which is more macOS-native for switching between persistent app sections.

### Panels and Inspectors
Apple describes macOS panels as floating supplementary controls, options, or information related to the active window or selection. For this project, the right settings pane should behave like an inspector: collapsible, context-preserving, and subordinate to the main monitoring content.

### Controls and Buttons
Apple's component guidance treats buttons as instantaneous actions and macOS push buttons as standard controls that can show text, symbols, icons, or combinations. The redesigned UI should keep destructive or persistence-affecting actions explicit, keep export actions near the content they affect, and use icon+label only where it improves recognition.

### Accessibility
Apple's accessibility guidance emphasizes adaptable interfaces that work with system accessibility features. The redesign should not rely on color alone for session, warning, or operator state; it should preserve keyboard access, text selection, VoiceOver labels, focus states, and Dynamic Type/resizable-window resilience.

## Design Implications for `untype ui`
- Promote current header actions into a native toolbar.
- Replace peer top tabs with a leading sidebar/source list.
- Treat the right-side settings surface as an inspector rather than decorative stacked cards.
- Keep transcript, history, and event log as dense, scannable work surfaces.
- Present credentials, permissions, and audio as status rows with severity and short remediation hints.
- Keep push-to-talk overlay compact, material-backed, and secondary to the main window.
- Preserve existing privacy boundaries: no secret display, no automatic transcript persistence, and no hidden fallback configuration.

## References
- Apple Human Interface Guidelines: `https://developer.apple.com/design/human-interface-guidelines/`
- Designing for macOS: `https://developer.apple.com/design/human-interface-guidelines/designing-for-macos`
- Toolbars: `https://developer.apple.com/design/human-interface-guidelines/toolbars`
- Sidebars: `https://developer.apple.com/design/human-interface-guidelines/sidebars`
- Panels: `https://developer.apple.com/design/human-interface-guidelines/panels`
- Windows: `https://developer.apple.com/design/human-interface-guidelines/windows`
- Buttons: `https://developer.apple.com/design/human-interface-guidelines/buttons`
- Accessibility: `https://developer.apple.com/design/human-interface-guidelines/accessibility`
