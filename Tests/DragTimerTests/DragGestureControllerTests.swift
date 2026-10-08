import AppKit
import XCTest
@testable import DragTimer

final class DragGestureControllerTests: XCTestCase {
    private let origin = CGPoint(x: 500, y: 900)

    func testReleaseInsideActivationDistanceOpensThePopoverInsteadOfStartingATimer() {
        let fixture = makeFixture()
        defer { fixture.cleanup() }

        fixture.controller.begin(origin: origin, pointer: origin, timestamp: 0)
        fixture.controller.drag(pointer: pointer(pulled: 7), timestamp: 0.1)
        fixture.controller.end(pointer: pointer(pulled: 7), timestamp: 0.2)

        XCTAssertEqual(fixture.popoverRequests(), 1)
        XCTAssertTrue(fixture.engine.timers.isEmpty)
        XCTAssertEqual(fixture.spy.overlay?.events, ["show", "hide"])
        XCTAssertEqual(fixture.spy.driver?.isRunning, false)
        XCTAssertEqual(fixture.spy.haptics, [])
    }

    func testReleaseAtActivationDistanceStartsTheMinimumTimer() {
        let fixture = makeFixture()
        defer { fixture.cleanup() }

        drag(fixture, pulled: [8])
        fixture.spy.driver?.fireFrame()

        XCTAssertEqual(fixture.popoverRequests(), 0)
        XCTAssertEqual(fixture.engine.timers.map(\.resetDuration), [60])
    }

    func testReleasedDurationMatchesTheLastRenderedReadout() {
        let fixture = makeFixture()
        defer { fixture.cleanup() }

        // 8 pt of activation, then four 20 pt rungs: 1m → 5m.
        drag(fixture, pulled: [20, 50, 88])
        fixture.spy.driver?.fireFrame()

        XCTAssertEqual(fixture.spy.overlay?.lastDuration, 300)
        XCTAssertEqual(fixture.engine.timers.map(\.resetDuration), [300])
        XCTAssertEqual(fixture.engine.timers.first?.label, "Timer")
        XCTAssertEqual(fixture.spy.overlay?.events.last, "hide")
        XCTAssertEqual(fixture.spy.driver?.isRunning, false)
    }

    func testReleaseCommitsImmediatelyWhenNoFrameDriverIsRunning() {
        let fixture = makeFixture(driverStarts: false)
        defer { fixture.cleanup() }

        drag(fixture, pulled: [88])

        XCTAssertEqual(fixture.engine.timers.map(\.resetDuration), [300])
    }

    func testCancelWhileTrackingCreatesNothingAndTearsDownTheOverlay() {
        let fixture = makeFixture()
        defer { fixture.cleanup() }

        fixture.controller.begin(origin: origin, pointer: origin, timestamp: 0)
        fixture.controller.drag(pointer: pointer(pulled: 88), timestamp: 0.1)
        fixture.controller.cancel()

        XCTAssertTrue(fixture.engine.timers.isEmpty)
        XCTAssertEqual(fixture.popoverRequests(), 0)
        XCTAssertEqual(fixture.spy.overlay?.events.last, "hide")
    }

    func testCancelAfterReleaseStillCreatesTheTimer() {
        let fixture = makeFixture()
        defer { fixture.cleanup() }

        drag(fixture, pulled: [88])
        fixture.controller.cancel()

        XCTAssertEqual(fixture.engine.timers.map(\.resetDuration), [300])
    }

    func testReleasingBackOnTheIconStartsNothing() {
        let fixture = makeFixture()
        defer { fixture.cleanup() }

        fixture.controller.begin(origin: origin, pointer: origin, timestamp: 0)
        fixture.controller.drag(pointer: pointer(pulled: 88), timestamp: 0.1)
        fixture.spy.haptics = []
        fixture.controller.drag(pointer: pointer(pulled: 3), timestamp: 0.2)
        fixture.spy.driver?.fireFrame()
        XCTAssertEqual(fixture.spy.overlay?.lastIsCancelling, true)
        XCTAssertEqual(fixture.spy.overlay?.lastIsSnapped, false)
        XCTAssertEqual(fixture.spy.haptics.last, .generic)

        fixture.controller.end(pointer: pointer(pulled: 3), timestamp: 2)
        fixture.spy.driver?.fireFrame()

        XCTAssertTrue(fixture.engine.timers.isEmpty)
        XCTAssertEqual(fixture.popoverRequests(), 0)
        XCTAssertEqual(fixture.spy.overlay?.events, ["show", "hide"])
        XCTAssertEqual(fixture.spy.driver?.isRunning, false)

        // The next drag is an ordinary one.
        drag(fixture, pulled: [88])
        fixture.spy.driver?.fireFrame()
        XCTAssertEqual(fixture.engine.timers.map(\.resetDuration), [300])
    }

