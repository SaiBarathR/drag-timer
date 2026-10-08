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

    func testFinishedTimerOutranksRunningCountdownUntilItIsAnswered() {
        let now = Date(timeIntervalSinceReferenceDate: 1_000)
        let running = timer(label: "Deep work", fireDate: now.addingTimeInterval(600), now: now)
        let tea = expiry(label: "Tea", expiredAt: now.addingTimeInterval(-135))

        for mode in [MenuBarDisplayMode.deadline, .pinned] {
            let result = presentation([running], finished: [tea], mode: mode, pinnedID: running.id, at: now)
            XCTAssertEqual(result.text, "+2:15", "\(mode)")
            XCTAssertEqual(result.finished, MenuBarFinishedState(label: "Tea", expiredAt: tea.expiredAt, count: 1))
            XCTAssertNil(result.timer)
            XCTAssertTrue(result.urgent)
        }

        XCTAssertEqual(presentation([running], mode: .deadline, at: now).text, "10:00")
        XCTAssertNil(presentation([running], mode: .deadline, at: now).finished)
    }

    func testFinishedStateNamesTheLongestWaitingTimerAndCountsTheRest() {
        let now = Date(timeIntervalSinceReferenceDate: 1_000)
        let recent = expiry(label: "Laundry", expiredAt: now.addingTimeInterval(-10))
        let oldest = expiry(label: "Tea", expiredAt: now.addingTimeInterval(-4_000))

        let result = presentation([], finished: [recent, oldest], mode: .deadline, at: now)

        XCTAssertEqual(result.finished, MenuBarFinishedState(label: "Tea", expiredAt: oldest.expiredAt, count: 2))
        XCTAssertEqual(result.text, "+1h 6m")
    }

    func testRingAndCountKeepTheirLayoutWhenATimerHasFinished() {
        let now = Date(timeIntervalSinceReferenceDate: 1_000)
        let running = timer(label: "Deep work", fireDate: now.addingTimeInterval(600), now: now)
        let tea = expiry(label: "Tea", expiredAt: now.addingTimeInterval(-5))

        let ring = presentation([running], finished: [tea], mode: .ring, at: now)
        XCTAssertNil(ring.text)
        XCTAssertEqual(ring.progress, 1)
        XCTAssertNotNil(ring.finished)

        let count = presentation([running], finished: [tea], mode: .count, at: now)
        XCTAssertEqual(count.text, "1")
        XCTAssertFalse(count.urgent)
        XCTAssertEqual(count.finished?.label, "Tea")

        let idleCount = presentation([], finished: [tea], mode: .count, at: now)
        XCTAssertNil(idleCount.text)
        XCTAssertNotNil(idleCount.finished)
    }

    func testOvertimeCountsUpInWholeSecondsFromZero() {
        let finished = Date(timeIntervalSinceReferenceDate: 500)

        XCTAssertEqual(MenuBarCountdown.overtimeText(since: finished, at: finished), "+0:00")
        XCTAssertEqual(MenuBarCountdown.overtimeText(since: finished, at: finished.addingTimeInterval(0.9)), "+0:00")
        XCTAssertEqual(MenuBarCountdown.overtimeText(since: finished, at: finished.addingTimeInterval(59.9)), "+0:59")
        XCTAssertEqual(MenuBarCountdown.overtimeText(since: finished, at: finished.addingTimeInterval(60)), "+1:00")
        XCTAssertEqual(MenuBarCountdown.overtimeText(since: finished, at: finished.addingTimeInterval(-3)), "+0:00")
    }

    func testFinishedAgoReadsInWholeMinutes() {
        let finished = Date(timeIntervalSinceReferenceDate: 500)
        func ago(_ seconds: TimeInterval) -> String {
            MenuBarCountdown.finishedAgoText(since: finished, at: finished.addingTimeInterval(seconds))
        }

        XCTAssertEqual(ago(0), "just now")
        XCTAssertEqual(ago(59), "just now")
        XCTAssertEqual(ago(60), "1 min ago")
        XCTAssertEqual(ago(59 * 60 + 59), "59 min ago")
        XCTAssertEqual(ago(60 * 60), "1 hr ago")
        XCTAssertEqual(ago(65 * 60), "1 hr 5 min ago")
        XCTAssertEqual(ago(24 * 60 * 60), "1 day ago")
        XCTAssertEqual(ago(49 * 60 * 60), "2 days ago")
    }

    func testOvertimeTicksOnWholeSecondsSinceTheTimerFinished() {
        let finished = Date(timeIntervalSinceReferenceDate: 1_000.25)

        let tick = CountdownClock.nextTick(inPhaseWith: finished, after: finished.addingTimeInterval(2.3))

        XCTAssertEqual(tick.timeIntervalSince(finished), 3, accuracy: 0.000_001)
        XCTAssertEqual(MenuBarCountdown.overtimeText(since: finished, at: tick.addingTimeInterval(0.001)), "+0:03")
    }

    func testMinuteTicksLandOnWholeMinutesSinceTheTimerFinished() {
        let finished = Date(timeIntervalSinceReferenceDate: 1_000.25)

        let tick = CountdownClock.nextTick(inPhaseWith: finished, after: finished.addingTimeInterval(130), every: 60)

        XCTAssertEqual(tick.timeIntervalSince(finished), 180, accuracy: 0.000_001)
        XCTAssertEqual(MenuBarCountdown.finishedAgoText(since: finished, at: tick), "3 min ago")
    }

    private func expiry(label: String, expiredAt: Date) -> PendingExpiry {
        PendingExpiry(
            timer: timer(label: label, fireDate: expiredAt, now: expiredAt.addingTimeInterval(-300)),
            expiredAt: expiredAt
        )
    }

    private func presentation(
        _ timers: [TimerRecord],
        finished: [PendingExpiry] = [],
        mode: MenuBarDisplayMode,
        pinnedID: UUID? = nil,
        showZero: Bool = false,
        at date: Date
    ) -> MenuBarPresentation {
        MenuBarPresentationPolicy.presentation(
            timers: timers,
            pendingExpiries: finished,
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
