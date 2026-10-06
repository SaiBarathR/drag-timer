import AppKit

enum TimerLabelPrompt {
    static func requestLabel(targetFireDate: Date) -> String? {
        let controller = TimerLabelPromptController(targetFireDate: targetFireDate)
        return controller.run()
    }
}

enum TimerLabelPromptKeyAction: Equatable {
    case startTimer
    case insertLineBreak
    case cancel
    case focusNext
    case focusPrevious
}

enum TimerLabelPromptKeyPolicy {
    /// Return still starts the timer, as it did in the single-line field, so
    /// drag, type, Return stays one motion. Shift-Return adds a line;
    /// Option-Return already arrives as `insertNewlineIgnoringFieldEditor(_:)`,
    /// which the text view handles itself.
    static func action(
        for selector: Selector,
        modifiers: NSEvent.ModifierFlags
    ) -> TimerLabelPromptKeyAction? {
        switch selector {
        case #selector(NSResponder.insertNewline(_:)):
            return modifiers.contains(.shift) ? .insertLineBreak : .startTimer
        case #selector(NSResponder.cancelOperation(_:)):
            return .cancel
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
    private var accepted = false

    init(targetFireDate: Date) {
        self.targetFireDate = targetFireDate
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: Self.contentWidth + 48, height: 246),
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

        labelView.placeholder = "What is this timer for?"
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

        let hintLabel = NSTextField(labelWithString: "Return starts the timer · Shift-Return adds a line")
        hintLabel.font = .systemFont(ofSize: 11)
        hintLabel.textColor = .secondaryLabelColor

        let cancelButton = NSButton(title: "Cancel", target: self, action: #selector(cancel))
        cancelButton.keyEquivalent = "\u{1b}"
        cancelButton.bezelStyle = .rounded

        let startButton = NSButton(title: "Start Timer", target: self, action: #selector(startTimer))
        startButton.keyEquivalent = "\r"
        startButton.bezelStyle = .rounded

        let buttonRow = NSStackView(views: [cancelButton, startButton])
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
            cancelButton.heightAnchor.constraint(equalToConstant: 30),
            startButton.heightAnchor.constraint(equalToConstant: 30)
        ])
        panel.defaultButtonCell = startButton.cell as? NSButtonCell
        panel.initialFirstResponder = labelView
    }

    func run() -> String? {
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

        guard accepted else { return nil }
        let trimmedLabel = labelView.string.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedLabel.isEmpty ? "Timer" : trimmedLabel
    }

    func windowWillClose(_ notification: Notification) {
        accepted = false
        NSApp.abortModal()
    }

    func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        let modifiers = NSApp.currentEvent?.modifierFlags ?? []
        switch TimerLabelPromptKeyPolicy.action(for: commandSelector, modifiers: modifiers) {
        case .startTimer: startTimer()
        case .insertLineBreak: textView.insertNewlineIgnoringFieldEditor(nil)
        case .cancel: cancel()
        case .focusNext: panel.selectNextKeyView(nil)
        case .focusPrevious: panel.selectPreviousKeyView(nil)
        case nil: return false
        }
        return true
    }

    #if DEBUG
    var labelTextViewForTesting: NSTextView { labelView }
    var isLabelEditorFirstResponderForTesting: Bool { panel.firstResponder === labelView }
    #endif

    @objc private func startTimer() {
        accepted = true
        NSApp.stopModal()
    }

    @objc private func cancel() {
        accepted = false
        NSApp.abortModal()
    }

    private func refreshDetailText() {
        let remaining = max(0, targetFireDate.timeIntervalSinceNow)
        detailLabel.stringValue =
            "Starts in \(DurationText.compact(remaining)) at \(TimerDateText.fireTime(for: targetFireDate))."
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
