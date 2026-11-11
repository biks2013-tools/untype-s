import CoreGraphics
import Testing
@testable import UntypeCore

/// One 1440×900 display; the menu bar takes the top 25 points.
private let primaryHeight: CGFloat = 900
private let screen = CGRect(x: 0, y: 0, width: 1440, height: 875)

@Test func caretIndicatorSitsUnderTheCaret() throws {
    // Caret 13 points high, its top 122 points from the top of the display.
    let caret = CGRect(x: 319, y: 122, width: 1, height: 13)
    let frame = try #require(CaretIndicatorLayout.frame(caret: caret, primaryHeight: primaryHeight, screens: [screen]))
    #expect(frame.size == CaretIndicatorLayout.size)
    #expect(frame.minX == 319)
    // AppKit coordinates: the caret's bottom edge is at 900 - 135 = 765.
    #expect(frame.maxY == 765 - CaretIndicatorLayout.gap)
}

@Test func caretIndicatorGoesAboveACaretAtTheBottomOfTheScreen() throws {
    let caret = CGRect(x: 100, y: 885, width: 1, height: 13)
    let frame = try #require(CaretIndicatorLayout.frame(caret: caret, primaryHeight: primaryHeight, screens: [screen]))
    // The caret's top edge is at 900 - 885 = 15.
    #expect(frame.minY == 15 + CaretIndicatorLayout.gap)
}

@Test func caretIndicatorStaysInsideTheScreenAtTheRightEdge() throws {
    let caret = CGRect(x: 1435, y: 300, width: 1, height: 16)
    let frame = try #require(CaretIndicatorLayout.frame(caret: caret, primaryHeight: primaryHeight, screens: [screen]))
    #expect(frame.maxX == screen.maxX)
}

@Test func caretIndicatorIsNotPlacedForACaretOffEveryScreen() {
    let caret = CGRect(x: 5000, y: 300, width: 1, height: 16)
    #expect(CaretIndicatorLayout.frame(caret: caret, primaryHeight: primaryHeight, screens: [screen]) == nil)
}

@Test func caretIndicatorUsesTheScreenTheCaretIsOn() throws {
    // A second display to the right of the primary one.
    let second = CGRect(x: 1440, y: 0, width: 1920, height: 1080)
    let caret = CGRect(x: 2000, y: 400, width: 1, height: 18)
    let frame = try #require(CaretIndicatorLayout.frame(caret: caret, primaryHeight: primaryHeight, screens: [screen, second]))
    #expect(second.contains(frame))
}

@Test func emptyOrAbsurdCaretRectanglesAreRejected() {
    // What Electron apps answer instead of an error (seen with Teams).
    #expect(!CaretLocator.isUsable(CGRect(x: 0, y: 1440, width: 0, height: 0)))
    #expect(!CaretLocator.isUsable(CGRect(x: 0, y: 0, width: 0, height: 13)))
    #expect(!CaretLocator.isUsable(CGRect(x: 10, y: 10, width: 1, height: 2000)))
    #expect(CaretLocator.isUsable(CGRect(x: 319, y: 122, width: 0, height: 13)))
}
