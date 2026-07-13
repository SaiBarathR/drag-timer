import AppKit
import Combine

final class StatusItemController: NSObject {
    private let statusItem: NSStatusItem
    private let timerEngine: TimerEngine
    private let settings: AppSettings
    private let onPopoverRequested: (NSView, NSRect) -> Void
    private let onPopoverAnchorChanged: (NSView, NSRect) -> Void
    private let gestureController: DragGestureController
    private var statusView: StatusItemCaptureView?
    private var timersCancellable: AnyCancellable?
    private var settingsCancellable: AnyCancellable?
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
        self.settings = settings
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
        observeSettingsChanges()
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
        view.setAccessibilityElement(true)
        view.setAccessibilityRole(.button)
        view.setAccessibilityLabel("Drag Timer")
        view.setAccessibilityHelp("Drag to set a timer. Click to view timers.")
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
            guard let self else { return }
            if let pinnedID = settings.pinnedTimerID,
               !timers.contains(where: { $0.id == pinnedID }) {
                settings.pinnedTimerID = nil
            }
            refreshCountdown(using: timers)
        }
    }

    private func observeSettingsChanges() {
        settingsCancellable = settings.objectWillChange.sink { [weak self] in
            DispatchQueue.main.async { self?.refreshCountdown() }
        }
    }

    private func refreshCountdown(at date: Date = Date()) {
        refreshCountdown(using: timerEngine.timers, at: date)
    }

    private func refreshCountdown(using timers: [TimerRecord], at date: Date = Date()) {
        guard let statusView else { return }
        let presentation = MenuBarPresentationPolicy.presentation(
            timers: timers,
            mode: settings.menuBarDisplayMode,
            pinnedTimerID: settings.pinnedTimerID,
            showZeroCount: settings.showZeroCount,
            urgentThreshold: settings.urgentThreshold,
            at: date
        )
        let description = accessibilityDescription(for: presentation, at: date)
        updateStatusView(
            statusView,
            presentation: presentation,
            toolTip: description + ". Drag to set another timer or click to view timers.",
            accessibilityLabel: "Drag Timer, \(description)"
        )
        setCountdownTickerRunning(presentation.timer != nil && presentation.requestedMode != .count)
    }

    private func updateStatusView(
        _ statusView: StatusItemCaptureView,
        presentation: MenuBarPresentation,
        toolTip: String,
        accessibilityLabel: String
    ) {
        let previousWidth = statusItem.length
        statusView.update(
            presentation: presentation,
            highContrast: TimerAppearancePolicy.highContrast(settings: settings),
            countdownScale: settings.countdownScale,
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

    private func accessibilityDescription(for presentation: MenuBarPresentation, at date: Date) -> String {
        switch presentation.requestedMode {
        case .count:
            return "\(presentation.runningCount) running timer\(presentation.runningCount == 1 ? "" : "s")"
        case .deadline, .pinned, .ring:
            guard let timer = presentation.timer else {
                return presentation.requestedMode == .pinned
                    ? "Pinned mode, no timer pinned"
                    : "No running timers"
            }
            let modeName = presentation.requestedMode.displayName
            let fallback = presentation.usesFallback ? ", using nearest timer" : ""
            let paused = timer.isPaused ? ", paused" : ""
            let urgent = presentation.urgent ? ", urgent" : ""
            return "\(modeName)\(fallback), \(timer.label), \(MenuBarCountdown.text(for: timer, at: date)) remaining\(paused)\(urgent)"
        }
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
    private var presentation = MenuBarPresentation(
        requestedMode: .deadline,
        text: nil,
        timer: nil,
        runningCount: 0,
        usesFallback: false,
        urgent: false,
        progress: nil
    )
    private var highContrast = false
    private var countdownScale: CountdownScale = .standard
    private var lockedPresentationWidth: CGFloat?

    var preferredWidth: CGFloat {
        lockedPresentationWidth ?? StatusItemGeometry.width(for: presentation.text, scale: countdownScale)
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
            hasCountdownLayout: presentation.hasExpandedLayout || lockedPresentationWidth != nil
        )
    }

    func update(
        presentation: MenuBarPresentation,
        highContrast: Bool,
        countdownScale: CountdownScale,
        toolTip: String,
        accessibilityLabel: String
    ) {
        let layoutChanged = self.presentation.text != presentation.text
        self.presentation = presentation
        self.highContrast = highContrast
        self.countdownScale = countdownScale
        self.toolTip = toolTip
        setAccessibilityLabel(accessibilityLabel)

        if layoutChanged {
            invalidateIntrinsicContentSize()
        }
        needsDisplay = true
    }

    func lockPresentationGeometryIfNeeded() {
        guard presentation.text != nil else { return }
        let requiredWidth = StatusItemGeometry.width(for: presentation.text, scale: countdownScale)
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
        let identityColor = presentation.timer?.resolvedIdentity.color.nsColor ?? NSColor.labelColor
        let color = presentation.urgent ? NSColor.systemRed : identityColor
        color.setStroke()

        let face = NSBezierPath(ovalIn: CGRect(
            x: center.x - radius,
            y: center.y - radius,
            width: radius * 2,
            height: radius * 2
        ))
        face.lineWidth = highContrast ? 2.1 : 1.6
        face.stroke()

        if presentation.timer?.isPaused == true {
            let pause = NSBezierPath()
            pause.move(to: CGPoint(x: center.x - 2, y: center.y - 3))
            pause.line(to: CGPoint(x: center.x - 2, y: center.y + 3))
            pause.move(to: CGPoint(x: center.x + 2, y: center.y - 3))
            pause.line(to: CGPoint(x: center.x + 2, y: center.y + 3))
            pause.lineWidth = highContrast ? 2.1 : 1.6
            pause.stroke()
        } else if let timer = presentation.timer,
                  let symbol = NSImage(
                    systemSymbolName: presentation.urgent ? "exclamationmark" : timer.resolvedIdentity.symbolName,
                    accessibilityDescription: nil
                  )?.withSymbolConfiguration(.init(pointSize: 8, weight: .bold)) {
            symbol.draw(
                in: NSRect(x: center.x - 4, y: center.y - 4, width: 8, height: 8),
                from: .zero,
                operation: .sourceOver,
                fraction: 1,
                respectFlipped: true,
                hints: nil
            )
        } else {
            let hands = NSBezierPath()
            hands.move(to: center)
            hands.line(to: CGPoint(x: center.x, y: center.y + 4))
            hands.move(to: center)
            hands.line(to: CGPoint(x: center.x + 3.2, y: center.y - 1.8))
            hands.lineWidth = highContrast ? 2.1 : 1.6
            hands.lineCapStyle = .round
            hands.stroke()
        }

        if presentation.requestedMode == .ring, let storedProgress = presentation.progress {
            let progress = CGFloat(storedProgress)
            NSColor.separatorColor.setStroke()
            let track = NSBezierPath(ovalIn: face.bounds.insetBy(dx: -2.5, dy: -2.5))
            track.lineWidth = highContrast ? 2.4 : 1.8
            track.stroke()
            color.setStroke()
            let ringRect = face.bounds.insetBy(dx: -2.5, dy: -2.5)
            let ring = NSBezierPath()
            ring.appendArc(
                withCenter: CGPoint(x: ringRect.midX, y: ringRect.midY),
                radius: ringRect.width / 2,
                startAngle: 90,
                endAngle: 90 - (360 * progress),
                clockwise: true
            )
            ring.lineWidth = highContrast ? 2.4 : 1.8
            ring.lineCapStyle = .round
            ring.stroke()
        }

        if let countdownText = presentation.text {
            let attributes: [NSAttributedString.Key: Any] = [
                .font: StatusItemGeometry.countdownFont(for: countdownScale),
                .foregroundColor: presentation.urgent ? NSColor.systemRed : NSColor.labelColor
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
            hasCountdownLayout: presentation.hasExpandedLayout || lockedPresentationWidth != nil
        )
        return CGPoint(x: iconRect.midX, y: iconRect.midY)
    }

    private var screenCenter: CGPoint {
        guard let window else { return NSEvent.mouseLocation }
        let windowPoint = convert(timerIconCenter, to: nil)
        return window.convertPoint(toScreen: windowPoint)
    }

}
