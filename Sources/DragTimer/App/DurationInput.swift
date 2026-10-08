import Foundation

/// Reads a typed timer length: "7", "25m", "1h", "1h30", "1h 30m", "1.5 hr",
/// "90 min", "1:30", "45s" or "1m 30s". A bare number is minutes, or the unit
/// below the part before it. A length with no seconds part is rounded to
/// whole minutes, as it always was; one with a seconds part keeps them. The
/// result is between one second and one day.
enum DurationInput {
    static let range: ClosedRange<TimeInterval> = 1...(24 * 60 * 60)
    /// Room for "1 hour 30 minutes 15 seconds" and little more.
    private static let maximumLength = 40

    private enum Unit: Int {
        case hours, minutes, seconds

        var seconds: Double {
            switch self {
            case .hours: return 3_600
            case .minutes: return 60
            case .seconds: return 1
            }
        }
    }

    static func parse(_ text: String) -> TimeInterval? {
        let input = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty, input.count <= maximumLength else { return nil }

        let clock = input.split(separator: ":", omittingEmptySubsequences: false)
        if clock.count == 2 {
            guard let hours = wholeNumber(clock[0]), let minutes = wholeNumber(clock[1]),
                  minutes < 60 else { return nil }
            return bounded(seconds: (hours * 60 + minutes) * 60, keepsSeconds: false)
        }

        var total = 0.0
        var last: Unit?
        var rest = Substring(input)
        while !rest.isEmpty {
            let digits = rest.prefix { $0.isNumber || $0 == "." }
            guard let value = Double(digits), value.isFinite, value < 100_000 else { return nil }
            rest = rest.dropFirst(digits.count).drop { $0 == " " }
            let name = rest.prefix { $0.isLetter }
            rest = rest.dropFirst(name.count).drop { $0 == " " }

            let unit: Unit
            switch name {
            case "h", "hr", "hrs", "hour", "hours": unit = .hours
            case "m", "min", "mins", "minute", "minutes": unit = .minutes
            case "s", "sec", "secs", "second", "seconds": unit = .seconds
            case "":
                // "1h30" is an hour and thirty minutes; "1m30" a minute and
                // thirty seconds; "30" by itself is thirty minutes.
                guard let below = Unit(rawValue: (last?.rawValue ?? Unit.hours.rawValue) + 1) else { return nil }
                unit = below
            default:
                return nil
            }
            // Largest unit first, each at most once.
            if let last, unit.rawValue <= last.rawValue { return nil }
            last = unit
            total += value * unit.seconds
        }
        return bounded(seconds: total, keepsSeconds: last == .seconds)
    }

    private static func wholeNumber(_ text: Substring) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed.count <= 4, trimmed.allSatisfy(\.isNumber) else { return nil }
        return Double(trimmed)
    }

    private static func bounded(seconds: Double, keepsSeconds: Bool) -> TimeInterval? {
        let duration = keepsSeconds ? seconds.rounded() : (seconds / 60).rounded() * 60
        return range.contains(duration) ? duration : nil
    }
}

/// What the popover's typed entry can ask for.
enum TimerEntry: Equatable {
    case length(TimeInterval)
    /// Ring at this time of day.
    case clockTime(Date)

    /// What the button that starts it says. A time that has already passed
    /// today is tomorrow's, and says so.
    func startTitle(now: Date = Date(), calendar: Calendar = .current) -> String {
        switch self {
        case let .length(duration):
            return "Start \(DurationText.planned(duration))"
        case let .clockTime(date):
            let time = TimerDateText.fireTime(for: date)
            return calendar.isDate(date, inSameDayAs: now) ? "Ring at \(time)" : "Ring tomorrow at \(time)"
        }
    }
}

extension DurationInput {
    /// A length as `parse` reads it, or a time of day after "@", "at" or
    /// "until": "@3:30pm", "at 15:30", "until 4". A time from 1 to 12 with no
    /// am or pm means the next time the clock reads it.
    static func parseEntry(
        _ text: String,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> TimerEntry? {
        let input = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard input.count <= maximumLength else { return nil }
        for prefix in ["@", "at", "until"] where input.hasPrefix(prefix) {
            let time = input.dropFirst(prefix.count).trimmingCharacters(in: .whitespaces)
            return clockTime(time, now: now, calendar: calendar).map(TimerEntry.clockTime)
        }
        return parse(text).map(TimerEntry.length)
    }

    private static func clockTime(_ text: String, now: Date, calendar: Calendar) -> Date? {
        var body = text
        var isAfternoon: Bool?
        for (suffix, afternoon) in [("am", false), ("pm", true)] where body.hasSuffix(suffix) {
            isAfternoon = afternoon
            body = String(body.dropLast(suffix.count)).trimmingCharacters(in: .whitespaces)
        }
        let parts = body.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count <= 2, let hour = parts.first.flatMap(wholeNumber).map({ Int($0) }) else { return nil }
        var minute = 0
        if parts.count == 2 {
            let digits = parts[1].trimmingCharacters(in: .whitespaces)
            guard digits.count == 2, let value = wholeNumber(Substring(digits)), value < 60 else { return nil }
            minute = Int(value)
        }

        let hours: [Int]
        if let isAfternoon {
            guard (1...12).contains(hour) else { return nil }
            hours = [hour % 12 + (isAfternoon ? 12 : 0)]
        } else if (1...12).contains(hour) {
            hours = [hour % 12, hour % 12 + 12]
        } else {
            guard (0...23).contains(hour) else { return nil }
            hours = [hour]
        }

        // Strict, so that on the night the clocks go forward a time that
        // does not exist is not quietly moved to one that does.
        let next = hours.compactMap { hour in
            calendar.nextDate(
                after: now,
                matching: DateComponents(hour: hour, minute: minute, second: 0),
                matchingPolicy: .strict
            )
        }.min()
        // Longer than a day only when the clocks go back; a timer cannot be.
        guard let next, next.timeIntervalSince(now) <= range.upperBound else { return nil }
        return next
    }
}
