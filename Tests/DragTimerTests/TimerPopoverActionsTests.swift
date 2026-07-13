import XCTest
@testable import DragTimer

final class TimerPopoverActionsTests: XCTestCase {
    func testRunningTimerKeepsOnlyPauseAsInlineAction() {
        XCTAssertEqual(
            TimerRowActionPolicy.inlineActions(isPaused: false),
            [.pause]
        )
    }

    func testPausedTimerExposesDeleteResetAndResumeInline() {
        XCTAssertEqual(
            TimerRowActionPolicy.inlineActions(isPaused: true),
            [.delete, .reset, .resume]
        )
    }

    func testInlineActionsHaveSpecificSymbolsAndLabels() {
        XCTAssertEqual(TimerRowInlineAction.delete.symbolName, "trash")
        XCTAssertEqual(TimerRowInlineAction.delete.accessibilityLabel, "Delete timer")
        XCTAssertEqual(TimerRowInlineAction.reset.symbolName, "arrow.counterclockwise")
        XCTAssertEqual(TimerRowInlineAction.reset.accessibilityLabel, "Reset timer")
        XCTAssertEqual(TimerRowInlineAction.resume.symbolName, "play.fill")
        XCTAssertEqual(TimerRowInlineAction.resume.accessibilityLabel, "Resume timer")
    }

    func testStopAllCancelsTimersBeforeDismissingPopover() {
        var calls: [String] = []
        let actions = TimerPopoverActions(
            cancelAll: { calls.append("cancel") },
            dismissPopover: { calls.append("dismiss") }
        )

        actions.stopAll()

        XCTAssertEqual(calls, ["cancel", "dismiss"])
    }
}
