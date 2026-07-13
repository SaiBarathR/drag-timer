import AppKit

final class DragGestureController {
    private static let activationDistance: CGFloat = 8

    private enum GestureState {
        case idle
        case tracking
        case settling
        case prompting
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
    private var lastDetentIndex: Int?
    private var lastHapticTimestamp: TimeInterval = 0

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
        lastDetentIndex = nil
        lastHapticTimestamp = 0

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
            isSnapped: newPhysics.isSnapped,
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
        let didActivate = !didMoveEnough && distance >= Self.activationDistance
        didMoveEnough = didMoveEnough || didActivate
        let enteredSnap = physics.updateDrag(distance: distance, timestamp: timestamp)

        self.physics = physics
        cursor = pointer
        displayLink?.retarget(to: screen(containing: pointer))

        updateHaptics(didActivate: didActivate, enteredSnap: enteredSnap, timestamp: timestamp)
    }

    func end(pointer: CGPoint, timestamp: TimeInterval) {
        guard state == .tracking else { return }
        cursor = pointer

        guard didMoveEnough, var physics else {
            finish()
            onPopoverRequested()
            return
        }

        let result = physics.release(at: timestamp)
        self.physics = physics
        pendingDuration = result.duration
        state = .settling

        if result.shouldHaptic && settings.hapticsEnabled {
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
        let shouldAskForLabel = settings.askForLabelAfterDrag
        let targetFireDate = Date().addingTimeInterval(duration.rounded())

        guard shouldAskForLabel else {
            finish()
            timerEngine.createTimer(duration: duration, options: settings.defaultOptions())
            return
        }

        finish(as: .prompting)

        // Leave the status item's nested mouse-tracking loop before presenting
        // a key window. This keeps keyboard focus and the Cancel shortcut
        // reliable after mouse-up.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let label = TimerLabelPrompt.requestLabel(
                targetFireDate: targetFireDate
            )
            self.state = .idle
            guard let label else { return }
            self.timerEngine.createTimer(
                fireDate: targetFireDate,
                options: self.settings.defaultOptions(label: label)
            )
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

    /// One activation buzz, a firm tick when a snap zone engages, and a light
    /// tick each time the scrubbed duration crosses a detent rung. The detents
    /// are what make the drag feel mechanical on a Force Touch trackpad —
    /// snap-zone crossings alone are seconds apart and read as silence.
    private func updateHaptics(didActivate: Bool, enteredSnap: Bool, timestamp: TimeInterval) {
        guard settings.hapticsEnabled, let physics else { return }
        let detent = Self.detentIndex(for: physics.displayDuration)

        if didActivate {
            // Performed while the finger is still down. macOS may suppress
            // haptics after mouse-up when the trackpad is no longer touched.
            performHaptic(.generic)
            lastDetentIndex = detent
            lastHapticTimestamp = timestamp
            return
        }

        guard didMoveEnough else { return }

        if enteredSnap && settings.snapDuringDrag {
            performHaptic(.alignment)
            lastDetentIndex = detent
            lastHapticTimestamp = timestamp
            return
        }

        if let lastDetentIndex, detent != lastDetentIndex, timestamp - lastHapticTimestamp >= 0.05 {
            performHaptic(.levelChange)
            lastHapticTimestamp = timestamp
        }
        lastDetentIndex = detent
    }

    /// Maps a duration onto a monotonic ladder of "nice" steps — every minute
    /// to 15 minutes, every 5 minutes to an
    /// hour, every 15 minutes to 4 hours, then every 30 minutes. Crossing a
    /// rung means the user scrubbed past a value worth feeling.
    private static func detentIndex(for duration: TimeInterval) -> Int {
        let bands: [(upperBound: TimeInterval, step: TimeInterval)] = [
            (15 * 60, 60),
            (60 * 60, 5 * 60),
            (4 * 60 * 60, 15 * 60),
            (.greatestFiniteMagnitude, 30 * 60)
        ]

        var index = 0
        var lowerBound: TimeInterval = 0
        for band in bands {
            let cappedUpper = min(duration, band.upperBound)
            if cappedUpper > lowerBound {
                index += Int((cappedUpper - lowerBound) / band.step)
            }
            if duration <= band.upperBound { break }
            lowerBound = band.upperBound
        }
        return index
    }

    private func performHaptic(_ pattern: NSHapticFeedbackManager.FeedbackPattern) {
        // Resolve the performer for every tick so AppKit can target whichever
        // Force Touch trackpad is currently driving the gesture.
        NSHapticFeedbackManager.defaultPerformer.perform(pattern, performanceTime: .now)
    }

    private func screen(containing point: CGPoint) -> NSScreen? {
        NSScreen.screens.first(where: { $0.frame.contains(point) }) ?? NSScreen.main
    }
}
