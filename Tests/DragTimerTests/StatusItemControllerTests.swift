import AppKit
import XCTest
@testable import DragTimer

final class StatusItemControllerTests: XCTestCase {
    @MainActor
    func testOpeningEmptyPopoverDoesNotExpandStatusItem() {
        _ = NSApplication.shared
        let fixture = makeFixture()
        defer { fixture.cleanup() }
        var requestedAnchors: [NSRect] = []
        let controller = StatusItemController(
            timerEngine: fixture.engine,
            settings: fixture.settings,
            onPopoverRequested: { _, anchorRect in requestedAnchors.append(anchorRect) }
        )

        XCTAssertEqual(controller.currentWidth, 32)
        controller.setPopoverVisible(true)
        controller.requestPopoverForTesting()

        XCTAssertEqual(controller.currentWidth, 32)
        XCTAssertEqual(requestedAnchors, [controller.currentPopoverAnchorRect])
        XCTAssertEqual(requestedAnchors.first?.midX, 16)
        controller.setPopoverVisible(false)
    }

    @MainActor
    func testRunningTimerWidthStaysUnchangedWhenPopoverIsRequested() {
        _ = NSApplication.shared
        let fixture = makeFixture()
        defer { fixture.cleanup() }
        var requestedAnchors: [NSRect] = []
        let controller = StatusItemController(
            timerEngine: fixture.engine,
            settings: fixture.settings,
            onPopoverRequested: { _, anchorRect in requestedAnchors.append(anchorRect) }
        )
        fixture.engine.createTimer(duration: 240, options: TimerOptions(label: "Anchor"))
        let runningWidth = controller.currentWidth

        controller.setPopoverVisible(true)
        controller.requestPopoverForTesting()

        XCTAssertGreaterThan(runningWidth, 32)
        XCTAssertEqual(controller.currentWidth, runningWidth)
        XCTAssertEqual(requestedAnchors.first?.midX, 13)
        controller.setPopoverVisible(false)
    }

    @MainActor
    func testPauseAndResumeKeepOpenPopoverWidthAndAnchorStable() {
        _ = NSApplication.shared
        let fixture = makeFixture()
        defer { fixture.cleanup() }
        var changedAnchors: [NSRect] = []
        let controller = StatusItemController(
            timerEngine: fixture.engine,
            settings: fixture.settings,
            onPopoverRequested: { _, _ in },
            onPopoverAnchorChanged: { _, anchorRect in changedAnchors.append(anchorRect) }
        )
        let timer = fixture.engine.createTimer(duration: 300, options: TimerOptions(label: "Stable"))
        let openWidth = controller.currentWidth
        let openAnchor = controller.currentPopoverAnchorRect

        controller.setPopoverVisible(true)
        let changesBeforePause = changedAnchors.count

        fixture.engine.pause(id: timer.id)
        XCTAssertEqual(controller.currentWidth, openWidth)
        XCTAssertEqual(controller.currentPopoverAnchorRect, openAnchor)
        XCTAssertEqual(changedAnchors.count, changesBeforePause)

        fixture.engine.resume(id: timer.id)
        XCTAssertEqual(controller.currentWidth, openWidth)
        XCTAssertEqual(controller.currentPopoverAnchorRect, openAnchor)
        XCTAssertEqual(changedAnchors.count, changesBeforePause)

        fixture.engine.pause(id: timer.id)
        XCTAssertEqual(controller.currentWidth, openWidth)
        XCTAssertEqual(controller.currentPopoverAnchorRect, openAnchor)
        XCTAssertEqual(changedAnchors.count, changesBeforePause)

        controller.setPopoverVisible(false)
        XCTAssertEqual(controller.currentWidth, 32)
        XCTAssertEqual(controller.currentPopoverAnchorRect.midX, 16)
        XCTAssertEqual(changedAnchors.count, changesBeforePause + 1)
    }

    @MainActor
    func testTimerLifecycleRecomputesWidthAndRefreshesVisibleAnchor() {
        _ = NSApplication.shared
        let fixture = makeFixture()
        defer { fixture.cleanup() }
        var changedAnchors: [NSRect] = []
        let controller = StatusItemController(
            timerEngine: fixture.engine,
            settings: fixture.settings,
            onPopoverRequested: { _, _ in },
            onPopoverAnchorChanged: { _, anchorRect in changedAnchors.append(anchorRect) }
        )
        let timer = fixture.engine.createTimer(duration: 300, options: TimerOptions(label: "Lifecycle"))
        XCTAssertGreaterThan(controller.currentWidth, 32)
        XCTAssertEqual(changedAnchors.last?.midX, 13)

        fixture.engine.pause(id: timer.id)
        XCTAssertEqual(controller.currentWidth, 32)
        XCTAssertEqual(changedAnchors.last?.midX, 16)

        fixture.engine.resume(id: timer.id)
        XCTAssertGreaterThan(controller.currentWidth, 32)
        XCTAssertEqual(changedAnchors.last?.midX, 13)

        fixture.engine.cancel(id: timer.id)
        XCTAssertTrue(fixture.engine.timers.isEmpty)
        XCTAssertEqual(controller.currentWidth, 32)
        XCTAssertEqual(changedAnchors.last?.midX, 16)
    }

    @MainActor
    func testCountdownFormatBoundaryShrinksWidthAndRefreshesAnchor() {
        _ = NSApplication.shared
        let fixture = makeFixture()
        defer { fixture.cleanup() }
        var anchorChangeCount = 0
        let controller = StatusItemController(
            timerEngine: fixture.engine,
            settings: fixture.settings,
            onPopoverRequested: { _, _ in },
            onPopoverAnchorChanged: { _, _ in anchorChangeCount += 1 }
        )
        let start = Date()
        fixture.engine.createTimer(
            fireDate: start.addingTimeInterval(601),
            options: TimerOptions(label: "Boundary")
        )
        controller.refreshCountdownForTesting(at: start)
        let fiveDigitWidth = controller.currentWidth
        let changesBeforeBoundary = anchorChangeCount

        controller.refreshCountdownForTesting(at: start.addingTimeInterval(2))

        XCTAssertEqual(fiveDigitWidth, StatusItemGeometry.width(for: "10:01"))
        XCTAssertEqual(controller.currentWidth, StatusItemGeometry.width(for: "9:59"))
        XCTAssertLessThan(controller.currentWidth, fiveDigitWidth)
        XCTAssertGreaterThan(anchorChangeCount, changesBeforeBoundary)
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
