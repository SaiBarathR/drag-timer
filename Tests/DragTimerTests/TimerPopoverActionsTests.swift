import XCTest
@testable import DragTimer

final class TimerPopoverActionsTests: XCTestCase {
    func testRunningTimerExposesMarkDoneAndPauseInline() {
        XCTAssertEqual(
            TimerRowActionPolicy.inlineActions(isPaused: false),
            [.done, .pause]
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
        XCTAssertEqual(TimerRowInlineAction.done.symbolName, "checkmark")
        XCTAssertEqual(TimerRowInlineAction.done.accessibilityLabel, "Mark timer done")
        XCTAssertEqual(TimerRowInlineAction.resume.symbolName, "play.fill")
        XCTAssertEqual(TimerRowInlineAction.resume.accessibilityLabel, "Resume timer")
    }

    func testListFollowsEngineOrderUntilAnOrderIsHeld() {
        let timers = [makeTimer("A"), makeTimer("B"), makeTimer("C")]

        XCTAssertEqual(
            TimerListOrderPolicy.arranged(timers, heldOrder: []).map(\.label),
            ["A", "B", "C"]
        )
    }

    func testPausedRowKeepsItsHeldPositionAfterEngineSortsItLast() {
        var top = makeTimer("Top")
        let middle = makeTimer("Middle")
        let bottom = makeTimer("Bottom")
        let heldOrder = [top, middle, bottom].map(\.id)
        top.pausedRemaining = 60

        let arranged = TimerListOrderPolicy.arranged([middle, bottom, top], heldOrder: heldOrder)

        XCTAssertEqual(arranged.map(\.label), ["Top", "Middle", "Bottom"])
        XCTAssertEqual(arranged.first?.isPaused, true)
    }

    func testHeldListDropsRemovedTimersAndAppendsNewOnesInEngineOrder() {
        let kept = makeTimer("Kept")
        let removed = makeTimer("Removed")
        let held = makeTimer("Held")
        let firstNew = makeTimer("First new")
        let secondNew = makeTimer("Second new")

        let arranged = TimerListOrderPolicy.arranged(
            [firstNew, held, secondNew, kept],
            heldOrder: [kept, removed, held].map(\.id)
        )

        XCTAssertEqual(arranged.map(\.label), ["Kept", "Held", "First new", "Second new"])
    }

    func testPointerOverListHoldsTheOrderThroughEveryChange() {
        let first = UUID(), second = UUID(), added = UUID()

        XCTAssertEqual(
            TimerListOrderPolicy.settle(from: [first, second], to: [second, first], isPointerOverList: true),
            .hold
        )
        XCTAssertEqual(
            TimerListOrderPolicy.settle(from: [first, second], to: [added, first, second], isPointerOverList: true),
            .hold
        )
    }

    func testReorderedOrRemovedRowsSettleAfterTheDelayOncePointerIsAway() {
        let first = UUID(), second = UUID()

        XCTAssertEqual(
            TimerListOrderPolicy.settle(from: [first, second], to: [second, first], isPointerOverList: false),
            .afterDelay
        )
        XCTAssertEqual(
            TimerListOrderPolicy.settle(from: [first, second], to: [second], isPointerOverList: false),
            .afterDelay
        )
    }

    func testNewTimerSettlesImmediatelyOncePointerIsAway() {
        let first = UUID(), second = UUID(), added = UUID()

        XCTAssertEqual(
            TimerListOrderPolicy.settle(from: [first, second], to: [added, second, first], isPointerOverList: false),
            .immediately
        )
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

        XCTAssertEqual(
            captured.map(\.duration),
            [TimeInterval(5 * 60), TimeInterval(15 * 60)]
        )
        XCTAssertEqual(captured.map(\.options.label), ["Coffee", "Journal"])
        XCTAssertTrue(captured.allSatisfy { $0.origin == .routine })
    }

    private func makeTimer(_ label: String) -> TimerRecord {
        let createdAt = Date(timeIntervalSince1970: 0)
        return TimerRecord(
            createdAt: createdAt,
            fireDate: createdAt.addingTimeInterval(300),
            options: TimerOptions(label: label)
        )
    }
}