    func testLeavingTheIconAgainTurnsCancelBackIntoADuration() {
        let fixture = makeFixture()
        defer { fixture.cleanup() }

        fixture.controller.begin(origin: origin, pointer: origin, timestamp: 0)
        for (index, pulled) in [88.0, 3, 48].enumerated() {
            fixture.controller.drag(pointer: pointer(pulled: pulled), timestamp: Double(index + 1) * 0.1)
        }
        fixture.spy.driver?.fireFrame()
        XCTAssertEqual(fixture.spy.overlay?.lastIsCancelling, false)
        fixture.controller.end(pointer: pointer(pulled: 48), timestamp: 2)
        fixture.spy.driver?.fireFrame()

        XCTAssertEqual(fixture.engine.timers.map(\.resetDuration), [180])
    }

    func testTheCancelZoneIsEnteredInsideTheActivationDistanceAndLeftAtIt() {
        let entering = makeFixture()
        defer { entering.cleanup() }
        // 7 pt is inside the activation distance but short of the icon:
        // still the one-minute rung on the way in.
        drag(entering, pulled: [88, 7])
        entering.spy.driver?.fireFrame()
        XCTAssertEqual(entering.engine.timers.map(\.resetDuration), [60])

        let leaving = makeFixture()
        defer { leaving.cleanup() }
        // Once on the icon, 7 pt is not yet off it.
        drag(leaving, pulled: [88, 3, 7])
        leaving.spy.driver?.fireFrame()
        XCTAssertTrue(leaving.engine.timers.isEmpty)
        XCTAssertEqual(leaving.popoverRequests(), 0)
    }

    func testEscapeAbortsADragThatIsStillHeld() {
        let fixture = makeFixture()
        defer { fixture.cleanup() }

        fixture.controller.begin(origin: origin, pointer: origin, timestamp: 0)
        XCTAssertEqual(fixture.spy.cancelKey?.isRegistered, true)
        fixture.controller.drag(pointer: pointer(pulled: 88), timestamp: 0.1)
        fixture.spy.cancelKey?.press()
        XCTAssertEqual(fixture.spy.overlay?.events.last, "hide")
        XCTAssertEqual(fixture.spy.cancelKey?.isRegistered, false)

        // The button is still down; letting go now belongs to no drag.
        fixture.controller.end(pointer: pointer(pulled: 88), timestamp: 2)
        fixture.spy.driver?.fireFrame()

        XCTAssertTrue(fixture.engine.timers.isEmpty)
        XCTAssertEqual(fixture.popoverRequests(), 0)
    }

    func testEscapePressedJustBeforeReleaseStillCancels() {
        let fixture = makeFixture()
        defer { fixture.cleanup() }

        fixture.controller.begin(origin: origin, pointer: origin, timestamp: 0)
        fixture.controller.drag(pointer: pointer(pulled: 88), timestamp: 0.1)
        fixture.spy.cancelKey?.pressWithoutDelivering()
        fixture.controller.end(pointer: pointer(pulled: 88), timestamp: 0.2)
        fixture.spy.driver?.fireFrame()
        // The callback arrives after the release and finds nothing to do.
        fixture.spy.cancelKey?.onPress?()

        XCTAssertTrue(fixture.engine.timers.isEmpty)
        XCTAssertEqual(fixture.popoverRequests(), 0)
        XCTAssertEqual(fixture.spy.overlay?.events.last, "hide")
        XCTAssertEqual(fixture.spy.cancelKey?.isRegistered, false)
    }

    func testReleasingOffTheIconClearsCancelForTheSettleFrames() {
        let fixture = makeFixture()
        defer { fixture.cleanup() }
        fixture.settings.applyPreset(.throwable)

        fixture.controller.begin(origin: origin, pointer: origin, timestamp: 0)
        fixture.controller.drag(pointer: pointer(pulled: 88), timestamp: 0.1)
        // The last sample before the button comes up is on the icon; the
        // release itself is reported well off it.
        fixture.controller.drag(pointer: pointer(pulled: 3), timestamp: 0.2)
        fixture.controller.end(pointer: pointer(pulled: 88), timestamp: 2)
        fixture.spy.driver?.fireFrame()

        XCTAssertEqual(fixture.spy.overlay?.lastIsCancelling, false)
        XCTAssertEqual(fixture.engine.timers.map(\.resetDuration), [300])
    }

