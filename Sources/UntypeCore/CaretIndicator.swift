import AppKit
import ApplicationServices
import SwiftUI

/// Finds the text caret of the focused control through Accessibility.
/// No dependencies on the rest of untype; safe to call off the main thread.
enum CaretLocator {
    /// Seconds an unresponsive app may hold up one Accessibility call.
    private static let messagingTimeout: Float = 0.25

    /// The caret (end of the selection) of the system-wide focused control, in
    /// Accessibility screen coordinates (origin top-left of the primary
    /// display). nil when the control does not report one, or belongs to
    /// `excludingPID`.
    static func caretRect(excludingPID: pid_t? = nil) -> CGRect? {
        guard let element = focusedElement() else {
            return nil
        }
        AXUIElementSetMessagingTimeout(element, messagingTimeout)
        if let excludingPID {
            var pid: pid_t = 0
            if AXUIElementGetPid(element, &pid) == .success, pid == excludingPID {
                return nil
            }
        }
        return caretRect(of: element)
    }

    /// The caret (end of the selection) of `element`.
    ///
    /// The rectangle of an empty range is not trusted first: AppKit text
    /// views report it one line too high. The characters around the caret
    /// give the place instead; the empty range is the last resort (an empty
    /// field).
    static func caretRect(of element: AXUIElement) -> CGRect? {
        var rangeRaw: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &rangeRaw) == .success,
              let rangeRaw, CFGetTypeID(rangeRaw) == AXValueGetTypeID()
        else {
            return nil
        }
        var selection = CFRange()
        guard AXValueGetValue(rangeRaw as! AXValue, .cfRange, &selection) else {
            return nil
        }
        let caret = selection.location + selection.length
        let empty = bounds(of: element, location: caret, length: 0).flatMap { isUsable($0) ? $0 : nil }
        // The character after the caret: its leading edge.
        if let next = bounds(of: element, location: caret, length: 1), isUsable(next) {
            return CGRect(x: next.minX, y: next.minY, width: 1, height: next.height)
        }
        // End of the text: the character before the caret. After a line
        // break the caret is at the start of the line under it.
        if caret > 0, let previous = bounds(of: element, location: caret - 1, length: 1), isUsable(previous) {
            if string(of: element, location: caret - 1, length: 1)?.last?.isNewline == true {
                let x = empty?.minX ?? origin(of: element)?.x ?? previous.minX
                return CGRect(x: x, y: previous.maxY, width: 1, height: previous.height)
            }
            return CGRect(x: previous.maxX, y: previous.minY, width: 1, height: previous.height)
        }
        guard var rect = empty else {
            return nil
        }
        // An empty field: only the empty range is left. Above the control's
        // own top it is the one-line-too-high answer.
        if let top = origin(of: element)?.y, rect.minY < top - 1 {
            rect.origin.y += rect.height
        }
        return CGRect(x: rect.minX, y: rect.minY, width: 1, height: rect.height)
    }

    private static func string(of element: AXUIElement, location: Int, length: Int) -> String? {
        var range = CFRange(location: location, length: length)
        guard let value = AXValueCreate(.cfRange, &range) else {
            return nil
        }
        var raw: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(
            element,
            kAXStringForRangeParameterizedAttribute as CFString,
            value,
            &raw
        ) == .success else {
            return nil
        }
        return raw as? String
    }

    private static func origin(of element: AXUIElement) -> CGPoint? {
        var raw: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &raw) == .success,
              let raw, CFGetTypeID(raw) == AXValueGetTypeID()
        else {
            return nil
        }
        var point = CGPoint.zero
        guard AXValueGetValue(raw as! AXValue, .cgPoint, &point) else {
            return nil
        }
        return point
    }

    /// The focused control: asked system-wide, then of the app in front
    /// (the system-wide query fails with "cannot complete" at times).
    static func focusedElement() -> AXUIElement? {
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, messagingTimeout)
        if let element = focusedElement(of: system) {
            return element
        }
        guard let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier else {
            return nil
        }
        let application = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(application, messagingTimeout)
        return focusedElement(of: application)
    }

    private static func focusedElement(of parent: AXUIElement) -> AXUIElement? {
        var raw: CFTypeRef?
        guard AXUIElementCopyAttributeValue(parent, kAXFocusedUIElementAttribute as CFString, &raw) == .success,
              let raw, CFGetTypeID(raw) == AXUIElementGetTypeID()
        else {
            return nil
        }
        return (raw as! AXUIElement)
    }

    private static func bounds(of element: AXUIElement, location: Int, length: Int) -> CGRect? {
        var range = CFRange(location: location, length: length)
        guard let value = AXValueCreate(.cfRange, &range) else {
            return nil
        }
        var raw: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(
            element,
            kAXBoundsForRangeParameterizedAttribute as CFString,
            value,
            &raw
        ) == .success, let raw, CFGetTypeID(raw) == AXValueGetTypeID()
        else {
            return nil
        }
        var rect = CGRect.zero
        guard AXValueGetValue(raw as! AXValue, .cgRect, &rect) else {
            return nil
        }
        return rect
    }

    /// Some controls answer with an empty or absurd rectangle instead of an
    /// error.
    static func isUsable(_ rect: CGRect) -> Bool {
        rect.height >= 4 && rect.height <= 400
            && rect.origin.x.isFinite && rect.origin.y.isFinite
            && !(rect.origin.x == 0 && rect.origin.y == 0 && rect.width == 0)
    }
}

