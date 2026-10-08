import AppKit
import XCTest
@testable import DragTimer

final class AppSettingsMigrationTests: XCTestCase {
    func testLegacyMinutePresetsMigrateOnceWithoutSortingOrDeduplicating() throws {
        let fixture = makeDefaults()
        defer { fixture.cleanup() }
        let legacy: [String: Any] = [
            "quickStartMinutes": [30, 5, 30],
            "defaultSoundName": "Glass",
            "defaultVolume": 0.4,
            "defaultLoop": true,
            "defaultNotificationsEnabled": false,
            "defaultSnoozeMinutes": 7
        ]
        fixture.defaults.set(try JSONSerialization.data(withJSONObject: legacy), forKey: storageKey)

        let firstLoad = AppSettings(defaults: fixture.defaults)
        XCTAssertEqual(firstLoad.quickStartMinutes, [30, 5, 30])
        XCTAssertEqual(firstLoad.quickStartPresets.map(\.alert.snoozeMinutes), [7, 7, 7])
        XCTAssertEqual(Set(firstLoad.quickStartPresets.map(\.id)).count, 3)
        let migratedIDs = firstLoad.quickStartPresets.map(\.id)

        let secondLoad = AppSettings(defaults: fixture.defaults)
        XCTAssertEqual(secondLoad.quickStartPresets.map(\.id), migratedIDs)
        XCTAssertEqual(secondLoad.quickStartMinutes, [30, 5, 30])
    }

    func testOnlyTheLaunchWithNoSavedSettingsIsAFirstLaunch() {
        let suite = "DragTimerFirstLaunchTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        XCTAssertTrue(AppSettings(defaults: defaults).isFirstLaunch)
        XCTAssertFalse(AppSettings(defaults: defaults).isFirstLaunch)
    }

    func testMissingAdditiveFieldsKeepSettingsBlobDecodable() throws {
        let fixture = makeDefaults()
        defer { fixture.cleanup() }
        fixture.defaults.set(
            try JSONSerialization.data(withJSONObject: ["hapticsEnabled": false]),
            forKey: storageKey
        )

        let settings = AppSettings(defaults: fixture.defaults)

        XCTAssertFalse(settings.hapticsEnabled)
        XCTAssertEqual(settings.menuBarDisplayMode, .deadline)
        XCTAssertEqual(settings.countdownScale, .standard)
        XCTAssertEqual(settings.quickStartMinutes, AppSettings.defaultQuickStartMinutes)
        XCTAssertTrue(settings.routines.isEmpty)
    }

    func testRichPresetOrderDuplicatesAndSnapshotOptionsPersist() {
        let fixture = makeDefaults()
        defer { fixture.cleanup() }
        let tea = QuickStartPreset(
            duration: 4 * 60,
            label: "Tea",
            alert: PresetAlertOptions(loop: true, snoozeMinutes: 3),
            identity: TimerIdentity(color: .amber, symbolName: "cup.and.saucer.fill")
        )
        let steep = QuickStartPreset(duration: 4 * 60, label: "Steep")
        let settings = AppSettings(defaults: fixture.defaults)

        settings.setQuickStartPresets([tea, steep])
        settings.movePreset(id: steep.id, offset: -1)
        XCTAssertTrue(settings.duplicatePreset(id: tea.id))

        let restored = AppSettings(defaults: fixture.defaults)
        XCTAssertEqual(restored.quickStartPresets.map(\.label), ["Steep", "Tea", "Tea Copy"])
        XCTAssertEqual(restored.quickStartMinutes, [4, 4, 4])
        let options = restored.quickStartPresets[1].timerTemplate().options
        XCTAssertEqual(options.label, "Tea")
        XCTAssertTrue(options.loop)
        XCTAssertEqual(options.snoozeMinutes, 3)
        XCTAssertEqual(options.identity.color, .amber)
    }

