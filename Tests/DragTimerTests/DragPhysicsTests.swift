import XCTest
@testable import DragTimer

final class DragPhysicsTests: XCTestCase {
    func testStoppedReleaseMatchesWholeMinutePreviewForEveryCurve() {
        for preset in FeelPreset.allCases {
            for snappingEnabled in [false, true] {
                var settings = DragPhysicsSettings.forPreset(preset)
                settings.snappingEnabled = snappingEnabled
                settings.reduceMotion = true
                var physics = DragPhysics(settings: settings)

                physics.begin(at: 1)
                _ = physics.updateDrag(distance: 250, timestamp: 1.1)
                let preview = physics.displayDuration
                let release = physics.release(at: 1.4)

                XCTAssertEqual(
                    preview.truncatingRemainder(dividingBy: DragDurationGrid.step),
                    0,
                    "\(preset.displayName) preview should select whole minutes"
                )
                XCTAssertEqual(
                    release.duration,
                    preview,
                    "\(preset.displayName) must not apply stale velocity after the drag stops"
                )
            }
        }
    }

    func testFreshMovingReleaseStillUsesConfiguredThrow() {
        var settings = DragPhysicsSettings.forPreset(.throwable)
        settings.snappingEnabled = false
        settings.reduceMotion = true
        var physics = DragPhysics(settings: settings)

        physics.begin(at: 1)
        _ = physics.updateDrag(distance: 250, timestamp: 1.1)
        let preview = physics.displayDuration
        let release = physics.release(at: 1.11)

        XCTAssertGreaterThan(release.duration, preview)
        XCTAssertEqual(release.duration.truncatingRemainder(dividingBy: DragDurationGrid.step), 0)
    }

    func testDragSelectionTextOmitsSeconds() {
        XCTAssertEqual(DurationText.dragSelection(60), "1m")
        XCTAssertEqual(DurationText.dragSelection(7 * 60), "7m")
        XCTAssertEqual(DurationText.dragSelection(60 * 60), "1h")
        XCTAssertEqual(DurationText.dragSelection(90 * 60), "1h 30m")
    }
}
