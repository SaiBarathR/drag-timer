import XCTest
@testable import DragTimer

final class TimerPopoverActionsTests: XCTestCase {
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