    func testRoutineSnapshotsOrderDuplicationAndPersistence() throws {
        let fixture = makeDefaults()
        defer { fixture.cleanup() }
        let settings = AppSettings(defaults: fixture.defaults)
        let teaPreset = QuickStartPreset(
            duration: 4 * 60,
            label: "Tea",
            alert: PresetAlertOptions(loop: true, snoozeMinutes: 3),
            identity: TimerIdentity(color: .amber, symbolName: "cup.and.saucer.fill")
        )
        settings.setQuickStartPresets([teaPreset])
        let teaTimer = RoutineTimerDefinition(preset: teaPreset)
        let focusTimer = RoutineTimerDefinition(
            duration: 25 * 60,
            options: TimerOptions(label: "Focus", notify: false)
        )
        let morning = TimerRoutine(name: "Morning", timers: [teaTimer, focusTimer])
        let cooking = TimerRoutine(
            name: "Cooking",
            timers: [RoutineTimerDefinition(duration: 10 * 60, options: TimerOptions(label: "Oven"))]
        )

        XCTAssertFalse(settings.addRoutine(TimerRoutine(name: "", timers: [])))
        XCTAssertFalse(settings.addRoutine(TimerRoutine(
            name: "Unlabeled",
            timers: [RoutineTimerDefinition(duration: 5 * 60, options: TimerOptions(label: ""))]
        )))
        XCTAssertTrue(settings.addRoutine(morning))
        XCTAssertTrue(settings.addRoutine(cooking))
        settings.moveRoutine(id: cooking.id, offset: -1)
        XCTAssertTrue(settings.duplicateRoutine(id: morning.id))

        var changedPreset = teaPreset
        changedPreset.label = "Changed preset"
        changedPreset.duration = 30 * 60
        settings.updatePreset(changedPreset)

        let restored = AppSettings(defaults: fixture.defaults)
        XCTAssertEqual(restored.routines.map(\.name), ["Cooking", "Morning", "Morning Copy"])
        let restoredMorning = try XCTUnwrap(restored.routines.first { $0.name == "Morning" })
        XCTAssertEqual(restoredMorning.timers.map(\.options.label), ["Tea", "Focus"])
        XCTAssertEqual(
            restoredMorning.timers.map(\.duration),
            [TimeInterval(4 * 60), TimeInterval(25 * 60)]
        )
        XCTAssertEqual(restoredMorning.timers[0].options.identity.color, .amber)
        XCTAssertTrue(restoredMorning.timers[0].options.loop)
        XCTAssertFalse(restoredMorning.timers[1].options.notify)

        let copy = try XCTUnwrap(restored.routines.first { $0.name == "Morning Copy" })
        XCTAssertNotEqual(copy.id, restoredMorning.id)
        XCTAssertEqual(copy.timers.count, restoredMorning.timers.count)
        XCTAssertTrue(zip(copy.timers, restoredMorning.timers).allSatisfy { $0.id != $1.id })
    }

    func testLegacyTimerDecodesWithDefaultIdentityAndOrigin() throws {
        let timer = TimerRecord(
            createdAt: Date(timeIntervalSinceReferenceDate: 100),
            fireDate: Date(timeIntervalSinceReferenceDate: 200),
            options: TimerOptions(label: "Legacy")
        )
        let encoded = try JSONEncoder().encode(timer)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object.removeValue(forKey: "identity")
        object.removeValue(forKey: "origin")
        object.removeValue(forKey: "parentEventID")

        let decoded = try JSONDecoder().decode(
            TimerRecord.self,
            from: JSONSerialization.data(withJSONObject: object)
        )

        XCTAssertEqual(decoded.resolvedIdentity, .default)
        XCTAssertEqual(decoded.resolvedOrigin, .drag)
    }

    func testIdentitySymbolsExistAndInvalidDecodedValuesFallBack() throws {
        for symbolName in TimerIdentity.allowedSymbols {
            XCTAssertNotNil(NSImage(systemSymbolName: symbolName, accessibilityDescription: nil), symbolName)
        }
        let decoded = try JSONDecoder().decode(
            TimerIdentity.self,
            from: Data(#"{"color":"future-color","symbolName":"not.a.symbol"}"#.utf8)
        )
        XCTAssertEqual(decoded, .default)
    }

    func testRestoringDragDefaultsPutsTheWholeFeelPaneBackToANewInstall() {
        let fixture = makeDefaults()
        defer { fixture.cleanup() }
        let fresh = makeDefaults()
        defer { fresh.cleanup() }
        let settings = AppSettings(defaults: fixture.defaults)
        settings.applyPreset(.throwable)
        settings.updatePhysics {
            $0.snappingEnabled = false
            $0.snapTolerance = 40
        }
        settings.setMaximumDragDurationHours(9)
        settings.hapticsEnabled = false
        settings.snapDuringDrag = false

        // Choosing the preset alone leaves snapping, haptics and the limit.
        settings.applyPreset(.snappy)
        XCTAssertFalse(settings.physics.snappingEnabled)
        XCTAssertEqual(settings.maximumDragDurationHours, 9)

        settings.restoreDragDefaults()

        let new = AppSettings(defaults: fresh.defaults)
        XCTAssertEqual(settings.preset, new.preset)
        XCTAssertEqual(settings.physics, new.physics)
        XCTAssertEqual(settings.hapticsEnabled, new.hapticsEnabled)
        XCTAssertEqual(settings.snapDuringDrag, new.snapDuringDrag)
        XCTAssertTrue(settings.physics.snappingEnabled)
        XCTAssertEqual(AppSettings(defaults: fixture.defaults).physics, new.physics)
    }

    func testAVolumeJustAboveZeroDoesNotReadAsZero() {
        XCTAssertEqual(VolumeText.percent(0), "0%")
        XCTAssertEqual(VolumeText.percent(0.004), "1%")
        XCTAssertEqual(VolumeText.percent(0.1), "10%")
        XCTAssertEqual(VolumeText.percent(0.799), "80%")
        XCTAssertEqual(VolumeText.percent(1), "100%")
        XCTAssertEqual(VolumeText.percent(1.4), "100%")
    }

    private let storageKey = "DragTimer.AppSettings.v1"

    private func makeDefaults() -> (defaults: UserDefaults, cleanup: () -> Void) {
        let suite = "DragTimerSettingsTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        return (defaults, { defaults.removePersistentDomain(forName: suite) })
    }
}
