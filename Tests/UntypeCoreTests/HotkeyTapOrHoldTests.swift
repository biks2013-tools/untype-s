import Foundation
import Testing
@testable import UntypeCore

@Test func aQuickPressIsATapThatKeepsRecording() {
    #expect(HotkeyTapOrHold.isTap(heldFor: 0))
    #expect(HotkeyTapOrHold.isTap(heldFor: 0.12))
    #expect(HotkeyTapOrHold.isTap(heldFor: HotkeyTapOrHold.tapThreshold - 0.001))
}

@Test func aPressHeldPastTheThresholdIsPushToTalk() {
    #expect(!HotkeyTapOrHold.isTap(heldFor: HotkeyTapOrHold.tapThreshold))
    #expect(!HotkeyTapOrHold.isTap(heldFor: 2.5))
}

@Test func aNegativeDurationIsNeverATap() {
    #expect(!HotkeyTapOrHold.isTap(heldFor: -0.1))
}

@Test func handsFreeFinishesHaveStableLogNames() {
    #expect(HotkeyTurnFinish.typeAndSend.rawValue == "type-and-send")
    #expect(HotkeyTurnFinish.typeOnly.rawValue == "type-only")
    #expect(HotkeyTurnFinish.discard.rawValue == "discard")
}
