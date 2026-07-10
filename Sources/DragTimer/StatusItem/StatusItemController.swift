import AppKit

final class StatusItemController: NSObject {
    private let statusItem: NSStatusItem
    private let onPopoverRequested: (NSView) -> Void
    private let gestureController: DragGestureController
    private var statusView: StatusItemCaptureView?

    init(
        timerEngine: TimerEngine,
        settings: AppSettings,
        onPopoverRequested: @escaping (NSView) -> Void
    ) {
        statusItem = NSStatusBar.system.statusItem(withLength: 32)
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
    }

    deinit {
        NSStatusBar.system.removeStatusItem(statusItem)
    }

    private func configureStatusView() {
        let height = NSStatusBar.system.thickness
        let view = StatusItemCaptureView(frame: NSRect(x: 0, y: 0, width: 32, height: height))
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

    private func showPopover() {
        guard let statusView else { return }
        onPopoverRequested(statusView)
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

    override func draw(_ dirtyRect: NSRect) {
        if isTracking {
            NSColor.selectedControlColor.withAlphaComponent(0.26).setFill()
            NSBezierPath(roundedRect: bounds.insetBy(dx: 2, dy: 1), xRadius: 5, yRadius: 5).fill()
        }

        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let radius: CGFloat = 7
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

    private var screenRect: NSRect {
        guard let window else { return .zero }
        let windowRect = convert(bounds, to: nil)
        return window.convertToScreen(windowRect)
    }

    private var screenCenter: CGPoint {
        let rect = screenRect
        guard !rect.isEmpty else { return NSEvent.mouseLocation }
        return CGPoint(x: rect.midX, y: rect.midY)
    }
}
