import AppKit
import XCTest
@testable import DragTimer

final class TimerPopoverPresentationTests: XCTestCase {
    @MainActor
    func testPreparationUsesCurrentSwiftUIFittingSizeForEmptyAndActiveStates() {
        _ = NSApplication.shared
        let fixture = makeFixture()
        defer { fixture.cleanup() }
        let controller = makeController(fixture: fixture)

        controller.prepareForPresentationForTesting()
        let emptySize = controller.currentContentSize

        XCTAssertEqual(emptySize.width, 346, accuracy: 1)
        XCTAssertEqual(emptySize.width, controller.currentFittingContentSize.width, accuracy: 0.5)
        XCTAssertEqual(emptySize.height, controller.currentFittingContentSize.height, accuracy: 0.5)

        let timer = fixture.engine.createTimer(duration: 300, options: TimerOptions(label: "Sizing"))
        runMainLoopBriefly()
        controller.prepareForPresentationForTesting()
        let activeSize = controller.currentContentSize

        XCTAssertEqual(activeSize.width, 346, accuracy: 1)
        XCTAssertEqual(activeSize.width, controller.currentFittingContentSize.width, accuracy: 0.5)
        XCTAssertEqual(activeSize.height, controller.currentFittingContentSize.height, accuracy: 0.5)
        XCTAssertEqual(TimerPopoverGeometry.minimumContentHeight, 349)
        XCTAssertEqual(
            TimerPopoverGeometry.minimumContentHeight,
            ceil(
                TimerPopoverGeometry.previousMinimumContentHeight
                    * TimerPopoverGeometry.minimumHeightMultiplier
            )
        )
        XCTAssertGreaterThanOrEqual(emptySize.height, TimerPopoverGeometry.minimumContentHeight)
        XCTAssertGreaterThanOrEqual(activeSize.height, TimerPopoverGeometry.minimumContentHeight)

        fixture.engine.pause(id: timer.id)
        runMainLoopBriefly()
        controller.prepareForPresentationForTesting()
        let pausedSize = controller.currentContentSize

        XCTAssertGreaterThanOrEqual(pausedSize.height, TimerPopoverGeometry.minimumContentHeight)
        XCTAssertEqual(pausedSize.height, activeSize.height, accuracy: 0.5)
    }

    @MainActor
    func testRoutineStripKeepsPopoverWidthAndAddsOnlyOneCompactRow() {
        _ = NSApplication.shared
        let fixture = makeFixture()
        defer { fixture.cleanup() }
        let controller = makeController(fixture: fixture)
        controller.prepareForPresentationForTesting()
        let withoutRoutine = controller.currentContentSize
        XCTAssertTrue(fixture.settings.addRoutine(TimerRoutine(
            name: "Morning routine",
            timers: [
                RoutineTimerDefinition(duration: 5 * 60, options: TimerOptions(label: "Coffee")),
                RoutineTimerDefinition(duration: 15 * 60, options: TimerOptions(label: "Journal"))
            ]
        )))
        runMainLoopBriefly()

        controller.prepareForPresentationForTesting()
        let withRoutine = controller.currentContentSize

        XCTAssertEqual(withRoutine.width, withoutRoutine.width, accuracy: 0.5)
        XCTAssertGreaterThanOrEqual(withRoutine.height, withoutRoutine.height)
        XCTAssertLessThanOrEqual(withRoutine.height - withoutRoutine.height, 70)
    }

    @MainActor
    func testEmptyAndActivePopoversStayAttachedToClockAnchor() throws {
        _ = NSApplication.shared
        guard let screen = NSScreen.main else {
            throw XCTSkip("Popover placement requires an attached screen")
        }

        let fixture = makeFixture()
        defer { fixture.cleanup() }
        let controller = makeController(fixture: fixture)
        let anchorView = makeVisibleAnchorWindow(on: screen)
        defer {
            controller.closeForTesting()
            anchorView.window?.orderOut(nil)
        }
        let emptyPositioningRect = StatusItemGeometry.popoverAnchorRect(
            in: anchorView.bounds,
            hasCountdownLayout: false
        )

        try assertAttachedPresentation(
            controller: controller,
            anchorView: anchorView,
            positioningRect: emptyPositioningRect,
            expectedClockCenterX: anchorView.bounds.midX
        )

        controller.closeForTesting()
        runMainLoopBriefly()
        fixture.engine.createTimer(duration: 300, options: TimerOptions(label: "Attached"))
        runMainLoopBriefly()
        let activeWidth = StatusItemGeometry.width(for: "4:00")
        anchorView.window?.setContentSize(NSSize(width: activeWidth, height: 22))
        anchorView.frame = NSRect(x: 0, y: 0, width: activeWidth, height: 22)
        let activePositioningRect = StatusItemGeometry.popoverAnchorRect(
            in: anchorView.bounds,
            hasCountdownLayout: true
        )

        try assertAttachedPresentation(
            controller: controller,
            anchorView: anchorView,
            positioningRect: activePositioningRect,
            expectedClockCenterX: 13
        )
    }

