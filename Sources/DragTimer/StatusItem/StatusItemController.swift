import AppKit
import Combine

final class StatusItemController: NSObject {
    private static let collapsedWidth: CGFloat = 32

    private let statusItem: NSStatusItem
    private let timerEngine: TimerEngine
    private let onPopoverRequested: (NSView) -> Void
    private let gestureController: DragGestureController
    private var statusView: StatusItemCaptureView?
    private var timersCancellable: AnyCancellable?
    private var countdownTicker: Timer?
    private var isPopoverVisible = false

    init(
        timerEngine: TimerEngine,
        settings: AppSettings,
        onPopoverRequested: @escaping (NSView) -> Void
    ) {
        statusItem = NSStatusBar.system.statusItem(withLength: Self.collapsedWidth)
        self.timerEngine = timerEngine
        self.onPopoverRequested = onPopoverRequested
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
        guard isPopoverVisible != isVisible else { return }
        isPopoverVisible = isVisible
        refreshCountdown()
    }

    #if DEBUG
    var currentWidth: CGFloat { statusItem.length }
    #endif

    private func configureStatusView() {
        let height = NSStatusBar.system.thickness
        let view = StatusItemCaptureView(
            frame: NSRect(x: 0, y: 0, width: Self.collapsedWidth, height: height)
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
        timersCancellable = timerEngine.$timers.sink { [weak self] _ in
            self?.refreshCountdown()
        }
    }

    private func refreshCountdown(at date: Date = Date()) {
        guard let statusView else { return }
        let timer = MenuBarCountdown.earliestRunningTimer(in: timerEngine.timers)
        let layoutMode = StatusItemLayoutPolicy.mode(
            hasRunningTimer: timer != nil,
            isPopoverVisible: isPopoverVisible
        )

        guard let timer else {
            statusView.update(
                countdownText: nil,
                layoutMode: layoutMode,
                toolTip: "Drag to set a timer. Click to view timers.",
                accessibilityLabel: "Drag Timer"
            )
            statusItem.length = layoutMode == .expanded
                ? statusView.expandedWidth
                : Self.collapsedWidth
            setCountdownTickerRunning(false)
            return
        }

        let countdownText = MenuBarCountdown.text(for: timer, at: date)
        statusView.update(
            countdownText: countdownText,
            layoutMode: layoutMode,
            toolTip: "\(timer.label): \(countdownText) remaining. Drag to set another timer or click to view timers.",
            accessibilityLabel: "Drag Timer, \(timer.label), \(countdownText) remaining"
        )
        statusItem.length = statusView.expandedWidth
        setCountdownTickerRunning(true)
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
        onPopoverRequested(statusView)
    }
}

/// A small, self-drawn menu-bar control. Its local tracking loop is deliberate:
/// once it receives mouse-down, AppKit continues feeding it drag/up events even
/// after the pointer has left the status item's bounds.
private final class StatusItemCaptureView: NSView {
    private static let iconDiameter: CGFloat = 14
    private static let iconLeading: CGFloat = 6
    private static let textLeading: CGFloat = 26
    private static let textTrailing: CGFloat = 7
    private static let countdownFont = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .medium)

    var onBegin: ((CGPoint, CGPoint, TimeInterval) -> Void)?
    var onDrag: ((CGPoint, TimeInterval) -> Void)?
    var onEnd: ((CGPoint, TimeInterval) -> Void)?
    var onClick: (() -> Void)?
    var onSecondaryClick: (() -> Void)?

    private var isTracking = false {
        didSet { needsDisplay = true }
    }
    private var countdownText: String?
    private var layoutMode: StatusItemLayoutMode = .collapsed

    var expandedWidth: CGFloat {
        // One fixed expanded width prevents the anchor from moving when a
        // countdown crosses a formatting boundary or disappears on pause.
        let textWidth = measuredWidth(of: "00h 00m")
        return ceil(Self.textLeading + textWidth + Self.textTrailing)
    }

    func update(
        countdownText: String?,
        layoutMode: StatusItemLayoutMode,
        toolTip: String,
        accessibilityLabel: String
    ) {
        let layoutChanged = self.countdownText != countdownText || self.layoutMode != layoutMode
        self.countdownText = countdownText
        self.layoutMode = layoutMode
        self.toolTip = toolTip
        setAccessibilityLabel(accessibilityLabel)

        if layoutChanged {
            invalidateIntrinsicContentSize()
        }
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        if isTracking {
            NSColor.selectedControlColor.withAlphaComponent(0.26).setFill()
            NSBezierPath(roundedRect: bounds.insetBy(dx: 2, dy: 1), xRadius: 5, yRadius: 5).fill()
        }

        let center = timerIconCenter
        let radius = Self.iconDiameter / 2
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
                .font: Self.countdownFont,
                .foregroundColor: NSColor.labelColor
            ]
            let textSize = (countdownText as NSString).size(withAttributes: attributes)
            let textRect = NSRect(
                x: Self.textLeading,
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
        guard layoutMode == .expanded else {
            return CGPoint(x: bounds.midX, y: bounds.midY)
        }
        return CGPoint(
            x: Self.iconLeading + (Self.iconDiameter / 2),
            y: bounds.midY
        )
    }

    private var screenCenter: CGPoint {
        guard let window else { return NSEvent.mouseLocation }
        let windowPoint = convert(timerIconCenter, to: nil)
        return window.convertPoint(toScreen: windowPoint)
    }

    private func measuredWidth(of text: String) -> CGFloat {
        (text as NSString).size(withAttributes: [.font: Self.countdownFont]).width
    }
}