    func testEscapeIsGivenBackAtReleaseAndCannotUndoATimer() {
        let fixture = makeFixture(askForLabel: true)
        defer { fixture.cleanup() }

        fixture.controller.begin(origin: origin, pointer: origin, timestamp: 0)
        fixture.controller.drag(pointer: pointer(pulled: 88), timestamp: 0.1)
        fixture.controller.end(pointer: pointer(pulled: 88), timestamp: 2)
        // Released: the key is back with the front application, and with
        // the name prompt that is about to open.
        XCTAssertEqual(fixture.spy.cancelKey?.isRegistered, false)
        fixture.spy.cancelKey?.onPress?()
        fixture.spy.driver?.fireFrame()
        wait(0.05)

        XCTAssertEqual(fixture.engine.timers.map(\.resetDuration), [300])
        XCTAssertEqual(fixture.spy.promptRequests.count, 1)
    }

    func testHapticsMarkActivationEachRungAndSnapCapture() {
        let fixture = makeFixture()
        defer { fixture.cleanup() }

        fixture.controller.begin(origin: origin, pointer: origin, timestamp: 0)
        // Activation, then one sample in the middle of each rung up to 4m.
        for (index, pulled) in [8.0, 28, 48, 68].enumerated() {
            fixture.controller.drag(pointer: pointer(pulled: pulled), timestamp: Double(index) * 0.05)
        }
        XCTAssertEqual(fixture.spy.haptics, [.generic, .alignment, .alignment, .alignment])

        // Entering the 5m zone is a double tick, the second 60 ms later.
        fixture.spy.haptics = []
        fixture.controller.drag(pointer: pointer(pulled: 88), timestamp: 0.3)
        XCTAssertEqual(fixture.spy.haptics, [.alignment])
        wait(0.15)
        XCTAssertEqual(fixture.spy.haptics, [.alignment, .alignment])

        // Releasing on a snap confirms it with one more tick.
        fixture.spy.haptics = []
        fixture.controller.end(pointer: pointer(pulled: 88), timestamp: 1)
        XCTAssertEqual(fixture.spy.haptics, [.alignment])
    }

    func testFastScrubAcrossSeveralRungsTicksOncePerEvent() {
        let fixture = makeFixture()
        defer { fixture.cleanup() }

        fixture.controller.begin(origin: origin, pointer: origin, timestamp: 0)
        fixture.controller.drag(pointer: pointer(pulled: 8), timestamp: 0)
        fixture.controller.drag(pointer: pointer(pulled: 148), timestamp: 0.02)
        fixture.controller.drag(pointer: pointer(pulled: 149), timestamp: 0.04)

        XCTAssertEqual(fixture.spy.haptics, [.generic, .alignment])
    }

    func testNoHapticsWhenDisabled() {
        let fixture = makeFixture()
        defer { fixture.cleanup() }
        fixture.settings.hapticsEnabled = false

        drag(fixture, pulled: [8, 28, 48, 68, 88])
        wait(0.15)

        XCTAssertEqual(fixture.spy.haptics, [])
    }

    func testPromptRenamesTheAlreadyRunningTimerAndKeepsItsPlannedDuration() {
        let fixture = makeFixture(askForLabel: true)
        defer { fixture.cleanup() }
        fixture.spy.promptOutcome = .renamed("Tea")

        drag(fixture, pulled: [88])
        fixture.spy.driver?.fireFrame()
        XCTAssertEqual(fixture.engine.timers.map(\.label), ["Timer"])

        // A second drag is ignored while the prompt is pending.
        fixture.controller.begin(origin: origin, pointer: origin, timestamp: 2)
        wait(0.05)

        XCTAssertEqual(fixture.spy.promptRequests.map(\.label), ["Timer"])
        XCTAssertEqual(fixture.spy.promptRequests.first?.fireDate, fixture.engine.timers.first?.fireDate)
        XCTAssertEqual(fixture.engine.timers.map(\.label), ["Tea"])
        XCTAssertEqual(fixture.engine.timers.map(\.resetDuration), [300])
        XCTAssertEqual(fixture.spy.overlays.count, 1)
    }

