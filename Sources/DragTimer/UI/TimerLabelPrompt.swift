import AppKit

enum TimerLabelPromptOutcome: Equatable {
    case renamed(String)
    /// Dismissed, or confirmed with a blank name: the timer keeps running
    /// under the name it already has.
    case keptName
    case discarded
}

enum TimerLabelPrompt {
    static func requestLabel(targetFireDate: Date, currentLabel: String) -> TimerLabelPromptOutcome {
        let controller = TimerLabelPromptController(
            targetFireDate: targetFireDate,
            currentLabel: currentLabel
        )
        return controller.run()
    }
}

enum TimerLabelPromptKeyAction: Equatable {
    case saveName
    case insertLineBreak
    case keepName
    case focusNext
    case focusPrevious
}

enum TimerLabelPromptKeyPolicy {
    /// Return saves the name, as it did in the single-line field, so drag,
    /// type, Return stays one motion. Escape leaves the already-running timer
    /// alone. Shift-Return adds a line;
    /// Option-Return already arrives as `insertNewlineIgnoringFieldEditor(_:)`,
    /// which the text view handles itself.
    static func action(
        for selector: Selector,
        modifiers: NSEvent.ModifierFlags
    ) -> TimerLabelPromptKeyAction? {
        switch selector {
        case #selector(NSResponder.insertNewline(_:)):
            return modifiers.contains(.shift) ? .insertLineBreak : .saveName
        case #selector(NSResponder.cancelOperation(_:)):
            return .keepName
        case #selector(NSResponder.insertTab(_:)):
            return .focusNext
        case #selector(NSResponder.insertBacktab(_:)):
            return .focusPrevious
        default:
            return nil
        }
    }
}

final class TimerLabelPromptController: NSObject, NSWindowDelegate, NSTextViewDelegate {
    private static let contentWidth: CGFloat = 342
    private static let labelEditorHeight: CGFloat = 64

    private let panel: NSPanel
    private let targetFireDate: Date
    private let detailLabel = NSTextField(labelWithString: "")
    private let labelView: PlaceholderTextView
    private let discardButton = NSButton(title: "Discard Timer", target: nil, action: nil)
    private var outcome: TimerLabelPromptOutcome = .keptName