/// Where the caret indicator goes for a caret rectangle.
enum CaretIndicatorLayout {
    static let size = CGSize(width: 44, height: 14)
    static let gap: CGFloat = 3

    /// The indicator's frame in AppKit screen coordinates (origin
    /// bottom-left): under the caret, left-aligned with it; above the caret
    /// when there is no room under it; kept inside the screen. nil when the
    /// caret is on no screen.
    ///
    /// - Parameters:
    ///   - caret: the caret in Accessibility coordinates (origin top-left).
    ///   - primaryHeight: height of the primary display.
    ///   - screens: visible frames of the screens, in AppKit coordinates.
    static func frame(caret: CGRect, primaryHeight: CGFloat, screens: [CGRect]) -> CGRect? {
        let caretBottom = primaryHeight - caret.maxY
        let caretTop = primaryHeight - caret.minY
        let anchor = CGPoint(x: caret.minX, y: (caretBottom + caretTop) / 2)
        guard let screen = screens.first(where: { $0.insetBy(dx: -1, dy: -1).contains(anchor) }) else {
            return nil
        }
        var y = caretBottom - gap - size.height
        if y < screen.minY {
            y = caretTop + gap
        }
        let x = min(max(caret.minX, screen.minX), screen.maxX - size.width)
        return CGRect(origin: CGPoint(x: x, y: y), size: size)
    }
}

/// A small animated line next to the text caret while a turn is being
/// processed. It never takes the mouse or the focus.
@MainActor
final class CaretIndicatorController {
    private var panel: NSPanel?
    private var timer: DispatchSourceTimer?
    private let queue = DispatchQueue(label: "untype.caret-indicator", qos: .userInitiated)
    /// Told when the indicator appears or disappears.
    var onVisibilityChange: ((Bool) -> Void)?
    private(set) var isVisible = false
    private var generation = 0

    var isRunning: Bool { timer != nil }

    /// Starts following the caret of the focused control.
    func start() {
        guard timer == nil else {
            return
        }
        generation += 1
        let generation = generation
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: .milliseconds(200))
        timer.setEventHandler { [weak self] in
            let rect = CaretLocator.caretRect(excludingPID: ownPID)
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self?.place(at: rect, generation: generation)
                }
            }
        }
        self.timer = timer
        timer.resume()
    }

    func stop() {
        generation += 1
        timer?.cancel()
        timer = nil
        panel?.orderOut(nil)
        setVisible(false)
    }

    private func place(at caret: CGRect?, generation: Int) {
        guard generation == self.generation, timer != nil else {
            return
        }
        guard let caret,
              let primary = NSScreen.screens.first,
              let frame = CaretIndicatorLayout.frame(
                  caret: caret,
                  primaryHeight: primary.frame.height,
                  screens: NSScreen.screens.map(\.visibleFrame)
              )
        else {
            panel?.orderOut(nil)
            setVisible(false)
            return
        }
        let panel = self.panel ?? makePanel()
        self.panel = panel
        if panel.frame != frame {
            panel.setFrame(frame, display: true)
        }
        if !panel.isVisible {
            panel.orderFrontRegardless()
        }
        setVisible(true)
    }

    private func setVisible(_ visible: Bool) {
        guard isVisible != visible else {
            return
        }
        isVisible = visible
        onVisibilityChange?(visible)
    }

    private func makePanel() -> NSPanel {
        let size = CaretIndicatorLayout.size
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.hasShadow = false
        let host = NSHostingView(rootView: CaretIndicatorView())
        host.frame = NSRect(origin: .zero, size: size)
        host.autoresizingMask = [.width, .height]
        panel.contentView = host
        return panel
    }
}

/// The processing line: a travelling wave in a small dark capsule, readable
/// over light and dark text fields.
struct CaretIndicatorView: View {
    private static let lineColor = Color(.sRGB, red: 0.45, green: 0.66, blue: 1.0, opacity: 1)

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { context in
            Canvas { canvas, size in
                let time = context.date.timeIntervalSinceReferenceDate
                let inset: CGFloat = 6
                let width = size.width - inset * 2
                let midY = size.height / 2
                let amplitude = (size.height / 2 - 3) * (0.75 + 0.25 * sin(time * 2.4))
                var path = Path()
                let steps = 40
                for index in 0...steps {
                    let x = Double(index) / Double(steps)
                    let envelope = sin(x * .pi)
                    let y = amplitude * envelope * sin(x * 2 * .pi * 2 - time * 6)
                    let point = CGPoint(x: inset + CGFloat(x) * width, y: midY - CGFloat(y))
                    if index == 0 {
                        path.move(to: point)
                    } else {
                        path.addLine(to: point)
                    }
                }
                canvas.stroke(
                    path,
                    with: .color(Self.lineColor),
                    style: StrokeStyle(lineWidth: 1.4, lineCap: .round, lineJoin: .round)
                )
            }
        }
        .background(Capsule(style: .continuous).fill(Color.black.opacity(0.72)))
        .overlay(Capsule(style: .continuous).strokeBorder(Color.white.opacity(0.18), lineWidth: 0.5))
        .accessibilityHidden(true)
    }
}
