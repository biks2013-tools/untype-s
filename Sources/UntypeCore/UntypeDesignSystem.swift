import AppKit
import SwiftUI

// Design system for the untype macOS UI.
// Tokens and primitives mirror the design handoff bundle at
// docs/reference/design-bundle-macos-modernization/. Surfaces use native
// SwiftUI materials and system accent colors so the result feels native to
// macOS while keeping the bundle's amber-accent identity.

public enum UntypeDesignTokens {
    public static let accentAmber = Color(.sRGB, red: 0.961, green: 0.639, blue: 0.259, opacity: 1.0) // shared.jsx UN_THEMES.dark.accent
    public static let accentAmberStrong = Color(.sRGB, red: 0.878, green: 0.522, blue: 0.110, opacity: 1.0) // light.accent
    public static let recordingRed = Color(.sRGB, red: 1.000, green: 0.353, blue: 0.302, opacity: 1.0)
    public static let recordingRedDeep = Color(.sRGB, red: 0.722, green: 0.200, blue: 0.169, opacity: 1.0)
    public static let successGreen = Color(.sRGB, red: 0.227, green: 0.820, blue: 0.478, opacity: 1.0)
    public static let warnGold = Color(.sRGB, red: 0.941, green: 0.725, blue: 0.310, opacity: 1.0)

    public static let cornerLarge: CGFloat = 16
    public static let cornerMedium: CGFloat = 10
    public static let cornerSmall: CGFloat = 6
    public static let cornerChip: CGFloat = 999
}

public enum UntypeStatusTone: Sendable {
    case ok
    case warn
    case recording
    case accent
    case off

    var color: Color {
        switch self {
        case .ok: return UntypeDesignTokens.successGreen
        case .warn: return UntypeDesignTokens.warnGold
        case .recording: return UntypeDesignTokens.recordingRed
        case .accent: return UntypeDesignTokens.accentAmber
        case .off: return Color.secondary.opacity(0.55)
        }
    }
}

public struct UntypeBrandMark: View {
    public var size: CGFloat
    public init(size: CGFloat = 24) {
        self.size = size
    }

    public var body: some View {
        RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [UntypeDesignTokens.accentAmber, UntypeDesignTokens.accentAmberStrong],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(width: size, height: size)
            .overlay(
                Text("u")
                    .font(.system(size: size * 0.55, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .offset(y: -size * 0.02)
            )
            .shadow(color: UntypeDesignTokens.accentAmber.opacity(0.35), radius: 6, x: 0, y: 3)
            .accessibilityHidden(true)
    }
}

public struct UntypeStatusDot: View {
    public var tone: UntypeStatusTone
    public var size: CGFloat

    public init(tone: UntypeStatusTone, size: CGFloat = 7) {
        self.tone = tone
        self.size = size
    }

    public var body: some View {
        Circle()
            .fill(tone.color)
            .frame(width: size, height: size)
            .overlay(
                Circle()
                    .stroke(tone.color.opacity(0.25), lineWidth: max(2, size * 0.5))
            )
            .shadow(color: tone.color.opacity(0.55), radius: size * 0.7, x: 0, y: 0)
            .accessibilityHidden(true)
    }
}

public struct UntypeStatusPill: View {
    public var symbol: String
    public var label: String
    public var value: String
    public var tone: UntypeStatusTone

    public init(symbol: String, label: String, value: String, tone: UntypeStatusTone) {
        self.symbol = symbol
        self.label = label
        self.value = value
        self.tone = tone
    }

    public var body: some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(tone.color)
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            Text(value)
                .font(.caption.weight(.medium))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(.thinMaterial, in: Capsule(style: .continuous))
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06))
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)")
    }
}

public struct UntypeOperatorChip: View {
    public var letter: String
    public var label: String
    public var isOn: Bool
    public var isRecording: Bool
    public var isCompact: Bool
    public var showsLabel: Bool
    public var action: () -> Void

    public init(
        letter: String,
        label: String,
        isOn: Bool,
        isRecording: Bool = false,
        isCompact: Bool = false,
        showsLabel: Bool = true,
        action: @escaping () -> Void
    ) {
        self.letter = letter
        self.label = label
        self.isOn = isOn
        self.isRecording = isRecording
        self.isCompact = isCompact
        self.showsLabel = showsLabel
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: isCompact ? 5 : 7) {
                UntypeStatusDot(
                    tone: !isOn ? .off : (isRecording ? .recording : .accent),
                    size: isCompact ? 5 : 6
                )
                Text(letter)
                    .font(.system(size: isCompact ? 11 : 12, weight: .bold, design: .monospaced))
                    .foregroundStyle(isOn ? UntypeDesignTokens.accentAmber : Color.secondary)
                    .lineLimit(1)
                if showsLabel {
                    Text(label)
                        .font(.system(size: isCompact ? 11 : 12, weight: .semibold))
                        .foregroundStyle(isOn ? Color.primary : Color.secondary)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, isCompact ? 9 : (showsLabel ? 12 : 10))
            .padding(.vertical, isCompact ? 4 : 6)
            .background(
                Capsule(style: .continuous)
                    .fill(isOn ? UntypeDesignTokens.accentAmber.opacity(0.16) : Color.primary.opacity(0.04))
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(isOn ? UntypeDesignTokens.accentAmber.opacity(0.45) : Color.primary.opacity(0.10))
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Operator \(letter) \(label), \(isOn ? "on" : "off")")
    }
}

public struct UntypeRecordButton: View {
    public var isRecording: Bool
    public var titleIdle: String
    public var titleRecording: String
    public var action: () -> Void

