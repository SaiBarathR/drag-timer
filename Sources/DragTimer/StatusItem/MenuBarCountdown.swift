import Foundation

/// Existing formatting API retained for compatibility with tests and the drag
/// overlay. Selection now feeds the richer menu-bar presentation policy.
enum MenuBarCountdown {
    static func earliestRunningTimer(in timers: [TimerRecord]) -> TimerRecord? {
        timers.lazy.filter { !$0.isPaused }.min { lhs, rhs in
            if lhs.fireDate != rhs.fireDate { return lhs.fireDate < rhs.fireDate }
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

struct MenuBarPresentation: Equatable {
    var requestedMode: MenuBarDisplayMode
    var text: String?
    var timer: TimerRecord?
    var runningCount: Int
    var usesFallback: Bool
    var urgent: Bool
    var progress: Double?

    var hasExpandedLayout: Bool { text != nil }
}

enum MenuBarPresentationPolicy {
    static func presentation(
        timers: [TimerRecord],
        mode: MenuBarDisplayMode,
        pinnedTimerID: UUID?,
        showZeroCount: Bool,
        urgentThreshold: UrgentThreshold,
        at date: Date = Date()
    ) -> MenuBarPresentation {
        let running = timers.filter { !$0.isPaused }
        let nearest = MenuBarCountdown.earliestRunningTimer(in: timers)
        let pinned = pinnedTimerID.flatMap { id in timers.first { $0.id == id } }

        switch mode {
        case .deadline:
            return timerPresentation(nearest, mode: mode, threshold: urgentThreshold, at: date)
        case .count:
            return MenuBarPresentation(
                requestedMode: mode,
                text: running.isEmpty && !showZeroCount ? nil : String(running.count),
                timer: nil,
                runningCount: running.count,
                usesFallback: false,
                urgent: false,
                progress: nil
            )
        case .pinned:
            let selected = pinned ?? nearest
            var result = timerPresentation(selected, mode: mode, threshold: urgentThreshold, at: date)
            result.usesFallback = pinned == nil && nearest != nil
            return result
        case .ring:
            let selected = pinned ?? nearest
            var result = timerPresentation(selected, mode: mode, threshold: urgentThreshold, at: date)
            result.text = nil
            result.usesFallback = pinnedTimerID != nil && pinned == nil && nearest != nil
            return result
        }
    }

    private static func timerPresentation(
        _ timer: TimerRecord?,
        mode: MenuBarDisplayMode,
        threshold: UrgentThreshold,
        at date: Date
    ) -> MenuBarPresentation {
        MenuBarPresentation(
            requestedMode: mode,
            text: timer.map { MenuBarCountdown.text(for: $0, at: date) },
            timer: timer,
            runningCount: timer == nil ? 0 : 1,
            usesFallback: false,
            urgent: timer.map { TimerAppearancePolicy.isUrgent($0, at: date, threshold: threshold) } ?? false,
            progress: timer.map { $0.progress(at: date) }
        )
    }
}