    init(targetFireDate: Date, currentLabel: String = "Timer") {
        self.targetFireDate = targetFireDate
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: Self.contentWidth + 48, height: 264),
            styleMask: [.titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        let labelScrollView = NSScrollView(
            frame: NSRect(x: 0, y: 0, width: Self.contentWidth, height: Self.labelEditorHeight)
        )
        labelScrollView.borderType = .bezelBorder
        labelView = PlaceholderTextView(frame: NSRect(origin: .zero, size: labelScrollView.contentSize))
        super.init()

        panel.title = "Name this timer"
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.level = .floating
        panel.animationBehavior = .utilityWindow
        panel.isReleasedWhenClosed = false
        panel.delegate = self
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true

        let titleLabel = NSTextField(labelWithString: "Name this timer")
        titleLabel.font = .systemFont(ofSize: 16, weight: .semibold)

        detailLabel.font = .systemFont(ofSize: 13)
        detailLabel.textColor = .secondaryLabelColor
        refreshDetailText()

        labelView.placeholder = currentLabel
        labelView.font = .systemFont(ofSize: 14)
        labelView.isRichText = false
        labelView.allowsUndo = true
        labelView.textContainerInset = NSSize(width: 2, height: 5)
        labelView.minSize = NSSize(width: 0, height: labelScrollView.contentSize.height)
        labelView.maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        labelView.isVerticallyResizable = true
        labelView.isHorizontallyResizable = false
        labelView.autoresizingMask = .width
        labelView.textContainer?.widthTracksTextView = true
        labelView.delegate = self
        labelView.setAccessibilityLabel("Timer label")
        labelView.setAccessibilityPlaceholderValue(labelView.placeholder)

        labelScrollView.hasVerticalScroller = true
        labelScrollView.autohidesScrollers = true
        labelScrollView.documentView = labelView

        let hintLabel = NSTextField(wrappingLabelWithString:
            "Return saves the name · Shift-Return adds a line\nEsc keeps the timer as \u{201C}\(currentLabel)\u{201D}")
        hintLabel.font = .systemFont(ofSize: 11)
        hintLabel.textColor = .secondaryLabelColor
        hintLabel.maximumNumberOfLines = 2
        hintLabel.lineBreakMode = .byTruncatingTail

        discardButton.target = self
        discardButton.action = #selector(discardTimer)
        discardButton.keyEquivalent = "\u{8}"
        discardButton.keyEquivalentModifierMask = .command
        discardButton.hasDestructiveAction = true
        discardButton.bezelStyle = .rounded
        discardButton.toolTip = "Cancel this timer (\u{2318}\u{232B})"

        let saveButton = NSButton(title: "Save Name", target: self, action: #selector(saveName))
        saveButton.keyEquivalent = "\r"
        saveButton.bezelStyle = .rounded

        let buttonRow = NSStackView(views: [discardButton, saveButton])
        buttonRow.orientation = .horizontal
        buttonRow.spacing = 10
        buttonRow.distribution = .fillEqually

        let contentStack = NSStackView(views: [titleLabel, detailLabel, labelScrollView, hintLabel, buttonRow])
        contentStack.orientation = .vertical
        contentStack.alignment = .leading
        contentStack.spacing = 10
        contentStack.setCustomSpacing(18, after: detailLabel)
        contentStack.setCustomSpacing(6, after: labelScrollView)
        contentStack.setCustomSpacing(16, after: hintLabel)
        contentStack.translatesAutoresizingMaskIntoConstraints = false

        let contentView = NSView()
        contentView.addSubview(contentStack)
        panel.contentView = contentView

        NSLayoutConstraint.activate([
            contentStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            contentStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),
            contentStack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 30),
            contentStack.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -20),
            labelScrollView.widthAnchor.constraint(equalTo: contentStack.widthAnchor),
            labelScrollView.heightAnchor.constraint(equalToConstant: Self.labelEditorHeight),
            buttonRow.widthAnchor.constraint(equalTo: contentStack.widthAnchor),
            hintLabel.widthAnchor.constraint(equalTo: contentStack.widthAnchor),
            discardButton.heightAnchor.constraint(equalToConstant: 30),
            saveButton.heightAnchor.constraint(equalToConstant: 30)
        ])
        panel.defaultButtonCell = saveButton.cell as? NSButtonCell
        panel.initialFirstResponder = labelView
    }

    func run() -> TimerLabelPromptOutcome {
        positionNearMenuBar()
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(labelView)

        // Repeat after the modal loop begins so the label editor—not the
        // window or default button—receives the first typed character.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            NSApp.activate(ignoringOtherApps: true)
            panel.makeKeyAndOrderFront(nil)
            panel.makeFirstResponder(labelView)
        }

        let detailTimer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            self?.refreshDetailText()
        }
        RunLoop.main.add(detailTimer, forMode: .common)
        NSApp.runModal(for: panel)
        detailTimer.invalidate()
        panel.orderOut(nil)

        return outcome
    }

    func windowWillClose(_ notification: Notification) {
        outcome = .keptName
        NSApp.abortModal()
    }

    func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        let modifiers = NSApp.currentEvent?.modifierFlags ?? []
        switch TimerLabelPromptKeyPolicy.action(for: commandSelector, modifiers: modifiers) {
        case .saveName: saveName()
        case .insertLineBreak: textView.insertNewlineIgnoringFieldEditor(nil)
        case .keepName: keepName()
        case .focusNext: panel.selectNextKeyView(nil)
        case .focusPrevious: panel.selectPreviousKeyView(nil)
        case nil: return false
        }
        return true
    }

    #if DEBUG
    var labelTextViewForTesting: NSTextView { labelView }
    var discardButtonForTesting: NSButton { discardButton }
    var isLabelEditorFirstResponderForTesting: Bool { panel.firstResponder === labelView }
    #endif

    @objc private func saveName() {
        let trimmedLabel = labelView.string.trimmingCharacters(in: .whitespacesAndNewlines)
        outcome = trimmedLabel.isEmpty ? .keptName : .renamed(trimmedLabel)
        NSApp.stopModal()
    }

    private func keepName() {
        outcome = .keptName
        NSApp.abortModal()
    }

    @objc private func discardTimer() {
        outcome = .discarded
        NSApp.abortModal()
    }

    private func refreshDetailText() {
        let remaining = max(0, targetFireDate.timeIntervalSinceNow)
        detailLabel.stringValue =
            "Running · rings at \(TimerDateText.fireTime(for: targetFireDate)), \(DurationText.compact(remaining)) left"
    }

    private func positionNearMenuBar() {
        guard let screen = NSScreen.main else {
            panel.center()
            return
        }
        let visibleFrame = screen.visibleFrame
        let origin = CGPoint(
            x: visibleFrame.midX - panel.frame.width / 2,
            y: visibleFrame.maxY - panel.frame.height - 18
        )
        panel.setFrameOrigin(origin)
    }
}

/// `NSTextView` has no placeholder of its own.
private final class PlaceholderTextView: NSTextView {
    var placeholder = ""

    override func didChangeText() {
        super.didChangeText()
        needsDisplay = true
    }

    // Input-method composition edits the text without `didChangeText()`.
    override func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        super.setMarkedText(string, selectedRange: selectedRange, replacementRange: replacementRange)
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard string.isEmpty else { return }
        let origin = textContainerOrigin
        placeholder.draw(
            at: NSPoint(x: origin.x + (textContainer?.lineFragmentPadding ?? 0), y: origin.y),
            withAttributes: [
                .font: font ?? .systemFont(ofSize: NSFont.systemFontSize),
                .foregroundColor: NSColor.placeholderTextColor
            ]
        )
    }
}
