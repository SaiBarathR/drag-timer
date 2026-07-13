import XCTest
@testable import DragTimer

final class MenuBarCountdownTests: XCTestCase {
    func testSelectsEarliestRunningTimerAndSkipsPausedTimers() {
        let now = Date(timeIntervalSinceReferenceDate: 1_000)
        let options = TimerOptions(label: "Countdown")
        let firstRunning = TimerRecord(
            createdAt: now,
            fireDate: now.addingTimeInterval(90),
            options: options
        )
        let laterRunning = TimerRecord(
            createdAt: now,
            fireDate: now.addingTimeInterval(180),
            options: options
        )
        var pausedSooner = TimerRecord(
            createdAt: now,
            fireDate: now.addingTimeInterval(30),
            options: options
        )
        pausedSooner.pausedRemaining = 30

        let selected = MenuBarCountdown.earliestRunningTimer(
            in: [laterRunning, pausedSooner, firstRunning]
        )

        XCTAssertEqual(selected?.id, firstRunning.id)
        XCTAssertNil(MenuBarCountdown.earliestRunningTimer(in: [pausedSooner]))
    }

    func testFormatsCountdownAtMinuteHourAndDayBoundaries() {
        XCTAssertEqual(MenuBarCountdown.text(forRemaining: 65), "1:05")
        XCTAssertEqual(MenuBarCountdown.text(forRemaining: (2 * 3_600) + (25 * 60) + 59), "2h 25m")
        XCTAssertEqual(MenuBarCountdown.text(forRemaining: (26 * 3_600) + 59), "1d 2h")
        XCTAssertEqual(MenuBarCountdown.text(forRemaining: 0.1), "0:01")
        XCTAssertEqual(MenuBarCountdown.text(forRemaining: 0), "0:00")
    }

    func testPopoverAnchorStaysExpandedWhenRunningTimerIsPaused() {
        let runningMode = StatusItemLayoutPolicy.mode(
            hasRunningTimer: true,
            isPopoverVisible: true
        )
        let pausedMode = StatusItemLayoutPolicy.mode(
            hasRunningTimer: false,
            isPopoverVisible: true
        )

        XCTAssertEqual(runningMode, .expanded)
        XCTAssertEqual(pausedMode, runningMode)
    }

    func testPausedTimerCollapsesOnlyAfterPopoverCloses() {
        XCTAssertEqual(
            StatusItemLayoutPolicy.mode(hasRunningTimer: false, isPopoverVisible: false),
            .collapsed
        )
    }
}
