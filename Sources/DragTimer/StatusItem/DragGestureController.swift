import AppKit

final class DragGestureController {
    private enum GestureState {
        case idle
        case tracking
        case settling
    }

    private let timerEngine: TimerEngine
    private let settings: AppSettings
    private var onPopoverRequested: () -> Void

    private var state: GestureState = .idle
    private var physics: DragPhysics?
    private var overlay: DragOverlayWindowController?
    private var displayLink: DisplayLinkDriver?
    private var origin: CGPoint?
    private var cursor: CGPoint?
    private var didMoveEnough = false
    private var pendingDuration: TimeInterval?
    private var lastLabelTimestamp: TimeInterval = 0

    init(timerEngine: TimerEngine, settings: AppSettings, onPopoverRequested: @escaping () -> Void) {
        self.timerEngine = timerEngine
        self.settings = settings
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

        let overlay = DragOverlayWindowController()
        self.overlay = overlay
        overlay.show()
        // Render one frame immediately. The display link owns the steady-state
        // cadence, but this makes the press affordance visible even before the
        // first v-sync callback arrives.
        overlay.render(
            originScreen: origin,
            cursorScreen: pointer,
            duration: newPhysics.displayDuration,
            updateText: true
        )

        let displayLink = DisplayLinkDriver()
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
        didMoveEnough = didMoveEnough || distance >= 8
        let enteredSnap = physics.updateDrag(distance: distance, timestamp: timestamp)

        self.physics = physics
        cursor = pointer
        displayLink?.retarget(to: screen(containing: pointer))

        if enteredSnap && settings.hapticsEnabled && settings.snapDuringDrag {
            performHaptic()
        }
    }

    func end(pointer: CGPoint, timestamp: TimeInterval) {
        guard state == .tracking else { return }
        cursor = pointer

        // Dragged events may be coalesced or stay inside the status item's
        // nested tracking loop. The final screen point is authoritative, so
        // derive the distance here as a guaranteed last sample.
        if let origin, var physics {
            let dx = pointer.x - origin.x
            let dy = pointer.y - origin.y
            let finalDistance = hypot(dx, dy)
            if finalDistance > physics.distance {
                let enteredSnap = physics.updateDrag(distance: finalDistance, timestamp: timestamp)
                self.physics = physics
                didMoveEnough = didMoveEnough || finalDistance >= 8
                if enteredSnap && settings.hapticsEnabled && settings.snapDuringDrag {
                    performHaptic()
                }
            }
        }

        guard didMoveEnough, var physics else {
            finish()
            onPopoverRequested()
            return
        }

        let result = physics.release()
        self.physics = physics
        pendingDuration = result.duration
        state = .settling

        if result.shouldHaptic && settings.hapticsEnabled {
            performHaptic()
        }

        if physics.phase == .finished {
            commitAndFinish()
        }
    }

    func cancel() {
        finish()
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
            updateText: updateText
        )

        if didFinish {
            commitAndFinish()
        }
    }

    private func commitAndFinish() {
        if let pendingDuration {
            timerEngine.createTimer(duration: pendingDuration, options: settings.defaultOptions())
        }
        finish()
    }

    private func finish() {
        displayLink?.stop()
        displayLink = nil
        overlay?.hide()
        overlay = nil
        physics = nil
        origin = nil
        cursor = nil
        pendingDuration = nil
        didMoveEnough = false
        state = .idle
    }

    private func performHaptic() {
        // `levelChange` is the more noticeable pattern for crossing a marked
        // interval, and maps directly to the snap points in the drag curve.
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
    }

    private func screen(containing point: CGPoint) -> NSScreen? {
        NSScreen.screens.first(where: { $0.frame.contains(point) }) ?? NSScreen.main
    }
}
