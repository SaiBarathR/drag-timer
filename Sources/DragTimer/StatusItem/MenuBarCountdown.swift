import Foundation

/// Pure menu-bar countdown policy, kept separate from AppKit so selection and
/// formatting stay deterministic and can be exercised by the self-check.
enum MenuBarCountdown {
    static func earliestRunningTimer(in timers: [TimerRecord]) -> TimerRecord? {
        timers
            .lazy
            .filter { !$0.isPaused }
            .min { lhs, rhs in
                if lhs.fireDate != rhs.fireDate {
                    return lhs.fireDate < rhs.fireDate
                }
                return lhs.id.uuidString < rhs.id.uuidString
            }
    }

    static func text(for timer: TimerRecord, at date: Date = Date()) -> String {
        text(forRemaining: timer.remaining(at: date))
    }

    static func text(forRemaining remaining: TimeInterval) -> String {
        let totalSeconds = max(0, Int(remaining.rounded(.up)))

        if totalSeconds >= 24 * 60 * 60 {
            let days = totalSeconds / (24 * 60 * 60)
            let hours = (totalSeconds % (24 * 60 * 60)) / (60 * 60)
            return "\(days)d \(hours)h"
        }

        if totalSeconds >= 60 * 60 {
            let hours = totalSeconds / (60 * 60)
            let minutes = (totalSeconds % (60 * 60)) / 60
            return "\(hours)h \(minutes)m"
        }

        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
