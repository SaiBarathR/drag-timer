import AppKit
import SwiftUI

extension TimerColorToken {
    var color: Color { Color(nsColor: nsColor) }

    var nsColor: NSColor {
        switch self {
        case .blue: return .systemBlue
        case .amber: return .systemOrange
        case .mint: return .systemGreen
        case .violet: return .systemPurple
        case .red: return .systemRed
        case .graphite: return .systemGray
        }
    }

    var displayName: String { rawValue.capitalized }
}

enum TimerAppearancePolicy {
    static func isUrgent(
        _ timer: TimerRecord,
        at date: Date,
        threshold: UrgentThreshold
    ) -> Bool {
        guard threshold.rawValue > 0, !timer.isPaused else { return false }
        let remaining = timer.remaining(at: date)
        return remaining > 0 && remaining <= TimeInterval(threshold.rawValue)
    }

    static func highContrast(settings: AppSettings) -> Bool {
        settings.contrastMode == .alwaysOn
            || NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
            || NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
    }
}

struct TimerIdentityBead: View {
    let identity: TimerIdentity
    var size: CGFloat = 24
    var urgent = false

    var body: some View {
        ZStack {
            Circle()
                .fill((urgent ? Color.red : identity.color.color).opacity(0.16))
            Circle()
                .stroke(urgent ? Color.red : identity.color.color, lineWidth: 1.5)
            Image(systemName: urgent ? "exclamationmark" : identity.symbolName)
                .font(.system(size: size * 0.42, weight: .semibold))
                .foregroundStyle(urgent ? Color.red : identity.color.color)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
