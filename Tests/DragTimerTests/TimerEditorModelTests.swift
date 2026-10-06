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

    func testDurationFieldsCarryMinutesAndStayWithinOneDay() {
        XCTAssertEqual(DurationFields.clamped(hours: 2, minutes: 15), 135)
        XCTAssertEqual(DurationFields.clamped(hours: 0, minutes: 90), 90)
        XCTAssertEqual(DurationFields.clamped(hours: 0, minutes: 0), 1)
        XCTAssertEqual(DurationFields.clamped(hours: -3, minutes: -5), 1)
        XCTAssertEqual(DurationFields.clamped(hours: 30, minutes: 0), 24 * 60)
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
