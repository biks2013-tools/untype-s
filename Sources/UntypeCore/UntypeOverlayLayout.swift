import AppKit
import Foundation

public struct UntypeOverlayLayout: Equatable, Sendable {
    public let width: CGFloat
    public let height: CGFloat
    public let bottomOffset: CGFloat

    public init(
        width: CGFloat = 720,
        height: CGFloat = 96,
        bottomOffset: CGFloat = 46
    ) {
        self.width = width
        self.height = height
        self.bottomOffset = bottomOffset
    }

    public func initialPanelFrame(in visibleFrame: CGRect, text: String = "") -> CGRect {
        let height = panelHeight(for: text, in: visibleFrame)
        return CGRect(
            x: visibleFrame.midX - width / 2,
            y: visibleFrame.minY + bottomOffset,
            width: width,
            height: height
        )
    }

    public func anchoredPanelFrame(
        bottomLeft: CGPoint,
        text: String,
        in visibleFrame: CGRect,
        currentHeight: CGFloat? = nil
    ) -> CGRect {
        let measuredHeight = panelHeight(for: text, in: visibleFrame)
        let finalHeight = max(currentHeight ?? height, measuredHeight)
        return CGRect(
            x: bottomLeft.x,
            y: bottomLeft.y,
            width: width,
            height: finalHeight
        )
    }

    public func panelHeight(for text: String, in visibleFrame: CGRect? = nil) -> CGFloat {
        let measuredTextHeight = wrappedTextHeight(for: text)
        let verticalChrome = textTopInset
            + measuredTextHeight
            + textBottomGap
            + bottomIndicatorHeight
            + bottomIndicatorInset
        let desiredHeight = max(height, ceil(verticalChrome))
        guard let visibleFrame else {
            return desiredHeight
        }
        let availableHeight = max(height, visibleFrame.height - bottomOffset)
        return min(desiredHeight, availableHeight)
    }

    private var textWidth: CGFloat {
        max(1, width - 32)
    }

    private var textTopInset: CGFloat {
        16
    }

    private var textBottomGap: CGFloat {
        8
    }

    private var bottomIndicatorHeight: CGFloat {
        18
    }

    private var bottomIndicatorInset: CGFloat {
        5
    }

    private func wrappedTextHeight(for text: String) -> CGFloat {
        let visibleText = text.isEmpty ? " " : text
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineBreakMode = .byWordWrapping
        let font = NSFont.monospacedSystemFont(
            ofSize: 12,
            weight: .regular
        )
        let bounds = (visibleText as NSString).boundingRect(
            with: CGSize(width: textWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [
                .font: font,
                .paragraphStyle: paragraphStyle
            ]
        )
        return ceil(bounds.height) + 2
    }
}
