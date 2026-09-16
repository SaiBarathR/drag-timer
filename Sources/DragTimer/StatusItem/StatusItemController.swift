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
    private var inputDiagnosticsMonitor: Any?

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
        if let inputDiagnosticsMonitor { NSEvent.removeMonitor(inputDiagnosticsMonitor) }
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
        view.onCancel = { [weak self] in
            self?.gestureController.cancel()
        }
        view.onClick = { [weak self] in
            self?.showPopover()
        }
        view.onSecondaryClick = { [weak self] in
            self?.gestureController.cancel()
            self?.showPopover()
        }

        // Keep the custom drawing and geometry; gesture recognizers own input
        // so AppKit can dispatch drags without a nested event-tracking loop.
        statusItem.view = view
        statusView = view
        if CommandLine.arguments.contains("--input-diagnostics") {
            inputDiagnosticsMonitor = NSEvent.addLocalMonitorForEvents(
                matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp]
            ) { [weak view] event in
                if event.window === view?.window {
                    NSLog("INPUT local type=%ld point=%@ hardware=%@ buttons=%lu", event.type.rawValue,
                          NSStringFromPoint(event.locationInWindow), NSStringFromPoint(NSEvent.mouseLocation), NSEvent.pressedMouseButtons)
                }
                return event
            }
            NSLog("INPUT host=%@ frame=%@ super=%@", String(describing: view.window),
                  NSStringFromRect(view.frame), String(describing: view.superview))
        }
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

/// Gesture recognition keeps tracking outside the icon without stealing events
/// from AppKit's modern input dispatch (including macOS 27).
private final class StatusItemCaptureView: NSView, NSGestureRecognizerDelegate {
    var onBegin: ((CGPoint, CGPoint, TimeInterval) -> Void)?
    var onDrag: ((CGPoint, TimeInterval) -> Void)?
    var onEnd: ((CGPoint, TimeInterval) -> Void)?
    var onCancel: (() -> Void)?
    var onClick: (() -> Void)?
    var onSecondaryClick: (() -> Void)?

    private lazy var panRecognizer = NSPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
    private lazy var clickRecognizer = NSClickGestureRecognizer(target: self, action: #selector(handleClick(_:)))
    private var pointerSession: StatusItemPointerSession?
    private var pointerTicker: Timer?

    deinit { pointerTicker?.invalidate() }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        panRecognizer.buttonMask = 0x1
        panRecognizer.delaysPrimaryMouseButtonEvents = true
        clickRecognizer.buttonMask = 0x1
        clickRecognizer.delegate = self
        addGestureRecognizer(panRecognizer)
        addGestureRecognizer(clickRecognizer)
        let secondaryClick = NSClickGestureRecognizer(target: self, action: #selector(handleSecondaryClick(_:)))
        secondaryClick.buttonMask = 0x2
        addGestureRecognizer(secondaryClick)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    func gestureRecognizer(
        _ gestureRecognizer: NSGestureRecognizer,
        shouldRequireFailureOf otherGestureRecognizer: NSGestureRecognizer
    ) -> Bool {
        gestureRecognizer === clickRecognizer && otherGestureRecognizer === panRecognizer
    }

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

    @objc private func handlePan(_ recognizer: NSPanGestureRecognizer) {
        guard pointerSession == nil else { return }
        let windowPoint = recognizer.location(in: nil)
        let pointer = window?.convertPoint(toScreen: windowPoint) ?? NSEvent.mouseLocation
        let timestamp = ProcessInfo.processInfo.systemUptime
        if CommandLine.arguments.contains("--input-diagnostics") {
            NSLog("INPUT pan state=%ld pointer=%@ origin=%@", recognizer.state.rawValue,
                  NSStringFromPoint(pointer), NSStringFromPoint(screenCenter))
        }
        switch recognizer.state {
        case .began:
            isTracking = true
            onBegin?(screenCenter, pointer, timestamp)
        case .changed:
            onDrag?(pointer, timestamp)
        case .ended:
            isTracking = false
            onEnd?(pointer, timestamp)
        case .cancelled, .failed:
            isTracking = false
            onCancel?()
        default:
            break
        }
    }

    @objc private func handleClick(_ recognizer: NSClickGestureRecognizer) {
        if CommandLine.arguments.contains("--input-diagnostics") {
            NSLog("INPUT click state=%ld buttons=%lu", recognizer.state.rawValue, NSEvent.pressedMouseButtons)
        }
        guard recognizer.state == .ended else { return }
        guard pointerSession == nil else { return }
        if NSEvent.pressedMouseButtons & 1 != 0 {
            // macOS 27 can forward a complete click before physical release,
            // with no subsequent drag events. Observe only this initiated
            // press; no global event tap or Accessibility permission is needed.
            pointerSession = StatusItemPointerSession(origin: NSEvent.mouseLocation)
            isTracking = true
            let ticker = Timer(timeInterval: 1.0 / 120.0, repeats: true) { [weak self] _ in
                self?.samplePhysicalPointer()
            }
            pointerTicker = ticker
            RunLoop.main.add(ticker, forMode: .common)
            RunLoop.main.add(ticker, forMode: .eventTracking)
        } else {
            onClick?()
        }
    }

    private func samplePhysicalPointer() {
        guard var session = pointerSession else { return }
        let pointer = NSEvent.mouseLocation
        let timestamp = ProcessInfo.processInfo.systemUptime
        let actions = session.sample(pointer: pointer, isPressed: NSEvent.pressedMouseButtons & 1 != 0)
        pointerSession = session
        if session.isFinished {
            stopPhysicalTracking()
        }
        for action in actions {
            if CommandLine.arguments.contains("--input-diagnostics") {
                if case .drag = action {} else { NSLog("INPUT physical %@", String(describing: action)) }
            }
            switch action {
            case let .begin(origin, pointer): onBegin?(origin, pointer, timestamp)
            case let .drag(pointer): onDrag?(pointer, timestamp)
            case let .end(pointer): onEnd?(pointer, timestamp)
            case .click: onClick?()
            }
        }
    }

    private func stopPhysicalTracking() {
        pointerTicker?.invalidate()
        pointerTicker = nil
        pointerSession = nil
        isTracking = false
    }

    @objc private func handleSecondaryClick(_ recognizer: NSClickGestureRecognizer) {
        guard recognizer.state == .ended else { return }
        stopPhysicalTracking()
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
