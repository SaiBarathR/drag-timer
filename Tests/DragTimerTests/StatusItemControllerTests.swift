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
        controller.showPopover()

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
        controller.showPopover()

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
    func testContextMenuReachesTimersHistorySettingsAndQuit() {
        _ = NSApplication.shared
        let fixture = makeFixture()
        defer { fixture.cleanup() }
        var calls: [String] = []
        let controller = StatusItemController(
            timerEngine: fixture.engine,
            settings: fixture.settings,
            onPopoverRequested: { _, _ in calls.append("timers") },
            onOpenSettings: { calls.append("settings") },
            onOpenHistory: { calls.append("history") }
        )

        let menu = controller.contextMenuForTesting
        let items = menu.items.filter { !$0.isSeparatorItem }

        XCTAssertEqual(items.map(\.title), ["Show Timers", "Timer History", "Settings…", "Quit Drag Timer"])
        for item in items.dropLast() {
            NSApp.sendAction(item.action!, to: item.target, from: item)
        }
        XCTAssertEqual(calls, ["timers", "history", "settings"])

        // Show Timers must not close a popover that is already open.
        controller.setPopoverVisible(true)
        NSApp.sendAction(items[0].action!, to: items[0].target, from: items[0])
        XCTAssertEqual(calls, ["timers", "history", "settings"])
        controller.showPopover()
        XCTAssertEqual(calls, ["timers", "history", "settings", "timers"])

        XCTAssertEqual(items.last?.action, #selector(NSApplication.terminate(_:)))
        XCTAssertTrue(items.last?.target === NSApp)
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
        let start = fixture.engine.createTimer(
            duration: 601,
            options: TimerOptions(label: "Boundary")
        ).createdAt
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
    func testFinishedTimerHoldsTheMenuBarUntilItIsAnswered() throws {
        _ = NSApplication.shared
        let fixture = makeFixture()
        defer { fixture.cleanup() }
        let controller = StatusItemController(
            timerEngine: fixture.engine,
            settings: fixture.settings,
            onPopoverRequested: { _, _ in }
        )
        let timer = fixture.engine.createTimer(duration: 60, options: TimerOptions(label: "Tea"))
        let finishedAt = timer.fireDate.addingTimeInterval(1)

        fixture.engine.processExpiries(at: finishedAt)
        XCTAssertTrue(fixture.engine.timers.isEmpty)
        controller.refreshCountdownForTesting(at: finishedAt.addingTimeInterval(135))

        XCTAssertEqual(controller.currentWidth, StatusItemGeometry.width(for: "+2:15"))
        XCTAssertEqual(
            controller.accessibilityLabelForTesting,
            "Drag Timer, Tea finished 2 min ago"
        )

        fixture.engine.markExpiryDone(id: try XCTUnwrap(fixture.engine.currentExpiry).id)
        XCTAssertEqual(controller.currentWidth, 32)
        XCTAssertEqual(controller.accessibilityLabelForTesting, "Drag Timer, No running timers")
    }

    @MainActor
    func testFinishingNeverPassesThroughTheIdleIcon() {
        _ = NSApplication.shared
        let fixture = makeFixture()
        defer { fixture.cleanup() }
        var anchors: [NSRect] = []
        let controller = StatusItemController(
            timerEngine: fixture.engine,
            settings: fixture.settings,
            onPopoverRequested: { _, _ in },
            onPopoverAnchorChanged: { _, anchorRect in anchors.append(anchorRect) }
        )
        let timer = fixture.engine.createTimer(duration: 60, options: TimerOptions(label: "Tea"))
        anchors.removeAll()

        fixture.engine.processExpiries(at: timer.fireDate.addingTimeInterval(1))

        // A collapse to the idle clock on the way to the finished state
        // would move every menu-bar item to its left, twice.
        XCTAssertFalse(anchors.contains { $0.midX == 16 }, "\(anchors)")
        XCTAssertGreaterThan(controller.currentWidth, 32)
    }

    @MainActor
    func testFinishedStateKeepsItsDescriptionFreshInEveryMode() {
        _ = NSApplication.shared
        let fixture = makeFixture()
        defer { fixture.cleanup() }
        let controller = StatusItemController(
            timerEngine: fixture.engine,
            settings: fixture.settings,
            onPopoverRequested: { _, _ in }
        )
        XCTAssertNil(controller.countdownTickIntervalForTesting)

        let timer = fixture.engine.createTimer(duration: 60, options: TimerOptions(label: "Tea"))
        XCTAssertEqual(controller.countdownTickIntervalForTesting, 1)
        fixture.engine.processExpiries(at: timer.fireDate.addingTimeInterval(1))

        // The count-up changes every second; without it only "2 min ago"
        // in the tooltip and the VoiceOver label does.
        XCTAssertEqual(controller.countdownTickIntervalForTesting, 1)
        fixture.settings.menuBarDisplayMode = .ring
        controller.refreshCountdownForTesting(at: Date())
        XCTAssertEqual(controller.countdownTickIntervalForTesting, 60)
        fixture.settings.menuBarDisplayMode = .count
        controller.refreshCountdownForTesting(at: Date())
        XCTAssertEqual(controller.countdownTickIntervalForTesting, 60)

        fixture.engine.markExpiryDone(id: fixture.engine.pendingExpiries[0].id)
        XCTAssertNil(controller.countdownTickIntervalForTesting)
    }

    @MainActor
    func testAPinOutlivesItsTimerOnlyWhileRemovingItCanBeUndone() {
        _ = NSApplication.shared
        let fixture = makeFixture()
        defer { fixture.cleanup() }
        let controller = StatusItemController(
            timerEngine: fixture.engine,
            settings: fixture.settings,
            onPopoverRequested: { _, _ in }
        )
        let tea = fixture.engine.createTimer(duration: 600, options: TimerOptions(label: "Tea"))
        let other = fixture.engine.createTimer(duration: 300, options: TimerOptions(label: "Other"))
        fixture.settings.menuBarDisplayMode = .pinned
        fixture.settings.pinnedTimerID = tea.id

        // Undone: the pin is still there for the timer to come back to.
        fixture.engine.cancel(id: tea.id)
        XCTAssertEqual(fixture.settings.pinnedTimerID, tea.id)
        fixture.engine.undoLastRemoval()
        XCTAssertEqual(fixture.settings.pinnedTimerID, tea.id)
        XCTAssertEqual(fixture.engine.timers.count, 2)

        // Stop all, undone, keeps it as well.
        fixture.engine.cancelAll()
        XCTAssertEqual(fixture.settings.pinnedTimerID, tea.id)
        fixture.engine.undoLastRemoval()
        XCTAssertEqual(fixture.settings.pinnedTimerID, tea.id)

        // Not undone: the pin goes when the offer does.
        fixture.engine.cancel(id: tea.id)
        fixture.engine.dismissUndo()
        XCTAssertNil(fixture.settings.pinnedTimerID)

        // Replaced by a later removal: the same.
        let again = fixture.engine.createTimer(duration: 600, options: TimerOptions(label: "Tea"))
        fixture.settings.pinnedTimerID = again.id
        fixture.engine.cancel(id: again.id)
        fixture.engine.cancel(id: other.id)
        XCTAssertNil(fixture.settings.pinnedTimerID)
        _ = controller
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
