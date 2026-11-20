#if os(macOS)
import AppKit
import SwiftUI

/// Where each Settings pane was scrolled to.
///
/// A plain reference type, held by the view in `@State`, so that remembering a
/// position never invalidates the view: nothing here drives the UI.
@MainActor
public final class UntypePaneScrollStore {
    init() {}

    private var offsets: [String: CGFloat] = [:]

    func offset(for pane: UntypeSettingsPane) -> CGFloat? {
        offsets[pane.rawValue]
    }

    func set(_ offset: CGFloat, for pane: UntypeSettingsPane) {
        offsets[pane.rawValue] = offset
    }

    /// Forgets every remembered position, so the window opens at the top of
    /// each pane next time rather than where it was left in an earlier visit.
    func reset() {
        offsets.removeAll()
    }
}

/// Keeps a scroll position per Settings pane while one `Form` — one scroll view
/// — serves all of them.
///
/// A Form per pane would keep its position for free, but the extra rendering
/// makes scrolling visibly less smooth, so the panes share one scroll view and
/// the offset is saved and restored here.
///
/// No scroll observation is needed. When the pane changes, the shared scroll
/// view still sits at the offset the outgoing pane was left at — that carried-
/// over offset is the bug this fixes — so it is read then, filed under the pane
/// being left, and the incoming pane's own offset is put back.
struct UntypePaneScrollMemory: NSViewRepresentable {
    let pane: UntypeSettingsPane
    let memory: UntypePaneScrollStore

    func makeCoordinator() -> Coordinator {
        Coordinator(memory: memory)
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        let coordinator = context.coordinator
        let shown = pane
        DispatchQueue.main.async {
            coordinator.paneChanged(to: shown, from: view)
        }
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        context.coordinator.paneChanged(to: pane, from: view)
    }

    @MainActor
    final class Coordinator {
        private let memory: UntypePaneScrollStore
        private weak var scrollView: NSScrollView?
        private var shownPane: UntypeSettingsPane?

        init(memory: UntypePaneScrollStore) {
            self.memory = memory
        }

        func paneChanged(to pane: UntypeSettingsPane, from view: NSView) {
            if scrollView == nil {
                scrollView = Self.locateScrollView(from: view)
            }
            guard shownPane != pane else { return }
            if let leaving = shownPane, let offset = scrollView?.contentView.bounds.origin.y {
                memory.set(offset, for: leaving)
            }
            shownPane = pane
            // The incoming pane's rows are laid out after this update, so the
            // restore has to wait for them; otherwise it clamps to the height
            // of the content being replaced.
            DispatchQueue.main.async { [weak self] in
                self?.restore(pane)
            }
        }

        private func restore(_ pane: UntypeSettingsPane) {
            guard let scrollView, shownPane == pane else { return }
            let wanted = memory.offset(for: pane) ?? 0
            let documentHeight = scrollView.documentView?.bounds.height ?? 0
            let highest = max(0, documentHeight - scrollView.contentView.bounds.height)
            scrollView.contentView.scroll(to: CGPoint(x: 0, y: min(max(0, wanted), highest)))
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }

        /// Puts the shared scroll view back to the top. Resetting the stored
        /// offsets is not enough on its own: a pane that is still the selected
        /// one when the window reopens never changes, so nothing would restore
        /// it and the scroll view would keep the position it was closed at.
        static func scrollToTop(in root: NSView?) {
            guard let root, let scrollView = locateScrollView(from: root) ?? frontmostScrollView(in: root) else {
                return
            }
            scrollView.contentView.scroll(to: .zero)
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }

        /// The Form's own scroll view. `enclosingScrollView` finds it when this
        /// view sits inside the scrolled content; from a background it does
        /// not, so the nearest ancestor is searched front to back — the Form is
        /// in front of the prompts pane, which has a scroll view of its own.
        static func locateScrollView(from view: NSView) -> NSScrollView? {
            if let enclosing = view.enclosingScrollView {
                return enclosing
            }
            var node: NSView? = view.superview
            while let current = node {
                if let found = frontmostScrollView(in: current) {
                    return found
                }
                node = current.superview
            }
            return nil
        }

        static func frontmostScrollView(in view: NSView) -> NSScrollView? {
            for subview in view.subviews.reversed() {
                if let scrollView = subview as? NSScrollView {
                    return scrollView
                }
                if let found = frontmostScrollView(in: subview) {
                    return found
                }
            }
            return nil
        }
    }
}
#endif