    public init(
        isRecording: Bool,
        titleIdle: String = "Start Listening",
        titleRecording: String = "Stop Recording",
        action: @escaping () -> Void
    ) {
        self.isRecording = isRecording
        self.titleIdle = titleIdle
        self.titleRecording = titleRecording
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                ZStack {
                    if isRecording {
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(Color.white)
                            .frame(width: 12, height: 12)
                    } else {
                        Circle()
                            .fill(Color.white)
                            .frame(width: 12, height: 12)
                    }
                }
                .frame(width: 16, height: 16)
                Text(isRecording ? titleRecording : titleIdle)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(
                Capsule(style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: isRecording
                                ? [UntypeDesignTokens.recordingRed, UntypeDesignTokens.recordingRedDeep]
                                : [UntypeDesignTokens.accentAmber, UntypeDesignTokens.accentAmberStrong],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(Color.white.opacity(0.20))
            )
            .shadow(
                color: (isRecording ? UntypeDesignTokens.recordingRed : UntypeDesignTokens.accentAmber).opacity(0.45),
                radius: 10, x: 0, y: 5
            )
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.18), value: isRecording)
        .accessibilityLabel(isRecording ? titleRecording : titleIdle)
    }
}

public struct UntypeWaveformView: View {
    public var isActive: Bool
    public var barCount: Int
    public var height: CGFloat
    public var seed: Int

    public init(isActive: Bool, barCount: Int = 28, height: CGFloat = 22, seed: Int = 0) {
        self.isActive = isActive
        self.barCount = barCount
        self.height = height
        self.seed = seed
    }

    private var bars: [CGFloat] {
        (0..<barCount).map { i in
            let x = Double(i + seed * 7) * 0.31
            let v = sin(x) * 0.4 + sin(x * 2.3) * 0.3 + sin(x * 0.5) * 0.3
            let normalized = max(0.10, min(1.0, v * 0.5 + 0.5))
            return CGFloat(normalized)
        }
    }

    public var body: some View {
        HStack(spacing: 2) {
            ForEach(Array(bars.enumerated()), id: \.offset) { _, value in
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(isActive ? UntypeDesignTokens.recordingRed : UntypeDesignTokens.accentAmber)
                    .opacity(isActive ? 0.95 : 0.45)
                    .frame(width: 3, height: max(2, value * height * (isActive ? 1.0 : 0.4)))
            }
        }
        .frame(height: height)
        .padding(.horizontal, 4)
        .accessibilityHidden(true)
    }
}

public struct UntypeKbd: View {
    public var keys: String
    public init(_ keys: String) { self.keys = keys }

    public var body: some View {
        Text(keys)
            .font(.system(size: 11, weight: .semibold, design: .monospaced))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.10))
            )
            .accessibilityLabel("Keyboard shortcut \(keys)")
    }
}

public struct UntypeSectionHeader: View {
    public var title: String
    public init(_ title: String) { self.title = title }

    public var body: some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .tracking(0.8)
    }
}

/// Status tone helpers — translate runtime status strings into a tone enum so
/// every status surface in the app uses identical color semantics. Inputs are
/// the string values produced by `UntypeUISettings.refreshingCredentialStatus`.
public enum UntypeStatusToneMap {
    public static func microphone(_ status: String) -> UntypeStatusTone {
        let lower = status.lowercased()
        if lower.contains("grant") || lower.contains("ok") || lower.contains("authorized") { return .ok }
        if lower.contains("denied") || lower.contains("missing") { return .warn }
        return .off
    }

    public static func accessibility(_ status: String) -> UntypeStatusTone {
        let lower = status.lowercased()
        if lower.contains("trust") || lower.contains("granted") || lower.contains("ok") { return .ok }
        if lower.contains("denied") || lower.contains("missing") { return .warn }
        return .off
    }

    public static func credential(_ status: String) -> UntypeStatusTone {
        let lower = status.lowercased()
        if lower.contains("configured") || lower.contains("ok") { return .ok }
        if lower.contains("missing") { return .warn }
        return .off
    }

    public static func session(isRunning: Bool, isHotkeyPressed: Bool) -> UntypeStatusTone {
        if isHotkeyPressed { return .recording }
        if isRunning { return .accent }
        return .off
    }

    public static func audio(_ status: String) -> UntypeStatusTone {
        let lower = status.lowercased()
        if lower.contains("active") { return .recording }
        if lower.contains("muted") { return .warn }
        if lower.contains("silent") { return .off }
        return .off
    }
}
