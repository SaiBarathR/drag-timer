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

    func testRoutineLaunchForwardsOrderedSnapshotsAsRoutineTemplates() {
        let routine = TimerRoutine(
            name: "Morning",
            timers: [
                RoutineTimerDefinition(duration: 5 * 60, options: TimerOptions(label: "Coffee")),
                RoutineTimerDefinition(duration: 15 * 60, options: TimerOptions(label: "Journal"))
            ]
        )
        var captured: [TimerTemplate] = []
        let action = RoutineLaunchAction { captured = $0 }

        action.start(routine)

        XCTAssertEqual(captured.map(\.duration), [5 * 60, 15 * 60])
        XCTAssertEqual(captured.map(\.options.label), ["Coffee", "Journal"])
        XCTAssertTrue(captured.allSatisfy { $0.origin == .routine })
    }
}
