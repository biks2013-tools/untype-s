import Foundation

/// Settings → Speech → Soniox balance: warn in the Transcript when the
/// Soniox credit drops below an amount the user chose.
public struct BalanceAlertPreferences: Codable, Equatable, Sendable {
    /// Warn below this many US dollars (nil or 0: off).
    public var thresholdUsd: Double?

    public init(thresholdUsd: Double? = nil) {
        self.thresholdUsd = thresholdUsd
    }

    public var isOn: Bool {
        (thresholdUsd ?? 0) > 0
    }

    /// The amount offered when the user switches the warning on.
    public static let suggestedThresholdUsd = 5.0
}

/// The Soniox organization's credit, from GET /v1/organization/balance.
public struct SonioxBalance: Equatable, Sendable {
    public let availableUsd: Double
    public let exhausted: Bool
    public let autopayEnabled: Bool

    public init(availableUsd: Double, exhausted: Bool, autopayEnabled: Bool = false) {
        self.availableUsd = availableUsd
        self.exhausted = exhausted
        self.autopayEnabled = autopayEnabled
    }

    /// Soniox sends the amounts as strings ("12.34"); numbers are accepted too.
    public static func parse(_ data: Data) throws -> SonioxBalance {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw UntypeError.sonioxProtocol("Soniox balance response is not a JSON object.")
        }
        guard let available = amount(object["available_balance_usd"]) else {
            throw UntypeError.sonioxProtocol("Soniox balance response has no available_balance_usd.")
        }
        return SonioxBalance(
            availableUsd: available,
            exhausted: (object["balance_exhausted"] as? Bool) ?? (available <= 0),
            autopayEnabled: (object["autopay_enabled"] as? Bool) ?? false
        )
    }

    private static func amount(_ value: Any?) -> Double? {
        if let number = value as? NSNumber {
            return number.doubleValue
        }
        if let text = value as? String {
            return Double(text.trimmingCharacters(in: .whitespaces))
        }
        return nil
    }
}

public enum SonioxBalanceClient {
    public static let endpoint = URL(string: "https://api.soniox.com/v1/organization/balance")!
    /// Soniox serves the balance to organization keys only.
    public static let organizationKeyName = "SONIOX_ORGANIZATION_API_KEY"

    /// The organization key when set; otherwise the transcription key, which
    /// works only when it happens to be an organization key.
    public static func apiKey(from env: EnvChain) -> (name: String, value: String)? {
        if let value = env.get(organizationKeyName)?.value {
            return (organizationKeyName, value)
        }
        if let value = env.get(STTProvider.soniox.apiKeyEnvName)?.value {
            return (STTProvider.soniox.apiKeyEnvName, value)
        }
        return nil
    }

    public static func fetch(apiKey: String, session: URLSession = .shared) async throws -> SonioxBalance {
        var request = URLRequest(url: endpoint, timeoutInterval: 15)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw UntypeError.sonioxNetwork("Soniox balance could not be read: \(error.localizedDescription)")
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        switch status {
        case 200..<300:
            return try SonioxBalance.parse(data)
        case 401, 403:
            throw UntypeError.sonioxAuth("Soniox only shows the balance to an organization API key. Add one as \(organizationKeyName) in Settings → Permissions & Keys.")
        default:
            throw UntypeError.sonioxNetwork("Soniox balance request failed (HTTP \(status)).")
        }
    }
}

/// Decides when a low balance is worth a Transcript warning: once when the
/// balance drops below the threshold, again only after `repeatInterval` while
/// it stays low, and afresh after it has been topped up above the threshold.
/// Pure, so the rule is testable apart from the network and the UI.
public struct BalanceWarningPolicy: Sendable {
    public let repeatInterval: TimeInterval
    private var lastWarned: Date?

    public init(repeatInterval: TimeInterval = 24 * 60 * 60) {
        self.repeatInterval = repeatInterval
    }

    /// The warning to show now, or nil.
    public mutating func warning(for balance: SonioxBalance, thresholdUsd: Double?, now: Date = Date()) -> String? {
        guard let threshold = thresholdUsd, threshold > 0, balance.availableUsd < threshold else {
            lastWarned = nil
            return nil
        }
        if let lastWarned, now.timeIntervalSince(lastWarned) < repeatInterval {
            return nil
        }
        lastWarned = now
        return Self.message(for: balance, thresholdUsd: threshold)
    }

    public static func message(for balance: SonioxBalance, thresholdUsd: Double) -> String {
        if balance.exhausted || balance.availableUsd <= 0 {
            return "Your Soniox balance is used up: dictation and meeting recording stop working. Add funds at console.soniox.com."
        }
        let left = formatUsd(balance.availableUsd)
        let hours = balance.availableUsd / SonioxPricing.realtimeUsdPerHour
        let autopay = balance.autopayEnabled ? " Auto top-up is on in Soniox." : ""
        return "Soniox balance is low: \(left) left (below your \(formatUsd(thresholdUsd)) warning), about \(Int(hours.rounded(.down))) h of dictation. Add funds at console.soniox.com.\(autopay)"
    }

    public static func formatUsd(_ value: Double) -> String {
        String(format: "$%.2f", value)
    }
}

public enum SonioxPricing {
    /// Real-time transcription, pay-as-you-go (soniox.com/pricing, 2026-11).
    public static let realtimeUsdPerHour = 0.12
}
