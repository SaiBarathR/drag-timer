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
        XCTAssertEqual(physics.displayDuration, 8 * 60)

        _ = physics.updateReleaseDistance(122)
        XCTAssertEqual(physics.displayDuration, 9 * 60)

        let release = physics.release(at: 1.4)
        XCTAssertEqual(release.duration, 9 * 60)
    }

    func testMappingScrubsDetentLadderUniformly() {
        var settings = DragPhysicsSettings.forPreset(.snappy)
        settings.snappingEnabled = false
        let mapper = DurationMapper(settings: settings)

        let rungs = DurationLadder.rungs(for: settings)
        let pixelsPerRung = settings.referenceDistance / Double(rungs.count - 1)

        // Every rung of the ladder costs the same pixel travel, whether the
        // step is worth one minute (early) or fifteen (late).
        for (index, rung) in rungs.enumerated() {
            XCTAssertEqual(
                mapper.duration(forDistance: pixelsPerRung * Double(index)),
                rung,
                accuracy: 0.001,
                "Rung \(index) should sit exactly \(index) uniform steps into the drag"
            )
        }

        XCTAssertEqual(mapper.duration(forDistance: 0), settings.minimumDuration)
        XCTAssertEqual(
            mapper.duration(forDistance: settings.referenceDistance),
            settings.maximumDuration,
            accuracy: 0.001
        )
    }

    func testLiveValueQuantizesToNearestLadderRung() {
        var settings = DragPhysicsSettings.forPreset(.snappy)
        settings.snappingEnabled = false
        let mapper = DurationMapper(settings: settings)

        let rungs = DurationLadder.rungs(for: settings)
        let pixelsPerRung = settings.referenceDistance / Double(rungs.count - 1)

        // Between rungs the readout holds the nearest rung instead of
        // interpolating through every in-between value.
        XCTAssertEqual(mapper.duration(forDistance: pixelsPerRung * 7.3), rungs[7])
        XCTAssertEqual(mapper.duration(forDistance: pixelsPerRung * 7.7), rungs[8])

        // The continuous variant still interpolates; snap-zone geometry and
        // haptic detents depend on it.
        XCTAssertEqual(
            mapper.continuousDuration(forDistance: pixelsPerRung * 7.5),
            (rungs[7] + rungs[8]) / 2,
            accuracy: 0.001
        )
    }

    func testDragPreviewOnlyEverShowsLadderValues() {
        for preset in [FeelPreset.precise, .snappy, .throwable] {
            var settings = DragPhysicsSettings.forPreset(preset)
            settings.snappingEnabled = false
            settings.reduceMotion = true
            var physics = DragPhysics(settings: settings)
            let rungs = Set(DurationLadder.rungs(for: settings.sanitized))

            physics.begin(at: 1)
            var timestamp = 1.0
            for distance in stride(from: 0.0, through: settings.referenceDistance, by: 3.7) {
                timestamp += 1.0 / 120.0
                _ = physics.updateDrag(distance: distance, timestamp: timestamp)
                XCTAssertTrue(
                    rungs.contains(physics.displayDuration),
                    "\(preset.displayName) preview \(physics.displayDuration) at \(distance)pt is not a ladder rung"
                )
            }
        }
    }

    func testRawRungPositionStaysContinuousForHapticDetents() {
        var settings = DragPhysicsSettings.forPreset(.snappy)
        settings.snappingEnabled = false
        settings.reduceMotion = true
        var physics = DragPhysics(settings: settings)

        let rungs = DurationLadder.rungs(for: settings)
        let pixelsPerRung = settings.referenceDistance / Double(rungs.count - 1)

        physics.begin(at: 1)
        XCTAssertEqual(physics.rawRungPosition, 0)

        _ = physics.updateDrag(distance: pixelsPerRung * 7.25, timestamp: 1.05)
        XCTAssertEqual(physics.rawRungPosition, 7.25, accuracy: 0.001)
        XCTAssertEqual(physics.displayDuration, rungs[7])
    }

    func testSnapHoldsWithHysteresisUntilClearlyOutsideTheZone() {
        var settings = DragPhysicsSettings.forPreset(.snappy)
        settings.reduceMotion = true
        var physics = DragPhysics(settings: settings)

        let rungs = DurationLadder.rungs(for: settings)
        let pixelsPerRung = settings.referenceDistance / Double(rungs.count - 1)
        let fiveMinuteDistance = pixelsPerRung * 4
        let toleranceRungs = SnapGrid.tolerance(settings: settings)
        let justOutside = fiveMinuteDistance + (toleranceRungs + 0.02) * pixelsPerRung
        let clearlyOutside = fiveMinuteDistance + (toleranceRungs * 1.6 + 0.05) * pixelsPerRung

        physics.begin(at: 1)
        _ = physics.updateDrag(distance: fiveMinuteDistance, timestamp: 1.1)
        XCTAssertTrue(physics.isSnapped)
        XCTAssertEqual(physics.displayDuration, 5 * 60)

        // Drifting just past the engage tolerance keeps the snap held...
        _ = physics.updateDrag(distance: justOutside, timestamp: 1.2)
        XCTAssertTrue(physics.isSnapped)
        XCTAssertEqual(physics.displayDuration, 5 * 60)

        // ...and only a clear exit releases it.
        _ = physics.updateDrag(distance: clearlyOutside, timestamp: 1.3)
        XCTAssertFalse(physics.isSnapped)
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
