import AppKit
import XCTest
@testable import DragTimer

final class TimerEditorModelTests: XCTestCase {
    func testEverySymbolHasItsOwnReadableName() {
        let names = TimerIdentity.allowedSymbols.map(TimerIdentity.displayName(forSymbol:))

        XCTAssertEqual(Set(names).count, TimerIdentity.allowedSymbols.count)
        XCTAssertTrue(names.allSatisfy { !$0.contains(".") })
        XCTAssertEqual(TimerIdentity.displayName(forSymbol: "cup.and.saucer.fill"), "Coffee")
    }

    func testColorNamesMatchTheSystemColorsShown() {
        XCTAssertEqual(TimerColorToken.mint.displayName, "Green")
        XCTAssertEqual(TimerColorToken.amber.displayName, "Orange")
        XCTAssertEqual(Set(TimerColorToken.allCases.map(\.displayName)).count, TimerColorToken.allCases.count)
    }

    func testDurationFieldShowsALengthItReadsBackUnchanged() {
        for minutes in [1, 5, 59, 60, 61, 90, 135, 240, 24 * 60] {
            let duration = TimeInterval(minutes * 60)
            XCTAssertEqual(DurationInput.parse(DurationField.text(for: duration)), duration, "\(minutes) min")
        }
    }

    func testEditShortcutsMenuCarriesTheStandardEditingShortcuts() {
        let menu = EditShortcutsMenu.make()
        let edit = menu.items.compactMap(\.submenu).first { $0.title == "Edit" }
        let shortcuts = edit?.items.filter { !$0.isSeparatorItem }.map { "\($0.title):\($0.keyEquivalent)" }

        XCTAssertEqual(shortcuts, ["Undo:z", "Redo:Z", "Cut:x", "Copy:c", "Paste:v", "Select All:a"])
        XCTAssertEqual(menu.items.count, 2)
    }

    func testApplyingEditedOptionsKeepsTimingAndNormalizesValues() {
        let created = Date(timeIntervalSinceReferenceDate: 500)
        var record = TimerRecord(
            createdAt: created,
            fireDate: created.addingTimeInterval(600),
            options: TimerOptions(label: "Old")
        )
        var edited = record.options
        edited.label = "  \n "
        edited.volume = 3
        edited.snoozeMinutes = 12
        edited.loop = true
        edited.identity = TimerIdentity(color: .violet, symbolName: "book.fill")

        record.apply(edited)

        XCTAssertEqual(record.label, "Timer")
        XCTAssertEqual(record.volume, 1)
        XCTAssertEqual(record.snoozeMinutes, 12)
        XCTAssertTrue(record.loop)
        XCTAssertEqual(record.resolvedIdentity, TimerIdentity(color: .violet, symbolName: "book.fill"))
        XCTAssertEqual(record.fireDate, created.addingTimeInterval(600))
        XCTAssertEqual(record.resetDuration, 600)
    }

    func testPresetAlertAndTimerOptionsConvertWithoutLoss() {
        let options = TimerOptions(
            label: "Tea",
            soundName: AlertSound.systemBeep.rawValue,
            volume: 0.35,
            loop: true,
            notify: false,
            snoozeMinutes: 9,
            identity: TimerIdentity(color: .red, symbolName: "flame.fill")
        )

        let roundTripped = TimerOptions(
            label: options.label,
            alert: PresetAlertOptions(options),
            identity: options.identity
        )

        XCTAssertEqual(roundTripped, options)
    }
}
