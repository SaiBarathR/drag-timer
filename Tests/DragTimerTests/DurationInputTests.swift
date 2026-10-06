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
            "5m 5m", "1..5", "0", "0m", "0.2", "25h", "1441", "99999999999999999999", "1e9"
        ] {
            XCTAssertNil(DurationInput.parse(text), "\"\(text)\"")
        }
    }
}