    @MainActor
    func testVisibilityCallbackWrapsPopoverPresentation() throws {
        _ = NSApplication.shared
        guard let screen = NSScreen.main else {
            throw XCTSkip("Popover placement requires an attached screen")
        }

        let fixture = makeFixture()
        defer { fixture.cleanup() }
        var visibilityChanges: [Bool] = []
        let controller = makeController(
            fixture: fixture,
            onPopoverVisibilityChanged: { visibilityChanges.append($0) }
        )
        let anchorView = makeVisibleAnchorWindow(on: screen)
        defer { anchorView.window?.orderOut(nil) }
        let positioningRect = StatusItemGeometry.popoverAnchorRect(
            in: anchorView.bounds,
            hasCountdownLayout: false
        )

        controller.toggle(relativeTo: anchorView, positioningRect: positioningRect)
        runMainLoopBriefly()
        XCTAssertEqual(visibilityChanges, [true])

        controller.closeForTesting()
        runMainLoopBriefly()
        XCTAssertEqual(visibilityChanges, [true, false])
    }

    @MainActor
    private func assertAttachedPresentation(
        controller: TimerPopoverController,
        anchorView: NSView,
        positioningRect: NSRect,
        expectedClockCenterX: CGFloat
    ) throws {
        guard let window = anchorView.window else {
            XCTFail("Anchor view must be attached to a window")
            return
        }

        controller.toggle(relativeTo: anchorView, positioningRect: positioningRect)
        runMainLoopBriefly()

        XCTAssertTrue(controller.isShownForTesting)
        XCTAssertEqual(controller.currentPositioningRect, positioningRect)
        guard let popoverFrame = controller.currentPopoverWindowFrame else {
            XCTFail("Popover content must be attached to a window")
            return
        }

        let anchorWindowRect = anchorView.convert(positioningRect, to: nil)
        let anchorScreenRect = window.convertToScreen(anchorWindowRect)
        XCTAssertLessThanOrEqual(
            abs(popoverFrame.maxY - anchorScreenRect.minY),
            12,
            "Popover must remain attached to the lower edge of the clock anchor"
        )
        XCTAssertEqual(positioningRect.midX, expectedClockCenterX, accuracy: 0.5)
    }

    @MainActor
    private func makeVisibleAnchorWindow(on screen: NSScreen) -> NSView {
        let anchorSize = NSSize(width: 32, height: 22)
        let frame = NSRect(
            x: screen.visibleFrame.midX - (anchorSize.width / 2),
            y: screen.visibleFrame.maxY - anchorSize.height,
            width: anchorSize.width,
            height: anchorSize.height
        )
        let window = NSWindow(
            contentRect: frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        let anchorView = NSView(frame: NSRect(origin: .zero, size: anchorSize))
        window.contentView = anchorView
        window.orderFrontRegardless()
        runMainLoopBriefly()
        return anchorView
    }

    @MainActor
    private func makeController(
        fixture: Fixture,
        onPopoverVisibilityChanged: @escaping (Bool) -> Void = { _ in }
    ) -> TimerPopoverController {
        TimerPopoverController(
            timerEngine: fixture.engine,
            settings: fixture.settings,
            onOpenSettings: {},
            onPopoverVisibilityChanged: onPopoverVisibilityChanged,
            animationsEnabled: false
        )
    }

    @MainActor
    private func makeFixture() -> Fixture {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DragTimerTests-\(UUID().uuidString)", isDirectory: true)
        let defaultsSuite = "DragTimerTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: defaultsSuite)!
        let engine = TimerEngine(
            persistence: TimerPersistence(fileURL: directory.appendingPathComponent("timers.json")),
            notificationService: NotificationService(center: nil),
            audioPlayer: SilentAudioPlayer()
        )
        return Fixture(
            engine: engine,
            settings: AppSettings(defaults: defaults),
            cleanup: {
                try? FileManager.default.removeItem(at: directory)
                defaults.removePersistentDomain(forName: defaultsSuite)
            }
        )
    }

    @MainActor
    private func runMainLoopBriefly() {
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
    }

    private struct Fixture {
        let engine: TimerEngine
        let settings: AppSettings
        let cleanup: () -> Void
    }

    private final class SilentAudioPlayer: AudioAlertPlaying {
        func play(timer: TimerRecord) {}
        func stop() {}
    }
}