    /// The engine fires timers from the main dispatch queue. A prompt opened
    /// from inside a main-queue block would hold that queue for as long as it
    /// stayed open, and no timer could ring until it was dismissed.
    func testOpenPromptLeavesTheMainQueueFreeForTimersToFire() {
        let fixture = makeFixture(askForLabel: true)
        defer { fixture.cleanup() }
        fixture.spy.probesMainQueueDuringPrompt = true

        drag(fixture, pulled: [88])
        fixture.spy.driver?.fireFrame()
        wait(0.5)

        XCTAssertEqual(fixture.spy.promptRequests.count, 1)
        XCTAssertEqual(fixture.spy.mainQueueDrainedDuringPrompt, true)
    }

    /// The same guarantee with the production modal prompt and the engine's
    /// real scheduler: a timer due while the prompt is open rings on time.
    @MainActor
    func testATimerRingsWhileTheRealNamePromptIsOpen() {
        _ = NSApplication.shared
        let fixture = makeFixture(askForLabel: true)
        defer { fixture.cleanup() }
        fixture.spy.usesRealPrompt = true
        let due = fixture.engine.createTimer(duration: 1, options: TimerOptions(label: "Due"))
        var rangWhilePromptWasOpen: Bool?
        // A run-loop timer keeps firing inside the modal session.
        let check = Timer(timeInterval: 1.6, repeats: false) { _ in
            guard NSApp.modalWindow != nil else { return }
            rangWhilePromptWasOpen = fixture.engine.pendingExpiries.contains { $0.timer.id == due.id }
            NSApp.abortModal()
        }
        RunLoop.main.add(check, forMode: .common)
        defer { check.invalidate() }

        drag(fixture, pulled: [88])
        fixture.spy.driver?.fireFrame()
        wait(2.2)

        XCTAssertEqual(rangWhilePromptWasOpen, true)
    }

    func testPromptDiscardRemovesTheTimerWithoutHistory() {
        let fixture = makeFixture(askForLabel: true)
        defer { fixture.cleanup() }
        fixture.spy.promptOutcome = .discarded

        drag(fixture, pulled: [88])
        fixture.spy.driver?.fireFrame()
        wait(0.05)

        XCTAssertTrue(fixture.engine.timers.isEmpty)
        XCTAssertTrue(fixture.engine.historyEntries.isEmpty)
    }

    func testDismissedPromptKeepsTheTimerAndAllowsTheNextDrag() {
        let fixture = makeFixture(askForLabel: true)
        defer { fixture.cleanup() }
        fixture.spy.promptOutcome = .keptName

        drag(fixture, pulled: [88])
        fixture.spy.driver?.fireFrame()
        wait(0.05)
        drag(fixture, pulled: [28])
        fixture.spy.driver?.fireFrame()
        wait(0.05)

        XCTAssertEqual(fixture.engine.timers.map(\.resetDuration).sorted(), [120, 300])
    }

    // MARK: - Helpers

    private func pointer(pulled distance: CGFloat) -> CGPoint {
        CGPoint(x: origin.x, y: origin.y - distance)
    }

    private func drag(_ fixture: Fixture, pulled distances: [CGFloat]) {
        fixture.controller.begin(origin: origin, pointer: origin, timestamp: 0)
        for (index, distance) in distances.enumerated() {
            fixture.controller.drag(pointer: pointer(pulled: distance), timestamp: Double(index + 1) * 0.05)
        }
        // Released a second later, so no preset carries momentum.
        fixture.controller.end(pointer: pointer(pulled: distances.last ?? 0), timestamp: 2)
    }

