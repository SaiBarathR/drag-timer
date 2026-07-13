import XCTest
@testable import DragTimer

final class TimerHistoryStoreTests: XCTestCase {
    func testRetentionBoundsAgeAndCount() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let now = Date(timeIntervalSinceReferenceDate: 10_000_000)
        let store = TimerHistoryStore(
            fileURL: directory.appendingPathComponent("history.json"),
            maximumEntries: 2,
            retentionInterval: 100
        )
        let values = [
            entry(endedAt: now.addingTimeInterval(-200)),
            entry(endedAt: now.addingTimeInterval(-30)),
            entry(endedAt: now.addingTimeInterval(-20)),
            entry(endedAt: now.addingTimeInterval(-10))
        ]

        try store.save(values, now: now)
        let restored = store.load(now: now)

        XCTAssertEqual(restored.count, 2)
        XCTAssertEqual(restored.map(\.endedAt), [now.addingTimeInterval(-10), now.addingTimeInterval(-20)])
    }

    func testCorruptHistoryIsPreservedAndReturnsEmpty() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("history.json")
        try Data("not json".utf8).write(to: url)
        let store = TimerHistoryStore(fileURL: url)

        XCTAssertEqual(store.load(), [])
        try Data("still not json".utf8).write(to: url)
        XCTAssertEqual(store.load(), [])

        let backups = try FileManager.default.contentsOfDirectory(atPath: directory.path)
            .filter { $0.hasPrefix("history.corrupt-") && $0.hasSuffix(".json") }
        XCTAssertEqual(backups.count, 2)
        XCTAssertEqual(Set(backups).count, 2)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    func testInsightsExcludeDiscardedAndSnoozeChildrenFromAverage() {
        let now = Date(timeIntervalSinceReferenceDate: 1_000)
        var completed = entry(endedAt: now, duration: 600, outcome: .completed)
        completed.resolution = .snoozed
        let cancelled = entry(endedAt: now, duration: 1_200, outcome: .cancelled)
        var snoozeChild = entry(endedAt: now, duration: 300, outcome: .completed)
        snoozeChild.origin = .snooze
        let discarded = entry(endedAt: now, duration: 9_000, outcome: .discarded)

        let insights = TimerHistoryInsights.calculate(
            entries: [completed, cancelled, snoozeChild, discarded]
        )

        XCTAssertEqual(insights.completedCount, 2)
        XCTAssertEqual(insights.cancelledCount, 1)
        XCTAssertEqual(insights.snoozedCount, 1)
        XCTAssertEqual(insights.averagePlannedDuration, 900)
    }

    private func entry(
        endedAt: Date,
        duration: TimeInterval = 60,
        outcome: TimerHistoryOutcome = .completed
    ) -> TimerHistoryEntry {
        let timer = TimerRecord(
            createdAt: endedAt.addingTimeInterval(-duration),
            fireDate: endedAt,
            options: TimerOptions(label: "Timer")
        )
        return TimerHistoryEntry(timer: timer, endedAt: endedAt, outcome: outcome)
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("DragTimerHistoryTests-\(UUID().uuidString)", isDirectory: true)
    }
}
