import XCTest
@testable import DragTimer

final class MaximumDragDurationTests: XCTestCase {
    func testMaximumDurationDefaultsToFourHoursAndPersistsChanges() {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = AppSettings(defaults: defaults)
        XCTAssertEqual(settings.maximumDragDurationHours, 4)
        XCTAssertEqual(settings.preset, .snappy)

        settings.setMaximumDragDurationHours(12)

        XCTAssertEqual(settings.maximumDragDurationHours, 12)
        XCTAssertEqual(settings.preset, .snappy, "Changing the range should not change the drag feel")
        XCTAssertEqual(AppSettings(defaults: defaults).maximumDragDurationHours, 12)
    }

    func testMaximumDurationClampsToSupportedRange() {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = AppSettings(defaults: defaults)

        settings.setMaximumDragDurationHours(2)
        XCTAssertEqual(settings.maximumDragDurationHours, 4)

        settings.setMaximumDragDurationHours(48)
        XCTAssertEqual(settings.maximumDragDurationHours, 24)
    }

    func testDragMappingAndSnapGridReachTwentyFourHours() {
        var physics = DragPhysicsSettings()
        physics.referenceDistance = 600
        physics.maximumDuration = 24 * 3_600
        let mapper = DurationMapper(settings: physics)

        XCTAssertEqual(mapper.duration(forDistance: 600), 24 * 3_600, accuracy: 0.001)
        XCTAssertEqual(SnapGrid.nearest(to: 24 * 3_600, settings: physics), 24 * 3_600)
    }

    private func makeDefaults() -> (UserDefaults, String) {
        let suiteName = "DragTimerTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        return (defaults, suiteName)
    }
}
