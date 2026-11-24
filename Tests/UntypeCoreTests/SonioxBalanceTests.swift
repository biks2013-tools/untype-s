import Foundation
import Testing
@testable import UntypeCore

@Test func sonioxBalanceParsesTheOrganizationBalanceResponse() throws {
    let json = Data("""
    {"available_balance_usd": "3.40", "free_balance_usd": "0.00", "used_balance_usd": "46.60",
     "invoice_billing_enabled": false, "balance_exhausted": false, "autopay_enabled": true,
     "autopay_threshold_usd": null, "autopay_amount_usd": null, "has_payment_method": true, "has_payment_error": false}
    """.utf8)
    let balance = try SonioxBalance.parse(json)
    #expect(balance == SonioxBalance(availableUsd: 3.4, exhausted: false, autopayEnabled: true))
    #expect(throws: UntypeError.self) { try SonioxBalance.parse(Data("{}".utf8)) }
}

@Test func balanceWarningShowsOnceWhenLowThenDailyAndAgainAfterTopUp() {
    var policy = BalanceWarningPolicy(repeatInterval: 3600)
    let start = Date(timeIntervalSince1970: 1_000_000)
    let low = SonioxBalance(availableUsd: 3.4, exhausted: false)
    let high = SonioxBalance(availableUsd: 20, exhausted: false)

    let off = policy.warning(for: low, thresholdUsd: nil, now: start)
    let aboveThreshold = policy.warning(for: high, thresholdUsd: 5, now: start)
    let first = policy.warning(for: low, thresholdUsd: 5, now: start)
    let repeated = policy.warning(for: low, thresholdUsd: 5, now: start.addingTimeInterval(600))
    let nextDay = policy.warning(for: low, thresholdUsd: 5, now: start.addingTimeInterval(3601))
    _ = policy.warning(for: high, thresholdUsd: 5, now: start.addingTimeInterval(3700))
    let afterTopUpAndDrop = policy.warning(for: low, thresholdUsd: 5, now: start.addingTimeInterval(3800))

    #expect(off == nil)
    #expect(aboveThreshold == nil)
    #expect(first?.contains("$3.40 left") == true)
    #expect(first?.contains("below your $5.00 warning") == true)
    #expect(first?.contains("28 h") == true)
    #expect(repeated == nil)
    #expect(nextDay != nil)
    #expect(afterTopUpAndDrop != nil)
}

@Test func balanceWarningSaysWhenTheBalanceIsUsedUp() {
    let message = BalanceWarningPolicy.message(for: SonioxBalance(availableUsd: 0, exhausted: true), thresholdUsd: 5)
    #expect(message.contains("used up"))
}

@Test func sonioxBalanceIsReadWithTheOrganizationKeyOnly() throws {
    let temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: temp) }
    let both = try EnvChain(cwd: temp, home: temp, shell: ["SONIOX_API_KEY": "project", "SONIOX_ORGANIZATION_API_KEY": "org"])
    let projectOnly = try EnvChain(cwd: temp, home: temp, shell: ["SONIOX_API_KEY": "project"])
    let none = try EnvChain(cwd: temp, home: temp, shell: [:])

    #expect(SonioxBalanceClient.apiKey(from: both) == "org")
    #expect(SonioxBalanceClient.apiKey(from: projectOnly) == nil)
    #expect(SonioxBalanceClient.apiKey(from: none) == nil)
}

@MainActor
@Test func transcriptionWindowKeepsTheBalanceWarningUntilClosedOrChanged() {
    let feed = MeetingTranscriptFeed()
    let low = BalanceWarningPolicy.lowBalanceNotice(for: SonioxBalance(availableUsd: 9.02, exhausted: false), thresholdUsd: 10)
    let lower = BalanceWarningPolicy.lowBalanceNotice(for: SonioxBalance(availableUsd: 8.5, exhausted: false), thresholdUsd: 10)
    #expect(low?.contains("$9.02 left") == true)
    #expect(BalanceWarningPolicy.lowBalanceNotice(for: SonioxBalance(availableUsd: 20, exhausted: false), thresholdUsd: 10) == nil)

    feed.setAccountWarning(low)
    #expect(feed.accountWarning == low)
    feed.dismissAccountWarning()
    feed.setAccountWarning(low)
    #expect(feed.accountWarning == nil)
    feed.setAccountWarning(lower)
    #expect(feed.accountWarning == lower)
    feed.setAccountWarning(nil)
    #expect(feed.accountWarning == nil)
}

@Test func theNotificationIsOnlyForAUsedUpBalanceAndOncePerTimeItRunsOut() {
    var policy = BalanceWarningPolicy()
    let low = SonioxBalance(availableUsd: 3, exhausted: false)
    let empty = SonioxBalance(availableUsd: 0, exhausted: true)

    let whileLow = policy.shouldNotifyUsedUp(low)
    let first = policy.shouldNotifyUsedUp(empty)
    let repeated = policy.shouldNotifyUsedUp(empty)
    _ = policy.shouldNotifyUsedUp(low)
    let afterTopUpSpent = policy.shouldNotifyUsedUp(empty)

    #expect(!whileLow)
    #expect(first)
    #expect(!repeated)
    #expect(afterTopUpSpent)
}
