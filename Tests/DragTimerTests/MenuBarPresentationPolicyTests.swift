import XCTest
@testable import DragTimer

final class MenuBarPresentationPolicyTests: XCTestCase {
    func testCountExcludesPausedAndHonorsZeroPreference() {
        let now = Date(timeIntervalSinceReferenceDate: 100)
        var paused = timer(label: "Paused", fireDate: now.addingTimeInterval(60), now: now)
        paused.pausedRemaining = 60
        let running = timer(label: "Running", fireDate: now.addingTimeInterval(120), now: now)

        let count = presentation([paused, running], mode: .count, at: now)
        XCTAssertEqual(count.text, "1")
        XCTAssertEqual(count.runningCount, 1)
        XCTAssertNil(presentation([], mode: .count, showZero: false, at: now).text)
        XCTAssertEqual(presentation([], mode: .count, showZero: true, at: now).text, "0")
    }

    func testPinnedPausedTimerDoesNotFallBack() {
        let now = Date(timeIntervalSinceReferenceDate: 100)
        var pinned = timer(label: "Pinned", fireDate: now.addingTimeInterval(300), now: now)
        pinned.pausedRemaining = 90
        let nearest = timer(label: "Nearest", fireDate: now.addingTimeInterval(30), now: now)

        let result = presentation([nearest, pinned], mode: .pinned, pinnedID: pinned.id, at: now)

        XCTAssertEqual(result.timer?.id, pinned.id)
        XCTAssertFalse(result.usesFallback)
        XCTAssertEqual(result.text, "1:30")
    }

    func testMissingPinFallsBackAndRingHasNoText() {
        let now = Date(timeIntervalSinceReferenceDate: 100)
        let nearest = timer(label: "Nearest", fireDate: now.addingTimeInterval(30), now: now)

        let pinned = presentation([nearest], mode: .pinned, pinnedID: UUID(), at: now)
        XCTAssertEqual(pinned.timer?.id, nearest.id)
        XCTAssertTrue(pinned.usesFallback)

        let ring = presentation([nearest], mode: .ring, pinnedID: UUID(), at: now)
        XCTAssertNil(ring.text)
        XCTAssertEqual(ring.timer?.id, nearest.id)
        XCTAssertNotNil(ring.progress)
    }

    func testUrgencyStartsAtConfiguredBoundaryAndIgnoresPaused() {
        let now = Date(timeIntervalSinceReferenceDate: 100)
        let timerAtBoundary = timer(label: "Urgent", fireDate: now.addingTimeInterval(60), now: now)
        XCTAssertTrue(presentation([timerAtBoundary], mode: .deadline, at: now).urgent)

        var paused = timerAtBoundary
        paused.pausedRemaining = 60
        XCTAssertFalse(presentation([paused], mode: .pinned, pinnedID: paused.id, at: now).urgent)
    }

    private func presentation(
        _ timers: [TimerRecord],
        mode: MenuBarDisplayMode,
        pinnedID: UUID? = nil,
        showZero: Bool = false,
        at date: Date
    ) -> MenuBarPresentation {
        MenuBarPresentationPolicy.presentation(
            timers: timers,
            mode: mode,
            pinnedTimerID: pinnedID,
            showZeroCount: showZero,
            urgentThreshold: .oneMinute,
            at: date
        )
    }

    private func timer(label: String, fireDate: Date, now: Date) -> TimerRecord {
        TimerRecord(createdAt: now, fireDate: fireDate, options: TimerOptions(label: label))
    }
}
