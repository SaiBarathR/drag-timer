import AppKit
import XCTest
@testable import DragTimer

final class TimerLabelPromptTests: XCTestCase {
    func testReturnStartsTimerAndShiftReturnAddsALine() {
        let insertNewline = #selector(NSResponder.insertNewline(_:))

        XCTAssertEqual(TimerLabelPromptKeyPolicy.action(for: insertNewline, modifiers: []), .startTimer)
        XCTAssertEqual(TimerLabelPromptKeyPolicy.action(for: insertNewline, modifiers: .shift), .insertLineBreak)
        XCTAssertEqual(
            TimerLabelPromptKeyPolicy.action(for: insertNewline, modifiers: [.shift, .capsLock]),
            .insertLineBreak
        )
    }

    func testEscapeCancelsAndTabMovesFocusInsteadOfTyping() {
        XCTAssertEqual(
            TimerLabelPromptKeyPolicy.action(for: #selector(NSResponder.cancelOperation(_:)), modifiers: []),
            .cancel
        )
        XCTAssertEqual(
            TimerLabelPromptKeyPolicy.action(for: #selector(NSResponder.insertTab(_:)), modifiers: []),
            .focusNext
        )
        XCTAssertEqual(
            TimerLabelPromptKeyPolicy.action(for: #selector(NSResponder.insertBacktab(_:)), modifiers: .shift),
            .focusPrevious
        )
    }

    func testOtherEditingCommandsStayWithTheTextView() {
        XCTAssertNil(TimerLabelPromptKeyPolicy.action(
            for: #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)),
            modifiers: .option
        ))
        XCTAssertNil(TimerLabelPromptKeyPolicy.action(
            for: #selector(NSResponder.deleteBackward(_:)),
            modifiers: []
        ))
    }

    @MainActor
    func testPromptKeepsEveryLineOfAMultilineLabel() {
        let label = runPrompt { textView in
            textView.insertText("  Standup notes", replacementRange: textView.selectedRange())
            textView.doCommand(by: #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)))
            textView.insertText("Ask about the invoice", replacementRange: textView.selectedRange())
            textView.doCommand(by: #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)))
            textView.doCommand(by: #selector(NSResponder.insertNewline(_:)))
        }

        XCTAssertEqual(label, "Standup notes\nAsk about the invoice")
    }

    @MainActor
    func testPromptFallsBackToTimerForBlankLabel() {
        let label = runPrompt { textView in
            textView.doCommand(by: #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)))
            textView.doCommand(by: #selector(NSResponder.insertNewline(_:)))
        }

        XCTAssertEqual(label, "Timer")
    }

    @MainActor
    func testEscapeDismissesPromptWithoutALabel() {
        let label = runPrompt { textView in
            textView.insertText("Discarded", replacementRange: textView.selectedRange())
            textView.doCommand(by: #selector(NSResponder.cancelOperation(_:)))
        }

        XCTAssertNil(label)
    }

    @MainActor
    func testTabDoesNotTypeIntoLabel() {
        let label = runPrompt { textView in
            textView.insertText("Tea", replacementRange: textView.selectedRange())
            textView.doCommand(by: #selector(NSResponder.insertTab(_:)))
            textView.doCommand(by: #selector(NSResponder.insertNewline(_:)))
        }

        XCTAssertEqual(label, "Tea")
    }

    /// Runs the real modal prompt and drives its editor once the modal loop
    /// is spinning. The watchdog keeps a broken prompt from hanging the suite.
    @MainActor
    private func runPrompt(_ interact: @escaping (NSTextView) -> Void) -> String? {
        _ = NSApplication.shared
        let controller = TimerLabelPromptController(targetFireDate: Date().addingTimeInterval(300))
        var editorHadFocus = false
        DispatchQueue.main.async {
            // The prompt re-asserts first responder from its own main-queue
            // block, which was enqueued by `run()` after this one.
            DispatchQueue.main.async {
                editorHadFocus = controller.isLabelEditorFirstResponderForTesting
                interact(controller.labelTextViewForTesting)
            }
        }
        let watchdog = Timer(timeInterval: 5, repeats: false) { _ in
            XCTFail("Label prompt never resolved")
            NSApp.abortModal()
        }
        RunLoop.main.add(watchdog, forMode: .common)
        defer { watchdog.invalidate() }

        let label = controller.run()

        XCTAssertTrue(editorHadFocus, "Label editor must own keyboard focus when the prompt opens")
        return label
    }
}
