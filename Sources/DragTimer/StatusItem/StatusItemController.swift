import AppKit
import Combine

final class StatusItemController: NSObject {
    private let statusItem: NSStatusItem
    private let timerEngine: TimerEngine
    private let onPopoverRequested: (NSView, NSRect) -> Void
    private let onPopoverAnchorChanged: (NSView, NSRect) -> Void
    private let gestureController: DragGestureController
    private var statusView: StatusItemCaptureView?
    private var timersCancellable: AnyCancellable?
    private var countdownTicker: Timer?
    private var isPopoverVisible = false

    init(
        timerEngine: TimerEngine,
        settings: AppSettings,
        onPopoverRequested: @escaping (NSView, NSRect) -> Void,
        onPopoverAnchorChanged: @escaping (NSView, NSRect) -> Void = { _, _ in }
    ) {
        statusItem = NSStatusBar.system.statusItem(withLength: StatusItemGeometry.collapsedWidth)
        self.timerEngine = timerEngine
        self.onPopoverRequested = onPopoverRequested
        self.onPopoverAnchorChanged = onPopoverAnchorChanged
        gestureController = DragGestureController(
            timerEngine: timerEngine,
            settings: settings,
            onPopoverRequested: {}
        )
        super.init()

        gestureController.setPopoverRequestHandler { [weak self] in
            self?.showPopover()
        }
        configureStatusView()
        observeTimerChanges()
    }

    deinit {
        countdownTicker?.invalidate()
        NSStatusBar.system.removeStatusItem(statusItem)
    }

    func setPopoverVisible(_ isVisible: Bool) {
        guard isPopoverVisible != isVisible, let statusView else { return }
        isPopoverVisible = isVisible
        if isVisible {
            statusView.lockPresentationGeometryIfNeeded()
        } else {
            statusView.unlockPresentationGeometry()
            refreshCountdown()
        }
    }

    #if DEBUG
    var currentWidth: CGFloat { statusItem.length }
    var currentPopoverAnchorRect: NSRect { statusView?.popoverAnchorRect ?? .zero }

    func requestPopoverForTesting() {
        showPopover()
    }

    func refreshCountdownForTesting(at date: Date) {
        refreshCountdown(at: date)
    }
    #endif

    private func configureStatusView() {
        let height = NSStatusBar.system.thickness
        let view = StatusItemCaptureView(
            frame: NSRect(x: 0, y: 0, width: StatusItemGeometry.collapsedWidth, height: height)
        )
        view.toolTip = "Drag to set a timer. Click to view timers."
        view.onBegin = { [weak self] origin, pointer, timestamp in
            guard let self else { return }
            self.gestureController.begin(origin: origin, pointer: origin, timestamp: timestamp)
            self.gestureController.drag(pointer: pointer, timestamp: timestamp)
        }
        view.onDrag = { [weak self] pointer, timestamp in
            self?.gestureController.drag(pointer: pointer, timestamp: timestamp)
        }
        view.onEnd = { [weak self] pointer, timestamp in
            self?.gestureController.end(pointer: pointer, timestamp: timestamp)
        }
        view.onClick = { [weak self] in
            self?.showPopover()
        }
        view.onSecondaryClick = { [weak self] in
            self?.gestureController.cancel()
            self?.showPopover()
        }

        // NSStatusItem's custom-view API is deprecated in favor of a button,
        // but remains the AppKit path that gives this interaction ownership of
        // the entire mouse-tracking sequence instead of a button action.
        statusItem.view = view
        statusView = view
    }

    private func observeTimerChanges() {
        timersCancellable = timerEngine.$timers.sink { [weak self] timers in
            // @Published delivers the new value before the stored property is
            // updated, so use the emitted collection instead of reading the
            // engine synchronously and briefly rendering stale timer state.
            self?.refreshCountdown(using: timers)
        }
    }

    private func refreshCountdown(at date: Date = Date()) {
        refreshCountdown(using: timerEngine.timers, at: date)
    }

    private func refreshCountdown(using timers: [TimerRecord], at date: Date = Date()) {
        guard let statusView else { return }
        let timer = MenuBarCountdown.earliestRunningTimer(in: timers)

        guard let timer else {
            updateStatusView(
                statusView,
                countdownText: nil,
                toolTip: "Drag to set a timer. Click to view timers.",
                accessibilityLabel: "Drag Timer"
            )
            setCountdownTickerRunning(false)
            return
        }

        let countdownText = MenuBarCountdown.text(for: timer, at: date)
        updateStatusView(
            statusView,
            countdownText: countdownText,
            toolTip: "\(timer.label): \(countdownText) remaining. Drag to set another timer or click to view timers.",
            accessibilityLabel: "Drag Timer, \(timer.label), \(countdownText) remaining"
        )
        setCountdownTickerRunning(true)
    }

    private func updateStatusView(
        _ statusView: StatusItemCaptureView,
        countdownText: String?,
        toolTip: String,
        accessibilityLabel: String
    ) {
        let previousWidth = statusItem.length
        statusView.update(
            countdownText: countdownText,
            toolTip: toolTip,
            accessibilityLabel: accessibilityLabel
        )
        if isPopoverVisible {
            statusView.lockPresentationGeometryIfNeeded()
        }

        let preferredWidth = statusView.preferredWidth
        guard previousWidth != preferredWidth else { return }
        statusItem.length = preferredWidth
        onPopoverAnchorChanged(statusView, statusView.popoverAnchorRect)
    }

