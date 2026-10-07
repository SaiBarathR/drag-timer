import AppKit
import XCTest
@testable import DragTimer

final class TimerLabelPromptTests: XCTestCase {
    func testReturnSavesNameAndShiftReturnAddsALine() {
        let insertNewline = #selector(NSResponder.insertNewline(_:))

        XCTAssertEqual(TimerLabelPromptKeyPolicy.action(for: insertNewline, modifiers: []), .saveName)
        XCTAssertEqual(TimerLabelPromptKeyPolicy.action(for: insertNewline, modifiers: .shift), .insertLineBreak)
        XCTAssertEqual(
            TimerLabelPromptKeyPolicy.action(for: insertNewline, modifiers: [.shift, .capsLock]),
            .insertLineBreak
        )
    }

    func testEscapeKeepsNameAndTabMovesFocusInsteadOfTyping() {
        XCTAssertEqual(
            TimerLabelPromptKeyPolicy.action(for: #selector(NSResponder.cancelOperation(_:)), modifiers: []),
            .keepName
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
        let outcome = runPrompt { textView in
            textView.insertText("  Standup notes", replacementRange: textView.selectedRange())
            textView.doCommand(by: #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)))
            textView.insertText("Ask about the invoice", replacementRange: textView.selectedRange())
            textView.doCommand(by: #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)))
            textView.doCommand(by: #selector(NSResponder.insertNewline(_:)))
        }

        XCTAssertEqual(outcome, .renamed("Standup notes\nAsk about the invoice"))
    }

    @MainActor
    func testBlankNameKeepsTheExistingName() {
        let outcome = runPrompt { textView in
            textView.doCommand(by: #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)))
            textView.doCommand(by: #selector(NSResponder.insertNewline(_:)))
        }

        XCTAssertEqual(outcome, .keptName)
    }

    @MainActor
    func testEscapeKeepsTheTimerUnderItsExistingName() {
        let outcome = runPrompt { textView in
            textView.insertText("Abandoned", replacementRange: textView.selectedRange())
            textView.doCommand(by: #selector(NSResponder.cancelOperation(_:)))
        }

        XCTAssertEqual(outcome, .keptName)
    }

    @MainActor
    func testDiscardButtonReportsDiscardEvenWithATypedName() {
        var controller: TimerLabelPromptController?
        let outcome = runPrompt(capturing: { controller = $0 }) { textView in
            textView.insertText("Mistake", replacementRange: textView.selectedRange())
            controller?.discardButtonForTesting.performClick(nil)
        }

        XCTAssertEqual(outcome, .discarded)
    }

    @MainActor
    func testEscapeKeepsTheTimerEvenWhenAButtonHasFocus() {
        var controller: TimerLabelPromptController?
        let outcome = runPrompt(capturing: { controller = $0 }) { textView in
            guard let panel = textView.window, let button = controller?.discardButtonForTesting else { return }
            panel.makeFirstResponder(button)
            panel.sendEvent(Self.keyDown("\u{1b}", keyCode: 53, in: panel))
        }

        XCTAssertEqual(outcome, .keptName)
    }

    /// Command-Delete deletes to the start of the line in a text view. As a
    /// key equivalent on Discard it would be taken before the editor saw it.
    @MainActor
    func testCommandDeleteBelongsToTheEditorNotToDiscard() {
        var controller: TimerLabelPromptController?
        var claimedByAControl: Bool?
        let outcome = runPrompt(capturing: { controller = $0 }) { textView in
            guard let panel = textView.window else { return }
            textView.insertText("Tea", replacementRange: textView.selectedRange())
            claimedByAControl = panel.performKeyEquivalent(
                with: Self.keyDown("\u{7f}", keyCode: 51, modifiers: .command, in: panel)
            )
            textView.doCommand(by: #selector(NSResponder.insertNewline(_:)))
        }

        XCTAssertEqual(controller?.discardButtonForTesting.keyEquivalent, "")
        XCTAssertEqual(claimedByAControl, false)
        XCTAssertEqual(outcome, .renamed("Tea"))
    }

    private static func keyDown(
        _ characters: String,
        keyCode: UInt16,
        modifiers: NSEvent.ModifierFlags = [],
        in window: NSWindow
    ) -> NSEvent {
        NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: modifiers,
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber,
            context: nil,
            characters: characters,
            charactersIgnoringModifiers: characters,
            isARepeat: false,
            keyCode: keyCode
        )!
    }

    @MainActor
    func testTabDoesNotTypeIntoLabel() {
        let outcome = runPrompt { textView in
            textView.insertText("Tea", replacementRange: textView.selectedRange())
            textView.doCommand(by: #selector(NSResponder.insertTab(_:)))
            textView.doCommand(by: #selector(NSResponder.insertNewline(_:)))
        }

        XCTAssertEqual(outcome, .renamed("Tea"))
    }

    /// Runs the real modal prompt and drives its editor once the modal loop
    /// is spinning. The watchdog keeps a broken prompt from hanging the suite.
    @MainActor
    private func runPrompt(
        capturing capture: (TimerLabelPromptController) -> Void = { _ in },
        _ interact: @escaping (NSTextView) -> Void
    ) -> TimerLabelPromptOutcome {
        _ = NSApplication.shared
        let controller = TimerLabelPromptController(targetFireDate: Date().addingTimeInterval(300))
        capture(controller)
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

        let outcome = controller.run()

        XCTAssertTrue(editorHadFocus, "Label editor must own keyboard focus when the prompt opens")
        return outcome
    }
}
