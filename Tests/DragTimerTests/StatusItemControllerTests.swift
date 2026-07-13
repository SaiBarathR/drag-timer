import AppKit
import XCTest
@testable import DragTimer

final class StatusItemControllerTests: XCTestCase {
    @MainActor
    func testPausingTimerDoesNotResizeAnchorUntilPopoverCloses() {
        _ = NSApplication.shared
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DragTimerTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let defaultsSuite = "DragTimerTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: defaultsSuite)!
        defer { defaults.removePersistentDomain(forName: defaultsSuite) }

        let engine = TimerEngine(
            persistence: TimerPersistence(fileURL: directory.appendingPathComponent("timers.json")),
            notificationService: NotificationService(center: nil),
            audioPlayer: SilentAudioPlayer()
        )
        let controller = StatusItemController(
            timerEngine: engine,
            settings: AppSettings(defaults: defaults),
            onPopoverRequested: { _ in }
        )
        let timer = engine.createTimer(duration: 300, options: TimerOptions(label: "Anchor"))

        controller.setPopoverVisible(true)
        let runningWidth = controller.currentWidth
        engine.pause(id: timer.id)

        XCTAssertEqual(controller.currentWidth, runningWidth)

        controller.setPopoverVisible(false)
        XCTAssertEqual(controller.currentWidth, 32)
    }

    private final class SilentAudioPlayer: AudioAlertPlaying {
        func play(timer: TimerRecord) {}
        func stop() {}
    }
}
