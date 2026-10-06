import XCTest
@testable import DragTimer

/// Characterization of the drag as it shipped in v1.4.1. Each transcript lists
/// every point where the readout, the snap state or the haptic detent changed
/// along a fixed pointer trace. A diff here means the drag feels different;
/// change these only on purpose.
final class DragFeelLockTests: XCTestCase {
    private static let frame = 1.0 / 120.0

    func testSlowDragTranscriptIsIdenticalForEveryPreset() {
        let trace = stride(from: 0.0, through: 420.0, by: 2.0).map { $0 }
        for preset in [FeelPreset.precise, .snappy, .throwable] {
            XCTAssertEqual(transcript(preset: preset, distances: trace), Self.slowDrag, preset.rawValue)
        }
    }

    func testReversalHoldsSnapsOnTheWayBack() {
        let out = stride(from: 0.0, through: 200.0, by: 2.0).map { $0 }
        let back = stride(from: 198.0, through: 60.0, by: -2.0).map { $0 }
        XCTAssertEqual(transcript(preset: .snappy, distances: out + back), Self.reversal)
    }

    /// 1 minute is both the minimum and a snap point, so the overlay opens in
    /// its snapped look and leaves it 0.64 rungs out. This is intended.
    func testDragOpensSnappedAtOneMinute() {
        var physics = DragPhysics(settings: .forPreset(.snappy))
        physics.begin(at: 0)
        XCTAssertFalse(physics.isSnapped)

        XCTAssertTrue(physics.updateDrag(distance: 0, timestamp: 0))
        XCTAssertTrue(physics.isSnapped)
        XCTAssertEqual(physics.displayDuration, 60)

        physics.updateDrag(distance: 12, timestamp: 0.1)
        XCTAssertTrue(physics.isSnapped)
        XCTAssertEqual(physics.displayDuration, 60)

        physics.updateDrag(distance: 14, timestamp: 0.2)
        XCTAssertFalse(physics.isSnapped)
        XCTAssertEqual(physics.displayDuration, 120)
    }

    func testReleaseAfterAPauseCommitsTheReadoutForEveryPreset() {
        for preset in [FeelPreset.precise, .snappy, .throwable] {
            var physics = dragged(preset: preset, to: 250, step: 5)
            let preview = physics.displayDuration
            let release = physics.release(at: 250 / 5 * Self.frame + 0.3)
            XCTAssertEqual(preview, 14 * 60, preset.rawValue)
            XCTAssertEqual(release.duration, preview, preset.rawValue)
            XCTAssertFalse(release.didSnap, preset.rawValue)
        }
    }

    func testFlickReleaseCommitsTheReadoutUnlessThrowable() {
        // 250 pt in 10 samples, released on the next frame: 3000 pt/s.
        let expected: [(FeelPreset, TimeInterval, Bool)] = [
            (.precise, 14 * 60, false),
            (.snappy, 14 * 60, false),
            (.throwable, Self.throwableFlickMinutes * 60, Self.throwableFlickSnapped)
        ]
        for (preset, duration, didSnap) in expected {
            var physics = dragged(preset: preset, to: 250, step: 25)
            let release = physics.release(at: 10 * Self.frame + 0.004)
            XCTAssertEqual(release.duration, duration, preset.rawValue)
            XCTAssertEqual(release.didSnap, didSnap, preset.rawValue)
        }
    }

    func testDefaultReleaseSettlesOnTheFirstFrame() {
        var physics = dragged(preset: .snappy, to: 250, step: 25)
        _ = physics.release(at: 10 * Self.frame + 0.004)
        XCTAssertEqual(physics.phase, .settling)
        XCTAssertTrue(physics.step(by: Self.frame))
        XCTAssertEqual(physics.displayDuration, 14 * 60)
    }

    /// Dragging slowly out and back must show every ladder value in both
    /// directions at every snap range the setting allows.
    func testEveryLadderValueIsReachableAtEverySnapRange() {
        let range = DragPhysicsSettings.snapToleranceRange
        for tolerance in stride(from: 8, through: range.upperBound, by: 2) + [range.upperBound, 60] {
            var settings = DragPhysicsSettings.forPreset(.snappy)
            settings.maximumDuration = 24 * 60 * 60
            settings.snapTolerance = tolerance
            let rungs = Set(DurationLadder.rungs(for: settings.sanitized))
            let end = Double(rungs.count) * DragPhysicsSettings.pointsPerRung
            let out = stride(from: 0.0, through: end, by: 1).map { $0 }

            XCTAssertEqual(shown(settings, along: out), rungs, "outward at \(tolerance)s")
            XCTAssertEqual(shown(settings, along: out + out.reversed(), skipping: out.count), rungs, "back at \(tolerance)s")
        }
    }

    private func shown(
        _ settings: DragPhysicsSettings,
        along distances: [Double],
        skipping warmUp: Int = 0
    ) -> Set<TimeInterval> {
        var physics = DragPhysics(settings: settings)
        physics.begin(at: 0)
        var values = Set<TimeInterval>()
        for (index, distance) in distances.enumerated() {
            physics.updateDrag(distance: distance, timestamp: Double(index) * Self.frame)
            if index >= warmUp { values.insert(physics.displayDuration) }
        }
        return values
    }

    // MARK: - Helpers

    private func dragged(preset: FeelPreset, to distance: Double, step: Double) -> DragPhysics {
        var physics = DragPhysics(settings: .forPreset(preset))
        physics.begin(at: 0)
        for (index, value) in stride(from: 0.0, through: distance, by: step).enumerated() {
            physics.updateDrag(distance: value, timestamp: Double(index) * Self.frame)
        }
        return physics
    }

    /// `distance:minutes`, with `*` while snapped and `|` where the haptic
    /// detent index (the rounded raw rung position) changed.
    private func transcript(preset: FeelPreset, distances: [Double]) -> String {
        var physics = DragPhysics(settings: .forPreset(preset))
        physics.begin(at: 0)
        var entries: [String] = []
        var last: (TimeInterval, Bool, Int)?
        for (index, distance) in distances.enumerated() {
            physics.updateDrag(distance: distance, timestamp: Double(index) * Self.frame)
            let detent = Int(physics.rawRungPosition.rounded())
            let state = (physics.displayDuration, physics.isSnapped, detent)
            if let last, last == state { continue }
            let tick = last.map { $0.2 != detent } ?? false
            entries.append(
                "\(Int(distance)):\(Int(physics.displayDuration / 60))"
                    + (physics.isSnapped ? "*" : "") + (tick ? "|" : "")
            )
            last = state
        }
        return entries.joined(separator: " ")
    }

    private static let throwableFlickMinutes: TimeInterval = 210
    private static let throwableFlickSnapped = false
    private static let slowDrag = """
        0:1* 10:1*| 14:2 30:3| 50:4| 70:5| 74:5* 90:5*| 94:6 110:7| 130:8| 150:9| 170:10| 190:11| \
        210:12| 230:13| 250:14| 270:15| 274:15* 290:15*| 294:20 310:25| 330:30| 332:30* 350:30*| \
        354:35 370:40| 390:45| 410:50|
        """
    private static let reversal = """
        0:1* 10:1*| 14:2 30:3| 50:4| 70:5| 74:5* 90:5*| 94:6 110:7| 130:8| 150:9| 170:10| 190:11| \
        188:10| 168:9| 148:8| 128:7| 108:6| 88:5| 86:5* 68:5*| 66:4
        """
}