    private func setCountdownTickerRunning(_ shouldRun: Bool) {
        if shouldRun {
            guard countdownTicker == nil else { return }

            let ticker = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
                self?.refreshCountdown()
            }
            countdownTicker = ticker
            RunLoop.main.add(ticker, forMode: .common)
        } else {
            countdownTicker?.invalidate()
            countdownTicker = nil
        }
    }

    private func showPopover() {
        guard let statusView else { return }
        onPopoverRequested(statusView, statusView.popoverAnchorRect)
    }
}

/// A small, self-drawn menu-bar control. Its local tracking loop is deliberate:
/// once it receives mouse-down, AppKit continues feeding it drag/up events even
/// after the pointer has left the status item's bounds.
private final class StatusItemCaptureView: NSView {
    var onBegin: ((CGPoint, CGPoint, TimeInterval) -> Void)?
    var onDrag: ((CGPoint, TimeInterval) -> Void)?
    var onEnd: ((CGPoint, TimeInterval) -> Void)?
    var onClick: (() -> Void)?
    var onSecondaryClick: (() -> Void)?

    private var isTracking = false {
        didSet { needsDisplay = true }
    }
    private var countdownText: String?
    private var lockedPresentationWidth: CGFloat?

    var preferredWidth: CGFloat {
        lockedPresentationWidth ?? StatusItemGeometry.width(for: countdownText)
    }

    var popoverAnchorRect: NSRect {
        let geometryBounds = NSRect(
            x: bounds.minX,
            y: bounds.minY,
            width: preferredWidth,
            height: bounds.height
        )
        return StatusItemGeometry.popoverAnchorRect(
            in: geometryBounds,
            hasCountdownLayout: countdownText != nil || lockedPresentationWidth != nil
        )
    }

    func update(
        countdownText: String?,
        toolTip: String,
        accessibilityLabel: String
    ) {
        let layoutChanged = self.countdownText != countdownText
        self.countdownText = countdownText
        self.toolTip = toolTip
        setAccessibilityLabel(accessibilityLabel)

        if layoutChanged {
            invalidateIntrinsicContentSize()
        }
        needsDisplay = true
    }

    func lockPresentationGeometryIfNeeded() {
        guard countdownText != nil else { return }
        let requiredWidth = StatusItemGeometry.width(for: countdownText)
        lockedPresentationWidth = max(lockedPresentationWidth ?? 0, requiredWidth)
    }

    func unlockPresentationGeometry() {
        lockedPresentationWidth = nil
    }

    override func draw(_ dirtyRect: NSRect) {
        if isTracking {
            NSColor.selectedControlColor.withAlphaComponent(0.26).setFill()
            NSBezierPath(roundedRect: bounds.insetBy(dx: 2, dy: 1), xRadius: 5, yRadius: 5).fill()
        }

        let center = timerIconCenter
        let radius = StatusItemGeometry.iconDiameter / 2
        let color = NSColor.labelColor
        color.setStroke()

        let face = NSBezierPath(ovalIn: CGRect(
            x: center.x - radius,
            y: center.y - radius,
            width: radius * 2,
            height: radius * 2
        ))
        face.lineWidth = 1.6
        face.stroke()

        let hands = NSBezierPath()
        hands.move(to: center)
        hands.line(to: CGPoint(x: center.x, y: center.y + 4))
        hands.move(to: center)
        hands.line(to: CGPoint(x: center.x + 3.2, y: center.y - 1.8))
        hands.lineWidth = 1.6
        hands.lineCapStyle = .round
        hands.stroke()

        if let countdownText {
            let attributes: [NSAttributedString.Key: Any] = [
                .font: StatusItemGeometry.countdownFont,
                .foregroundColor: NSColor.labelColor
            ]
            let textSize = (countdownText as NSString).size(withAttributes: attributes)
            let textRect = NSRect(
                x: StatusItemGeometry.textLeading,
                y: floor((bounds.height - textSize.height) / 2) + 0.5,
                width: ceil(textSize.width),
                height: ceil(textSize.height)
            )
            (countdownText as NSString).draw(in: textRect, withAttributes: attributes)
        }
    }

    override func mouseDown(with event: NSEvent) {
        let origin = screenCenter
        var didBeginDrag = false
        isTracking = true

        defer { isTracking = false }

        while true {
            guard let nextEvent = NSApp.nextEvent(
                matching: [.leftMouseDragged, .leftMouseUp],
                until: .distantFuture,
                inMode: .eventTracking,
                dequeue: true
            ) else {
                continue
            }

            let pointer = NSEvent.mouseLocation
            switch nextEvent.type {
            case .leftMouseDragged:
                if !didBeginDrag {
                    didBeginDrag = true
                    onBegin?(origin, pointer, nextEvent.timestamp)
                } else {
                    onDrag?(pointer, nextEvent.timestamp)
                }
            case .leftMouseUp:
                if didBeginDrag {
                    onEnd?(pointer, nextEvent.timestamp)
                } else {
                    onClick?()
                }
                return
            default:
                break
            }
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        onSecondaryClick?()
    }

    private var timerIconCenter: CGPoint {
        let iconRect = StatusItemGeometry.iconRect(
            in: bounds,
            hasCountdownLayout: countdownText != nil || lockedPresentationWidth != nil
        )
        return CGPoint(x: iconRect.midX, y: iconRect.midY)
    }

    private var screenCenter: CGPoint {
        guard let window else { return NSEvent.mouseLocation }
        let windowPoint = convert(timerIconCenter, to: nil)
        return window.convertPoint(toScreen: windowPoint)
    }

}
