import XCTest
@testable import DragTimer

final class DurationInputTests: XCTestCase {
    func testBareNumbersAreMinutes() {
        XCTAssertEqual(DurationInput.parse("7"), 7 * 60)
        XCTAssertEqual(DurationInput.parse(" 25 "), 25 * 60)
        XCTAssertEqual(DurationInput.parse("90"), 90 * 60)
    }

    func testUnitsInTheirCommonSpellings() {
        for text in ["25m", "25 m", "25min", "25 mins", "25 minutes", "25M"] {
            XCTAssertEqual(DurationInput.parse(text), 25 * 60, text)
        }
        for text in ["2h", "2 h", "2hr", "2 hrs", "2 hours", "2H"] {
            XCTAssertEqual(DurationInput.parse(text), 2 * 3_600, text)
        }
    }

    func testHoursAndMinutesTogether() {
        for text in ["1h30", "1h 30", "1h30m", "1 hr 30 min", "1:30", "1.5h", "1.5 hours"] {
            XCTAssertEqual(DurationInput.parse(text), 90 * 60, text)
        }
        XCTAssertEqual(DurationInput.parse("0:05"), 5 * 60)
        XCTAssertEqual(DurationInput.parse("24h"), 24 * 3_600)
    }

    func testRoundsToWholeMinutes() {
        XCTAssertEqual(DurationInput.parse("2.4"), 2 * 60)
        XCTAssertEqual(DurationInput.parse("0.25h"), 15 * 60)
    }

    func testRejectsWhatItCannotRead() {
        for text in [
            "", " ", "abc", "5x", "m", "h", "-5", "1:75", "1:2:3", ":30", "1:", "30m 1h", "1h 2h",
            "5m 5m", "1..5", "0", "0m", "0.2", "25h", "1441", "99999999999999999999", "1e9",
            "0s", "0.4s", "30s 1m", "5s 5", "5s 5s", "86401s", "1h 30m 15s 2", "s"
        ] {
            XCTAssertNil(DurationInput.parse(text), "\"\(text)\"")
        }
    }

    func testSecondsInTheirCommonSpellings() {
        for text in ["45s", "45 s", "45sec", "45 secs", "45 seconds", "45S"] {
            XCTAssertEqual(DurationInput.parse(text), 45, text)
        }
        XCTAssertEqual(DurationInput.parse("90s"), 90)
        XCTAssertEqual(DurationInput.parse("1s"), 1)
        XCTAssertEqual(DurationInput.parse("86400s"), 24 * 3_600)
    }

    func testSecondsAfterLargerUnits() {
        for text in ["1m30s", "1m 30s", "1 min 30 sec", "1m30", "1m 30"] {
            XCTAssertEqual(DurationInput.parse(text), 90, text)
        }
        XCTAssertEqual(DurationInput.parse("1h 5s"), 3_605)
        XCTAssertEqual(DurationInput.parse("1h30m15s"), 5_415)
        XCTAssertEqual(DurationInput.parse("1h 30 15"), 5_415)
    }

    func testOnlyALengthWithSecondsKeepsThem() {
        XCTAssertEqual(DurationInput.parse("1.5m"), 2 * 60)
        XCTAssertEqual(DurationInput.parse("1.5m 0s"), 90)
        XCTAssertEqual(DurationInput.parse("0.5m 10s"), 40)
        XCTAssertEqual(DurationInput.parse("2.6s"), 3)
    }

    func testEveryLengthIsShownForEditingInAFormThatReadsBack() {
        for duration: TimeInterval in [1, 45, 60, 90, 25 * 60, 3_600, 3_605, 5_400, 5_415, 86_400] {
            XCTAssertEqual(DurationInput.parse(DurationText.typed(duration)), duration, DurationText.typed(duration))
        }
        XCTAssertEqual(DurationText.typed(90), "1m 30s")
        XCTAssertEqual(DurationText.typed(45), "45s")
        XCTAssertEqual(DurationText.typed(5_400), "1h 30m")
    }

