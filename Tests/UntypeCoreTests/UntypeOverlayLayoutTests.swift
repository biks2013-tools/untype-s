import Foundation
import Testing
@testable import UntypeCore

@Test func overlayLayoutUsesConfiguredFixedSize() {
    let layout = UntypeOverlayLayout(width: 240, height: 96)
    let visibleFrame = CGRect(x: 100, y: 200, width: 1000, height: 700)

    let frame = layout.initialPanelFrame(in: visibleFrame)

    #expect(frame.width == 240)
    #expect(frame.height == 96)
}

@Test func overlayLayoutInitialFrameIsBottomCentered() {
    let layout = UntypeOverlayLayout(width: 240, height: 96, bottomOffset: 46)
    let visibleFrame = CGRect(x: 100, y: 200, width: 1000, height: 700)

    let frame = layout.initialPanelFrame(in: visibleFrame)

    #expect(frame.midX == visibleFrame.midX)
    #expect(frame.minY == visibleFrame.minY + layout.bottomOffset)
}

@Test func overlayLayoutWrapsLongTextIntoTallerPanel() {
    let layout = UntypeOverlayLayout(width: 240, height: 96)
    let visibleFrame = CGRect(x: 100, y: 200, width: 1000, height: 700)

    let shortFrame = layout.initialPanelFrame(in: visibleFrame, text: "short text")
    let longFrame = layout.initialPanelFrame(
        in: visibleFrame,
        text: "This is a longer transcribed sentence that should exceed the overlay text width and wrap onto additional visible lines."
    )

    #expect(longFrame.width == shortFrame.width)
    #expect(longFrame.minY == shortFrame.minY)
    #expect(longFrame.height > shortFrame.height)
}

@Test func overlayLayoutAnchoredGrowthKeepsBottomEdgeStable() {
    let layout = UntypeOverlayLayout(width: 240, height: 96)
    let visibleFrame = CGRect(x: 100, y: 200, width: 1000, height: 700)
    let anchor = CGPoint(x: 500, y: 246)

    let shortFrame = layout.anchoredPanelFrame(
        bottomLeft: anchor,
        text: "short text",
        in: visibleFrame
    )
    let longFrame = layout.anchoredPanelFrame(
        bottomLeft: anchor,
        text: "This is a longer transcribed sentence that should exceed the overlay text width and wrap onto additional visible lines.",
        in: visibleFrame,
        currentHeight: shortFrame.height
    )

    #expect(longFrame.minX == shortFrame.minX)
    #expect(longFrame.minY == shortFrame.minY)
    #expect(longFrame.height > shortFrame.height)
    #expect(longFrame.maxY > shortFrame.maxY)
}

@Test func overlayLayoutDoesNotShrinkVisiblePanelForShorterText() {
    let layout = UntypeOverlayLayout(width: 240, height: 96)
    let visibleFrame = CGRect(x: 100, y: 200, width: 1000, height: 700)
    let anchor = CGPoint(x: 500, y: 246)
    let expandedFrame = layout.anchoredPanelFrame(
        bottomLeft: anchor,
        text: "This is a longer transcribed sentence that should exceed the overlay text width and wrap onto additional visible lines.",
        in: visibleFrame
    )

    let shorterFrame = layout.anchoredPanelFrame(
        bottomLeft: anchor,
        text: "short text",
        in: visibleFrame,
        currentHeight: expandedFrame.height
    )

    #expect(shorterFrame == expandedFrame)
}
