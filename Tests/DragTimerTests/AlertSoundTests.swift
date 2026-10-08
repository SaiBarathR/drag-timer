import XCTest
@testable import DragTimer

final class AlertSoundTests: XCTestCase {
    func testEverySoundOfferedExistsOnThisSystem() {
        for sound in AlertSound.allCases where sound != .systemBeep {
            XCTAssertNotNil(sound.fileURL, "\(sound.rawValue).aiff is missing from /System/Library/Sounds")
        }
        XCTAssertNil(AlertSound.systemBeep.fileURL)
        XCTAssertEqual(AlertSound.allCases.count, 15)
        XCTAssertEqual(Set(AlertSound.allCases.map(\.displayName)).count, 15)
    }

    func testUnknownAndLegacySoundNamesFallBackToGlass() {
        XCTAssertEqual(AlertSound.normalizedName("Ping"), "Ping")
        XCTAssertEqual(AlertSound.normalizedName("System"), "System")
        XCTAssertEqual(AlertSound.normalizedName("Pulse"), "Glass")
        XCTAssertEqual(AlertSound.normalizedName("ping"), "Glass")
        XCTAssertEqual(AlertSound.normalizedName(""), "Glass")
        XCTAssertEqual(TimerOptions(label: "Tea", soundName: "Submarine").soundName, "Submarine")
    }

    func testSpokenNameSurvivesEveryAlertModelAndIsOffForSavedData() throws {
        let options = TimerOptions(label: "Tea", soundName: "Ping", speaksName: true)
        let timer = TimerRecord(fireDate: Date().addingTimeInterval(60), options: options)
        let preset = QuickStartPreset(duration: 240, label: "Tea", alert: PresetAlertOptions(options))
        let routineTimer = RoutineTimerDefinition(preset: preset)

        XCTAssertTrue(timer.options.speaksName)
        XCTAssertTrue(preset.timerTemplate().options.speaksName)
        XCTAssertTrue(routineTimer.timerTemplate().options.speaksName)
        XCTAssertTrue(try roundTrip(timer).options.speaksName)
        XCTAssertTrue(try roundTrip(preset).alert.speaksName)
        XCTAssertTrue(try roundTrip(routineTimer).options.speaksName)

        // Everything saved by 1.5.0 lacks the key.
        XCTAssertFalse(try decodeWithout("speaksName", timer).options.speaksName)
        XCTAssertFalse(try decodeWithout("speaksName", options).speaksName)
        XCTAssertFalse(try decodeWithout("speaksName", PresetAlertOptions(options)).speaksName)
        XCTAssertEqual(try decodeWithout("speaksName", options).soundName, "Ping")
    }

    func testEditingATimerCanTurnTheSpokenNameOnAndOff() {
        var timer = TimerRecord(fireDate: Date().addingTimeInterval(60), options: TimerOptions(label: "Tea"))
        XCTAssertNil(AudioAlertPlayer.announcement(for: timer))

        var options = timer.options
        options.speaksName = true
        timer.apply(options)
        XCTAssertEqual(AudioAlertPlayer.announcement(for: timer), "Tea finished")

        options.speaksName = false
        timer.apply(options)
        XCTAssertNil(AudioAlertPlayer.announcement(for: timer))
    }

    func testAnnouncementReadsAMultiLineNameAsOneSentence() {
        let timer = TimerRecord(
            fireDate: Date().addingTimeInterval(60),
            options: TimerOptions(label: "Tea\nfor two", speaksName: true)
        )

        XCTAssertEqual(AudioAlertPlayer.announcement(for: timer), "Tea for two finished")
    }

    func testDefaultSpokenNameSettingPersistsAndReachesNewTimers() {
        let suite = "DragTimerSoundTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let settings = AppSettings(defaults: defaults)
        XCTAssertFalse(settings.defaultOptions().speaksName)
        settings.defaultSpeaksName = true
        settings.defaultSoundName = AlertSound.hero.rawValue

        let reloaded = AppSettings(defaults: defaults)
        XCTAssertTrue(reloaded.defaultOptions().speaksName)
        XCTAssertEqual(reloaded.defaultOptions().soundName, "Hero")
    }

    private func roundTrip<Value: Codable>(_ value: Value) throws -> Value {
        try JSONDecoder().decode(Value.self, from: JSONEncoder().encode(value))
    }

    private func decodeWithout<Value: Codable>(_ key: String, _ value: Value) throws -> Value {
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) as? [String: Any]
        )
        XCTAssertNotNil(object.removeValue(forKey: key), "\(Value.self) did not encode \(key)")
        return try JSONDecoder().decode(Value.self, from: JSONSerialization.data(withJSONObject: object))
    }
}