    /// Always at least one real pass of the run loop. On a stalled CI machine
    /// the deadline can have gone by before `run(until:)` starts, and it then
    /// returns without firing the timer the test is waiting for.
    private func wait(_ interval: TimeInterval) {
        let deadline = Date().addingTimeInterval(interval)
        repeat {
            RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.02))
        } while Date() < deadline
    }

    private struct Fixture {
        let controller: DragGestureController
        let engine: TimerEngine
        let settings: AppSettings
        let spy: Spy
        let popoverRequests: () -> Int
        let cleanup: () -> Void
    }

    private func makeFixture(askForLabel: Bool = false, driverStarts: Bool = true) -> Fixture {
        let suite = "DragGestureControllerTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(suite, isDirectory: true)
        let settings = AppSettings(defaults: defaults)
        settings.askForLabelAfterDrag = askForLabel
        let engine = TimerEngine(
            persistence: TimerPersistence(fileURL: directory.appendingPathComponent("timers.json")),
            notificationService: NotificationService(center: nil),
            audioPlayer: SilentAudio()
        )
        let spy = Spy(driverStarts: driverStarts)
        var popoverRequests = 0
        let controller = DragGestureController(
            timerEngine: engine,
            settings: settings,
            environment: spy.environment,
            onPopoverRequested: { popoverRequests += 1 }
        )
        return Fixture(
            controller: controller,
            engine: engine,
            settings: settings,
            spy: spy,
            popoverRequests: { popoverRequests },
            cleanup: {
                defaults.removePersistentDomain(forName: suite)
                try? FileManager.default.removeItem(at: directory)
            }
        )
    }

    private final class Spy {
        var overlays: [OverlaySpy] = []
        var drivers: [DriverSpy] = []
        var cancelKeys: [CancelKeySpy] = []
        var haptics: [NSHapticFeedbackManager.FeedbackPattern] = []
        var promptRequests: [(fireDate: Date, label: String)] = []
        var promptOutcome: TimerLabelPromptOutcome = .keptName
        var probesMainQueueDuringPrompt = false
        var usesRealPrompt = false
        var mainQueueDrainedDuringPrompt: Bool?
        private let driverStarts: Bool

        var overlay: OverlaySpy? { overlays.last }
        var cancelKey: CancelKeySpy? { cancelKeys.last }
        var driver: DriverSpy? { drivers.last }

        init(driverStarts: Bool) { self.driverStarts = driverStarts }

        var environment: DragGestureEnvironment {
            DragGestureEnvironment(
                makeOverlay: { [unowned self] _, _, _ in
                    let overlay = OverlaySpy()
                    overlays.append(overlay)
                    return overlay
                },
                makeFrameDriver: { [unowned self] in
                    let driver = DriverSpy(starts: driverStarts)
                    drivers.append(driver)
                    return driver
                },
                performHaptic: { [unowned self] in haptics.append($0) },
                requestLabel: { [unowned self] fireDate, label in
                    promptRequests.append((fireDate, label))
                    if usesRealPrompt {
                        return TimerLabelPrompt.requestLabel(targetFireDate: fireDate, currentLabel: label)
                    }
                    if probesMainQueueDuringPrompt {
                        // Stand in for the modal prompt: one nested run-loop
                        // pass, which returns as soon as the main queue is
                        // serviced and gives up after 50 ms if it cannot be.
                        var drained = false
                        DispatchQueue.main.async { drained = true }
                        RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.05))
                        mainQueueDrainedDuringPrompt = drained
                    }
                    return promptOutcome
                },
                makeCancelKey: { [unowned self] in
                    let key = CancelKeySpy()
                    cancelKeys.append(key)
                    return key
                }
            )
        }
    }

    private final class OverlaySpy: DragOverlayPresenting {
        var events: [String] = []
        var lastDuration: TimeInterval?
        var lastIsCancelling: Bool?
        var lastIsSnapped: Bool?

        func show() { events.append("show") }
        func hide() { events.append("hide") }
        func render(
            originScreen: CGPoint,
            cursorScreen: CGPoint,
            duration: TimeInterval,
            isSnapped: Bool,
            isCancelling: Bool,
            updateText: Bool
        ) {
            lastDuration = duration
            lastIsCancelling = isCancelling
            lastIsSnapped = isSnapped
        }
    }

    private final class CancelKeySpy: DragCancelKeying {
        var onPress: (() -> Void)?
        private(set) var isRegistered = false
        private(set) var wasPressed = false

        func register() {
            isRegistered = true
            wasPressed = false
        }

        func unregister() { isRegistered = false }

        /// Escape reaches the app only while the key is registered.
        func press() {
            guard isRegistered else { return }
            wasPressed = true
            onPress?()
        }

        /// The key has gone down but its callback has not run yet.
        func pressWithoutDelivering() {
            if isRegistered { wasPressed = true }
        }
    }

    private final class DriverSpy: DragFrameDriving {
        var onFrame: ((TimeInterval, TimeInterval) -> Void)?
        private(set) var isRunning = false
        private let starts: Bool
        private var timestamp: TimeInterval = 10

        init(starts: Bool) { self.starts = starts }

        func start(on screen: NSScreen?) { isRunning = starts }
        func retarget(to screen: NSScreen?) {}
        func stop() { isRunning = false }

        func fireFrame() {
            guard isRunning else { return }
            timestamp += 1.0 / 120.0
            onFrame?(1.0 / 120.0, timestamp)
        }
    }

    private final class SilentAudio: AudioAlertPlaying {
        func play(timer: TimerRecord) {}
        func stop() {}
    }
}
