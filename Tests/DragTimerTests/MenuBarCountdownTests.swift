import AppKit
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

    func testStatusItemWidthFollowsRenderedCountdownText() {
        let countdowns = ["4:00", "10:00", "12h 59m", "1d 2h"]

        XCTAssertEqual(StatusItemGeometry.width(for: nil), 32)
        for countdown in countdowns {
            let expected = ceil(
                StatusItemGeometry.textLeading
                    + StatusItemGeometry.measuredWidth(of: countdown)
                    + StatusItemGeometry.textTrailing
            )
            XCTAssertEqual(StatusItemGeometry.width(for: countdown), expected)
        }

        XCTAssertEqual(StatusItemGeometry.width(for: "4:00"), StatusItemGeometry.width(for: "9:59"))
        XCTAssertLessThan(StatusItemGeometry.width(for: "4:00"), StatusItemGeometry.width(for: "10:00"))
        XCTAssertLessThan(StatusItemGeometry.width(for: "10:00"), StatusItemGeometry.width(for: "12h 59m"))
    }

    func testPopoverAnchorTracksClockGlyphInsteadOfWholeItem() {
        let countdownWidth = StatusItemGeometry.width(for: "4:00")
        let countdownBounds = NSRect(x: 0, y: 0, width: countdownWidth, height: 22)
        let countdownAnchor = StatusItemGeometry.popoverAnchorRect(
            in: countdownBounds,
            hasCountdownLayout: true
        )

        XCTAssertEqual(countdownAnchor.size, NSSize(width: 14, height: countdownBounds.height))
        XCTAssertEqual(countdownAnchor.midX, 13)
        XCTAssertNotEqual(countdownAnchor.midX, countdownBounds.midX)
        XCTAssertEqual(countdownAnchor.minY, countdownBounds.minY)

        let collapsedBounds = NSRect(x: 0, y: 0, width: 32, height: 22)
        let collapsedAnchor = StatusItemGeometry.popoverAnchorRect(
            in: collapsedBounds,
            hasCountdownLayout: false
        )
        XCTAssertEqual(collapsedAnchor.midX, collapsedBounds.midX)
    }
}