    func testEntryReadsALengthUnlessItNamesATimeOfDay() {
        let now = date(hour: 14, minute: 20, second: 10)

        XCTAssertEqual(entry("25m", now), .length(25 * 60))
        XCTAssertEqual(entry("1:30", now), .length(90 * 60))
        XCTAssertEqual(entry("90s", now), .length(90))
        XCTAssertNil(entry("abc", now))
        XCTAssertNil(entry("", now))
    }

    func testClockTimeWithAmOrPmIsTheNextSuchTime() {
        let now = date(hour: 14, minute: 20, second: 10)

        for text in ["@3:30pm", "@3:30 pm", "at 3:30pm", "until 3:30PM", "@ 3:30pm", "at 15:30", "@15:30"] {
            XCTAssertEqual(entry(text, now), .clockTime(date(hour: 15, minute: 30)), text)
        }
        XCTAssertEqual(entry("@2pm", now), .clockTime(date(day: 9, hour: 14, minute: 0)))
        XCTAssertEqual(entry("@9am", now), .clockTime(date(day: 9, hour: 9, minute: 0)))
        XCTAssertEqual(entry("@12am", now), .clockTime(date(day: 9, hour: 0, minute: 0)))
        XCTAssertEqual(entry("@12pm", now), .clockTime(date(day: 9, hour: 12, minute: 0)))
        XCTAssertEqual(entry("at 0:15", now), .clockTime(date(day: 9, hour: 0, minute: 15)))
    }

    func testClockTimeWithoutAmOrPmIsTheNextTimeTheClockReadsIt() {
        let afternoon = date(hour: 14, minute: 20, second: 10)
        XCTAssertEqual(entry("@4", afternoon), .clockTime(date(hour: 16, minute: 0)))
        XCTAssertEqual(entry("until 2:30", afternoon), .clockTime(date(hour: 14, minute: 30)))
        XCTAssertEqual(entry("@2:20", afternoon), .clockTime(date(day: 9, hour: 2, minute: 20)))
        XCTAssertEqual(entry("@12", afternoon), .clockTime(date(day: 9, hour: 0, minute: 0)))

        let lateEvening = date(hour: 22, minute: 5)
        XCTAssertEqual(entry("at 9", lateEvening), .clockTime(date(day: 9, hour: 9, minute: 0)))
        XCTAssertEqual(entry("at 11", lateEvening), .clockTime(date(hour: 23, minute: 0)))
    }

    func testRejectsTimesOfDayItCannotRead() {
        let now = date(hour: 14, minute: 20, second: 10)

        for text in [
            "@", "at", "at ", "until", "@25", "@24:00", "@13pm", "@0am", "@3:60", "@3:5", "@3:30:15",
            "@3.30", "@pm", "at noon", "@-3", "@3:30 xm", "@3pm 10m"
        ] {
            XCTAssertNil(entry(text, now), "\"\(text)\"")
        }
    }

    func testPresetsAndRoutineTimersCanBeShorterThanAMinuteAndSurviveAReload() {
        let suite = "DragTimerSecondsTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = AppSettings(defaults: defaults)
        let plank = QuickStartPreset(duration: 45, label: "Plank")
        let rest = RoutineTimerDefinition(duration: 90, options: TimerOptions(label: "Rest"))

        settings.setQuickStartPresets([plank])
        XCTAssertTrue(settings.addRoutine(TimerRoutine(name: "Circuit", timers: [rest])))
        let reloaded = AppSettings(defaults: defaults)

        XCTAssertEqual(reloaded.quickStartPresets.map(\.duration), [45])
        XCTAssertEqual(reloaded.quickStartPresets[0].timerTemplate().duration, 45)
        XCTAssertEqual(reloaded.routines[0].timerTemplates.map(\.duration), [90])
        XCTAssertEqual(QuickStartPreset(duration: 0.2).duration, 1)
    }

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func entry(_ text: String, _ now: Date) -> TimerEntry? {
        DurationInput.parseEntry(text, now: now, calendar: calendar)
    }

    private func date(day: Int = 8, hour: Int, minute: Int, second: Int = 0) -> Date {
        calendar.date(from: DateComponents(
            year: 2026, month: 10, day: day, hour: hour, minute: minute, second: second
        ))!
    }
}
