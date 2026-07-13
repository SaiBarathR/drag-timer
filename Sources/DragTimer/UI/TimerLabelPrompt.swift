import AppKit

enum TimerLabelPrompt {
    static func requestLabel(targetFireDate: Date) -> String? {
        let controller = TimerLabelPromptController(targetFireDate: targetFireDate)
        return controller.run()
    }
}

private final class TimerLabelPromptController: NSObject, NSWindowDelegate {
    private let panel: NSPanel
    private let targetFireDate: Date
    private let detailLabel = NSTextField(labelWithString: "")
    private let labelField = NSTextField()
    private var accepted = false

    init(targetFireDate: Date) {
        self.targetFireDate = targetFireDate
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 390, height: 190),
            styleMask: [.titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
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

        labelField.placeholderString = "What is this timer for?"
        labelField.stringValue = ""
        labelField.font = .systemFont(ofSize: 14)
        labelField.setAccessibilityLabel("Timer label")

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

        let contentStack = NSStackView(views: [titleLabel, detailLabel, labelField, buttonRow])
        contentStack.orientation = .vertical
        contentStack.alignment = .leading
        contentStack.spacing = 10
        contentStack.setCustomSpacing(18, after: detailLabel)
        contentStack.translatesAutoresizingMaskIntoConstraints = false

        let contentView = NSView()
        contentView.addSubview(contentStack)
        panel.contentView = contentView

        NSLayoutConstraint.activate([
            contentStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            contentStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),
            contentStack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 30),
            contentStack.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -20),
            labelField.widthAnchor.constraint(equalTo: contentStack.widthAnchor),
            labelField.heightAnchor.constraint(equalToConstant: 26),
            buttonRow.widthAnchor.constraint(equalTo: contentStack.widthAnchor),
            cancelButton.heightAnchor.constraint(equalToConstant: 30),
            startButton.heightAnchor.constraint(equalToConstant: 30)
        ])
        panel.defaultButtonCell = startButton.cell as? NSButtonCell
        panel.initialFirstResponder = labelField
    }

    func run() -> String? {
        positionNearMenuBar()
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(labelField)

        // Repeat after the modal loop begins so the field editor—not the
        // window or default button—receives the first typed character.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            NSApp.activate(ignoringOtherApps: true)
            panel.makeKeyAndOrderFront(nil)
            panel.makeFirstResponder(labelField)
        }

        let detailTimer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            self?.refreshDetailText()
        }
        RunLoop.main.add(detailTimer, forMode: .common)
        NSApp.runModal(for: panel)
        detailTimer.invalidate()
        panel.orderOut(nil)

        guard accepted else { return nil }
        let trimmedLabel = labelField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedLabel.isEmpty ? "Timer" : trimmedLabel
    }

    func windowWillClose(_ notification: Notification) {
        accepted = false
        NSApp.abortModal()
    }

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
