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

    func testReleaseFreshnessBoundaryPreservesFullThrowUntilItExpires() {
        var immediate = movingThrowablePhysics()
        let immediateRelease = immediate.release(at: 1.1)

        var justFresh = movingThrowablePhysics()
        let justFreshRelease = justFresh.release(
            at: 1.1 + DragPhysics.releaseVelocityLifetime - 0.001
        )

        var stale = movingThrowablePhysics()
        let stalePreview = stale.displayDuration
        let staleRelease = stale.release(at: 1.1 + DragPhysics.releaseVelocityLifetime)

        var justStale = movingThrowablePhysics()
        let justStalePreview = justStale.displayDuration
        let justStaleRelease = justStale.release(
            at: 1.1 + DragPhysics.releaseVelocityLifetime + 0.001
        )

        XCTAssertEqual(justFreshRelease.duration, immediateRelease.duration)
        XCTAssertEqual(staleRelease.duration, stalePreview)
        XCTAssertEqual(justStaleRelease.duration, justStalePreview)
    }

    func testSparseDragSamplesKeepMomentumWithinSamplingWindow() {
        var settings = DragPhysicsSettings.forPreset(.throwable)
        settings.snappingEnabled = false
        settings.reduceMotion = true
        var physics = DragPhysics(settings: settings)

        physics.begin(at: 1)
        _ = physics.updateDrag(distance: 100, timestamp: 1.05)
        _ = physics.updateDrag(
            distance: 250,
            timestamp: 1.05 + DragPhysics.maximumVelocitySampleInterval - 0.01
        )
        let preview = physics.displayDuration
        let release = physics.release(at: 1.05 + DragPhysics.maximumVelocitySampleInterval)

        XCTAssertGreaterThan(release.duration, preview)
    }

    func testMouseUpDistanceAdvancesSelectionWithoutRefreshingStaleVelocity() {
        var settings = DragPhysicsSettings.forPreset(.snappy)
        settings.snappingEnabled = false
        settings.reduceMotion = true
        var physics = DragPhysics(settings: settings)

        physics.begin(at: 1)
        _ = physics.updateDrag(distance: 114, timestamp: 1.1)
        XCTAssertEqual(physics.displayDuration, 60)

        _ = physics.updateReleaseDistance(119)
        XCTAssertEqual(physics.displayDuration, 120)

        let release = physics.release(at: 1.4)
        XCTAssertEqual(release.duration, 120)
    }

    func testDurationRangeSanitizationKeepsWholeMinuteNonDegenerateBounds() {
        var settings = DragPhysicsSettings()
        settings.minimumDuration = 61
        settings.maximumDuration = 239

        let sanitized = settings.sanitized
        XCTAssertEqual(sanitized.minimumDuration, 120)
        XCTAssertEqual(sanitized.maximumDuration, 180)

        settings.minimumDuration = 121
        settings.maximumDuration = 179
        let collapsed = settings.sanitized
        XCTAssertEqual(collapsed.minimumDuration, 180)
        XCTAssertEqual(collapsed.maximumDuration, 240)
    }

    func testDragSelectionTextOmitsSeconds() {
        XCTAssertEqual(DurationText.dragSelection(60), "1m")
        XCTAssertEqual(DurationText.dragSelection(7 * 60), "7m")
        XCTAssertEqual(DurationText.dragSelection(60 * 60), "1h")
        XCTAssertEqual(DurationText.dragSelection(90 * 60), "1h 30m")
    }

    private func movingThrowablePhysics() -> DragPhysics {
        var settings = DragPhysicsSettings.forPreset(.throwable)
        settings.snappingEnabled = false
        settings.reduceMotion = true
        var physics = DragPhysics(settings: settings)
        physics.begin(at: 1)
        _ = physics.updateDrag(distance: 250, timestamp: 1.1)
        return physics
    }
}
