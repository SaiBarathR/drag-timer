import AppKit

protocol DragOverlayPresenting: AnyObject {
    func show()
    func hide()
    func render(
        originScreen: CGPoint,
        cursorScreen: CGPoint,
        duration: TimeInterval,
        isSnapped: Bool,
        updateText: Bool
    )
}

protocol DragFrameDriving: AnyObject {
    var onFrame: ((TimeInterval, TimeInterval) -> Void)? { get set }
    var isRunning: Bool { get }
    func start(on screen: NSScreen?)
    func retarget(to screen: NSScreen?)
    func stop()
}

extension DragOverlayWindowController: DragOverlayPresenting {}
extension DisplayLinkDriver: DragFrameDriving {}

/// Everything the gesture touches outside its own state machine, so tests can
/// drive a drag without windows, a display link, a trackpad or a modal panel.
struct DragGestureEnvironment {
    var makeOverlay: (DragRulerLayout, CountdownScale, Bool) -> DragOverlayPresenting
    var makeFrameDriver: () -> DragFrameDriving
    var performHaptic: (NSHapticFeedbackManager.FeedbackPattern) -> Void
    var requestLabel: (Date, String) -> TimerLabelPromptOutcome

    static let live = DragGestureEnvironment(
        makeOverlay: { rulerLayout, countdownScale, highContrast in
            DragOverlayWindowController(
                rulerLayout: rulerLayout,
                countdownScale: countdownScale,
                highContrast: highContrast
            )
        },
        makeFrameDriver: { DisplayLinkDriver() },
        // Resolve the performer for every tick so AppKit can target whichever
        // Force Touch trackpad is currently driving the gesture.
        performHaptic: { NSHapticFeedbackManager.defaultPerformer.perform($0, performanceTime: .now) },
        requestLabel: { TimerLabelPrompt.requestLabel(targetFireDate: $0, currentLabel: $1) }
    )
}

final class DragGestureController {
    private static let activationDistance = StatusItemPointerSession.activationDistance

    private enum GestureState {
        case idle
        case tracking
        case settling
        case prompting
    }

    private let timerEngine: TimerEngine
    private let settings: AppSettings
    private let environment: DragGestureEnvironment
    private var onPopoverRequested: () -> Void

    private var state: GestureState = .idle
    private var physics: DragPhysics?
    private var overlay: DragOverlayPresenting?
    private var displayLink: DragFrameDriving?
    private var origin: CGPoint?
    private var cursor: CGPoint?
    private var didMoveEnough = false
    private var pendingDuration: TimeInterval?
    private var lastLabelTimestamp: TimeInterval = 0
    private var lastDetentIndex: Int?

    init(
        timerEngine: TimerEngine,
        settings: AppSettings,
        environment: DragGestureEnvironment = .live,
        onPopoverRequested: @escaping () -> Void
    ) {
        self.timerEngine = timerEngine
        self.settings = settings
        self.environment = environment
        self.onPopoverRequested = onPopoverRequested
    }

    func setPopoverRequestHandler(_ handler: @escaping () -> Void) {
        onPopoverRequested = handler
    }

    func begin(origin: CGPoint, pointer: CGPoint, timestamp: TimeInterval) {
        guard state == .idle else { return }

        var physicsSettings = settings.physics
        physicsSettings.reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion

        var newPhysics = DragPhysics(settings: physicsSettings)
        newPhysics.begin(at: timestamp)

        self.origin = origin
        cursor = pointer
        physics = newPhysics
        state = .tracking
        didMoveEnough = false
        pendingDuration = nil
        lastLabelTimestamp = 0
        lastDetentIndex = nil

        let overlay = environment.makeOverlay(
            DragRulerLayout(
                settings: physicsSettings,
                activationDistance: Self.activationDistance
            ),
            settings.countdownScale,
            TimerAppearancePolicy.highContrast(settings: settings)
        )
        self.overlay = overlay
        overlay.show()
        // Render one frame immediately. The display link owns the steady-state
        // cadence, but this makes the press affordance visible even before the
        // first v-sync callback arrives.
        overlay.render(
            originScreen: origin,
            cursorScreen: pointer,
            duration: newPhysics.displayDuration,
            isSnapped: newPhysics.isSnapped,
            updateText: true
        )

        let displayLink = environment.makeFrameDriver()
        displayLink.onFrame = { [weak self] elapsed, timestamp in
            self?.renderFrame(elapsed: elapsed, timestamp: timestamp)
        }
        self.displayLink = displayLink
        displayLink.start(on: screen(containing: origin))
    }

    func drag(pointer: CGPoint, timestamp: TimeInterval) {
        guard state == .tracking, let origin, var physics else { return }

        let dx = pointer.x - origin.x
        let dy = pointer.y - origin.y
        let distance = hypot(dx, dy)
        let didActivate = !didMoveEnough && distance >= Self.activationDistance
        didMoveEnough = didMoveEnough || didActivate
        let enteredSnap = physics.updateDrag(
            distance: Self.mappedDistance(for: distance),
            timestamp: timestamp
        )

        self.physics = physics
        cursor = pointer
        displayLink?.retarget(to: screen(containing: pointer))

        updateHaptics(didActivate: didActivate, enteredSnap: enteredSnap)
    }

