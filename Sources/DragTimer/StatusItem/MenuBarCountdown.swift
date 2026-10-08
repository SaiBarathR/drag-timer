import Foundation

/// Countdown text and nearest-deadline selection for the menu bar.
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

    /// Time since a timer finished, counting up: "+0:05", "+2:15", "+1h 5m".
    static func overtimeText(since dueAt: Date, at date: Date = Date()) -> String {
        "+" + text(forRemaining: max(0, date.timeIntervalSince(dueAt)).rounded(.down))
    }

    /// How long ago a timer finished, in whole minutes: "just now",
    /// "2 min ago", "1 hr 5 min ago", "3 days ago".
    static func finishedAgoText(since dueAt: Date, at date: Date = Date()) -> String {
        // Half a second of slack, so a view that re-reads this exactly on the
        // minute never lands a hair short of it.
        let minutes = Int((max(0, date.timeIntervalSince(dueAt)) + 0.5) / 60)
        if minutes < 1 { return "just now" }
        if minutes < 60 { return "\(minutes) min ago" }
        let hours = minutes / 60
        if hours < 24 {
            return minutes % 60 == 0 ? "\(hours) hr ago" : "\(hours) hr \(minutes % 60) min ago"
        }
        return "\(hours / 24) \(hours / 24 == 1 ? "day" : "days") ago"
    }
}

/// The finished timers still waiting for Snooze, Restart or Mark done.
struct MenuBarFinishedState: Equatable {
    /// The first in the engine's order, which is also the popover's card.
    var label: String
    /// When that timer was due, which is what the count-up starts from: a
    /// timer the Mac slept through has been finished since then, not since
    /// the Mac woke.
    var dueAt: Date
    var count: Int
}

struct MenuBarPresentation: Equatable {
    var requestedMode: MenuBarDisplayMode
    var text: String?
    var timer: TimerRecord?
    var runningCount: Int
    var usesFallback: Bool
    var urgent: Bool
    var progress: Double?
    var finished: MenuBarFinishedState?

    var hasExpandedLayout: Bool { text != nil }
}

enum MenuBarPresentationPolicy {
    static func presentation(
        timers: [TimerRecord],
        pendingExpiries: [PendingExpiry] = [],
        mode: MenuBarDisplayMode,
        pinnedTimerID: UUID?,
        showZeroCount: Bool,
        urgentThreshold: UrgentThreshold,
        at date: Date = Date()
    ) -> MenuBarPresentation {
        let running = timers.filter { !$0.isPaused }
        let nearest = MenuBarCountdown.earliestRunningTimer(in: timers)
        let pinned = pinnedTimerID.flatMap { id in timers.first { $0.id == id } }
        let finished = finishedState(pendingExpiries)

        // A finished timer nobody has answered outranks every countdown: the
        // sound may have been missed, and the menu bar is all that is left.
        if let finished, mode != .count {
            return MenuBarPresentation(
                requestedMode: mode,
                text: mode == .ring
                    ? nil
                    : MenuBarCountdown.overtimeText(since: finished.dueAt, at: date),
                timer: nil,
                runningCount: running.count,
                usesFallback: false,
                urgent: true,
                progress: 1,
                finished: finished
            )
        }

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
                progress: nil,
                finished: finished
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

    private static func finishedState(_ pendingExpiries: [PendingExpiry]) -> MenuBarFinishedState? {
        // The same order the engine keeps, so this is the popover's card.
        let oldest = pendingExpiries.min(by: PendingExpiry.isOrderedBefore)
        return oldest.map {
            MenuBarFinishedState(label: $0.timer.label, dueAt: $0.dueAt, count: pendingExpiries.count)
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

/// Countdowns change digits when a whole number of seconds remains. Ticking on
/// those instants keeps the menu bar and the popover in step with each other
/// and with the alert, instead of each lagging by its own arbitrary phase.
enum CountdownClock {
    /// A past instant in phase with the timer's remaining whole seconds.
    static func tickAnchor(for timer: TimerRecord) -> Date {
        timer.fireDate.addingTimeInterval(-7 * 24 * 60 * 60)
    }

    /// The first instant at or after `date` at which `timer` has a whole
    /// number of seconds left.
    static func nextTick(for timer: TimerRecord, after date: Date) -> Date {
        nextTick(inPhaseWith: timer.fireDate, after: date)
    }

    /// The first instant at or after `date` that is a whole number of
    /// intervals from `phase`, whether `phase` is still ahead (a fire date)
    /// or already behind (the moment a timer finished).
    static func nextTick(inPhaseWith phase: Date, after date: Date, every interval: TimeInterval = 1) -> Date {
        let offset = phase.timeIntervalSince(date) / interval
        return date.addingTimeInterval((offset - offset.rounded(.down)) * interval)
    }
}
