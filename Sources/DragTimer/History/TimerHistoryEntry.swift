import Foundation

enum TimerHistoryOutcome: String, Codable, CaseIterable {
    case completed
    case cancelled
    case discarded
}

enum ExpiryResolution: String, Codable, CaseIterable {
    case markDone
    case snoozed
    case restarted
}

struct TimerHistoryEntry: Codable, Identifiable, Equatable {
    /// For completions this is also the pending-expiry event ID, which makes
    /// replay after a crash idempotent.
    var id: UUID
    var sourceTimerID: UUID
    var linkedTimerID: UUID?
    var label: String
    var plannedDuration: TimeInterval
    var startedAt: Date
    var endedAt: Date
    var outcome: TimerHistoryOutcome
    var resolution: ExpiryResolution?
    var optionsSnapshot: TimerOptions
    var identity: TimerIdentity
    var origin: TimerOrigin
    var parentEventID: UUID?

    init(
        id: UUID = UUID(),
        timer: TimerRecord,
        endedAt: Date,
        outcome: TimerHistoryOutcome,
        resolution: ExpiryResolution? = nil,
        linkedTimerID: UUID? = nil
    ) {
        self.id = id
        sourceTimerID = timer.id
        self.linkedTimerID = linkedTimerID
        label = timer.label
        plannedDuration = timer.resetDuration
        startedAt = timer.createdAt
        self.endedAt = endedAt
        self.outcome = outcome
        self.resolution = resolution
        optionsSnapshot = timer.options
        identity = timer.resolvedIdentity
        origin = timer.resolvedOrigin
        parentEventID = timer.parentEventID
    }

    var actualElapsed: TimeInterval { max(0, endedAt.timeIntervalSince(startedAt)) }
}

struct PendingExpiry: Codable, Identifiable, Equatable {
    var id: UUID
    var timer: TimerRecord
    var expiredAt: Date

    init(id: UUID = UUID(), timer: TimerRecord, expiredAt: Date) {
        self.id = id
        self.timer = timer
        self.expiredAt = expiredAt
    }
}

struct TimerHistoryInsights: Equatable {
    var completedCount: Int
    var cancelledCount: Int
    var snoozedCount: Int
    var averagePlannedDuration: TimeInterval?

    static func calculate(entries: [TimerHistoryEntry], since: Date? = nil) -> TimerHistoryInsights {
        let filtered = entries.filter { entry in
            guard let since else { return true }
            return entry.endedAt >= since
        }
        let durationEntries = filtered.filter {
            $0.outcome != .discarded && $0.origin != .snooze
        }
        let average = durationEntries.isEmpty
            ? nil
            : durationEntries.map(\.plannedDuration).reduce(0, +) / Double(durationEntries.count)
        return TimerHistoryInsights(
            completedCount: filtered.filter { $0.outcome == .completed }.count,
            cancelledCount: filtered.filter { $0.outcome == .cancelled }.count,
            snoozedCount: filtered.filter { $0.resolution == .snoozed }.count,
            averagePlannedDuration: average
        )
    }
}