    func end(pointer: CGPoint, timestamp: TimeInterval) {
        guard state == .tracking, let origin, var physics else { return }
        cursor = pointer

        let dx = pointer.x - origin.x
        let dy = pointer.y - origin.y
        let finalDistance = hypot(dx, dy)
        let didActivate = !didMoveEnough && finalDistance >= Self.activationDistance
        let enteredSnap = physics.updateReleaseDistance(Self.mappedDistance(for: finalDistance))
        self.physics = physics
        didMoveEnough = didMoveEnough || didActivate

        updateHaptics(didActivate: didActivate, enteredSnap: enteredSnap)
        lastLabelTimestamp = timestamp
        overlay?.render(
            originScreen: origin,
            cursorScreen: pointer,
            duration: physics.displayDuration,
            isSnapped: physics.isSnapped,
            updateText: true
        )

        guard didMoveEnough else {
            finish()
            onPopoverRequested()
            return
        }

        let result = physics.release(at: timestamp)
        self.physics = physics
        pendingDuration = result.duration
        state = .settling

        if result.didSnap && settings.hapticsEnabled {
            performHaptic(.alignment)
        }

        // The display link normally drives the settle to completion, but if it
        // never started (no usable screen) the released duration must not be
        // lost — commit immediately instead.
        if physics.phase == .finished || displayLink?.isRunning != true {
            commitAndFinish()
        }
    }

    func cancel() {
        // Cancelling only aborts an in-flight drag. Once the user has released
        // (settling), the timer is already decided; a right-click arriving
        // during the short settle animation must still create it.
        if state == .settling {
            commitAndFinish()
        } else if state == .tracking {
            finish()
        }
    }

    private func renderFrame(elapsed: TimeInterval, timestamp: TimeInterval) {
        guard var physics, let origin, let cursor else { return }

        let didFinish = state == .settling && physics.step(by: elapsed)
        self.physics = physics

        let updateText = timestamp - lastLabelTimestamp >= (1.0 / 30.0)
        if updateText {
            lastLabelTimestamp = timestamp
        }

        overlay?.render(
            originScreen: origin,
            cursorScreen: cursor,
            duration: physics.displayDuration,
            isSnapped: physics.isSnapped,
            updateText: updateText
        )

        if didFinish {
            commitAndFinish()
        }
    }

    private func commitAndFinish() {
        guard let duration = pendingDuration else {
            finish()
            return
        }
        // The timer starts at release with the default name, so time spent in
        // the prompt never shortens it; the prompt only renames or discards.
        let shouldAskForLabel = settings.askForLabelAfterDrag
        finish(as: shouldAskForLabel ? .prompting : .idle)
        let timer = timerEngine.createTimer(duration: duration, options: settings.defaultOptions())
        guard shouldAskForLabel else { return }

        // Finish dispatching the release gesture before presenting a key window
        // so keyboard focus and the Escape shortcut work reliably.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let outcome = self.environment.requestLabel(timer.fireDate, timer.label)
            self.state = .idle
            switch outcome {
            case let .renamed(label): self.timerEngine.rename(id: timer.id, to: label)
            case .keptName: break
            case .discarded: self.timerEngine.discard(id: timer.id)
            }
        }
    }

    private func finish(as finalState: GestureState = .idle) {
        displayLink?.stop()
        displayLink = nil
        overlay?.hide()
        overlay = nil
        physics = nil
        origin = nil
        cursor = nil
        pendingDuration = nil
        didMoveEnough = false
        state = finalState
    }

    /// Mapping starts where the drag activates, not at the raw press origin,
    /// so a barely-activated drag reads exactly the minimum duration instead
    /// of already sitting a rung or two into the ladder.
    private static func mappedDistance(for distance: CGFloat) -> Double {
        max(0, distance - activationDistance)
    }

    /// One activation buzz, a distinct double tick when a snap zone engages,
    /// and a firm tick each time the drag crosses a detent rung. The detents
    /// are what make the drag feel mechanical on a Force Touch trackpad —
    /// snap-zone crossings alone are seconds apart and read as silence.
    private func updateHaptics(didActivate: Bool, enteredSnap: Bool) {
        guard settings.hapticsEnabled, let physics else { return }
        // The detent index comes from the raw geometric rung position, before
        // snap or rounding, so tick timing matches hand movement exactly: one
        // tick per rung boundary crossed, in either direction. The boundary
        // sits at the rounding midpoint, which is also where the quantized
        // readout changes.
        let detent = Int(physics.rawRungPosition.rounded())

        if didActivate {
            // Performed while the finger is still down. macOS may suppress
            // haptics after mouse-up when the trackpad is no longer touched.
            performHaptic(.generic)
            lastDetentIndex = detent
            return
        }

        guard didMoveEnough else { return }

        if enteredSnap && settings.snapDuringDrag {
            performSnapCaptureHaptic()
            lastDetentIndex = detent
            return
        }

        // At most one tick per drag event: a fast scrub that jumps several
        // rungs between events still marks the crossing with a single firm
        // tick instead of machine-gunning — and no time-based throttle ever
        // silently drops a boundary crossing.
        if let lastDetentIndex, detent != lastDetentIndex {
            performHaptic(.alignment)
        }
        lastDetentIndex = detent
    }

    /// Snap capture reads as a quick double tick so it stays distinguishable
    /// from the single firm tick used for ordinary rung crossings.
    private func performSnapCaptureHaptic() {
        performHaptic(.alignment)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) { [weak self] in
            guard let self, self.state == .tracking || self.state == .settling else { return }
            self.performHaptic(.alignment)
        }
    }

    private func performHaptic(_ pattern: NSHapticFeedbackManager.FeedbackPattern) {
        environment.performHaptic(pattern)
    }

    private func screen(containing point: CGPoint) -> NSScreen? {
        NSScreen.screens.first(where: { $0.frame.contains(point) }) ?? NSScreen.main
    }
}
